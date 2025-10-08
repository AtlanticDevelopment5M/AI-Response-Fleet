local U = require 'shared/utils'

-- ===== Coroner =====
RegisterNetEvent('arp_ai:request:coroner', function(targetId)
  local src = source
  local C = Config.Coroner
  if not C then return end

  local srcPed = GetPlayerPed(src)
  local spawnAt, heading = U.findRoadNodeAhead(srcPed, C.SpawnDistance or 40.0)
  local veh = U.spawnVehicle(C.VehicleModel or 'cvan', spawnAt, heading, C.UseEmergencyLights)
  if not veh then return end

  local ped = U.spawnPed(C.PedModel or 's_m_m_doctor_01', spawnAt, heading, veh)
  U.applyVehicleSetup(veh, { livery = C.LiveryIndex, extras = C.Extras })

  -- Tell target to respawn (client handles fade/resurrect)
  if targetId then TriggerClientEvent('arp_coroner:respawn', targetId) end

  -- Drive off & cleanup
  local away = GetOffsetFromEntityInWorldCoords(veh, 0.0, 120.0, 0.0)
  U.driveAndCleanup(ped, veh, away, C.DriveSpeed or 18.0, 786603, (C.DriveOffTime or 5000)/1000)
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
