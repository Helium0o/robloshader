-- Picks this player's quality tier. Either the one they chose in the GRAPHICS menu, or Auto: a first guess from
-- the device and their Roblox graphics level, then nudged by the frame rate they actually get. Every player
-- decides for themselves; nothing here is shared.
local UIS = game:GetService("UserInputService")

local Quality = {}
Quality.__index = Quality

local WARMUP = 10          -- s after joining before Auto judges anything (streaming / loading hitches)

function Quality.new(Config)
  local self = setmetatable({}, Quality)
  self.cfg = Config
  self.order = Config.TierOrder
  self.mode = "Auto"
  self.changed = Instance.new("BindableEvent")
  self.fps, self.acc, self.frames, self.age = 60, 0, 0, 0
  self.lowT, self.highT = 0, 0
  self.ceiling = nil       -- after Auto had to drop a tier it doesn't climb back past that tier (no flip-flopping)
  self.focused = true
  self.mobile = UIS.TouchEnabled and not UIS.KeyboardEnabled
  local ok, ugs = pcall(function() return UserSettings():GetService("UserGameSettings") end)
  self.ugs = ok and ugs or nil
  self.name = self:guess()
  if self.ugs then
    -- Roblox graphics level changed in the escape menu: guess again (Auto only)
    pcall(function()
      self.ugs:GetPropertyChangedSignal("SavedQualityLevel"):Connect(function()
        if self.mode == "Auto" then self.ceiling = nil; self:set(self:guess()) end
      end)
    end)
  end
  -- a window in the background gets throttled by Roblox: don't read that as "this PC is slow"
  UIS.WindowFocusReleased:Connect(function() self.focused = false end)
  UIS.WindowFocused:Connect(function() self.focused = true; self.lowT, self.highT = 0, 0 end)
  return self
end

function Quality:index(name)
  for i, n in ipairs(self.order) do if n == name then return i end end
  return 1
end

-- highest tier Auto may use on this device
function Quality:max()
  local m = #self.order
  if self.mobile then m = math.min(m, self:index(self.cfg.Auto.MobileMax)) end
  if self.ceiling then m = math.min(m, self.ceiling) end
  return m
end

-- first guess: the player's Roblox graphics level when they set one, else the device type
function Quality:guess()
  local A = self.cfg.Auto
  local level = 0
  if self.ugs then
    local ok, v = pcall(function() return self.ugs.SavedQualityLevel.Value end)
    if ok then level = v end
  end
  local name
  if level <= 0 then name = self.mobile and A.MobileStart or A.DesktopStart
  elseif level <= 3 then name = "Low"            -- Roblox itself turns shadows off below level 4
  elseif level <= 6 then name = "Medium"
  elseif level <= 8 then name = "High"
  else name = "Ultra" end
  return self.order[math.min(self:index(name), self:max())]
end

function Quality:set(name)
  if name == self.name then return end
  self.name = name
  self.changed:Fire(name)
end

-- "Auto" or a tier name (from the menu)
function Quality:choose(mode)
  self.mode = mode
  self.lowT, self.highT, self.ceiling = 0, 0, nil
  self:set(mode == "Auto" and self:guess() or mode)
end

function Quality:tier() return self.cfg.Tiers[self.name] end

-- call every frame with the frame's dt
function Quality:update(dt)
  self.age += dt
  self.acc += dt
  self.frames += 1
  if self.acc < 1 then return end
  self.fps = self.frames / self.acc
  self.acc, self.frames = 0, 0
  if self.mode ~= "Auto" or self.age < WARMUP or not self.focused then return end
  local A = self.cfg.Auto
  local i = self:index(self.name)
  self.lowT = self.fps < A.LowFps and self.lowT + 1 or 0
  self.highT = self.fps > A.HighFps and self.highT + 1 or 0
  local canDrop = i > self:index(A.Floor) or self.fps < A.VeryLowFps
  if self.lowT >= A.DropAfter and i > 1 and canDrop then
    self.lowT, self.highT = 0, 0
    self.ceiling = i - 1
    self:set(self.order[i - 1])
  elseif self.highT >= A.RiseAfter and i < self:max() then
    self.lowT, self.highT = 0, 0
    self:set(self.order[i + 1])
  end
end

return Quality
