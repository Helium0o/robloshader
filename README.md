# robloshader: Bubble Shaders for Bubblegum World

A lighting and post-processing ("shader") system for the Bubblegum World driving game.
It covers a shared day/night cycle, time-of-day colour grading, bloom, sun rays and atmosphere, plus a
showroom blur in customs and a colour kick when boosting.

At night the town lights up: house windows, porch lamps, traffic lights and lamp posts. Car light shadows run on
a budget, and each player picks a quality tier on their own (Auto by default).

Roblox has no custom shader code. A "shader" there means `Lighting`, `Atmosphere`, the post effects
(`ColorCorrection`, `Bloom`, `SunRays`, `DepthOfField`), materials and lights. This drives all of them every
frame from one set of looks.

## What it does in the game

| | |
|---|---|
| **Day / night** | One 20-minute day: a long bright day, slower golden hour and sunset, a shorter lavender night. Every player sees the same sky. The admin `time` command still works, and the cycle carries on from the time you set. |
| **Looks** | Nine keyframes (night, dawn, morning, noon, afternoon, golden, sunset, dusk, night), eased into each other. Each one sets lighting, lilac-tinted shadows, the pink atmosphere, grade, bloom and sun rays. |
| **Night lights** | 1,576 round house windows: 70% light up one by one through dusk, a few stay on into dawn. 200 porch lamps, 110 traffic tail lamps, headlight beams on the nearest traffic cars, and plaza lamp posts that are off by day. |
| **Car lights** | Every car light casts shadows, which are the most expensive thing in the scene. Each client keeps shadows on its own car plus the nearest few lit cars, and turns them off elsewhere. In daylight only your own car keeps them. |
| **Drift track** | The sky track gets clearer air and a little more punch, blended in as you arrive. |
| **Customs** | A soft background blur keeps your car sharp (High and Ultra), with a touch more contrast. |
| **Boost** | A short saturation, exposure and bloom kick on your own screen. It follows your F2 camera mode: Steady gives none, Comfort a gentle one. |
| **GRAPHICS menu** | F3, or the pill under TUNE. Auto / Low / Medium / High / Ultra, with your live FPS. Admins also get a time-of-day preview that only changes their own screen. |

## Built for multiplayer

- **Rendering never touches the network.** All effects run in a LocalScript, and client changes to `Lighting`
  are never sent anywhere.
- **The server stores three attributes on `Lighting`** (cycle share, an anchor moment in server time, and the
  cycle length). It writes them once at start and again whenever someone sets the time. Each client computes
  the time from `workspace:GetServerTimeNow()`, so 30 players stay in sync with no per-frame traffic.
- **The same windows light up for everyone with no syncing.** Which windows light, and when, comes from a hash
  of each window's position, so every client makes the same choice.
- **Each player gets their own tier.** Auto guesses from the device and the player's Roblox graphics level,
  then measures FPS: it drops a tier when FPS stays low, never flip-flops back up, and ignores a window that's
  in the background. Phones are capped at High.
- **Light budgets scale with player count.** Car light shadows go only to the N nearest lit cars, so a full
  server at night costs the same as a quiet one. Porch lamp and traffic beam lights are a small pool that moves
  to whatever is near your camera.
- **Streaming-safe.** Night-light parts are tagged once by the server (`CollectionService`). Tags replicate and
  follow `StreamingEnabled`, and pooled lights recover when their part streams out.
- **No fighting your scripts.** The server's car light states (on, brake, reverse) are never touched; the client
  only changes the `Shadows` flag and puts it back if something else changes it. The place's own Atmosphere,
  Bloom, SunRays and DepthOfField are adopted rather than duplicated.

## Install

**Option A: patched place.** `tools/build` writes a copy of your place with everything installed. It also sets
the place's static Lighting to the server-start look, so Studio and the first frame after joining already match.

```
lune run tools/build bubblegum_world.rbxl bubblegum_world_shaders.rbxl
```

**Option B: Rojo.** `rojo serve` with `default.project.json` syncs only these three scripts into your open place
(`$ignoreUnknownInstances` leaves everything else alone):

| Path in the place | Source |
|---|---|
| `ReplicatedStorage.BubbleShaders` | `src/shared/BubbleShaders` (Config, Looks, Clock, Blend) |
| `ServerScriptService.BubbleShadersServer` | `src/server/BubbleShadersServer.server.luau` |
| `StarterPlayer.StarterPlayerScripts.BubbleShadersClient` | `src/client/BubbleShadersClient` (+ Quality, PostFx, CarLightLod, NightLights, GraphicsMenu) |

Place files are git-ignored on purpose: this repository is public, so the game itself never goes in it.

## Tuning

Everything lives in two modules:

- **`Config.luau`** holds:
  - the cycle (`DayCycle.Enabled`, `Minutes`, `StartClock`) and how the day is spread (`DayCurve`);
  - the sun's latitude;
  - quality tiers and the Auto thresholds;
  - zones (world boxes with their own look);
  - the boost kick;
  - which parts count as night lights (matched by folder, colour, shape and size).
- **`Looks.luau`** holds the keyframes. Every keyframe has every key. Zones and moments use `set` to move toward a
  value, `add` to add, and `mul` to multiply, all blended by weight.

To turn the cycle off, set `Config.DayCycle.Enabled = false`. The time then stays wherever the server's
`Lighting.ClockTime` is, and the looks still follow it.

Server code that needs the current hour:

```lua
Clock.read(Lighting, Config.DayCurve, workspace:GetServerTimeNow())
```

| Tier | Bloom | Sun rays | DOF (customs) | Cars with light shadows | Porch lights | Traffic beams |
|---|---|---|---|---|---|---|
| Low | – | – | – | your own only | 0 | 0 |
| Medium | 80% | – | – | 2 within 90 studs | 4 | 3 |
| High | ✓ | ✓ | ✓ | 4 within 140 studs | 8 | 6 |
| Ultra | ✓ | ✓ | ✓ | 8 within 220 studs | 14 | 10 |

## Checking it

```
selene generate-roblox-std && selene src tests
lune run tests/looks                       # clock maths, ranges, every key in every look, tier / zone config
lune run tests/simulate <place.rbxl>       # runs the server + client scripts against the real place
```

`tests/simulate` loads the place into a small mock engine. That engine provides properties, signals, tags,
attributes, a task scheduler and a fake server clock. The test then runs the real scripts through a whole day and
checks the following:
- tagging
- the clock wrapping once per cycle
- the admin time change
- windows and porch lamps at night
- the car-light shadow budget, including the server turning a far car's shadows back on
- boost, the customs blur, the sky-track zone
- Auto dropping a tier at 25 fps without flip-flopping

## Good to know

- **The looks were tuned without Roblox's renderer.** The values sit inside the documented ranges and were checked
  against approximate previews, so expect to nudge `Looks.luau` after a look in Studio. Use the admin time
  preview in the F3 menu.
- **Keep `Lighting.LightingStyle` at Realistic with `PrioritizeLightingQuality` on.** That is how the place is set
  now, and both are Studio-only settings.
- **Roblox turns some effects off on low graphics levels.** It disables shadows below level 4 and may turn some
  post effects off, so low-end players get less no matter what this system asks for.
- **To see the cost**, open the MicroProfiler and look at `ShadowMapSystem` and `computeLightingPerform`. Car
  light shadows are what the budget controls.
- **Optional next steps:**
  - MaterialVariants (texture maps can only be set in Studio, not from scripts);
  - remembering the F3 choice with your existing player save;
  - Terrain `Clouds` for the sunset sky.
