local C = Config.Tow
RegisterCommand('tow', function()
  -- Find nearest vehicle in front (you can reuse your existing logic)
  local veh = GetVehiclePedIsIn(PlayerPedId(), true)
  if veh == 0 then
    -- raycast / search nearby
    local pos = GetEntityCoords(PlayerPedId())
    veh = GetClosestVehicle(pos.x, pos.y, pos.z, 5.0, 0, 70)
  end
  if veh == 0 then print('No vehicle nearby.') return end
  TriggerServerEvent('arp_ai:request:tow', NetworkGetNetworkIdFromEntity(veh))
end, false)

CreateThread(function()
  if not C.EnableOxTarget or GetResourceState('ox_target') ~= 'started' then return end
  exports.ox_target:addGlobalVehicle({
    label = 'Call Tow',
    icon = 'fa-solid fa-truck-pickup',
    distance = 3.0,
    canInteract = function(entity)
      return GetEntitySpeed(entity) <= (C.MaxTargetSpeed or 1.0)
    end,
    onSelect = function(data)
      TriggerServerEvent('arp_ai:request:tow', NetworkGetNetworkIdFromEntity(data.entity))
    end
  })
end)
