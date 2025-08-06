local Config = require('config')
local Bridge = exports['community_bridge']:Bridge()

-- Locale loader
local langCode = Config.Language or "en"
local langFile = LoadResourceFile(GetCurrentResourceName(), ("locales/%s.json"):format(langCode))
if not langFile then
    error("[Midnight_Redeem] Could not load language file locales/" .. langCode .. ".json")
end
Lang = json.decode(langFile)
if not Lang then
    error("[Midnight_Redeem] locales/" .. langCode .. ".json exists but is not valid JSON!")
end

-- Safe get lang function (optional)
local function L(key)
    return Lang[key] or ("MISSING_LANG_" .. key)
end

local function DebugPrint(message)
    if Config.Debug then
        print("[Midnight_Redeem] " .. message)
    end
end

function NotificationUser(title, description, type)
    Bridge.Notify.SendNotify(description, type, 6000)
end

RegisterNetEvent("midnight-redeem:notifyUser", function(title, description, type)
    NotificationUser(title, description, type)
end)

RegisterNetEvent("midnight-redeem:openAdminMenu", function()
    lib.callback("midnight-redeem:getAllCodes", false, function(options)
        local main = Bridge.Input.Open(L("ADMIN_MENU_TITLE"), {
            {
                type = 'select',
                label = L("ADMIN_MENU_ACTION_LABEL"),
                options = {
                    { label = L("ADMIN_MENU_ACTION_GENERATE"), value = 'generate' },
                    { label = L("ADMIN_MENU_ACTION_MANAGE"), value = 'manage' }
                },
                required = true
            }
        })

        if not main or not main[1] then return end

        if main[1] == 'generate' then
            local rewards = {}

            while true do
                local itemInput = Bridge.Input.Open(L("ADMIN_ADD_REWARD_ITEM_TITLE"), {
                    { type = 'input', label = L("ADMIN_ADD_REWARD_ITEM_NAME_LABEL"), placeholder = L("ADMIN_ADD_REWARD_ITEM_NAME_PLACEHOLDER"), required = true },
                    { type = 'number', label = L("ADMIN_ADD_REWARD_ITEM_AMOUNT_LABEL"), placeholder = L("ADMIN_ADD_REWARD_ITEM_AMOUNT_PLACEHOLDER"), required = true }
                })

                if not itemInput then break end

                local itemName = itemInput[1]
                local itemAmount = tonumber(itemInput[2])

                if itemName and itemAmount and itemAmount > 0 then
                    table.insert(rewards, { item = itemName, amount = itemAmount })
                else
                    NotificationUser(nil, L("ADMIN_ADD_INVALID_ITEM"), 'error')
                    break
                end

                local choiceInput = Bridge.Input.Open(L("ADMIN_ADD_ANOTHER_ITEM_TITLE"), {
                    {
                        type = 'select',
                        label = L("ADMIN_ADD_ANOTHER_ITEM_LABEL"),
                        options = {
                            { label = L("ADMIN_ADD_ANOTHER_ITEM_YES"), value = 'yes' },
                            { label = L("ADMIN_ADD_ANOTHER_ITEM_NO"), value = 'no' }
                        },
                        required = true
                    }
                })

                if not choiceInput or choiceInput[1] == 'no' then break end
            end

            local finalInput = Bridge.Input.Open(L("ADMIN_FINALIZE_TITLE"), {
                { type = 'input', label = L("ADMIN_FINALIZE_VEHICLE_LABEL"), placeholder = L("ADMIN_FINALIZE_VEHICLE_PLACEHOLDER"), required = false },
                { type = 'number', label = L("ADMIN_FINALIZE_MONEY_LABEL"), placeholder = L("ADMIN_FINALIZE_MONEY_PLACEHOLDER"), required = false },
                { type = 'number', label = L("ADMIN_FINALIZE_USES_LABEL"), placeholder = L("ADMIN_FINALIZE_USES_PLACEHOLDER"), required = true },
                { type = 'number', label = L("ADMIN_FINALIZE_EXPIRY_LABEL"), placeholder = L("ADMIN_FINALIZE_EXPIRY_PLACEHOLDER"), required = true },
                { type = 'input', label = L("ADMIN_FINALIZE_CODE_LABEL"), placeholder = L("ADMIN_FINALIZE_CODE_PLACEHOLDER"), required = true }
            })
            
            if not finalInput then return end
            
            local vehicleName = finalInput[1] ~= "" and finalInput[1] or nil
            local moneyAmount = tonumber(finalInput[2])
            local uses = tonumber(finalInput[3])
            local expiryDays = tonumber(finalInput[4])
            local customCode = finalInput[5]
            
            if moneyAmount and moneyAmount > 0 then
                table.insert(rewards, { money = true, amount = moneyAmount })
            end
            
            if vehicleName then
                table.insert(rewards, { vehicle = true, model = vehicleName })
            end
            
            if #rewards == 0 then
                return NotificationUser(nil, L("ADMIN_REQUIRE_ITEM"), 'error')
            end
            
            TriggerServerEvent("midnight-redeem:generateCode", json.encode(rewards), uses, expiryDays, customCode)

        elseif main[1] == 'manage' then
            lib.callback("midnight-redeem:getAllCodes", false, function(options)
                if not options or #options == 0 then
                    lib.notify({ title = L("ADMIN_NO_CODES"), description = L("ADMIN_NO_CODES"), type = 'error' })
                    return
                end

                local input = Bridge.Input.Open(L("ADMIN_MANAGE_TITLE"), {
                    {
                        type = 'select',
                        label = L("ADMIN_MANAGE_SELECT_LABEL"),
                        options = options,
                        required = true
                    },
                    {
                        type = 'select',
                        label = L("ADMIN_MANAGE_ACTION_LABEL"),
                        options = {
                            { label = L("ADMIN_MANAGE_ACTION_VIEW"), value = 'view' },
                            { label = L("ADMIN_MANAGE_ACTION_DELETE"), value = 'delete' }
                        },
                        required = true
                    }
                })

                if input and input[1] and input[2] then
                    if input[2] == 'view' then
                        TriggerServerEvent("midnight-redeem:adminCheckCode", input[1])
                    elseif input[2] == 'delete' then
                        local confirm = Bridge.Input.Open(L("ADMIN_MANAGE_CONFIRM_DELETE_TITLE"), {
                            {
                                type = 'select',
                                label = L("ADMIN_MANAGE_CONFIRM_DELETE_LABEL"),
                                options = {
                                    { label = L("ADMIN_MANAGE_CONFIRM_DELETE_YES"), value = 'yes' },
                                    { label = L("ADMIN_MANAGE_CONFIRM_DELETE_NO"), value = 'no' }
                                },
                                required = true
                            }
                        })
                        if confirm and confirm[1] == 'yes' then
                            TriggerServerEvent("midnight-redeem:deleteCode", input[1])
                        end
                    end
                end
            end)
        end
    end)
end)

RegisterNetEvent("midnight-redeem:redeemcode", function()
    local input = Bridge.Input.Open(L("REDEEM_TITLE"), {
        { type = 'input', label = L("REDEEM_INPUT_LABEL"), placeholder = L("REDEEM_INPUT_PLACEHOLDER"), required = true },
        {
            type = 'select',
            label = L("REDEEM_MONEY_LABEL"),
            options = {
                { label = L("REDEEM_MONEY_CASH"), value = 'cash' },
                { label = L("REDEEM_MONEY_BANK"), value = 'bank' }
            },
            required = true
        }
    })

    if not input or input[1] == '' then
        return NotificationUser(nil, L("REDEEM_MUST_ENTER"), 'error')
    end

    local code = input[1]
    local moneyOption = input[2]

    DebugPrint("CLIENT: sending redeemCode –", code, " as", moneyOption)
    TriggerServerEvent("midnight-redeem:redeemCode", code, moneyOption)
end)