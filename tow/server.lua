local towingTargets = {}  -- netId => true (busy)

local function requestModel(model)
    if type(model) == 'string' then model = joaat(model) end
    if not IsModelInCdimage(model) then return false end
    RequestModel(model)
    local deadline = GetGameTimer() + 10000
    while not HasModelLoaded(model) do
        if GetGameTimer() > deadline then return false end
        Wait(0)
    end
    return model
end

local function findRoadSpawnNear(coords, dist, tryAhead, headingHint)
    local nodeCoord, nodeHeading = vector3(0,0,0), 0.0
    local success = false
    if tryAhead and headingHint then
        local ahead = coords + (headingHint * dist)
        success, nodeCoord, nodeHeading = GetClosestVehicleNodeWithHeading(ahead.x, ahead.y, ahead.z, 1, 3.0, 0)
    end
    if not success then
        success, nodeCoord, nodeHeading = GetClosestVehicleNodeWithHeading(coords.x, coords.y, coords.z, 1, 3.0, 0)
        if success then
            -- push it outwards by dist
            local dir = (coords - nodeCoord)
            if #(dir) < 1.0 then dir = vector3(0.0, 1.0, 0.0) end
            dir = (dir / #(dir)) * dist
            local fallback = nodeCoord + dir
            local ok2, node2, head2 = GetClosestVehicleNodeWithHeading(fallback.x, fallback.y, fallback.z, 1, 3.0, 0)
            if ok2 then nodeCoord, nodeHeading = node2, head2 end
        end
    end
    return nodeCoord, nodeHeading
end

local function driveToCoords(ped, veh, dest, speed, style)
    TaskVehicleDriveToCoord(ped, veh, dest.x, dest.y, dest.z, speed, 0, GetEntityModel(veh), style, 5.0, true)
end

-- Core tow routine (server-owned entities for clean networking)
local function spawnTowAndAttach(src, targetNet, callerCoords)
    if towingTargets[targetNet] then
        Config.Notify(src, '~y~A tow is already en route for that vehicle.')
        return
    end

    local targetEnt = NetworkGetEntityFromNetworkId(targetNet)
    if targetEnt == 0 or not DoesEntityExist(targetEnt) then
        Config.Notify(src, '~r~Target vehicle no longer exists.')
        return
    end

    if GetEntitySpeed(targetEnt) > Config.MaxTargetSpeed then
        Config.Notify(src, '~y~Vehicle must be stationary to tow.')
        return
    end

    -- choose model based on mode
    local towModel = (Config.TowMode == 'hook') and Config.HookModel or Config.FlatbedModel
    local drvModel = Config.DriverModel

    local towHash = requestModel(towModel)
    local pedHash = requestModel(drvModel)
    if not towHash or not pedHash then
        Config.Notify(src, '~r~Tow assets are missing/not streamed.')
        return
    end

    towingTargets[targetNet] = true

    -- figure heading vector from caller (roughly facing)
    local callerPed = GetPlayerPed(src)
    local callerHeading = GetEntityHeading(callerPed)
    local forwardVec = vector3(-math.sin(math.rad(callerHeading)), math.cos(math.rad(callerHeading)), 0.0)

    local spawnPos, spawnHeading = findRoadSpawnNear(callerCoords, Config.SpawnDistance, Config.SpawnTryAhead, forwardVec)
    local tow = CreateVehicle(towHash, spawnPos.x, spawnPos.y, spawnPos.z, spawnHeading, true, true)
    local driver = CreatePedInsideVehicle(tow, 26, pedHash, -1, true, false)

    SetVehicleEngineOn(tow, true, true, false)
    SetVehicleSiren(tow, false) -- tweak if you use emergency lights on your tow model
    SetEntityAsMissionEntity(tow, true, true)
    SetEntityAsMissionEntity(driver, true, true)

    -- head toward the target vehicle
    local targetPos = GetEntityCoords(targetEnt)
    driveToCoords(driver, tow, targetPos, Config.TowSpeed, Config.DrivingStyle)

    -- wait until within AttachRange or timeout
    local deadline = GetGameTimer() + 30000 -- 30s approach window
    while DoesEntityExist(tow) and DoesEntityExist(targetEnt) do
        local dist = #(GetEntityCoords(tow) - GetEntityCoords(targetEnt))
        if dist <= Config.AttachRange then break end
        if GetGameTimer() > deadline then break end
        Wait(250)
    end

    if not (DoesEntityExist(tow) and DoesEntityExist(targetEnt)) then
        Config.Notify(src, '~r~Tow failed: entities lost.')
        goto cleanup
    end

    -- stop and align a bit
    TaskVehicleTempAction(driver, tow, 1, 2000) -- brake
    Wait(800)

    -- ATTACH
    if Config.TowMode == 'hook' then
        -- Place truck behind target to improve hook attach
        local tgtHeading = GetEntityHeading(targetEnt)
        SetEntityHeading(tow, tgtHeading)
        -- Try native hook attach
        -- 0x29A16F8D621C4508 AttachVehicleToTowTruck(towTruck, vehicle, rear, hookOffsetX, hookOffsetY, hookOffsetZ)
        AttachVehicleToTowTruck(tow, targetEnt, true, 0.0, 0.0, 0.0)
    else
        -- FLATBED attachment via generic offset
        local off = Config.FlatbedOffset
        local ox, oy, oz = off.pos.x, off.pos.y, off.pos.z
        local rx, ry, rz = off.rot.x, off.rot.y, off.rot.z

        -- freeze target briefly during attach to avoid physics jolts
        FreezeEntityPosition(targetEnt, true)
        SetVehicleEngineOn(targetEnt, false, true, true)
        SetVehicleDoorsLocked(targetEnt, 2)

        AttachEntityToEntity(
            targetEnt, tow,
            20, -- bone index; often 20 works for many flatbeds. adjust if needed.
            ox, oy, oz,
            rx * 1.0, ry * 1.0, rz * 1.0,
            false, false, true, false, 2, true
        )
        FreezeEntityPosition(targetEnt, false)
    end

    -- Drive away for N seconds, then despawn both
    local farNode, farHead = GetClosestVehicleNodeWithHeading(targetPos.x + 150.0, targetPos.y + 150.0, targetPos.z, 1, 3.0, 0)
    if farNode then
        driveToCoords(driver, tow, farNode, Config.TowSpeed, Config.DrivingStyle)
    else
        TaskVehicleDriveWander(driver, tow, Config.TowSpeed, Config.DrivingStyle)
    end

    local untilTime = GetGameTimer() + (Config.DriveAwaySeconds * 1000)
    while GetGameTimer() < untilTime and DoesEntityExist(tow) do
        Wait(500)
    end

::cleanup::
    -- Detach (hook mode auto detaches on delete, but be explicit)
    if DoesEntityExist(targetEnt) then
        if Config.TowMode == 'hook' then
            DetachVehicleFromTowTruck(tow, targetEnt)
        else
            if IsEntityAttachedToEntity(targetEnt, tow) then
                DetachEntity(targetEnt, true, true)
            end
        end
    end

    -- Delete the towed vehicle as requested
    if DoesEntityExist(targetEnt) then
        DeleteEntity(targetEnt)
    end

    if DoesEntityExist(driver) then
        DeleteEntity(driver)
    end
    if DoesEntityExist(tow) then
        DeleteEntity(tow)
    end

    towingTargets[targetNet] = nil
end

RegisterNetEvent('arp_tow:requestTow', function(targetNetId, playerCoords)
    local src = source
    if not targetNetId then return end

    -- basic sanity
    local ent = NetworkGetEntityFromNetworkId(targetNetId)
    if ent == 0 or not DoesEntityExist(ent) then
        Config.Notify(src, '~r~Invalid vehicle.')
        return
    end

    -- Verify player is near the target (server-side check)
    local ped = GetPlayerPed(src)
    local pcoords = GetEntityCoords(ped)
    local vcoords = GetEntityCoords(ent)
    if #(pcoords - vcoords) > (Config.PlayerVehicleRange + 1.5) then
        Config.Notify(src, '~r~You must be next to the vehicle to tow.')
        return
    end

    Config.Notify(src, '~b~Tow en route...')
    spawnTowAndAttach(src, targetNetId, vector3(playerCoords.x, playerCoords.y, playerCoords.z))
end)

-- Cleanup on stop (best-effort)
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for netId,_ in pairs(towingTargets) do
        local ent = NetworkGetEntityFromNetworkId(netId)
        if ent ~= 0 and DoesEntityExist(ent) then
            if IsEntityAttached(ent) then DetachEntity(ent, true, true) end
        end
    end
end)

