RuntimeConfig = RuntimeConfig or {}

Config = Config or {}

local KVP_KEY = "midnight_redeem:runtime_config_v1"
local CONFIG_ROW_ID = 1
local DEFAULT_WELCOME = "hello, i'm shadow. tell me what code you want and i'll help draft it, validate it, and execute it when you're ready."

ContentFilter = ContentFilter or {}
BadWords = BadWords or {}

local badWordLookup = {}
local storedConfigCache = nil
local configInitialized = false

-- Factory defaults (seed / reset-to-defaults only; live config comes from the database)
Config.Debug = false

Config.Framework = 'qb' -- just used for vehicle rewards

Config.AdminCommand = "adminredeem"
Config.RedeemCommand = "redeemcode"
Config.mincustomchar = 6

Config.DailyRewardEnabled      = true
Config.RewardTimes = {  "00:00"  }
Config.DailyRewarduses         = 3
Config.DailyRewardperuserlimit = 1
Config.DailyRewardhours        = 24

Config.sqlCleanUpDays = 14 -- recommended for stats to show correctly
Config.TranscriptRetentionDays = 31 -- auto-delete AI chat transcripts after this many days

Config.DashboardRefreshInterval = 180 --recommended 

-- Logging System Configuration
-- Options: "both", "discord", "fivemanage"
-- "discord" = Only send to Discord
-- "fivemanage" = Only send to FiveManage
Config.Logsystem = "both"

-- AI Assistant Configuration
-- Set to true to enable the AI chat assistant
-- Requires MREDEEM_AI_API_KEY to be set in server.cfg
-- Supported providers: "openai" (default), "anthropic"
-- Set MREDEEM_AI_PROVIDER in server.cfg to change provider
-- Set MREDEEM_AI_MODEL in server.cfg to change model (e.g., "gpt-3.5-turbo", "gpt-4", "claude-3-haiku-20240307")
Config.AIEnabled = true

-- AI Chat Rate Limiting
-- Maximum number of AI chat messages per user per window (0 = unlimited)
Config.AIChatRateLimit = 20
-- Rate limit window in hours (24 hours = messages reset every day)
Config.AIChatRateLimitWindow = 24


Config.DailyRewards = {
    [1] = { cash = 2500},
    [2] = { sprunk = 25, mustard = 10},
    [3] = { bread = 15},
    [4] = { cash = 1000},
    [5] = { sprunk = 100},
    [6] = { testburger = 8, water = 12},
    [7] = { cash = 500},
    [8] = { sandwich = 20, water = 5},
    [9] = { cash = 500},
    [10] = { sprunk = 50, mustard = 20},
    [11] = { testburger = 3, water = 6},
    [12] = { cash = 350},
    [13] = { sprunk = 75, mustard = 15, water = 8},
    [14] = { cash = 1500},
    [15] = { testburger = 5, water = 10, mustard = 2},
    [16] = { cash = 750},
    [17] = { testburger = 30},
    [18] = { cash = 2000},
    [19] = { sprunk = 40, mustard = 12},
    [20] = { sprunk = 15, water = 8}
}

