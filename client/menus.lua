local function _normalizeCode(v)
    if type(v) == "table" then v = v.value or v.label end
    v = tostring(v or ""):match("^%s*(.-)%s*$")
    return v
end

local function _nowUnix()
    if type(os) == "table" and type(os.time) == "function" then
        return os.time()
    end
    if type(GetCloudTimeAsInt) == "function" then
        return GetCloudTimeAsInt()
    end
    return 0
end

local function _expiryToDaysLeft(expiry)
    if not expiry then return 0 end

    local now = _nowUnix()
    if now == 0 then return 0 end

    local ts
    local t = type(expiry)

    if t == "number" then
        ts = (expiry > 1e12) and math.floor(expiry / 1000) or expiry
    elseif t == "string" then
        if #expiry >= 10 then
            if type(os) == "table" and type(os.time) == "function" then
                ts = os.time({
                    year  = tonumber(expiry:sub(1,4)),
                    month = tonumber(expiry:sub(6,7)),
                    day   = tonumber(expiry:sub(9,10)),
                    hour  = tonumber(expiry:sub(12,13)) or 0,
                    min   = tonumber(expiry:sub(15,16)) or 0,
                    sec   = tonumber(expiry:sub(18,19)) or 0
                })
            else
                ts = nil
            end
        end
    end

    if not ts then return 0 end
    local diff = math.floor((ts - now) / 86400)
    return diff > 0 and diff or 0
end

local function _pickExpiryDMY(withTime)
    local modeAns = Bridge.Input.Open(locales("ADMIN_FINALIZE_EXPIRY_LABEL") or "Expiry", {{
        type = 'select',
        label = locales("ADMIN_FINALIZE_EXPIRY_LABEL") or "Expiry",
        options = {
            { label = (locales("NO_EXPIRY") or "No expiry"), value = 'none' },
            { label = (locales("EXPIRY_EXACT_DATETIME") or "Pick date/time"), value = 'exact' },
        },
        required = true
    }})
    if not modeAns then return nil end
    if modeAns[1] == 'none' then return { mode = 'none' } end

    local days = {}
    for d = 1, 31 do
        local s = (d < 10 and ("0"..d) or tostring(d))
        table.insert(days, { label = s, value = s })
    end

    local months = {
        { label = "January",   value = "01" },
        { label = "February",  value = "02" },
        { label = "March",     value = "03" },
        { label = "April",     value = "04" },
        { label = "May",       value = "05" },
        { label = "June",      value = "06" },
        { label = "July",      value = "07" },
        { label = "August",    value = "08" },
        { label = "September", value = "09" },
        { label = "October",   value = "10" },
        { label = "November",  value = "11" },
        { label = "December",  value = "12" }
    }

    local startYear = 2025
    if type(os) == "table" and type(os.date) == "function" then
        startYear = tonumber(os.date("%Y")) or startYear
    end
    if startYear > 2090 then startYear = 2025 end

    local years = {}
    for y = startYear, 2090 do
        table.insert(years, { label = tostring(y), value = tostring(y) })
    end

    local selects = {
        { type = 'select', label = locales("DAY")   or "Day",   options = days,   required = true },
        { type = 'select', label = locales("MONTH") or "Month", options = months, required = true },
        { type = 'select', label = locales("YEAR")  or "Year",  options = years,  required = true },
    }

    if withTime then
        local hours, minutes = {}, {}
        for h = 0, 23 do
            local s = (h < 10 and ("0"..h) or tostring(h))
            table.insert(hours, { label = s, value = s })
        end
        minutes = {
            { label = "00", value = "00" },
            { label = "01", value = "01" },
            { label = "02", value = "02" },
            { label = "03", value = "03" },
            { label = "04", value = "04" },
            { label = "05", value = "05" },
            { label = "06", value = "06" },
            { label = "07", value = "07" },
            { label = "08", value = "08" },
            { label = "09", value = "09" },
            { label = "10", value = "10" },
            { label = "11", value = "11" },
            { label = "12", value = "12" },
            { label = "13", value = "13" },
            { label = "14", value = "14" },
            { label = "15", value = "15" },
            { label = "16", value = "16" },
            { label = "17", value = "17" },
            { label = "18", value = "18" },
            { label = "19", value = "19" },
            { label = "20", value = "20" },
            { label = "21", value = "21" },
            { label = "22", value = "22" },
            { label = "23", value = "23" },
            { label = "24", value = "24" },
            { label = "25", value = "25" },
            { label = "26", value = "26" },
            { label = "27", value = "27" },
            { label = "28", value = "28" },
            { label = "29", value = "29" },
            { label = "30", value = "30" },
            { label = "31", value = "31" },
            { label = "32", value = "32" },
            { label = "33", value = "33" },
            { label = "34", value = "34" },
            { label = "35", value = "35" },
            { label = "36", value = "36" },
            { label = "37", value = "37" },
            { label = "38", value = "38" },
            { label = "39", value = "39" },
            { label = "40", value = "40" },
            { label = "41", value = "41" },
            { label = "42", value = "42" },
            { label = "43", value = "43" },
            { label = "44", value = "44" },
            { label = "45", value = "45" },
            { label = "46", value = "46" },
            { label = "47", value = "47" },
            { label = "48", value = "48" },
            { label = "49", value = "49" },
            { label = "50", value = "50" },
            { label = "51", value = "51" },
            { label = "52", value = "52" },
            { label = "53", value = "53" },
            { label = "54", value = "54" },
            { label = "55", value = "55" },
            { label = "56", value = "56" },
            { label = "57", value = "57" },
            { label = "58", value = "58" },
            { label = "59", value = "59" },
        }
        table.insert(selects, { type = 'select', label = locales("HOUR")   or "Hour",   options = hours,   required = true })
        table.insert(selects, { type = 'select', label = locales("MINUTE") or "Minute", options = minutes, required = true })
    end

    local dt = Bridge.Input.Open(locales("EXPIRY_PICK_EXACT_TITLE") or "Pick exact expiry", selects)
    if not dt then return nil end

    local D, M, Y = dt[1], dt[2], dt[3]
    local H, Min = "00", "00"
    if withTime then
        H, Min = dt[4], dt[5]
    end

    local iso = string.format("%s-%s-%s %s:%s:00", Y, M, D, H, Min)
    return { mode = 'exact', iso = iso }
