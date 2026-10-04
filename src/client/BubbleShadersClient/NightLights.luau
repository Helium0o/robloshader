-- The town lighting up at night: house windows, porch lamps, traffic tail lamps and headlight beams, lamp posts.
-- The same for every player without any network traffic: which windows light up (and how late) comes from a hash
-- of each window's position, so every client picks the same ones. The parts were tagged by the server
-- (BubbleShadersServer); tags replicate and follow streaming, so parts that stream in later just join in.
-- Real light sources are a small pool that goes to the nearest few lamps / traffic cars only.
local CollectionService = game:GetService("CollectionService")

local NightLights = {}
NightLights.__index = NightLights

local NEON = Enum.Material.Neon

-- 0..1, the same on every client for a part that hasn't moved (position rounded to 1/4 stud)
local function hash01(p, salt)
  local x, y, z = math.floor(p.X * 4 + 0.5), math.floor(p.Y * 4 + 0.5), math.floor(p.Z * 4 + 0.5)
  local h = (x * 92837111 + y * 689287499 + z * 283923481 + salt * 1234567) % 2147483647
  h = (h * 48271) % 2147483647                 -- two Park-Miller steps to spread it out (exact in doubles)
  h = (h * 48271) % 2147483647
  return h / 2147483647
end

-- glowing parts: on = Neon in their glow colour, off = back to how the place had them
local function glowSet()
  return {items = {}}
end
local function glowAdd(set, part, lit, threshold, color)
  if not part:IsA("BasePart") or set.items[part] then return end
  set.items[part] = {lit = lit, th = threshold, color = color, mat = part.Material, col = part.Color, on = false}
end
local function glowRemove(set, part)
  local e = set.items[part]
  if not e then return end
  set.items[part] = nil
  if e.on and part.Parent then part.Material, part.Color = e.mat, e.col end
end
local function glowUpdate(set, night)
  for part, e in pairs(set.items) do
    local on = e.lit and night >= e.th
    if on ~= e.on then
      e.on = on
      if on then part.Material, part.Color = NEON, e.color else part.Material, part.Color = e.mat, e.col end
    end
  end
end

local function watchTag(tag, added, removed)
  for _, inst in ipairs(CollectionService:GetTagged(tag)) do task.spawn(added, inst) end
  CollectionService:GetInstanceAddedSignal(tag):Connect(added)
  CollectionService:GetInstanceRemovedSignal(tag):Connect(removed)
end

-- move a pooled instance; false when it was destroyed (its part streamed out with it) and must be made again
local function moveTo(inst, parent)
  if inst.Parent == parent then return true end
  return (pcall(function() inst.Parent = parent end))
end