Config.BadWords = {

    profanity = {
        "fuck", "shit", "bitch", "ass", "dick", "cock", "pussy", "cunt", "whore", "slut",
        "bastard", "motherfucker", "fucker", "faggot", "nigger", "nigga", "kike", "spic",
        "chink", "gook", "wetback", "towelhead", "raghead", "sandnigger", "beaner", "spic"
    },

    hate_speech = {
        "kill", "death", "murder", "suicide", "bomb", "terrorist", "nazi", "hitler",
        "genocide", "ethnic", "racial", "discrimination", "bigot", "racist", "sexist",
        "homophobic", "transphobic", "antisemitic", "islamophobic"
    },

    gaming_toxicity = {
        "noob", "nub", "scrub", "trash", "garbage", "useless", "worthless", "stupid",
        "idiot", "moron", "retard", "autistic", "cancer", "aids", "gay", "fag",
        "uninstall", "delete", "quit", "ragequit", "salty", "mad", "cry", "tears"
    },

    sexual = {
        "porn", "pornography", "sex", "sexual", "penis", "vagina", "boobs", "tits",
        "naked", "nude", "strip", "stripper", "escort", "prostitute", "hooker"
    },

    violence = {
        "blood", "gore", "violence", "weapon", "gun", "knife", "bomb", "explosion",
        "torture", "abuse", "rape", "assault", "attack", "fight", "war", "battle"
    },

    drugs = {
        "drugs", "cocaine", "heroin", "meth", "weed", "marijuana", "alcohol", "drunk",
        "high", "stoned", "addict", "dealer", "pusher", "smoke", "inject", "snort"
    },

    scams = {
        "scam", "fraud", "cheat", "hack", "crack", "steal", "rob", "theft", "fake",
        "phishing", "malware", "virus", "trojan", "spyware", "keylogger"
    },

    variations = {
        "f*ck", "f**k", "f***", "sh*t", "b*tch", "a**", "d*ck", "p*ssy", "c*nt",
        "f4ck", "f4ck", "sh1t", "b1tch", "a55", "d1ck", "p0rn", "n00b", "nub"
    },

    server_specific = {
        "admin abuse", "mod abuse", "staff abuse", "corrupt", "bias", "favoritism",
        "unfair", "rigged", "fixed", "scripted", "hacked server", "dead server"
    },

    additional_toxic = {
        "spam", "flood", "advertise", "promote", "sell", "buy", "trade", "market",
        "advertisement", "commercial", "business", "company", "corporation"
    }
}
Config.PreFilledRewards = {

    reward_categories = {

        basic_items = {
            name = "Basic Items",
            description = "Essential survival and utility items",
            icon = "??",
            rewards = {
                { item = "bread", amount = 1, max_amount = 100, label = "Bread" },
                { item = "water", amount = 1, max_amount = 100, label = "Water" },
                { item = "phone", amount = 1, max_amount = 10, label = "Phone" },
                { item = "lockpick", amount = 1, max_amount = 50, label = "Lockpick" },
                { item = "repairkit", amount = 1, max_amount = 50, label = "Repair Kit" }
            }
        },

        premium_items = {
            name = "Premium Items",
            description = "High-value and rare items",
            icon = "??",
            rewards = {
                { item = "goldbar", amount = 1, max_amount = 20, label = "Gold Bar" },
                { item = "diamond", amount = 1, max_amount = 10, label = "Diamond" },
                { item = "emerald", amount = 1, max_amount = 15, label = "Emerald" },
                { item = "ruby", amount = 1, max_amount = 15, label = "Ruby" },
                { item = "admincard", amount = 1, max_amount = 5, label = "Admin Card" }
            }
        },

        money_options = {
            name = "Money Options",
            description = "Cash and bank transfer options",
            icon = "??",
            rewards = {
                { money = true, amount = 1000, max_amount = 100000, option = "cash", label = "Cash" },
                { money = true, amount = 1000, max_amount = 100000, option = "bank", label = "Bank Transfer" }
            }
        },

        vehicles = {
            name = "Vehicles",
            description = "Various vehicle models",
            icon = "??",
            rewards = {
                { vehicle = true, model = "adder", label = "Adder (Supercar)" },
                { vehicle = true, model = "zentorno", label = "Zentorno (Supercar)" },
                { vehicle = true, model = "t20", label = "T20 (Hypercar)" },
                { vehicle = true, model = "sultan", label = "Sultan (Sports)" },
                { vehicle = true, model = "hakuchou", label = "Hakuchou (Motorcycle)" },
                { vehicle = true, model = "sanchez", label = "Sanchez (Dirt Bike)" },
                { vehicle = true, model = "bati", label = "Bati (Sport Bike)" },
                { vehicle = true, model = "police", label = "Police Car" },
                { vehicle = true, model = "ambulance", label = "Ambulance" },
                { vehicle = true, model = "firetruk", label = "Fire Truck" }
            }
        },

        tools_equipment = {
            name = "Tools & Equipment",
            description = "Professional tools and equipment",
            icon = "???",
            rewards = {
                { item = "wrench", amount = 1, max_amount = 20, label = "Wrench" },
                { item = "screwdriver", amount = 1, max_amount = 20, label = "Screwdriver" },
                { item = "hammer", amount = 1, max_amount = 20, label = "Hammer" },
                { item = "drill", amount = 1, max_amount = 10, label = "Drill" },
                { item = "welder", amount = 1, max_amount = 10, label = "Welder" }
            }
        },

        medical_supplies = {
            name = "Medical Supplies",
            description = "Health and medical items",
            icon = "??",
            rewards = {
                { item = "bandage", amount = 1, max_amount = 50, label = "Bandage" },
                { item = "medkit", amount = 1, max_amount = 20, label = "Med Kit" },
                { item = "painkillers", amount = 1, max_amount = 30, label = "Painkillers" },
                { item = "antibiotics", amount = 1, max_amount = 25, label = "Antibiotics" }
            }
        },

        food_beverages = {
            name = "Food & Beverages",
            description = "Various food and drink items",
            icon = "???",
            rewards = {
                { item = "sandwich", amount = 1, max_amount = 50, label = "Sandwich" },
                { item = "burger", amount = 1, max_amount = 50, label = "Burger" },
                { item = "pizza", amount = 1, max_amount = 50, label = "Pizza" },
                { item = "coffee", amount = 1, max_amount = 50, label = "Coffee" },
                { item = "soda", amount = 1, max_amount = 50, label = "Soda" },
                { item = "beer", amount = 1, max_amount = 50, label = "Beer" },
                { item = "wine", amount = 1, max_amount = 50, label = "Wine" }
            }
        },

        clothing_fashion = {
            name = "Clothing & Fashion",
            description = "Apparel and fashion items",
            icon = "??",
            rewards = {
                { item = "tshirt", amount = 1, max_amount = 20, label = "T-Shirt" },
                { item = "jeans", amount = 1, max_amount = 20, label = "Jeans" },
                { item = "shoes", amount = 1, max_amount = 20, label = "Shoes" },
                { item = "hat", amount = 1, max_amount = 20, label = "Hat" },
                { item = "jacket", amount = 1, max_amount = 20, label = "Jacket" }
            }
        },

        electronics = {
            name = "Electronics",
            description = "Electronic devices and gadgets",
            icon = "??",
            rewards = {
                { item = "laptop", amount = 1, max_amount = 10, label = "Laptop" },
                { item = "tablet", amount = 1, max_amount = 10, label = "Tablet" },
                { item = "headphones", amount = 1, max_amount = 20, label = "Headphones" },
                { item = "speaker", amount = 1, max_amount = 15, label = "Speaker" },
                { item = "camera", amount = 1, max_amount = 10, label = "Camera" }
            }
        }
    },

    quick_templates = {

        starter_basic = {
            name = "Basic Starter",
            description = "Essential items for new players",
            icon = "??",
            category = "starter",
            rewards = {
                { category = "basic_items", item = "bread", amount = 5 },
                { category = "basic_items", item = "water", amount = 5 },
                { category = "money_options", money = true, amount = 1000, option = "cash" }
            }
        },
        
        starter_enhanced = {
            name = "Enhanced Starter",
            description = "Enhanced starter package with tools",
            icon = "??",
            category = "starter",
            rewards = {
                { category = "basic_items", item = "bread", amount = 10 },
                { category = "basic_items", item = "water", amount = 10 },
                { category = "basic_items", item = "phone", amount = 1 },
                { category = "basic_items", item = "lockpick", amount = 2 },
                { category = "money_options", money = true, amount = 2000, option = "cash" }
            }
        },

        vip_basic = {
            name = "Basic VIP",
            description = "Entry-level VIP package",
            icon = "??",
            category = "vip",
            rewards = {
                { category = "basic_items", item = "phone", amount = 1 },
                { category = "basic_items", item = "lockpick", amount = 3 },
                { category = "money_options", money = true, amount = 5000, option = "bank" }
            }
        },
        
        vip_premium = {
            name = "Premium VIP",
            description = "Premium VIP experience",
            icon = "??",
            category = "vip",
            rewards = {
                { category = "basic_items", item = "phone", amount = 1 },
                { category = "premium_items", item = "goldbar", amount = 2 },
                { category = "money_options", money = true, amount = 15000, option = "bank" },
                { category = "vehicles", vehicle = true, model = "zentorno" }
            }
        },

        event_participant = {
            name = "Event Participant",
            description = "Basic event participation reward",
            icon = "??",
            category = "event",
            rewards = {
                { category = "premium_items", item = "goldbar", amount = 1 },
                { category = "money_options", money = true, amount = 5000, option = "cash" }
            }
        },
        
        event_winner = {
            name = "Event Winner",
            description = "Grand prize for event winners",
            icon = "??",
            category = "event",
            rewards = {
                { category = "premium_items", item = "goldbar", amount = 5 },
                { category = "money_options", money = true, amount = 50000, option = "bank" },
                { category = "vehicles", vehicle = true, model = "t20" }
            }
        },

        refund_small = {
            name = "Small Refund",
            description = "Minor compensation package",
            icon = "??",
            category = "refund",
            rewards = {
                { category = "money_options", money = true, amount = 1000, option = "cash" },
                { category = "basic_items", item = "repairkit", amount = 1 }
            }
        },
        
        refund_medium = {
            name = "Medium Refund",
            description = "Moderate compensation package",
            icon = "??",
            category = "refund",
            rewards = {
                { category = "money_options", money = true, amount = 5000, option = "cash" },
                { category = "basic_items", item = "repairkit", amount = 3 },
                { category = "basic_items", item = "lockpick", amount = 2 }
            }
        },
        
        refund_large = {
            name = "Large Refund",
            description = "Major compensation package",
            icon = "??",
            category = "refund",
            rewards = {
                { category = "money_options", money = true, amount = 10000, option = "bank" },
                { category = "basic_items", item = "repairkit", amount = 5 },
                { category = "premium_items", item = "goldbar", amount = 1 }
            }
        },

        staff_basic = {
            name = "Staff Basic",
            description = "Basic tools for staff members",
            icon = "???",
            category = "staff",
            rewards = {
                { category = "premium_items", item = "admincard", amount = 1 },
                { category = "basic_items", item = "lockpick", amount = 5 },
                { category = "money_options", money = true, amount = 1000, option = "cash" }
            }
        },
        
        staff_advanced = {
            name = "Staff Advanced",
            description = "Advanced tools for experienced staff",
            icon = "???",
            category = "staff",
            rewards = {
                { category = "premium_items", item = "admincard", amount = 1 },
                { category = "basic_items", item = "lockpick", amount = 10 },
                { category = "basic_items", item = "repairkit", amount = 5 },
                { category = "money_options", money = true, amount = 2500, option = "cash" }
            }
        },

        vehicle_basic = {
            name = "Vehicle Package",
            description = "Basic vehicle with tools",
            icon = "??",
            category = "vehicle",
            rewards = {
                { category = "vehicles", vehicle = true, model = "sultan" },
                { category = "basic_items", item = "repairkit", amount = 3 },
                { category = "basic_items", item = "lockpick", amount = 2 }
            }
        },
        
        vehicle_luxury = {
            name = "Luxury Vehicle",
            description = "Premium vehicle package",
            icon = "??",
            category = "vehicle",
            rewards = {
                { category = "vehicles", vehicle = true, model = "t20" },
                { category = "basic_items", item = "repairkit", amount = 5 },
                { category = "basic_items", item = "lockpick", amount = 3 },
                { category = "money_options", money = true, amount = 5000, option = "bank" }
            }
        },

        summer_pack = {
            name = "Summer Pack",
            description = "Summer season special items",
            icon = "??",
            category = "seasonal",
            rewards = {
                { category = "food_beverages", item = "water", amount = 25 },
                { category = "food_beverages", item = "soda", amount = 15 },
                { category = "money_options", money = true, amount = 8000, option = "cash" }
            }
        },
        
        winter_pack = {
            name = "Winter Pack",
            description = "Winter season special items",
            icon = "??",
            category = "seasonal",
            rewards = {
                { category = "food_beverages", item = "bread", amount = 25 },
                { category = "food_beverages", item = "coffee", amount = 20 },
                { category = "basic_items", item = "repairkit", amount = 8 },
                { category = "money_options", money = true, amount = 8000, option = "cash" }
            }
        },

        police_pack = {
            name = "Police Pack",
            description = "Law enforcement package",
            icon = "??",
            category = "role",
            rewards = {
                { category = "basic_items", item = "phone", amount = 1 },
                { category = "basic_items", item = "repairkit", amount = 5 },
                { category = "money_options", money = true, amount = 5000, option = "bank" }
            }
        },
        
        medic_pack = {
            name = "Medic Pack",
            description = "Medical professional package",
            icon = "??",
            category = "role",
            rewards = {
                { category = "basic_items", item = "phone", amount = 1 },
                { category = "medical_supplies", item = "medkit", amount = 3 },
                { category = "medical_supplies", item = "bandage", amount = 10 },
                { category = "money_options", money = true, amount = 5000, option = "bank" }
            }
        },
        
        mechanic_pack = {
            name = "Mechanic Pack",
            description = "Vehicle mechanic package",
            icon = "??",
            category = "role",
            rewards = {
                { category = "basic_items", item = "repairkit", amount = 15 },
                { category = "basic_items", item = "lockpick", amount = 10 },
                { category = "tools_equipment", item = "wrench", amount = 5 },
                { category = "money_options", money = true, amount = 5000, option = "cash" }
            }
        }
    }
}
Config.AICodeTemplates = {

    styles = {
        "cool",
        "professional", 
        "fun",
        "gaming",
        "corporate",
        "casual",
        "modern",
        "classic",
        "trendy",
        "elegant",
        "bold",
        "minimalist",
        "gang",
        "jobs",
        "civillian"
    },
    
    style_prefixes = {
        cool = { "SHADOW", "NIGHT", "UNDER", "STREET", "BLACK", "DARK", "GHOST", "PHANTOM", "SECRET", "ILLEGAL", "HIDDEN", "STEALTH", "UNDERWORLD", "CRIME", "VOID", "SILENT" },
        professional = { "OFFICE", "CORP", "BIZ", "EXEC", "ADMIN", "STAFF", "AGENCY", "DEPARTMENT", "FORMAL", "OFFICIAL", "PROF", "TEAM", "BUSINESS", "SUITE", "MANAGEMENT", "BOARD" },
        fun = { "PARTY", "EVENT", "SOCIAL", "FESTIVAL", "CELEBRATE", "JOY", "HAPPY", "FUN", "MEETUP", "BBQ", "BIRTHDAY", "FESTIVE", "WEEKEND", "GATHERING", "CELEBRATION", "FUNFEST" },
        gaming = { "ARENA", "TOURNEY", "COMP", "CHAMP", "LEAGUE", "TOURNAMENT", "MATCH", "RACE", "FIGHT", "BATTLE", "VICTORY", "ESPORT", "ROUND", "DUEL", "CUP", "GRAND" },
        corporate = { "CORP", "BUSINESS", "COMPANY", "ENTERPRISE", "ORGANIZATION", "GROUP", "SYNDICATE", "HOLDINGS", "DIVISION", "BRANCH", "ASSOCIATION", "FOUNDATION", "CONGLOMERATE", "CORPORATION", "INDUSTRY", "VENTURE" },
        casual = { "CHILL", "RELAX", "HANG", "LOUNGE", "CASUAL", "EASY", "MEETUP", "FRIENDS", "COMFY", "SESSIONS", "RELAXED", "COMFORT", "EASYGO", "LAID", "SOCIAL", "CHAT" },
        modern = { "2025", "NOW", "TODAY", "NEW", "FRESH", "LATEST", "UPDATE", "MODERN", "CURRENT", "NEWEST", "RECENT", "LIVE", "PRESENT", "THIS", "NEXT", "TODAYS" },
        classic = { "ORIGINAL", "VINTAGE", "RETRO", "CLASSIC", "TRADITIONAL", "LEGEND", "ICONIC", "ESTABLISHED", "FOUNDING", "HERITAGE", "TIMELESS", "OLD", "ANCIENT", "FIRST", "ORIGIN", "ROOTS" },
        trendy = { "HOT", "POP", "VIBE", "HYPE", "TREND", "FIRE", "BUZZ", "WAVE", "LIT", "DOPE", "FRESH", "SLAPS", "FLOW", "STREAM", "CHILL", "COOL" },
        elegant = { "ELITE", "PREMIUM", "LUXURY", "EXCLUSIVE", "VIP", "PRESTIGE", "SUPREME", "ROYAL", "GRAND", "DIAMOND", "PLATINUM", "NOBLE", "MASTER", "ULTIMATE", "LEGENDARY", "EPIC" },
        bold = { "POWER", "ALPHA", "PRIME", "ULTRA", "MAX", "EXTREME", "FIERCE", "MIGHTY", "STRONG", "BEAST", "TITAN", "FORCE", "DOMINATE", "INTENSE", "EPIC", "SUPREME" },
        minimalist = { "SIMPLE", "CLEAN", "BASIC", "PURE", "MIN", "CORE", "BASE", "PLAIN", "MINIMAL", "NEAT", "TIDY", "RAW", "STRIP", "ESSENCE", "CLEAR", "BARE" },
        gang = { "GANG", "CREW", "MOB", "SET", "SQUAD", "CLAN", "FAMILY", "TRIBE", "TERRITORY", "BLOCK", "HOOD", "AREA", "ZONE", "TURF", "UNIT", "CELL" },
        jobs = { "BONUS", "PAYDAY", "REWARD", "SALARY", "WAGES", "EARNINGS", "PAYCHECK", "PERFORMANCE", "ACHIEVEMENT", "MILESTONE", "SUCCESS", "EFFORT", "DEDICATION", "COMMITMENT", "EXCELLENCE", "RECOGNITION" },
        civilian = { "CIVILIAN", "CITIZEN", "PUBLIC", "COMMUNITY", "RESIDENT", "PERSON", "PEOPLE", "LOCAL", "TOWN", "CITY", "NEIGHBORHOOD", "STREET", "HOUSE", "HOME", "GENERAL", "FOLK" }
    },

    prefixes = {
        "VIP",
        "EVENT", 
        "REWARD",
        "GIFT",
        "SPECIAL",
        "BONUS",
        "WELCOME",
        "THANKS",
        "HAPPY",
        "LUCKY",
        "GOLDEN",
        "SILVER",
        "PLATINUM",
        "DIAMOND",
        "LEGENDARY",
        "EPIC",
        "RARE",
        "UNIQUE",
        "EXCLUSIVE",
        "PREMIUM",
        "ELITE",
        "LUXURY",
        "SUPREME",
        "POWER",
        "ALPHA",
        "PRIME",
        "VICTORY",
        "CHAMP",
        "SUCCESS",
        "ACHIEVEMENT",
        "MILESTONE",
        "PARTY",
        "SOCIAL",
        "CELEBRATE",
        "CLASSIC",
        "ORIGINAL",
        "NEW",
        "FRESH",
        "HOT",
        "POP",
        "VIBE",
        "HYPE",
        "FIRE"
    },

    suffixes = {
        "2025",
        "GIFT",
        "REWARD",
        "SPECIAL",
        "BONUS",
        "PACK",
        "DEAL",
        "OFFER",
        "CHANCE",
        "OPPORTUNITY",
        "MOMENT",
        "TIME",
        "DAY",
        "NIGHT",
        "WEEK",
        "MONTH",
        "YEAR",
        "FOREVER",
        "NOW",
        "HERE"
    },

    cool = {
        "{PREFIX}-{RANDOM:6}",
        "{PREFIX}{RANDOM:4}",
        "{PREFIX}-{RANDOM:8}",
        "{PREFIX}{RANDOM:6}",
        "{PREFIX}-{RANDOM:4}-{RANDOM:4}"
    },
    
    professional = {
        "{PREFIX}-{RANDOM:6}",
        "{PREFIX}{RANDOM:4}",
        "{PREFIX}-{RANDOM:8}",
        "{PREFIX}{RANDOM:6}",
        "{PREFIX}-{RANDOM:4}-{RANDOM:4}"
    },
    
    fun = {
        "{PREFIX}-{RANDOM:6}",
        "{PREFIX}{RANDOM:4}",
        "{PREFIX}-{RANDOM:8}",
        "{PREFIX}{RANDOM:6}",
        "{PREFIX}-{RANDOM:4}-{RANDOM:4}"
    },
    
    gaming = {
        "{PREFIX}-{RANDOM:6}",
        "{PREFIX}{RANDOM:4}",
        "{PREFIX}-{RANDOM:8}",
        "{PREFIX}{RANDOM:6}",
        "{PREFIX}-{RANDOM:4}-{RANDOM:4}"
    },
    
    corporate = {
        "{PREFIX}-{RANDOM:6}",
        "{PREFIX}{RANDOM:4}",
        "{PREFIX}-{RANDOM:8}",
        "{PREFIX}{RANDOM:6}",
        "{PREFIX}-{RANDOM:4}-{RANDOM:4}"
    },
    
    casual = {
        "{PREFIX}-{RANDOM:6}",
        "{PREFIX}{RANDOM:4}",
        "{PREFIX}-{RANDOM:8}",
        "{PREFIX}{RANDOM:6}",
        "{PREFIX}-{RANDOM:4}-{RANDOM:4}"
    },
    
    modern = {
        "{PREFIX}-{RANDOM:6}",
        "{PREFIX}{RANDOM:4}",
        "{PREFIX}-{RANDOM:8}",
        "{PREFIX}{RANDOM:6}",
        "{PREFIX}-{RANDOM:4}-{RANDOM:4}"
    },
    
    classic = {
        "{PREFIX}-{RANDOM:6}",
        "{PREFIX}{RANDOM:4}",
        "{PREFIX}-{RANDOM:8}",
        "{PREFIX}{RANDOM:6}",
        "{PREFIX}-{RANDOM:4}-{RANDOM:4}"
    },
    
    trendy = {
        "{PREFIX}-{RANDOM:6}",
        "{PREFIX}{RANDOM:4}",
        "{PREFIX}-{RANDOM:8}",
        "{PREFIX}{RANDOM:6}",
        "{PREFIX}-{RANDOM:4}-{RANDOM:4}"
    },
    
    elegant = {
        "{PREFIX}-{RANDOM:6}",
        "{PREFIX}{RANDOM:4}",
        "{PREFIX}-{RANDOM:8}",
        "{PREFIX}{RANDOM:6}",
        "{PREFIX}-{RANDOM:4}-{RANDOM:4}"
    },
    
    bold = {
        "{PREFIX}-{RANDOM:6}",
        "{PREFIX}{RANDOM:4}",
        "{PREFIX}-{RANDOM:8}",
        "{PREFIX}{RANDOM:6}",
        "{PREFIX}-{RANDOM:4}-{RANDOM:4}"
    },
    
    minimalist = {
        "{PREFIX}-{RANDOM:6}",
        "{PREFIX}{RANDOM:4}",
        "{PREFIX}-{RANDOM:8}",
        "{PREFIX}{RANDOM:6}",
        "{PREFIX}-{RANDOM:4}-{RANDOM:4}"
    },
    
    gang = {
        "{PREFIX}-{RANDOM:6}",
        "{PREFIX}{RANDOM:4}",
        "{PREFIX}-{RANDOM:8}",
        "{PREFIX}{RANDOM:6}",
        "{PREFIX}-{RANDOM:4}-{RANDOM:4}"
    },
    
    jobs = {
        "{PREFIX}-{RANDOM:6}",
        "{PREFIX}{RANDOM:4}",
        "{PREFIX}-{RANDOM:8}",
        "{PREFIX}{RANDOM:6}",
        "{PREFIX}-{RANDOM:4}-{RANDOM:4}"
    },
    
    civilian = {
        "{PREFIX}-{RANDOM:6}",
        "{PREFIX}{RANDOM:4}",
        "{PREFIX}-{RANDOM:8}",
        "{PREFIX}{RANDOM:6}",
        "{PREFIX}-{RANDOM:4}-{RANDOM:4}"
    }
}

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = deepCopy(v)
    end
    return out