end

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

local function StartGenerateCodeWizard()
    local choice = Bridge.Input.Open(locales("ADMIN_ADD_ITEM_QUESTION_TITLE") or "Add an item?",
    {{
        type = 'select',
        label = locales("ADMIN_ADD_ITEM_QUESTION_LABEL") or "Do you want to add an item reward?",
        options = {
            { label = locales("GENERIC_YES") or "Yes", value = 'yes' },
            { label = locales("GENERIC_NO")  or "No",  value = 'no'  }
        },
        required = true
    }})

    if not choice then 
        return 
    end

    if choice[1] == 'yes' then
        generateCodeMenu({})
    else
        generateCodeSubMenu({}, true)
    end
end

local function openEditCodeMenu(selectedCode)
    selectedCode = _normalizeCode(selectedCode)
    if selectedCode == "" then
        return NotificationUser(nil, locales("NOTIFY_CODE_NOT_FOUND") or "No code selected.", 'error')
    end

    lib.callback("midnight-redeem:getCodeDetails", false, function(details)
        if not details then
            return NotificationUser(nil, locales("NOTIFY_NO_CODE_FOUND") or "Code not found.", 'error')
        end

        local daysLeft = _expiryToDaysLeft(details.expiry)

        local overwriteQ = Bridge.Input.Open(locales("ADMIN_EDIT_REWARDS_TITLE") or "Edit rewards?", {
            {
                type = 'select',
                label = (locales("ADMIN_EDIT_REWARDS_LABEL") or "Do you want to overwrite rewards?"),
                options = {
                    { label = (locales("GENERIC_YES") or "Yes"), value = 'yes' },
                    { label = (locales("GENERIC_NO")  or "No"),  value = 'no'  }
                },
                required = true
            }
        })
        if not overwriteQ then
            return
        end

        local overwrite = overwriteQ[1] == 'yes'
        if overwrite then
            return startRewardRebuildForEdit(details)
        end

        local meta = Bridge.Input.Open(locales("ADMIN_EDIT_META_TITLE") or "Edit code details", {
            { type = 'number', label = (locales("ADMIN_FINALIZE_USES_LABEL")   or "Uses"),                   placeholder = tostring(details.uses or 0), required = false },
            { type = 'number', label = (locales("ADMIN_FINALIZE_EXPIRY_LABEL") or "Expiry (days)"),          placeholder = tostring(daysLeft or 0),     required = false },
            { type = 'input',  label = (locales("ADMIN_FINALIZE_CODE_LABEL")   or "Code (rename optional)"), placeholder = tostring(details.code or ""), required = false },
            { type = 'number', label = (locales("ADMIN_PER_USER_LIMIT_LABEL")  or "Per-user uses (0 = unlimited)"),
                                placeholder = tostring(details.per_user_limit or 1), required = false },
        })
        if not meta then
            return
        end

        local newUses     = tonumber(meta[1])
        local newExpiry   = tonumber(meta[2])

        local function trim(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end
        local newCodeRaw  = meta[3] or ""
        local newCode     = _normalizeCode(trim(newCodeRaw))

        local newPerUser  = tonumber(meta[4] or details.per_user_limit or 1)

        local minLen2 = tonumber(Config and Config.mincustomchar) or 0
        if newCode ~= "" and minLen2 > 0 then
            local l = (utf8 and utf8.len and utf8.len(newCode)) or #newCode
            if l < minLen2 then
                local msg = (locales and locales("ADMIN_CODE_TOO_SHORT", minLen2))
                            or ("Custom code must be at least " .. minLen2 .. " characters long.")
                NotificationUser(nil, msg, 'error')
                return openEditCodeMenu(selectedCode)
            end
        end

        if newPerUser ~= nil and newPerUser < 0 then
            NotificationUser(nil, (locales("ADMIN_PER_USER_LIMIT_INVALID") or "Per-user uses must be 0 or a positive number."), 'error')
            return openEditCodeMenu(selectedCode)
        end

        TriggerServerEvent("midnight-redeem:updateCode", {
            originalCode = details.code,
            uses         = newUses,
            expiryDays   = newExpiry,
            newCode      = (newCode ~= "" and newCode or nil),
            perUserLimit = newPerUser
        })
    end, selectedCode)
end


function startRewardRebuildForEdit(details)
    return generateCodeMenuEdit(details, {})
end

local function finalizeEditRewards(details, rewards)
    local finalInputPart1 = Bridge.Input.Open(locales("ADMIN_FINALIZE_TITLE"), {
        { type = 'input',  label = locales("ADMIN_FINALIZE_VEHICLE_LABEL"), placeholder = locales("ADMIN_FINALIZE_VEHICLE_PLACEHOLDER"), required = false },
        { type = 'number', label = locales("ADMIN_FINALIZE_MONEY_LABEL"),   placeholder = locales("ADMIN_FINALIZE_MONEY_PLACEHOLDER"),   required = false },
        { type = 'number', label = locales("ADMIN_FINALIZE_USES_LABEL"),    placeholder = tostring(details.uses or 0),                   required = false },
        { type = 'input',  label = locales("ADMIN_FINALIZE_CODE_LABEL"),    placeholder = tostring(details.code or ""),                  required = false }
    })
    if not finalInputPart1 then return end

    local expiryPick = _pickExpiryDMY(true)
    if not expiryPick then return end

    local vehicleName = finalInputPart1[1] ~= "" and finalInputPart1[1] or nil
    local moneyAmount = tonumber(finalInputPart1[2])
    if moneyAmount and moneyAmount > 0 then
        table.insert(rewards, { money = true, amount = moneyAmount })
    end
    if vehicleName then
        table.insert(rewards, { vehicle = true, model = vehicleName })
    end
    if #rewards == 0 and not vehicleName and not (moneyAmount and moneyAmount > 0) then
        return NotificationUser(nil, locales("ADMIN_REQUIRE_ITEM"), 'error')
    end

    local newUses   = tonumber(finalInputPart1[3])      
    local newCode   = _normalizeCode(finalInputPart1[4])

    local payload = {
        originalCode = details.code,
        itemsJson    = json.encode(rewards),
        uses         = newUses,
        newCode      = (newCode ~= "" and newCode or nil)
    }

    if expiryPick.mode == 'none' then
        payload.expiryDays = 0
    elseif expiryPick.mode == 'exact' then
        payload.expiryAbs = expiryPick.iso
    end

    TriggerServerEvent("midnight-redeem:updateCode", payload)
end

function generateCodeMenuEdit(details, passedRewards)
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

    if itemName ~= "" and itemAmount and itemAmount > 0 then
        table.insert(rewards, { item = itemName, amount = itemAmount })
    elseif itemName ~= "" or (itemAmount and itemAmount > 0) then
        NotificationUser(nil, locales("ADMIN_ADD_INVALID_ITEM"), 'error')
        return generateCodeMenu(rewards)
    end

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
        return generateCodeMenuEdit(details, rewards)
    end

    return finalizeEditRewards(details, rewards)
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
                    { label = locales("ADMIN_MANAGE_ACTION_EDIT"),   value = 'edit' }, -- NEW
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
        elseif inputOption[2] == 'edit' then
            openEditCodeMenu(selectedCode)
        end
    end)
