local Bridge = exports['community_bridge']:Bridge()

local function NotificationUser(title, description, ntype)
    local ok = pcall(function()
        Bridge.Notify.SendNotify((description and #description > 0) and description or (title or ""), ntype or "info", 6000)
    end)
    SendNUIMessage({ action = 'toast', title = title or "Midnight Redeem", description = description or "", type = ntype or "info", duration = 2500 })
    if not ok and lib and lib.notify then
        lib.notify({ title = title or "Midnight Redeem", description = description or "", type = ntype or "info", duration = 6000 })
    elseif not ok then
    print(("[midnight-redeem][%s] %s - %s"):format(ntype or "info", title or "", description or ""))
    end
end

local function openUI(mode, tab)
    if MidnightRedeem and MidnightRedeem.Death and not MidnightRedeem.Death.canOpenUI() then
        MidnightRedeem.Death.notifyBlocked()
        return
    end
    if MidnightRedeem and MidnightRedeem.Death then
        MidnightRedeem.Death.setUIOpen(true)
    end
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'showUI', mode = mode, tab = tab })
end

local function closeUI()
    if MidnightRedeem and MidnightRedeem.Death then
        MidnightRedeem.Death.setUIOpen(false)
    end
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'hideUI' })
end

RegisterNetEvent('midnight_redeem:deathCloseUI', function()
    closeUI()
end)

AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    closeUI()
    TriggerServerEvent("midnight-redeem:requestClientConfig")
end)

RegisterNetEvent("midnight-redeem:syncClientConfig", function(payload)
    payload = payload or {}
    Config.mincustomchar = tonumber(payload.mincustomchar) or Config.mincustomchar or 6
    if payload.aiEnabled ~= nil then
        Config.AIEnabled = payload.aiEnabled == true
    end
end)

RegisterNetEvent('midnight_redeem:ui:open', function(payload)
    payload = payload or {}
    if payload.mode == 'admin' then
        return
    end
    openUI(payload.mode or 'player', payload.tab or 'redeem')
end)

RegisterNetEvent('midnight_redeem:ui:close', function()
    closeUI()
end)

RegisterNetEvent("midnight-redeem:openAdminMenu", function()
    openUI('admin', 'dashboard')
    TriggerServerEvent("midnight-redeem:registerAdminClient")
    if type(RegisterCodeMenus) == "function" then pcall(RegisterCodeMenus) end
end)

RegisterNetEvent("midnight-redeem:sendAllDashboardData", function(data)
    SendNUIMessage({ action = 'allDashboardData', data = data })
end)

RegisterNetEvent("midnight-redeem:redeemcode", function()
    openUI('player', 'redeem')
end)

RegisterNetEvent('midnight_redeem:openPlayer', function()
    openUI('player', 'redeem')
end)

RegisterNetEvent("midnight-redeem:notifyUser", function(title, description, ntype)
    NotificationUser(title, description, ntype)
end)

RegisterNetEvent("midnight-redeem:sendUIToast", function(title, description, ntype)
    SendNUIMessage({ action = 'toast', title = title or "Midnight Redeem", description = description or "", type = ntype or "info", duration = 2500 })
end)

CreateThread(function()

    if type(RegisterCodeMenus) == "function" then 
        pcall(RegisterCodeMenus) 
    end
    

    if type(RegisterRedeemMenu) == "function" then
        pcall(function()
            RegisterRedeemMenu({ 
                id = 'redeemcode', 
                title = 'Redeem Code', 
                onSelect = function() TriggerEvent('midnight_redeem:openPlayer') end 
            })
        end)
    else
        RegisterCommand('redeemcode', function() 
            TriggerEvent('midnight_redeem:openPlayer') 
        end, false)
    end
end)

RegisterNUICallback('close', function(_, cb)
    closeUI(); if cb then cb(true) end
end)

RegisterNUICallback('adminCreate', function(data, cb)
    local itemsJson   = tostring(data.itemsJson or "[]")
    local uses        = tonumber(data.uses) or 1
    local expiry      = data.expiry
    local customCode  = tostring(data.customCode or "")
    local perUser     = tonumber(data.perUserLimit) or 1
    local timeRestrictions = data.timeRestrictions
    local playerRestriction = data.playerRestriction
    
    local minCustomChar = tonumber(Config.mincustomchar) or 6
    if customCode and customCode ~= "" and #customCode < minCustomChar then
        NotificationUser("Create Code", "Code must be at least " .. minCustomChar .. " characters long.", "error")
        if cb then cb(false) end
        return
    end
    
    TriggerServerEvent("midnight-redeem:generateCode", itemsJson, uses, expiry, customCode, perUser, timeRestrictions, playerRestriction)
    if cb then cb(true) end
end)