end

local FactoryConfig = deepCopy(Config)

local function isOwner(source)
    return AdminHasPermission(source, "FULL_ACCESS")
end

local function mergeTables(base, overrides)
    if type(base) ~= "table" then
        return deepCopy(overrides)
    end
    if type(overrides) ~= "table" then
        return deepCopy(base)
    end
    local out = deepCopy(base)
    for k, v in pairs(overrides) do
        if type(v) == "table" and type(out[k]) == "table" then
            out[k] = mergeTables(out[k], v)
        else
            out[k] = deepCopy(v)
        end
    end
    return out
end

local function getDefaultSnapshot()
    return {
        general = {
            Debug = FactoryConfig.Debug == true,
            Framework = tostring(FactoryConfig.Framework or "qb"),
            AdminCommand = tostring(FactoryConfig.AdminCommand or "adminredeem"),
            RedeemCommand = tostring(FactoryConfig.RedeemCommand or "redeemcode"),
            mincustomchar = tonumber(FactoryConfig.mincustomchar) or 6,
            sqlCleanUpDays = tonumber(FactoryConfig.sqlCleanUpDays) or 14,
            TranscriptRetentionDays = tonumber(FactoryConfig.TranscriptRetentionDays) or 31,
            DashboardRefreshInterval = tonumber(FactoryConfig.DashboardRefreshInterval) or 180,
            Logsystem = tostring(FactoryConfig.Logsystem or "both"),
        },
        daily = {
            DailyRewardEnabled = FactoryConfig.DailyRewardEnabled ~= false,
            RewardTimes = deepCopy(FactoryConfig.RewardTimes or { "00:00" }),
            DailyRewarduses = tonumber(FactoryConfig.DailyRewarduses) or 3,
            DailyRewardperuserlimit = tonumber(FactoryConfig.DailyRewardperuserlimit) or 1,
            DailyRewardhours = tonumber(FactoryConfig.DailyRewardhours) or 24,
            DailyRewards = deepCopy(FactoryConfig.DailyRewards or {}),
        },
        prefilled = {
            PreFilledRewards = deepCopy(FactoryConfig.PreFilledRewards or {}),
            AICodeTemplates = deepCopy(FactoryConfig.AICodeTemplates or {}),
        },
        contentFilter = {
            BadWords = deepCopy(FactoryConfig.BadWords or {}),
        },
        aiChat = {
            aiEnabled = FactoryConfig.AIEnabled ~= false,
            rateLimit = tonumber(FactoryConfig.AIChatRateLimit) or 20,
            rateLimitWindow = tonumber(FactoryConfig.AIChatRateLimitWindow) or 24,
            transcriptRetentionDays = tonumber(FactoryConfig.TranscriptRetentionDays) or 31,
            welcomeMessage = DEFAULT_WELCOME,
        },
    }
