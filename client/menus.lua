local function confirmDeleteMenu(selectedCode)
    if type(selectedCode) == "table" then
        selectedCode = selectedCode.value or selectedCode.label
    end
    selectedCode = tostring(selectedCode or ""):match("^%s*(.-)%s*$")
    if selectedCode == "" then
        return NotificationUser(nil, locales("NOTIFY_CODE_NOT_FOUND") or "No code selected.", 'error')
    end

    local confirm = Bridge.Input.Open(locales("ADMIN_MANAGE_CONFIRM_DELETE_TITLE"), {
        {
            type = 'select',
            label = (locales("ADMIN_MANAGE_CONFIRM_DELETE_LABEL") or "Delete this code?")
                .. (" [%s]"):format(selectedCode),
            options = {
                { label = locales("ADMIN_MANAGE_CONFIRM_DELETE_YES"), value = 'yes' },
                { label = locales("ADMIN_MANAGE_CONFIRM_DELETE_NO"),  value = 'no' }
            },
            required = true
        }
    })

    if confirm and confirm[1] == 'yes' then
        TriggerServerEvent("midnight-redeem:deleteCode", selectedCode)
    end
end

local function manageAdminMenu()
    lib.callback("midnight-redeem:getAllCodes", false, function(redeemCodes)
        local count = (type(redeemCodes) == "table" and #redeemCodes) or 0
        if count == 0 then
            return NotificationUser(nil, locales("ADMIN_NO_CODES") or "No redeem codes found.", 'error')
        end

        local options = {
            {
                type = 'select',
                label = locales("ADMIN_MANAGE_SELECT_LABEL"),
                options = redeemCodes,
                required = true
            },
            {
                type = 'select',
                label = locales("ADMIN_MANAGE_ACTION_LABEL"),
                options = {
                    { label = locales("ADMIN_MANAGE_ACTION_VIEW"),   value = 'view' },
                    { label = locales("ADMIN_MANAGE_ACTION_DELETE"), value = 'delete' }
                },
                required = true
            }
        }

        local inputOption = Bridge.Input.Open(locales("ADMIN_MANAGE_TITLE"), options)
        if not inputOption or not inputOption[1] or not inputOption[2] then return end

        local selectedCode = inputOption[1]
        if type(selectedCode) == "table" then
            selectedCode = selectedCode.value or selectedCode.label
        end
        selectedCode = tostring(selectedCode or ""):match("^%s*(.-)%s*$")
        if selectedCode == "" then
            return NotificationUser(nil, locales("NOTIFY_CODE_NOT_FOUND") or "No code selected.", 'error')
        end

        if inputOption[2] == 'view' then
            TriggerServerEvent("midnight-redeem:adminCheckCode", selectedCode)
        elseif inputOption[2] == 'delete' then
            confirmDeleteMenu(selectedCode)
        end
    end)
end

local function generateCodeSubMenu(rewards)
    local choiceInput = Bridge.Input.Open(locales("ADMIN_ADD_ANOTHER_ITEM_TITLE"), {
        {
            type = 'select',
            label = locales("ADMIN_ADD_ANOTHER_ITEM_LABEL"),
            options = {
                { label = locales("ADMIN_ADD_ANOTHER_ITEM_YES"), value = 'yes' },
                { label = locales("ADMIN_ADD_ANOTHER_ITEM_NO"),  value = 'no' }
            },
            required = true
        }
    })

    if not choiceInput then return end
    if choiceInput[1] == 'yes' then
        return generateCodeMenu(rewards)
    end

    local finalInput = Bridge.Input.Open(locales("ADMIN_FINALIZE_TITLE"), {
        { type = 'input',  label = locales("ADMIN_FINALIZE_VEHICLE_LABEL"), placeholder = locales("ADMIN_FINALIZE_VEHICLE_PLACEHOLDER"), required = false },
        { type = 'number', label = locales("ADMIN_FINALIZE_MONEY_LABEL"),   placeholder = locales("ADMIN_FINALIZE_MONEY_PLACEHOLDER"),   required = false },
        { type = 'number', label = locales("ADMIN_FINALIZE_USES_LABEL"),    placeholder = locales("ADMIN_FINALIZE_USES_PLACEHOLDER"),    required = true },
        { type = 'number', label = locales("ADMIN_FINALIZE_EXPIRY_LABEL"),  placeholder = locales("ADMIN_FINALIZE_EXPIRY_PLACEHOLDER"),  required = true },
        { type = 'input',  label = locales("ADMIN_FINALIZE_CODE_LABEL"),    placeholder = locales("ADMIN_FINALIZE_CODE_PLACEHOLDER"),    required = true }
    })

    if not finalInput then return end

    local vehicleName = finalInput[1] ~= "" and finalInput[1] or nil
    local moneyAmount = tonumber(finalInput[2])

    if moneyAmount and moneyAmount > 0 then
        table.insert(rewards, { money = true, amount = moneyAmount })
    end
    if vehicleName then
        table.insert(rewards, { vehicle = true, model = vehicleName })
    end

    if #rewards == 0 then
        return NotificationUser(nil, locales("ADMIN_REQUIRE_ITEM"), 'error')
    end

    TriggerServerEvent(
        "midnight-redeem:generateCode",
        json.encode(rewards),
        tonumber(finalInput[3]),
        tonumber(finalInput[4]),
        finalInput[5]
    )
end

function generateCodeMenu(passedRewards)
    local rewards = passedRewards or {}
    local itemInput = Bridge.Input.Open(locales("ADMIN_ADD_REWARD_ITEM_TITLE"), {
        {
            type = 'input',
            label = locales("ADMIN_ADD_REWARD_ITEM_NAME_LABEL"),
            placeholder = locales("ADMIN_ADD_REWARD_ITEM_NAME_PLACEHOLDER"),
            required = true
        },
        {
            type = 'number',
            label = locales("ADMIN_ADD_REWARD_ITEM_AMOUNT_LABEL"),
            placeholder = locales("ADMIN_ADD_REWARD_ITEM_AMOUNT_PLACEHOLDER"),
            required = true
        }
    })

    if not itemInput then return end

    local itemName   = itemInput[1]
    local itemAmount = tonumber(itemInput[2])

    if itemName and itemAmount and itemAmount > 0 then
        table.insert(rewards, { item = itemName, amount = itemAmount })
    else
        NotificationUser(nil, locales("ADMIN_ADD_INVALID_ITEM"), 'error')
        return generateCodeMenu(rewards)
    end

    generateCodeSubMenu(rewards)
end

function RegisterCodeMenus()
    local main = Bridge.Input.Open(locales("ADMIN_MENU_TITLE"), {
        {
            type = 'select',
            label = locales("ADMIN_MENU_ACTION_LABEL"),
            options = {
                { label = locales("ADMIN_MENU_ACTION_GENERATE"), value = 'generate' },
                { label = locales("ADMIN_MENU_ACTION_MANAGE"),   value = 'manage' }
            },
            required = true
        }
    })

    if not main or not main[1] then return end

    if main[1] == 'generate' then
        generateCodeMenu()
    elseif main[1] == 'manage' then
        manageAdminMenu()
    end
end

function RegisterRedeemMenu()
    local input = Bridge.Input.Open(locales("REDEEM_TITLE"), {
        { type = 'input', label = locales("REDEEM_INPUT_LABEL"), placeholder = locales("REDEEM_INPUT_PLACEHOLDER"), required = true },
        {
            type = 'select',
            label = locales("REDEEM_MONEY_LABEL"),
            options = {
                { label = locales("REDEEM_MONEY_CASH"), value = 'cash' },
                { label = locales("REDEEM_MONEY_BANK"), value = 'bank' }
            },
            required = true
        }
    })

    if not input or input[1] == '' then
        return NotificationUser(nil, locales("REDEEM_MUST_ENTER"), 'error')
    end

    TriggerServerEvent("midnight-redeem:redeemCode", input[1], input[2])
end