-- Bubble Shaders looks: what the town looks like through the day, plus places / moments with their own look.
-- Pastel candy world: bright airy days, lilac (not grey) shadows, pink golden hour, lavender night where the
-- streets stay readable and the neon, windows and car lights do the glowing.
--
-- Every keyframe has every key. Between keyframes values ease (smoothstep), colours blend channel by channel.
--   Brightness ... ShadowSoftness   Lighting
--   Atm*                            Atmosphere (Density 0-1, Offset 0-1, Glare / Haze 0-10)
--   Grade*                          ColorCorrectionEffect (Brightness / Contrast / Saturation -1..1, Tint)
--   Bloom*                          BloomEffect (Threshold 0.8-4: a bit above 1 keeps neon glowing, the sky not)
--   Rays*                           SunRaysEffect (0-1)
--   Dof*                            DepthOfFieldEffect (DofFar 0 = off). Focus is worked out live.
--   Night                           0 day .. 1 night: drives windows, porch lamps, traffic lights, car light budget
local rgb = Color3.fromRGB
local Looks = {}

local function with(base, changes)
  local t = table.clone(base)
  for k, v in pairs(changes) do t[k] = v end
  return t
end

local NOON = {
  Brightness = 3, Exposure = 0.05,
  Ambient = rgb(98, 88, 112), OutdoorAmbient = rgb(130, 118, 146),
  ShiftTop = rgb(255, 247, 240), ShiftBottom = rgb(226, 210, 240),
  EnvDiffuse = 0.85, EnvSpecular = 0.9, ShadowSoftness = 0.18,
  AtmDensity = 0.24, AtmOffset = 0.2, AtmColor = rgb(255, 224, 238), AtmDecay = rgb(255, 196, 222), AtmGlare = 0.15, AtmHaze = 0.9,
  GradeBrightness = 0.01, GradeContrast = 0.08, GradeSaturation = 0.06, GradeTint = rgb(255, 252, 253),
  BloomIntensity = 0.45, BloomSize = 26, BloomThreshold = 1.35,
  RaysIntensity = 0.05, RaysSpread = 0.55,
  DofFar = 0, DofNear = 0, DofRadius = 30,
  Night = 0,
}
local MORNING = with(NOON, {
  Brightness = 2.7, Exposure = 0.1,
  Ambient = rgb(104, 92, 120), OutdoorAmbient = rgb(140, 124, 160),
  ShiftTop = rgb(255, 226, 214), ShiftBottom = rgb(214, 200, 246), ShadowSoftness = 0.22,
  AtmDensity = 0.28, AtmColor = rgb(255, 214, 232), AtmDecay = rgb(200, 176, 240), AtmGlare = 0.5, AtmHaze = 1.4,
  GradeBrightness = 0.015, GradeContrast = 0.07, GradeSaturation = 0.08, GradeTint = rgb(255, 246, 248),
  BloomIntensity = 0.5, BloomSize = 28, BloomThreshold = 1.3,
  RaysIntensity = 0.08, RaysSpread = 0.7,
})
local AFTERNOON = with(NOON, {
  ShiftTop = rgb(255, 240, 226),
  AtmGlare = 0.25, AtmHaze = 1.0,
  GradeTint = rgb(255, 250, 248),
  RaysIntensity = 0.06,
})
local GOLDEN = with(NOON, {
  Brightness = 2.8, Exposure = 0.08,
  Ambient = rgb(110, 88, 112), OutdoorAmbient = rgb(156, 122, 150),
  ShiftTop = rgb(255, 200, 160), ShiftBottom = rgb(210, 180, 240),
  EnvDiffuse = 0.8, EnvSpecular = 1, ShadowSoftness = 0.2,
  AtmDensity = 0.28, AtmColor = rgb(255, 200, 212), AtmDecay = rgb(255, 150, 178), AtmGlare = 0.9, AtmHaze = 1.8,
  GradeBrightness = 0.015, GradeContrast = 0.1, GradeSaturation = 0.13, GradeTint = rgb(255, 240, 234),
  BloomIntensity = 0.6, BloomSize = 30, BloomThreshold = 1.2,
  RaysIntensity = 0.12, RaysSpread = 0.8,
})
local SUNSET = with(GOLDEN, {
  Brightness = 2.2, Exposure = 0.12,
  Ambient = rgb(110, 82, 120), OutdoorAmbient = rgb(160, 112, 160),
  ShiftTop = rgb(255, 150, 140), ShiftBottom = rgb(190, 150, 230),
  EnvDiffuse = 0.75, ShadowSoftness = 0.25,
  AtmDensity = 0.3, AtmOffset = 0.22, AtmColor = rgb(255, 178, 204), AtmDecay = rgb(180, 116, 200), AtmGlare = 1.6, AtmHaze = 2.2,
  GradeBrightness = 0.01, GradeContrast = 0.12, GradeSaturation = 0.12, GradeTint = rgb(255, 236, 240),
  BloomIntensity = 0.8, BloomSize = 32, BloomThreshold = 1.1,
  RaysIntensity = 0.16, RaysSpread = 0.9,
  Night = 0.25,
})
local DUSK = with(SUNSET, {
  Brightness = 1.4, Exposure = 0.2,
  Ambient = rgb(88, 72, 128), OutdoorAmbient = rgb(128, 104, 180),
  ShiftTop = rgb(200, 150, 230), ShiftBottom = rgb(140, 120, 220),
  EnvDiffuse = 0.6, EnvSpecular = 0.7, ShadowSoftness = 0.3,
  AtmDensity = 0.32, AtmOffset = 0.2, AtmColor = rgb(190, 138, 222), AtmDecay = rgb(96, 74, 170), AtmGlare = 0.5, AtmHaze = 1.8,
  GradeBrightness = 0, GradeContrast = 0.12, GradeSaturation = 0.1, GradeTint = rgb(244, 236, 255),
  BloomIntensity = 1, BloomSize = 32, BloomThreshold = 1,
  RaysIntensity = 0.04, RaysSpread = 0.6,
  Night = 0.7,
})
local NIGHT = with(DUSK, {
  Brightness = 1.5, Exposure = 0.25,
  Ambient = rgb(72, 66, 106), OutdoorAmbient = rgb(100, 92, 142),
  ShiftTop = rgb(185, 185, 255), ShiftBottom = rgb(110, 100, 190),
  EnvDiffuse = 0.5, EnvSpecular = 0.55, ShadowSoftness = 0.35,
  AtmDensity = 0.33, AtmOffset = 0.18, AtmColor = rgb(124, 108, 176), AtmDecay = rgb(60, 54, 116), AtmGlare = 0, AtmHaze = 0.9,
  GradeContrast = 0.14, GradeSaturation = 0.08, GradeTint = rgb(238, 234, 255),
  BloomIntensity = 1, BloomSize = 34, BloomThreshold = 1,
  RaysIntensity = 0, RaysSpread = 0.5,
  Night = 1,
})
local DAWN = with(MORNING, {
  Brightness = 1.6, Exposure = 0.2,
  Ambient = rgb(96, 80, 124), OutdoorAmbient = rgb(140, 112, 170),
  ShiftTop = rgb(255, 176, 190), ShiftBottom = rgb(170, 150, 230),
  EnvDiffuse = 0.65, EnvSpecular = 0.8, ShadowSoftness = 0.3,
  AtmDensity = 0.32, AtmColor = rgb(255, 186, 214), AtmDecay = rgb(150, 120, 206), AtmGlare = 1, AtmHaze = 2.2,
  GradeBrightness = 0.01, GradeContrast = 0.1, GradeSaturation = 0.12, GradeTint = rgb(252, 236, 248),
  BloomIntensity = 0.9, BloomSize = 32, BloomThreshold = 1.05,
  RaysIntensity = 0.12, RaysSpread = 0.85,
  Night = 0.45,
})