RegisterNUICallback('createShadowChatSession', function(_, cb)
    local ok, result = pcall(function()
        return lib.callback.await("midnight-redeem:createShadowChatSession", false)
    end)
    if not ok then
        result = { success = false, error = "Failed to create chat session." }
    end
    if cb then cb(result) end
end)

RegisterNUICallback('shadowChatMessage', function(data, cb)
    local ok, result = pcall(function()
        return lib.callback.await(
            "midnight-redeem:shadowChatMessage",
            false,
            data.message,
            data.conversationHistory or {},
            data.sessionId,
            data.pendingAction,
            data.confirmPendingAction
        )
    end)
    if not ok then
        result = { success = false, error = "Shadow callback failed." }
    end
    if cb then cb(result) end
end)

RegisterNUICallback('shadowExecuteAction', function(data, cb)
    local ok, result = pcall(function()
        return lib.callback.await("midnight-redeem:shadowExecuteAction", false, data.action, data.payload, data.sessionId)
    end)
    if not ok then
        result = { success = false, error = "Shadow action failed." }
    end
    if cb then cb(result) end
end)

RegisterNUICallback('validateCode', function(data, cb)
    local code   = tostring((data and data.code) or "")
    local account = (data and data.account) or "cash"
    
    if code == "" then
        if cb then cb({ success = false, error = "Please enter a code." }) end
        return
    end
    
    local ok, result = pcall(function() 
        return lib.callback.await("midnight-redeem:validateCode", false, code, account)
    end)
    
    if not ok or not result then
        if cb then cb({ success = false, error = "Failed to validate code." }) end
        return
    end
    
    if cb then cb(result) end
end)

RegisterNUICallback('applyReward', function(data, cb)
    local code   = tostring((data and data.code) or "")
    local account = (data and data.account) or "cash"
    
    if code == "" then
        if cb then cb({ success = false, error = "Please enter a code." }) end
        return
    end
    
    local ok, result = pcall(function() 
        return lib.callback.await("midnight-redeem:applyReward", false, code, account)
    end)
    
    if not ok or not result then
        if cb then cb({ success = false, error = "Failed to apply reward." }) end
        return
    end
    
    if cb then cb(result) end
end)

RegisterNUICallback('playerRedeem', function(data, cb)
    local code   = tostring((data and data.code) or "")
    local account = (data and data.account) or "cash"
    
    if code == "" then
        NotificationUser("Redeem", "Please enter a code.", "error")
        if cb then cb({ success = false, error = "Please enter a code." }) end
        return
    end
    
    local ok, result = pcall(function() 
        return lib.callback.await("midnight-redeem:redeemCodeWithResult", false, code, account)
    end)
    
    if not ok or not result then
        if cb then cb({ success = false, error = "Failed to process redemption." }) end
        return
    end
    
    if cb then cb(result) end
end)

RegisterNUICallback('getAllCodes', function(_, cb)
    local ok, result = pcall(function() return lib.callback.await("midnight-redeem:getAllCodes", false) end)
    if not ok then result = {} end
    if cb then cb(result) end
end)

RegisterNUICallback('checkCodeRewards', function(data, cb)
    local ok, result = pcall(function() 
        return lib.callback.await("midnight-redeem:checkCodeRewards", false, data.code)
    end)
    if not ok then 
        result = { success = false, hasMoneyRewards = false }
    end
    if cb then cb(result) end
end)

RegisterNUICallback('getAllCodesWithDetails', function(_, cb)
    local ok, result = pcall(function() 
        local res = lib.callback.await("midnight-redeem:getAllCodesWithDetails", false)
        return res
    end)
    if not ok then 
        result = { success = false, data = {} }
    else
        result = { success = true, data = result or {} }
    end
    if cb then cb(result) end
end)

