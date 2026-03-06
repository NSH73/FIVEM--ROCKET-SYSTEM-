Config = {}

Config.Debug = false
Config.BalanceProfile = 'medium'
Config.ToggleKey = 'J'
Config.AccessMode = 'all' -- all | job | item
Config.DefaultWeaponMode = 'guided_missile'
Config.WeaponOrder = { 'guided_missile', 'drop_bomb' }

Config.AllowedVehicles = {
    'raiju'
}

Config.AllowedJobs = {
    'police',
    'army'
}

Config.RequiredItem = 'airstrike_tablet'
Config.RequirePlaneModelType = true

Config.NetworkCullDistance = 2200.0
Config.MaxImpactDistancePadding = 125.0

Config.Intel = {
    enabled = true,
    title = 'ROCKET ISR',
    defaultMode = 'recon',
    modes = { 'day', 'night_vision', 'thermal' },
    controls = {
        modeToggle = 38, -- E
        weaponCycle = 44, -- Q
        visionCycle = 45, -- R
        lockTarget = 47 -- G
    },
    camera = {
        maxRange = 2200.0,
        gimbalOffset = { x = 0.0, y = 3.6, z = -0.8 },
        yawSpeed = 7.0,
        pitchSpeed = 5.5,
        pitchMin = -89.0,
        pitchMax = -8.0,
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
    },
    ui = {
        accent = { r = 88, g = 255, b = 188, a = 225 },
        warning = { r = 255, g = 124, b = 92, a = 225 },
        dim = { r = 180, g = 220, b = 205, a = 180 }
    }
}

Config.Camera = Config.Intel.camera

Config.Weapons = {
    guided_missile = {
        label = 'Guided Missile',
        maxRange = 1800.0,
        cooldownMs = 5200,
        weaponHash = 'WEAPON_RPG',
        projectileSpeed = 450.0,
        bulletDamage = 0,
        missilesPerShot = 6,
        impactSpreadRadius = 12.0,
        explosionType = 59,
        damageScale = 3.0,
        cameraShake = 1.8
    },
    drop_bomb = {
        label = 'Drop Bomb',
        maxRange = 1050.0,
        cooldownMs = 7000,
        weaponHash = 'WEAPON_HOMINGLAUNCHER',
        projectileSpeed = 260.0,
        bulletDamage = 0,
        missilesPerShot = 6,
        impactSpreadRadius = 18.0,
        explosionType = 59,
        damageScale = 3.6,
        cameraShake = 2.2
    }
}
