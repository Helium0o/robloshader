--!nocheck
-- Headless run of Bubble Shaders against the real place, with Lune:
--   lune run tests/simulate <place.rbxl>
-- Loads the place, mirrors its instances into a small mock engine (properties, signals, tags, attributes,
-- a task scheduler and a fake server clock), runs the server script and the client script from src/, then plays
-- a whole day cycle with cars driving at night, a boost, the customs camera, an admin time change and a frame
-- rate drop - checking the results on the way. Not Roblox itself, but it runs every line of our code against
-- the place's real hierarchy, names, colours and lights.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Color3, Vector3, CFrame, Enum = roblox.Color3, roblox.Vector3, roblox.CFrame, roblox.Enum
local db = roblox.getReflectionDatabase()

local placePath = process.args[1] or "place.rbxl"
local SRC = "src"

----------------------------------------------------------------- signals
local Signal = {}
Signal.__index = Signal
function Signal.new() return setmetatable({conns = {}}, Signal) end
function Signal:Connect(fn)
  local c = {fn = fn, Connected = true}
  function c.Disconnect() c.Connected = false end
  table.insert(self.conns, c)
  return c
end
function Signal:Fire(...)
  for _, c in ipairs(table.clone(self.conns)) do if c.Connected then c.fn(...) end end
end

----------------------------------------------------------------- scheduler (task.*) on a fake clock
local now = 0
local sleeping = {}
local function resume(co, ...)
  local ok, err = coroutine.resume(co, ...)
  if not ok then error(debug.traceback(co, tostring(err)), 0) end
end
local task = {}
function task.spawn(fn, ...)
  local co = type(fn) == "thread" and fn or coroutine.create(fn)
  resume(co, ...)
  return co
end
task.defer = task.spawn
function task.wait(t)
  local co = coroutine.running()
  table.insert(sleeping, {co = co, at = now + (t or 0)})
  coroutine.yield()
  return t or 0
end
local function runSleepers()
  local due = {}
  for i = #sleeping, 1, -1 do
    if sleeping[i].at <= now then table.insert(due, table.remove(sleeping, i)) end
  end
  for _, s in ipairs(due) do resume(s.co) end
end

----------------------------------------------------------------- mock instances
local Inst = {}
local Methods = {}
local EVENTS = {ChildAdded = true, ChildRemoved = true, DescendantAdded = true, DescendantRemoving = true, Changed = true,
  Activated = true, Event = true, InputBegan = true, WindowFocused = true, WindowFocusReleased = true,
  RenderStepped = true, Heartbeat = true, Seated = true, Died = true, CharacterAdded = true}
local DEFAULTS = {Enabled = true, Shadows = false, Transparency = 0, Brightness = 1, Range = 8}
local tagAdded, tagRemoved = {}, {}
local function tagSignal(map, tag) map[tag] = map[tag] or Signal.new(); return map[tag] end

local superCache = {}
local function isA(class, target)
  local key = class .. ">" .. target
  if superCache[key] ~= nil then return superCache[key] end
  local c, r = class, false
  while c do
    if c == target then r = true; break end
    local info = db:GetClass(c)
    c = info and info.Superclass or nil
  end
  superCache[key] = r
  return r
end

local function new(class)
  local o = {__class = class, __props = {Name = class}, __children = {}, __attrs = {}, __tags = {}, __psig = {}, __asig = {}, __ev = {}}
  return setmetatable(o, Inst)
end

Inst.__index = function(self, k)
  local m = Methods[k]
  if m then return m end
  if k == "Parent" then return rawget(self, "__parent") end
  if k == "ClassName" then return self.__class end
  if EVENTS[k] then
    local s = self.__ev[k]
    if not s then s = Signal.new(); self.__ev[k] = s end
    return s
  end
  local v = self.__props[k]
  if v ~= nil then return v end
  if k == "Position" and self.__props.CFrame then return self.__props.CFrame.Position end
  if DEFAULTS[k] ~= nil then return DEFAULTS[k] end
  for _, c in ipairs(self.__children) do if c.__props.Name == k then return c end end
  return nil
end
Inst.__tostring = function(self) return self.__props.Name end

local function inGame(o)
  local p = o
  while p do
    if p.__class == "DataModel" then return true end
    p = rawget(p, "__parent")
  end
  return false
