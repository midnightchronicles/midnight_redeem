local Config = require('config')
local Bridge = exports['community_bridge']:Bridge()

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

RegisterCommand(Config.GenerateCommand, function()
    TriggerServerEvent('Midnight_redeem:checkadmin')
    local rewards = {}

    while true do
        local itemInput = Bridge.Input.Open('Add Reward Item', {
            { type = 'input', label = 'Item Name', placeholder = 'press cancel if no item', required = true },
            { type = 'number', label = 'Item Amount', placeholder = 'e.g. 1', required = true }
        })

        if not itemInput then
            DebugPrint("^1[DEBUG] Item input cancelled^7")
            break
        end

        local itemName = itemInput[1]
        local itemAmount = tonumber(itemInput[2])

        if itemName and itemAmount and itemAmount > 0 then
            table.insert(rewards, { item = itemName, amount = itemAmount })
        else
            NotificationUser(nil, 'Invalid item or amount. Please try again.', 'error')
            break
        end

        local choiceInput = Bridge.Input.Open('Add Another Item?', {
            {
                type = 'select',
                label = 'Add another item?',
                options = {
                    { label = 'Yes', value = 'yes' },
                    { label = 'No', value = 'no' }
                },
                required = true
            }
        })

        if not choiceInput then
            DebugPrint("^1[DEBUG] User cancelled selection input^7")
            break
        end

        if choiceInput[1] == 'no' then
            break
        end
    end

    local finalInput = Bridge.Input.Open('Finalize Redeem Code', {
        { type = 'input', label = 'Vehicle Name', placeholder = 'e.g. asbo', required = false },
        { type = 'number', label = 'Money Amount', placeholder = 'e.g. 500', required = false },
        { type = 'number', label = 'Uses', placeholder = 'e.g. 1', required = true },
        { type = 'number', label = 'Expiry (Days)', placeholder = 'e.g. 1', required = true },
        { type = 'input', label = 'Custom Code', placeholder = 'e.g. foodpack123', required = true }
    })
    
    if not finalInput then
        DebugPrint("^1[DEBUG] No input submitted for finalization^7")
        return
    end
    
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
        return NotificationUser(nil, 'You must provide at least an item, money, or vehicle.', 'error')
    end
    
    TriggerServerEvent("midnight-redeem:generateCode", json.encode(rewards), uses, expiryDays, customCode)
end, false)

RegisterCommand(Config.RedeemCommand, function()
    local input = Bridge.Input.Open('Redeem Code', {
        { type = 'input', label = 'Enter Redeem Code', placeholder = 'e.g. waterbonus2025', required = true },
        {
            type = 'select',
            label = 'Receive Money In:',
            options = {
                { label = 'Cash', value = 'cash' },
                { label = 'Bank', value = 'bank' }
            },
            required = true
        }
    })

    if not input or input[1] == '' then
        return NotificationUser(nil , 'You must enter a redeem code.', 'error')
    end

    local code = input[1]
    local moneyOption = input[2]

    DebugPrint("CLIENT: sending redeemCode –", code, " as", moneyOption)
    TriggerServerEvent("midnight-redeem:redeemCode", code, moneyOption)
end, false)

RegisterNetEvent("midnight-redeem:openCodeInput", function()
    lib.callback("midnight-redeem:getAllCodes", false, function(options)
        if not options or #options == 0 then
            lib.notify({ title = 'No codes', description = 'No redeem codes found.', type = 'error' })
            return
        end

        local input = Bridge.Input.Open('Check Redeem Code', {
            {
                type = 'select',
                label = 'Select Redeem Code',
                options = options,
                required = true
            }
        })

        if input and input[1] and input[1] ~= "" then
            TriggerServerEvent("midnight-redeem:adminCheckCode", input[1])
        end
    end)
end)