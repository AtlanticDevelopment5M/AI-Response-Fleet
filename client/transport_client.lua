local C = Config.Transport
RegisterCommand(C.CommandName or 'transport', function(_, args)
  local targetId = tonumber(args[1])
  if not targetId then return print('Usage: /transport [id]') end
  TriggerServerEvent('arp_ai:request:transport', targetId)
end, false)

CreateThread(function()
  if not C.EnableOxTarget then return end
  if GetResourceState('ox_target') ~= 'started' then return end
  exports.ox_target:addPlayer({
    label = 'Request Transport',
    icon = 'fa-regular fa-handcuffs',
    distance = 3.0,
    canInteract = function(entity)
      return IsPedAPlayer(entity)
    end,
    onSelect = function(data)
      local idx = NetworkGetPlayerIndexFromPed(data.entity)
      if idx and idx ~= -1 then
        TriggerServerEvent('arp_ai:request:transport', GetPlayerServerId(idx))
      end
    end
  })
end)
