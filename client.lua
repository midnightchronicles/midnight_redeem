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
    local rewards = {}

    while true do
        local itemInput = Bridge.Input.Open('Add Reward Item', {
            { type = 'input', label = 'Item Name', placeholder = 'e.g. water', required = true },
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
        { type = 'number', label = 'Money Amount', placeholder = 'e.g. 500', required = false },
        { type = 'number', label = 'Uses', placeholder = 'e.g. 1', required = true },
        { type = 'number', label = 'Expiry (Days)', placeholder = 'e.g. 1', required = true },
        { type = 'input', label = 'Custom Code', placeholder = 'e.g. foodpack123', required = true }
    })

    if not finalInput then
        DebugPrint("^1[DEBUG] No input submitted for finalization^7")
        return
    end

    local moneyAmount = tonumber(finalInput[1])
    local uses = tonumber(finalInput[2])
    local expiryDays = tonumber(finalInput[3])
    local customCode = finalInput[4]

    if moneyAmount and moneyAmount > 0 then
        table.insert(rewards, { money = true, amount = moneyAmount })
    end

    if #rewards == 0 then
        return NotificationUser(nil, 'You must provide at least an item or a money amount.', 'error')
    end

    DebugPrint("CLIENT: sending generateCode –", customCode)
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