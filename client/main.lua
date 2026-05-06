-- ====================================================================================
-- AIBus - Final Unified client.lua (Verified Complete)
-- ====================================================================================

-- Global Variables
local QBCore = exports['qb-core']:GetCoreObject()
local PlayerData = {}
local createdEntities, blips, busProgress, ownedBuses = {}, {}, {}, {}

-- Player State
local inBus, currentBus, requestedStop = false, nil, false
local busRequestedAtStop, requestedBusNetId, trackedBusNetId, lastPlayerStop = nil, nil, nil, nil

-- UI State
local isTimetableOpen = false
local textDisplayInfo = { shouldDraw = false, coords = nil, text = "", action = nil }
local inBusText = ""

-- ====================================================================================
-- CORE FUNCTIONS
-- ====================================================================================

function getOnBus(bus)
    local ped = PlayerPedId()
    local emptySeat = nil
    for i = 1, 15 do if IsVehicleSeatFree(bus, i) then emptySeat = i; break end end
    if emptySeat then
        TaskWarpPedIntoVehicle(ped, bus, emptySeat)
        inBus, currentBus = true, bus

        -- FIX: Check if trackedBusNetId is not nil before using it as an index
        if trackedBusNetId and blips[trackedBusNetId] and DoesBlipExist(blips[trackedBusNetId]) then
            RemoveBlip(blips[trackedBusNetId])
        end
        
        -- Also check if the bus the player is boarding has a blip, even if it wasn't the tracked one
        local busNetId = VehToNet(bus)
        if blips[busNetId] and DoesBlipExist(blips[busNetId]) then
            RemoveBlip(blips[busNetId])
            blips[busNetId] = nil
        end

        trackedBusNetId, busRequestedAtStop, requestedBusNetId = nil, nil, nil
        QBCore.Functions.Notify("You have boarded the bus.", "primary")
    else
        QBCore.Functions.Notify("The bus is full.", "error")
    end
end
function getOffBus()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == currentBus then
        TaskLeaveVehicle(ped, vehicle, 0)
        inBus, currentBus, requestedStop = false, nil, false
        SendNUIMessage({ action = 'hideStoppingSign' })
        QBCore.Functions.Notify("You have left the bus.", "primary")
    end
end

function isBusAtAStop(bus)
    if not bus or not DoesEntityExist(bus) or GetEntitySpeed(bus) > 0.5 then return false end
    local busCoords = GetEntityCoords(bus)
    for _, route in ipairs(Config.Routes) do
        for _, stop in ipairs(route.Stops) do
            if #(busCoords - vector3(stop.x, stop.y, stop.z)) < Config.StopZoneRadius then
                return true
            end
        end
    end
    return false
end

-- RESTORED: Function to check if spawn area is clear
function IsSpawnAreaClear(coords)
    if not coords then return false end
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) and #(GetEntityCoords(vehicle, true) - coords) < 10.0 then
            return false
        end
    end
    for _, ped in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(ped) and not IsPedAPlayer(ped) and #(GetEntityCoords(ped, true) - coords) < 5.0 then
            return false
        end
    end
    return true
end

-- RESTORED: Function to clean up old buses on script start
function CleanupExistingBuses()
    if Config.Debug then print('[AIBus] Running cleanup of old AI buses...') end
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) then
            local isAnAiBus = false
            for _, route in ipairs(Config.Routes) do
                if GetEntityModel(vehicle) == GetHashKey(route.BusModel) then isAnAiBus = true; break end
            end
            if isAnAiBus then
                local plate = GetVehicleNumberPlateText(vehicle):gsub("^%s+", ""):gsub("%s+$", "")
                if plate:match("^"..Config.BusPlate) then
                    local driver = GetPedInVehicleSeat(vehicle, -1)
                    if driver and not IsPedAPlayer(driver) and DoesEntityExist(driver) then DeleteEntity(driver) end
                    DeleteEntity(vehicle)
                end
            end
        end
    end
end

-- ====================================================================================
-- EMOTE, UI & SOUND FUNCTIONS
-- ====================================================================================

function PlayHailBusEmote()
    local playerPed = PlayerPedId()
    local animDict = "gestures@m@standing@casual"
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do Wait(50) end
    TaskPlayAnim(playerPed, animDict, "gesture_hand_up", 8.0, -8.0, 3000, 0, 0, false, false, false)
    CreateThread(function() Wait(4000); RemoveAnimDict(animDict) end)
end

function ShowStoppingSign()
    SendNUIMessage({ action = 'showStoppingSign' })
    PlaySoundFrontend(-1, "Bus_Request_Stop", "DLC_APT_Apartment_SoundSet", true)
end

function DrawText3D(x, y, z, text)
    SetTextScale(0.35, 0.35); SetTextFont(4); SetTextProportional(1); SetTextColour(255, 255, 255, 215)
    SetTextEntry("STRING"); SetTextCentre(true); AddTextComponentString(text); SetDrawOrigin(x, y, z, 0)
    DrawText(0.0, 0.0); local factor = (string.len(text)) / 370
    DrawRect(0.0, 0.0 + 0.0125, 0.017 + factor, 0.03, 0, 0, 0, 75); ClearDrawOrigin()
end

function DrawText2D(x, y, text)
    SetTextFont(4); SetTextProportional(1); SetTextScale(0.0, 0.4); SetTextColour(255, 255, 255, 255)
    SetTextDropshadow(0, 0, 0, 0, 255); SetTextEdge(1, 0, 0, 0, 255); SetTextDropShadow(); SetTextOutline()
    SetTextEntry("STRING"); AddTextComponentString(text); DrawText(x, y)
end

-- ====================================================================================
-- BUS DRIVING & MANAGEMENT
-- ====================================================================================

