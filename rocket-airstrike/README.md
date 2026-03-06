# rocket-airstrike

QBCore aircraft ISR + airstrike system for configured planes (default: `raiju`).

## Features

- Toggle ISR mode with `J` (`airstrike_toggle` command).
- Dedicated ISR gimbal camera with stabilized yaw/pitch.
- Multi-stage ground zoom driven by camera FOV.
- Recon and strike modes in the same system.
- Day, night vision, and thermal viewing modes.
- Target lock on terrain / observed points.
- Raycast targeting with ISR HUD and tactical reticle.
- Two default strike modes:
  - `guided_missile`
  - `drop_bomb`
- Server-side validation for:
  - pilot seat
  - allowed vehicle model
  - access mode (`all/job/item`)
  - per-player per-weapon cooldown
  - range sanity check

## Install

1. Keep folder at:
   - `resources/ROCKET-SYSTEM/rocket-airstrike`
2. Add to `server.cfg`:
   - `ensure rocket-airstrike`
3. Restart resource/server.

## Configure

Edit `config.lua`:

- `Config.AllowedVehicles` to choose supported aircraft.
- `Config.AccessMode` (`all`, `job`, `item`).
- `Config.Intel` for ISR camera, zoom, HUD, lock, and vision behavior.
- `Config.Weapons` for damage/range/cooldown per strike type.
- `Config.Camera` remains aliased to the ISR camera config for compatibility.

## Controls (while active)

- `J`: Toggle system on/off
- `Mouse`: Move ISR gimbal
- `Scroll`: Zoom stages
- `E`: Toggle `RECON` / `STRIKE`
- `R`: Cycle vision (`DAY` / `NV` / `THERMAL`)
- `G`: Lock / unlock target
- `Q`: Cycle strike weapon
- `LMB`: Fire selected strike mode in `STRIKE`

## Add More Vehicle Models

```lua
Config.AllowedVehicles = {
    'raiju',
    'lazer',
    'hydra'
}
```

## Add More Weapon Modes

```lua
Config.WeaponOrder = { 'guided_missile', 'drop_bomb', 'cluster' }

Config.Weapons.cluster = {
    label = 'Cluster Strike',
    maxRange = 900.0,
    cooldownMs = 7000,
    explosionType = 2,
    damageScale = 1.9,
    cameraShake = 1.3
}
```

## ISR Config Example

```lua
Config.Intel = {
    enabled = true,
    title = 'ROCKET ISR',
    defaultMode = 'recon',
    modes = { 'day', 'night_vision', 'thermal' },
    camera = {
        maxRange = 2200.0,
        gimbalOffset = { x = 0.0, y = 3.6, z = -0.8 },
        defaultPitch = -55.0,
        defaultFov = 22.0,
        zoomLevels = { 55.0, 38.0, 26.0, 18.0, 12.0, 8.0 }
    },
    stabilization = {
        aimSmoothing = 0.14,
        lockSmoothing = 0.2,
        fovSmoothing = 0.18
    },
    targetLock = {
        enabled = true,
        maxRange = 2200.0
    }
}
```
