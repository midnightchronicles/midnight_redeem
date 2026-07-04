Config = Config or {}

local Bridge = exports['community_bridge']:Bridge()

locales = Bridge.Language.Locale

function Debugprint(message)
    if Config and Config.Debug then
        print("[midnight_redeem] " .. tostring(message))
    end
end

if not IsDuplicityVersion() then return end

function GetFrameworkVersion()
    return Bridge.Framework.GetFrameworkName() or "unknown"
end

Config.mincustomchar = Config.mincustomchar or 6



function GenerateSQLTables()
    local result = MySQL.query.await('SHOW TABLES LIKE "midnight_codes"')
    if not result or #result == 0 then
        MySQL.query.await([[
            CREATE TABLE midnight_codes (
                code VARCHAR(60) NOT NULL COLLATE 'utf8mb3_general_ci',
                total_item_count INT NOT NULL,
                items JSON NOT NULL,
                uses INT NOT NULL,
                created_by VARCHAR(255) NOT NULL COLLATE 'utf8mb3_general_ci',
                expiry DATETIME NULL DEFAULT NULL,
                redeemed_by JSON NULL DEFAULT (JSON_OBJECT()),
                expired_notified TINYINT(1) NOT NULL DEFAULT 0,
                per_user_limit INT NOT NULL DEFAULT 1,
                restricted_to_enabled TINYINT(1) NOT NULL DEFAULT 0,
                restricted_to_type VARCHAR(32) NULL DEFAULT NULL COLLATE 'utf8mb3_general_ci',
                restricted_to_value VARCHAR(255) NULL DEFAULT NULL COLLATE 'utf8mb3_general_ci',
                unlimited TINYINT(1) NOT NULL DEFAULT 0,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (code),
                INDEX idx_uses (uses),
                INDEX idx_expiry (expiry),
                INDEX idx_expired_notified (expired_notified),
                INDEX idx_created_by (created_by),
                INDEX idx_uses_expiry (uses, expiry),
                INDEX idx_created_at (created_at),
                INDEX idx_updated_at (updated_at),
                INDEX idx_unlimited (unlimited),
                INDEX idx_created_at_expiry (created_at, expiry),
                INDEX idx_unlimited_uses (unlimited, uses),
                CONSTRAINT redeemed_by_valid CHECK (JSON_VALID(redeemed_by))
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci
        ]])
        Debugprint("Midnight Chronicles Setting Up The midnight_codes SQL Tables For You. This only runs once and is here to make it easy for you.")
        Wait(1000)
    else

        local columns = {
            { name = 'created_at', sql = 'TIMESTAMP DEFAULT CURRENT_TIMESTAMP' },
            { name = 'per_user_limit', sql = 'INT NOT NULL DEFAULT 1' },
            { name = 'updated_at', sql = 'TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP' },
            { name = 'time_locked', sql = 'TINYINT(1) NOT NULL DEFAULT 0' },
            { name = 'time_restrictions', sql = 'JSON NULL DEFAULT NULL' },
            { name = 'time_restrictions_active', sql = 'TINYINT(1) NOT NULL DEFAULT 0' },
            { name = 'cycle_based_limit', sql = 'TINYINT(1) NOT NULL DEFAULT 0' },
            { name = 'user_cycle_redemptions', sql = 'JSON NULL DEFAULT NULL' },
            { name = 'restricted_to_enabled', sql = 'TINYINT(1) NOT NULL DEFAULT 0' },
            { name = 'restricted_to_type', sql = 'VARCHAR(32) NULL DEFAULT NULL COLLATE \'utf8mb3_general_ci\'' },
            { name = 'restricted_to_value', sql = 'VARCHAR(255) NULL DEFAULT NULL COLLATE \'utf8mb3_general_ci\'' },
            { name = 'unlimited', sql = 'TINYINT(1) NOT NULL DEFAULT 0' }
        }
        
        for _, col in ipairs(columns) do
            local colExists = MySQL.query.await(string.format([[
                SELECT COUNT(*) as count FROM information_schema.columns 
                WHERE table_schema = DATABASE() 
                AND table_name = 'midnight_codes' 
                AND column_name = '%s'
            ]], col.name))
            
            if not colExists or colExists[1].count == 0 then
                MySQL.query.await(string.format('ALTER TABLE midnight_codes ADD COLUMN %s %s', col.name, col.sql))
            end
        end
        

        local indexes = {
            'idx_uses',
            'idx_expiry', 
            'idx_expired_notified',
            'idx_created_by',
            'idx_uses_expiry',
            'idx_created_at',
            'idx_updated_at',
            'idx_time_locked',
            'idx_time_restrictions_active',
            'idx_cycle_based_limit',
            'idx_unlimited',
            'idx_created_at_expiry',
            'idx_unlimited_uses'
        }
        
        for _, indexName in ipairs(indexes) do
            local indexExists = MySQL.query.await(string.format([[
                SELECT COUNT(*) as count FROM information_schema.statistics 
                WHERE table_schema = DATABASE() 
                AND table_name = 'midnight_codes' 
                AND index_name = '%s'
            ]], indexName))
            
            if not indexExists or indexExists[1].count == 0 then
                if indexName == 'idx_uses_expiry' then
                    MySQL.query.await('CREATE INDEX idx_uses_expiry ON midnight_codes (uses, expiry)')
                elseif indexName == 'idx_uses' then
                    MySQL.query.await('CREATE INDEX idx_uses ON midnight_codes (uses)')
                elseif indexName == 'idx_expiry' then
                    MySQL.query.await('CREATE INDEX idx_expiry ON midnight_codes (expiry)')
                elseif indexName == 'idx_expired_notified' then
                    MySQL.query.await('CREATE INDEX idx_expired_notified ON midnight_codes (expired_notified)')
                elseif indexName == 'idx_created_by' then
                    MySQL.query.await('CREATE INDEX idx_created_by ON midnight_codes (created_by)')
                elseif indexName == 'idx_created_at' then
                    MySQL.query.await('CREATE INDEX idx_created_at ON midnight_codes (created_at)')
                elseif indexName == 'idx_updated_at' then
                    MySQL.query.await('CREATE INDEX idx_updated_at ON midnight_codes (updated_at)')
                elseif indexName == 'idx_time_locked' then
                    MySQL.query.await('CREATE INDEX idx_time_locked ON midnight_codes (time_locked)')
                elseif indexName == 'idx_time_restrictions_active' then
                    MySQL.query.await('CREATE INDEX idx_time_restrictions_active ON midnight_codes (time_restrictions_active)')
                elseif indexName == 'idx_cycle_based_limit' then
                    MySQL.query.await('CREATE INDEX idx_cycle_based_limit ON midnight_codes (cycle_based_limit)')
                elseif indexName == 'idx_unlimited' then
                    MySQL.query.await('CREATE INDEX idx_unlimited ON midnight_codes (unlimited)')
                elseif indexName == 'idx_created_at_expiry' then
                    MySQL.query.await('CREATE INDEX idx_created_at_expiry ON midnight_codes (created_at, expiry)')
                elseif indexName == 'idx_unlimited_uses' then
                    MySQL.query.await('CREATE INDEX idx_unlimited_uses ON midnight_codes (unlimited, uses)')
                end
            end
        end
    end

    MySQL.query.await([[
        UPDATE midnight_codes
           SET redeemed_by = JSON_OBJECT()
         WHERE redeemed_by IS NULL
            OR JSON_VALID(redeemed_by) = 0
            OR JSON_TYPE(redeemed_by) <> 'OBJECT'
    ]])


    MySQL.query.await([[
        UPDATE midnight_codes
           SET updated_at = created_at
         WHERE updated_at IS NULL
    ]])

    local permResult = MySQL.query.await('SHOW TABLES LIKE "midnight_user_permissions"')
    if not permResult or #permResult == 0 then
        MySQL.query.await([[
            CREATE TABLE midnight_user_permissions (
                identifier VARCHAR(255) NOT NULL COLLATE 'utf8mb3_general_ci',
                role VARCHAR(20) NOT NULL DEFAULT 'staff' COLLATE 'utf8mb3_general_ci',
                permission_level INT NOT NULL DEFAULT 1,
                player_name VARCHAR(255) NULL COLLATE 'utf8mb3_general_ci',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (identifier),
                INDEX idx_role (role),
                INDEX idx_permission_level (permission_level),
                INDEX idx_player_name (player_name)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci
        ]])
        Debugprint("Midnight Chronicles Setting Up The midnight_user_permissions SQL Tables For You. This only runs once and is here to make it easy for you.")
        Wait(1000)
    else

        MySQL.query.await([[
            ALTER TABLE midnight_user_permissions 
            ADD COLUMN IF NOT EXISTS player_name VARCHAR(255) NULL COLLATE 'utf8mb3_general_ci'
        ]])
    end

    local templateResult = MySQL.query.await('SHOW TABLES LIKE "midnight_templates"')
    if not templateResult or #templateResult == 0 then
        MySQL.query.await([[
            CREATE TABLE midnight_templates (
                id INT AUTO_INCREMENT PRIMARY KEY,
                name VARCHAR(255) NOT NULL COLLATE 'utf8mb3_general_ci',
                category VARCHAR(50) NOT NULL DEFAULT 'custom' COLLATE 'utf8mb3_general_ci',
                rewards JSON NOT NULL,
                created_by VARCHAR(255) NOT NULL COLLATE 'utf8mb3_general_ci',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                INDEX idx_created_by (created_by),
                INDEX idx_category (category),
                INDEX idx_name (name),
                INDEX idx_created_at (created_at),
                CONSTRAINT rewards_valid CHECK (JSON_VALID(rewards))
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci
        ]])
        Debugprint("Midnight Chronicles Setting Up The midnight_templates SQL Tables For You. This only runs once and is here to make it easy for you.")
        Wait(1000)
    else

        local templateColumns = {
            { name = 'category', sql = 'VARCHAR(50) NOT NULL DEFAULT \'custom\' COLLATE \'utf8mb3_general_ci\'' },
            { name = 'created_at', sql = 'TIMESTAMP DEFAULT CURRENT_TIMESTAMP' },
            { name = 'updated_at', sql = 'TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP' }
        }
        
        for _, col in ipairs(templateColumns) do
            local colExists = MySQL.query.await(string.format([[
                SELECT COUNT(*) as count FROM information_schema.columns 
                WHERE table_schema = DATABASE() 
                AND table_name = 'midnight_templates' 
                AND column_name = '%s'
            ]], col.name))
            
            if not colExists or colExists[1].count == 0 then
                MySQL.query.await(string.format('ALTER TABLE midnight_templates ADD COLUMN %s %s', col.name, col.sql))
            end
        end
        

        local templateIndexes = {
            'idx_created_by',
            'idx_category',
            'idx_name',
            'idx_created_at'
        }
        
        for _, indexName in ipairs(templateIndexes) do
            local indexExists = MySQL.query.await(string.format([[
                SELECT COUNT(*) as count FROM information_schema.statistics 
                WHERE table_schema = DATABASE() 
                AND table_name = 'midnight_templates' 
                AND index_name = '%s'
            ]], indexName))
            
            if not indexExists or indexExists[1].count == 0 then
                if indexName == 'idx_created_by' then
                    MySQL.query.await('CREATE INDEX idx_created_by ON midnight_templates (created_by)')
                elseif indexName == 'idx_category' then
                    MySQL.query.await('CREATE INDEX idx_category ON midnight_templates (category)')
                elseif indexName == 'idx_name' then
                    MySQL.query.await('CREATE INDEX idx_name ON midnight_templates (name)')
                elseif indexName == 'idx_created_at' then
                    MySQL.query.await('CREATE INDEX idx_created_at ON midnight_templates (created_at)')
                end
            end
        end

        local constraintExists = MySQL.query.await([[
            SELECT COUNT(*) as count FROM information_schema.table_constraints 
            WHERE table_schema = DATABASE() 
            AND table_name = 'midnight_templates' 
            AND constraint_name = 'rewards_valid'
        ]])
        
        if not constraintExists or constraintExists[1].count == 0 then
            MySQL.query.await('ALTER TABLE midnight_templates ADD CONSTRAINT rewards_valid CHECK (JSON_VALID(rewards))')
        end
    end

    local statsResult = MySQL.query.await('SHOW TABLES LIKE "midnight_redeem_stats"')
    if not statsResult or #statsResult == 0 then
        MySQL.query.await([[
            CREATE TABLE midnight_redeem_stats (
                id INT AUTO_INCREMENT PRIMARY KEY,
                reward_type VARCHAR(50) NOT NULL COLLATE 'utf8mb3_general_ci',
                reward_name VARCHAR(255) NOT NULL COLLATE 'utf8mb3_general_ci',
                reward_amount INT NULL DEFAULT NULL,
                redemption_count INT NOT NULL DEFAULT 1,
                last_redeemed TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                INDEX idx_reward_type (reward_type),
                INDEX idx_reward_name (reward_name),
                INDEX idx_redemption_count (redemption_count),
                INDEX idx_last_redeemed (last_redeemed),
                UNIQUE KEY unique_reward (reward_type, reward_name, reward_amount)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci
        ]])
        Debugprint("Midnight Chronicles Setting Up The midnight_redeem_stats SQL Tables For You. This only runs once and is here to make it easy for you.")
        Wait(1000)
    end

    local aiChatRateLimitResult = MySQL.query.await('SHOW TABLES LIKE "midnight_ai_chat_rate_limit"')
    if not aiChatRateLimitResult or #aiChatRateLimitResult == 0 then
        MySQL.query.await([[
            CREATE TABLE midnight_ai_chat_rate_limit (
                id INT AUTO_INCREMENT PRIMARY KEY,
                identifier VARCHAR(255) NOT NULL COLLATE 'utf8mb3_general_ci',
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_identifier_timestamp (identifier, timestamp),
                INDEX idx_timestamp (timestamp)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci
        ]])
        Debugprint("Midnight Chronicles Setting Up The midnight_ai_chat_rate_limit SQL Tables For You. This only runs once and is here to make it easy for you.")
        Wait(1000)
    else
        -- Check and create indexes if they don't exist
        local indexes = {
            'idx_identifier_timestamp',
            'idx_timestamp'
        }
        
        for _, indexName in ipairs(indexes) do
            local indexExists = MySQL.query.await(string.format([[
                SELECT COUNT(*) as count FROM information_schema.statistics 
                WHERE table_schema = DATABASE() 
                AND table_name = 'midnight_ai_chat_rate_limit' 
                AND index_name = '%s'
            ]], indexName))
            
            if not indexExists or indexExists[1].count == 0 then
                if indexName == 'idx_identifier_timestamp' then
                    MySQL.query.await('CREATE INDEX idx_identifier_timestamp ON midnight_ai_chat_rate_limit (identifier, timestamp)')
                elseif indexName == 'idx_timestamp' then
                    MySQL.query.await('CREATE INDEX idx_timestamp ON midnight_ai_chat_rate_limit (timestamp)')
                end
            end
        end
    end
end

function OptimizeDatabasePerformance()
    local success = pcall(function()
        MySQL.query.await("SET SESSION wait_timeout = 28800")
        MySQL.query.await("SET SESSION interactive_timeout = 28800")
        MySQL.query.await("SET SESSION sql_mode = 'STRICT_TRANS_TABLES,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO'")
        MySQL.query.await("ANALYZE TABLE midnight_codes")
        MySQL.query.await("ANALYZE TABLE midnight_redeem_stats")
        MySQL.query.await("ANALYZE TABLE midnight_templates")
        MySQL.query.await("ANALYZE TABLE midnight_user_permissions")
        MySQL.query.await("ANALYZE TABLE midnight_ai_chat_rate_limit")
        MySQL.query.await("ANALYZE TABLE midnight_ai_chat_sessions")
        MySQL.query.await("ANALYZE TABLE midnight_ai_chat_messages")
        
        Debugprint("Database performance optimization completed successfully")
    end)
    
    if not success then
        Debugprint("Database optimization failed (this is normal for some setups)")
    end
end

-- Create AI chat sessions and messages tables
local function CreateAIChatTables()
    -- Create AI chat sessions table
    local aiChatSessionsResult = MySQL.query.await('SHOW TABLES LIKE "midnight_ai_chat_sessions"')
    if not aiChatSessionsResult or #aiChatSessionsResult == 0 then
        MySQL.query.await([[
            CREATE TABLE midnight_ai_chat_sessions (
                id INT AUTO_INCREMENT PRIMARY KEY,
                session_id VARCHAR(32) NOT NULL UNIQUE COLLATE 'utf8mb3_general_ci',
                identifier VARCHAR(255) NOT NULL COLLATE 'utf8mb3_general_ci',
                player_name VARCHAR(255) NOT NULL COLLATE 'utf8mb3_general_ci',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                INDEX idx_session_id (session_id),
                INDEX idx_identifier (identifier),
                INDEX idx_created_at (created_at),
                INDEX idx_identifier_created_at (identifier, created_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci
        ]])
        Debugprint("Midnight Chronicles Setting Up The midnight_ai_chat_sessions SQL Tables For You. This only runs once and is here to make it easy for you.")
        Wait(1000)
    else
        local sessionIdColumn = MySQL.query.await([[
            SELECT CHARACTER_MAXIMUM_LENGTH as max_len
            FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
            AND TABLE_NAME = 'midnight_ai_chat_sessions'
            AND COLUMN_NAME = 'session_id'
        ]])

        local maxLen = sessionIdColumn and sessionIdColumn[1] and tonumber(sessionIdColumn[1].max_len) or 0
        if maxLen > 0 and maxLen < 32 then
            MySQL.query.await("ALTER TABLE midnight_ai_chat_sessions MODIFY COLUMN session_id VARCHAR(32) NOT NULL COLLATE 'utf8mb3_general_ci'")
            Debugprint("Updated midnight_ai_chat_sessions session_id column size")
        end
    end
    
    -- Create AI chat messages table
    local aiChatMessagesResult = MySQL.query.await('SHOW TABLES LIKE "midnight_ai_chat_messages"')
    if not aiChatMessagesResult or #aiChatMessagesResult == 0 then
        MySQL.query.await([[
            CREATE TABLE midnight_ai_chat_messages (
                id INT AUTO_INCREMENT PRIMARY KEY,
                session_id VARCHAR(32) NOT NULL COLLATE 'utf8mb3_general_ci',
                role ENUM('user', 'assistant') NOT NULL,
                content TEXT NOT NULL COLLATE 'utf8mb3_general_ci',
                timestamp TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3),
                INDEX idx_session_id (session_id),
                INDEX idx_timestamp (timestamp),
                INDEX idx_session_timestamp (session_id, timestamp)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci
        ]])
        Debugprint("Midnight Chronicles Setting Up The midnight_ai_chat_messages SQL Tables For You. This only runs once and is here to make it easy for you.")
        Wait(1000)
    else
        -- Check if timestamp has millisecond precision, if not add it
        local timestampColumn = MySQL.query.await([[
            SELECT DATA_TYPE, COLUMN_TYPE 
            FROM information_schema.COLUMNS 
            WHERE TABLE_SCHEMA = DATABASE() 
            AND TABLE_NAME = 'midnight_ai_chat_messages' 
            AND COLUMN_NAME = 'timestamp'
        ]])
        
        if timestampColumn and timestampColumn[1] then
            local columnType = timestampColumn[1].COLUMN_TYPE or ""
            if not string.find(columnType, "TIMESTAMP(3)") then
                MySQL.query.await("ALTER TABLE midnight_ai_chat_messages MODIFY COLUMN timestamp TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3)")
                Debugprint("Updated midnight_ai_chat_messages timestamp column to support milliseconds")
            end
        end
        
        local messageSessionIdColumn = MySQL.query.await([[
            SELECT CHARACTER_MAXIMUM_LENGTH as max_len
            FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
            AND TABLE_NAME = 'midnight_ai_chat_messages'
            AND COLUMN_NAME = 'session_id'
        ]])

        local msgMaxLen = messageSessionIdColumn and messageSessionIdColumn[1] and tonumber(messageSessionIdColumn[1].max_len) or 0
        if msgMaxLen > 0 and msgMaxLen < 32 then
            MySQL.query.await("ALTER TABLE midnight_ai_chat_messages MODIFY COLUMN session_id VARCHAR(32) NOT NULL COLLATE 'utf8mb3_general_ci'")
            Debugprint("Updated midnight_ai_chat_messages session_id column size")
        end
    end
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    GenerateSQLTables()
    Wait(200)
    CreateAIChatTables()
    Wait(100)
    OptimizeDatabasePerformance()
    Wait(100)
end)

function _nowMinutes()
    local now = os.date("*t")
    return now.hour * 60 + now.min
end

function _formatHHMM(mins)
    local h = math.floor(mins / 60)
    local m = mins % 60
    return string.format("%02d%02d", h, m)
end

function _parseDailyReward(entry)
    if type(entry) == "table" then
        local rewards = {}
        local hasRewards = false
        
        for key, value in pairs(entry) do
            local itemName = tostring(key)
            local amount = tonumber(value)
            
            if amount and amount > 0 then
                local lname = itemName:lower()
                
                if lname == "cash" or lname == "bank" then
                    table.insert(rewards, { money = true, amount = amount, option = lname })
                    hasRewards = true
                else
                    local reward = { item = itemName, amount = amount }
                    if type(value) == "table" and value.label then
                        reward.label = tostring(value.label)
                    end
                    table.insert(rewards, reward)
                    hasRewards = true
                end
            elseif itemName and type(value) == "string" and value ~= "" then
                local lname = itemName:lower()
                if lname == "vehicle" then
                    table.insert(rewards, { vehicle = true, model = value })
                    hasRewards = true
                end
            end
        end
        
        if hasRewards then
            return #rewards == 1 and rewards[1] or rewards
        end
        
        if entry.money then
            local amt = tonumber(entry.amount or 0) or 0
            if amt > 0 then
                local opt = (entry.option and tostring(entry.option):lower()) or "cash"
                if opt ~= "cash" and opt ~= "bank" then opt = "cash" end
                return { money = true, amount = amt, option = opt }
            end
        elseif entry.item then
            local item = tostring(entry.item)
            local amt  = tonumber(entry.amount or 0) or 0
            if item ~= "" and amt > 0 then
                local reward = { item = item, amount = amt }
                if entry.label and tostring(entry.label) ~= "" then
                    reward.label = tostring(entry.label)
                end
                return reward
            end
        elseif entry.vehicle then
            local model = nil
            if type(entry.vehicle) == "string" then
                model = entry.vehicle
            elseif entry.model then
                model = tostring(entry.model)
            end
            if model and model ~= "" then
                local reward = { vehicle = true, model = model }
                if entry.label and tostring(entry.label) ~= "" then
                    reward.label = tostring(entry.label)
                end
                return reward
            end
        end
        return nil
    elseif type(entry) == "string" then
        local left, right = entry:match("^%s*([^%.,:%s]+)[%.,:](%d+)%s*$")
        if left and right then
            local name = tostring(left)
            local amt  = tonumber(right)
            if not amt or amt <= 0 then return nil end
            local lname = name:lower()
            if lname == "cash" or lname == "bank" then
                return { money = true, amount = amt, option = lname }
            else
                return { item = name, amount = amt }
            end
        end
        return nil
    end
    return nil
end

function _getConfiguredTimesInMinutes()
    local times = {}
    if Config and Config.RewardTimes then
        for _, timeStr in ipairs(Config.RewardTimes) do
            local hour, min = timeStr:match("(%d+):(%d+)")
            if hour and min then
                table.insert(times, tonumber(hour) * 60 + tonumber(min))
            end
        end
    end
    return times
end