RegisterNUICallback('getAllCodesForSearch', function(_, cb)
    local ok, result = pcall(function()
        return lib.callback.await("midnight-redeem:getAllCodesForSearch", false)
    end)
    if not ok then result = {} end
    if cb then cb(result or {}) end
end)



RegisterNUICallback('getAllUserPermissions', function(_, cb)
    local ok, result = pcall(function() return lib.callback.await("midnight-redeem:getAllUserPermissions", false) end)
    if not ok then 
        result = { success = false, data = {} }
    else
        result = { success = true, data = result or {} }
    end
    if cb then cb(result) end
end)

RegisterNUICallback('getUserPermissions', function(_, cb)
    local ok, result = pcall(function()
        return lib.callback.await("midnight-redeem:getUserPermissions", false)
    end)
    if not ok then
        result = { role = "staff", level = 1, permissions = {} }
    end
    if cb then cb(result or { role = "staff", level = 1, permissions = {} }) end
end)


RegisterNUICallback('updateUserPermission', function(data, cb)
    local ok, result = pcall(function() 
        return lib.callback.await("midnight-redeem:updateUserPermission", false, data.userId or data.playerId, data.newRole) 
    end)
    if not ok then 
        result = { success = false, message = "Callback failed" } 
    end
    if cb then cb(result) end
end)

RegisterNUICallback('deleteUser', function(data, cb)
    local ok, result = pcall(function() 
        return lib.callback.await("midnight-redeem:deleteUser", false, data.identifier) 
    end)
    if not ok then 
        result = { success = false, message = "Callback failed" } 
    end
    if cb then cb(result) end
end)

RegisterNUICallback('getCodeDetails', function(data, cb)
    local ok, result = pcall(function()
        local res = lib.callback.await("midnight-redeem:getCodeDetails", false, data.code)
        return res
    end)
    if not ok then
        result = { success = false, data = {} }
    else
        result = result or { success = false, data = {} }
    end
    if cb then cb(result) end
end)

RegisterNUICallback('adminUpdate', function(data, cb)
    TriggerServerEvent("midnight-redeem:updateCode", data or {})
    NotificationUser("Update Code", "Changes sent.", "success")
    if cb then cb(true) end
end)

RegisterNUICallback('updateCode', function(data, cb)
    TriggerServerEvent("midnight-redeem:updateCode", data or {})
    if cb then cb(true) end
end)

RegisterNUICallback('purgeCodes', function(data, cb)
    local result = lib.callback.await("midnight-redeem:purgeCodes", false, data.period, data.includeActive)
    if cb then cb(result) end
end)

RegisterNUICallback('deleteCode', function(data, cb)
    local code = data and data.code or ""
    if code == "" then
        SendNUIMessage({ action = 'toast', title = "Delete Code", description = "No code specified for deletion.", type = "error", duration = 2500 })
        if cb then cb(false) end
        return
    end
    TriggerServerEvent("midnight-redeem:deleteCode", code)
    SendNUIMessage({ action = 'toast', title = "Delete Code", description = "Delete request sent.", type = "success", duration = 2500 })
    if cb then cb(true) end
end)

RegisterNUICallback('deleteTranscript', function(data, cb)
    local sessionId = data and data.sessionId or ""
    if sessionId == "" then
        SendNUIMessage({ action = 'toast', title = "Delete Transcript", description = "No transcript session specified for deletion.", type = "error", duration = 2500 })
        if cb then cb(false) end
        return
    end
    TriggerServerEvent("midnight-redeem:deleteTranscript", sessionId)
    SendNUIMessage({ action = 'toast', title = "Delete Transcript", description = "Delete request sent.", type = "success", duration = 2500 })
    if cb then cb(true) end
end)

RegisterNUICallback('getAIChatSessions', function(_, cb)
    local ok, result = pcall(function()
        return lib.callback.await("midnight-redeem:getAIChatSessions", false)
    end)
    if not ok then result = { success = false, sessions = {} } end
    if cb then cb(result or { success = false, sessions = {} }) end
end)

RegisterNUICallback('getAllAIChatSessions', function(_, cb)
    local ok, result = pcall(function()
        return lib.callback.await("midnight-redeem:getAllAIChatSessions", false)
    end)
    if not ok then result = { success = false, sessions = {} } end
    if cb then cb(result or { success = false, sessions = {} }) end
end)

