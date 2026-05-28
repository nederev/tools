local M = {}

local config = {
  targetName = nil,
  targetIdentifier = nil,
  displayNames = { "Sidecar Display" },
  helperPath = os.getenv("HOME") .. "/.hammerspoon/bin/sidecarctl",
  logPath = os.getenv("HOME") .. "/.hammerspoon/sidecar-reconnector.log",
  retryDelays = { 8, 15, 30 },
  hotkeys = {
    reconnect = { modifiers = { "ctrl", "alt", "cmd" }, key = "u" },
    debug = { modifiers = { "ctrl", "alt", "cmd" }, key = "d" },
  },
}

local timers = {}

local function mergeTable(base, override)
  if type(override) ~= "table" then
    return base
  end

  for key, value in pairs(override) do
    if type(value) == "table" and type(base[key]) == "table" then
      mergeTable(base[key], value)
    else
      base[key] = value
    end
  end

  return base
end

local function timestamp()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function log(message)
  local line = timestamp() .. " " .. tostring(message)
  print(line)

  local file = io.open(config.logPath, "a")
  if file then
    file:write(line .. "\n")
    file:close()
  end
end

local function containsIgnoreCase(value, needle)
  if not value or not needle or needle == "" then
    return false
  end

  return value:lower():find(needle:lower(), 1, true) ~= nil
end

local function shellQuote(value)
  value = tostring(value or "")
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function targetArgs()
  local args = {}

  if config.targetName and config.targetName ~= "" then
    table.insert(args, "--name")
    table.insert(args, shellQuote(config.targetName))
  end

  if config.targetIdentifier and config.targetIdentifier ~= "" then
    table.insert(args, "--id")
    table.insert(args, shellQuote(config.targetIdentifier))
  end

  return table.concat(args, " ")
end

local function hasTargetConfig()
  return (config.targetName and config.targetName ~= "") or
    (config.targetIdentifier and config.targetIdentifier ~= "")
end

function M.dumpDisplays()
  log("--- display dump start ---")

  for index, screen in ipairs(hs.screen.allScreens()) do
    local frame = screen:frame()
    local fullFrame = screen:fullFrame()
    log(string.format(
      "hs.screen[%d] name=%s id=%s frame=%dx%d+%d+%d full=%dx%d+%d+%d",
      index,
      screen:name() or "<nil>",
      tostring(screen:id()),
      frame.w,
      frame.h,
      frame.x,
      frame.y,
      fullFrame.w,
      fullFrame.h,
      fullFrame.x,
      fullFrame.y
    ))
  end

  local profiler = hs.execute("/usr/sbin/system_profiler SPDisplaysDataType 2>/dev/null", true) or ""
  log("system_profiler SPDisplaysDataType:\n" .. profiler)
  log("--- display dump end ---")
end

function M.isConnected()
  local names = {}
  for _, name in ipairs(config.displayNames or {}) do
    table.insert(names, name)
  end
  if config.targetName then
    table.insert(names, config.targetName)
  end

  for _, screen in ipairs(hs.screen.allScreens()) do
    local screenName = screen:name() or ""

    for _, candidateName in ipairs(names) do
      if containsIgnoreCase(screenName, candidateName) then
        return true, "hs.screen: " .. screenName
      end
    end
  end

  local output = hs.execute("/usr/sbin/system_profiler SPDisplaysDataType 2>/dev/null", true) or ""
  for _, candidateName in ipairs(names) do
    if containsIgnoreCase(output, candidateName) then
      return true, "system_profiler"
    end
  end

  return false, "not listed as display"
end

function M.runReconnect(reason)
  if not hasTargetConfig() then
    log("runReconnect refused: targetName or targetIdentifier is required")
    hs.alert.show("Sidecar target not configured")
    return false
  end

  local connected, detail = M.isConnected()
  log("runReconnect reason=" .. tostring(reason) .. " connected=" .. tostring(connected) .. " detail=" .. tostring(detail))

  if connected then
    hs.alert.show("Sidecar already connected")
    return true
  end

  local command = shellQuote(config.helperPath) .. " connect " .. targetArgs() .. " 2>&1"
  local output, ok, kind, status = hs.execute(command, true)
  log("helper ok=" .. tostring(ok) .. " kind=" .. tostring(kind) .. " status=" .. tostring(status) .. " output=" .. tostring(output))

  if ok then
    hs.alert.show("Sidecar reconnect requested")
  else
    hs.alert.show("Sidecar reconnect failed")
  end

  hs.timer.doAfter(4, function()
    local postConnected, postDetail = M.isConnected()
    log("post-reconnect connected=" .. tostring(postConnected) .. " detail=" .. tostring(postDetail))
  end)

  return ok
end

local function stopTimers()
  for _, timer in ipairs(timers) do
    timer:stop()
  end
  timers = {}
end

function M.ensureConnected(reason)
  if not hasTargetConfig() then
    log("ensureConnected refused: targetName or targetIdentifier is required")
    return false
  end

  local connected, detail = M.isConnected()
  log("ensureConnected reason=" .. tostring(reason) .. " connected=" .. tostring(connected) .. " detail=" .. tostring(detail))

  if connected then
    return true
  end

  stopTimers()
  for _, delay in ipairs(config.retryDelays or {}) do
    table.insert(timers, hs.timer.doAfter(delay, function()
      M.runReconnect(reason .. " retry +" .. tostring(delay) .. "s")
    end))
  end

  return false
end

function M.setup(userConfig)
  mergeTable(config, userConfig or {})

  if not config.targetName and not config.targetIdentifier then
    log("Sidecar Reconnector loaded without targetName or targetIdentifier.")
  end

  M.watcher = hs.caffeinate.watcher.new(function(event)
    log("caffeinate event=" .. tostring(event))
    if event == hs.caffeinate.watcher.systemDidWake then
      M.ensureConnected("system wake")
    elseif event == hs.caffeinate.watcher.screensDidWake then
      M.ensureConnected("screens wake")
    elseif event == hs.caffeinate.watcher.sessionDidBecomeActive then
      M.ensureConnected("unlock")
    end
  end)
  M.watcher:start()

  if config.hotkeys and config.hotkeys.reconnect then
    hs.hotkey.bind(config.hotkeys.reconnect.modifiers, config.hotkeys.reconnect.key, function()
      M.runReconnect("manual hotkey")
    end)
  end

  if config.hotkeys and config.hotkeys.debug then
    hs.hotkey.bind(config.hotkeys.debug.modifiers, config.hotkeys.debug.key, function()
      M.dumpDisplays()
    end)
  end

  SidecarReconnector = M
  log("Sidecar Reconnector loaded. helper=" .. tostring(config.helperPath))
  return M
end

return M