end

function generateCodeSubMenu(rewards, skipAddAnotherPrompt)
    rewards = rewards or {}

    if not skipAddAnotherPrompt then
        local choiceInput = Bridge.Input.Open(locales("ADMIN_ADD_ANOTHER_ITEM_TITLE"), {
            {
                type = 'select',
                label = locales("ADMIN_ADD_ANOTHER_ITEM_LABEL"),
                options = {
                    { label = locales("ADMIN_ADD_ANOTHER_ITEM_YES"), value = 'yes' },
                    { label = locales("ADMIN_ADD_ANOTHER_ITEM_NO"),  value = 'no'  }
                },
                required = true
            }
        })
        if not choiceInput then
            return
        end
        if choiceInput[1] == 'yes' then
            return generateCodeMenu(rewards)
        end
    end

    local function trim(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end
    local minLen = tonumber(Config and Config.mincustomchar) or 0

    local vehicleName, moneyAmount, uses, code, perUserLimit
    local valid

    repeat
        valid = true

        local finalInputPart1 = Bridge.Input.Open(locales("ADMIN_FINALIZE_TITLE"), {
            { type = 'input',  label = locales("ADMIN_FINALIZE_VEHICLE_LABEL"), placeholder = locales("ADMIN_FINALIZE_VEHICLE_PLACEHOLDER"), required = false },
            { type = 'number', label = locales("ADMIN_FINALIZE_MONEY_LABEL"),   placeholder = locales("ADMIN_FINALIZE_MONEY_PLACEHOLDER"),   required = false },
            { type = 'number', label = locales("ADMIN_FINALIZE_USES_LABEL"),    placeholder = locales("ADMIN_FINALIZE_USES_PLACEHOLDER"),    required = true },
            { type = 'input',  label = locales("ADMIN_FINALIZE_CODE_LABEL"),    placeholder = locales("ADMIN_FINALIZE_CODE_PLACEHOLDER"),    required = true },
            { type = 'number', label = (locales("ADMIN_PER_USER_LIMIT_LABEL") or "Per-user uses (0 = unlimited)"), placeholder = "1", required = true }
        })

        if not finalInputPart1 then
            return
        end

        vehicleName  = finalInputPart1[1] ~= "" and finalInputPart1[1] or nil
        moneyAmount  = tonumber(finalInputPart1[2])
        uses         = tonumber(finalInputPart1[3])
        code         = trim(finalInputPart1[4])
        perUserLimit = tonumber(finalInputPart1[5] or 1)

        if not uses or uses <= 0 then
            NotificationUser(nil, locales("NOTIFY_INVALID_USES") or "Uses must be a positive number.", 'error')
            valid = false
        end

        if perUserLimit == nil or perUserLimit < 0 then
            NotificationUser(nil, (locales("ADMIN_PER_USER_LIMIT_INVALID") or "Per-user uses must be 0 or a positive number."), 'error')
            valid = false
        end

        if minLen > 0 then
            local len = (utf8 and utf8.len and utf8.len(code)) or #code
            if len < minLen then
                local msg = (locales and locales("ADMIN_CODE_TOO_SHORT", minLen)) or ("Custom code must be at least " .. minLen .. " characters long.")
                NotificationUser(nil, msg, 'error')
                valid = false
            end
        end
    until valid

    local expiryPick = _pickExpiryDMY(true)
    if not expiryPick then
        return
    end

    if moneyAmount and moneyAmount > 0 then
        table.insert(rewards, { money = true, amount = moneyAmount })
    end
    if vehicleName then
        table.insert(rewards, { vehicle = true, model = vehicleName })
    end

    if #rewards == 0 and not vehicleName and not (moneyAmount and moneyAmount > 0) then
        return NotificationUser(nil, locales("ADMIN_REQUIRE_ITEM") or "Please add at least one reward (item, money, or vehicle).", 'error')
    end

    local expiryArgDays = 0
    local expiryAbs
    if expiryPick.mode == 'exact' then
        expiryAbs = expiryPick.iso
    end

    TriggerServerEvent(
        "midnight-redeem:generateCode",
        json.encode(rewards),
        uses,
        (expiryAbs and expiryAbs or expiryArgDays),
        code,
        perUserLimit
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

    local itemName   = tostring(itemInput[1] or "")
    local itemAmount = tonumber(itemInput[2])

    if itemName ~= "" and itemAmount and itemAmount > 0 then
        table.insert(rewards, { item = itemName, amount = itemAmount })
    elseif itemName ~= "" or (itemAmount and itemAmount > 0) then
        NotificationUser(nil, locales("ADMIN_ADD_INVALID_ITEM") or "Invalid item details.", 'error')
        return generateCodeMenu(rewards)
    end

    local choiceInput = Bridge.Input.Open(locales("ADMIN_ADD_ANOTHER_ITEM_TITLE"), {
        {
            type = 'select',
            label = locales("ADMIN_ADD_ANOTHER_ITEM_LABEL"),
            options = {
                { label = locales("ADMIN_ADD_ANOTHER_ITEM_YES"), value = 'yes' },
                { label = locales("ADMIN_ADD_ANOTHER_ITEM_NO"),  value = 'no'  }
            },
            required = true
        }
    })
    if not choiceInput then return end

    if choiceInput[1] == 'yes' then
        return generateCodeMenu(rewards)
    end

    generateCodeSubMenu(rewards, true)
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
        StartGenerateCodeWizard()
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