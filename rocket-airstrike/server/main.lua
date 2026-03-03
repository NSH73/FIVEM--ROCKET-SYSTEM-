local QBCore = exports['qb-core']:GetCoreObject()
local playerCooldowns = {}
local allowedVehicleHashes = {}

local function debugLog(msg)
    if not Config.Debug then return end
    print(('[rocket-airstrike] %s'):format(msg))
end

local function buildAllowedVehicleHashes()
    allowedVehicleHashes = {}
    for _, model in ipairs(Config.AllowedVehicles or {}) do
        allowedVehicleHashes[joaat(model)] = true
    end
end

local function hasAccess(src)
    if Config.AccessMode == 'all' then
        return true
    end

    local player = QBCore.Functions.GetPlayer(src)
    if not player then
        return false
    end

    if Config.AccessMode == 'job' then
        local jobName = player.PlayerData.job and player.PlayerData.job.name
        for _, allowedJob in ipairs(Config.AllowedJobs or {}) do
            if allowedJob == jobName then
                return true
            end
        end
        return false
    end

    if Config.AccessMode == 'item' then
        local requiredItem = Config.RequiredItem
        if not requiredItem then return false end
        local item = player.Functions.GetItemByName(requiredItem)
        return item and (item.amount or 0) > 0
    end

    return false
end

local function getWeapon(weaponType)
    if not Config.Weapons then return nil end
    return Config.Weapons[weaponType]
end

local function isPlaneVehicle(vehicle, model)
    if not Config.RequirePlaneModelType then
        return true
    end

    if type(IsThisModelAPlane) == 'function' then
        return IsThisModelAPlane(model)
    end

    if type(GetVehicleClass) == 'function' then
        return GetVehicleClass(vehicle) == 16
    end

    if type(GetVehicleClassFromName) == 'function' then
        return GetVehicleClassFromName(model) == 16
    end

    -- Final fallback: keep whitelist functional even if class/model natives are unavailable.
    debugLog('Plane native unavailable on this runtime, using whitelist-only validation.')
    return true
end

local function getEntityNetId(entity)
    if type(NetworkGetNetworkIdFromEntity) == 'function' then
        return NetworkGetNetworkIdFromEntity(entity)
    end
    if type(VehToNet) == 'function' then
        return VehToNet(entity)
    end
    return 0
end

local function reject(src, weaponType, reason)
    TriggerClientEvent('rocket-airstrike:client:fireResult', src, {
        accepted = false,
        weaponType = weaponType,
        reason = reason
    })
end

local function accept(src, weaponType, nextReadyAt)
    TriggerClientEvent('rocket-airstrike:client:fireResult', src, {
        accepted = true,
        weaponType = weaponType,
        nextReadyAt = nextReadyAt
    })
end

local function buildVolleyImpact(baseImpact, missileIndex, missileCount, spreadRadius)
    if spreadRadius <= 0.0 or missileCount <= 1 then
        return baseImpact
    end

    local angle = ((missileIndex - 1) / missileCount) * (math.pi * 2.0)
    local randomRadius = spreadRadius * (0.35 + (math.random() * 0.65))

    return vector3(
        baseImpact.x + (math.cos(angle) * randomRadius),
        baseImpact.y + (math.sin(angle) * randomRadius),
        baseImpact.z
    )
end

RegisterNetEvent('rocket-airstrike:server:requestFire', function(weaponType, impactCoords, vehicleNetId)
    local src = source
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then
        return reject(src, weaponType, 'Invalid player ped.')
    end

    if type(weaponType) ~= 'string' then
        return reject(src, weaponType, 'Invalid weapon type.')
    end

    local weapon = getWeapon(weaponType)
    if not weapon then
        return reject(src, weaponType, 'Weapon mode is not configured.')
    end

    if type(impactCoords) ~= 'table' or not impactCoords.x or not impactCoords.y or not impactCoords.z then
        return reject(src, weaponType, 'Invalid impact coordinates.')
    end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        return reject(src, weaponType, 'You are not in a vehicle.')
    end

    if GetPedInVehicleSeat(vehicle, -1) ~= ped then
        return reject(src, weaponType, 'You must be the pilot.')
    end

    local model = GetEntityModel(vehicle)
    if not allowedVehicleHashes[model] then
        return reject(src, weaponType, 'Vehicle is not allowed.')
    end

    if not isPlaneVehicle(vehicle, model) then
        return reject(src, weaponType, 'Vehicle must be a plane.')
    end

    if not hasAccess(src) then
        return reject(src, weaponType, 'Access denied.')
    end

    if vehicleNetId ~= getEntityNetId(vehicle) then
        return reject(src, weaponType, 'Vehicle ownership validation failed.')
    end

    local impact = vector3(impactCoords.x + 0.0, impactCoords.y + 0.0, impactCoords.z + 0.0)
    local vehicleCoords = GetEntityCoords(vehicle)
    local maxAllowedDistance = (weapon.maxRange or 1000.0) + (Config.MaxImpactDistancePadding or 125.0)
    if #(impact - vehicleCoords) > maxAllowedDistance then
        return reject(src, weaponType, 'Impact point out of range.')
    end

    local now = GetGameTimer()
    playerCooldowns[src] = playerCooldowns[src] or {}
    local readyAt = playerCooldowns[src][weaponType] or 0
    if readyAt > now then
        return reject(src, weaponType, 'Weapon cooldown active.')
    end

    local cooldownMs = weapon.cooldownMs or 0
    local nextReadyAt = now + cooldownMs
    playerCooldowns[src][weaponType] = nextReadyAt

    accept(src, weaponType, nextReadyAt)

    local missileCount = math.max(1, math.floor(weapon.missilesPerShot or 1))
    local spreadRadius = (weapon.impactSpreadRadius or 0.0) + 0.0
    local launchZ = vehicleCoords.z + 1.0

    for i = 1, missileCount do
        local volleyImpact = buildVolleyImpact(impact, i, missileCount, spreadRadius)

        TriggerClientEvent('rocket-airstrike:client:createProjectile', -1, {
            launchCoords = {
                x = vehicleCoords.x,
                y = vehicleCoords.y,
                z = launchZ
            },
            coords = {
                x = volleyImpact.x,
                y = volleyImpact.y,
                z = volleyImpact.z
            },
            weaponHash = weapon.weaponHash or 'WEAPON_AIRSTRIKE_ROCKET',
            projectileSpeed = weapon.projectileSpeed or 320.0,
            bulletDamage = weapon.bulletDamage or 0,
            explosionType = weapon.explosionType or 4,
            damageScale = weapon.damageScale or 1.0,
            cameraShake = weapon.cameraShake or 1.0
        })
    end

    debugLog(('src=%s weapon=%s impact=%.2f,%.2f,%.2f'):format(src, weaponType, impact.x, impact.y, impact.z))
end)

AddEventHandler('playerDropped', function()
    playerCooldowns[source] = nil
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    buildAllowedVehicleHashes()
end)