function driveBus(bus, driver, route, startStopIndex)
    local currentStopIndex = startStopIndex
    local busNetId = VehToNet(bus)
    CreateThread(function()
        -- Variables to track passenger state for despawning
        local stopsSinceEmpty = 0 
        local wasPreviouslyOccupied = false
        local distanceCheckTimer = GetGameTimer() -- FIX: Corrected function name

        busProgress[busNetId] = currentStopIndex
        if Config.Debug then print(('[AIBus] [Owner: %s] Drive thread STARTED for bus %s.'):format(GetPlayerServerId(PlayerId()), busNetId)) end
        local initialStopVec = route.Stops[currentStopIndex]
        TaskVehicleDriveToCoordLongrange(driver, bus, initialStopVec.x, initialStopVec.y, initialStopVec.z, 15.0, Config.DrivingFlags, 10.0)
        
        while DoesEntityExist(bus) and DoesEntityExist(driver) and ownedBuses[busNetId] do
            -- NEW: Periodically check distance to player for despawning
            if GetGameTimer() > distanceCheckTimer + 15000 then -- Check every 15 seconds
                local playerPed = PlayerPedId()
                if DoesEntityExist(playerPed) then
                    local distance = #(GetEntityCoords(playerPed) - GetEntityCoords(bus))
                    if distance > (Config.PlayerActivationRadius or 800.0) and GetVehicleNumberOfPassengers(bus) == 0 then
                        if Config.Debug then print(('[AIBus] Bus %s is too far from its owner and is empty. Despawning.'):format(busNetId)) end
                        TriggerServerEvent("AIBus:server:removeRogueBus", busNetId, route.Name)
                        DeleteEntity(bus)
                        break -- Exit the driving loop
                    end
                end
                distanceCheckTimer = GetGameTimer() -- Reset timer
            end

            local stopCoord = vector3(route.Stops[currentStopIndex].x, route.Stops[currentStopIndex].y, route.Stops[currentStopIndex].z)
            local inZone = false
            while DoesEntityExist(bus) and ownedBuses[busNetId] and not inZone do
                Wait(250)
                if #(GetEntityCoords(bus) - stopCoord) <= Config.StopZoneRadius then inZone = true end
            end
            if not (DoesEntityExist(bus) and DoesEntityExist(driver) and ownedBuses[busNetId]) then break end
            
            ClearPedTasks(driver)
            SetVehicleBrakeLights(bus, true)
            local timeout = 0
            while GetEntitySpeed(bus) > 0.1 and timeout < 50 do SetVehicleForwardSpeed(bus, 0.0); Wait(50); timeout = timeout + 1 end
            SetVehicleHandbrake(bus, true)
            local waitTime = Config.StopWaitTime
            if requestedStop and inBus and currentBus == bus then waitTime = Config.StopRequestWaitTime; getOffBus() end

            local frozenPeds, stoppedVehicles = {}, {}
            local busCoords = GetEntityCoords(bus)
            for _, ped in ipairs(GetGamePool('CPed')) do
                if DoesEntityExist(ped) and not IsPedAPlayer(ped) and #(GetEntityCoords(ped) - busCoords) < 25.0 then
                    if not IsPedInAnyVehicle(ped, false) then
                        TaskStandStill(ped, -1)
                        table.insert(frozenPeds, ped)
                    end
                end
            end
for _, veh in ipairs(GetGamePool('CVehicle')) do
    if DoesEntityExist(veh) and veh ~= bus and #(GetEntityCoords(veh) - busCoords) < 30.0 then
        local vehDriver = GetPedInVehicleSeat(veh, -1)
        if DoesEntityExist(vehDriver) and not IsPedAPlayer(vehDriver) then
            -- Task the driver to stand still indefinitely, which stops the vehicle.
            TaskStandStill(vehDriver, -1) 
            table.insert(stoppedVehicles, vehDriver)
        end
    end
end
            SetVehicleIndicatorLights(bus, 0, true); SetVehicleIndicatorLights(bus, 1, true)
            local timeWaited = 0
            while timeWaited < waitTime and ownedBuses[busNetId] do SetVehicleForwardSpeed(bus, 0.0); SetVehicleHandbrake(bus, true); Wait(100); timeWaited = timeWaited + 100 end
            
            -- Check passenger count and update despawn logic
            if DoesEntityExist(bus) then
                local passengerCount = GetVehicleNumberOfPassengers(bus)
                if passengerCount > 0 then
                    wasPreviouslyOccupied = true -- Mark that the bus has had passengers
                    stopsSinceEmpty = 0 -- Reset counter
                else
                    stopsSinceEmpty = stopsSinceEmpty + 1
                    if Config.Debug then print(('[AIBus] Bus %s is empty. Stops since empty: %d.'):format(busNetId, stopsSinceEmpty)) end
                end

                -- Check despawn conditions
                local shouldDespawn = false
                if wasPreviouslyOccupied and stopsSinceEmpty >= 3 then
                    if Config.Debug then print(('[AIBus] Bus %s was occupied and is now empty for 3 stops. Despawning.'):format(busNetId)) end
                    shouldDespawn = true
                elseif stopsSinceEmpty >= 10 then -- For buses that were always empty
                    if Config.Debug then print(('[AIBus] Bus %s reached 10 consecutive empty stops. Despawning.'):format(busNetId)) end
                    shouldDespawn = true
                end

                if shouldDespawn then
                    TriggerServerEvent("AIBus:server:removeRogueBus", busNetId, route.Name)
                    DeleteEntity(bus)
                    break -- Exit the driving loop
                end
            end

            for _, ped in ipairs(frozenPeds) do if DoesEntityExist(ped) then ClearPedTasks(ped) end end
            for _, vehDriver in ipairs(stoppedVehicles) do if DoesEntityExist(vehDriver) then ClearPedTasks(vehDriver) end end

            if not ownedBuses[busNetId] then break end
            SetVehicleIndicatorLights(bus, 0, false); SetVehicleIndicatorLights(bus, 1, false)
            SetVehicleBrakeLights(bus, false); SetVehicleHandbrake(bus, false)
            currentStopIndex = (currentStopIndex % #route.Stops) + 1
            busProgress[busNetId] = currentStopIndex
            local nextStopVec = route.Stops[currentStopIndex]
            
            TaskVehicleDriveToCoordLongrange(driver, bus, nextStopVec.x, nextStopVec.y, nextStopVec.z, 15.0, Config.DrivingFlags, 10.0)
            
            Wait(2000)

            if DoesEntityExist(bus) and GetEntitySpeed(bus) < 0.5 then
                if Config.Debug then print(('[AIBus] Bus %s appears stuck after stop. Giving it a nudge.'):format(busNetId)) end
                SetVehicleForwardSpeed(bus, 2.0) 
                Wait(500)
                TaskVehicleDriveToCoordLongrange(driver, bus, nextStopVec.x, nextStopVec.y, nextStopVec.z, 15.0, Config.DrivingFlags, 10.0)
            end
        end
        busProgress[busNetId] = nil
        if Config.Debug then print('[AIBus] Drive thread ending for bus '..busNetId) end
    end)
end


function MonitorBusThread(bus, driver, routeName, routeStops)
    local busNetId = VehToNet(bus)
    CreateThread(function()
        local timeStationary = 0
        local lastPosition = GetEntityCoords(bus)
        local timeoutCounter = 0
        local maxTimeout = 45
        while DoesEntityExist(bus) and DoesEntityExist(driver) and ownedBuses[busNetId] do
            Wait(5000)
            if GetVehicleNumberOfPassengers(bus) > 0 then timeoutCounter = 0; timeStationary = 0; goto continue_monitor end
            if IsPedDeadOrDying(driver, true) then TriggerServerEvent("AIBus:server:removeRogueBus", busNetId, routeName); break end
            local currentPosition = GetEntityCoords(bus)
            if #(currentPosition - lastPosition) < 1.0 then timeStationary = timeStationary + 5 else timeStationary = 0; lastPosition = currentPosition end
            if timeStationary > 90 then
                if Config.Debug then print(('[AIBus] Bus %s seems to be stuck. Flagging as rogue.'):format(busNetId)) end
                TriggerServerEvent("AIBus:server:removeRogueBus", busNetId, routeName); break
            end
            local isNearAnyStop = false
            for _, stop in ipairs(routeStops) do if #(currentPosition - vector3(stop.x, stop.y, stop.z)) < 350.0 then isNearAnyStop = true; break end end
            local hasDrivingTask = (GetScriptTaskStatus(driver, -1) == 1 or GetScriptTaskStatus(driver, -1) == 15)
            if not isNearAnyStop and not hasDrivingTask then timeoutCounter = timeoutCounter + 10 elseif not isNearAnyStop then timeoutCounter = timeoutCounter + 2 else timeoutCounter = math.max(0, timeoutCounter - 2) end
            if timeoutCounter >= maxTimeout then
                if Config.Debug then print('[AIBus] Bus with NetID ' .. busNetId .. ' flagged as rogue (off-route/no task).') end
                TriggerServerEvent("AIBus:server:removeRogueBus", busNetId, routeName); break
            end
            ::continue_monitor::
        end
    end)
end

function IsPlayerNearby(coords, radius)
    for _, playerId in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(playerId)
        if ped and #(GetEntityCoords(ped) - coords) <= radius then return true end
    end
    return false
end

-- ====================================================================================
-- ETA & DATA FUNCTIONS
-- ====================================================================================

function calculateETA(bus, busCurrentStopIndex, playerStopIndex, route)
    if not DoesEntityExist(bus) or not busCurrentStopIndex or not playerStopIndex or not route then return nil end
    if busCurrentStopIndex == playerStopIndex then return nil end
    local totalStops = #route.Stops
    local stopsToWaitAt = 0
    if busCurrentStopIndex < playerStopIndex then
        stopsToWaitAt = playerStopIndex - busCurrentStopIndex - 1
    else
        stopsToWaitAt = (totalStops - busCurrentStopIndex) + (playerStopIndex - 1)
    end
    stopsToWaitAt = math.max(0, stopsToWaitAt)
    local totalWaitSeconds = stopsToWaitAt * (Config.StopWaitTime / 1000)
    local destinationCoords = route.Stops[playerStopIndex]
    local travelDistance = GetStreetDistance(GetEntityCoords(bus), vector3(destinationCoords.x, destinationCoords.y, destinationCoords.z))
    if travelDistance > 0 then
        local travelTimeSeconds = travelDistance / 15.0
        local totalETASeconds = travelTimeSeconds + totalWaitSeconds
        return math.ceil(totalETASeconds / 60)
    end
    return nil
end

function GetStreetDistance(coords1, coords2)
    local dist = CalculateTravelDistanceBetweenPoints(coords1.x, coords1.y, coords1.z, coords2.x, coords2.y, coords2.z)
    return (dist > 0.0 and dist or -1)
end

function getTimetableData()
    local data = {}
    for _, route in ipairs(Config.Routes) do data[route.Name] = { buses = {}, totalStops = #route.Stops } end
    for _, entity in ipairs(createdEntities) do
        if DoesEntityExist(entity.bus) then
            local busNetId = VehToNet(entity.bus)
            local routeName = entity.routeName
            if data[routeName] then
                local coords = GetEntityCoords(entity.bus)
                local streetName = GetStreetNameFromHashKey(GetStreetNameAtCoord(coords.x, coords.y, coords.z))
                local eta = lastPlayerStop and calculateETA(entity.bus, busProgress[busNetId], lastPlayerStop.stopIndex, lastPlayerStop.route) or nil
                table.insert(data[routeName].buses, {
                    netId = busNetId, currentStopIndex = busProgress[busNetId] or 1,
                    totalStops = data[routeName].totalStops, streetName = streetName or "Unknown Road", eta = eta
                })
            end
        end
    end
    return data
end

-- ====================================================================================
-- BUS REQUEST & BLIP LOGIC
-- ====================================================================================

function createBlips()
    if not Config.Blips.EnableStopBlips then return end
    for routeIndex, route in ipairs(Config.Routes) do
        for stopIndex, stop in ipairs(route.Stops) do
            local blip = AddBlipForCoord(stop.x, stop.y, stop.z)
            SetBlipSprite(blip, Config.StopBlip.Sprite); SetBlipDisplay(blip, Config.StopBlip.Display)
            SetBlipScale(blip, Config.StopBlip.Scale); SetBlipColour(blip, Config.StopBlip.Colour)
            SetBlipAsShortRange(blip, Config.StopBlip.ShortRange) 
            BeginTextCommandSetBlipName("STRING"); AddTextComponentString(route.Name .. " - Stop " .. stopIndex); EndTextCommandSetBlipName(blip)
        end
    end
end

function requestBusAtStop(stopCoords, atStopData)
    PlayHailBusEmote()
    local bestBus, fewestStopsAway = nil, 9999
    local targetRoute = atStopData.route
    if not targetRoute then return end
    for _, entityData in ipairs(createdEntities) do
        if entityData.routeName == targetRoute.Name and DoesEntityExist(entityData.bus) then
            local busNetId = VehToNet(entityData.bus)
            local busCurrentIdx = busProgress[busNetId]
            if busCurrentIdx then
                local stopsAway = 0
                if busCurrentIdx <= atStopData.stopIndex then stopsAway = atStopData.stopIndex - busCurrentIdx
                else stopsAway = (#targetRoute.Stops - busCurrentIdx) + atStopData.stopIndex end
                if stopsAway < fewestStopsAway then fewestStopsAway = stopsAway; bestBus = entityData.bus end
            end
        end
    end

    if bestBus then
        QBCore.Functions.Notify("Next bus is on its way. Tracking it on your map.", "primary")
        busRequestedAtStop = stopCoords 
        requestedBusNetId = VehToNet(bestBus)
        if Config.Blips.EnableBusBlips then
            if blips[trackedBusNetId] and DoesBlipExist(blips[trackedBusNetId]) then RemoveBlip(blips[trackedBusNetId]) end
            local blip = AddBlipForEntity(bestBus)
            SetBlipSprite(blip, 513); SetBlipColour(blip, 4); SetBlipRoute(blip, true)
            blips[requestedBusNetId] = blip
            trackedBusNetId = requestedBusNetId
        end
    else
        QBCore.Functions.Notify("There are no active buses on this route currently.", "error")
    end
end

function requestNextBusStop()
    if not inBus then return end
    if isBusAtAStop(currentBus) then getOffBus(); return end
    if requestedStop then
        cancelNextBusStop()
    else
        requestedStop = true
        ShowStoppingSign()
        QBCore.Functions.Notify("You have requested to get off at the next stop.", "primary")
    end
end

function cancelNextBusStop()
    if not inBus or not requestedStop then return end
    requestedStop = false
    SendNUIMessage({ action = 'hideStoppingSign' })
    QBCore.Functions.Notify("Your request to get off at the next stop has been canceled.", "primary")
end

-- ====================================================================================
-- THREADS & LOOPS
-- ====================================================================================
CreateThread(function()
    while true do
        -- Check every 45 seconds. A long interval is fine for cleanup tasks.
        Wait(45000) 

        if Config.Debug then print('[AIBus] Running orphaned driver cleanup...') end

        local driverModel = GetHashKey(Config.DriverModel or 's_m_y_busboy_01')
        local peds = GetGamePool('CPed')
        local cleanedCount = 0

        for _, ped in ipairs(peds) do
            -- Check if the entity exists and is the correct AI model
            if DoesEntityExist(ped) and not IsPedAPlayer(ped) and GetEntityModel(ped) == driverModel then
                -- Check if the driver is outside of any vehicle
                if not IsPedInAnyVehicle(ped, false) then
                    if Config.Debug then print(('[AIBus] Found orphaned bus driver (Entity ID: %s). Deleting.'):format(ped)) end
                    DeleteEntity(ped)
                    cleanedCount = cleanedCount + 1
                end
            end
        end

        if Config.Debug and cleanedCount > 0 then
            print(('[AIBus] Cleaned up %d orphaned drivers.'):format(cleanedCount))
        end
    end
end)
-- UNIFIED LOGIC THREAD
CreateThread(function()
    while true do
        Wait(1000)
        local playerPed = PlayerPedId()
        if not playerPed or playerPed == 0 then goto continue_loop end
        local playerCoords = GetEntityCoords(playerPed)

        -- Check if a bus was requested and if the player has walked away
        if busRequestedAtStop and #(playerCoords - busRequestedAtStop) > 25.0 then 
            if Config.Debug then print('[AIBus] Player walked away from bus request stop. Cancelling request.') end
            
            if trackedBusNetId and blips[trackedBusNetId] and DoesBlipExist(blips[trackedBusNetId]) then
                RemoveBlip(blips[trackedBusNetId])
            end

            busRequestedAtStop = nil
            requestedBusNetId = nil
            trackedBusNetId = nil

            QBCore.Functions.Notify("You moved too far from the stop. Your bus request has been cancelled.", "warning")
        end

        if inBus and GetVehiclePedIsIn(playerPed, false) ~= currentBus then
            inBus = false; currentBus = nil; requestedStop = false
            SendNUIMessage({ action = 'hideInBusUI' }); SendNUIMessage({ action = 'hideStoppingSign' })
        end

        if inBus then
            textDisplayInfo.shouldDraw = false
            if nextBusInfo then nextBusInfo = nil; SendNUIMessage({ action = 'hideNextBus' }) end
            if isBusAtAStop(currentBus) then inBusText = "Press [E] to get off now"
            elseif requestedStop then inBusText = "Stop Requested | Press [E] to cancel"
            else inBusText = "Press [E] to request next stop" end
            local routeName, routeStops = nil, nil
            for _, entityData in ipairs(createdEntities) do
                if entityData.bus == currentBus then
                    routeName = entityData.routeName
                    for _, r in ipairs(Config.Routes) do if r.Name == routeName then routeStops = r.Stops; break end end
                    break
                end
            end
            local busNetId = VehToNet(currentBus)
            local nextStopIndex = busProgress[busNetId]
            if routeName and routeStops and nextStopIndex then
                local nextStopVec = routeStops[nextStopIndex]
                local nextStopName = GetStreetNameFromHashKey(GetStreetNameAtCoord(nextStopVec.x, nextStopVec.y, nextStopVec.z)) or "Unknown Road"
                if isBusAtAStop(currentBus) then
                    local currentStopIndex = (nextStopIndex == 1) and #routeStops or (nextStopIndex - 1)
                    local currentStopVec = routeStops[currentStopIndex]
                    local currentStopName = GetStreetNameFromHashKey(GetStreetNameAtCoord(currentStopVec.x, currentStopVec.y, currentStopVec.z)) or "Unknown Stop"
                    SendNUIMessage({ action = 'showInBusUI', data = { status = 'stopped', routeName = routeName, currentStopName = currentStopName, nextStopName = nextStopName }})
                else
                    SendNUIMessage({ action = 'showInBusUI', data = { status = 'driving', routeName = routeName, nextStopName = nextStopName }})
                end
            end
            goto continue_loop
        else
            inBusText = ""
            SendNUIMessage({ action = 'hideInBusUI' })
        end
        
        if IsPedInAnyVehicle(playerPed, false) then
            textDisplayInfo.shouldDraw = false
            if nextBusInfo then nextBusInfo = nil; SendNUIMessage({ action = 'hideNextBus' }) end
            goto continue_loop
        end

        local closestDistToStop, atStopData = 10.0, nil
        for _, route in ipairs(Config.Routes) do
            for stopIndex, stop in ipairs(route.Stops) do
                local stopCoords = vector3(stop.x, stop.y, stop.z)
                local distance = #(playerCoords - stopCoords)
                if distance < closestDistToStop then
                    closestDistToStop = distance
                    atStopData = { route = route, stopIndex = stopIndex, coords = stopCoords }
                end
            end
        end

        lastPlayerStop = atStopData

        if atStopData then
            textDisplayInfo.coords = atStopData.coords + vector3(0.0, 0.0, 1.0)
            if Config.SuspendService or atStopData.route.suspendedRoute then
                textDisplayInfo.shouldDraw = true
                textDisplayInfo.text = Config.SuspendService and "Bus Service Suspended" or "Service Suspended for this Route"
                textDisplayInfo.action = nil
                if nextBusInfo then nextBusInfo = nil; SendNUIMessage({ action = 'hideNextBus' }) end
                goto continue_loop
            end

            local busToBoard = nil
            if requestedBusNetId then
                local requestedBus = NetToVeh(requestedBusNetId)
                if requestedBus and DoesEntityExist(requestedBus) and IsVehicleStopped(requestedBus) and #(GetEntityCoords(requestedBus) - atStopData.coords) < Config.StopZoneRadius then
                    busToBoard = requestedBus
                end
            else
                local closestBusDistToPlayer = 9999.0
                local closestBusAtStop = nil
                for _, entityData in ipairs(createdEntities) do
                    if entityData.bus and DoesEntityExist(entityData.bus) and IsVehicleStopped(entityData.bus) and #(GetEntityCoords(entityData.bus) - atStopData.coords) < Config.StopZoneRadius then
                        local distToPlayer = #(playerCoords - GetEntityCoords(entityData.bus))
                        if distToPlayer < closestBusDistToPlayer then
                            closestBusDistToPlayer = distToPlayer
                            closestBusAtStop = entityData.bus
                        end
                    end
                end
                busToBoard = closestBusAtStop
            end
            
            if busToBoard then
                textDisplayInfo.shouldDraw = true
                textDisplayInfo.text = "[E] - Board Bus"
                textDisplayInfo.action = function()
                    local busNetId = VehToNet(busToBoard)
                    if busNetId and busNetId ~= 0 then
                        TriggerServerEvent('AIBus:server:requestBoardBus', busNetId)
                    else
                        QBCore.Functions.Notify("This bus cannot be boarded right now.", "error")
                    end
                    requestedBusNetId = nil; busRequestedAtStop = nil
                end
                if nextBusInfo then nextBusInfo = nil; SendNUIMessage({ action = 'hideNextBus' }) end
            else
                if busRequestedAtStop then
                    textDisplayInfo.shouldDraw = true
                    textDisplayInfo.text = "Bus Requested"
                    textDisplayInfo.action = nil
                else
                    textDisplayInfo.shouldDraw = true
                    textDisplayInfo.text = "[E] - Request Bus"
                    textDisplayInfo.action = function()
                        -- Check for nearby buses before requesting a new one
                        local isBusNearby = false
                        local stopsToCheck = 4 -- How many stops behind to check for an active bus
                        
                        for _, entity in ipairs(createdEntities) do
                            if entity.routeName == atStopData.route.Name and DoesEntityExist(entity.bus) then
                                local busNetId = VehToNet(entity.bus)
                                local busCurrentIdx = busProgress[busNetId]
                                if busCurrentIdx then
                                    local stopsAway = 0
                                    local totalStops = #atStopData.route.Stops
                                    if busCurrentIdx <= atStopData.stopIndex then
                                        stopsAway = atStopData.stopIndex - busCurrentIdx
                                    else
                                        stopsAway = (totalStops - busCurrentIdx) + atStopData.stopIndex
                                    end

                                    if stopsAway <= stopsToCheck then
                                        isBusNearby = true
                                        break
                                    end
                                end
                            end
                        end

                        if isBusNearby then
                            QBCore.Functions.Notify("There is already a bus approaching this stop.", "info")
                            requestBusAtStop(atStopData.coords, atStopData) -- Track the nearby bus
                        else
                            PlayHailBusEmote()
                            TriggerServerEvent('AIBus:server:requestBusSpawn', atStopData.route.Name, atStopData.stopIndex)
                            busRequestedAtStop = atStopData.coords
                        end
                    end
                end
                
                local bestETA, busWithBestETA = 9999, nil
                local targetRoute = atStopData.route
                if targetRoute then
                    for _, entity in ipairs(createdEntities) do
                        if entity.routeName == targetRoute.Name and DoesEntityExist(entity.bus) then
                            local busNetId = VehToNet(entity.bus)
                            local busCurrentIdx = busProgress[busNetId]
                            if busCurrentIdx then
                                local eta = calculateETA(entity.bus, busCurrentIdx, atStopData.stopIndex, targetRoute)
                                if eta and eta < bestETA then
                                    bestETA = eta
                                    busWithBestETA = { routeName = entity.routeName, eta = eta }
                                end
                            end
                        end
                    end
                end
                if busWithBestETA then
                    if GetEntitySpeed(playerPed) < 0.2 then
                        if not nextBusInfo or nextBusInfo.eta ~= busWithBestETA.eta then
                            nextBusInfo = busWithBestETA
                            SendNUIMessage({ action = 'showNextBus', nextBus = nextBusInfo })
                        end
                    else
                        if nextBusInfo then nextBusInfo = nil; SendNUIMessage({ action = 'hideNextBus' }) end
                    end
                else
                    if nextBusInfo then nextBusInfo = nil; SendNUIMessage({ action = 'hideNextBus' }) end
                end
            end
        else
            textDisplayInfo.shouldDraw = false
            if nextBusInfo then nextBusInfo = nil; SendNUIMessage({ action = 'hideNextBus' }) end
        end
        ::continue_loop::
    end
end)

CreateThread(function()
    while true do
        Wait(20000) -- Check every 20 seconds

        local myServerId = GetPlayerServerId(PlayerId())

        -- Loop through all the buses this client is supposed to own
        for busNetId, isOwner in pairs(ownedBuses) do
            if isOwner then
                local bus = NetToVeh(busNetId)
                if DoesEntityExist(bus) then
                    local driver = GetPedInVehicleSeat(bus, -1)
                    if DoesEntityExist(driver) and not IsPedAPlayer(driver) then
                        -- Check if the driver has an active driving task
                        local taskStatus = GetScriptTaskStatus(driver, -1)
                        
                        -- Task status 0 or 7 means "no task" or "task finished".
                        -- If the bus is not at a stop, it should have a task.
                        if (taskStatus == 0 or taskStatus == 7) and not isBusAtAStop(bus) then
                            if Config.Debug then
                                print(('[AIBus] [Self-Healing] Owned bus %s has no active AI task. Restarting AI.'):format(busNetId))
                            end

                            -- Find the route info for this bus to restart its logic
                            local routeConfig, routeName
                            for _, entityData in ipairs(createdEntities) do
                                if entityData.bus == bus then
                                    routeName = entityData.routeName
                                    break
                                end
                            end
                            for _, r in ipairs(Config.Routes) do
                                if r.Name == routeName then
                                    routeConfig = r
                                    break
                                end
                            end

                            if routeConfig and busProgress[busNetId] then
                                -- Restart the drive and monitor threads for this bus
                                driveBus(bus, driver, routeConfig, busProgress[busNetId])
                                MonitorBusThread(bus, driver, routeConfig.Name, routeConfig.Stops)
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- DRAWING & INPUT THREAD
CreateThread(function()
    while true do
        Wait(0)
        if textDisplayInfo.shouldDraw and textDisplayInfo.coords then
            DrawText3D(textDisplayInfo.coords.x, textDisplayInfo.coords.y, textDisplayInfo.coords.z, textDisplayInfo.text)
        end
        if inBusText ~= "" then
            DrawText2D(0.5, 0.95, inBusText)
        end
        if IsControlJustReleased(0, 38) then
            if inBus then requestNextBusStop()
            elseif textDisplayInfo.shouldDraw and textDisplayInfo.action then textDisplayInfo.action() end
        end
    end
end)

-- ESC KEY HANDLER THREAD
CreateThread(function()
    while true do
        Wait(0)
        if isTimetableOpen then
            if IsControlJustReleased(0, 200) then
                isTimetableOpen = false
                SetNuiFocus(false, false)
                SendNUIMessage({ action = 'closeTimetable' })
            end
        end
    end
end)
-- ====================================================================================
-- COMMANDS, NUI CALLBACKS, AND EVENTS
-- ====================================================================================

RegisterCommand('busstop', function() requestNextBusStop() end, false)
RegisterCommand('cancelstop', function() cancelNextBusStop() end, false)

RegisterCommand('bustimetable', function()
    if textDisplayInfo.shouldDraw then
        QBCore.Functions.Notify("Cannot open timetable while at a bus stop interaction point.", "error")
        return
    end
    isTimetableOpen = not isTimetableOpen
    SetNuiFocus(isTimetableOpen, isTimetableOpen)
    if isTimetableOpen then
        SendNUIMessage({ action = 'openTimetable', busData = getTimetableData() })
    else
        SendNUIMessage({ action = 'closeTimetable' })
    end
end, false)

RegisterCommand('busrequest', function()
    local playerCoords = GetEntityCoords(PlayerPedId())
    local atStopData = nil
    local closestDist = Config.StopInteractionDistance
    for _, route in ipairs(Config.Routes) do
        for stopIndex, stop in ipairs(route.Stops) do
            local stopCoords = vector3(stop.x, stop.y, stop.z)
            if #(playerCoords - stopCoords) < closestDist then
                closestDist = #(playerCoords - stopCoords)
                atStopData = { route = route, stopIndex = stopIndex, coords = stopCoords }
            end
        end
    end
    if atStopData then
        requestBusAtStop(atStopData.coords, atStopData)
    else
        QBCore.Functions.Notify("You are not near a bus stop.", "error")
    end
end, false)

RegisterNUICallback('close', function(data, cb)
    isTimetableOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeTimetable' })
    cb('ok')
end)

RegisterNUICallback('trackBus', function(data, cb)
    local netId = tonumber(data.netId)
    local bus = NetToVeh(netId)
    if blips[trackedBusNetId] and DoesBlipExist(blips[trackedBusNetId]) then RemoveBlip(blips[trackedBusNetId]) end
    if DoesEntityExist(bus) then
        local blip = AddBlipForEntity(bus)
        SetBlipSprite(blip, 513); SetBlipColour(blip, 4); SetBlipRoute(blip, true)
        blips[netId] = blip
        trackedBusNetId = netId
        QBCore.Functions.Notify("Bus is now being tracked on your map.", "primary")
    end
    cb('ok')
end)

-- ====================================================================================
-- SCRIPT EVENTS (NET & LOCAL)
-- ====================================================================================

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        TriggerServerEvent('AIBus:server:RequestFullSync')
        Wait(2000)
        CleanupExistingBuses()
        createBlips()
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) then
            local isAnAiBus = false
            for _, route in ipairs(Config.Routes) do
                if GetEntityModel(vehicle) == GetHashKey(route.BusModel) then isAnAiBus = true; break end
            end
            if isAnAiBus then
                local plate = GetVehicleNumberPlateText(vehicle):gsub("^%s+", ""):gsub("%s+$", "")
                if plate:match("^"..Config.BusPlate) then
                    local driver = GetPedInVehicleSeat(vehicle, -1)
                    if driver and not IsPedAPlayer(driver) and DoesEntityExist(driver) then DeleteEntity(driver) end
                    DeleteEntity(vehicle)
                end
            end
        end
    end
    createdEntities = {}
end)

AddEventHandler('playerSpawned', function()
    createBlips()
    TriggerServerEvent('AIBus:server:syncBusesForNewPlayer')
end)

RegisterNetEvent('AIBus:client:requestSpawn', function(route, startStopIndex, plate, busModel, ownerId)
    CreateThread(function()
        if Config.Debug then print(('[AIBus-client] Received spawn request. Intended Owner: %s'):format(ownerId)) end
        local startStop = route.Stops[startStopIndex]
        local found, roadCoords, roadHeading = GetClosestVehicleNodeWithHeading(startStop.x, startStop.y, startStop.z, 1, 3.0, 0)
        local spawnCoords = found and roadCoords or vector3(startStop.x, startStop.y, startStop.z)
        local spawnHeading = found and roadHeading or startStop.w
        if not IsSpawnAreaClear(spawnCoords) then return end
        local modelHash = GetHashKey(busModel or 'bus')
        RequestModel(modelHash)
        local timeout = 0
        while not HasModelLoaded(modelHash) and timeout < 150 do Wait(100); timeout = timeout + 1 end
        if not HasModelLoaded(modelHash) then SetModelAsNoLongerNeeded(modelHash); return end
        local spawnedBus = CreateVehicle(modelHash, spawnCoords, spawnHeading, true, true)
        SetModelAsNoLongerNeeded(modelHash)
        if not DoesEntityExist(spawnedBus) then return end
        SetEntityAsMissionEntity(spawnedBus, true, true)
        SetVehicleNumberPlateText(spawnedBus, plate)
        local pedModel = 's_m_y_busboy_01'
        RequestModel(pedModel)
        while not HasModelLoaded(pedModel) do Wait(100) end
        local driver = CreatePedInsideVehicle(spawnedBus, 4, pedModel, -1, true, false)
        SetEntityAsMissionEntity(driver, true, true)
        SetModelAsNoLongerNeeded(pedModel)
        local netId = VehToNet(spawnedBus)
        if netId and netId ~= 0 then
            TriggerServerEvent('AIBus:server:registerBus', netId, route.Name, plate, startStopIndex, ownerId)
        else
            DeleteEntity(driver); DeleteEntity(spawnedBus)
        end
    end)
end)

RegisterNetEvent('AIBus:client:initiateBus', function(busNetId, route, startStopIndex, ownerId)
    if Config.Debug then print(('[AIBus-client] Initiating bus. NetID: %s, Owner: %s, My ID: %s'):format(busNetId, ownerId, GetPlayerServerId(PlayerId()))) end
    for _, entityData in ipairs(createdEntities) do if NetToVeh(busNetId) == entityData.bus then return end end
    local timeout = 0
    while not NetworkDoesNetworkIdExist(busNetId) and timeout < 300 do Wait(100); timeout = timeout + 1 end
    if not NetworkDoesNetworkIdExist(busNetId) then return end
    local bus = NetToVeh(busNetId)
    if DoesEntityExist(bus) then
        if Config.Blips.EnableBusBlips and not blips[busNetId] then
            local blip = AddBlipForEntity(bus)
            SetBlipSprite(blip, Config.BusBlip.Sprite); SetBlipColour(blip, Config.BusBlip.Colour); SetBlipScale(blip, Config.BusBlip.Scale)
            BeginTextCommandSetBlipName("STRING"); AddTextComponentString(Config.BusBlip.Text .. " - " .. route.Name); EndTextCommandSetBlipName(blip)
            blips[busNetId] = blip
        end
        table.insert(createdEntities, { bus = bus, driver = nil, blip = blips[busNetId], routeName = route.Name })
        local myServerId = GetPlayerServerId(PlayerId())
        ownedBuses[busNetId] = (myServerId == ownerId)
        if ownedBuses[busNetId] then
            local driver = GetPedInVehicleSeat(bus, -1)
            if DoesEntityExist(driver) and not IsPedAPlayer(driver) then
                driveBus(bus, driver, route, startStopIndex)
                MonitorBusThread(bus, driver, route.Name, route.Stops)
            end
        end
    end
end)

RegisterNetEvent('AIBus:client:updateOwner', function(busNetId, newOwnerId)
    local myServerId = GetPlayerServerId(PlayerId())
    local iAmTheNewOwner = (myServerId == newOwnerId)
    ownedBuses[busNetId] = iAmTheNewOwner
    if iAmTheNewOwner then
        if Config.Debug then print('[AIBus] Ownership acquired for bus ' .. busNetId) end
        local bus = NetToVeh(busNetId)
        if DoesEntityExist(bus) then
            local routeConfig, routeName
            for _, entityData in ipairs(createdEntities) do if entityData.bus == bus then routeName = entityData.routeName; break end end
            for _, r in ipairs(Config.Routes) do if r.Name == routeName then routeConfig = r; break end end
            if routeConfig then
                local driver = GetPedInVehicleSeat(bus, -1)
                if DoesEntityExist(driver) and not IsPedAPlayer(driver) then
                    driveBus(bus, driver, routeConfig, busProgress[busNetId] or 1)
                    MonitorBusThread(bus, driver, routeConfig.Name, routeConfig.Stops)
                end
            end
        end
    end
end)

RegisterNetEvent('AIBus:client:syncBuses', function(serverBuses)
    if Config.Debug then print('[AIBus] Received sync packet from server for ' .. #serverBuses .. ' buses.') end
    local clientBusNetIds = {}
    for _, entity in ipairs(createdEntities) do if DoesEntityExist(entity.bus) then table.insert(clientBusNetIds, VehToNet(entity.bus)) end end
    for _, busData in ipairs(serverBuses) do
        local found = false
        for _, clientNetId in ipairs(clientBusNetIds) do if clientNetId == busData.netId then found = true; break end end
        if not found then
            TriggerEvent('AIBus:client:initiateBus', busData.netId, busData.route, busData.startStopIndex, busData.ownerId)
        end
    end
end)
RegisterNetEvent('AIBus:client:getOnBus', function(busNetId)
    local bus = NetToVeh(busNetId)
    if DoesEntityExist(bus) then
        getOnBus(bus)
    else
        if Config.Debug then print('[AIBus] GetOnBus event failed because bus with NetID '..busNetId..' does not exist on this client.') end
        QBCore.Functions.Notify("The bus is no longer here.", "error")
    end
end)


-- =================================================================
-- BUS MAP FEATURE v4.1 (FINAL)
-- =================================================================

local isBusMapActive = false
local tempMapBlips = {}       -- Table to hold our temporary bus stop blips
local hiddenWorldBlips = {}     -- Table to store world blips that we hide
local allowedBlipSet = {}       -- A fast-lookup set for allowed blips

-- Convert the config array into a hash set for quick lookups
for _, spriteId in ipairs(Config.Blips.AllowedMapBlips or {}) do
    allowedBlipSet[spriteId] = true
end

local routeColors = { -- Define some colors for your routes. Add more if needed.
    { R = 231, G = 76, B = 60 },   -- Red
    { R = 52, G = 152, B = 219 },  -- Blue
    { R = 46, G = 204, B = 113 },  -- Green
}

-- Scans and hides blips NOT in the allowed list
local function hideOtherBlips()
    hiddenWorldBlips = {}
    local exclusionSet = {} -- Blips to NOT hide (buses, stops)
    for _, blip in ipairs(tempMapBlips) do exclusionSet[blip] = true end
    for _, blip in pairs(blips) do if DoesBlipExist(blip) then exclusionSet[blip] = true end end

    -- Iterate through a wide range of possible sprite IDs
    for spriteId = 1, 800 do
        -- Only search for sprites that are NOT on our allowed list
        if not allowedBlipSet[spriteId] then
            local blip = GetFirstBlipInfoId(spriteId)
            while DoesBlipExist(blip) do
                -- Double-check it's not a bus-related blip before hiding
                if not exclusionSet[blip] then
                    table.insert(hiddenWorldBlips, {blip = blip, alpha = GetBlipAlpha(blip)})
                    SetBlipAlpha(blip, 0)
                end
                blip = GetNextBlipInfoId(spriteId)
            end
        end
    end
    print('[BusMap] Hid ' .. #hiddenWorldBlips .. ' other world blips.')
end

-- Restores all the world blips we hid
local function restoreOtherBlips()
    for _, blipData in ipairs(hiddenWorldBlips) do
        if DoesBlipExist(blipData.blip) then
            SetBlipAlpha(blipData.blip, blipData.alpha)
        end
    end
    print('[BusMap] Restored ' .. #hiddenWorldBlips .. ' other world blips.')
    hiddenWorldBlips = {}
end

-- Cleans up the temporary bus stop blips we created
local function cleanupMapBlips()
    for _, blip in ipairs(tempMapBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    print('[BusMap] Cleaned up ' .. #tempMapBlips .. ' temporary stop blips.')
    tempMapBlips = {}
end

-- Command to toggle the map display
RegisterCommand('busmap', function()
    isBusMapActive = not isBusMapActive
    if isBusMapActive then
        QBCore.Functions.Notify("Bus map display enabled. Open your map.", "primary")
    else
        QBCore.Functions.Notify("Bus map display disabled.", "primary")
        restoreOtherBlips()
        cleanupMapBlips()
    end
end, false)

-- Main thread for the map feature
CreateThread(function()
    while true do
        Wait(100)
        if isBusMapActive then
            if IsPauseMenuActive() then
                -- First frame logic: create blips and hide others
                if #tempMapBlips == 0 then
                    for routeIndex, routeData in ipairs(Config.Routes) do
                        for stopIndex, stopData in ipairs(routeData.Stops) do
                            local blip = AddBlipForCoord(stopData.x, stopData.y, stopData.z)
                            SetBlipSprite(blip, 1) -- Small dot sprite
                            SetBlipScale(blip, 0.5)
                            SetBlipColour(blip, routeData.suspendedRoute and 1 or 4) -- Red if suspended, Yellow if active
                            BeginTextCommandSetBlipName("STRING")
                            if routeData.suspendedRoute then
                                AddTextComponentString("Suspended Bus Route")
                            else
                                AddTextComponentString(routeData.Name)
                            end
                            EndTextCommandSetBlipName(blip)
                            table.insert(tempMapBlips, blip)
                        end
                    end
                    hideOtherBlips()
                end

                -- Continuous drawing logic for route lines
                for routeIndex, routeData in ipairs(Config.Routes) do
                    local color = routeColors[routeIndex] or { R = 255, G = 255, B = 255 }
                    local alpha = routeData.suspendedRoute and 100 or 255
                    for stopIndex = 1, #routeData.Stops - 1 do
                        local startPos = routeData.Stops[stopIndex]
                        local endPos = routeData.Stops[stopIndex + 1]
                        DrawLine(startPos.x, startPos.y, startPos.z, endPos.x, endPos.y, endPos.z, color.R, color.G, color.B, alpha)
                    end
                    local lastStop = routeData.Stops[#routeData.Stops]
                    local firstStop = routeData.Stops[1]
                    DrawLine(lastStop.x, lastStop.y, lastStop.z, firstStop.x, firstStop.y, firstStop.z, color.R, color.G, color.B, alpha)
                end
            else
                -- If map was open but is now closed, cleanup
                if #tempMapBlips > 0 then
                    restoreOtherBlips()
                    cleanupMapBlips()
                end
            end
        end
    end
end)