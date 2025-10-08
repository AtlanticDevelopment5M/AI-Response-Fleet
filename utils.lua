local M = {}

function M.ensureModel(model)
  model = type(model) == 'string' and joaat(model) or model
  if not IsModelInCdimage(model) then return false end
  RequestModel(model)
  local t = GetGameTimer() + 10000
  while not HasModelLoaded(model) and GetGameTimer() < t do Wait(0) end
  return HasModelLoaded(model) and model or false
end

function M.findRoadNodeAhead(fromPed, dist)
  local p = GetEntityCoords(fromPed)
  local h = GetEntityHeading(fromPed)
  local forward = GetOffsetFromEntityInWorldCoords(fromPed, 0.0, dist, 0.0)
  local ok, node, heading = GetClosestVehicleNodeWithHeading(forward.x, forward.y, forward.z, 1, 3.0, 0)
  if not ok then ok, node, heading = GetClosestVehicleNodeWithHeading(p.x, p.y, p.z, 1, 3.0, 0) end
  return node, heading or h
end

function M.spawnVehicle(modelName, coords, heading, sirensOn)
  local mdl = M.ensureModel(modelName)
  if not mdl then return nil end
  local veh = CreateVehicle(mdl, coords.x, coords.y, coords.z, heading or 0.0, true, true)
  SetVehicleOnGroundProperly(veh)
  SetVehicleDoorsLocked(veh, 1)
  if sirensOn then SetVehicleSiren(veh, true) end
  SetEntityAsMissionEntity(veh, true, true)
  SetModelAsNoLongerNeeded(mdl)
  return veh
end

function M.spawnPed(modelName, coords, heading, intoVehicle)
  local mdl = M.ensureModel(modelName)
  if not mdl then return nil end
  local ped = CreatePed(4, mdl, coords.x, coords.y, coords.z, heading or 0.0, true, true)
  SetEntityAsMissionEntity(ped, true, true)
  SetPedCanBeDraggedOut(ped, false)
  SetBlockingOfNonTemporaryEvents(ped, true)
  if intoVehicle then
    TaskWarpPedIntoVehicle(ped, intoVehicle, -1)
  end
  SetModelAsNoLongerNeeded(mdl)
  return ped
end

function M.applyVehicleSetup(veh, cfg)
  if not veh or not cfg then return end
  if cfg.livery and cfg.livery >= 0 then SetVehicleLivery(veh, cfg.livery) end
  if cfg.extras then
    for id, enable in pairs(cfg.extras) do
      SetVehicleExtra(veh, id, enable and 0 or 1)
    end
  end
  if cfg.mods then
    for t, idx in pairs(cfg.mods) do
      if idx ~= -1 then SetVehicleModKit(veh, 0); SetVehicleMod(veh, t, idx, false) end
    end
  end
  if cfg.windowTint and cfg.windowTint >= 0 then SetVehicleWindowTint(veh, cfg.windowTint) end
  local c = cfg.colors or {}
  if c.primary  and c.primary  >= 0 then SetVehicleColours(veh, c.primary,  GetVehicleColours(veh)) end
  if c.secondary and c.secondary >= 0 then local p,_ = GetVehicleColours(veh); SetVehicleColours(veh, p, c.secondary) end
  if c.pearlescent or c.wheel then
    local pearl = c.pearlescent or select(1, GetVehicleExtraColours(veh))
    local wheel = c.wheel       or select(2, GetVehicleExtraColours(veh))
    SetVehicleExtraColours(veh, pearl, wheel)
  end
end

function M.driveAndCleanup(ped, veh, to, speed, drivingStyle, secondsBeforeDelete, attachedVeh)
  TaskVehicleDriveToCoordLongrange(ped, veh, to.x, to.y, to.z, speed or 18.0, drivingStyle or 786603, 5.0)
  CreateThread(function()
    Wait((secondsBeforeDelete or 10) * 1000)
    if attachedVeh and DoesEntityExist(attachedVeh) then DeleteEntity(attachedVeh) end
    if DoesEntityExist(veh) then DeleteEntity(veh) end
    if DoesEntityExist(ped) then DeleteEntity(ped) end
  end)
end

return M

