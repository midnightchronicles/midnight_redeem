Bridge = exports['community_bridge']:Bridge()

locales = Bridge.Language.Locale

function DebugPrint(message)
    if not Config.Debug then return end
    print("[Midnight_Redeem] " .. message)
end

if not IsDuplicityVersion() then return end

function GetFrameworkVersion()
    return Bridge.Framework.GetFrameworkName() or "unknown"
end

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
                PRIMARY KEY (code),
                CONSTRAINT redeemed_by_valid CHECK (JSON_VALID(redeemed_by))
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci
        ]])
        print("Midnight Chronicles Setting Up The midnight_codes SQL Tables For You. This only runs once and is here to make it easy for you.")
        Wait(1000)
        return
    end

    local col = MySQL.query.await([[SHOW COLUMNS FROM midnight_codes LIKE "per_user_limit"]])
    if not col or #col == 0 then
        MySQL.query.await([[ALTER TABLE midnight_codes ADD COLUMN per_user_limit INT NOT NULL DEFAULT 1]])
        print("Midnight Chronicles: Added 'per_user_limit' column to 'midnight_codes' this will only be done once to make it easy for you.")
    end

    MySQL.query.await([[
        UPDATE midnight_codes
           SET redeemed_by = JSON_OBJECT()
         WHERE redeemed_by IS NULL
            OR JSON_VALID(redeemed_by) = 0
            OR JSON_TYPE(redeemed_by) <> 'OBJECT'
    ]])
end

function CheckUnusedCodes()
    local time = os.date("%Y-%m-%d %H:%M:%S")
    local results = MySQL.query.await('SELECT * FROM midnight_codes WHERE expiry IS NOT NULL AND expiry <= ? AND uses > 0 AND expired_notified = 0', { time })
    if not results or #results == 0 then return end
    for _, row in ipairs(results) do
        local items = (pcall(json.decode, row.items or "[]")) and json.decode(row.items or "[]") or {}
        local rewardLines = {}
        for _, reward in ipairs(items) do
            if reward.item then
                table.insert(rewardLines, ("• %dx %s"):format(reward.amount or 1, reward.item))
            elseif reward.money then
                table.insert(rewardLines, ("• $%s (%s)"):format(reward.amount or 0, reward.option or "cash"))
            elseif reward.vehicle then
                table.insert(rewardLines, ("• Vehicle: %s"):format(reward.model or "Unknown"))
            end
        end
        local rewardText = next(rewardLines) and table.concat(rewardLines, "\n") or "None"
        local expiryDisplay = row.expiry
        if tonumber(expiryDisplay) then
            expiryDisplay = math.floor(tonumber(expiryDisplay) / 1000)
            expiryDisplay = os.date("%Y-%m-%d %H:%M:%S", expiryDisplay)
        end
        local msg = ("**Code:** `%s`\n**Expired:** `%s`\n**Uses Left:** `%s`\n\n**Rewards:**\n%s\n\n*This code expired without being fully used!*"):format(row.code, expiryDisplay or "N/A", row.uses, rewardText)
        SendToDiscord("Code Expired & Unused", msg, 15158332)
        exports.oxmysql:execute('UPDATE midnight_codes SET expired_notified = 1 WHERE code = ?', { row.code })
    end
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Bridge.Version.VersionChecker("midnightchronicles/midnight_redeem", false)
    GenerateSQLTables()
    CheckUnusedCodes()
end)