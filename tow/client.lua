local function getClosestVehicleNearPlayer(range)
    local ped = PlayerPedId()
    local pcoords = GetEntityCoords(ped)
    local veh = 0
    local minDist = range or 3.0

    -- try vehicle player is facing
    local forwardVeh = GetVehiclePedIsIn(ped, false)
    if forwardVeh ~= 0 then
        -- if inside a vehicle, disallow (we want “next to” a vehicle)
        return 0
    end

    -- iterate vehicles nearby
    local handle, vehIter = FindFirstVehicle()
    local success
    repeat
        if DoesEntityExist(vehIter) then
            local dist = #(GetEntityCoords(vehIter) - pcoords)
            if dist < minDist then
                minDist = dist
                veh = vehIter
            end
        end
        success, vehIter = FindNextVehicle(handle)
    until not success
    EndFindVehicle(handle)

    return veh
end

-- Simple notify bridge
RegisterNetEvent('arp_tow:notify', function(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, true)
end)

-- Command trigger
if Config.EnableCommand then
    RegisterCommand('tow', function()
        local veh = getClosestVehicleNearPlayer(Config.PlayerVehicleRange)
        if veh == 0 then
            Config.Notify(PlayerId() ~= -1 and PlayerId() or cache.serverId, '~r~No vehicle nearby to tow.')
            return
        end

        -- sanity checks
        if IsEntityAVehicle(veh) then
            if GetEntitySpeed(veh) > Config.MaxTargetSpeed then
                Config.Notify(cache.serverId, '~y~Vehicle must be stationary to tow.')
                return
            end
            local netId = NetworkGetNetworkIdFromEntity(veh)
            local coords = GetEntityCoords(PlayerPedId())
            TriggerServerEvent('arp_tow:requestTow', netId, coords)
        end
    end, false)
end

-- ox_target integration
CreateThread(function()
    if not Config.EnableOxTarget then return end
    if not pcall(function() return exports.ox_target end) then return end

    exports.ox_target:addGlobalVehicle({
        {
            label = 'Call Tow',
            icon = 'fa-solid fa-truck-pickup',
            onSelect = function(data)
                local veh = data.entity
                if not DoesEntityExist(veh) then return end
                if GetEntitySpeed(veh) > Config.MaxTargetSpeed then
                    Config.Notify(cache.serverId, '~y~Vehicle must be stationary to tow.')
                    return
                end
                local netId = NetworkGetNetworkIdFromEntity(veh)
                local coords = GetEntityCoords(PlayerPedId())
                TriggerServerEvent('arp_tow:requestTow', netId, coords)
            end,
            distance = Config.PlayerVehicleRange + 0.5,
            canInteract = function(entity, distance, coords, name)
                local ped = PlayerPedId()
                return not IsPedInAnyVehicle(ped, false) and distance <= Config.PlayerVehicleRange + 0.5
            end
        }
    })
end)