end
local function eachDesc(o, fn)
  for _, c in ipairs(o.__children) do fn(c); eachDesc(c, fn) end
end
local function fireTags(o, map)
  local function one(x) for t in pairs(x.__tags) do if map[t] then map[t]:Fire(x) end end end
  one(o)
  eachDesc(o, one)
end

Inst.__newindex = function(self, k, v)
  if k == "Parent" then
    if rawget(self, "__destroyed") then error("The Parent property of " .. tostring(self) .. " is locked") end
    local old = rawget(self, "__parent")
    if old == v then return end
    if old then
      local wasIn = inGame(old)
      local a = old
      while a do
        a.DescendantRemoving:Fire(self)
        a = rawget(a, "__parent")
      end
      local i = table.find(old.__children, self)
      if i then table.remove(old.__children, i) end
      rawset(self, "__parent", nil)
      old.ChildRemoved:Fire(self)
      if wasIn then fireTags(self, tagRemoved) end
    end
    if v then
      rawset(self, "__parent", v)
      table.insert(v.__children, self)
      v.ChildAdded:Fire(self)
      local a = v
      while a do
        a.DescendantAdded:Fire(self)
        eachDesc(self, function(d) a.DescendantAdded:Fire(d) end)
        a = rawget(a, "__parent")
      end
      if inGame(v) then fireTags(self, tagAdded) end
    end
    return
  end
  local old = self.__props[k]
  self.__props[k] = v
  if old ~= v then
    if self.__psig[k] then self.__psig[k]:Fire() end
    if self.__ev.Changed then self.__ev.Changed:Fire(k) end
  end
end

function Methods.IsA(self, c) return isA(self.__class, c) end
function Methods.FindFirstChild(self, name, recursive)
  for _, c in ipairs(self.__children) do if c.__props.Name == name then return c end end
  if recursive then
    for _, c in ipairs(self.__children) do
      local f = c:FindFirstChild(name, true)
      if f then return f end
    end
  end
  return nil
end
function Methods.WaitForChild(self, name, timeout)
  local c = self:FindFirstChild(name)
  local waited = 0
  while not c do
    if timeout and waited >= timeout then return nil end
    if not coroutine.isyieldable() then error("WaitForChild(" .. name .. ") would wait forever on " .. tostring(self)) end
    task.wait(0.1)
    waited += 0.1
    c = self:FindFirstChild(name)
  end
  return c
end
function Methods.FindFirstChildOfClass(self, cls)
  for _, c in ipairs(self.__children) do if c.__class == cls then return c end end
  return nil
end
function Methods.FindFirstChildWhichIsA(self, cls)
  for _, c in ipairs(self.__children) do if c:IsA(cls) then return c end end
  return nil
end
function Methods.GetChildren(self) return table.clone(self.__children) end
function Methods.GetDescendants(self)
  local out = {}
  eachDesc(self, function(d) table.insert(out, d) end)
  return out
end
function Methods.GetAttribute(self, k) return self.__attrs[k] end
function Methods.GetAttributes(self) return table.clone(self.__attrs) end
function Methods.SetAttribute(self, k, v)
  local old = self.__attrs[k]
  self.__attrs[k] = v
  if old ~= v and self.__asig[k] then self.__asig[k]:Fire() end
end
function Methods.GetAttributeChangedSignal(self, k)
  self.__asig[k] = self.__asig[k] or Signal.new()
  return self.__asig[k]
end
function Methods.GetPropertyChangedSignal(self, k)
  self.__psig[k] = self.__psig[k] or Signal.new()
  return self.__psig[k]
end
function Methods.Destroy(self)
  self.Parent = nil
  rawset(self, "__destroyed", true)
  for _, c in ipairs(table.clone(self.__children)) do c:Destroy() end
end
function Methods.GetPivot(self)
  if self.__props.CFrame then return self.__props.CFrame end
  local pp = self.__props.PrimaryPart
  if pp then return pp.CFrame end
  for _, d in ipairs(self:GetDescendants()) do if d:IsA("BasePart") then return d.CFrame end end
  return CFrame.new()