RegisterNUICallback('getAIChatMessages', function(data, cb)
    local ok, result = pcall(function()
        return lib.callback.await("midnight-redeem:getAIChatMessages", false, data and data.sessionId)
    end)
    if not ok then result = { success = false, messages = {} } end
    if cb then cb(result or { success = false, messages = {} }) end
end)

RegisterNUICallback('getAIChatSettings', function(_, cb)
    local ok, result = pcall(function()
        return lib.callback.await("midnight-redeem:getAIChatSettings", false)
    end)
    if not ok then result = { success = false, error = "Failed to load chat settings." } end
    if cb then cb(result or { success = false }) end
end)

RegisterNUICallback('saveAIChatSettings', function(data, cb)
    local ok, result = pcall(function()
        return lib.callback.await("midnight-redeem:saveAIChatSettings", false, data or {})
    end)
    if not ok then result = { success = false, error = "Failed to save chat settings." } end
    if cb then cb(result or { success = false }) end
end)

RegisterNUICallback('runTranscriptCleanup', function(_, cb)
    local ok, result = pcall(function()
        return lib.callback.await("midnight-redeem:runTranscriptCleanup", false)
    end)
    if not ok then result = { success = false, error = "Cleanup failed." } end
    if cb then cb(result or { success = false }) end
end)

RegisterNUICallback('clearAllTranscripts', function(_, cb)
    local ok, result = pcall(function()
        return lib.callback.await("midnight-redeem:clearAllTranscripts", false)
    end)
    if not ok then result = { success = false, error = "Failed to clear transcripts." } end
    if cb then cb(result or { success = false }) end
end)

RegisterNUICallback('resetAIChatRateLimits', function(_, cb)
    local ok, result = pcall(function()
        return lib.callback.await("midnight-redeem:resetAIChatRateLimits", false)
    end)
    if not ok then result = { success = false, error = "Failed to reset rate limits." } end
    if cb then cb(result or { success = false }) end
end)

RegisterNUICallback('checkCodeName', function(data, cb)
    local ok, result = pcall(function()
        return lib.callback.await("midnight-redeem:checkCodeName", false, data and data.codeName)
    end)
    if not ok then result = { valid = false, issues = { "Failed to validate code name." } } end
    if cb then cb(result or { valid = false, issues = { "Failed to validate code name." } }) end
end)

RegisterNUICallback('getRuntimeConfig', function(data, cb)
    local ok, result = pcall(function()
        return lib.callback.await("midnight-redeem:getRuntimeConfig", false, data and data.section)
    end)
    if not ok then
        print(("[midnight-redeem] getRuntimeConfig NUI error: %s"):format(tostring(result)))
        result = { success = false, error = "Failed to load runtime config." }
    end
    if cb then cb(result or { success = false, error = "Failed to load runtime config." }) end
end)

RegisterNUICallback('saveRuntimeConfig', function(data, cb)
    local ok, result = pcall(function()
        return lib.callback.await("midnight-redeem:saveRuntimeConfig", false, data.section, data.payload)
    end)
    if not ok then result = { success = false, error = "Failed to save runtime config." } end
    if cb then cb(result or { success = false }) end
end)

RegisterNUICallback('resetRuntimeConfig', function(data, cb)
    local ok, result = pcall(function()
        return lib.callback.await("midnight-redeem:resetRuntimeConfig", false, data.section)
    end)
    if not ok then result = { success = false, error = "Failed to reset runtime config." } end
    if cb then cb(result or { success = false }) end
end)

RegisterNUICallback('getDashboard', function(_, cb)
    local ok, result = pcall(function() 
        return lib.callback.await("midnight-redeem:dashboardStats", false) 
    end)
    
    if not ok or not result then 
        result = { 
            success = false,
            data = { 
                totalCodes = 0, 
                activeCodes = 0, 
                fullCodes = 0, 
                expiredCodes = 0,
                recentCodes = {}
            }
        }
    else

        result = {
            success = true,
            data = {
                totalCodes = result.total or 0,
                activeCodes = result.active or 0,
                fullCodes = result.full or 0,
                expiredCodes = result.expired or 0,
                recentCodes = result.recent or {}
            }
        }
    end
    
    if cb then cb(result) end
end)

