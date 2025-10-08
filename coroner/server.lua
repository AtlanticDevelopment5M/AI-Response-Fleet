-- =========================================================
--  arp_coroner - server.lua
--  Spawns an AI coroner (cvan) that bags a body and respawns target
--  Trigger via /coroner (playerid) or ox_target (handled client-side)
-- =========================================================

-- ============= NOTIFY BRIDGE =============================
-- Uses Forge Chat if present, falls back to chat:addMessage
local function notify(playerId, msg, title, bg)
    title = title or 'Coroner'
    bg = bg or 'default'

    if GetResourceState('forge-chat') == 'started' then
        TriggerEvent('forge-chat:exportSendMessage', playerId, msg, title, bg)
    else
        TriggerClientEvent('chat:addMessage', playerId, {
            args = { title, msg }
        })
    end
end
-- =========================================================

local function dbg(msg)
    if Config and Config.debug then
        print(('[arp_coroner] %s'):format(msg))
    end
end

local function loadModel(hash)
    if type(hash) == 'string' then hash = joaat(hash) end
    if not IsModelInCdimage(hash) then return false end

    RequestModel(hash)
    local start = GetGameTimer()
    while not HasModelLoaded(hash) do
        Wait(10)
        if GetGameTimer() - start > 8000 then
            return false
        end
    end
    return true
end

local function nearestRoadSpawn(fromCoords, distance)
    -- Pick a point roughly "distance" meters away in a random heading, then snap to road
    local heading = math.random() * 360.0
    local rx = fromCoords.x + distance * math.cos(math.rad(heading))
    local ry = fromCoords.y + distance * math.sin(math.rad(heading))
    local found, node, nodeHeading = GetClosestVehicleNodeWithHeading(rx, ry, fromCoords.z, 1, 3.0, 0)

    if not found then
        -- fallback: try directly from origin
        found, node, nodeHeading = GetClosestVehicleNodeWithHeading(fromCoords.x, fromCoords.y, fromCoords.z, 1, 3.0, 0)
    end

    if not found then
        node = fromCoords
        nodeHeading = heading
    end

    return vector3(node.x, node.y, node.z), nodeHeading
end

local function openBack(v)
    -- Trunk (index 5) is usually rear hatch for vans/SUVs
    SetVehicleDoorOpen(v, 5, false, false)
end

local function closeBack(v)
    SetVehicleDoorShut(v, 5, false)
end

-- Small helper to compute distance between two coords
local function dist(a, b)
    return #(a - b)
end

