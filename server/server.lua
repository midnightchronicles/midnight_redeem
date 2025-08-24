local Bridge = exports['community_bridge']:Bridge()

-- === Shared helpers =========================================================
local json_decode = json.decode
local json_encode = json.encode
local fmt = string.format
local insert = table.insert
local concat = table.concat

local function safe_json_decode(str, fallback)
    local ok, t = pcall(json_decode, str or "[]")
    return (ok and t) or (fallback or {})
end

local function build_reward_lines(items)
    local lines = {}
    for _, r in ipairs(items or {}) do
        if r.item then
            insert(lines, fmt("• %dx %s", r.amount or 1, r.item))
        elseif r.money then
            insert(lines, fmt("• $%s (%s)", r.amount or 0, r.option or "cash"))
        elseif r.vehicle then
            insert(lines, fmt("• Vehicle: %s", r.model or "Unknown"))
        end
    end
    return lines, (next(lines) and concat(lines, "\n") or "None")
end

local function parse_expiry_flexible(expiryFlexible)
    if expiryFlexible == nil then return nil end
    local t = type(expiryFlexible)
    if t == "number" then
        if expiryFlexible > 0 then
            return os.date("%Y-%m-%d %H:%M:%S", os.time() + (expiryFlexible * 86400))
        else
            return nil
        end
    elseif t == "string" then
        if #expiryFlexible >= 19 and expiryFlexible:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$") then
            return expiryFlexible
        end
        local maybeDays = tonumber(expiryFlexible)
        if maybeDays and maybeDays > 0 then
            return os.date("%Y-%m-%d %H:%M:%S", os.time() + (maybeDays * 86400))
        end
    end
    return nil
end

-- === Expiry checker (batched marking, less decoding) ========================
function CheckExpiredUnusedCodes()
    local now = os.date("%Y-%m-%d %H:%M:%S")
    local results = MySQL.query.await([[
        SELECT code, items, expiry, uses
        FROM midnight_codes
        WHERE expiry IS NOT NULL
          AND expiry <= ?
          AND uses > 0
          AND expired_notified = 0
    ]], { now })
    if not results or #results == 0 then return end

    local toMark = {}
    for _, row in ipairs(results) do
        local items = safe_json_decode(row.items, {})
        local _, rewardText = build_reward_lines(items)

        local expiryDisplay = row.expiry
        if tonumber(expiryDisplay) then
            expiryDisplay = math.floor(tonumber(expiryDisplay) / 1000)
            expiryDisplay = os.date("%Y-%m-%d %H:%M:%S", expiryDisplay)
        end

        local msg = fmt("**Code:** `%s`\n**Expired:** `%s`\n**Uses Left:** `%s`\n\n**Rewards:**\n%s\n\n*This code expired without being fully used!*",
            row.code, expiryDisplay or "N/A", row.uses, rewardText)
        SendToDiscord("Code Expired & Unused", msg, 15158332)
        insert(toMark, row.code)
    end

    if #toMark > 0 then
        local placeholders = {}
        for i=1,#toMark do placeholders[i] = "?" end
        MySQL.query.await("UPDATE midnight_codes SET expired_notified = 1 WHERE code IN (" .. table.concat(placeholders, ",") .. ")", toMark)
    end
end

-- === Delete code (same flow, simpler affected check) ========================
RegisterServerEvent("midnight-redeem:deleteCode", function(code)
    local src = source
    if not Bridge.Framework.GetIsFrameworkAdmin(src) then
        return Bridge.Notify.SendNotify(src, locales("NOTIFY_PERMISSION_DENIED_DELETE"), "error", 6000)
    end

    local affected = MySQL.update.await('DELETE FROM midnight_codes WHERE code = ?', { code })
    if (affected or 0) > 0 then
        Bridge.Notify.SendNotify(src, locales("NOTIFY_CODE_DELETED", code), "success", 6000)
        SendToDiscord("Code Deleted", string.format("**Code:** `%s`\n**admin** `%s`.", code, GetPlayerName(src)), 15158332)
    else
        Bridge.Notify.SendNotify(src, locales("NOTIFY_CODE_NOT_FOUND", code), "error", 6000)
    end
end)