end

local function ensureConfigTable()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS midnight_runtime_config (
            id TINYINT UNSIGNED NOT NULL DEFAULT 1,
            config_json LONGTEXT NOT NULL,
            created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
end

local function isCompleteConfig(data)
    return type(data) == "table"
        and type(data.general) == "table"
        and type(data.daily) == "table"
        and type(data.prefilled) == "table"
        and type(data.contentFilter) == "table"
        and type(data.aiChat) == "table"
end

local function repairStoredConfig(data)
    local defaults = getDefaultSnapshot()
    if type(data) ~= "table" then
        return defaults
    end

    local repaired = deepCopy(defaults)
    for section, payload in pairs(data) do
        if type(payload) == "table" and repaired[section] then
            repaired[section] = mergeTables(repaired[section], payload)
        elseif type(payload) == "table" then
            repaired[section] = deepCopy(payload)
        end
    end
    return repaired
end

local function persistConfigToDb(config)
    local ok, err = pcall(function()
        ensureConfigTable()
        MySQL.insert.await([[
            INSERT INTO midnight_runtime_config (id, config_json)
            VALUES (?, ?)
            ON DUPLICATE KEY UPDATE
                config_json = VALUES(config_json),
                updated_at = CURRENT_TIMESTAMP
        ]], { CONFIG_ROW_ID, json.encode(config) })
    end)
    if not ok then
        print(("[midnight_redeem] Failed to persist runtime config: %s"):format(tostring(err)))
    end
    return ok
end

local function loadLegacyKvpConfig()
    local raw = GetResourceKvpString(KVP_KEY)
    if not raw or raw == "" then
        return nil
    end

    local ok, overrides = pcall(json.decode, raw)
    if not ok or type(overrides) ~= "table" then
        return nil
    end

    local config = getDefaultSnapshot()
    for section, payload in pairs(overrides) do
        if type(payload) == "table" then
            if config[section] then
                config[section] = mergeTables(config[section], payload)
            else
                config[section] = deepCopy(payload)
            end
        end
    end

    DeleteResourceKvp(KVP_KEY)
    return config
end

local function loadOrSeedConfig(forceReload)
    if storedConfigCache and not forceReload then
        return storedConfigCache
    end

    local ok, loaded = pcall(function()
        ensureConfigTable()

        local row = MySQL.single.await(
            "SELECT config_json FROM midnight_runtime_config WHERE id = ? LIMIT 1",
            { CONFIG_ROW_ID }
        )

        if row and row.config_json and row.config_json ~= "" then
            local decodeOk, data = pcall(json.decode, row.config_json)
            if decodeOk and isCompleteConfig(data) then
                return data
            end

            if decodeOk and type(data) == "table" then
                local repaired = repairStoredConfig(data)
                persistConfigToDb(repaired)
                return repaired
            end
        end

        local config = loadLegacyKvpConfig() or getDefaultSnapshot()
        if persistConfigToDb(config) then
            print("[midnight_redeem] Runtime config seeded to database.")
        end
        return config
    end)

    if ok and type(loaded) == "table" then
        storedConfigCache = loaded
        return storedConfigCache
    end

    print(("[midnight_redeem] Runtime config DB load failed, using in-memory defaults: %s"):format(tostring(loaded)))
    storedConfigCache = getDefaultSnapshot()
    persistConfigToDb(storedConfigCache)
    return storedConfigCache
end

local function persistConfig(config)
    storedConfigCache = config
    persistConfigToDb(config)
end

local function rebuildBadWordLookup()
    badWordLookup = {}
    BadWords = Config.BadWords or {}
    for _, words in pairs(BadWords) do
        if type(words) == "table" then
            for _, word in ipairs(words) do
                badWordLookup[string.lower(tostring(word))] = true
            end
        end
    end
end

function RuntimeConfig.rebuildContentFilter()
    rebuildBadWordLookup()
end

function ContentFilter.checkString(input)
    if not input or type(input) ~= "string" then
        return false, "Invalid input"
    end

    local foundWords = {}
    for word in string.gmatch(string.lower(input), "%w+") do
        if badWordLookup[word] then
            foundWords[#foundWords + 1] = word
        end
    end

    if #foundWords > 0 then
        return true, foundWords
    end

    return false, nil
end

function ContentFilter.checkCodeName(codeName)
    if not codeName or type(codeName) ~= "string" then
        return false, "Invalid code name"
    end

    local issues = {}
    local hasBadWords, badWords = ContentFilter.checkString(codeName)
    if hasBadWords then
        issues[#issues + 1] = "Contains inappropriate language: " .. table.concat(badWords, ", ")
    end

    if string.find(codeName:lower(), "hack") or string.find(codeName:lower(), "cheat") then
        issues[#issues + 1] = "Suspicious content detected"
    end

    local numberCount = 0
    for _ in string.gmatch(codeName, "%d") do
        numberCount = numberCount + 1
    end

    if numberCount > string.len(codeName) * 0.7 then
        issues[#issues + 1] = "Code contains too many numbers"
    end

    if #issues > 0 then
        return false, issues
    end

    return true, nil
end

function ContentFilter.sanitize(input)
    if not input or type(input) ~= "string" then
        return input
    end

    local sanitized = input
    for _, words in pairs(BadWords) do
        if type(words) == "table" then
            for _, word in ipairs(words) do
                local pattern = string.gsub(word, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
                sanitized = string.gsub(sanitized, pattern, string.rep("*", #word))
            end
        end
    end

    return sanitized
end

function ContentFilter.getStats()
    local totalWords = 0
    local categories = 0
    for _, words in pairs(BadWords) do
        if type(words) == "table" then
            totalWords = totalWords + #words
            categories = categories + 1
        end
    end
    return { totalWords = totalWords, categories = categories }
end

function ContentFilter.logFilteredAttempt(source, content, reason)
    local playerName = source and source > 0 and (GetPlayerName(source) or "Unknown") or "System"
    print(("[CONTENT_FILTER] %s attempted blocked content '%s' - %s"):format(playerName, content or "N/A", reason or "blocked"))
end

function RuntimeConfig.applyOverrides(stored)
    stored = stored or loadOrSeedConfig(false)

    local general = stored.general or {}
    Config.Debug = general.Debug == true
    Config.Framework = general.Framework or "qb"
    Config.AdminCommand = general.AdminCommand or "adminredeem"
    Config.RedeemCommand = general.RedeemCommand or "redeemcode"
    Config.mincustomchar = tonumber(general.mincustomchar) or 6
    Config.sqlCleanUpDays = tonumber(general.sqlCleanUpDays) or 14
    Config.DashboardRefreshInterval = tonumber(general.DashboardRefreshInterval) or 180
    Config.Logsystem = general.Logsystem or "both"

    local daily = stored.daily or {}
    Config.DailyRewardEnabled = daily.DailyRewardEnabled ~= false
    Config.RewardTimes = type(daily.RewardTimes) == "table" and daily.RewardTimes or { "00:00" }
    Config.DailyRewarduses = tonumber(daily.DailyRewarduses) or 3
    Config.DailyRewardperuserlimit = tonumber(daily.DailyRewardperuserlimit) or 1
    Config.DailyRewardhours = tonumber(daily.DailyRewardhours) or 24
    Config.DailyRewards = type(daily.DailyRewards) == "table" and daily.DailyRewards or {}

    local prefilled = stored.prefilled or {}
    if type(prefilled.PreFilledRewards) == "table" then
        Config.PreFilledRewards = prefilled.PreFilledRewards
    end
    if type(prefilled.AICodeTemplates) == "table" then
        Config.AICodeTemplates = prefilled.AICodeTemplates
    end

    local contentFilter = stored.contentFilter or {}
    Config.BadWords = type(contentFilter.BadWords) == "table" and contentFilter.BadWords or {}

    local aiChat = stored.aiChat or {}
    Config.AIEnabled = aiChat.aiEnabled ~= false
    Config.AIChatRateLimit = math.max(0, tonumber(aiChat.rateLimit) or 0)
    Config.AIChatRateLimitWindow = math.max(1, tonumber(aiChat.rateLimitWindow) or 24)
    Config.TranscriptRetentionDays = math.max(0, tonumber(aiChat.transcriptRetentionDays or general.TranscriptRetentionDays) or 31)
    Config.AIWelcomeMessage = tostring(aiChat.welcomeMessage or DEFAULT_WELCOME):sub(1, 500)

    RuntimeConfig.rebuildContentFilter()
end

function RuntimeConfig.getClientSyncPayload()
    return {
        mincustomchar = tonumber(Config.mincustomchar) or 6,
        aiEnabled = Config.AIEnabled ~= false,
    }
end

function RuntimeConfig.syncToClient(target)
    local payload = RuntimeConfig.getClientSyncPayload()
    if type(target) == "number" and target > 0 then
        TriggerClientEvent("midnight-redeem:syncClientConfig", target, payload)
    else
        TriggerClientEvent("midnight-redeem:syncClientConfig", -1, payload)
    end
end

function RuntimeConfig.getSection(section)
    local stored = loadOrSeedConfig(false)
    return deepCopy(stored[section] or {})
end

function RuntimeConfig.getAllSections()
    return {
        general = RuntimeConfig.getSection("general"),
        daily = RuntimeConfig.getSection("daily"),
        prefilled = RuntimeConfig.getSection("prefilled"),
        contentFilter = RuntimeConfig.getSection("contentFilter"),
        aiChat = RuntimeConfig.getSection("aiChat"),
    }
end

function RuntimeConfig.saveSection(source, section, payload)
    if not isOwner(source) then
        return false, "Owner access required."
    end
    if type(section) ~= "string" or type(payload) ~= "table" then
        return false, "Invalid section payload."
    end

    local stored = loadOrSeedConfig(false)
    stored[section] = payload
    persistConfig(stored)
    RuntimeConfig.applyOverrides(stored)
    RuntimeConfig.syncToClient(-1)

    if SendToDiscord then
        SendToDiscord(
            "Runtime Config Updated",
            ("**Section:** `%s`\n**Updated by:** `%s`"):format(section, GetPlayerName(source) or "Unknown"),
            3447003,
            nil,
            "admin"
        )
    end

    return true, RuntimeConfig.getSection(section)
end

function RuntimeConfig.resetSection(source, section)
    if not isOwner(source) then
        return false, "Owner access required."
    end
    local stored = loadOrSeedConfig(false)
    local defaults = getDefaultSnapshot()
    stored[section] = deepCopy(defaults[section] or {})
    persistConfig(stored)
    RuntimeConfig.applyOverrides(stored)
    RuntimeConfig.syncToClient(-1)
    return true, RuntimeConfig.getSection(section)
end

exports("GetPreFilledConfig", function()
    return Config
end)

exports("GetRuntimeConfigSection", RuntimeConfig.getSection)
exports("GetAIWelcomeMessage", function()
    return Config.AIWelcomeMessage or DEFAULT_WELCOME
end)

lib.callback.register("midnight-redeem:getRuntimeConfig", function(source, section)
    RuntimeConfig.init()

    if not AdminHasPermission(source, "FULL_ACCESS") then
        return { success = false, error = "Owner access required." }
    end

    local ok, payload = pcall(function()
        if section and section ~= "" then
            return { success = true, section = section, data = RuntimeConfig.getSection(section), canEdit = true }
        end
        return { success = true, data = RuntimeConfig.getAllSections(), canEdit = true }
    end)

    if not ok then
        print(("[midnight_redeem] getRuntimeConfig failed: %s"):format(tostring(payload)))
        return { success = false, error = "Failed to load runtime config." }
    end

    return payload
end)

lib.callback.register("midnight-redeem:saveRuntimeConfig", function(source, section, payload)
    if not AdminHasPermission(source, "FULL_ACCESS") then
        return { success = false, error = "Owner access required." }
    end
    local ok, result = RuntimeConfig.saveSection(source, section, payload)
    if not ok then
        return { success = false, error = result }
    end
    return { success = true, data = result }
end)

lib.callback.register("midnight-redeem:resetRuntimeConfig", function(source, section)
    if not AdminHasPermission(source, "FULL_ACCESS") then
        return { success = false, error = "Owner access required." }
    end
    local ok, result = RuntimeConfig.resetSection(source, section)
    if not ok then
        return { success = false, error = result }
    end
    return { success = true, data = result }
end)

local function buildAIChatSettingsPayload()
    return {
        aiEnabled = Config.AIEnabled ~= false,
        rateLimit = tonumber(Config.AIChatRateLimit) or 0,
        rateLimitWindow = tonumber(Config.AIChatRateLimitWindow) or 24,
        transcriptRetentionDays = tonumber(Config.TranscriptRetentionDays) or 31,
        welcomeMessage = Config.AIWelcomeMessage or DEFAULT_WELCOME,
        webSearchEnabled = GetConvarInt("MREDEEM_AI_WEB_SEARCH", 0) == 1,
        aiProvider = GetConvar("MREDEEM_AI_PROVIDER", "openai"),
        aiModel = GetConvar("MREDEEM_AI_MODEL", "gpt-4.1-mini"),
    }
end

lib.callback.register("midnight-redeem:getAIChatSettings", function(source)
    if not AdminHasPermission(source, "FULL_ACCESS") then
        return { success = false, error = "Owner access required." }
    end
    return { success = true, settings = buildAIChatSettingsPayload(), canEdit = true }
end)

lib.callback.register("midnight-redeem:saveAIChatSettings", function(source, payload)
    if not AdminHasPermission(source, "FULL_ACCESS") then
        return { success = false, error = "Owner access required." }
    end
    if type(payload) ~= "table" then
        return { success = false, error = "Invalid settings payload." }
    end
    local welcomeMessage = tostring(payload.welcomeMessage or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if welcomeMessage == "" then
        return { success = false, error = "Welcome message cannot be empty." }
    end
    local ok, result = RuntimeConfig.saveSection(source, "aiChat", {
        aiEnabled = payload.aiEnabled == true,
        rateLimit = math.max(0, tonumber(payload.rateLimit) or 0),
        rateLimitWindow = math.max(1, tonumber(payload.rateLimitWindow) or 24),
        transcriptRetentionDays = math.max(0, tonumber(payload.transcriptRetentionDays) or 31),
        welcomeMessage = welcomeMessage:sub(1, 500),
    })
    if not ok then
        return { success = false, error = result }
    end
    return { success = true, settings = buildAIChatSettingsPayload() }
end)

lib.callback.register("midnight-redeem:runTranscriptCleanup", function(source)
    if not AdminHasPermission(source, "FULL_ACCESS") then
        return { success = false, error = "Owner access required." }
    end
    local deleted = CleanupOldTranscripts and CleanupOldTranscripts() or 0
    return { success = true, deleted = deleted or 0 }
end)

lib.callback.register("midnight-redeem:clearAllTranscripts", function(source)
    if not AdminHasPermission(source, "FULL_ACCESS") then
        return { success = false, error = "Owner access required." }
    end
    local sessionCount = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM midnight_ai_chat_sessions")) or 0
    local messageCount = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM midnight_ai_chat_messages")) or 0
    MySQL.query.await("DELETE FROM midnight_ai_chat_messages")
    MySQL.update.await("DELETE FROM midnight_ai_chat_sessions")
    if SendToDiscord then
        SendToDiscord(
            "All Transcripts Cleared",
            string.format("**Cleared by:** `%s`\n**Sessions:** `%d`\n**Messages:** `%d`", GetPlayerName(source) or "Unknown", sessionCount, messageCount),
            15158332,
            nil,
            "admin"
        )
    end
    return { success = true, sessionsDeleted = sessionCount, messagesDeleted = messageCount }
end)

lib.callback.register("midnight-redeem:resetAIChatRateLimits", function(source)
    if not AdminHasPermission(source, "FULL_ACCESS") then
        return { success = false, error = "Owner access required." }
    end
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS midnight_ai_chat_rate_limit (
        id INT AUTO_INCREMENT PRIMARY KEY,
        identifier VARCHAR(255) NOT NULL,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )]])
    local deleted = MySQL.update.await("DELETE FROM midnight_ai_chat_rate_limit") or 0
    return { success = true, deleted = deleted }
end)

lib.callback.register("midnight-redeem:getAIEnabled", function()
    return { enabled = Config.AIEnabled ~= false }
end)

function RuntimeConfig.init()
    if configInitialized then
        return
    end
    configInitialized = true

    local ok, err = pcall(function()
        RuntimeConfig.applyOverrides(loadOrSeedConfig(true))
    end)

    if not ok then
        print(("[midnight_redeem] Failed to load runtime config from database: %s"):format(tostring(err)))
        storedConfigCache = storedConfigCache or getDefaultSnapshot()
        RuntimeConfig.applyOverrides(storedConfigCache)
    end

    RuntimeConfig.syncToClient(-1)
end

RegisterNetEvent("midnight-redeem:requestClientConfig", function()
    local src = source
    if not src or src <= 0 then return end
    RuntimeConfig.init()
    RuntimeConfig.syncToClient(src)
end)

AddEventHandler("onResourceStart", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    CreateThread(function()
        RuntimeConfig.init()
    end)
end)
