
-- ===== Coroner =====
-- server/main.lua
local U = require 'shared/utils'

local function addBlipFor(src, netId, optic)
  TriggerClientEvent('arp_ai:blip:add', src, netId, optic or {})
end

local function removeBlipFor(src, netId)
  TriggerClientEvent('arp_ai:blip:remove', src, netId)
end


-- ===== Coroner with body bag + cop animation + nearest-hospital respawn =====
RegisterNetEvent('arp_ai:request:coroner', function(targetId)
    local src = source
    local C = Config.Coroner
    if not C then return end

    local srcPed = GetPlayerPed(src)
    if not srcPed or srcPed == 0 then return end

    -- Where is the body?
    local tPed, tCoords
    if targetId then
        tPed = GetPlayerPed(targetId)
        if tPed and tPed ~= 0 then tCoords = GetEntityCoords(tPed) end
    end
    if not tCoords then
        tCoords = GetEntityCoords(srcPed)
    end

    -------------------------------------------------------------------------
    -- 1) Officer animation: kneel/bagging before bag appears
    -------------------------------------------------------------------------
    do
        local dict, name = "amb@medic@standing@tendtodead@base", "base"
        RequestAnimDict(dict)
        local t = GetGameTimer() + 8000
        while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(0) end
        TaskPlayAnim(srcPed, dict, name, 8.0, -8.0, 5000, 1, 0, false, false, false)
        Wait(4500)
        ClearPedTasks(srcPed)
    end

    -------------------------------------------------------------------------
    -- 2) Spawn body bag at the target location
    -------------------------------------------------------------------------
    local bagHash = joaat(C.BagModel or 'prop_body_bag_01')
    if not IsModelInCdimage(bagHash) then
        print('[arp_coroner] Invalid BagModel; falling back to prop_body_bag_01')
        bagHash = joaat('prop_body_bag_01')
    end
    RequestModel(bagHash)
    do
        local t = GetGameTimer() + 8000
        while not HasModelLoaded(bagHash) and GetGameTimer() < t do Wait(0) end
    end
    local bodyBag = CreateObject(bagHash, tCoords.x, tCoords.y, tCoords.z - 0.9, true, true, true)
    PlaceObjectOnGroundProperly(bodyBag)
    SetEntityAsMissionEntity(bodyBag, true, true)

    -------------------------------------------------------------------------
    -- 3) Spawn coroner van + ped at a road node
    -------------------------------------------------------------------------
    local spawnAt, heading = U.findRoadNodeAhead(srcPed, C.SpawnDistance or 40.0)
    local veh = U.spawnVehicle(C.VehicleModel or 'cvan', spawnAt, heading, C.UseEmergencyLights)
    if not veh then
        if DoesEntityExist(bodyBag) then DeleteEntity(bodyBag) end
        return
    end
    U.applyVehicleSetup(veh, { livery = C.LiveryIndex, extras = C.Extras })

    local ped = U.spawnPed(C.PedModel or 's_m_m_doctor_01', spawnAt, heading, veh)
    if not ped then
        DeleteEntity(veh)
        if DoesEntityExist(bodyBag) then DeleteEntity(bodyBag) end
        return
    end

    -- Optional blip for the caller (requires client/blips.lua)
    if Config.Blips and Config.Blips.Coroner and Config.Blips.Coroner.enabled then
        local netId = NetworkGetNetworkIdFromEntity(veh)
        TriggerClientEvent('arp_ai:blip:add', src, netId, Config.Blips.Coroner)
        SetTimeout((C.DriveOffTime or 5000), function()
            TriggerClientEvent('arp_ai:blip:remove', src, netId)
        end)
    end

    -------------------------------------------------------------------------
    -- 4) Drive to the scene and detect arrival
    -------------------------------------------------------------------------
    TaskVehicleDriveToCoordLongrange(ped, veh, tCoords.x, tCoords.y, tCoords.z, C.DriveSpeed or 18.0, 786603, 8.0)
    local arrived = false
    while DoesEntityExist(veh) do
        local vpos = GetEntityCoords(veh)
        if #(vpos - tCoords) <= (C.ArrivalRange or 12.0) then
            arrived = true
            break
        end
        Wait(250)
    end

    if arrived then
        -- park + exit
        TaskVehicleTempAction(ped, veh, 27, 2000) -- handbrake-ish
        TaskLeaveVehicle(ped, veh, 256)
        while IsPedInAnyVehicle(ped, false) do Wait(0) end

        -- walk to bag
        TaskGoToCoordAnyMeans(ped, GetEntityCoords(bodyBag), 1.0, 0, false, 786603, 0xbf800000)
        local tEnd = GetGameTimer() + 10000
        while #(GetEntityCoords(ped) - GetEntityCoords(bodyBag)) > 2.2 and GetGameTimer() < tEnd do Wait(100) end

        -- tend animation, then pick up bag (attach to hand) + carry
        U.playAnim(ped, "amb@medic@standing@tendtodead@base", "base", 1, 1.0)
        Wait(math.floor((C.TendDuration or 3500) * 0.75))
        ClearPedTasks(ped)

        local hand = GetPedBoneIndex(ped, 57005) -- right hand
        AttachEntityToEntity(
            bodyBag, ped, hand,
            0.17, 0.02, -0.26,    -- position offset (tune for your bag model)
            90.0, 180.0, 80.0,    -- rotation offset
            false, false, true, false, 2, true
        )
        U.playAnim(ped, "anim@heists@box_carry@", "idle", 49, 1.0)

        ---------------------------------------------------------------------
        -- 5) Respawn the target at the nearest hospital (from config)
        ---------------------------------------------------------------------
        if targetId then
            local hosp = U.nearestHospital(C.Hospitals, tCoords) or { coords = tCoords, heading = 0.0 }
            TriggerClientEvent('arp_coroner:respawnAtHospital', targetId, hosp.coords, hosp.heading or 0.0, hosp.label or "Hospital")
        end

        -- carry to van rear and load
        local rear = GetOffsetFromEntityInWorldCoords(veh, 0.0, -2.2, 0.0)
        TaskGoToCoordAnyMeans(ped, rear, 1.0, 0, false, 786603, 0xbf800000)
        tEnd = GetGameTimer() + 10000
        while #(GetEntityCoords(ped) - rear) > 2.2 and GetGameTimer() < tEnd do Wait(100) end

        local o = C.LoadOffset or { pos = vector3(0.0,-2.2,0.6), rot = vector3(0.0,0.0,0.0) }
        DetachEntity(bodyBag, true, true)
        AttachEntityToEntity(bodyBag, veh, -1, o.pos, o.rot, false, false, true, false, 2, true)
        Wait(750)

        -- return to driver seat
        TaskEnterVehicle(ped, veh, 5000, -1, 1.0, 1, 0)
        local tEnter = GetGameTimer() + 8000
        while not IsPedInAnyVehicle(ped, false) and GetGameTimer() < tEnter do Wait(0) end
    end

    -------------------------------------------------------------------------
    -- 6) Drive away & cleanup (bag attached to van will be deleted too)
    -------------------------------------------------------------------------
    local away = GetOffsetFromEntityInWorldCoords(veh, 0.0, 120.0, 0.0)
    U.driveAndCleanup(ped, veh, away, C.DriveSpeed or 18.0, 786603, (C.DriveOffTime or 5000)/1000, bodyBag)

    Config.Notify(src, 'Coroner dispatched.', 'Coroner')
