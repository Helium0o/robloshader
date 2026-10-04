-- GRAPHICS menu (F3 or the pill under TUNE): Auto / Low / Medium / High / Ultra, with what each one does and the
-- frame rate you're getting. Admins (IsAdmin attribute, set by DriveableCarServer) also get a time-of-day preview
-- that only changes their own screen - handy for checking the looks without moving everyone's clock.
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local GraphicsMenu = {}

local PINK, TEXT, SOFT = Color3.fromRGB(255, 105, 165), Color3.fromRGB(200, 60, 120), Color3.fromRGB(150, 110, 175)
local SKY = Color3.fromRGB(120, 180, 240)
local MODES = {"Auto", "Low", "Medium", "High", "Ultra"}
local DESC = {
  Auto = "Recommended. Picks the best look your device runs smoothly and adjusts while you play.",
  Low = "Fastest. Colour grading only: no bloom, no sun rays, no light shadows from other cars.",
  Medium = "Soft glow and colour grading, a couple of nearby cars' lights cast shadows.",
  High = "Adds sun rays, showroom blur, more car light shadows and lamp light at night.",
  Ultra = "Everything on: the most lights and shadows at night. For strong PCs.",
}
local PREVIEW = {{"Live", nil}, {"Dawn", 5.9}, {"Noon", 12}, {"Golden", 16.6}, {"Sunset", 17.7}, {"Night", 22}}

local function corner(p, r) local c = Instance.new("UICorner"); c.CornerRadius = r or UDim.new(0, 12); c.Parent = p end
local function stroke(p, c, t) local s = Instance.new("UIStroke"); s.Color = c; s.Thickness = t or 2; s.Parent = p; return s end
local function txt(parent, text, size, col)
  local t = Instance.new("TextLabel")
  t.BackgroundTransparency = 1; t.Text = text; t.Font = Enum.Font.FredokaOne; t.TextSize = size
  t.TextColor3 = col or TEXT; t.TextXAlignment = Enum.TextXAlignment.Left; t.TextWrapped = true
  t.Size = UDim2.new(1, 0, 0, size + 4); t.Parent = parent
  return t
end
local function button(parent, text, w)
  local b = Instance.new("TextButton")
  b.Size = UDim2.new(0, w, 0, 28); b.Text = text; b.Font = Enum.Font.FredokaOne; b.TextSize = 15
  b.AutoButtonColor = true; b.Parent = parent
  corner(b, UDim.new(0, 10))
  return b
end
local function paint(b, on)
  b.BackgroundColor3 = on and PINK or Color3.new(1, 1, 1)
  b.TextColor3 = on and Color3.new(1, 1, 1) or TEXT
end
local function row(parent, order)
  local f = Instance.new("Frame")
  f.BackgroundTransparency = 1; f.Size = UDim2.new(1, 0, 0, 0); f.AutomaticSize = Enum.AutomaticSize.Y; f.LayoutOrder = order
  local g = Instance.new("UIGridLayout")
  g.CellSize = UDim2.new(0, 84, 0, 28); g.CellPadding = UDim2.new(0, 6, 0, 6); g.SortOrder = Enum.SortOrder.LayoutOrder; g.Parent = f
  f.Parent = parent
  return f
end

-- quality: Quality object; Config: the shared config; setPreview(hour or nil): local time preview
function GraphicsMenu.new(quality, Config, setPreview)
  local player = Players.LocalPlayer
  local gui = Instance.new("ScreenGui")
  gui.Name = "BubbleGraphicsGui"; gui.ResetOnSpawn = false; gui.DisplayOrder = 30
  gui.Parent = player:WaitForChild("PlayerGui")

  local pill = button(gui, "GRAPHICS  (F3)", 132)
  pill.Position = UDim2.new(0, 16, 0, 104); pill.Size = UDim2.new(0, 132, 0, 30)
  pill.BackgroundColor3 = SKY; pill.TextColor3 = Color3.new(1, 1, 1)
  stroke(pill, Color3.new(1, 1, 1), 2)

  local panel = Instance.new("Frame")
  panel.Position = UDim2.new(0, 16, 0, 142); panel.Size = UDim2.new(0, 300, 0, 0); panel.AutomaticSize = Enum.AutomaticSize.Y
  panel.BackgroundColor3 = Color3.fromRGB(255, 244, 249); panel.Visible = false; panel.Parent = gui
  corner(panel, UDim.new(0, 18)); stroke(panel, Color3.fromRGB(255, 120, 175), 3)
  local pad = Instance.new("UIPadding")
  pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 12), UDim.new(0, 14)
  pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 14), UDim.new(0, 14)
  pad.Parent = panel
  local list = Instance.new("UIListLayout")
  list.Padding = UDim.new(0, 8); list.SortOrder = Enum.SortOrder.LayoutOrder; list.Parent = panel

  local title = txt(panel, "✨  GRAPHICS", 20); title.LayoutOrder = 1
  local status = txt(panel, "", 14, SOFT); status.LayoutOrder = 2
  local modeRow = row(panel, 3)
  local desc = txt(panel, "", 14, SOFT); desc.LayoutOrder = 4; desc.Size = UDim2.new(1, 0, 0, 0); desc.AutomaticSize = Enum.AutomaticSize.Y

  local modeButtons = {}
  local function refresh()
    for m, b in pairs(modeButtons) do paint(b, m == quality.mode) end
    desc.Text = DESC[quality.mode] or ""
  end
  for i, m in ipairs(MODES) do
    local b = button(modeRow, m, 84); b.LayoutOrder = i
    b.Activated:Connect(function() quality:choose(m); refresh() end)
    modeButtons[m] = b
  end
  refresh()

  -- admins: preview a time of day on this screen only
  local previewButtons = {}
  local function previewRow()
    if panel:FindFirstChild("PreviewRow") then return end
    local head = txt(panel, "TIME PREVIEW  (only you see it)", 14, SOFT); head.LayoutOrder = 5; head.Name = "PreviewHead"
    local r = row(panel, 6); r.Name = "PreviewRow"
    for i, p in ipairs(PREVIEW) do
      local b = button(r, p[1], 84); b.LayoutOrder = i
      b.Activated:Connect(function()
        setPreview(p[2])
        for _, o in ipairs(previewButtons) do paint(o, o == b) end
      end)
      table.insert(previewButtons, b)
      paint(b, i == 1)
    end
  end
  if player:GetAttribute("IsAdmin") then previewRow() end
  player:GetAttributeChangedSignal("IsAdmin"):Connect(function() if player:GetAttribute("IsAdmin") then previewRow() end end)

  local function toggle() panel.Visible = not panel.Visible end
  pill.Activated:Connect(toggle)
  UIS.InputBegan:Connect(function(input, processed)
    if not processed and input.KeyCode == Config.MenuKey then toggle() end
  end)
  quality.changed.Event:Connect(refresh)

  task.spawn(function()
    while gui.Parent do
      if panel.Visible then
        local shown = quality.mode == "Auto" and ("Auto  >  " .. quality.name) or quality.name
        status.Text = string.format("%s   ·   %d fps", shown, math.floor(quality.fps + 0.5))
      end
      task.wait(0.5)
    end
  end)
  return gui
end

return GraphicsMenu
