--!nocheck
-- Installs (or updates) Bubble Shaders in a place file:
--   lune run tools/build <in.rbxl> <out.rbxl>
-- Same layout as default.project.json (Rojo users can sync that instead):
--   ReplicatedStorage.BubbleShaders                            Config, Looks, Clock, Blend
--   ServerScriptService.BubbleShadersServer
--   StarterPlayer.StarterPlayerScripts.BubbleShadersClient     + Quality, PostFx, CarLightLod, NightLights, GraphicsMenu
-- It also sets the place's own Lighting to the look at server start, so Studio and the very first frame after
-- joining already look right (the client takes over from there).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Instance = roblox.Instance

local input, output = process.args[1], process.args[2]
if not (input and output) then
  print("usage: lune run tools/build <in.rbxl> <out.rbxl>")
  process.exit(1)
end
local game = roblox.deserializePlace(fs.readFile(input))

----------------------------------------------------------------- src/ -> instances (Rojo's file conventions)
local function baseName(file)
  return (file:gsub("%.server%.luau$", ""):gsub("%.client%.luau$", ""):gsub("%.luau$", ""))
end
local function scriptClass(file)
  if file:match("%.server%.luau$") then return "Script" end
  if file:match("%.client%.luau$") then return "LocalScript" end
  return "ModuleScript"
end
local function fromPath(path, name)
  if fs.isFile(path) then
    local s = Instance.new(scriptClass(path))
    s.Name = name
    s.Source = fs.readFile(path)
    return s
  end
  local entries = fs.readDir(path)
  table.sort(entries)
  local inst
  for _, e in ipairs(entries) do
    if e:match("^init%.") then
      inst = Instance.new(scriptClass(e))
      inst.Source = fs.readFile(path .. "/" .. e)
    end
  end
  inst = inst or Instance.new("Folder")
  inst.Name = name
  for _, e in ipairs(entries) do
    if not e:match("^init%.") and (fs.isDir(path .. "/" .. e) or e:match("%.luau$")) then
      fromPath(path .. "/" .. e, baseName(e)).Parent = inst
    end
  end
  return inst
end
local function install(parent, name, path)
  local old = parent:FindFirstChild(name)
  if old then old:Destroy() end
  fromPath(path, name).Parent = parent
  print("installed " .. parent.Name .. "." .. name)
end

local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local SPS = game:GetService("StarterPlayer"):FindFirstChildOfClass("StarterPlayerScripts")
install(RS, "BubbleShaders", "src/shared/BubbleShaders")
install(SSS, "BubbleShadersServer", "src/server/BubbleShadersServer.server.luau")
install(SPS, "BubbleShadersClient", "src/client/BubbleShadersClient")

----------------------------------------------------------------- the look at server start, baked into Lighting
local env = {Color3 = roblox.Color3, Vector3 = roblox.Vector3, Enum = roblox.Enum}
local function load(name)
  return luau.load(fs.readFile("src/shared/BubbleShaders/" .. name .. ".luau"), {debugName = name, environment = table.clone(env)})()
end
local Config, Looks, Blend = load("Config"), load("Looks"), load("Blend")
local hour = Config.DayCycle.StartClock
local look = Blend.sampleDay({}, Looks.Day, hour)
local tier = Config.Tiers.High

local L = game:GetService("Lighting")
L.TimeOfDay = string.format("%02d:%02d:00", math.floor(hour), math.floor(hour % 1 * 60 + 0.5))
L.GeographicLatitude = Config.Latitude
L.Brightness = look.Brightness
L.ExposureCompensation = look.Exposure
L.Ambient, L.OutdoorAmbient = look.Ambient, look.OutdoorAmbient
L.ColorShift_Top, L.ColorShift_Bottom = look.ShiftTop, look.ShiftBottom
L.EnvironmentDiffuseScale, L.EnvironmentSpecularScale = look.EnvDiffuse, look.EnvSpecular
L.ShadowSoftness = look.ShadowSoftness

local function child(class, name)
  local c = L:FindFirstChildOfClass(class)
  if not c then
    c = Instance.new(class)
    c.Name = name
    c.Parent = L
  end
  return c
end
local atm = child("Atmosphere", "Atmosphere")
atm.Density, atm.Offset, atm.Color, atm.Decay = look.AtmDensity, look.AtmOffset, look.AtmColor, look.AtmDecay
atm.Glare, atm.Haze = look.AtmGlare, look.AtmHaze
local bloom = child("BloomEffect", "Bloom")
bloom.Enabled = true
bloom.Intensity, bloom.Size, bloom.Threshold = look.BloomIntensity * tier.bloomScale, look.BloomSize, look.BloomThreshold
local rays = child("SunRaysEffect", "SunRays")
rays.Enabled = true
rays.Intensity, rays.Spread = look.RaysIntensity, look.RaysSpread
child("DepthOfFieldEffect", "DepthOfField").Enabled = false
local grade = L:FindFirstChild("BubbleGrade")
if not grade then
  grade = Instance.new("ColorCorrectionEffect")
  grade.Name = "BubbleGrade"
  grade.Parent = L
end
grade.Brightness, grade.Contrast, grade.Saturation, grade.TintColor =
  look.GradeBrightness, look.GradeContrast, look.GradeSaturation, look.GradeTint
print(string.format("Lighting set to the %.2f h look", hour))

fs.writeFile(output, roblox.serializePlace(game))
print("wrote " .. output)