-- === Create code (same API, fewer decodes & helper usage) ===================
function HandleRedeemCode(source, itemsJson, uses, expiryFlexible, customCode)
    local playerName = GetPlayerName(source) or "discord admin"

    local success, itemsTable = pcall(json_decode, itemsJson)
    if not success or type(itemsTable) ~= "table" then
        return Bridge.Notify.SendNotify(source, locales("NOTIFY_INVALID_ITEM_DATA"), "error", 6000)
    end

    uses = tonumber(uses)
    if not uses or uses <= 0 then
        return Bridge.Notify.SendNotify(source, locales("NOTIFY_INVALID_USES"), "error", 6000)
    end

    local expiryDate = parse_expiry_flexible(expiryFlexible)

    local rewards = (type(itemsTable[1]) == "table") and itemsTable or { itemsTable }
    local totalItemCount = 0
    for _, reward in ipairs(rewards) do
        if reward.item then totalItemCount = totalItemCount + (tonumber(reward.amount) or 0) end
    end

    local insertId = MySQL.insert.await(
        'INSERT INTO midnight_codes (code, total_item_count, items, uses, created_by, expiry, redeemed_by, expired_notified) VALUES (?, ?, ?, ?, ?, ?, ?, 0)',
        { customCode, totalItemCount, itemsJson, uses, playerName, expiryDate, json_encode({}) }
    )

    if insertId then
        TriggerClientEvent("midnight-redeem:notifyUser", source, locales("NOTIFY_CODE_CREATED"), locales("NOTIFY_CODE_CREATED"), "success")

        local _, rewardText = build_reward_lines(rewards)
        local message = string.format(
            "**Admin:** `%s`\n**Code:** `%s`\n**Uses:** `%s`\n**Expiry:** `%s`\n\n**Rewards:**\n%s",
            playerName, customCode, uses, expiryDate or "Never", rewardText
        )
        SendToDiscord("Redeem Code Created", message, 3066993)
    else
        Bridge.Notify.SendNotify(source, locales("NOTIFY_FAILED_INSERT"), "error", 6000)
    end
end

RegisterServerEvent("midnight-redeem:generateCode", function(itemsJson, uses, expiryDays, customCode)
    HandleRedeemCode(source, itemsJson, uses, expiryDays, customCode)
end)

-- === Vehicle helper (await; preserves behavior) =============================
local function addVehicleToGarage(model, playerName, uniqueId)
    local currentFramework = GetFrameworkVersion()
    if model then
        local plate = string.upper(string.sub(playerName or "PLR", 1, 3)) .. math.random(1000, 9999)
        local props = { model = model, plate = plate }
        local state, garage = 1, "pillbox"
        if currentFramework == "es_extended" then
            MySQL.query.await('INSERT INTO `owned_vehicles` (owner, plate, vehicle, stored) VALUES (?, ?, ?, ?)', {
                uniqueId, plate, json_encode(props), state
            })
        elseif currentFramework == "qb-core" then
            MySQL.query.await('INSERT INTO `player_vehicles` (license, citizenid, vehicle, hash, mods, plate, state, garage) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
                uniqueId, uniqueId, model, GetHashKey(model), json_encode(props), plate, state, garage
            })
        end
        return plate
    end
end

