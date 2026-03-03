local QBCore = exports['qb-core']:GetCoreObject()

local state = {
    active = false,
    cam = nil,
    vehicle = 0,
    yaw = 0.0,
    pitch = -12.0,
    distance = Config.Camera.defaultDistance or 24.0,
    weapon = Config.DefaultWeaponMode,
    allowedVehicleHashes = {},
    nextReadyAt = {},
    debugNotified = false
}

local function notify(msg, msgType)
    if QBCore and QBCore.Functions and QBCore.Functions.Notify then
        QBCore.Functions.Notify(msg, msgType or 'primary')
    else
        print(('[rocket-airstrike] %s'):format(msg))
    end
end

local function buildAllowedVehicleHashes()
    state.allowedVehicleHashes = {}
    for _, model in ipairs(Config.AllowedVehicles or {}) do
        state.allowedVehicleHashes[joaat(model)] = true
    end
end

local function isVehicleAllowed(vehicle)
    if vehicle == 0 then return false end
    local model = GetEntityModel(vehicle)
    if not state.allowedVehicleHashes[model] then return false end
    if Config.RequirePlaneModelType and not IsThisModelAPlane(model) then return false end
    return true
end

local function hasAccess()
    if Config.AccessMode == 'all' then
        return true
    end

    local playerData = QBCore.Functions.GetPlayerData()
    if not playerData then
        return false
    end

    if Config.AccessMode == 'job' then
        local jobName = playerData.job and playerData.job.name
        for _, allowedJob in ipairs(Config.AllowedJobs or {}) do
            if allowedJob == jobName then
                return true
            end
        end
        return false
    end

    if Config.AccessMode == 'item' then
        local itemName = Config.RequiredItem
        if not itemName then return false end
        local items = playerData.items or {}
        for _, item in pairs(items) do
            if item and item.name == itemName and (item.amount or 0) > 0 then
                return true
            end
        end
        return false
    end

    return false
end

local function validatePilotVehicle()
    local ped = PlayerPedId()
    if IsEntityDead(ped) then
        return false, 'You cannot use airstrike while dead.'
    end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        return false, 'Enter a supported aircraft first.'
    end

    if GetPedInVehicleSeat(vehicle, -1) ~= ped then
        return false, 'You must be in the pilot seat.'
    end

    if not isVehicleAllowed(vehicle) then
        return false, 'This vehicle is not configured for airstrike.'
    end

    if not hasAccess() then
        return false, 'You are not allowed to use this system.'
    end

    return true, vehicle
end

local function rotationToDirection(rot)
    local z = math.rad(rot.z)
    local x = math.rad(rot.x)
    local cosX = math.cos(x)
    return vector3(-math.sin(z) * cosX, math.cos(z) * cosX, math.sin(x))
end

local function drawText2D(x, y, scale, text)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextScale(scale, scale)
    SetTextColour(255, 255, 255, 220)
    SetTextOutline()
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(x, y)
end

local function drawCrosshair()
    local cx, cy = 0.5, 0.5
    local s = 0.006
    DrawRect(cx, cy - 0.012, 0.0014, s, 255, 100, 80, 210)
    DrawRect(cx, cy + 0.012, 0.0014, s, 255, 100, 80, 210)
    DrawRect(cx - 0.008, cy, s, 0.002, 255, 100, 80, 210)
    DrawRect(cx + 0.008, cy, s, 0.002, 255, 100, 80, 210)
end

