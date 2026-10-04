-- The shared day clock (used by the server and every client). Pure maths plus three attributes on Lighting:
--   BubbleClockShare   share of the cycle (0..1) at the anchor moment
--   BubbleClockOrigin  the anchor moment, in server time (workspace:GetServerTimeNow())
--   BubbleClockLength  seconds per whole day (0 = time stands still)
-- Each client works the time out from the synced server clock, so everyone sees the same sky and nothing is
-- sent while the day goes by.
local Clock = {}
Clock.ATTR_SHARE, Clock.ATTR_ORIGIN, Clock.ATTR_LENGTH = "BubbleClockShare", "BubbleClockOrigin", "BubbleClockLength"

-- share of the cycle (0..1) -> clock hour (0..24) along the day curve ({share, hour} keyframes, both rising)
function Clock.hourAt(curve, share)
  share = share % 1
  for i = 1, #curve - 1 do
    local a, b = curve[i], curve[i + 1]
    if share <= b[1] then
      local t = b[1] > a[1] and (share - a[1]) / (b[1] - a[1]) or 0
      return (a[2] + (b[2] - a[2]) * t) % 24
    end
  end
  return curve[#curve][2] % 24
end

-- clock hour -> share of the cycle (the other way round: used when someone sets the time)
function Clock.shareAt(curve, hour)
  local h0 = curve[1][2]
  local h = h0 + (hour - h0) % 24            -- the same time of day, inside the curve's 24 hours
  for i = 1, #curve - 1 do
    local a, b = curve[i], curve[i + 1]
    if h <= b[2] then
      local t = b[2] > a[2] and (h - a[2]) / (b[2] - a[2]) or 0
      return (a[1] + (b[1] - a[1]) * t) % 1
    end
  end
  return 0
end

-- the current clock hour from the server's anchor, or nil when there is none (server script not installed)
function Clock.read(lighting, curve, serverNow)
  local share, origin = lighting:GetAttribute(Clock.ATTR_SHARE), lighting:GetAttribute(Clock.ATTR_ORIGIN)
  if type(share) ~= "number" or type(origin) ~= "number" then return nil end
  local length = lighting:GetAttribute(Clock.ATTR_LENGTH)
  if type(length) == "number" and length > 0 then share += (serverNow - origin) / length end
  return Clock.hourAt(curve, share)
end

return Clock