-- {clock hour, look}, rising. The day wraps round (the last one blends into the first one 24 h later).
Looks.Day = {
  {4.4, NIGHT},
  {5.9, DAWN},
  {7.8, MORNING},
  {12.0, NOON},
  {14.8, AFTERNOON},
  {16.6, GOLDEN},
  {17.7, SUNSET},
  {18.5, DUSK},
  {19.6, NIGHT},
}

-- Zones / moments: blended on top of the time of day by a 0..1 weight.
--   set  move toward this value     add  add this much     mul  multiply by this
Looks.Zones = {
  -- the drift track floats in the sky: clearer air so you can read the corners, a bit more punch
  SkyTrack = {
    mul = {AtmDensity = 0.7, AtmHaze = 0.7},
    add = {GradeContrast = 0.04, GradeSaturation = 0.06, BloomIntensity = 0.15, RaysIntensity = 0.04, Exposure = 0.05},
  },
  -- customs / try-on camera: the car is the star (soft background blur on High and Ultra)
  Showroom = {
    set = {DofFar = 0.35, DofNear = 0, DofRadius = 14, ShadowSoftness = 0.12},
    add = {GradeContrast = 0.04, GradeSaturation = 0.04, Exposure = 0.1, BloomIntensity = 0.1},
  },
}

Looks.KEYS = {}
for k in pairs(NOON) do table.insert(Looks.KEYS, k) end
table.sort(Looks.KEYS)

return Looks