local function getWeaponOrder()
    local ordered = {}
    for _, key in ipairs(Config.WeaponOrder or {}) do
        if Config.Weapons[key] then
            ordered[#ordered + 1] = key
        end
    end

    if #ordered == 0 then
        for key, _ in pairs(Config.Weapons or {}) do
            ordered[#ordered + 1] = key
        end
    end
    return ordered
end

local function getWeaponData(key)
    return Config.Weapons and Config.Weapons[key]
end

local function getWeaponHash(weaponHashName)
    if type(weaponHashName) == 'number' then
        return weaponHashName
    end
    if type(weaponHashName) == 'string' and weaponHashName ~= '' then
        return joaat(weaponHashName)
    end
    return joaat('WEAPON_AIRSTRIKE_ROCKET')
end

local function getCurrentCooldownMs()
    local weaponData = getWeaponData(state.weapon)
    return weaponData and weaponData.cooldownMs or 0
end

local function getRaycastImpact(maxRange, ignoredEntity)
    local camCoord = GetCamCoord(state.cam)
    local camRot = GetCamRot(state.cam, 2)
    local dir = rotationToDirection(camRot)
    local farCoord = camCoord + (dir * maxRange)

    local ray = StartShapeTestRay(
        camCoord.x, camCoord.y, camCoord.z,
        farCoord.x, farCoord.y, farCoord.z,
        -1,
        ignoredEntity,
        0
    )
    local _, hit, endCoords = GetShapeTestResult(ray)
    if hit == 1 then
        return endCoords
    end
    return farCoord
end

local function createCam(vehicle)
    local vehicleCoords = GetEntityCoords(vehicle)
    state.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(state.cam, vehicleCoords.x, vehicleCoords.y - state.distance, vehicleCoords.z + 5.0)
    PointCamAtEntity(state.cam, vehicle, 0.0, 0.0, Config.Camera.targetZOffset or 1.8, true)
    SetCamActive(state.cam, true)
    RenderScriptCams(true, true, 250, true, true)
end

local function destroyCam()
    if state.cam and DoesCamExist(state.cam) then
        SetCamActive(state.cam, false)
        DestroyCam(state.cam, false)
    end
    state.cam = nil
    RenderScriptCams(false, true, 250, true, true)
end

local function setSystemActive(value)
    if value == state.active then return end
    state.active = value

    if not value then
        destroyCam()
        state.vehicle = 0
    end
end

local function fireCurrentWeapon(impactCoords)
    local weaponData = getWeaponData(state.weapon)
    if not weaponData then return end

    local now = GetGameTimer()
    local readyAt = state.nextReadyAt[state.weapon] or 0
    if readyAt > now then
        return
    end

    state.nextReadyAt[state.weapon] = now + (weaponData.cooldownMs or 0)
    TriggerServerEvent(
        'rocket-airstrike:server:requestFire',
        state.weapon,
        { x = impactCoords.x, y = impactCoords.y, z = impactCoords.z },
        VehToNet(state.vehicle)
    )
end

local function switchWeapon()
    local ordered = getWeaponOrder()
    if #ordered <= 1 then return end

    local currentIndex = 1
    for i = 1, #ordered do
        if ordered[i] == state.weapon then
            currentIndex = i
            break
        end
    end

    local nextIndex = currentIndex + 1
    if nextIndex > #ordered then
        nextIndex = 1
    end

    state.weapon = ordered[nextIndex]
    local weaponData = getWeaponData(state.weapon)
    notify(('Weapon: %s'):format((weaponData and weaponData.label) or state.weapon), 'success')
end

local function updateCamera()
    if not state.cam or not DoesCamExist(state.cam) then
        setSystemActive(false)
        return
    end

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or vehicle ~= state.vehicle or GetPedInVehicleSeat(vehicle, -1) ~= ped or IsEntityDead(ped) then
        setSystemActive(false)
        return
    end

    DisableControlAction(0, 1, true)
    DisableControlAction(0, 2, true)
    DisableControlAction(0, 24, true)
    DisableControlAction(0, 69, true)
    DisableControlAction(0, 70, true)
    DisableControlAction(0, 75, true)
    DisableControlAction(0, 91, true)
    DisableControlAction(0, 92, true)

    local lookX = GetDisabledControlNormal(0, 1)
    local lookY = GetDisabledControlNormal(0, 2)

    state.yaw = state.yaw - (lookX * (Config.Camera.yawSpeed or 6.0) * 2.5)
    state.pitch = state.pitch - (lookY * (Config.Camera.pitchSpeed or 5.5) * 2.5)
    state.pitch = math.min(Config.Camera.pitchMax or 40.0, math.max(Config.Camera.pitchMin or -70.0, state.pitch))

    if IsDisabledControlJustPressed(0, 241) then
        state.distance = math.max((Config.Camera.minDistance or 14.0), state.distance - (Config.Camera.zoomStep or 1.0))
    elseif IsDisabledControlJustPressed(0, 242) then
        state.distance = math.min((Config.Camera.maxDistance or 55.0), state.distance + (Config.Camera.zoomStep or 1.0))
    end

    local target = GetEntityCoords(vehicle)
    local yawRad = math.rad(state.yaw)
    local pitchRad = math.rad(state.pitch)
    local orbitDir = vector3(
        math.cos(pitchRad) * math.cos(yawRad),
        math.cos(pitchRad) * math.sin(yawRad),
        math.sin(pitchRad)
    )

    local camPos = target + (orbitDir * state.distance)
    SetCamCoord(state.cam, camPos.x, camPos.y, camPos.z + (Config.Camera.targetZOffset or 1.8))
    PointCamAtCoord(state.cam, target.x, target.y, target.z + (Config.Camera.targetZOffset or 1.8))

    local weaponData = getWeaponData(state.weapon)
    local impactCoords = getRaycastImpact((weaponData and weaponData.maxRange) or 1000.0, vehicle)

    if IsDisabledControlJustPressed(0, 38) then
        switchWeapon()
    end

    if IsDisabledControlJustPressed(0, 24) then
        fireCurrentWeapon(impactCoords)
    end

    drawCrosshair()

    local now = GetGameTimer()
    local readyAt = state.nextReadyAt[state.weapon] or 0
    local cooldownLeft = math.max(0, readyAt - now)
    local label = weaponData and weaponData.label or state.weapon
    local hudText = ('AIRSTRIKE | %s | CD: %.1fs | [E] Switch [J] Exit'):format(label, cooldownLeft / 1000.0)
    drawText2D(0.35, 0.92, 0.38, hudText)
end

RegisterNetEvent('rocket-airstrike:client:toggleSystem', function()
    if state.active then
        setSystemActive(false)
        notify('Airstrike camera disabled.', 'error')
        return
    end

    local ok, result = validatePilotVehicle()
    if not ok then
        notify(result, 'error')
        return
    end

    local vehicle = result
    state.vehicle = vehicle
    state.distance = Config.Camera.defaultDistance or state.distance
    state.yaw = GetEntityHeading(vehicle) + 180.0
    state.pitch = -12.0

    if not getWeaponData(state.weapon) then
        state.weapon = getWeaponOrder()[1]
    end

    createCam(vehicle)
    setSystemActive(true)
    notify('Airstrike camera enabled.', 'success')
end)

RegisterNetEvent('rocket-airstrike:client:fireResult', function(payload)
    if type(payload) ~= 'table' then return end
    if payload.accepted then
        local weapon = payload.weaponType
        if weapon and payload.nextReadyAt then
            state.nextReadyAt[weapon] = payload.nextReadyAt
        end
        return
    end

    if payload.weaponType then
        state.nextReadyAt[payload.weaponType] = 0
    end
    if payload.reason then
        notify(payload.reason, 'error')
    end
end)

RegisterNetEvent('rocket-airstrike:client:createExplosion', function(payload)
    if type(payload) ~= 'table' or type(payload.coords) ~= 'table' then
        return
    end

    local coords = vector3(payload.coords.x + 0.0, payload.coords.y + 0.0, payload.coords.z + 0.0)
    local ped = PlayerPedId()
    local pedCoords = GetEntityCoords(ped)
    if #(pedCoords - coords) > (Config.NetworkCullDistance or 2200.0) then
        return
    end

    AddExplosion(
        coords.x,
        coords.y,
        coords.z,
        payload.explosionType or 4,
        payload.damageScale or 1.0,
        true,
        false,
        payload.cameraShake or 1.0,
        false
    )
end)

RegisterNetEvent('rocket-airstrike:client:createProjectile', function(payload)
    if type(payload) ~= 'table' or type(payload.coords) ~= 'table' or type(payload.launchCoords) ~= 'table' then
        return
    end

    local launch = vector3(payload.launchCoords.x + 0.0, payload.launchCoords.y + 0.0, payload.launchCoords.z + 0.0)
    local impact = vector3(payload.coords.x + 0.0, payload.coords.y + 0.0, payload.coords.z + 0.0)
    local pedCoords = GetEntityCoords(PlayerPedId())
    local cullDistance = Config.NetworkCullDistance or 2200.0
    if #(pedCoords - impact) > cullDistance and #(pedCoords - launch) > cullDistance then
        return
    end

    local speed = payload.projectileSpeed or 320.0
    local weaponHash = getWeaponHash(payload.weaponHash)
    local bulletDamage = payload.bulletDamage or 0
    local ownerPed = PlayerPedId()

    ShootSingleBulletBetweenCoords(
        launch.x, launch.y, launch.z,
        impact.x, impact.y, impact.z,
        bulletDamage,
        true,
        weaponHash,
        ownerPed,
        true,
        false,
        speed
    )

    local distance = #(impact - launch)
    local travelMs = math.floor(math.min(6000, math.max(120, (distance / speed) * 1000)))

    CreateThread(function()
        Wait(travelMs)
        AddExplosion(
            impact.x,
            impact.y,
            impact.z,
            payload.explosionType or 4,
            payload.damageScale or 1.0,
            true,
            false,
            payload.cameraShake or 1.0,
            false
        )
    end)
end)

RegisterCommand('airstrike_toggle', function()
    TriggerEvent('rocket-airstrike:client:toggleSystem')
end, false)

RegisterKeyMapping('airstrike_toggle', 'Toggle aircraft airstrike camera', 'keyboard', Config.ToggleKey or 'J')

CreateThread(function()
    buildAllowedVehicleHashes()
    local defaultWeapon = Config.DefaultWeaponMode
    if not getWeaponData(defaultWeapon) then
        state.weapon = getWeaponOrder()[1]
    end
end)

CreateThread(function()
    while true do
        if state.active then
            Wait(0)
            updateCamera()
        else
            Wait(200)
        end
    end
end)

AddEventHandler('baseevents:onPlayerDied', function()
    if state.active then
        setSystemActive(false)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    setSystemActive(false)
end)