end)


-- ===== Transport =====
RegisterNetEvent('arp_ai:request:transport', function(targetId)
  local src = source
  local C = Config.Transport
  if not C then return end
  if C.IsSourceOnDuty and not C.IsSourceOnDuty(src) then
    return Config.Notify(src, 'You must be on duty to request transport.', 'Transport', 'red')
  end

  local srcPed = GetPlayerPed(src)
  local spawnAt, heading = U.findRoadNodeAhead(srcPed, C.SpawnDistance or 40.0)
  local veh = U.spawnVehicle(C.Vehicle.model or 'police', spawnAt, heading, C.Vehicle.sirensOn)
  if not veh then return end
  U.applyVehicleSetup(veh, C.Vehicle)

  local ped = U.spawnPed(C.Officer.model or 'mp_m_freemode_01', spawnAt, heading, veh)
  -- (Optional) apply MP freemode components/props here if desired

  -- Grab & seat suspect server-side (example/fallback; your client may do anims)
  if targetId then
    local tPed = GetPlayerPed(targetId)
    TaskEnterVehicle(tPed, veh, 5000, (C.RearSeatPreference[1] or 1), 1.0, 1, 0)
  end

  local away = GetOffsetFromEntityInWorldCoords(veh, 0.0, 180.0, 0.0)
  U.driveAndCleanup(ped, veh, away, 18.0, 786603, C.DriveAwaySeconds or 10)
  if C.OnTransportComplete then C.OnTransportComplete(src, targetId) end
  Config.Notify(src, 'Transport en route.', 'Transport')
end)

-- ===== Tow =====
RegisterNetEvent('arp_ai:request:tow', function(targetNetId)
  local src = source
  local C = Config.Tow
  if not C then return end

  local srcPed = GetPlayerPed(src)
  local spawnAt, heading = U.findRoadNodeAhead(srcPed, C.SpawnDistance or 40.0)
  local truckModel = (C.TowMode == 'hook') and (C.HookModel or 'towtruck2') or (C.FlatbedModel or 'flatbed')
  local truck = U.spawnVehicle(truckModel, spawnAt, heading, true)
  if not truck then return end
  local driver = U.spawnPed(C.DriverModel or 's_m_m_trucker_01', spawnAt, heading, truck)

  -- Attach target vehicle (basic flow; you can replace with your own)
  local targetVeh = NetworkGetEntityFromNetworkId(targetNetId)
  if targetVeh ~= 0 and DoesEntityExist(targetVeh) then
    if C.TowMode == 'hook' then
      AttachVehicleToTowTruck(truck, targetVeh, true, 0.0, 0.0, 0.0)
    else
      AttachEntityToEntity(targetVeh, truck, 20, C.FlatbedOffset.pos, C.FlatbedOffset.rot, false, false, true, false, 2, true)
    end
  end

  local away = GetOffsetFromEntityInWorldCoords(truck, 0.0, 160.0, 0.0)
  U.driveAndCleanup(driver, truck, away, C.TowSpeed or 18.0, C.DrivingStyle or 786603, C.DriveAwaySeconds or 10, targetVeh)
  Config.Notify(src, 'Tow truck en route.', 'Tow')
end)
