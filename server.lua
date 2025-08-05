local Config = require('config')
local Bridge = exports['community_bridge']:Bridge()
if Config.Framework == "qb" and QBCore == nil then
    QBCore = exports['qb-core']:GetCoreObject()
elseif Config.Framework == "esx" and ESX == nil then
    TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
end

local webhookUrl = ''

local function versionCheck(resource, repository, paid)
    local currentVersion = GetResourceMetadata(resource, 'version', 0)
    if not currentVersion then
        print("^4Please contact ^0[^5Midnight Chronicles^0]^4 for support and reference this error:^0 ".."^3SS_Util.VersionCheck^0, ^1Can't find current resource version for '%s'^0[^3"..resource.."^0]")
        return
    end

    SetTimeout(1000, function()
        PerformHttpRequest(('https://api.github.com/repos/%s/releases/latest'):format(repository), function(status, response)
            if status ~= 200 then
                if status == 403 or status == 429 then
                    print("[^1Update check failed for^0] [^3"..resource.."^0] [^3Git API Limitations^0]\n[^4You may still get this error for a while when restarting the script or server.^0]")
                else
                    print("[^3RUN^0] [^1ERROR^0] [^4Reference^0] [^3VersionCheck^0]\n[^1Check^0] [^3"..repository.."^0] [^4Status^0] [^3"..status.."^0]")
                end
                return
            end

            response = json.decode(response)
            if response.prerelease then return end

            local latestVersion = response.tag_name:match('%d+%.%d+%.%d+') or response.tag_name:match('%d+%.%d+')
            if not latestVersion then
                return
            elseif latestVersion == currentVersion then
                print("[^5midnight_redeem^0] [^2Is up to date^0] [^4Your version^0] [^3"..currentVersion.."^0] [^4Latest Version^0] [^3"..latestVersion.."^0]")
            else
                local cv = { string.strsplit('.', currentVersion) }
                local lv = { string.strsplit('.', latestVersion) }

                local maxParts = math.min(#cv, #lv)
                for i = 1, maxParts do
                    local current, minimum = tonumber(cv[i] or 0), tonumber(lv[i] or 0)
                    if i == maxParts then
                        if (#cv > i and current == minimum and tonumber(cv[i+1] or 0) > tonumber(lv[i+1] or 0)) or (#cv >= i and current > minimum) then
                            if paid then
                                print("[^5midnight_redeem^0] [^4is newer than expected^0] [^4Your version^0] [^3"..currentVersion.."^0] [^4Latest Version^0] [^3"..latestVersion.."^0]\n[^1Please downgrade to latest release for^0] [^3"..resource.."^0] [^1through the cfx portal]")
                                break
                            else
                                print("[^5midnight_redeem^0] [^4is newer than expected^0] [^4Your version^0] [^3"..currentVersion.."^0] [^4Latest Version^0] [^3"..latestVersion.."^0]\n[^1Please downgrade to latest release here: https://github.com/midnightchronicles/midnight_redeem^0]")
                                break
                            end
                        end
                    end
                    if current ~= minimum then
                        if current < minimum then
                            if not paid then
                                print("[^5midnight_redeem^0] [^4is outdated^0] [^4Your version^0] [^3"..currentVersion.."^0] [^4Latest Version^0] [^3"..latestVersion.."^0]\n[^1Please update^0] [^3"..resource.."^0] [^1here:^0]\n[^5https://github.com/midnightchronicles/midnight_redeem^0]")
                                break
                            else
                                print("[^5midnight_redeem^0] [^4is outdated^0] [^4Your version^0] [^3"..currentVersion.."^0] [^4Latest Version^0] [^3"..latestVersion.."^0]\n[^1Please update^0] [^3"..resource.."^0] [^1through the cfx portal^0]")
                                break
                            end
                        end
                    end
                end
            end
        end, 'GET')
    end)
end

function DebugPrint(message)
    if Config.Debug then
        print("[Midnight_Redeem] " .. message)
    end
end

function SendToDiscord(title, message, color, extraFields)
    if not webhookUrl or webhookUrl == "" then
        return DebugPrint("^1[Discord Webhook] No webhook URL defined.^7")
    end

    local embed = {
        {
            ["title"] = title,
            ["description"] = message,
            ["color"] = color or 16777215,
            ["footer"] = { ["text"] = "Midnight Redeem System" },
            ["timestamp"] = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time())
        }
    }

    if extraFields and type(extraFields) == "table" then
        for k, v in pairs(extraFields) do
            embed[1][k] = v
        end
    end

    PerformHttpRequest(webhookUrl, function(err, text, headers)
        if err ~= 204 then
            DebugPrint(string.format("^1[Discord Webhook] Failed to send message. HTTP %s | Response: %s^7", tostring(err), tostring(text)))
        end
    end, 'POST', json.encode({ embeds = embed }), { ['Content-Type'] = 'application/json' })
end

function checkadmin(source)
    if source ~= 0 and source ~= -1 and not Bridge.Framework.GetIsFrameworkAdmin(source) then
        return Bridge.Notify.SendNotify(source, "You do not have permission to use this command.", "error", 6000)
    end
end

RegisterServerEvent("Midnight_redeem:checkadmin", function()
    local src = source
    checkadmin(src)
end)

local function CheckExpiredUnusedCodes()
    local today = os.date("%Y-%m-%d", os.time())
    exports.oxmysql:execute(
        'SELECT * FROM midnight_codes WHERE expiry IS NOT NULL AND expiry <= ? AND uses > 0',
        { today },
        function(results)
            if results and #results > 0 then
                for _, row in ipairs(results) do
                    local items = {}
                    local success, decoded = pcall(json.decode, row.items or "[]")
                    if success and type(decoded) == "table" then
                        items = decoded
                    end

                    local rewardLines = {}
                    for _, reward in ipairs(items) do
                        if reward.item then
                            table.insert(rewardLines, string.format("• %dx %s", reward.amount or 1, reward.item))
                        elseif reward.money then
                            table.insert(rewardLines, string.format("• $%s (%s)", reward.amount or 0, reward.option or "cash"))
                        elseif reward.vehicle then
                            table.insert(rewardLines, string.format("• Vehicle: %s", reward.model or "Unknown"))
                        end
                    end
                    local rewardText = #rewardLines > 0 and table.concat(rewardLines, "\n") or "None"

                    local expiryDisplay = "Never"
                    if row.expiry and type(row.expiry) == "string" and #row.expiry > 0 then
                        expiryDisplay = row.expiry
                    end

                    local msg = string.format(
                        "**Code:** `%s`\n**Expiry:** `%s`\n**Uses Left:** `%s`\n\n**Rewards:**\n%s\n\n*This code expired today without being fully used!*",
                        row.code, expiryDisplay, row.uses, rewardText
                    )
                    SendToDiscord("Code Expired & Unused", msg, 15158332)
                end
            else
                SendToDiscord("Code Expiry Check", "No codes expired today.", 3066993)
            end
        end
    )
end

AddEventHandler('onResourceStart', function(resource)
    if resource == "midnight_redeem" then
        versionCheck(resource,"midnightchronicles/midnight_redeem",false)
        CheckExpiredUnusedCodes()
    end
end)

function GenerateRedeemCode(source, itemsJson, uses, expiryDays, customCode)

    local playerName = GetPlayerName(source) or "discord admin"
    local identifiers = GetPlayerIdentifiers(source)
    local identifierMap = {}

    for _, id in ipairs(identifiers) do
        if id:find("license:") then
            identifierMap.license = id
        elseif id:find("license2:") then
            identifierMap.license2 = id
        elseif id:find("discord:") then
            identifierMap.discord = id:gsub("discord:", "")
        elseif id:find("steam:") then
            identifierMap.steam = id
        end
    end

    local cfxId = identifierMap.license or "N/A"
    local discordId = identifierMap.discord or "N/A"
    local steamId = identifierMap.steam or "N/A"

    local success, itemsTable = pcall(json.decode, itemsJson)
    if not success or type(itemsTable) ~= "table" then
        return Bridge.Notify.SendNotify(source, "Invalid item data.", "error", 6000)
    end

    uses = tonumber(uses)
    expiryDays = tonumber(expiryDays)
    if not uses or uses <= 0 then return Bridge.Notify.SendNotify(source, "Invalid uses.", "error", 6000) end
    if not expiryDays or expiryDays < 0 then expiryDays = 0 end

    local expiryDate = expiryDays > 0 and os.date("%Y-%m-%d %H:%M:%S", os.time() + (expiryDays * 86400)) or nil

    local function isArray(t)
        if type(t) ~= "table" then return false end
        for k in pairs(t) do if type(k) ~= "number" then return false end end
        return true
    end

    local rewards = isArray(itemsTable) and itemsTable or { itemsTable }

    local totalItemCount = 0
    for _, reward in ipairs(rewards) do
        if reward.item then totalItemCount = totalItemCount + (tonumber(reward.amount) or 0) end
    end

    exports.oxmysql:execute(
        'INSERT INTO midnight_codes (code, total_item_count, items, uses, created_by, expiry, redeemed_by) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { customCode, totalItemCount, itemsJson, uses, playerName, expiryDate, json.encode({}) },
        function(rowsChanged)
            local affected = type(rowsChanged) == "table" and rowsChanged.affectedRows or rowsChanged
            if affected and affected > 0 then
                Bridge.Notify.SendNotify(source, "Redeem code created successfully!", "success", 6000)

                local rewardLines = {}
                for _, reward in ipairs(rewards) do
                    if reward.item then
                        table.insert(rewardLines, string.format("• %dx %s", reward.amount or 1, reward.item))
                    elseif reward.money then
                        table.insert(rewardLines, string.format("• $%s (%s)", reward.amount or 0, reward.option or "cash"))
                    elseif reward.vehicle then
                        table.insert(rewardLines, string.format("• Vehicle: %s", reward.model or "Unknown"))
                    end
                end

                local rewardText = table.concat(rewardLines, "\n")

                local message = string.format(
                    "**Admin:** `%s`\n**Code:** `%s`\n**Uses:** `%s`\n**Expiry:** `%s`\n\n**Rewards:**\n%s\n\n**Identifiers:**\n- CFX: `%s`\n- Discord: `%s`\n- Steam: `%s`",
                    playerName, customCode, uses, expiryDate or "Never", rewardText, cfxId, discordId, steamId
                )

                SendToDiscord("Redeem Code Created", message, 3066993)
            else
                Bridge.Notify.SendNotify(source, "Failed to insert code into DB.", "error", 6000)
            end
        end
    )
end

RegisterServerEvent("midnight-redeem:generateCode", function(itemsJson, uses, expiryDays, customCode)
    GenerateRedeemCode(source, itemsJson, uses, expiryDays, customCode)
end)

RegisterServerEvent("midnight-redeem:redeemCode", function(code, option)
    local src = source
    local playerName = GetPlayerName(src)

    local identifiers = GetPlayerIdentifiers(src)
    local identifierMap = {}
    for _, id in ipairs(identifiers) do
        if id:find("license:") then
            identifierMap.license = id
        elseif id:find("license2:") then
            identifierMap.license2 = id
        elseif id:find("discord:") then
            identifierMap.discord = id:gsub("discord:", "")
        elseif id:find("steam:") then
            identifierMap.steam = id
        end
    end

    local identifier = identifierMap.license or identifierMap.license2 or identifierMap.steam or identifierMap.discord or "unknown"
    local playerId = identifier

    function Bridge.Framework.GetPlayerData(source)
        if Config.Framework == "esx" then
            local xPlayer = ESX.GetPlayerFromId(source)
            if xPlayer then
                return {
                    identifier = xPlayer.identifier
                }
            end
        elseif Config.Framework == "qb" then
            local Player = QBCore.Functions.GetPlayer(source)
            if Player then
                return {
                    citizenid = Player.PlayerData.citizenid
                }
            end
        end
        return nil
    end

    exports.oxmysql:execute('SELECT * FROM midnight_codes WHERE code = ? AND (expiry IS NULL OR expiry > NOW())', {
        code
    }, function(result)
        if result[1] then
            local redeemData = result[1]
            local items = json.decode(redeemData.items)
            local remainingUses = redeemData.uses
            local redeemedBy = json.decode(redeemData.redeemed_by) or {}

            if redeemedBy[playerId] then
                return Bridge.Notify.SendNotify(src, "You have already redeemed this code!", "error", 6000)
            end

            if remainingUses <= 0 then
                return Bridge.Notify.SendNotify(src, "This code has already been used the maximum number of times!", "error", 6000)
            end

            local receivedSummary = {}
            local moneyReward = 0
            local accountType = option or "cash"

            for _, reward in ipairs(items) do
                if reward.item then
                    Bridge.Inventory.AddItem(src, reward.item, reward.amount)
                    table.insert(receivedSummary, ("• %dx %s"):format(reward.amount or 1, reward.item))
                elseif reward.money then
                    local account = reward.option or option or "cash"
                    Bridge.Framework.AddAccountBalance(src, account, reward.amount)
                    moneyReward = moneyReward + (tonumber(reward.amount) or 0)
                    accountType = account
                    table.insert(receivedSummary, ("• $%s (%s)"):format(reward.amount or 0, account))
                elseif reward.vehicle then
                    local model = reward.model
                    if model then
                        local plate = string.upper(string.sub(GetPlayerName(src), 1, 3)) .. math.random(1000, 9999)
                        local props = {
                            model = model,
                            plate = plate
                        }

                        local state = 1
                        local garage = "pillbox"

                        local playerData = Bridge.Framework.GetPlayerData(src)

                        if Config.Framework == "esx" then
                            exports.oxmysql:execute('INSERT INTO `owned_vehicles` (owner, plate, vehicle, stored) VALUES (?, ?, ?, ?)', {
                                identifier, plate, json.encode(props), state
                            })
                        elseif Config.Framework == "qb" then
                            exports.oxmysql:execute('INSERT INTO `player_vehicles` (license, citizenid, vehicle, hash, mods, plate, state, garage) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
                                identifier, playerData and playerData.citizenid or "unknown", model, GetHashKey(model), json.encode(props), plate, state, garage
                            })
                        end

                        table.insert(receivedSummary, ("• Vehicle: %s (Plate: %s)"):format(model, plate))
                    end
                end
            end

            local notifyMsg = "successful! You have received:\n" .. table.concat(receivedSummary, "\n")
            TriggerClientEvent("midnight-redeem:notifyUser", src, "Code Redeemed", notifyMsg, "success")

            redeemedBy[playerId] = true
            exports.oxmysql:execute('UPDATE midnight_codes SET uses = ?, redeemed_by = ? WHERE code = ?', {
                remainingUses - 1,
                json.encode(redeemedBy),
                code
            })

            local cfxId = identifierMap.license or "N/A"
            local discordId = identifierMap.discord or "N/A"
            local steamId = identifierMap.steam or "N/A"

            local itemSummary = ""
            for _, item in ipairs(items) do
                local label = item.item or item.model or (item.option or "cash")
                itemSummary = itemSummary .. "- **" .. label .. "** x" .. (item.amount or 1) .. "\n"
            end

            local message = string.format(
                "**Redeemed By:** `%s`\n**Code:** `%s`\n\n**Rewards:**\n`%s`\n\n**Identifiers:**\n- CFX: `%s`\n- Discord: `%s`\n- Steam: `%s`",
                playerName, code, itemSummary, cfxId, discordId, steamId
            )

            SendToDiscord("Code Redeemed", message, 15844367)
        else
            Bridge.Notify.SendNotify(src, "Invalid or expired code!", "error", 6000)
        end
    end)
end)

exports('GenerateRedeemCode', function(source, itemsJson, uses, expiryDays, customCode)
    GenerateRedeemCode(source, itemsJson, uses, expiryDays, customCode)
end)

RegisterServerEvent("zdiscord:generateRedeemCode", function(itemsJson, uses, expiryDays, customCode)
    uses = tonumber(uses)
    expiryDays = tonumber(expiryDays)
    if itemsJson and uses and expiryDays and customCode then
        exports["midnight_redeem"]:GenerateRedeemCode(source, itemsJson, uses, expiryDays, customCode)
        print(("Generated redeem code with rewards %s, uses %s, expiry %s, code %s"):format(itemsJson, uses, expiryDays, customCode))
    else
        print("[zdiscord] Invalid arguments for GenerateRedeemCode.")
    end
end)

lib.callback.register("midnight-redeem:getAllCodes", function(source)
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
            Bridge.Notify.SendNotify(src, info, "info", 15000)
        else
            Bridge.Notify.SendNotify(src, "No code found.", "error", 6000)
        end
    end)
end)

RegisterCommand("checkredeem", function(source)
    checkadmin(source)
    TriggerClientEvent("midnight-redeem:openCodeInput", source)
end, false)