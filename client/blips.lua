local blips = {}  -- [netId] = blip

local function safeName(name)
  return (name and name ~= "") and name or "AI Unit"
end

local function createOrUpdateBlipForNetId(netId, opts)
  local ent = NetToEnt(netId)
  if not ent or ent == 0 or not DoesEntityExist(ent) then return end

  -- if a blip already exists for this netId, reuse it
  local blip = blips[netId]
  if not blip or not DoesBlipExist(blip) then
    blip = AddBlipForEntity(ent)
    blips[netId] = blip
  end

  -- apply style
  SetBlipSprite(blip, opts.sprite or 56)
  SetBlipColour(blip, opts.color or 3)
  SetBlipScale(blip, opts.scale or 0.9)
  SetBlipAsShortRange(blip, false)
  ShowNumberOnBlip(blip, 0)

  if opts.showRoute then
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, opts.color or 3)
  else
    SetBlipRoute(blip, false)
  end

  BeginTextCommandSetBlipName("STRING")
  AddTextComponentString(safeName(opts.label))
  EndTextCommandSetBlipName(blip)

  if (opts.flashOnCreateMs or 0) > 0 then
    local endTime = GetGameTimer() + opts.flashOnCreateMs
    CreateThread(function()
      while GetGameTimer() < endTime and DoesBlipExist(blip) do
        SetBlipFlashes(blip, true)
        Wait(250)
      end
      if DoesBlipExist(blip) then SetBlipFlashes(blip, false) end
    end)
  end
end

local function removeBlipForNetId(netId)
  local blip = blips[netId]
  if blip and DoesBlipExist(blip) then
    RemoveBlip(blip)
  end
  blips[netId] = nil
end

-- Add/Remove events (scoped to the player who called the AI)
RegisterNetEvent("arp_ai:blip:add", function(netId, opts)
  createOrUpdateBlipForNetId(netId, opts or {})
end)

RegisterNetEvent("arp_ai:blip:remove", function(netId)
  removeBlipForNetId(netId)
end)

-- Safety: if entity despawns unexpectedly, auto-clean blip (cheap watchdog)
CreateThread(function()
  while true do
    for netId, blip in pairs(blips) do
      if not DoesBlipExist(blip) or NetToEnt(netId) == 0 or not DoesEntityExist(NetToEnt(netId)) then
        removeBlipForNetId(netId)
      end
    end
    Wait(2000)
  end
end)
