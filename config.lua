Config = {}

---------------------------------------------------
-- 🟦 GLOBAL SETTINGS
---------------------------------------------------
Config.Debug = false

-- Shared notifications; can be bridged to forge-chat, ND_Core, etc.
Config.Notify = function(src, msg, title, color)
    if not title then title = "AI Services" end
    if not color then color = "blue" end

    -- Example bridge to forge-chat (uncomment if available)
    -- TriggerEvent('forge-chat:exportSendMessage', src, msg, title, color)

    -- Default fallback:
    if IsDuplicityVersion() then
        TriggerClientEvent('chat:addMessage', src, { args = {title, msg} })
    else
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(msg)
        EndTextCommandThefeedPostTicker(false, true)
    end
end


---------------------------------------------------
-- 🚓 TRANSPORT SERVICE
---------------------------------------------------
Config.Transport = {

    EnableChatCommand = true,    -- /transport [id]
    EnableOxTarget    = true,    -- ox_target on player entities
    CommandName       = 'transport',

    SpawnDistance     = 40.0,    -- vehicle spawn distance (on road)
    DriveAwaySeconds  = 10,      -- cleanup timer

    Officer = {
        model = 'mp_m_freemode_01',
        components = {
            {3, 0, 0}, {4, 35, 0}, {6, 25, 0},
            {8, 15, 0}, {11, 55, 0}, {9, 0, 0},
            {1, 0, 0}, {7, 0, 0},
        },
        props = {
            {0, -1, 0}, -- clear hat
        }
    },

    Vehicle = {
        model = 'police',
        sirensOn = true,
        livery = 0,
        extras = {
            [1] = true,
            [2] = false,
            [3] = true
        },
        mods = {
            [11] = 3, [12] = 2, [13] = 2,
            [15] = 3, [16] = 4, [23] = 10
        },
        windowTint = 1,
        colors = {
            primary = -1,
            secondary = -1,
            pearlescent = -1,
            wheel = -1
        }
    },

    RearSeatPreference = { 1, 2, 3 },

    IsSourceOnDuty = function(source)
        -- Replace with your ND_Core / duty system
        return true
    end,

    OnTransportComplete = function(source, target)
        -- Placeholder export/event
        -- e.g. exports['arp_jail']:OnTransportComplete(source, target)
    end
}


---------------------------------------------------
-- ⚰️ CORONER SERVICE
---------------------------------------------------
Config.Coroner = {

    TriggerMode = 'chat', -- 'chat' or 'ox_target'
    MaxCallDistance = 15.0,

    VehicleModel  = 'cvan',
    PedModel      = 's_m_m_doctor_01',
    SpawnDistance = 40.0,
    DriveSpeed    = 18.0,
    DriveOffTime  = 5000, -- ms

    LiveryIndex   = 0,
    Extras = {
        [1] = true,
        [2] = false,
    },

    UseEmergencyLights = true,

    TendDuration  = 3500,
    BagCarryDelay = 500,
    LoadDuration  = 1500,

    TargetLabel = 'Call Coroner',
}


---------------------------------------------------
-- 🚛 TOW SERVICE
---------------------------------------------------
Config.Tow = {

    EnableCommand      = true,
    EnableOxTarget     = true,
    PlayerVehicleRange = 3.0,

    SpawnDistance      = 40.0,
    SpawnTryAhead      = true,

    AttachRange        = 10.0,
    DriveAwaySeconds   = 10,

    DriverModel        = 's_m_m_trucker_01',

    TowMode            = 'flatbed',  -- 'flatbed' or 'hook'
    FlatbedModel       = 'flatbed',
    HookModel          = 'towtruck2',

    FlatbedOffset = {
        pos = vector3(0.0, -1.8, 0.85),
        rot = vector3(0.0, 0.0, 0.0)
    },

    TowSpeed           = 18.0,
    DrivingStyle       = 786603,
    MaxTargetSpeed     = 1.0
}

---------------------------------------------------
-- ✅ END OF CONFIG
---------------------------------------------------