-- ============= MAIN ENTRYPOINT ===========================
-- Called by chat command and ox_target client
RegisterNetEvent('arp_coroner:request', function(targetServerId)
    local src = source
    local target = tonumber(targetServerId or -1)
    if not target or target <= 0 then
        notify(src, 'Usage: /coroner (playerid)')
        return
    end

    local pedSrc = GetPlayerPed(src)
    local pedTarget = GetPlayerPed(target)
    if pedSrc == 0 or pedTarget == 0 then
        return
    end

    local srcCoords = GetEntityCoords(pedSrc)
    local targetCoords = GetEntityCoords(pedTarget)

    -- Proximity check
    if dist(srcCoords, targetCoords) > (Config.maxCallDistance or 15.0) then
        notify(src, ('Too far from target (%.1fm > %.1fm).'):format(
            dist(srcCoords, targetCoords), Config.maxCallDistance or 15.0))
        return
    end

    -- Death check
    if not IsPedDeadOrDying(pedTarget, true) and GetEntityHealth(pedTarget) > 101 then
        notify(src, 'Target is not dead.')
        return
    end

    -- Load models
    local vehModel = Config.vehicleModel or 'cvan'
    local pedModel = Config.pedModel or 's_m_m_doctor_01'
    if not loadModel(vehModel) or not loadModel(pedModel) then
        notify(src, 'Failed to load vehicle/ped model.')
        return
    end

    -- Spawn van on nearest road ~spawnDistance away from the CALLER (source)
    local spawnDist = Config.spawnDistance or 40.0
    local spawnPos, spawnHeading = nearestRoadSpawn(srcCoords, spawnDist)

    local veh = CreateVehicle(joaat(vehModel), spawnPos.x, spawnPos.y, spawnPos.z, spawnHeading, true, true)
    if not DoesEntityExist(veh) then
        notify(src, 'Failed to spawn van.')
        return
    end
    SetVehicleOnGroundProperly(veh)

    local ped = CreatePedInsideVehicle(veh, 26, joaat(pedModel), -1, true, false)
    if not DoesEntityExist(ped) then
        DeleteEntity(veh)
        notify(src, 'Failed to spawn coroner.')
        return
    end

    SetEntityAsMissionEntity(veh, true, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetVehicleEngineOn(veh, true, true, false)

    -- Visual config
    if Config.liveryIndex ~= nil then
        SetVehicleLivery(veh, Config.liveryIndex)
    end
    if Config.extras then
        for id, enabled in pairs(Config.extras) do
            if DoesExtraExist(veh, id) then
                SetVehicleExtra(veh, id, not enabled)
            end
        end
    end
    if Config.useEmergencyLights then
        SetVehicleSiren(veh, true)
        SetVehicleHasMutedSirens(veh, false)
        SetVehicleLights(veh, 2)
    end

    -- Drive near the target
    local driveSpeed = Config.driveSpeed or 18.0
    TaskVehicleDriveToCoord(ped, veh, targetCoords.x, targetCoords.y, targetCoords.z, driveSpeed, 0, joaat(vehModel), 786603, 5.0, true)
    dbg('Driving to target...')

    -- Wait until the van is close
    local startWait = GetGameTimer()
    while DoesEntityExist(veh) and dist(GetEntityCoords(veh), targetCoords) > 7.5 do
        Wait(250)
        if GetGameTimer() - startWait > 30000 then
            dbg('Timeout driving to target; proceeding anyway.')
            break
        end
    end

    -- Stop and get out
    if DoesEntityExist(veh) and DoesEntityExist(ped) then
        TaskVehicleTempAction(ped, veh, 27, 2000) -- brake
        TaskLeaveVehicle(ped, veh, 256)
        local leaveWait = GetGameTimer()
        while IsPedInAnyVehicle(ped, false) and GetGameTimer() - leaveWait < 6000 do
            Wait(50)
        end
    end

    -- Walk to the body using pathfinding (BETTER than TaskGoStraightToCoord)
    -- TASK_GO_TO_COORD_ANY_MEANS(Ped, x,y,z, speed, p5, p6, walkingStyle, p8)
    if DoesEntityExist(ped) then
        TaskGoToCoordAnyMeans(ped, targetCoords.x, targetCoords.y, targetCoords.z, 1.25, 0, false, 786603, 0xbf800000)
        local steps = 0
        while DoesEntityExist(ped) and dist(GetEntityCoords(ped), targetCoords) > 1.8 and steps < 120 do
            Wait(100)
            steps = steps + 1
        end
        ClearPedTasksImmediately(ped)
    end

    -- Signal the target to respawn "at the same time" the coroner starts tending
    TriggerClientEvent('arp_coroner:respawn', target)

    -- Tend animation (scenario)
    if DoesEntityExist(ped) then
        TaskStartScenarioInPlace(ped, 'CODE_HUMAN_MEDIC_TEND_TO_DEAD', 0, true)
        Wait(Config.tendDuration or 3500)
        ClearPedTasksImmediately(ped)
    end

    -- Spawn a body bag and "carry" it
    local bagModel = joaat('prop_body_bag_01')
    if loadModel(bagModel) then
        local bag = CreateObject(bagModel, targetCoords.x, targetCoords.y, targetCoords.z, true, true, true)
        if DoesEntityExist(bag) and DoesEntityExist(ped) then
            SetEntityAsMissionEntity(bag, true, true)
            -- Attach to right hand (bone index 57005)
            AttachEntityToEntity(
                bag,
                ped,
                GetPedBoneIndex(ped, 57005),
                0.15, 0.0, -0.1,
                0.0, 90.0, 0.0,
                true, true, false, true, 2, true
            )

            Wait(Config.bagCarryDelay or 500)

            -- Walk back to the rear of the van using TaskGoToCoordAnyMeans
            if DoesEntityExist(veh) then
                local backPos = GetOffsetFromEntityInWorldCoords(veh, -2.0, -3.0, 0.0)
                TaskGoToCoordAnyMeans(ped, backPos.x, backPos.y, backPos.z, 1.1, 0, false, 786603, 0xbf800000)

                local s = 0
                while DoesEntityExist(ped) and dist(GetEntityCoords(ped), backPos) > 2.2 and s < 120 do
                    Wait(100)
                    s = s + 1
                end

                openBack(veh)
                Wait(400)

                -- Move bag into cargo, then delete
                local cargoPos = GetOffsetFromEntityInWorldCoords(veh, -1.0, -1.5, 0.0)
                DetachEntity(bag, true, true)
                SetEntityCoordsNoOffset(bag, cargoPos.x, cargoPos.y, cargoPos.z, false, false, false)
                Wait(Config.loadDuration or 1500)
                if DoesEntityExist(bag) then DeleteEntity(bag) end

                closeBack(veh)
            end
        end
    end

    -- Get back in, drive away a bit, despawn
    if DoesEntityExist(ped) and DoesEntityExist(veh) then
        TaskEnterVehicle(ped, veh, 3000, -1, 1.0, 1, 0)
        local enterWait = GetGameTimer()
        while not IsPedInAnyVehicle(ped, false) and GetGameTimer() - enterWait < 6000 do
            Wait(50)
        end

        TaskVehicleDriveWander(ped, veh, driveSpeed, 786603)
        Wait(Config.driveOffTime or 5000)
    end

    if DoesEntityExist(ped) then DeleteEntity(ped) end
    if DoesEntityExist(veh) then DeleteEntity(veh) end
end)

-- ============= CHAT COMMAND MODE =========================
-- Only enabled when triggerMode == 'chat'
CreateThread(function()
    if not Config or Config.triggerMode ~= 'chat' then return end

    RegisterCommand('coroner', function(src, args)
        local target = tonumber(args[1] or -1)
        if not target or target <= 0 then
            notify(src, 'Usage: /coroner (playerid)')
            return
        end
        TriggerEvent('arp_coroner:request', target)
    end, false)
end)

