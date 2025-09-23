local Bridge = exports['community_bridge']:Bridge()

function Debugprint(msg)
    if Config.Debug then
        print("[midnight_redeem] " .. msg)
    end
end

function Checkadmin(src)
    if not Bridge.Framework.GetIsFrameworkAdmin(src) then return false, Bridge.Notify.SendNotify(src, locales("NOTIFY_PERMISSION_DENIED"), "error", 6000) end
    return true
end

local json_decode = json.decode
local json_encode = json.encode
local fmt = string.format
local insert = table.insert
local concat = table.concat

local function iso_to_unix(iso)
    if type(iso) ~= "string" or #iso < 19 then return nil end
    local y, mo, d, h, mi, s = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d):(%d%d)$")
    y, mo, d, h, mi, s = tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi), tonumber(s)
    if not y then return nil end
    return os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s })
end

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

function HandleRedeemCode(source, itemsJson, uses, expiryFlexible, customCode, perUserLimit, createdByOverride)
    local hasPlayer = (type(source) == "number" and source > 0)
    local playerName = createdByOverride
                      or (hasPlayer and (GetPlayerName(source) or "ingame moderator"))
                      or "discord admin"

    local ok, itemsTable = pcall(json_decode, itemsJson)
    if not ok or type(itemsTable) ~= "table" then
        if hasPlayer then
            return Bridge.Notify.SendNotify(source, locales("NOTIFY_INVALID_ITEM_DATA"), "error", 6000)
        else
            Debugprint("[midnight_redeem] Invalid item data for code creation.")
            return
        end
    end

    uses = tonumber(uses)
    if not uses or uses <= 0 then
        if hasPlayer then
            return Bridge.Notify.SendNotify(source, locales("NOTIFY_INVALID_USES"), "error", 6000)
        else
            Debugprint("[midnight_redeem] Invalid uses for code creation.")
            return
        end
    end

    local expiryDate = parse_expiry_flexible(expiryFlexible)
    local expiryRawUnix = nil
    do
        local days = tonumber(expiryFlexible)
        if days ~= nil then
            if days > 0 then
                expiryRawUnix = os.time() + (days * 86400)
            else
                expiryRawUnix = nil
            end
        else
            local ts = iso_to_unix(expiryDate or expiryFlexible)
            ts = ts and tonumber(ts) or nil
            if ts and ts > 9999999999 then ts = math.floor(ts / 1000) end
            expiryRawUnix = ts
        end
    end

    if expiryRawUnix and expiryRawUnix <= os.time() then
        local msg = (locales and (locales("NOTIFY_EXPIRY_IN_PAST") or nil)) or "The expiry date/time is already in the past."
        if hasPlayer then
            return Bridge.Notify.SendNotify(source, msg, "error", 6000)
        else
            Debugprint("[midnight_redeem] " .. msg)
            return
        end
    end

    perUserLimit = tonumber(perUserLimit)
    if perUserLimit == nil or perUserLimit < 0 then perUserLimit = 1 end

    local rewards = (type(itemsTable[1]) == "table") and itemsTable or { itemsTable }

    local totalItemCount = 0
    for _, reward in ipairs(rewards) do
        if reward.item then
            totalItemCount = totalItemCount + (tonumber(reward.amount) or 0)
        end
    end

    local insertId = MySQL.insert.await(
        'INSERT INTO midnight_codes (code, total_item_count, items, uses, created_by, expiry, redeemed_by, expired_notified, per_user_limit) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?)',
        { customCode, totalItemCount, itemsJson, uses, playerName, expiryDate, json_encode({}), perUserLimit }
    )

    if insertId then
        if hasPlayer then
            TriggerClientEvent("midnight-redeem:notifyUser", source, locales("NOTIFY_CODE_CREATED"), locales("NOTIFY_CODE_CREATED"), "success")
        end

        local _, rewardText = build_reward_lines(rewards)

        local expiryHuman
        if not expiryRawUnix then
            expiryHuman = "Never"
        else
            local ts = math.floor(expiryRawUnix)
            expiryHuman = "<t:" .. ts .. ":f> (<t:" .. ts .. ":R>)"
        end

        local perUserHuman = (perUserLimit == 0) and "Unlimited" or tostring(perUserLimit)

        local message = string.format(
            "**Admin:** `%s`\n**Code:** `%s`\n**Uses:** `%s`\n**Per-User Limit:** `%s`\n**Expiry:** %s\n\n**Rewards:**\n%s",
            playerName, customCode, uses, perUserHuman, expiryHuman, rewardText
        )

        SendToDiscord("Redeem Code Created", message, 3066993)
        local dbgExpiry = expiryDate or "Never"
        local dbgUnix   = expiryRawUnix and tostring(expiryRawUnix) or "nil"
        local dbgRewards = (rewardText or "None"):gsub("\n", " | ")
        Debugprint(("[CreateCode] insertId=%s code='%s' uses=%d perUser=%s expiry='%s' (unix=%s) created_by='%s' totalItems=%d rewards=[%s]")
            :format(tostring(insertId), tostring(customCode), tonumber(uses) or 0, tostring(perUserLimit),
                    dbgExpiry, dbgUnix, tostring(playerName), tonumber(totalItemCount) or 0, dbgRewards))

    else
        if hasPlayer then
            Bridge.Notify.SendNotify(source, locales("NOTIFY_FAILED_INSERT"), "error", 6000)
        else
            Debugprint("[midnight_redeem] Failed to insert daily/system code.")
        end
    end
