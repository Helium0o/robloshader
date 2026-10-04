-- Look blending. Everything writes into a table the caller keeps (no garbage per frame).
local Blend = {}

local function smooth(t) return t * t * (3 - 2 * t) end
local function mix(a, b, t)
  if type(a) == "number" then return a + (b - a) * t end
  return a:Lerp(b, t)                         -- Color3
end
Blend.mix = mix

-- the look at `hour` from {hour, look} keyframes (rising; the last one blends into the first one 24 h later)
function Blend.sampleDay(out, frames, hour)
  local n = #frames
  local a, b, t = frames[1][2], frames[1][2], 0
  for i = 1, n do
    local h0, h1 = frames[i][1], frames[i % n + 1][1]
    if i == n then h1 += 24 end
    local h = hour
    if h < h0 then h += 24 end                -- (only the wrap-round pair can contain it then)
    if h >= h0 and h < h1 then
      a, b, t = frames[i][2], frames[i % n + 1][2], smooth((h - h0) / (h1 - h0))
      break
    end
  end
  for k, v in pairs(a) do out[k] = mix(v, b[k], t) end
  return out
end

-- a zone / moment on top, by weight w (0..1): set = move toward, add = add, mul = multiply
function Blend.zone(out, zone, w)
  if not zone or w <= 0.001 then return out end
  if zone.set then for k, v in pairs(zone.set) do out[k] = mix(out[k], v, w) end end
  if zone.mul then for k, v in pairs(zone.mul) do out[k] *= 1 + (v - 1) * w end end
  if zone.add then for k, v in pairs(zone.add) do out[k] += v * w end end
  return out
end

-- 1 inside the box, fading to 0 at `fade` studs outside it
function Blend.boxWeight(pos, min, max, fade)
  local dx = math.max(min.X - pos.X, 0, pos.X - max.X)
  local dy = math.max(min.Y - pos.Y, 0, pos.Y - max.Y)
  local dz = math.max(min.Z - pos.Z, 0, pos.Z - max.Z)
  local d = math.sqrt(dx * dx + dy * dy + dz * dz)
  return 1 - math.clamp(d / math.max(fade, 0.001), 0, 1)
end

return Blend
