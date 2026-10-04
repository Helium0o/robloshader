-- Car light shadows on a budget. Every driveable car's head / brake / reverse / side-tail / scanner / backfire lights
-- are SpotLights and PointLights with Shadows on (DriveableCarServer and CarExhaustFx turn it on, so a car's light
-- never shines through its own body). Shadow-casting local lights are the most expensive thing in the scene: a
-- full server at night is 100+ of them. Each client keeps shadows only on the nearest few lit cars (its own car
-- always first) and turns them off on the rest. Locally only: nobody else is affected, and the server's light
-- states (on / off / brake / reverse) are never touched - only the Shadows flag, put back whenever the server or
-- another script sets it again.
local CarLightLod = {}
CarLightLod.__index = CarLightLod

local DAY_BUDGET = 1        -- in full daylight car lamps barely show: only your own car keeps shadows

function CarLightLod.new(folder)
  local self = setmetatable({folder = folder, lights = {}, want = {}, conns = {}, ranked = {}, allowed = {}}, CarLightLod)
  local function carOf(d)
    local p = d.Parent
    while p and p.Parent ~= folder do p = p.Parent end
    return p
  end
  local function add(d)
    if not d:IsA("Light") or self.lights[d] then return end
    local car = carOf(d)
    if not car then return end
    self.lights[d] = car
    self.conns[d] = d:GetPropertyChangedSignal("Shadows"):Connect(function()
      local w = self.want[d]
      if w ~= nil and d.Shadows ~= w then d.Shadows = w end
    end)
  end
  local function remove(d)
    if not self.lights[d] then return end
    self.lights[d], self.want[d] = nil, nil
    self.conns[d]:Disconnect()
    self.conns[d] = nil
  end
  for _, d in ipairs(folder:GetDescendants()) do add(d) end
  folder.DescendantAdded:Connect(add)
  folder.DescendantRemoving:Connect(remove)
  return self
end

local function carPos(car)
  local ch = car:FindFirstChild("Chassis")
  if ch and ch:IsA("BasePart") then return ch.Position end
  return car:GetPivot().Position
end

-- tier: Config.Tiers entry; night: 0..1; camPos: camera position; myCar: the model you're driving (or nil)
function CarLightLod:update(tier, night, camPos, myCar)
  local budget = tier.carShadows
  if night < 0.2 then budget = math.min(budget, DAY_BUDGET) end
  local ranked, allowed = self.ranked, self.allowed
  table.clear(ranked)
  table.clear(allowed)
  for _, car in ipairs(self.folder:GetChildren()) do
    if car == myCar then
      allowed[car] = true               -- your own car always (headlights through your own bonnet look broken)
    elseif car:GetAttribute("LightsOn") == true then
      local d = (carPos(car) - camPos).Magnitude
      if d <= tier.shadowRange then table.insert(ranked, {car, d}) end
    end
  end
  table.sort(ranked, function(a, b) return a[2] < b[2] end)
  local left = budget - (myCar and 1 or 0)
  for i = 1, math.min(left, #ranked) do allowed[ranked[i][1]] = true end
  for light, car in pairs(self.lights) do
    -- backfire flashes last a tenth of a second: never worth a shadow map on someone else's car
    local w = allowed[car] == true and (car == myCar or light.Name ~= "PopLight")
    self.want[light] = w
    if light.Shadows ~= w then light.Shadows = w end
  end
end

return CarLightLod
