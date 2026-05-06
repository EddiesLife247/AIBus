Config = {}

-- General Settings
Config.Debug = false             -- Enable or disable debug mode (prints and markers)
Config.SuspendService = false -- Disable all spawning logic, and display text as Bus Service Suspended.
Config.StopWaitTime = 5000      -- How long the bus waits at a stop, in milliseconds (e.g., 5000 = 5 seconds)
Config.StopRequestWaitTime = 10000 -- How long the bus waits if a player has requested to get off (e.g., 10000 = 10 seconds)
Config.StopZoneRadius = 15.0    -- NEW: The radius around a stop to be considered "at the stop for the bus"
Config.StopInteractionDistance = 20.0 -- The max distance a player can be from a stop to see prompts.

Config.NPCSpawning = true       -- Enable or disable NPC spawning at bus stops
Config.NPCSpawnRadius = 10.0    -- The radius around the bus stop to spawn NPCs
Config.Timeout = 300
Config.MaxTimeout = 75 -- When we determin a bus as non responsive after this many timeouts (Default: 75)
Config.Despawn = 600 -- When We Despawn Busses after non responsive (allows for police chases, default: 600)
Config.NearStop = 150 -- This configures the distance away from a stop the bus has to be before it detects its near a stop.
Config.DrivingFlags = 786603 -- BEST IS: (786603)

Config.DriverModel = 's_m_y_busboy_01'
Config.DistanceSpawn = 500.0


Config.BusMaxSpeed = 15.0 -- Meters Per Second (15.0 = 33.5 mph, 54 kmph)

Config.AnimDict = "gestures@m@standing@casual" -- The dictionary for the hailbusemote
Config.AnimName = "gesture_hand_up" -- The dictionary for the hailbusemote

Config.BusPlate = "ACBR"

-- Payment Settings
Config.RideFare = 50.00             -- The cost of a single bus ride
Config.PaymentMethod = 'cash'       -- 'cash' or 'bank' or 'item'
Config.PaymentItem = 'money'        -- The item name to use for payment if PaymentMethod is 'item'

-- Blip Settings
Config.Blips = {
    EnableStopBlips = false,  -- Set to true to show bus stop blips, false to hide them.
    EnableBusBlips = false,   -- Set to true to show AI bus blips, false to hide them.
    AllowedMapBlips = {
        -- Hospitals
        61,

        -- Clothing Stores
        73,

        -- City Services (Examples - add more if you need)
        60,  -- Police Station
        66,  -- Fire Station
        491, -- City Hall

        -- Custom Businesses (Add your server's custom blip sprite IDs here)
        -- 475, -- Example
        -- 476, -- Example
    }
}

-- UPDATED: Settings specifically for the static bus stop markers
Config.StopBlip = {
    Sprite = 257,
    Display = 4,
    Scale = 0.3,
    Colour = 2,
    ShortRange = true, -- IMPORTANT: Set to false to make blips always visible, true to make them disappear when far away.
}

-- NEW: Settings specifically for the moving AI bus blips
Config.BusBlip = {
    Sprite = 227,
    Colour = 3,
    Scale = 0.5,
    Text = "Bus", -- This text will be shown followed by the route name.
}

-- Bus Routes
Config.Routes = {
    {
        Name = "Route 1: Downtown Loop",
        BusModel = 'bus', -- Model for this specific route
        MaxBusses = 2, -- NEW: The maximum number of buses to spawn on this route.
	suspendedRoute = false,
        Stops = {
            vector4(433.71, -668.34, 29.08, 88.63),
            vector4(304.63, -765.15, 29.31, 160.97),
            vector4(167.73, -1355.16, 29.3, 135.98),
            vector4(-7.82, -1564.32, 29.29, 139.46),
            vector4(-110.01, -1686.12, 29.31, 139.47),
            vector4(3.09, -1706.71, 29.29, 291.83),
	    vector4(236.51, -1576.51, 29.29, 298.26),
            vector4(390.44, -1487.48, 29.29, 297.34),
            vector4(542.74, -1387.42, 29.26, 34.07),
	    vector4(507.63, -1087.48, 29.01, 352.25),
            vector4(507.96, -844.35, 24.97, 358.64)
        }
    },
    {
        Name = "Route 2: Vinewood Loop",
        BusModel = 'bus', -- Model for this specific route
        MaxBusses = 3, -- NEW: The maximum number of buses to spawn on this route.
	suspendedRoute = false,
        Stops = {
            vector4(476.62, -670.06, 26.46, 88.6),
            vector4(238.29, -826.31, 30.07, 65.15),
            vector4(252.44, -643.3, 39.99, 336.1),
            vector4(415.58, -401.15, 46.89, 296.69),
            vector4(531.24, -205.38, 52.27, 21.09),
            vector4(664.68, -47.22, 80.47, 313.77),
	    vector4(582.39, 73.15, 94.18, 62.75),
	    vector4(399.59, 137.23, 102.21, 68.87),
	    vector4(276.19, 182.28, 104.57, 67.39),
            vector4(74.37, 259.48, 109.17, 66.53),
	    vector4(-170.05, 268.3, 93.16, 85.12),
	    vector4(-455.03, 258.34, 83.02, 80.19),
	    vector4(-550.99, 102.0, 62.28, 168.63),
            vector4(-537.12, -109.28, 39.32, 214.15),
            vector4(-431.59, -285.09, 35.99, 228.94),
	    vector4(-231.67, -540.6, 34.7, 155.71),
	    vector4(-163.91, -713.73, 34.6, 241.31),
            vector4(105.51, -809.42, 31.4, 245.76),
	    vector4(350.72, -869.99, 29.29, 266.65),
	    vector4(461.8, -831.91, 27.2, 269.65)
        }
    },
    {
        Name = "Route 3: Vespucci Loop",
        BusModel = 'bus', -- Model for this specific route
        MaxBusses = 4, -- NEW: The maximum number of buses to spawn on this route.
	suspendedRoute = false,
        Stops = {
            vector4(350.39, -722.29, 29.27, 339.93),
	    vector4(497.46, -754.37, 24.88, 176.31),
	    vector4(436.54, -947.72, 29.05, 86.41),
	    vector4(310.77, -1034.76, 29.21, 93.33),
	    vector4(60.41, -1073.16, 29.29, 155.35),
	    vector4(-61.53, -1127.81, 25.87, 89.57),
	    vector4(-184.15, -1128.54, 23.03, 91.29),
	    vector4(-234.52, -860.17, 30.47, 73.15),
	    vector4(-548.87, -1032.59, 22.73, 174.79),
	    vector4(-664.37, -1236.54, 10.61, 31.55),
	    vector4(-791.34, -1050.95, 12.35, 25.66),
	    vector4(-1040.83, -779.49, 18.76, 60.23),
	    vector4(-1191.37, -610.13, 25.8, 35.89),
	    vector4(-1250.63, -540.4, 30.21, 38.84),
	    vector4(-1346.2, -417.63, 35.76, 37.05),
	    vector4(-1220.37, -320.97, 37.62, 305.9),
	    vector4(-1023.81, -251.65, 37.74, 290.95),
	    vector4(-853.67, -308.47, 38.96, 243.56),
	    vector4(-680.68, -378.4, 34.29, 242.82),
	    vector4(-465.13, -392.0, 33.89, 253.11),
	    vector4(-216.63, -461.87, 33.72, 187.07),
	    vector4(-190.89, -703.64, 34.14, 248.02),
	    vector4(120.94, -815.45, 31.29, 246.74),
	    vector4(323.56, -799.71, 29.27, 343.56)
        }
    },

}