local function dbg(msg)
  if Config.debug then print(('[arp_coroner] %s'):format(msg)) end
end

-- Optional: ox_target mode
CreateThread(function()
  if Config.triggerMode ~= 'ox_target' then return end
  if GetResourceState('ox_target') ~= 'started' then
    print('[arp_coroner] triggerMode set to ox_target but ox_target is not running.')
    return
  end

  -- Add a player target option
  exports.ox_target:addPlayer({
    label = Config.targetLabel or 'Call Coroner',
    icon = 'fa-solid fa-briefcase-medical',
    distance = 3.0,
    canInteract = function(entity, distance, coords, name, bone)
      -- Only show on dead players within call range
      if not entity or not DoesEntityExist(entity) then return false end
      if not IsPedAPlayer(entity) then return false end
      if not IsPedDeadOrDying(entity, true) and GetEntityHealth(entity) > 101 then return false end

      local localPed = PlayerPedId()
      local myCoords = GetEntityCoords(localPed)
      local theirCoords = GetEntityCoords(entity)
      return #(myCoords - theirCoords) <= Config.maxCallDistance
    end,
    onSelect = function(data)
      local targetPlayerId = NetworkGetPlayerIndexFromPed(data.entity)
      if targetPlayerId == -1 then
        dbg('No player index from ped')
        return
      end
      local targetServerId = GetPlayerServerId(targetPlayerId)
      TriggerServerEvent('arp_coroner:request', targetServerId)
    end
  })
end)

-- Respawn the local player when told to by the server
RegisterNetEvent('arp_coroner:respawn', function()
  local ped = PlayerPedId()
  local coords = GetEntityCoords(ped)
  local heading = GetEntityHeading(ped)

  -- Fade out/in for a smooth effect
  DoScreenFadeOut(500)
  while not IsScreenFadedOut() do Wait(0) end

  -- Safety: clear death state and resurrect
  NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, true, false)
  ClearPedTasksImmediately(ped)
  ClearPedBloodDamage(ped)
  SetEntityHealth(ped, 200)
  SetPlayerInvincible(PlayerId(), false)

  -- Small grace time to avoid immediate ragdoll
  Wait(250)
  DoScreenFadeIn(700)
end)

