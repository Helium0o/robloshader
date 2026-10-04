-- Bubble Shaders (client): this player's sky, lighting, colour grading, bloom, sun rays, depth of field, night lights
-- and car light shadows. Runs entirely on this client - nothing is sent to the server or other players - and every
-- player gets the tier their own device can run (GRAPHICS menu, F3).
--   time of day   shared clock from the server (Clock), the same sky for everyone
--   looks         Looks.Day keyframes, blended; zones (Config.Zones) and moments (customs, boost) on top
--   budgets       CarLightLod: shadows only on the nearest lit cars; NightLights: pooled lamp / traffic lights
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local RS = game:GetService("ReplicatedStorage")

local Shared = RS:WaitForChild("BubbleShaders")
local Config = require(Shared:WaitForChild("Config"))
local Looks = require(Shared:WaitForChild("Looks"))
local Clock = require(Shared:WaitForChild("Clock"))
local Blend = require(Shared:WaitForChild("Blend"))
local Quality = require(script:WaitForChild("Quality"))
local PostFx = require(script:WaitForChild("PostFx"))
local CarLightLod = require(script:WaitForChild("CarLightLod"))
local NightLights = require(script:WaitForChild("NightLights"))
local GraphicsMenu = require(script:WaitForChild("GraphicsMenu"))
-- the player's camera mode (F2) scales the boost kick: "Steady" means no screen effects at all
local cameraModes = RS:FindFirstChild("CameraModes")
local CameraModes = cameraModes and cameraModes:IsA("ModuleScript") and require(cameraModes) or nil

local player = Players.LocalPlayer
local quality = Quality.new(Config)
local fx = PostFx.new(Config)
local night = NightLights.new(Config)

local lod
task.spawn(function()
  local f = workspace
  for _, n in ipairs(Config.CarsFolder) do f = f and f:WaitForChild(n, 60) end
  if f then lod = CarLightLod.new(f) end
end)

-- time of day: the admin preview (this screen only), else the shared cycle, else whatever the server set
local preview = nil
local function currentHour()
  if preview then return preview end
  local h = Config.DayCycle.Enabled and Clock.read(Lighting, Config.DayCurve, workspace:GetServerTimeNow())
  return h or Lighting.ClockTime
end
GraphicsMenu.new(quality, Config, function(h) preview = h end)

-- the car you're driving, and whether it's boosting right now (GumCarClient turns the BoostFlame emitters on
-- locally the moment you boost, so this needs no remote)
local function myCar()
  local char = player.Character
  local hum = char and char:FindFirstChildOfClass("Humanoid")
  local seat = hum and hum.SeatPart
  return seat and seat:IsA("VehicleSeat") and seat.Parent or nil
end
local flames, flameCar, flameScan = {}, nil, -1
local function boosting(car, now)
  if car ~= flameCar or now - flameScan > 1 then        -- re-collected: exhaust tips can be swapped while driving
    flameCar, flameScan = car, now
    table.clear(flames)
    local ch = car and car:FindFirstChild("Chassis")
    if ch then
      for _, d in ipairs(ch:GetDescendants()) do
        if d:IsA("ParticleEmitter") and d.Name == "BoostFlame" then table.insert(flames, d) end
      end
    end
  end
  for _, e in ipairs(flames) do if e.Enabled then return true end end
  return false
end

local look = {}
local zoneW = {}
local showroomW, boostK = 0, 0
local hour = currentHour()
local clockT, lodT, flushT = math.huge, math.huge, 0
local B = Config.Boost

local function step(dt)
  local now = os.clock()
  quality:update(dt)
  local tier = quality:tier()
  local cam = workspace.CurrentCamera
  local camPos = cam and cam.CFrame.Position or Vector3.zero

  -- the sun moves slowly: only every 1 / ClockHz s
  clockT += dt
  local newHour = nil
  if clockT >= 1 / Config.ClockHz or preview then
    clockT = 0
    hour = currentHour()
    newHour = hour
  end
  Blend.sampleDay(look, Looks.Day, hour)

  -- zones (eased so walking / driving in and out blends over a second or two)
  local ease = 1 - math.exp(-dt * 2)
  for _, z in ipairs(Config.Zones) do
    local target = Blend.boxWeight(camPos, z.min, z.max, z.fade)
    local w = zoneW[z.name] or target
    w += (target - w) * ease
    zoneW[z.name] = w
    Blend.zone(look, Looks.Zones[z.name], w)
  end

  -- customs / try-on camera (ShopUI sets InCustoms)
  local car = myCar()
  local inCustoms = player:GetAttribute("InCustoms") == true
  showroomW += ((inCustoms and 1 or 0) - showroomW) * (1 - math.exp(-dt * 3))
  Blend.zone(look, Looks.Zones.Showroom, showroomW)

  -- boost kick
  local scale = B.ModeScale[CameraModes and CameraModes.current or "Balanced"] or 1
  local target = (car and boosting(car, now)) and scale or 0
  local tau = target > boostK and B.RiseTime or B.FallTime
  boostK += (target - boostK) * (1 - math.exp(-dt / tau))
  if boostK > 0.002 then
    look.GradeSaturation += B.Saturation * boostK
    look.GradeContrast += B.Contrast * boostK
    look.Exposure += B.Exposure * boostK
    look.BloomIntensity += B.Bloom * boostK
    look.GradeTint = look.GradeTint:Lerp(B.Tint, math.min(boostK, 1))
  end

  -- depth of field (customs only): keep your car sharp
  local focus = 30
  if showroomW > 0.01 and car then focus = (car:GetPivot().Position - camPos).Magnitude end

  fx:apply(look, tier, newHour, focus)

  -- budgets: re-ranked a few times a second
  lodT += dt
  if lodT >= 1 / Config.LodHz then
    lodT = 0
    if lod then lod:update(tier, look.Night, camPos, car) end
    night:update(tier, look.Night, camPos)
  end
  flushT += dt
  if flushT > 5 then flushT = 0; fx:flush() end
end

step(0)                                    -- right away, so nobody sees a frame of the plain look
RunService.RenderStepped:Connect(step)
