local vehicleClasses = {
    [0] = true,
    [1] = true,
    [2] = true,
    [3] = true,
    [4] = true,
    [5] = true,
    [6] = true,
    [7] = true,
    [8] = true,
    [9] = true,
    [10] = true,
    [11] = true,
    [12] = true,
    [13] = true,
    [14] = false,
    [15] = false,
    [16] = false,
    [17] = true,
    [18] = true,
    [19] = true,
    [20] = true,
    [21] = false
}
local maxSpeed = 0
local useMph = SpeedLimiter.mph -- Set to true if you want to use mph, false for km/h
local speedLimiterEnabled = false
local limiterSpeed = 0.0
local resetSpeedOnEnter = true
local threadActive = false
local limiterPromise = promise.new()
local limiterType = 0 -- 0 = off, 1 = manual, 2 = auto mode
local lastVehicle = 0
local holding = false

local function TransformToSpeed(speed)
    local mult = 3.6
    if SpeedLimiter.mph then
        mult = 2.2369
    end
    return math.floor(speed * mult)
end

local function TransformFromSpeed(speed)
    local mult = 3.6
    if SpeedLimiter.mph then
        mult = 2.2369
    end
    return (speed) / mult
end

local function autoLimiterSpeed()
    local ped = GetPlayerPed(-1)
    local coords = GetEntityCoords(ped)
    local street = qbx.getStreetName(coords)
    local str = street['main']
    local spd = TransformFromSpeed(SpeedLimiter.citySpeed)
    if str:find('Fwy') or str:find('Freeway') or str:find('Route') or str:find('Highway') or str:find('Hwy') then
        spd = TransformFromSpeed(SpeedLimiter.highwaySpeed)
    end
    if not IsPointOnRoad(coords.x, coords.y, coords.z,-1) then
        spd = TransformFromSpeed(SpeedLimiter.offroadSpeed)
    end
    return spd
end

local function limiterThread() 
    while true do
        Citizen.Await(limiterPromise)
        local playerPed = GetPlayerPed(-1)
        local vehicle = GetVehiclePedIsIn(playerPed, false)
        if lastVehicle ~= vehicle and lastVehicle ~= 0 then
            maxSpeed = GetVehicleHandlingFloat(lastVehicle, "CHandlingData", "fInitialDriveMaxFlatVel")
            SetEntityMaxSpeed(lastVehicle, maxSpeed)
            lastVehicle = vehicle
        end
        if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == playerPed then
            if GetEntityHeightAboveGround(playerPed) > 2 then
                maxSpeed = GetVehicleHandlingFloat(vehicle, "CHandlingData", "fInitialDriveMaxFlatVel")
                SetEntityMaxSpeed(vehicle, maxSpeed)
                lastVehicle = 0
            elseif limiterType == 1 and lastVehicle ~= vehicle then
                SetEntityMaxSpeed(vehicle, limiterSpeed)
                lastVehicle = vehicle
            elseif limiterType == 2 then
                local newspeed = 0.0
                newspeed = autoLimiterSpeed()
                if limiterSpeed > newspeed then
                    limiterSpeed = limiterSpeed - 0.4
                elseif limiterSpeed < (newspeed - 0.4) then
                    limiterSpeed = limiterSpeed + 0.4
                elseif limiterSpeed < newspeed then
                    limiterSpeed = newspeed
                end
                SetEntityMaxSpeed(vehicle, limiterSpeed)
                lastVehicle = vehicle
            end
        end
        Citizen.Wait(250)
    end
end

local function toggleLimiter(longHold)
    local playerPed = GetPlayerPed(-1)
    local vehicle = GetVehiclePedIsIn(playerPed, false)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1)  ~= playerPed then
        return
    end
    if not vehicleClasses[GetVehicleClass(vehicle)] then
        exports.qbx_core:Notify('Vehicle does not support speed limiting', 'error')
        return
    end
    if GetEntityHeightAboveGround(playerPed) > 2 then
        exports.qbx_core:Notify('Cannot use limiter in the air', 'error')
        return
    end
    if lastVehicle ~= vehicle then
        maxSpeed = GetVehicleHandlingFloat(lastVehicle, "CHandlingData", "fInitialDriveMaxFlatVel")
        SetEntityMaxSpeed(lastVehicle, maxSpeed)
    end
    if longHold == false and limiterType ~= 2 then
        limiterType = 1
        maxSpeed = GetVehicleHandlingFloat(vehicle, "CHandlingData", "fInitialDriveMaxFlatVel")
        limiterSpeed = GetEntitySpeed(vehicle)
        if limiterSpeed <= TransformFromSpeed(SpeedLimiter.minSpeed) then
            limiterSpeed = TransformFromSpeed(SpeedLimiter.minSpeed)
            exports.qbx_core:Notify('Too slow, limiter set to '..SpeedLimiter.minSpeed, 'error')
        else
            exports.qbx_core:Notify('Speed limiter set to '..TransformToSpeed(limiterSpeed), 'success')
        end
        lastVehicle = vehicle
        SetEntityMaxSpeed(vehicle, limiterSpeed)
        limiterPromise:resolve()
    elseif longHold == true and limiterType == 0 then
        limiterType = 2
        limiterSpeed = GetEntitySpeed(vehicle)
        SetEntityMaxSpeed(vehicle, limiterSpeed)
        exports.qbx_core:Notify('Speed limiter set to automatic', 'success')
        limiterPromise:resolve()
    elseif longHold == true and limiterType ~= 0 then
        limiterType = 0
        maxSpeed = GetVehicleHandlingFloat(vehicle, "CHandlingData", "fInitialDriveMaxFlatVel")
        SetEntityMaxSpeed(lastVehicle, maxSpeed)
        exports.qbx_core:Notify('Speed limiter disabled', 'success')
    end
end

do
    ---@type KeybindProps
    local keybind = {
        name = 'qbx_smallresources',
        defaultKey = SpeedLimiter.defaultKey,
        defaultMapper = 'keyboard',
        description = 'Toggle Speed Limiter',
    }

    function keybind:onPressed()
        holding = true
        Citizen.Wait(SpeedLimiter.holdTime)
        if holding then
            holding = false
            toggleLimiter(true)
        end
        return
    end

    function keybind:onReleased()
        if holding then
            holding = false
            toggleLimiter(false)
        end
    end

    lib.addKeybind(keybind)
end

CreateThread(function()
    limiterThread()
end)