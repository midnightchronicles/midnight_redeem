local Bridge = exports['community_bridge']:Bridge()

function NotificationUser(title, description, type)
    Bridge.Notify.SendNotify(description, type, 6000)
end

RegisterNetEvent("midnight-redeem:notifyUser", function(title, description, type)
    NotificationUser(title, description, type)
end)

RegisterCommand("genredeem", function()

    local input = Bridge.Input.Open('Generate Redeem Code', {
        { type = 'input', label = 'Item Name', placeholder = 'e.g. water', required = false },
        { type = 'number', label = 'Item Amount', placeholder = 'e.g. 1', required = false },
        { type = 'number', label = 'Money Amount', placeholder = 'e.g. 500', required = false },
        { type = 'number', label = 'Uses', placeholder = 'e.g. 1', required = true },
        { type = 'number', label = 'Expiry (Days)', placeholder = 'e.g. 1', required = true },
        { type = 'input', label = 'Custom Code', placeholder = 'e.g. foodpack123', required = true }
    })

    if not input then
        print("^1[DEBUG] No input submitted^7")
        return
    end

    print("^2[DEBUG] Input dialog returned^7")

    local itemName = input[1]
    local itemAmount = tonumber(input[2])
    local moneyAmount = tonumber(input[3])
    local uses = tonumber(input[4])
    local expiryDays = tonumber(input[5])
    local customCode = input[6]

    if not customCode or customCode == "" then
        return NotificationUser(nil , 'Custom code is required.', 'error')
    end

    local rewards = {}

    if itemName and itemAmount and itemAmount > 0 then
        table.insert(rewards, { item = itemName, amount = itemAmount })
    end

    if moneyAmount and moneyAmount > 0 then
        table.insert(rewards, { money = true, amount = moneyAmount })
    end

    if #rewards == 0 then
        return NotificationUser(nil , 'You must provide at least an item or a money amount.', 'error')
    end

    print("CLIENT: sending generateCode –", customCode)
    TriggerServerEvent("midnight-redeem:generateCode", json.encode(rewards), uses, expiryDays, customCode)
end, false)

RegisterCommand("redeemcode", function()
    local Bridge = exports['community_bridge']:Bridge()
    local input = Bridge.Input.Open('Redeem Code', {
        { type = 'input', label = 'Enter Redeem Code', placeholder = 'e.g. waterbonus2025', required = true }
    })

    if not input or input[1] == '' then
        return NotificationUser(nil , 'You must enter a redeem code.', 'error')
    end

    local code = input[1]
    print("CLIENT: sending redeemCode –", code)
    TriggerServerEvent("midnight-redeem:redeemCode", code)
end, false)