-- === Atomic redemption (same event name & outward flow) =====================
local function handleCodeRedemption(src, code, option)
    local uniqueId  = Bridge.Framework.GetPlayerIdentifier(src)
    local playerName= GetPlayerName(src)

    -- Get items only (minimal read)
    local row = (MySQL.query.await(
        'SELECT items FROM midnight_codes WHERE code = ? AND (expiry IS NULL OR expiry > NOW()) LIMIT 1',
        { code }
    ) or {})[1]

    if not row then
        return Bridge.Notify.SendNotify(src, locales("NOTIFY_INVALID_OR_EXPIRED"), "error", 6000)
    end

    local items = safe_json_decode(row.items, {})

    -- Atomic claim: decrement and mark user as redeemed if eligible
    local jsonPath = '$."' .. uniqueId .. '"'
    local affected = MySQL.update.await([[
        UPDATE midnight_codes
           SET uses = uses - 1,
               redeemed_by = JSON_SET(redeemed_by, ?, true)
         WHERE code = ?
           AND (expiry IS NULL OR expiry > NOW())
           AND uses > 0
           AND JSON_EXTRACT(redeemed_by, ?) IS NULL
    ]], { jsonPath, code, jsonPath })

    if (affected or 0) <= 0 then
        -- already redeemed / no uses / expired in the meantime
        return Bridge.Notify.SendNotify(src, locales("NOTIFY_ALREADY_REDEEMED"), "error", 6000)
    end

    -- Grant rewards (safe: one use has been reserved)
    local receivedSummary = {}
    for _, reward in ipairs(items) do
        if reward.item then
            Bridge.Inventory.AddItem(src, reward.item, reward.amount)
            insert(receivedSummary, fmt("• %dx %s", reward.amount or 1, reward.item))
        elseif reward.money then
            local account = reward.option or option or "cash"
            Bridge.Framework.AddAccountBalance(src, account, reward.amount)
            insert(receivedSummary, fmt("• $%s (%s)", reward.amount or 0, account))
        elseif reward.vehicle then
            local plate = addVehicleToGarage(reward.model, playerName, uniqueId)
            insert(receivedSummary, fmt("• Vehicle: %s%s", reward.model or "Unknown", plate and (" (Plate: " .. plate .. ")") or ""))
        end
    end

    local notifyMsg = locales("NOTIFY_SUCCESSFUL_RECEIVE", table.concat(receivedSummary, "\n"))
    TriggerClientEvent("midnight-redeem:notifyUser", src, locales("NOTIFY_CODE_REDEEMED"), notifyMsg, "success")

    local safePlayerName = playerName or "N/A"
    local safeCode = code or "N/A"
    local safeSummary = (#receivedSummary > 0 and table.concat(receivedSummary, "\n")) or "N/A"
    local safeUniqueId = uniqueId or "N/A"

    local message = ("**Redeemed By:** `%s`\n**Code:** `%s`\n**Rewards:**\n%s\n**Identifiers:**\n- UniqueID: `%s`")
        :format(safePlayerName, safeCode, safeSummary, safeUniqueId)
    SendToDiscord("Code Redeemed", message, 15844367)
end

RegisterServerEvent("midnight-redeem:redeemCode", function(code, option)
    handleCodeRedemption(source, code, option)
end)

-- === Export keeps same signature ===========================================
exports('GenerateRedeemCode', function(source, itemsJson, uses, expiryDays, customCode)
    HandleRedeemCode(source, itemsJson, uses, expiryDays, customCode)
end)

-- === zdiscord passthrough unchanged ========================================
RegisterServerEvent("zdiscord:generateRedeemCode", function(itemsJson, uses, expiryFlexible, customCode)
    local usesNum = tonumber(uses)
    local expArg = expiryFlexible
    if type(expiryFlexible) == "string" then
        local d = tonumber(expiryFlexible)
        if d then expArg = d end
    end

    if itemsJson and usesNum and expArg ~= nil and customCode then
        exports["midnight_redeem"]:GenerateRedeemCode(source, itemsJson, usesNum, expArg, customCode)
        print(("Generated redeem code with rewards %s, uses %s, expiry %s, code %s"):format(itemsJson, usesNum, tostring(expArg), customCode))
    else
        print("[zdiscord] Invalid arguments for GenerateRedeemCode.")
    end
end)

-- === Simple list callback (unchanged externally) ============================
lib.callback.register("midnight-redeem:getAllCodes", function(src)
    local src = source
    local results = exports.oxmysql:executeSync("SELECT code FROM midnight_codes")
    local options = {}
    for _, row in ipairs(results or {}) do
        table.insert(options, { label = row.code, value = row.code })
    end
    return options
end)

-- === Admin check (kept same flow; minor helper reuse possible) ==============
RegisterServerEvent("midnight-redeem:adminCheckCode", function(code)
    local src = source
    exports.oxmysql:execute('SELECT * FROM midnight_codes WHERE code = ?', { code }, function(result)
        if result[1] then
            local row = result[1]
            local items = json.decode(row.items or "[]")
            local rewardList = {}
            for _, reward in ipairs(items) do
                if reward.item then
                    table.insert(rewardList, string.format("• %dx %s", reward.amount or 1, reward.item))
                elseif reward.money then
                    table.insert(rewardList, string.format("• $%s (%s)", reward.amount or 0, reward.option or "cash"))
                elseif reward.vehicle then
                    table.insert(rewardList, string.format("• Vehicle: %s", reward.model or "Unknown"))
                end
            end

            local daysLeft = "Never"
            if row.expiry then
                local expiryTime
                if type(row.expiry) == "number" then
                    expiryTime = math.floor(row.expiry / 1000)
                elseif type(row.expiry) == "string" and #row.expiry >= 10 then
                    expiryTime = os.time({
                        year = tonumber(row.expiry:sub(1,4)),
                        month = tonumber(row.expiry:sub(6,7)),
                        day = tonumber(row.expiry:sub(9,10)),
                        hour = tonumber(row.expiry:sub(12,13)) or 0,
                        min = tonumber(row.expiry:sub(15,16)) or 0,
                        sec = tonumber(row.expiry:sub(18,19)) or 0
                    })
                end
                if expiryTime then
                    local now = os.time()
                    local diff = math.floor((expiryTime - now) / 86400)
                    daysLeft = diff >= 0 and tostring(diff) or "Expired"
                end
            end

            local info = ("Code: %s\nUses Left: %s\nDays Left: %s\nRewards:\n%s"):format(
                row.code, row.uses, daysLeft, table.concat(rewardList, "\n")
            )
            Bridge.Notify.SendNotify(src, info, locales("NOTIFY_INFO"), 15000)
        else
            Bridge.Notify.SendNotify(src, locales("NOTIFY_NO_CODE_FOUND"), "error", 6000)
        end
    end)
end)

-- === Details callback (unchanged return shape) ==============================
lib.callback.register("midnight-redeem:getCodeDetails", function(src, code)
    local result = exports.oxmysql:executeSync('SELECT code, uses, expiry, items FROM midnight_codes WHERE code = ?', { code })
    local row = result and result[1]
    if not row then return nil end

    local itemsTbl = {}
    local ok, decoded = pcall(json.decode, row.items or "[]")
    if ok and type(decoded) == "table" then itemsTbl = decoded end

    local expStr = nil
    if row.expiry ~= nil then
        if type(row.expiry) == "number" then
            local ts = row.expiry > 1e12 and math.floor(row.expiry / 1000) or row.expiry
            expStr = os.date("%Y-%m-%d %H:%M:%S", ts)
        elseif type(row.expiry) == "string" then
            expStr = row.expiry
        end
    end

    return {
        code  = row.code,
        uses  = row.uses,
        expiry= expStr,
        items = itemsTbl
    }
end)

-- === Update code (kept your flow; minor tidy) ===============================
RegisterServerEvent("midnight-redeem:updateCode", function(payload)
    local src = source
    if not Bridge.Framework.GetIsFrameworkAdmin(src) then
        return Bridge.Notify.SendNotify(src, locales("NOTIFY_PERMISSION_DENIED_DELETE") or "You do not have permission.", "error", 6000)
    end

    if type(payload) ~= "table" or not payload.originalCode or payload.originalCode == "" then
        return Bridge.Notify.SendNotify(src, locales("NOTIFY_INVALID_DATA") or "Invalid edit payload.", "error", 6000)
    end

    local cur = exports.oxmysql:executeSync('SELECT * FROM midnight_codes WHERE code = ?', { payload.originalCode })
    if not cur or not cur[1] then
        return Bridge.Notify.SendNotify(src, locales("NOTIFY_NO_CODE_FOUND") or "Code not found.", "error", 6000)
    end
    cur = cur[1]

    local newItemsJson = payload.itemsJson or cur.items
    local newUses = payload.uses or cur.uses
    local newCode = payload.newCode or cur.code

    local newExpiry = cur.expiry
    if payload.expiryAbs ~= nil then
        if type(payload.expiryAbs) == "string" and #payload.expiryAbs >= 19
           and payload.expiryAbs:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$") then
            newExpiry = payload.expiryAbs
        else
            newExpiry = nil
        end
    elseif payload.expiryDays ~= nil then
        local days = tonumber(payload.expiryDays) or 0
        if days <= 0 then
            newExpiry = nil
        else
            newExpiry = os.date("%Y-%m-%d %H:%M:%S", os.time() + (days * 86400))
        end
    end

    local totalItemCount = cur.total_item_count
    if payload.itemsJson then
        local ok, tbl = pcall(json.decode, newItemsJson or "[]")
        tbl = ok and tbl or {}
        local sum = 0
        for _, r in ipairs(tbl) do
            if r.item then sum = sum + (tonumber(r.amount) or 0) end
        end
        totalItemCount = sum
    end

    if newCode ~= cur.code then
        local exists = exports.oxmysql:executeSync('SELECT code FROM midnight_codes WHERE code = ?', { newCode })
        if exists and exists[1] then
            return Bridge.Notify.SendNotify(src, locales("NOTIFY_CODE_EXISTS") or "That code already exists.", "error", 6000)
        end
    end

    local q = [[
        UPDATE midnight_codes
        SET code = ?, items = ?, uses = ?, expiry = ?, total_item_count = ?
        WHERE code = ?
    ]]

    exports.oxmysql:execute(q, { newCode, newItemsJson, newUses, newExpiry, totalItemCount, cur.code }, function(affected)
        local okA = affected and ((type(affected) == "number" and affected > 0) or (type(affected) == "table" and affected.affectedRows and affected.affectedRows > 0))
        if okA then
            Bridge.Notify.SendNotify(src, locales("NOTIFY_CODE_UPDATED") or "Code updated.", "success", 6000)

            local rewardsPreview = {}
            local ok2, tbl2 = pcall(json.decode, newItemsJson or "[]")
            tbl2 = ok2 and tbl2 or {}
            for _, reward in ipairs(tbl2) do
                if reward.item then
                    table.insert(rewardsPreview, string.format("• %dx %s", reward.amount or 1, reward.item))
                elseif reward.money then
                    table.insert(rewardsPreview, string.format("• $%s (%s)", reward.amount or 0, reward.option or "cash"))
                elseif reward.vehicle then
                    table.insert(rewardsPreview, string.format("• Vehicle: %s", reward.model or "Unknown"))
                end
            end

            local msg = ("**Admin:** `%s`\n**Old Code:** `%s`\n**New Code:** `%s`\n**Uses:** `%s`\n**Expiry:** `%s`\n\n**Rewards:**\n%s")
                :format(GetPlayerName(src) or "Unknown", cur.code, newCode, newUses or "?", newExpiry or "Never", table.concat(rewardsPreview, "\n"))
            SendToDiscord("Redeem Code Updated", msg, 3447003)
        else
            Bridge.Notify.SendNotify(src, locales("NOTIFY_FAILED_UPDATE") or "Failed to update code.", "error", 6000)
        end
    end)
end)

-- === Commands (unchanged) ===================================================
RegisterCommand(Config.AdminCommand, function(source)
    local src = source
    local isAdmin = Checkadmin(src)
    if not isAdmin then return end
    TriggerClientEvent("midnight-redeem:openAdminMenu", src)
end, false)

RegisterCommand(Config.RedeemCommand, function(source)
    local src = source
    TriggerClientEvent("midnight-redeem:redeemcode", src)
end, false)