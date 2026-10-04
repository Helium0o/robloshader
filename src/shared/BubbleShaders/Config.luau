-- Bubble Shaders settings: everything worth tuning lives here.
-- All the rendering runs on each player's own client (lighting and post effects never touch the network).
-- The server only keeps the shared day clock (3 attributes on Lighting) and tags the town's night lights once.
local Config = {}

----------------------------------------------------------------- day / night
-- One clock for every player: the server stores where the cycle was at a moment of server time, and each
-- client works the current time out from workspace:GetServerTimeNow(). Everyone sees the same sky with zero
-- network traffic. Setting Lighting.ClockTime on the server (e.g. the admin "time" command) re-anchors it.
Config.DayCycle = {
  Enabled = true,       -- false: the time stays wherever the server's Lighting.ClockTime is
  Minutes = 20,         -- real minutes for one whole day
  StartClock = 14.5,    -- time of day when a server starts
}
-- How the day is spread over the cycle: {share of the cycle, clock hour}, both rising (hours may pass 24,
-- the curve must cover exactly 24 h). Long bright day, a slower golden hour / sunset (the prettiest part),
-- a shorter night. With Minutes = 20:
Config.DayCurve = {
  {0.00, 5.5},          -- sunrise
  {0.06, 7.5},          -- 1.2 min of morning glow
  {0.48, 15.8},         -- 8.4 min of day
  {0.64, 18.8},         -- 3.2 min of golden hour + sunset
  {0.90, 28.6},         -- 5.2 min of night (to 04:36)
  {1.00, 29.5},         -- 2 min of dawn, back to 05:30
}
Config.Latitude = 28    -- degrees: sun crosses a little to the south, so noon shadows aren't straight down

----------------------------------------------------------------- quality tiers
-- Each player gets a tier picked from their device and Roblox graphics level, then adjusted by measured FPS
-- (Auto), or the one they choose in the GRAPHICS menu (F3).
--   bloom / sunRays / dof   post effects allowed
--   carShadows              how many lit cars (nearest first, your own always first) keep shadow-casting lights
--   shadowRange             studs: cars further than this never get light shadows
--   porchLights             real PointLights on the nearest lit porch lamps at night (the lamps glow either way)
--   trafficBeams            headlight SpotLights on the nearest traffic cars at night (no shadows)
Config.TierOrder = {"Low", "Medium", "High", "Ultra"}
Config.Tiers = {
  Low    = {bloom = false, sunRays = false, dof = false, bloomScale = 0,   carShadows = 0, shadowRange = 0,   porchLights = 0,  trafficBeams = 0},
  Medium = {bloom = true,  sunRays = false, dof = false, bloomScale = 0.8, carShadows = 2, shadowRange = 90,  porchLights = 4,  trafficBeams = 3},
  High   = {bloom = true,  sunRays = true,  dof = true,  bloomScale = 1,   carShadows = 4, shadowRange = 140, porchLights = 8,  trafficBeams = 6},
  Ultra  = {bloom = true,  sunRays = true,  dof = true,  bloomScale = 1,   carShadows = 8, shadowRange = 220, porchLights = 14, trafficBeams = 10},
}
Config.Auto = {
  DesktopStart = "High",      -- first guess when Roblox graphics is on Automatic
  MobileStart = "Medium",
  MobileMax = "High",         -- Auto never goes above this on phones / tablets
  Floor = "Medium",           -- Auto only drops below this when FPS is really bad (VeryLowFps)
  LowFps = 40,                -- average below this for DropAfter seconds: one tier down
  VeryLowFps = 24,
  DropAfter = 4,
  HighFps = 57,               -- average above this for RiseAfter seconds: one tier back up
  RiseAfter = 30,
}

----------------------------------------------------------------- places with their own look
-- Boxes in world space. Inside a box the camera blends to that zone's look (Looks.Zones[name]) over `fade` studs.
Config.Zones = {
  {name = "SkyTrack", min = Vector3.new(-470, 400, 4780), max = Vector3.new(710, 1000, 6330), fade = 80},
}

----------------------------------------------------------------- boost
-- A short colour kick while boosting (your own car only). Scaled by the player's camera mode, so "Steady"
-- (no camera effects) gets none and "Comfort" gets a gentle one.
Config.Boost = {
  Saturation = 0.12, Contrast = 0.05, Exposure = 0.06, Bloom = 0.25,
  Tint = Color3.fromRGB(255, 238, 247),
  RiseTime = 0.12, FallTime = 0.5,
  ModeScale = {Comfort = 0.4, Balanced = 1, Sporty = 1.25, Steady = 0},
}

----------------------------------------------------------------- night lights
-- Found and tagged by the server once (CollectionService tags replicate and survive streaming).
Config.NightLights = {
  -- round house windows: light blue glass cylinders
  Window = {Tag = "BubbleWindow", Folder = {"BubblegumTown", "Houses"}, Color = {190, 228, 255}, Shape = "Cylinder",
    LitShare = 0.7,           -- share of windows that light up (the same ones for every player)
    Colors = {Color3.fromRGB(255, 214, 150), Color3.fromRGB(255, 196, 170), Color3.fromRGB(255, 226, 190), Color3.fromRGB(240, 200, 255)}},
  -- little yellow lamp ball next to each front door
  Porch = {Tag = "BubblePorchLamp", Folder = {"BubblegumTown", "Houses"}, Color = {255, 238, 150}, Shape = "Ball", MaxSize = 1.2,
    Glow = Color3.fromRGB(255, 210, 130), Range = 16, Brightness = 1.4},
  -- traffic cars' red tail lamp balls (their headlights are already Neon)
  TrafficTail = {Tag = "BubbleTailLamp", Folder = {"BubblegumTown", "Traffic"}, Color = {255, 80, 125}, Shape = "Ball", MaxSize = 1.0,
    Glow = Color3.fromRGB(255, 60, 90)},
  TrafficCar = {Tag = "BubbleTrafficCar", Folder = {"BubblegumTown", "Traffic"},
    BeamColor = Color3.fromRGB(255, 244, 214), Range = 40, Angle = 60, Brightness = 1.2},
  -- lamp posts with a PointLight (the plaza): off in daylight, brighter at night
  StreetLight = {Tag = "BubbleStreetLight", Folders = {{"BubblegumTown", "Plaza"}, {"BubblegumTown", "Zones"}}},
}

----------------------------------------------------------------- misc
Config.CarsFolder = {"BubblegumTown", "DriveableCars"}   -- every driveable car (their lights get the shadow budget)
Config.MenuKey = Enum.KeyCode.F3
Config.ClockHz = 10           -- how often the sun is moved (it's slow; nobody sees the steps)
Config.LodHz = 4              -- how often car light shadows / night lights are re-ranked

return Config
