-- Owns Lighting and the post effects on this client. It adopts the place's own Atmosphere / Bloom / SunRays /
-- DepthOfField (so Studio still shows roughly the right look) and adds one ColorCorrection. A property is only
-- written when its value really changed, so most frames write nothing at all.
-- Everything here is local: a LocalScript changing Lighting is never sent to the server or other players.
local Lighting = game:GetService("Lighting")

local PostFx = {}
PostFx.__index = PostFx

-- the place's own effect if it has one (only the first: two Blooms would add up), else a new one
local function adopt(parent, class, name)
  local found = parent:FindFirstChildOfClass(class)
  if found then return found end
  local e = Instance.new(class)
  e.Name = name
  e.Parent = parent
  return e
end

local function differs(a, b)
  if a == nil then return true end
  if type(b) == "number" then return math.abs(a - b) > 1e-3 end
  if typeof(b) == "Color3" then return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) > 0.004 end
  return a ~= b
end

function PostFx.new(Config)
  local self = setmetatable({}, PostFx)
  self.last = {}
  self.atm = adopt(Lighting, "Atmosphere", "Atmosphere")
  self.bloom = adopt(Lighting, "BloomEffect", "Bloom")
  self.rays = adopt(Lighting, "SunRaysEffect", "SunRays")
  self.dof = adopt(Lighting, "DepthOfFieldEffect", "DepthOfField")
  -- ours (other ColorCorrections, e.g. a hit flash, still stack on top); the built place already has one
  local grade = Lighting:FindFirstChild("BubbleGrade")
  if not (grade and grade:IsA("ColorCorrectionEffect")) then
    grade = Instance.new("ColorCorrectionEffect")
    grade.Name = "BubbleGrade"
    grade.Parent = Lighting
  end
  self.grade = grade
  Lighting.GeographicLatitude = Config.Latitude
  return self
end

function PostFx:put(inst, prop, v)
  local c = self.last[inst]
  if not c then c = {}; self.last[inst] = c end
  if differs(c[prop], v) then
    c[prop] = v
    inst[prop] = v
  end
end

-- forget what was written, so anything else that changed these properties gets put right on the next frame
function PostFx:flush() table.clear(self.last) end

-- look: a Looks table; tier: Config.Tiers entry; hour: new ClockTime or nil (it's moved less often);
-- focus: studs to keep sharp when depth of field is on
function PostFx:apply(look, tier, hour, focus)
  local put = self.put
  if hour then put(self, Lighting, "ClockTime", hour) end
  put(self, Lighting, "Brightness", look.Brightness)
  put(self, Lighting, "ExposureCompensation", math.clamp(look.Exposure, -3, 3))
  put(self, Lighting, "Ambient", look.Ambient)
  put(self, Lighting, "OutdoorAmbient", look.OutdoorAmbient)
  put(self, Lighting, "ColorShift_Top", look.ShiftTop)
  put(self, Lighting, "ColorShift_Bottom", look.ShiftBottom)
  put(self, Lighting, "EnvironmentDiffuseScale", math.clamp(look.EnvDiffuse, 0, 1))
  put(self, Lighting, "EnvironmentSpecularScale", math.clamp(look.EnvSpecular, 0, 1))
  put(self, Lighting, "ShadowSoftness", math.clamp(look.ShadowSoftness, 0, 1))

  local atm = self.atm
  put(self, atm, "Density", math.clamp(look.AtmDensity, 0, 1))
  put(self, atm, "Offset", math.clamp(look.AtmOffset, 0, 1))
  put(self, atm, "Color", look.AtmColor)
  put(self, atm, "Decay", look.AtmDecay)
  put(self, atm, "Glare", math.clamp(look.AtmGlare, 0, 10))
  put(self, atm, "Haze", math.clamp(look.AtmHaze, 0, 10))

  local grade = self.grade
  put(self, grade, "Brightness", math.clamp(look.GradeBrightness, -1, 1))
  put(self, grade, "Contrast", math.clamp(look.GradeContrast, -1, 1))
  put(self, grade, "Saturation", math.clamp(look.GradeSaturation, -1, 1))
  put(self, grade, "TintColor", look.GradeTint)

  local bloom = self.bloom
  put(self, bloom, "Enabled", tier.bloom)
  if tier.bloom then
    put(self, bloom, "Intensity", math.clamp(look.BloomIntensity * tier.bloomScale, 0, 1))
    put(self, bloom, "Size", math.clamp(look.BloomSize, 0, 56))
    put(self, bloom, "Threshold", math.clamp(look.BloomThreshold, 0.8, 4))
  end

  local rays = self.rays
  local raysOn = tier.sunRays and look.RaysIntensity > 0.005
  put(self, rays, "Enabled", raysOn)
  if raysOn then
    put(self, rays, "Intensity", math.clamp(look.RaysIntensity, 0, 1))
    put(self, rays, "Spread", math.clamp(look.RaysSpread, 0, 1))
  end

  local dof = self.dof
  local dofOn = tier.dof and look.DofFar > 0.01
  put(self, dof, "Enabled", dofOn)
  if dofOn then
    put(self, dof, "FarIntensity", math.clamp(look.DofFar, 0, 1))
    put(self, dof, "NearIntensity", math.clamp(look.DofNear, 0, 1))
    put(self, dof, "InFocusRadius", math.clamp(look.DofRadius, 0, 50))
    put(self, dof, "FocusDistance", math.clamp(focus or 30, 0, 200))
  end
end

return PostFx
