# rocket-airstrike

QBCore aircraft camera + airstrike system for configured planes (default: `raiju`).

## Features

- Toggle mode with `J` (`airstrike_toggle` command).
- 360 orbit camera around aircraft.
- Raycast targeting with on-screen crosshair.
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
- `Config.Weapons` for damage/range/cooldown per strike type.
- `Config.Camera` for orbit and zoom behavior.

## Controls (while active)

- `J`: Toggle system on/off
- `Mouse`: Rotate camera
- `Scroll`: Zoom
- `LMB`: Fire selected mode
- `E`: Switch weapon mode

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