RegisterNUICallback('bulkGenerateCodes', function(data, cb)
    local amount = tonumber(data.amount) or 100
    local pattern = tostring(data.pattern or "")
    local uses = tonumber(data.uses) or 1
    local perUserLimit = tonumber(data.perUserLimit) or 1
    local expiryHours = tonumber(data.expiryHours) or 24
    local rewards = data.rewards or {}
    
    if amount < 1 or amount > 10000 then
        NotificationUser("Bulk Generation", "Invalid amount. Must be between 1 and 10,000.", "error")
        if cb then cb(false) end
        return
    end
    
    if pattern:gsub("^%s*(.-)%s*$", "%1") == "" then
        NotificationUser("Bulk Generation", "Invalid pattern. Please provide a valid code pattern.", "error")
        if cb then cb(false) end
        return
    end
    
    if #rewards == 0 then
        NotificationUser("Bulk Generation", "No rewards specified. Please add at least one reward.", "error")
        if cb then cb(false) end
        return
    end
    

    TriggerServerEvent("midnight-redeem:bulkGenerateCodes", amount, pattern, uses, perUserLimit, expiryHours, rewards)
    if cb then cb(true) end
end)

RegisterNUICallback('getServerConfig', function(_, cb)
    local versionInfo = {}
    pcall(function()
        versionInfo = lib.callback.await("midnight-redeem:getVersionInfo", false, false) or {}
    end)

    local aiEnabled = Config.AIEnabled ~= false
    pcall(function()
        local aiState = lib.callback.await("midnight-redeem:getAIEnabled", false)
        if aiState and aiState.enabled ~= nil then
            aiEnabled = aiState.enabled == true
        end
    end)

    local config = {
        minCustomChar = tonumber(Config.mincustomchar) or 6,
        aiEnabled = aiEnabled,
        version = versionInfo,
    }
    if cb then cb(config) end
end)

RegisterNUICallback('getVersionInfo', function(data, cb)
    local ok, result = pcall(function()
        return lib.callback.await("midnight-redeem:getVersionInfo", false, data and data.refresh == true)
    end)
    if not ok then result = {} end
    if cb then cb(result or {}) end
end)

RegisterNUICallback('checkEditPermission', function(_, cb)
    local ok, result = pcall(function() 
        return lib.callback.await("midnight-redeem:checkEditPermission", false) 
    end)
    if not ok then 
        result = false 
    end
    if cb then cb(result) end
end)

RegisterNUICallback('getPreFilledRewards', function(_, cb)
    local ok, result = pcall(function() 
        return lib.callback.await("midnight-redeem:getPreFilledRewards", false) 
    end)
    if not ok then 
        result = {} 
    end
    if cb then cb(result) end
end)

RegisterNUICallback('saveTemplate', function(data, cb)
    local templateName = data.name
    local rewards = data.rewards
    
    if not templateName or not rewards then
        cb({ success = false, error = "Invalid template data" })
        return
    end
    
    local result = lib.callback.await("midnight-redeem:saveTemplate", false, templateName, rewards)
    cb(result)
end)

RegisterNUICallback('getSavedTemplates', function(data, cb)
    local result = lib.callback.await("midnight-redeem:getSavedTemplates", false)
    cb(result)
end)

RegisterNUICallback('deleteSavedTemplate', function(data, cb)
    local templateName = data.templateName or data.name
    local result = lib.callback.await("midnight-redeem:deleteSavedTemplate", false, templateName)
    if cb then cb(result) end
end)


RegisterNUICallback('createCode', function(data, cb)
    local result = lib.callback.await("midnight-redeem:createCode", false, data)
    cb(result)
end)

RegisterNUICallback('refreshData', function(data, cb)
    TriggerServerEvent("midnight-redeem:refreshData")
    if cb then cb({ success = true }) end
end)

RegisterNUICallback('addReward', function(data, cb)
    local result = lib.callback.await("midnight-redeem:addReward", false, data)
    if cb then cb(result) end
end)

RegisterNUICallback('removeReward', function(data, cb)
    local result = lib.callback.await("midnight-redeem:removeReward", false, data)
    if cb then cb(result) end
end)

RegisterNUICallback('updateReward', function(data, cb)
    local result = lib.callback.await("midnight-redeem:updateReward", false, data)
    if cb then cb(result) end
end)

exports('openUI', openUI)
exports('closeUI', closeUI)

