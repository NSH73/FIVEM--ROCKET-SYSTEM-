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

Config.Camera = {
    minDistance = 14.0,
    maxDistance = 55.0,
    defaultDistance = 24.0,
    zoomStep = 1.0,
    yawSpeed = 6.0,
    pitchSpeed = 5.5,
    pitchMin = -70.0,
    pitchMax = 40.0,
    targetZOffset = 1.8
}

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
