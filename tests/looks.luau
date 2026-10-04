--!nocheck
-- Quick checks of the shared modules, no place needed:
--   lune run tests/looks
-- The clock maths round-trips, every look has every key, every value is inside the range Roblox accepts,
-- and the config's tiers / zones are complete.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local env = {Color3 = roblox.Color3, Vector3 = roblox.Vector3, Enum = roblox.Enum}
local function load(name)
  local src = fs.readFile("src/shared/BubbleShaders/" .. name .. ".luau")
  return luau.load(src, {debugName = name, environment = table.clone(env)})()
end
local Config, Looks, Clock, Blend = load("Config"), load("Looks"), load("Clock"), load("Blend")

local failures = 0
local function check(ok, msg)
  if not ok then failures += 1; print("  FAIL " .. msg) end
end

-- clock
local curve = Config.DayCurve
check(curve[1][1] == 0 and curve[#curve][1] == 1, "day curve runs from share 0 to 1")
check(math.abs(curve[#curve][2] - curve[1][2] - 24) < 1e-9, "day curve covers exactly 24 hours")
for i = 2, #curve do check(curve[i][1] > curve[i - 1][1] and curve[i][2] > curve[i - 1][2], "day curve rises at " .. i) end
for h = 0, 23.99, 0.05 do
  local back = Clock.hourAt(curve, Clock.shareAt(curve, h))
  check(math.abs(back - h) < 1e-6 or math.abs(math.abs(back - h) - 24) < 1e-6, string.format("clock round trip at %.2f -> %.4f", h, back))
end
local fake = {attrs = {}}
function fake:GetAttribute(k) return self.attrs[k] end
fake.attrs[Clock.ATTR_SHARE], fake.attrs[Clock.ATTR_ORIGIN], fake.attrs[Clock.ATTR_LENGTH] = Clock.shareAt(curve, 12), 100, 0
check(math.abs(Clock.read(fake, curve, 5000) - 12) < 1e-6, "frozen clock stays put")
fake.attrs[Clock.ATTR_LENGTH] = 1200
check(math.abs(Clock.read(fake, curve, 100 + 1200) - 12) < 1e-6, "one cycle later it's the same time")
check(Clock.read({GetAttribute = function() return nil end}, curve, 0) == nil, "no anchor -> nil")

-- looks
local RANGES = {
  Brightness = {0, 10}, Exposure = {-3, 3}, EnvDiffuse = {0, 1}, EnvSpecular = {0, 1}, ShadowSoftness = {0, 1},
  AtmDensity = {0, 1}, AtmOffset = {0, 1}, AtmGlare = {0, 10}, AtmHaze = {0, 10},
  GradeBrightness = {-1, 1}, GradeContrast = {-1, 1}, GradeSaturation = {-1, 1},
  BloomIntensity = {0, 1}, BloomSize = {0, 56}, BloomThreshold = {0.8, 4},
  RaysIntensity = {0, 1}, RaysSpread = {0, 1}, DofFar = {0, 1}, DofNear = {0, 1}, DofRadius = {0, 50}, Night = {0, 1},
}
for i, f in ipairs(Looks.Day) do
  if i > 1 then check(f[1] > Looks.Day[i - 1][1], "keyframes rise at " .. i) end
  for _, k in ipairs(Looks.KEYS) do check(f[2][k] ~= nil, string.format("keyframe %.1f has %s", f[1], k)) end
  for k, v in pairs(f[2]) do
    local r = RANGES[k]
    if r then check(v >= r[1] and v <= r[2], string.format("keyframe %.1f %s = %s inside %s..%s", f[1], k, tostring(v), r[1], r[2])) end
    if not r then check(typeof(v) == "Color3", string.format("keyframe %.1f %s is a colour", f[1], k)) end
  end
end
check(Looks.Day[#Looks.Day][1] - Looks.Day[1][1] < 24, "keyframes fit in one day")
-- the blend is continuous: no jumps anywhere round the clock (wrap included)
local a, b = {}, {}
for h = 0, 24, 0.01 do
  Blend.sampleDay(a, Looks.Day, h % 24)
  Blend.sampleDay(b, Looks.Day, (h + 0.01) % 24)
  check(math.abs(a.Brightness - b.Brightness) < 0.05 and math.abs(a.Night - b.Night) < 0.02, string.format("smooth at %.2f h", h))
end
for name, z in pairs(Looks.Zones) do
  for _, part in ipairs({"set", "add", "mul"}) do
    for k, v in pairs(z[part] or {}) do
      check(table.find(Looks.KEYS, k) ~= nil, name .. "." .. part .. "." .. k .. " is a look key")
      if part ~= "set" then check(type(v) == "number", name .. "." .. part .. "." .. k .. " is a number") end
    end
  end
end

-- config
for _, n in ipairs(Config.TierOrder) do
  local t = Config.Tiers[n]
  check(t ~= nil, "tier " .. n)
  for _, k in ipairs({"bloom", "sunRays", "dof", "bloomScale", "carShadows", "shadowRange", "porchLights", "trafficBeams"}) do
    check(t and t[k] ~= nil, n .. "." .. k)
  end
end
for _, k in ipairs({"DesktopStart", "MobileStart", "MobileMax", "Floor"}) do check(Config.Tiers[Config.Auto[k]] ~= nil, "Auto." .. k) end
for _, z in ipairs(Config.Zones) do check(Looks.Zones[z.name] ~= nil, "zone " .. z.name .. " has a look") end

print(failures == 0 and "all good" or (failures .. " failure(s)"))
process.exit(failures == 0 and 0 or 1)
