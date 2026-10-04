-- Bubble Shaders (server): keeps the shared day clock and tags the town's night lights. That's all - every visual
-- runs on the players' own clients. No remotes and no loops: three attributes on Lighting (written when the server
-- starts and whenever someone sets the time) and CollectionService tags added once.
--
-- Set the time from any server script by setting Lighting.ClockTime (like the admin "time" command does): the cycle
-- carries on from there for everyone. Server code that needs the current hour:
--   Clock.read(Lighting, Config.DayCurve, workspace:GetServerTimeNow())
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local RS = game:GetService("ReplicatedStorage")

local Shared = RS:WaitForChild("BubbleShaders")
local Config = require(Shared:WaitForChild("Config"))
local Clock = require(Shared:WaitForChild("Clock"))

----------------------------------------------------------------- day clock
local function anchor(hour)
  Lighting:SetAttribute(Clock.ATTR_SHARE, Clock.shareAt(Config.DayCurve, hour))
  Lighting:SetAttribute(Clock.ATTR_LENGTH, Config.DayCycle.Enabled and Config.DayCycle.Minutes * 60 or 0)
  Lighting:SetAttribute(Clock.ATTR_ORIGIN, workspace:GetServerTimeNow())
end
anchor(Config.DayCycle.Enabled and Config.DayCycle.StartClock or Lighting.ClockTime)
-- (this script never writes ClockTime itself, so this only fires when someone else sets the time)
Lighting:GetPropertyChangedSignal("ClockTime"):Connect(function() anchor(Lighting.ClockTime) end)

----------------------------------------------------------------- night light tags
local function folderAt(path)
  local f = workspace
  for _, n in ipairs(path) do f = f and f:FindFirstChild(n) end
  return f
end
local function rgb(c) return math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) end
local function matches(p, rule)
  if not p:IsA("Part") then return false end
  if rule.Shape and p.Shape ~= Enum.PartType[rule.Shape] then return false end
  if rule.MaxSize and math.max(p.Size.X, p.Size.Y, p.Size.Z) > rule.MaxSize then return false end
  local r, g, b = rgb(p.Color)
  return r == rule.Color[1] and g == rule.Color[2] and b == rule.Color[3]
end
-- parts inside a folder that look like `rule` (colour / shape / size), now and when added later
local function tagParts(rule)
  local folder = folderAt(rule.Folder)
  if not folder then warn("[BubbleShaders] no folder " .. table.concat(rule.Folder, ".") .. " for " .. rule.Tag); return end
  local function check(d) if matches(d, rule) then CollectionService:AddTag(d, rule.Tag) end end
  for _, d in ipairs(folder:GetDescendants()) do check(d) end
  folder.DescendantAdded:Connect(check)
end

local NL = Config.NightLights
tagParts(NL.Window)
tagParts(NL.Porch)
tagParts(NL.TrafficTail)

-- traffic car models (headlight beams go on the nearest few)
do
  local folder = folderAt(NL.TrafficCar.Folder)
  if folder then
    local function check(m) if m:IsA("Model") then CollectionService:AddTag(m, NL.TrafficCar.Tag) end end
    for _, m in ipairs(folder:GetChildren()) do check(m) end
    folder.ChildAdded:Connect(check)
  end
end

-- lamp posts: every Light in these folders
for _, path in ipairs(NL.StreetLight.Folders) do
  local folder = folderAt(path)
  if folder then
    local function check(d) if d:IsA("Light") then CollectionService:AddTag(d, NL.StreetLight.Tag) end end
    for _, d in ipairs(folder:GetDescendants()) do check(d) end
    folder.DescendantAdded:Connect(check)
  end
end
