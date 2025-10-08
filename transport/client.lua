local function loadModel(model)
  local hash = (type(model) == 'number') and model or GetHashKey(model)
  if not HasModelLoaded(hash) then
    RequestModel(hash)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(hash) do
      Wait(10)
      if GetGameTimer() > timeout then break end
    end
  end
  return HasModelLoaded(hash) and hash or nil
end

local function setMpClothes(ped, comps, props)
  -- Only if freemode model
  local model = GetEntityModel(ped)
  if model ~= GetHashKey('mp_m_freemode_01') and model ~= GetHashKey('mp_f_freemode_01') then return end
  SetPedDefaultComponentVariation(ped)
  if comps then
    for _,c in ipairs(comps) do
      local compId, drawable, texture = c[1], c[2], c[3]
      SetPedComponentVariation(ped, compId, drawable, texture, 0)
    end
  end
  if props then
    for _,p in ipairs(props) do
      local propId, drawable, texture = p[1], p[2], p[3]
      if drawable == -1 then
        ClearPedProp(ped, propId)
      else
        SetPedPropIndex(ped, propId, drawable, texture, true)
      end
    end
  end
end

local function applyVehicleConfig(veh)
  if not DoesEntityExist(veh) then return end

  -- Livery
  if Config.Vehicle.livery and Config.Vehicle.livery >= 0 then
    SetVehicleLivery(veh, Config.Vehicle.livery)
  end

  -- Extras
  if Config.Vehicle.extras then
    for id, enable in pairs(Config.Vehicle.extras) do
      if DoesExtraExist(veh, id) then
        SetVehicleExtra(veh, id, (enable and 0 or 1))
      end
    end
  end

  -- Mods
  if Config.Vehicle.mods then
    SetVehicleModKit(veh, 0)
    for modType, modIndex in pairs(Config.Vehicle.mods) do
      if modIndex and modIndex >= 0 then
        SetVehicleMod(veh, modType, modIndex, false)
      end
    end
  end

  -- Tint
  if Config.Vehicle.windowTint and Config.Vehicle.windowTint >= 0 then
    SetVehicleWindowTint(veh, Config.Vehicle.windowTint)
  end

  -- Colors
  if Config.Vehicle.colors then
    local c = Config.Vehicle.colors
    if (c.primary or -1) >= 0 and (c.secondary or -1) >= 0 then
      SetVehicleColours(veh, c.primary, c.secondary)
    end
    if (c.pearlescent or -1) >= 0 and (c.wheel or -1) >= 0 then
      SetVehicleExtraColours(veh, c.pearlescent, c.wheel)
    end
  end

  -- Sirens
  SetVehicleSiren(veh, Config.Vehicle.sirensOn and true or false)
end

-- Basic client notify fallback
RegisterNetEvent('arp_transport:notify', function(msg)
  BeginTextCommandThefeedPost('STRING'); AddTextComponentSubstringPlayerName(msg)
  EndTextCommandThefeedPostTicker(false, false)
end)

