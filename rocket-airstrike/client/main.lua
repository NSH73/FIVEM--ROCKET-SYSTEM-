local QBCore = exports['qb-core']:GetCoreObject()

local state = {
    active = false,
    cam = nil,
    vehicle = 0,
    mode = 'recon',
    visionIndex = 1,
    yaw = 0.0,
    targetYaw = 0.0,
    pitch = (Config.Intel and Config.Intel.camera and Config.Intel.camera.defaultPitch) or -55.0,
    targetPitch = (Config.Intel and Config.Intel.camera and Config.Intel.camera.defaultPitch) or -55.0,
    fov = (Config.Intel and Config.Intel.camera and Config.Intel.camera.defaultFov) or 22.0,
    targetFov = (Config.Intel and Config.Intel.camera and Config.Intel.camera.defaultFov) or 22.0,
    zoomIndex = 1,
    weapon = Config.DefaultWeaponMode,
    allowedVehicleHashes = {},
    nextReadyAt = {},
    debugNotified = false,
    lockedTarget = nil,
    lastRaycast = nil
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

local function getIntelConfig()
    return Config.Intel or {}
end

local function getIntelCameraConfig()
    local intel = getIntelConfig()
    return intel.camera or Config.Camera or {}
end

local function getStabilizationConfig()
    local intel = getIntelConfig()
    return intel.stabilization or {}
end

local function getTargetLockConfig()
    local intel = getIntelConfig()
    return intel.targetLock or {}
end

local function getUiConfig()
    local intel = getIntelConfig()
    return intel.ui or {}
end

local function getControlConfig()
    local intel = getIntelConfig()
    return intel.controls or {}
end

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function round(value, decimals)
    local factor = 10 ^ (decimals or 0)
    return math.floor((value * factor) + 0.5) / factor
end

local function normalizeAngle(angle)
    return (angle + 360.0) % 360.0
end

local function angleDelta(target, current)
    return ((target - current + 540.0) % 360.0) - 180.0
end

local function smoothAngle(current, target, amount)
    return normalizeAngle(current + (angleDelta(target, current) * clamp(amount, 0.0, 1.0)))
end

local function smoothValue(current, target, amount)
    return current + ((target - current) * clamp(amount, 0.0, 1.0))
end

local function getVisionMode()
    local intel = getIntelConfig()
    local modes = intel.modes or { 'day', 'night_vision', 'thermal' }
    return modes[state.visionIndex] or modes[1] or 'day'
end

local function getControlLabel(controlId)
    local labels = {
        [38] = 'E',
        [44] = 'Q',
        [45] = 'R',
        [47] = 'G'
    }
    return labels[controlId] or tostring(controlId)
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

local function directionToRotation(direction)
    local yaw = math.deg(math.atan2(-direction.x, direction.y))
    local pitch = math.deg(math.atan2(direction.z, math.sqrt((direction.x * direction.x) + (direction.y * direction.y))))
    return normalizeAngle(yaw), pitch
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

local function drawLineRect(x, y, width, height, color)
    DrawRect(x, y - (height * 0.5), width, 0.0015, color.r, color.g, color.b, color.a)
    DrawRect(x, y + (height * 0.5), width, 0.0015, color.r, color.g, color.b, color.a)
    DrawRect(x - (width * 0.5), y, 0.0015, height, color.r, color.g, color.b, color.a)
    DrawRect(x + (width * 0.5), y, 0.0015, height, color.r, color.g, color.b, color.a)
end

local function drawReticle()
    local ui = getUiConfig()
    local accent = ui.accent or { r = 88, g = 255, b = 188, a = 225 }
    local warning = ui.warning or { r = 255, g = 124, b = 92, a = 225 }
    local color = state.mode == 'strike' and warning or accent
    local cx, cy = 0.5, 0.5

    DrawRect(cx, cy, 0.0012, 0.012, color.r, color.g, color.b, color.a)
    DrawRect(cx, cy, 0.012, 0.0012, color.r, color.g, color.b, color.a)

    DrawRect(cx, cy - 0.022, 0.0015, 0.010, color.r, color.g, color.b, math.floor(color.a * 0.9))
    DrawRect(cx, cy + 0.022, 0.0015, 0.010, color.r, color.g, color.b, math.floor(color.a * 0.9))
    DrawRect(cx - 0.022, cy, 0.010, 0.0015, color.r, color.g, color.b, math.floor(color.a * 0.9))
    DrawRect(cx + 0.022, cy, 0.010, 0.0015, color.r, color.g, color.b, math.floor(color.a * 0.9))

    if state.lockedTarget then
        drawLineRect(cx, cy, 0.060, 0.060, color)
    else
        drawLineRect(cx, cy, 0.040, 0.040, color)
    end
end

local function getZoomLevels()
    local cameraCfg = getIntelCameraConfig()
    local levels = cameraCfg.zoomLevels or { 55.0, 38.0, 26.0, 18.0, 12.0, 8.0 }
    return levels
end

local function getNearestZoomIndex(fov)
    local levels = getZoomLevels()
    local nearestIndex = 1
    local nearestDistance = math.huge

    for index, value in ipairs(levels) do
        local distance = math.abs(value - fov)
        if distance < nearestDistance then
            nearestDistance = distance
            nearestIndex = index
        end
    end

    return nearestIndex
end

local function setZoomIndex(index)
    local levels = getZoomLevels()
    state.zoomIndex = clamp(index, 1, #levels)
    state.targetFov = levels[state.zoomIndex]
end

local function getGimbalOrigin(vehicle)
    local cameraCfg = getIntelCameraConfig()
    local offset = cameraCfg.gimbalOffset or { x = 0.0, y = 3.6, z = -0.8 }
    return GetOffsetFromEntityInWorldCoords(vehicle, offset.x or 0.0, offset.y or 0.0, offset.z or 0.0)
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

    local _, hit, endCoords, _, entityHit = GetShapeTestResult(ray)
    return {
        hit = hit == 1,
        coords = hit == 1 and endCoords or farCoord,
        entity = entityHit or 0
    }
end

local function applyVisionMode()
    local mode = getVisionMode()

    SetNightvision(false)
    SetSeethrough(false)
    ClearTimecycleModifier()

    if mode == 'night_vision' then
        SetTimecycleModifier('heliGunCamNight')
        SetTimecycleModifierStrength(0.85)
        SetNightvision(true)
        return
    end

    if mode == 'thermal' then
        SetTimecycleModifier('scanline_cam_cheap')
        SetTimecycleModifierStrength(1.0)
        SetSeethrough(true)
        return
    end

    SetTimecycleModifier('heliGunCam')
    SetTimecycleModifierStrength(0.45)
end

local function clearVisionMode()
    SetNightvision(false)
    SetSeethrough(false)
    ClearTimecycleModifier()
end

local function cycleVisionMode()
    local intel = getIntelConfig()
    local modes = intel.modes or { 'day', 'night_vision', 'thermal' }
    state.visionIndex = state.visionIndex + 1
    if state.visionIndex > #modes then
        state.visionIndex = 1
    end

    applyVisionMode()

    local labels = {
        day = 'DAY',
        night_vision = 'NV',
        thermal = 'THERMAL'
    }
    notify(('Vision: %s'):format(labels[getVisionMode()] or string.upper(getVisionMode())), 'success')
end

local function clearTargetLock()
    state.lockedTarget = nil
end

local function toggleTargetLock()
    local lockCfg = getTargetLockConfig()
    if not lockCfg.enabled then
        notify('Target lock is disabled in config.', 'error')
        return
    end

    if state.lockedTarget then
        clearTargetLock()
        notify('Target lock released.', 'error')
        return
    end

    local raycast = state.lastRaycast
    if not raycast or not raycast.hit then
        notify('Aim at terrain or a valid target first.', 'error')
        return
    end

    local vehicleCoords = GetEntityCoords(state.vehicle)
    if #(raycast.coords - vehicleCoords) > (lockCfg.maxRange or 2200.0) then
        notify('Target is outside lock range.', 'error')
        return
    end

    state.lockedTarget = vector3(raycast.coords.x, raycast.coords.y, raycast.coords.z)
    notify('Target locked.', 'success')
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

local function createCam(vehicle)
    state.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    local origin = getGimbalOrigin(vehicle)
    SetCamCoord(state.cam, origin.x, origin.y, origin.z)
    SetCamRot(state.cam, state.pitch, 0.0, state.yaw, 2)
    SetCamFov(state.cam, state.fov)
    SetCamActive(state.cam, true)
    RenderScriptCams(true, true, 250, true, true)
    applyVisionMode()
end

local function destroyCam()
    if state.cam and DoesCamExist(state.cam) then
        SetCamActive(state.cam, false)
        DestroyCam(state.cam, false)
    end
    state.cam = nil
    RenderScriptCams(false, true, 250, true, true)
    ClearFocus()
    clearVisionMode()
end

local function setSystemActive(value)
    if value == state.active then return end
    state.active = value

    if not value then
        clearTargetLock()
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

local function toggleMode()
    if state.mode == 'recon' then
        state.mode = 'strike'
        notify('Mode: STRIKE', 'success')
        return
    end

    state.mode = 'recon'
    notify('Mode: RECON', 'primary')
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

local function drawHud(impactCoords, rangeMeters)
    local intel = getIntelConfig()
    local ui = getUiConfig()
    local controls = getControlConfig()
    local accent = ui.accent or { r = 88, g = 255, b = 188, a = 225 }
    local warning = ui.warning or { r = 255, g = 124, b = 92, a = 225 }
    local dim = ui.dim or { r = 180, g = 220, b = 205, a = 180 }
    local modeColor = state.mode == 'strike' and warning or accent
    local weaponData = getWeaponData(state.weapon)
    local now = GetGameTimer()
    local readyAt = state.nextReadyAt[state.weapon] or 0
    local cooldownLeft = math.max(0, readyAt - now)
    local zoomLevels = getZoomLevels()
    local zoomLevel = zoomLevels[state.zoomIndex] or state.targetFov
    local visionLabelMap = {
        day = 'DAY',
        night_vision = 'NV',
        thermal = 'THERMAL'
    }
    local title = intel.title or 'ROCKET ISR'
    local trackText = state.lockedTarget and 'LOCKED' or 'FREE'
    local weaponLabel = weaponData and weaponData.label or 'Standby'
    local targetText = ('TARGET %.0f %.0f %.0f'):format(impactCoords.x, impactCoords.y, impactCoords.z)
    local zoomDescriptor = ('Z%d / %.0fFOV'):format(state.zoomIndex, zoomLevel)

    DrawRect(0.5, 0.06, 0.38, 0.05, 0, 0, 0, 110)
    DrawRect(0.5, 0.94, 0.56, 0.06, 0, 0, 0, 105)
    DrawRect(0.14, 0.50, 0.002, 0.82, modeColor.r, modeColor.g, modeColor.b, 110)
    DrawRect(0.86, 0.50, 0.002, 0.82, modeColor.r, modeColor.g, modeColor.b, 110)

    drawText2D(0.365, 0.04, 0.42, title)
    drawText2D(0.355, 0.072, 0.32, ('MODE %s | VISION %s | %s'):format(string.upper(state.mode), visionLabelMap[getVisionMode()] or 'DAY', zoomDescriptor))
    drawText2D(0.235, 0.905, 0.34, ('TRACK %s | RANGE %sm | WEAPON %s | CD %.1fs'):format(trackText, round(rangeMeters, 0), weaponLabel, cooldownLeft / 1000.0))
    drawText2D(0.235, 0.934, 0.30, targetText)

    DrawRect(0.17, 0.14, 0.15, 0.055, 0, 0, 0, 95)
    DrawRect(0.83, 0.14, 0.15, 0.055, 0, 0, 0, 95)
    drawText2D(0.108, 0.125, 0.30, ('[%s] MODE'):format(getControlLabel(controls.modeToggle or 38)))
    drawText2D(0.108, 0.148, 0.30, ('[%s] VISION'):format(getControlLabel(controls.visionCycle or 45)))
    drawText2D(0.755, 0.125, 0.30, ('[%s] LOCK'):format(getControlLabel(controls.lockTarget or 47)))
    drawText2D(0.755, 0.148, 0.30, ('[%s] WEAPON'):format(getControlLabel(controls.weaponCycle or 44)))
    drawText2D(0.43, 0.964, 0.28, state.mode == 'strike' and '[LMB] FIRE  [J] EXIT' or '[SCROLL] ZOOM  [J] EXIT')

    DrawRect(0.50, 0.885, 0.34, 0.0015, dim.r, dim.g, dim.b, dim.a)
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

    local cameraCfg = getIntelCameraConfig()
    local stabilization = getStabilizationConfig()
    local controls = getControlConfig()
    local modeToggleControl = controls.modeToggle or 38
    local weaponCycleControl = controls.weaponCycle or 44
    local visionCycleControl = controls.visionCycle or 45
    local lockTargetControl = controls.lockTarget or 47
    local aimSmoothing = stabilization.aimSmoothing or 0.14
    local lockSmoothing = stabilization.lockSmoothing or 0.2
    local fovSmoothing = stabilization.fovSmoothing or 0.18

    DisableControlAction(0, 1, true)
    DisableControlAction(0, 2, true)
    DisableControlAction(0, 24, true)
    DisableControlAction(0, 69, true)
    DisableControlAction(0, 70, true)
    DisableControlAction(0, 75, true)
    DisableControlAction(0, 91, true)
    DisableControlAction(0, 92, true)
    DisableControlAction(0, modeToggleControl, true)
    DisableControlAction(0, weaponCycleControl, true)
    DisableControlAction(0, visionCycleControl, true)
    DisableControlAction(0, lockTargetControl, true)
    DisableControlAction(0, 241, true)
    DisableControlAction(0, 242, true)

    local lookX = GetDisabledControlNormal(0, 1)
    local lookY = GetDisabledControlNormal(0, 2)

    if state.lockedTarget then
        local lockCfg = getTargetLockConfig()
        local origin = getGimbalOrigin(vehicle)
        local targetDistance = #(state.lockedTarget - origin)
        if targetDistance > (lockCfg.maxRange or 2200.0) then
            clearTargetLock()
            notify('Target lock lost.', 'error')
        else
            local targetYaw, targetPitch = directionToRotation(state.lockedTarget - origin)
            state.targetYaw = targetYaw
            state.targetPitch = clamp(targetPitch, cameraCfg.pitchMin or -89.0, cameraCfg.pitchMax or -8.0)
        end
    else
        state.targetYaw = normalizeAngle(state.targetYaw - (lookX * (cameraCfg.yawSpeed or 7.0) * 2.5))
        state.targetPitch = clamp(
            state.targetPitch - (lookY * (cameraCfg.pitchSpeed or 5.5) * 2.5),
            cameraCfg.pitchMin or -89.0,
            cameraCfg.pitchMax or -8.0
        )
    end

    if IsDisabledControlJustPressed(0, 241) then
        setZoomIndex(state.zoomIndex + 1)
    elseif IsDisabledControlJustPressed(0, 242) then
        setZoomIndex(state.zoomIndex - 1)
    end

    local rotationSmoothing = state.lockedTarget and lockSmoothing or aimSmoothing
    state.yaw = smoothAngle(state.yaw, state.targetYaw, rotationSmoothing)
    state.pitch = smoothValue(state.pitch, state.targetPitch, rotationSmoothing)
    state.fov = smoothValue(state.fov, state.targetFov, fovSmoothing)

    local origin = getGimbalOrigin(vehicle)
    SetCamCoord(state.cam, origin.x, origin.y, origin.z)
    SetCamRot(state.cam, state.pitch, 0.0, state.yaw, 2)
    SetCamFov(state.cam, state.fov)

    local weaponData = getWeaponData(state.weapon)
    local raycastRange = math.max(
        (cameraCfg.maxRange or 2200.0),
        (weaponData and weaponData.maxRange) or 0.0,
        (getTargetLockConfig().maxRange or 2200.0)
    )
    state.lastRaycast = getRaycastImpact(raycastRange, vehicle)
    local impactCoords = state.lockedTarget or state.lastRaycast.coords
    local rangeMeters = #(impactCoords - origin)
    SetFocusPosAndVel(impactCoords.x, impactCoords.y, impactCoords.z, 0.0, 0.0, 0.0)

    if IsDisabledControlJustPressed(0, modeToggleControl) then
        toggleMode()
    end

    if IsDisabledControlJustPressed(0, visionCycleControl) then
        cycleVisionMode()
    end

    if IsDisabledControlJustPressed(0, lockTargetControl) then
        toggleTargetLock()
    end

    if IsDisabledControlJustPressed(0, weaponCycleControl) then
        if state.mode == 'strike' then
            switchWeapon()
        else
            notify('Weapon cycling is available in STRIKE mode.', 'error')
        end
    end

    if IsDisabledControlJustPressed(0, 24) then
        if state.mode == 'strike' then
            fireCurrentWeapon(impactCoords)
        else
            notify('Switch to STRIKE mode to fire.', 'error')
        end
    end

    drawReticle()
    drawHud(impactCoords, rangeMeters)
end

RegisterNetEvent('rocket-airstrike:client:toggleSystem', function()
    if state.active then
        setSystemActive(false)
        notify('ISR system disabled.', 'error')
        return
    end

    if Config.Intel and Config.Intel.enabled == false then
        notify('ISR system is disabled in config.', 'error')
        return
    end

    local ok, result = validatePilotVehicle()
    if not ok then
        notify(result, 'error')
        return
    end

    local cameraCfg = getIntelCameraConfig()
    local vehicle = result
    state.vehicle = vehicle
    state.mode = (Config.Intel and Config.Intel.defaultMode) or 'recon'
    state.visionIndex = 1
    state.yaw = normalizeAngle(GetEntityHeading(vehicle))
    state.targetYaw = state.yaw
    state.pitch = cameraCfg.defaultPitch or -55.0
    state.targetPitch = state.pitch
    state.zoomIndex = getNearestZoomIndex(cameraCfg.defaultFov or 22.0)
    state.fov = getZoomLevels()[state.zoomIndex]
    state.targetFov = state.fov
    state.lastRaycast = nil
    clearTargetLock()

    if not getWeaponData(state.weapon) then
        state.weapon = getWeaponOrder()[1]
    end

    createCam(vehicle)
    setSystemActive(true)
    notify('ISR system enabled.', 'success')
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

RegisterKeyMapping('airstrike_toggle', 'Toggle aircraft ISR system', 'keyboard', Config.ToggleKey or 'J')

CreateThread(function()
    buildAllowedVehicleHashes()
    local defaultWeapon = Config.DefaultWeaponMode
    if not getWeaponData(defaultWeapon) then
        state.weapon = getWeaponOrder()[1]
    end
    state.zoomIndex = getNearestZoomIndex(state.fov)
    state.targetFov = getZoomLevels()[state.zoomIndex]
    state.fov = state.targetFov
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
