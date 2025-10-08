local C = Config.Coroner
-- Command
RegisterCommand('coroner', function(_, args)
  local targetId = tonumber(args[1])
  if not targetId then return print('Usage: /coroner [id]') end
  TriggerServerEvent('arp_ai:request:coroner', targetId)
end, false)

-- ox_target
CreateThread(function()
  if (C.TriggerMode or C.triggerMode) ~= 'ox_target' then return end
  if GetResourceState('ox_target') ~= 'started' then return end
  exports.ox_target:addPlayer({
    label = (C.TargetLabel or C.targetLabel or 'Call Coroner'),
    icon = 'fa-solid fa-briefcase-medical',
    distance = 3.0,
    canInteract = function(entity)
      if not IsPedAPlayer(entity) then return false end
      if not IsPedDeadOrDying(entity, true) and GetEntityHealth(entity) > 101 then return false end
      local me = PlayerPedId()
      return #(GetEntityCoords(me) - GetEntityCoords(entity)) <= (C.MaxCallDistance or C.maxCallDistance or 15.0)
    end,
    onSelect = function(data)
      local idx = NetworkGetPlayerIndexFromPed(data.entity)
      if idx and idx ~= -1 then
        TriggerServerEvent('arp_ai:request:coroner', GetPlayerServerId(idx))
      end
    end
  })
end)

-- Respawn the local player at a specific hospital
RegisterNetEvent('arp_coroner:respawnAtHospital', function(hCoords, hHeading, label)
    local ped = PlayerPedId()
    local coords = hCoords or GetEntityCoords(ped)
    local heading = hHeading or GetEntityHeading(ped)

    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(0) end

    -- Safety: clear death state and resurrect at hospital
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, true, false)
    ClearPedTasksImmediately(ped)
    ClearPedBloodDamage(ped)
    SetEntityHealth(ped, 200)
    SetPlayerInvincible(PlayerId(), false)

    if label then
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(('~b~Admitted to %s'):format(label))
        EndTextCommandThefeedPostTicker(false, true)
    end

    Wait(250)
    DoScreenFadeIn(700)
end)

