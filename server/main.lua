-- =================================================================
-- AIBus/server.lua - FINAL UNIFIED VERSION
-- =================================================================
local QBCore = exports['qb-core']:GetCoreObject()
local createdRoutes = {}
local busStrikes = {}


-- Initialize the management table for all routes
for i, route in ipairs(Config.Routes) do
    createdRoutes[route.Name] = {}
end

-- =================================================================
-- CORE THREADS (LOOPS)
-- =================================================================

-- Server-side loop to manage bus spawning
CreateThread(function()
    while true do
        Wait(15000) -- Check every 15 seconds

       --[[  if Config.SuspendService then goto continue_spawn_loop end

        local players = QBCore.Functions.GetPlayers()
        if #players == 0 then goto continue_spawn_loop end

        for routeIndex, route in ipairs(Config.Routes) do
            if not route.suspendedRoute then
                local routeData = createdRoutes[route.Name]
                if routeData then
                    local maxBusesForRoute = tonumber(route.MaxBusses) or 2
                    if #routeData < maxBusesForRoute then
                        local busCount = #routeData
                        local startFraction = busCount / maxBusesForRoute
                        local startStopIndex = math.floor(#route.Stops * startFraction) + 1
                        local stopToSpawnAt = route.Stops[startStopIndex] or route.Stops[1]

                        local nearbyPlayerId = nil
                        local closestDistance = Config.DistanceSpawn or 700.0
                        for _, playerId in ipairs(players) do
                            local playerPed = GetPlayerPed(playerId)
                            if playerPed and DoesEntityExist(playerPed) then
                                local distance = #(GetEntityCoords(playerPed) - vector3(stopToSpawnAt.x, stopToSpawnAt.y, stopToSpawnAt.z))
                                if distance < closestDistance then
                                    closestDistance = distance
                                    nearbyPlayerId = playerId
                                end
                            end
                        end

                        if nearbyPlayerId then
                            local busNumberOnRoute = busCount + 1
                            local plate = string.format("%s%d%d", Config.BusPlate, routeIndex, busNumberOnRoute)
                            if Config.Debug then print(('[AIBus-server] Requesting client %s to spawn bus for "%s" (Plate: %s, Owner: %s)'):format(nearbyPlayerId, route.Name, plate, nearbyPlayerId)) end
                            TriggerClientEvent('AIBus:client:requestSpawn', nearbyPlayerId, route, startStopIndex, plate, route.BusModel, nearbyPlayerId)
                        end
                    end
                end
            end
        end
        ::continue_spawn_loop::
        ]]--
    end
end)

-- Ownership management loop
CreateThread(function()
    while true do
        Wait(45000) -- Check every 45 seconds
        local players = QBCore.Functions.GetPlayers()
        if #players == 0 or Config.SuspendService then goto continue_ownership_loop end

        for routeName, buses in pairs(createdRoutes) do
            for i = #buses, 1, -1 do
                local busData = buses[i]
                if busData then
                    local busEntity = NetworkGetEntityFromNetworkId(busData.netId)

                    if not DoesEntityExist(busEntity) then
                        if Config.Debug then print(('[AIBus-server] Bus %s (NetID: %s) no longer exists. Removing from tracking.'):format(busData.plate, busData.netId)) end
                        table.remove(createdRoutes[routeName], i)
                    else
                        local currentPos = GetEntityCoords(busEntity)
                        -- Stuck/Driverless Check: If bus hasn't moved, increment stuck timer.
                        if busData.lastPos and #(currentPos - busData.lastPos) < 5.0 then
                            createdRoutes[routeName][i].stuckTime = (busData.stuckTime or 0) + 1
                        else
                            createdRoutes[routeName][i].lastPos = currentPos
                            createdRoutes[routeName][i].stuckTime = 0
                        end

                        -- If stuck for 3 checks (~2.25 mins), assume it's abandoned/broken and remove it.
                        if createdRoutes[routeName][i].stuckTime >= 3 then
                            if Config.Debug then print(('[AIBus-server] Bus %s (NetID: %s) appears stuck or driverless. Removing.'):format(busData.plate, busData.netId)) end
                            TriggerClientEvent('AIBus:client:forceDeleteBus', -1, busData.netId)
                            table.remove(createdRoutes[routeName], i)
                        else
                            -- Ownership Transfer Logic
                            local ownerPed = GetPlayerPed(busData.ownerId)
                            if not ownerPed or not DoesEntityExist(ownerPed) or #(GetEntityCoords(ownerPed) - currentPos) > 700.0 then
                                local newOwnerId = nil
                                for _, playerId in ipairs(players) do
                                    local playerPed = GetPlayerPed(playerId)
                                    if playerPed and #(GetEntityCoords(playerPed) - currentPos) < 700.0 then
                                        newOwnerId = playerId
                                        break
                                    end
                                end
                                if newOwnerId and newOwnerId ~= busData.ownerId then
                                    if Config.Debug then print(('[AIBus-server] Bus %s is too far from owner %s. Assigning new owner: %s'):format(busData.plate, busData.ownerId, newOwnerId)) end
                                    createdRoutes[routeName][i].ownerId = newOwnerId
                                    TriggerClientEvent('AIBus:client:updateOwner', -1, busData.netId, newOwnerId)
                                end
                            end
                        end
                    end
                end
            end
        end
        ::continue_ownership_loop::
    end
end)
CreateThread(function()
    while true do
        Wait(60000) -- Check every 60 seconds

        if Config.SuspendService then goto continue_despawn_loop end
        
        local players = QBCore.Functions.GetPlayers()
        if #players == 0 then goto continue_despawn_loop end

        local playerCoords = {}
        for _, playerId in ipairs(players) do
            local playerPed = GetPlayerPed(playerId)
            if playerPed and DoesEntityExist(playerPed) then
                playerCoords[playerId] = GetEntityCoords(playerPed)
            end
        end

        -- Iterate backwards to safely remove items from the table
        for routeName, buses in pairs(createdRoutes) do
            local routeConfig = nil
            for _, r in ipairs(Config.Routes) do if r.Name == routeName then routeConfig = r; break end end

            if routeConfig then
                for i = #buses, 1, -1 do
                    local busData = buses[i]
                    local busEntity = NetworkGetEntityFromNetworkId(busData.netId)
                    if not DoesEntityExist(busEntity) then goto continue_bus_loop end -- Skip if already gone

                    local busCoords = GetEntityCoords(busEntity)
                    local isPlayerNearby = false
                    local activationRadius = Config.PlayerActivationRadius or 800.0 -- FIX: Added fallback value

                    -- Check if any player is near the bus itself
                    for _, pCoords in pairs(playerCoords) do
                        if #(busCoords - pCoords) < activationRadius then -- FIX: Used fallback variable
                            isPlayerNearby = true
                            break
                        end
                    end

                    -- If no one is near the bus, check if anyone is near its route stops
                    if not isPlayerNearby then
                        for _, stop in ipairs(routeConfig.Stops) do
                            for _, pCoords in pairs(playerCoords) do
                                if #(vector3(stop.x, stop.y, stop.z) - pCoords) < activationRadius then -- FIX: Used fallback variable
                                    isPlayerNearby = true
                                    break
                                end
                            end
                            if isPlayerNearby then break end
                        end
                    end

                    -- If still no players nearby after all checks, despawn the bus
                    if not isPlayerNearby then
                        if Config.Debug then print(('[AIBus-server] No players near bus %s or its route. Despawning.'):format(busData.plate)) end
                        table.remove(createdRoutes[routeName], i)
                        TriggerClientEvent('AIBus:client:forceDeleteBus', -1, busData.netId)
                    end
                    ::continue_bus_loop::
                end
            end
        end
        ::continue_despawn_loop::
    end
end)

-- =================================================================
-- PLAYER REQUESTED BUS SPAWN EVENT
-- =================================================================
RegisterServerEvent('AIBus:server:requestBusSpawn', function(routeName, currentStopIndex)
    local src = source
    local route = nil
    local routeIndex = 0
    for i, r in ipairs(Config.Routes) do 
        if r.Name == routeName then 
            route = r
            routeIndex = i
            break 
        end 
    end
    
    if not route then return end

    -- Check if there are already enough buses on this route
    local maxBusesForRoute = tonumber(route.MaxBusses) or 2
    if #createdRoutes[routeName] >= maxBusesForRoute then
        TriggerClientEvent('QBCore:Notify', src, "A bus is already on its way for this route.", "primary")
        return
    end

    -- Calculate a spawn point 2 stops behind the player
    local numStops = #route.Stops
    -- The formula ensures the index wraps around correctly
    local startStopIndex = ((currentStopIndex - 1 - 2 + numStops) % numStops) + 1
    
    local stopToSpawnAt = route.Stops[startStopIndex]

    -- Use the existing spawn logic, but trigger it for the requesting player
    local busNumberOnRoute = #createdRoutes[routeName] + 1
    local plate = string.format("%s%d%d", Config.BusPlate, routeIndex, busNumberOnRoute)
    
    if Config.Debug then print(('[AIBus-server] Player %s requested a bus for "%s". Spawning at stop %s.'):format(src, route.Name, startStopIndex)) end
    TriggerClientEvent('AIBus:client:requestSpawn', src, route, startStopIndex, plate, route.BusModel, src)
    TriggerClientEvent('QBCore:Notify', src, "A bus has been dispatched for this route. It will arrive shortly.", "success")
end)
-- =================================================================
-- SERVER EVENTS
-- =================================================================

RegisterServerEvent('AIBus:server:registerBus', function(netId, routeName, plate, startStopIndex, ownerId)
    if not createdRoutes[routeName] then return end
    if not ownerId then
        if Config.Debug then print(('[AIBus-server] ERROR: Bus %s registered with a nil owner.'):format(plate)) end
        return
    end

    local busEntity = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(busEntity) then return end -- Safety check

    table.insert(createdRoutes[routeName], { 
        netId = netId, 
        plate = plate, 
        startStopIndex = startStopIndex, 
        ownerId = ownerId,
        lastPos = GetEntityCoords(busEntity), -- Add initial position
        stuckTime = 0 -- Add stuck timer
    })
    
    if Config.Debug then print(('[AIBus-server] Client registered new bus. Plate: %s, NetID: %s, Owner: %s. Broadcasting.'):format(plate, netId, ownerId)) end
    
    local route = nil
    for _, r in ipairs(Config.Routes) do if r.Name == routeName then route = r; break end end
    if route then
        TriggerClientEvent('AIBus:client:initiateBus', -1, netId, route, startStopIndex, ownerId)
    end
end)

RegisterServerEvent('AIBus:server:requestBoardBus', function(busNetId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    if Config.Debug then print(('[AIBus-server] Player %s is requesting to board bus with NetID: %s'):format(src, busNetId)) end

    local busEntity = NetworkGetEntityFromNetworkId(busNetId)
    if not DoesEntityExist(busEntity) then
        if Config.Debug then print(('[AIBus-server] Boarding FAILED for player %s. Bus with NetID %s does not exist.'):format(src, busNetId)) end
        TriggerClientEvent('QBCore:Notify', src, "That bus no longer exists.", "error")
        return
    end

    if Config.RideFare and Config.RideFare > 0 then
        if Player.Functions.RemoveMoney(Config.PaymentMethod, Config.RideFare, "bus-ride-fare") then
            if Config.Debug then print(('[AIBus-server] Payment successful for player %s. Authorizing boarding.'):format(src)) end
            TriggerClientEvent('QBCore:Notify', src, ("You paid $%s for the bus ride."):format(Config.RideFare), "success")
            TriggerClientEvent('AIBus:client:getOnBus', src, busNetId)
        else
            if Config.Debug then print(('[AIBus-server] Payment FAILED for player %s.'):format(src)) end
            TriggerClientEvent('QBCore:Notify', src, "You can't afford the bus fare!", "error")
        end
    else
        TriggerClientEvent('AIBus:client:getOnBus', src, busNetId)
    end
end)

RegisterServerEvent('AIBus:server:removeRogueBus', function(busNetId, routeName)
    busStrikes[busNetId] = (busStrikes[busNetId] or 0) + 1
    if Config.Debug then print(('[AIBus-server] Bus %s reported as rogue. Strike count: %s'):format(busNetId, busStrikes[busNetId])) end

    if busStrikes[busNetId] >= 3 then -- If 3 different clients (or the same one 3 times) report it, remove it for good.
        if not createdRoutes[routeName] then return end
        for i = #createdRoutes[routeName], 1, -1 do
            if createdRoutes[routeName][i].netId == busNetId then
                table.remove(createdRoutes[routeName], i)
                local busEntity = NetworkGetEntityFromNetworkId(busNetId)
                if DoesEntityExist(busEntity) then
                    -- You might need a client event to delete the entities properly
                    TriggerClientEvent('AIBus:client:forceDeleteBus', -1, busNetId)
                end
                busStrikes[busNetId] = nil -- Clean up
                if Config.Debug then print('[AIBus-server] Bus failed strike check. Removed from tracking. A replacement can now be spawned.') end
                break
            end
        end
    end
end)

-- NEW: Admin command direct delete event
RegisterServerEvent('AIBus:server:adminDeleteBus', function(busNetId, routeName)
    if not createdRoutes[routeName] then return end
    for i = #createdRoutes[routeName], 1, -1 do
        if createdRoutes[routeName][i].netId == busNetId then
            table.remove(createdRoutes[routeName], i)
            if Config.Debug then print(('[AIBus-server] Admin command removed bus %s from tracking.'):format(busNetId)) end
            TriggerClientEvent('AIBus:client:forceDeleteBus', -1, busNetId)
            break
        end
    end
end)

RegisterNetEvent('AIBus:client:forceDeleteBus', function(busNetId)
    local bus = NetToVeh(busNetId)
    if DoesEntityExist(bus) then
        local driver = GetPedInVehicleSeat(bus, -1)
        if DoesEntityExist(driver) and not IsPedAPlayer(driver) then
            DeleteEntity(driver)
        end
        DeleteEntity(bus)
    end
end)

RegisterServerEvent('AIBus:server:playerTookOverBus', function(busNetId, routeName)
    if not createdRoutes[routeName] then return end
    for i = #createdRoutes[routeName], 1, -1 do
        if createdRoutes[routeName][i].netId == busNetId then
            table.remove(createdRoutes[routeName], i)
            if Config.Debug then print('[AIBus-server] Removed taken-over bus from tracking. A replacement will be spawned.') end
            break
        end
    end
end)

-- =================================================================
-- PLAYER SYNC EVENTS
-- =================================================================

AddEventHandler('playerSpawned', function()
    TriggerServerEvent('AIBus:server:syncBusesForNewPlayer')
end)

RegisterServerEvent('AIBus:server:syncBusesForNewPlayer', function()
    local src = source
    CreateThread(function()
        Wait(1500)
        for routeName, routeData in pairs(createdRoutes) do
            local routeConfig = nil
            for _, r in ipairs(Config.Routes) do if r.Name == routeName then routeConfig = r; break end end
            if routeConfig then
                for _, busData in ipairs(routeData) do
                    if DoesEntityExist(NetworkGetEntityFromNetworkId(busData.netId)) then
                        TriggerClientEvent('AIBus:client:initiateBus', src, busData.netId, routeConfig, busData.startStopIndex, busData.ownerId)
                    end
                end
            end
        end
    end)
end)

RegisterServerEvent('AIBus:server:RequestFullSync', function()
    local src = source
    local activeBuses = {}
    for routeName, routeData in pairs(createdRoutes) do
        local routeConfig = nil
        for _, r in ipairs(Config.Routes) do if r.Name == routeName then routeConfig = r; break end end
        if routeConfig then
            for _, busData in ipairs(routeData) do
                if DoesEntityExist(NetworkGetEntityFromNetworkId(busData.netId)) then
                    table.insert(activeBuses, { netId = busData.netId, route = routeConfig, startStopIndex = busData.startStopIndex, ownerId = busData.ownerId })
                end
            end
        end
    end
    if #activeBuses > 0 then
        TriggerClientEvent('AIBus:client:syncBuses', src, activeBuses)
    end
end)

-- =================================================================
-- ADMIN COMMANDS
-- =================================================================

QBCore.Commands.Add("forcebusowner", "Force change bus owner", {{name="plate", help="License plate of the bus"}, {name="newownerid", help="Server ID of the new owner"}}, true, function(source, args)
    local plate = args[1]
    local newOwnerId = tonumber(args[2])
    if not plate or not newOwnerId then
        TriggerClientEvent('QBCore:Notify', source, "Usage: /forcebusowner [plate] [new_owner_id]", "error")
        return
    end
    local foundBus, busToUpdate = false, nil
    for routeName, buses in pairs(createdRoutes) do
        for i, busData in ipairs(buses) do
            if busData.plate == plate then
                busToUpdate = busData
                foundBus = true
                break
            end
        end
        if foundBus then break end
    end
    if not foundBus then
        TriggerClientEvent('QBCore:Notify', source, "A bus with that license plate was not found.", "error")
        return
    end
    if not GetPlayerPed(newOwnerId) then
        TriggerClientEvent('QBCore:Notify', source, "The target player ID is not online.", "error")
        return
    end
    busToUpdate.ownerId = newOwnerId
    TriggerClientEvent('AIBus:client:updateOwner', -1, busToUpdate.netId, newOwnerId)
    TriggerClientEvent('QBCore:Notify', source, ("Ownership of bus %s transferred to player %s."):format(plate, newOwnerId), "success")
end, "admin")

-- NEW: Admin command to clean up buses
QBCore.Commands.Add("cleanupbusses", "Remove AI buses from the server.", {{name="force", help="Optional: Type 'force' to remove buses with players."}}, true, function(source, args)
    local forceCleanup = (args[1] and string.lower(args[1]) == 'force') or false
    
    if forceCleanup then
        TriggerClientEvent('QBCore:Notify', source, "Requesting all clients to FORCE cleanup of ALL AI buses...", "primary")
    else
        TriggerClientEvent('QBCore:Notify', source, "Requesting all clients to cleanup EMPTY AI buses...", "primary")
    end

    -- Trigger a client-side check on all clients
    TriggerClientEvent('AIBus:client:requestCleanup', -1, forceCleanup)
end, "admin")
