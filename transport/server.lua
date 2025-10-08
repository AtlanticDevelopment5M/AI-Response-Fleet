local function isPlayerOnline(id)
  id = tonumber(id)
  if not id then return false end
  for _, pid in ipairs(GetPlayers()) do
    if tonumber(pid) == id then return true end
  end
  return false
end

-- Chat command
if Config.EnableChatCommand then
  RegisterCommand(Config.CommandName, function(source, args)
    local src = source
    -- ✅ Duty check for SOURCE player (not target)
    if not Config.IsSourceOnDuty(src) then
      Config.Notify(src, "You must be on duty to request transport.")
      return
    end

    local target = tonumber(args[1] or -1)
    if not target or not isPlayerOnline(target) then
      Config.Notify(src, ("Usage: /%s [player id]"):format(Config.CommandName))
      return
    end

    if target == src then
      Config.Notify(src, "You cannot transport yourself.")
      return
    end

    TriggerClientEvent('arp_transport:begin', src, target)
  end)
end

-- ox_target trigger (from client on SOURCE interact with a target player entity)
RegisterNetEvent('arp_transport:targetInteract', function(target)
  local src = source
  if not Config.EnableOxTarget then return end
  if not Config.IsSourceOnDuty(src) then
    Config.Notify(src, "You must be on duty to request transport.")
    return
  end
  if not isPlayerOnline(target) then
    Config.Notify(src, "Target is no longer available.")
    return
  end
  TriggerClientEvent('arp_transport:begin', src, target)
end)

-- Ask target client to warp into vehicle (rear seat)
RegisterNetEvent('arp_transport:putInVehicle', function(netVeh, seatOptions)
  local target = source
  TriggerClientEvent('arp_transport:_clientPutInVehicle', target, netVeh, seatOptions)
end)

-- Cleanup callback + your placeholder export
RegisterNetEvent('arp_transport:completed', function(src, target)
  -- Call your placeholder export/callback now
  Config.OnTransportComplete(src, target)
end)