function NightLights.new(Config)
  local self = setmetatable({}, NightLights)
  local C = Config.NightLights
  self.cfg = C
  self.night = 0

  -- windows: LitShare of them light up, each at its own moment through dusk (and some stay on into the dawn)
  self.windows = glowSet()
  local W = C.Window
  watchTag(W.Tag, function(p)
    local pos = p.Position
    local colour = W.Colors[1 + math.floor(hash01(pos, 3) * #W.Colors) % #W.Colors]
    glowAdd(self.windows, p, hash01(pos, 1) < W.LitShare, 0.3 + 0.5 * hash01(pos, 2), colour)
    glowUpdate(self.windows, self.night)
  end, function(p) glowRemove(self.windows, p) end)

  -- porch lamps: every one comes on, a little staggered; the nearest few also get a real light (pooled)
  self.porch = glowSet()
  local P = C.Porch
  watchTag(P.Tag, function(p)
    glowAdd(self.porch, p, true, 0.2 + 0.25 * hash01(p.Position, 4), P.Glow)
    glowUpdate(self.porch, self.night)
  end, function(p) glowRemove(self.porch, p) end)
  self.porchPool = {}

  -- traffic tail lamps
  self.tails = glowSet()
  local T = C.TrafficTail
  watchTag(T.Tag, function(p)
    glowAdd(self.tails, p, true, 0.3, T.Glow)
    glowUpdate(self.tails, self.night)
  end, function(p) glowRemove(self.tails, p) end)

  -- traffic cars (for headlight beams on the nearest few)
  self.traffic = {}
  watchTag(C.TrafficCar.Tag, function(m) self.traffic[m] = true end, function(m) self.traffic[m] = nil end)
  self.beamPool = {}

  -- lamp posts: their PointLights only shine from dusk to dawn
  self.street = {}
  watchTag(C.StreetLight.Tag, function(l)
    if l:IsA("Light") then self.street[l] = true; l.Enabled = self.night >= 0.25 end
  end, function(l) self.street[l] = nil end)
  return self
end

-- the nearest `count` entries of `list` ({inst, position}) within `range` of pos
local function nearest(list, pos, count, range)
  local out = {}
  if count <= 0 then return out end
  for _, e in ipairs(list) do
    local d = (e[2] - pos).Magnitude
    if d <= range then table.insert(out, {e[1], d}) end
  end
  table.sort(out, function(a, b) return a[2] < b[2] end)
  for i = count + 1, #out do out[i] = nil end
  return out
end

function NightLights:porchLights(tier, camPos)
  local P = self.cfg.Porch
  local list = {}
  if self.night >= 0.3 then
    for part, e in pairs(self.porch.items) do if e.on then table.insert(list, {part, part.Position}) end end
  end
  local pick = nearest(list, camPos, tier.porchLights, 160)
  for i = 1, math.max(#pick, #self.porchPool) do
    local l = self.porchPool[i]
    local target = pick[i] and pick[i][1]
    if target then
      if not (l and moveTo(l, target)) then
        l = Instance.new("PointLight")
        l.Shadows = false
        l.Parent = target
        self.porchPool[i] = l
      end
      l.Color, l.Range, l.Brightness = P.Glow, P.Range, P.Brightness * math.clamp((self.night - 0.3) / 0.4, 0, 1)
    elseif l then
      moveTo(l, nil)
    end
  end
end

function NightLights:trafficBeams(tier, camPos)
  local T = self.cfg.TrafficCar
  local list = {}
  if self.night >= 0.35 then
    for m in pairs(self.traffic) do
      local root = m:FindFirstChild("Root")
      if root and root:IsA("BasePart") then table.insert(list, {root, root.Position}) end
    end
  end
  local pick = nearest(list, camPos, tier.trafficBeams, 220)
  for i = 1, math.max(#pick, #self.beamPool) do
    local b = self.beamPool[i]
    local root = pick[i] and pick[i][1]
    if root then
      if not (b and moveTo(b.att, root)) then
        local att = Instance.new("Attachment")
        att.Name = "BubbleBeam"
        local l = Instance.new("SpotLight")
        l.Face, l.Shadows, l.Color, l.Range, l.Angle = Enum.NormalId.Front, false, T.BeamColor, T.Range, T.Angle
        l.Parent = att
        att.Parent = root
        b = {att = att, light = l}
        self.beamPool[i] = b
      end
      -- front of the car (traffic faces its LookVector), tipped down onto the road
      b.att.CFrame = CFrame.new(0, -0.6, -root.Size.Z / 2) * CFrame.Angles(math.rad(-8), 0, 0)
      b.light.Brightness = T.Brightness * math.clamp((self.night - 0.35) / 0.35, 0, 1)
    elseif b then
      moveTo(b.att, nil)
    end
  end
end

-- tier: Config.Tiers entry; night: 0..1 from the look; camPos: camera position
function NightLights:update(tier, night, camPos)
  self.night = night
  glowUpdate(self.windows, night)
  glowUpdate(self.porch, night)
  glowUpdate(self.tails, night)
  for l in pairs(self.street) do
    local on = night >= 0.25
    if l.Parent and l.Enabled ~= on then l.Enabled = on end
  end
  self:porchLights(tier, camPos)
  self:trafficBeams(tier, camPos)
end

return NightLights