end
function Methods.Fire(self, ...) self.Event:Fire(...) end
function Methods.AddTag(self, t) self.__tags[t] = true end
function Methods.HasTag(self, t) return self.__tags[t] == true end
function Methods.Connect() error("Connect called on an Instance") end

local Instance = {new = function(class, parent)
  local o = new(class)
  if parent then o.Parent = parent end
  return o
end}

----------------------------------------------------------------- mirror the place
print("loading " .. placePath)
local real = roblox.deserializePlace(fs.readFile(placePath))
local COPY = {"CFrame", "Size", "Color", "Material", "Shape", "Transparency", "Anchored", "Enabled", "Shadows", "Brightness",
  "Range", "Angle", "Face", "Source", "Density", "Offset", "Decay", "Glare", "Haze", "Intensity", "Threshold", "Spread",
  "Ambient", "OutdoorAmbient", "FarIntensity", "NearIntensity", "FocusDistance", "InFocusRadius", "ExposureCompensation"}
local count = 0
local function mirror(r, parent)
  local o = new(r.ClassName)
  o.__props.Name = r.Name
  for _, k in ipairs(COPY) do
    local ok, v = pcall(function() return r[k] end)
    if ok and v ~= nil then o.__props[k] = v end
  end
  for k, v in pairs(r:GetAttributes()) do o.__attrs[k] = v end
  for _, t in ipairs(r:GetTags()) do o.__tags[t] = true end
  rawset(o, "__parent", parent)
  if parent then table.insert(parent.__children, o) end
  count += 1
  for _, c in ipairs(r:GetChildren()) do mirror(c, o) end
  return o
end
local game = new("DataModel")
game.__props.Name = "Game"
for _, svc in ipairs(real:GetChildren()) do mirror(svc, game) end
print(string.format("mirrored %d instances", count))

local function service(name)
  local s = game:FindFirstChildOfClass(name)
  if not s then s = new(name); s.__props.Name = name; s.Parent = game end
  return s
end
local workspace = service("Workspace")
local Lighting = service("Lighting")
local RS = service("ReplicatedStorage")
local SSS = service("ServerScriptService")
Lighting.__props.ClockTime = 14.5
workspace.CurrentCamera = workspace:FindFirstChildOfClass("Camera") or Instance.new("Camera", workspace)
workspace.CurrentCamera.__props.CFrame = CFrame.new(170, 12, -20)
function Methods.GetServerTimeNow() return 1_000_000 + now end