end

RegisterServerEvent("midnight-redeem:generateCode", function(itemsJson, uses, expiryDays, customCode, perUserLimit)
    HandleRedeemCode(source, itemsJson, uses, expiryDays, customCode, perUserLimit)
end)

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

local function handleCodeRedemption(src, code, option)
    local uniqueId  = Bridge.Framework.GetPlayerIdentifier(src)
    local playerName= GetPlayerName(src)

    local row = (MySQL.query.await(
        'SELECT items, per_user_limit, redeemed_by FROM midnight_codes WHERE code = ? AND (expiry IS NULL OR expiry > NOW()) LIMIT 1',
        { code }
    ) or {})[1]

    if not row then
        return Bridge.Notify.SendNotify(src, locales("NOTIFY_INVALID_OR_EXPIRED"), "error", 6000)
    end

    local items = safe_json_decode(row.items, {})
    local jsonPath = '$."' .. uniqueId .. '"'

    local affected = MySQL.update.await([[
        UPDATE midnight_codes
           SET uses = uses - 1,
               redeemed_by = JSON_SET(
                   CASE
                       WHEN redeemed_by IS NULL
                            OR JSON_VALID(redeemed_by) = 0
                            OR JSON_TYPE(redeemed_by) <> 'OBJECT'
                       THEN JSON_OBJECT()
                       ELSE redeemed_by
                   END,
                   ?,  -- path
                   COALESCE(
                       CAST(
                           JSON_UNQUOTE(
                               JSON_EXTRACT(
                                   CASE
                                       WHEN redeemed_by IS NULL
                                            OR JSON_VALID(redeemed_by) = 0
                                            OR JSON_TYPE(redeemed_by) <> 'OBJECT'
                                       THEN JSON_OBJECT()
                                       ELSE redeemed_by
                                   END,
                                   ?
                               )
                           ) AS UNSIGNED
                       ),
                       0
                   ) + 1
               )
         WHERE code = ?
           AND (expiry IS NULL OR expiry > NOW())
           AND uses > 0
           AND (
                 per_user_limit = 0
                 OR COALESCE(
                        CAST(
                            JSON_UNQUOTE(
                                JSON_EXTRACT(
                                    CASE
                                        WHEN redeemed_by IS NULL
                                             OR JSON_VALID(redeemed_by) = 0
                                             OR JSON_TYPE(redeemed_by) <> 'OBJECT'
                                    THEN JSON_OBJECT()
                                    ELSE redeemed_by
                                    END,
                                    ?
                                )
                            ) AS UNSIGNED
                        ),
                        0
                    ) < per_user_limit
               )
    ]], { jsonPath, jsonPath, code, jsonPath })

    if (affected or 0) <= 0 then
        local curCount, limit = 0, 1
        if row then
            limit = tonumber(row.per_user_limit or 1) or 1
            if row.redeemed_by then
                local okJ, parsed = pcall(json.decode, row.redeemed_by)
                if okJ and type(parsed) == "table" then
                    local v = parsed[uniqueId]
                    if type(v) == "number" then curCount = v end
                end
            end
        end
        if limit > 0 and curCount >= limit then
            return Bridge.Notify.SendNotify(src, (locales("NOTIFY_PER_USER_LIMIT_REACHED") or "You have reached the per-user redemption limit for this code."), "error", 6000)
        end
        return Bridge.Notify.SendNotify(src, (locales("NOTIFY_ALREADY_REDEEMED") or "You have already redeemed this code."), "error", 6000)
    end

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

    local infoRow = (MySQL.query.await(
        'SELECT per_user_limit, redeemed_by, uses, expiry FROM midnight_codes WHERE code = ? LIMIT 1',
        { code }
    ) or {})[1]

    local perUserLeftText, usesLeftText, expiryText = "N/A", "N/A", "Never"
    if infoRow then
        local limitVal = tonumber(infoRow.per_user_limit or 0) or 0
        local used = 0
        if infoRow.redeemed_by then
            local okJ, parsed = pcall(json.decode, infoRow.redeemed_by)
            if okJ and type(parsed) == "table" then
                local v = parsed[uniqueId]
                if type(v) == "number" then used = v end
            end
        end
        if limitVal == 0 then
            perUserLeftText = "Unlimited"
        else
            local left = math.max(limitVal - used, 0)
            perUserLeftText = string.format("%d left (used %d/%d)", left, used, limitVal)
        end

        local usesLeft = tonumber(infoRow.uses)
        if usesLeft ~= nil then
            usesLeftText = tostring(usesLeft)
        end

        local ts
        local e = infoRow.expiry
        if e ~= nil then
            local et = type(e)
            if et == "string" then
                ts = iso_to_unix(e)
                if not ts then
                    local y, mo, d, h, mi = e:match("^(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d)$")
                    if y then
                        ts = os.time({
                            year = tonumber(y), month = tonumber(mo), day = tonumber(d),
                            hour = tonumber(h), min = tonumber(mi), sec = 0
                        })
                    end
                end
            elseif et == "number" then
                ts = (e > 1e12) and math.floor(e / 1000) or e
            elseif et == "table" then
                if e.year and e.month and e.day then
                    ts = os.time({
                        year = tonumber(e.year), month = tonumber(e.month), day = tonumber(e.day),
                        hour = tonumber(e.hour or 0), min = tonumber(e.min or 0), sec = tonumber(e.sec or 0)
                    })
                end
            end
        end

        if ts and ts > 0 then
            expiryText = "<t:" .. tostring(ts) .. ":f> (<t:" .. tostring(ts) .. ":R>)"
        else
            expiryText = "Never"
        end
    end

    local PlayerName = playerName or "N/A"
    local Code = code or "N/A"
    local Summary = (#receivedSummary > 0 and table.concat(receivedSummary, "\n")) or "N/A"
    local UniqueId = uniqueId or "N/A"

    local message = ("**Redeemed By:** `%s`\n**Code:** `%s`\n**Uses Left:** `%s`\n**User limit Remaining:** %s\n**Expiry:** %s\n**Rewards:**\n%s\n**Identifiers:**\n- UniqueID: `%s`")
        :format(PlayerName, Code, usesLeftText, perUserLeftText, expiryText, Summary, UniqueId)
    SendToDiscord("Code Redeemed", message, 15844367)
end

RegisterServerEvent("midnight-redeem:redeemCode", function(code, option)
    handleCodeRedemption(source, code, option)
end)

exports('GenerateRedeemCode', function(source, itemsJson, uses, expiryDays, customCode, perUserLimit)
    HandleRedeemCode(source, itemsJson, uses, expiryDays, customCode, perUserLimit)
end)

RegisterServerEvent("zdiscord:generateRedeemCode", function(itemsJson, uses, expiryFlexible, customCode, perUserLimit)
        if source ~= 0 then
            local invoker = GetInvokingResource()
            if invoker ~= "zdiscord" then
                return
            end
        end
    
        local usesNum = tonumber(uses)
        local expArg  = tonumber(expiryFlexible) or expiryFlexible
        local perUser = tonumber(perUserLimit)
    
        if itemsJson and usesNum and expArg ~= nil and customCode then
            exports["midnight_redeem"]:GenerateRedeemCode(0, itemsJson, usesNum, expArg, customCode, perUser)
            Debugprint(("Generated redeem code via zdiscord: uses=%s expiry=%s code=%s perUser=%s"):format(uses, tostring(expArg), customCode, tostring(perUser)))
        else
            Debugprint("[zdiscord] Invalid arguments for GenerateRedeemCode.")
        end
    end)

lib.callback.register("midnight-redeem:getAllCodes", function(src)
    local src = source
    local results = exports.oxmysql:executeSync("SELECT code FROM midnight_codes")
    local options = {}
    for _, row in ipairs(results or {}) do
        table.insert(options, { label = row.code, value = row.code })
    end
    return options
end)

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

lib.callback.register("midnight-redeem:getCodeDetails", function(src, code)
    local result = exports.oxmysql:executeSync('SELECT code, uses, expiry, items, per_user_limit FROM midnight_codes WHERE code = ?', { code })
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
        items = itemsTbl,
        per_user_limit = row.per_user_limit
    }
end)

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
    local newPerUser = cur.per_user_limit
    if payload.perUserLimit ~= nil then
        local p = tonumber(payload.perUserLimit)
        if p and p >= 0 then newPerUser = p end
    end

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
        SET code = ?, items = ?, uses = ?, expiry = ?, total_item_count = ?, per_user_limit = ?
        WHERE code = ?
    ]]

    exports.oxmysql:execute(q, { newCode, newItemsJson, newUses, newExpiry, totalItemCount, newPerUser, cur.code }, function(affected)
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

local function _parseDailyReward(entry)
    if type(entry) == "table" then
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
                return { item = item, amount = amt }
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

function CreateDailyCode()
    if not (Config and Config.DailyRewardEnabled) then
        Debugprint("[midnight_redeem] Daily code generation disabled (Config.DailyRewardEnabled = false).")
        return
    end

    local usesNum       = tonumber(Config.DailyRewarduses) or 1
    local perUserLimit  = tonumber(Config.DailyRewardperuserlimit) or 1
    local hoursNum      = tonumber(Config.DailyRewardhours) or 6

    if usesNum <= 0 or perUserLimit < 0 or hoursNum <= 0 then
        Debugprint("[midnight_redeem] Daily code skipped: invalid Config values (uses/perUserLimit/hours).")
        return
    end

    local pickedReward = nil
    if type(Config.DailyRewards) == "table" and #Config.DailyRewards > 0 then
        local candidates = {}
        for _, e in ipairs(Config.DailyRewards) do
            local r = _parseDailyReward(e)
            if r then table.insert(candidates, r) end
        end
        if #candidates > 0 then
            local seedExtra = (GetGameTimer and GetGameTimer() or 0)
            math.randomseed(os.time() + seedExtra)
            pickedReward = candidates[math.random(#candidates)]
        end
    end

    if not pickedReward then
        local rewardName = tostring(Config.DailyRewardItem or "cash")
        local amountNum  = tonumber(Config.DailyRewardamount) or 0
        if amountNum <= 0 then
            Debugprint("[midnight_redeem] Daily code skipped: no valid reward in Config.DailyRewards and fallback amount <= 0.")
            return
        end
        local rn = rewardName:lower()
        if rn == "cash" or rn == "bank" then
            pickedReward = { money = true, amount = amountNum, option = rn }
        else
            pickedReward = { item = rewardName, amount = amountNum }
        end
    end

    local itemsJson = json.encode({ pickedReward })

    local expiryAbs = os.date("%Y-%m-%d %H:%M:%S", os.time() + (hoursNum * 3600))

    local function _randCode(len)
        local chars = "AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz123456789"
        local out = {}
        for i = 1, len do
            local idx = math.random(#chars)
            out[i] = chars:sub(idx, idx)
        end
        return table.concat(out)
    end

    local seedExtra = (GetGameTimer and GetGameTimer() or 0)
    math.randomseed(os.time() + seedExtra)

    local code
    for _ = 1, 10 do
        local candidate = ("D-%s-%s-%s"):format(todayKey, slotKey, _randCode(6))
        local exists = MySQL.query.await('SELECT code FROM midnight_codes WHERE code = ? LIMIT 1', { candidate })
        if not (exists and exists[1]) then
            code = candidate
            break
        end
    end
    if not code then
        code = ("D-%s-%s-%06d"):format(todayKey, slotKey, math.random(0, 999999))
    end

    HandleRedeemCode(0, itemsJson, usesNum, expiryAbs, code, perUserLimit, "Daily Code")

    local expiryTs = (iso_to_unix and iso_to_unix(expiryAbs)) or (os.time() + (tonumber(Config.DailyRewardhours) or 0) * 3600)
    local expiry   = expiryTs and (("<t:%d:f> (<t:%d:R>)"):format(expiryTs, expiryTs)) or "Never"
    local codeFmt  = ("`%s`"):format(code)

    SendToDiscord("🎁 Daily Reward Code", "Use this code today:", 3447003, {
        fields = {
            { name = "Redeem Code", value = codeFmt, inline = false },
            { name = "Expiry",      value = expiry,  inline = false },
        }
    }, "daily")
end

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