-- Main flow
RegisterNetEvent('arp_transport:begin', function(targetId)
  local srcPed = PlayerPedId()
  local srcCoords = GetEntityCoords(srcPed)
  local target = GetPlayerFromServerId(targetId)
  if target == -1 then
    TriggerEvent('arp_transport:notify', 'Target not found.')
    return
  end
  local targetPed = GetPlayerPed(target)
  local targetCoords = GetEntityCoords(targetPed)

  -- Spawn vehicle on nearby road around target (so approach looks natural)
  local vehHash = loadModel(Config.Vehicle.model)
  local pedHash = loadModel(Config.Officer.model)
  if not vehHash or not pedHash then
    TriggerEvent('arp_transport:notify', 'Failed to load vehicle/officer model.')
    return
  end

  local spawnCoord = GetOffsetFromEntityInWorldCoords(targetPed, Config.SpawnDistance, 0.0, 0.0)
  local found, roadPos, roadHeading = GetClosestVehicleNodeWithHeading(spawnCoord.x, spawnCoord.y, spawnCoord.z, 1, 3.0, 0)
  if not found then
    roadPos = spawnCoord; roadHeading = GetEntityHeading(srcPed)
  end

  local veh = CreateVehicle(vehHash, roadPos.x, roadPos.y, roadPos.z, roadHeading, true, true)
  SetVehicleOnGroundProperly(veh)
  SetVehicleDoorsLocked(veh, 1)
  SetVehicleEngineOn(veh, true, true, false)
  SetVehicleIsConsideredByPlayer(veh, true)
  SetEntityAsMissionEntity(veh, true, true)
  applyVehicleConfig(veh)

  local driver = CreatePedInsideVehicle(veh, 4, pedHash, -1, true, true)
  SetEntityAsMissionEntity(driver, true, true)
  SetPedFleeAttributes(driver, 0, false)
  SetBlockingOfNonTemporaryEvents(driver, true)
  SetPedCanBeDraggedOut(driver, false)
  SetDriverAbility(driver, 1.0)
  SetDriverAggressiveness(driver, 0.0)
  setMpClothes(driver, Config.Officer.components, Config.Officer.props)

  -- Drive close, stop, get out, approach target
  TaskVehicleDriveToCoordLongrange(driver, veh, targetCoords.x, targetCoords.y, targetCoords.z, 16.0, 447, 10.0)
  -- Poll until close
  local arriveTimeout = GetGameTimer() + 20000
  while #(GetEntityCoords(veh) - targetCoords) > 10.0 and GetGameTimer() < arriveTimeout do
    Wait(250)
  end

  -- Park-ish
  TaskVehicleTempAction(driver, veh, 27, 2000)
  Wait(500)
  TaskLeaveVehicle(driver, veh, 256)
  while IsPedInAnyVehicle(driver, false) do Wait(50) end

  -- Walk to suspect
  ClearPedTasks(driver)
  TaskGoToEntity(driver, targetPed, -1, 1.2, 1.0, 1073741824, 0)
  local approachTimeout = GetGameTimer() + 12000
  while #(GetEntityCoords(driver) - targetCoords) > 2.0 and GetGameTimer() < approachTimeout do
    Wait(100)
  end

  -- Play quick “grab” anim on officer; ask target client to place in rear seat
  local dict, anim = 'mp_arresting', 'a_uncuff' -- short, readable action
  RequestAnimDict(dict); while not HasAnimDictLoaded(dict) do Wait(10) end
  TaskPlayAnim(driver, dict, anim, 8.0, -8.0, 1500, 0, 0, false, false, false)
  Wait(800)

  local netVeh = VehToNet(veh)
  local seatOptions = Config.RearSeatPreference
  TriggerServerEvent('arp_transport:putInVehicle', netVeh, seatOptions)

  -- Officer returns to driver seat (if he got bumped)
  TaskEnterVehicle(driver, veh, 5000, -1, 2.0, 1, 0)
  local enterTimeout = GetGameTimer() + 8000
  while not IsPedInVehicle(driver, veh, false) and GetGameTimer() < enterTimeout do Wait(100) end

  -- Start driving away
  local away = GetOffsetFromEntityInWorldCoords(veh, 0.0, -150.0, 0.0)
  TaskVehicleDriveToCoordLongrange(driver, veh, away.x, away.y, away.z, 20.0, 447, 10.0)

  local untilCleanup = GetGameTimer() + (Config.DriveAwaySeconds * 1000)
  while GetGameTimer() < untilCleanup do Wait(250) end

  -- Cleanup
  local src = GetPlayerServerId(PlayerId())
  TriggerServerEvent('arp_transport:completed', src, targetId)

  -- Despawn safely
  if DoesEntityExist(veh) then
    SetEntityAsMissionEntity(veh, true, true)
  end
  if DoesEntityExist(driver) then
    DeleteEntity(driver)
  end
  if DoesEntityExist(veh) then
    DeleteEntity(veh)
  end
end)

-- Target client handler: put *this* player in the transporter vehicle
RegisterNetEvent('arp_transport:_clientPutInVehicle', function(netVeh, seatOptions)
  local veh = NetToVeh(netVeh)
  if not DoesEntityExist(veh) then return end

  local ped = PlayerPedId()

  -- Try preferred rear seats first, else any free seat
  local placed = false
  if seatOptions and #seatOptions > 0 then
    for _, seat in ipairs(seatOptions) do
      if IsVehicleSeatFree(veh, seat) then
        TaskWarpPedIntoVehicle(ped, veh, seat)
        placed = true
        break
      end
    end
  end
  if not placed then
    -- Scan vehicle seats
    local maxSeats = GetVehicleModelNumberOfSeats(GetEntityModel(veh)) - 1
    for s = maxSeats, 0, -1 do
      if IsVehicleSeatFree(veh, s) then
        TaskWarpPedIntoVehicle(ped, veh, s)
        break
      end
    end
  end
end)

-- Optional: add ox_target option to all player peds (source is the interactor)
CreateThread(function()
  if not Config.EnableOxTarget then return end
  if GetResourceState('ox_target') ~= 'started' then return end

  local ox = exports.ox_target
  -- Global player target
  ox:addGlobalPlayer({
    {
      icon = 'fa-solid fa-van-shuttle',
      label = 'Request Transport',
      onSelect = function(data)
        -- data.entity is target ped; get server id
        local targetId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(data.entity))
        if targetId and targetId ~= GetPlayerServerId(PlayerId()) then
          TriggerServerEvent('arp_transport:targetInteract', targetId)
        end
      end,
      canInteract = function(entity, distance, coords, name, bone)
        if entity == PlayerPedId() then return false end
        return distance <= 2.5
      end
    }
  })
end)