-- services the mock provides by hand
local CollectionService = new("CollectionService")
-- (rawset: these must not go through the mock's own Instance:AddTag)
rawset(CollectionService, "AddTag", function(_, inst, tag)
  if inst.__tags[tag] then return end
  inst.__tags[tag] = true
  if inGame(inst) and tagAdded[tag] then tagAdded[tag]:Fire(inst) end
end)
rawset(CollectionService, "GetTagged", function(_, tag)
  local out = {}
  eachDesc(game, function(d) if d.__tags[tag] then table.insert(out, d) end end)
  return out
end)
rawset(CollectionService, "GetInstanceAddedSignal", function(_, tag) return tagSignal(tagAdded, tag) end)
rawset(CollectionService, "GetInstanceRemovedSignal", function(_, tag) return tagSignal(tagRemoved, tag) end)

local RunService = new("RunService")
local UIS = new("UserInputService")
UIS.__props.TouchEnabled, UIS.__props.KeyboardEnabled = false, true
local Players = service("Players")
local player = new("Player")
player.__props.Name = "Tester"
player.Parent = Players
Players.__props.LocalPlayer = player
local playerGui = Instance.new("PlayerGui", player)
playerGui.__props.Name = "PlayerGui"
local character = Instance.new("Model", workspace)
character.__props.Name = "Tester"
local humanoid = Instance.new("Humanoid", character)
player.__props.Character = character

local ugs = new("UserGameSettings")
ugs.__props.SavedQualityLevel = Enum.SavedQualitySetting.Automatic
local function UserSettings() return {GetService = function() return ugs end} end

local services = {CollectionService = CollectionService, RunService = RunService, UserInputService = UIS}
function Methods.GetService(self, name)
  if self.__class ~= "DataModel" then error("GetService on " .. self.__class) end
  return services[name] or service(name)
end

-- the server has its own Lighting: what it writes reaches the client like replication would (attributes, ClockTime),
-- what the client writes stays on the client
local serverLighting = new("Lighting")
serverLighting.__props.Name = "Lighting"
serverLighting.__props.ClockTime = 14.5
rawset(serverLighting, "SetAttribute", function(self, k, v)
  Methods.SetAttribute(self, k, v)
  Lighting:SetAttribute(k, v)
end)
serverLighting:GetPropertyChangedSignal("ClockTime"):Connect(function() Lighting.ClockTime = serverLighting.ClockTime end)
local serverGame = {GetService = function(_, name)
  if name == "Lighting" then return serverLighting end
  return game:GetService(name)
end}

----------------------------------------------------------------- install our scripts
local function readSrc(path) return fs.readFile(path) end
local function scriptFrom(path, class, name, parent)
  local s = Instance.new(class)
  s.__props.Name = name
  s.__props.Source = readSrc(path)
  s.__props.__file = path
  s.Parent = parent
  return s
end
-- (a place built with tools/build already has them: replace those with the current src)
local SPS0 = service("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
for _, pair in ipairs({{RS, "BubbleShaders"}, {SSS, "BubbleShadersServer"}, {SPS0, "BubbleShadersClient"}}) do
  local old = pair[1]:FindFirstChild(pair[2])
  if old then old:Destroy() end
end
local shared = Instance.new("Folder", RS)
shared.__props.Name = "BubbleShaders"
for _, n in ipairs({"Config", "Looks", "Clock", "Blend"}) do
  scriptFrom(SRC .. "/shared/BubbleShaders/" .. n .. ".luau", "ModuleScript", n, shared)
end
local serverScript = scriptFrom(SRC .. "/server/BubbleShadersServer.server.luau", "Script", "BubbleShadersServer", SSS)
local SPS = service("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local clientScript = scriptFrom(SRC .. "/client/BubbleShadersClient/init.client.luau", "LocalScript", "BubbleShadersClient", SPS)
for _, n in ipairs({"Quality", "PostFx", "CarLightLod", "NightLights", "GraphicsMenu"}) do
  scriptFrom(SRC .. "/client/BubbleShadersClient/" .. n .. ".luau", "ModuleScript", n, clientScript)
end

local loaded = {}
local env
local function run(s, gameOverride)
  local e = table.clone(env)                -- raw fields: Lune only injects the globals that are missing
  e.script = s
  if gameOverride then e.game = gameOverride end
  local fn = luau.load(s.Source, {debugName = s.__props.__file or s.Name, environment = e})
  return fn()
end
local function requireModule(m)
  if loaded[m] == nil then loaded[m] = run(m) end
  return loaded[m]
end
env = {
  game = game, workspace = workspace, Instance = Instance, Enum = Enum, Color3 = Color3, Vector3 = Vector3,
  CFrame = CFrame, UDim = roblox.UDim, UDim2 = roblox.UDim2, Vector2 = roblox.Vector2, task = task,
  require = requireModule, UserSettings = UserSettings, warn = function(...) print("WARN", ...) end,
  typeof = typeof, print = print, math = math, table = table, string = string, os = {clock = function() return now end},
  pcall = pcall, ipairs = ipairs, pairs = pairs, type = type, tostring = tostring, tonumber = tonumber,
  setmetatable = setmetatable, coroutine = coroutine, bit32 = bit32, select = select, error = error,
}

----------------------------------------------------------------- checks
local failures = 0
local function check(ok, msg)
  print((ok and "  ok   " or "  FAIL ") .. msg)
  if not ok then failures += 1 end
end
local function countTag(t) return #CollectionService:GetTagged(t) end

print("\n== server")
task.spawn(run, serverScript, serverGame)
check(countTag("BubbleWindow") > 1000, "windows tagged: " .. countTag("BubbleWindow"))
check(countTag("BubblePorchLamp") >= 150, "porch lamps tagged: " .. countTag("BubblePorchLamp"))
check(countTag("BubbleTailLamp") >= 100, "traffic tail lamps tagged: " .. countTag("BubbleTailLamp"))
check(countTag("BubbleTrafficCar") >= 50, "traffic cars tagged: " .. countTag("BubbleTrafficCar"))
check(countTag("BubbleStreetLight") >= 8, "street lights tagged: " .. countTag("BubbleStreetLight"))
check(type(Lighting:GetAttribute("BubbleClockOrigin")) == "number", "clock anchored on Lighting")

print("\n== client")
task.spawn(run, clientScript)
local Config = requireModule(shared.Config)
local folder = workspace.BubblegumTown.DriveableCars
local hum = humanoid
local cars = folder:GetChildren()
check(#cars >= 10, "driveable cars found: " .. #cars)
check(playerGui:FindFirstChild("BubbleGraphicsGui") ~= nil, "graphics menu built")
check(Lighting:FindFirstChild("BubbleGrade") ~= nil, "colour grade added")

local frameDt = 1 / 60
local function frames(seconds, dt)
  dt = dt or frameDt
  for _ = 1, math.floor(seconds / dt + 0.5) do
    now += dt
    runSleepers()
    RunService.RenderStepped:Fire(dt)
  end
end
local function hourNow() return Lighting.ClockTime end
local function neonCount(tag)
  local n = 0
  for _, p in ipairs(CollectionService:GetTagged(tag)) do if p.Material == Enum.Material.Neon then n += 1 end end
  return n
end
local function shadowLights()
  local on, total = 0, 0
  for _, d in ipairs(folder:GetDescendants()) do
    if d:IsA("Light") then total += 1; if d.Shadows then on += 1 end end
  end
  return on, total
end
local function lights(class, name)
  local n = 0
  eachDesc(workspace, function(d) if d.__class == class and (not name or d.__props.Name == name) and d.Parent then n += 1 end end)
  return n
end

-- the server turns every car's lights on with shadows (like DriveableCarServer.setCarLights)
for i, car in ipairs(cars) do
  if i <= 12 then
    car:SetAttribute("LightsOn", true)
    for _, d in ipairs(car:GetDescendants()) do if d:IsA("Light") then d.Shadows = true end end
  end
end
-- we drive the R34
local r34 = folder:FindFirstChild("R34")
hum.SeatPart = r34 and r34:FindFirstChild("DriveSeat")
workspace.CurrentCamera.__props.CFrame = CFrame.new(150, 8, -40)

print("\n== a whole day (" .. Config.DayCycle.Minutes .. " min)")
local rows = {}
local lastHour = hourNow()
local wrapped = 0
for step = 1, Config.DayCycle.Minutes * 60 do
  frames(1)
  local h = hourNow()
  if h < lastHour - 12 then wrapped += 1 end
  lastHour = h
  if step % 60 == 0 then
    local on, total = shadowLights()
    table.insert(rows, string.format("  %5.2f h  bright %.2f  exp %.2f  bloom %.2f/%.2f  windows %4d  porch %3d  tails %3d  beams %2d  porchLights %2d  shadows %2d/%d",
      h, Lighting.Brightness, Lighting.ExposureCompensation, Lighting.Bloom.Intensity, Lighting.Bloom.Threshold,
      neonCount("BubbleWindow"), neonCount("BubblePorchLamp"), neonCount("BubbleTailLamp"),
      lights("SpotLight", nil) - lights("SpotLight", "HeadBeam") - lights("SpotLight", "BrakeBeam") - lights("SpotLight", "ReverseBeam"),
      lights("PointLight", nil) - lights("PointLight", "PopLight") - 8, on, total))
  end
end
for _, r in ipairs(rows) do print(r) end
check(wrapped == 1, "clock went round exactly once in one cycle")

-- at night
serverLighting.ClockTime = 23           -- admin "time 23" (server side)
frames(2)
check(math.abs(hourNow() - 23) < 0.1, string.format("admin time change followed: %.3f", hourNow()))
local nightWindows = neonCount("BubbleWindow")
local total = countTag("BubbleWindow")
check(nightWindows > total * 0.5 and nightWindows < total * 0.85, string.format("night: %d of %d windows lit", nightWindows, total))
check(neonCount("BubblePorchLamp") == countTag("BubblePorchLamp"), "night: every porch lamp on")
local on, all = shadowLights()
check(on > 0 and on < all, string.format("night: %d of %d car lights cast shadows", on, all))
local myOn, myAll = 0, 0
for _, d in ipairs(r34:GetDescendants()) do if d:IsA("Light") then myAll += 1; if d.Shadows then myOn += 1 end end end
check(myOn > 0, string.format("own car keeps shadows (%d of %d lights)", myOn, myAll))
check(Lighting.Bloom.Enabled and Lighting.SunRays.Enabled == false, "night: bloom on, sun rays off")

-- standing by a house at night: the nearest porch lamps get real lights (pooled, never more than the tier allows)
local lamp = CollectionService:GetTagged("BubblePorchLamp")[1]
workspace.CurrentCamera.__props.CFrame = CFrame.new(lamp.Position + Vector3.new(10, 6, 10))
frames(1)
local porchLights = 0
for _, l in ipairs(CollectionService:GetTagged("BubblePorchLamp")) do
  if l:FindFirstChildOfClass("PointLight") then porchLights += 1 end
end
check(porchLights > 0 and porchLights <= Config.Tiers.High.porchLights, "by a house at night: " .. porchLights .. " porch lamps cast real light")
workspace.CurrentCamera.__props.CFrame = CFrame.new(150, 8, -40)
frames(1)

-- the server sets Shadows back on (brake light) on a far car: the client puts it right again
local far
for _, car in ipairs(cars) do
  if car ~= r34 and car:GetAttribute("LightsOn") and (car:GetPivot().Position - Vector3.new(150, 8, -40)).Magnitude > 300 then far = car end
end
if far then
  local l
  for _, d in ipairs(far:GetDescendants()) do if d:IsA("Light") then l = d end end
  l.Shadows = true
  check(l.Shadows == false, "far car's light shadow switched back off after the server turned it on")
end

-- daytime
serverLighting.ClockTime = 12
frames(2)
check(neonCount("BubbleWindow") == 0, "noon: no windows lit")
local dOn = shadowLights()
check(dOn <= myAll, "noon: only own car keeps light shadows (" .. dOn .. ")")
check(Lighting.SunRays.Enabled, "noon: sun rays on (High)")

-- boost
local flame
for _, d in ipairs(r34:GetDescendants()) do if d:IsA("ParticleEmitter") and d.Name == "BoostFlame" then flame = d end end
if not flame then
  local att = Instance.new("Attachment", r34.Chassis); att.__props.Name = "Exhaust"
  flame = Instance.new("ParticleEmitter", att); flame.__props.Name = "BoostFlame"
end
local sat0 = Lighting.BubbleGrade.Saturation
flame.Enabled = true
frames(1.1)
check(Lighting.BubbleGrade.Saturation > sat0 + 0.05, string.format("boost: saturation %.3f -> %.3f", sat0, Lighting.BubbleGrade.Saturation))
flame.Enabled = false
frames(3)
check(math.abs(Lighting.BubbleGrade.Saturation - sat0) < 0.01, "boost: back to normal after")

-- customs camera
player:SetAttribute("InCustoms", true)
frames(2)
check(Lighting.DepthOfField.Enabled, string.format("customs: depth of field on, focus %.1f", Lighting.DepthOfField.FocusDistance))
player:SetAttribute("InCustoms", nil)
frames(3)
check(not Lighting.DepthOfField.Enabled, "customs: depth of field off after")

-- the sky track zone
workspace.CurrentCamera.__props.CFrame = CFrame.new(120, 510, 5400)
local dens0 = Lighting.Atmosphere.Density
frames(4)
check(Lighting.Atmosphere.Density < dens0, string.format("sky track: clearer air %.3f -> %.3f", dens0, Lighting.Atmosphere.Density))
workspace.CurrentCamera.__props.CFrame = CFrame.new(150, 8, -40)

-- a slow device: Auto steps down to Medium and stays there
local gui = playerGui.BubbleGraphicsGui
local function tierShown() return Lighting.SunRays.Enabled and "High+" or "Medium-" end
frames(15, 1 / 25)
check(tierShown() == "Medium-", "25 fps: Auto dropped below High (sun rays off)")
frames(40, 1 / 60)
check(tierShown() == "Medium-", "60 fps again: Auto doesn't flip-flop back up")
check(gui ~= nil, "menu still there")

print(string.format("\n%d failure(s)", failures))
process.exit(failures == 0 and 0 or 1)
