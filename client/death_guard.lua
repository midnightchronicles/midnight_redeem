local Bridge = exports['community_bridge']:Bridge()

MidnightRedeem = MidnightRedeem or {}
MidnightRedeem.Death = MidnightRedeem.Death or {}

local uiOpen = false

local function deadMessage()
    local msg = "You cannot use this while dead."
    pcall(function()
        local locale = Bridge.Language and Bridge.Language.Locale
        if locale then
            local translated = locale("NOTIFY_UI_UNAVAILABLE_WHILE_DEAD")
            if translated and translated ~= "NOTIFY_UI_UNAVAILABLE_WHILE_DEAD" then
                msg = translated
            end
        end
    end)
    return msg
end

function MidnightRedeem.Death.isPlayerDead()
    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) then
        return false
    end

    -- Bridge reads QBX metadata; only call once the framework reports the player is loaded.
    local bridge = Bridge and Bridge.Framework
    if bridge and type(bridge.GetIsPlayerLoaded) == "function" and bridge.GetIsPlayerLoaded() then
        if type(bridge.GetIsPlayerDead) == "function" then
            local ok, dead = pcall(function()
                return bridge.GetIsPlayerDead()
            end)
            if ok and dead == true then
                return true
            end
        end
    end

    if IsEntityDead(ped) or IsPedFatallyInjured(ped) then
        return true
    end

    local playerState = LocalPlayer and LocalPlayer.state
    if playerState and playerState.isDead == true then
        return true
    end

    return false
end

function MidnightRedeem.Death.canOpenUI()
    return not MidnightRedeem.Death.isPlayerDead()
end

function MidnightRedeem.Death.notifyBlocked()
    local msg = deadMessage()
    pcall(function()
        Bridge.Notify.SendNotify(msg, "error", 4000)
    end)
end

function MidnightRedeem.Death.setUIOpen(open)
    uiOpen = open == true
end

function MidnightRedeem.Death.isUIOpen()
    return uiOpen
end

function MidnightRedeem.Death.releaseFocus()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end

function MidnightRedeem.Death.forceCloseUI()
    uiOpen = false
    MidnightRedeem.Death.releaseFocus()
    SendNUIMessage({ action = "hideUI" })
    TriggerEvent("midnight_redeem:deathCloseUI")
end

CreateThread(function()
    while true do
        Wait(300)
        if MidnightRedeem.Death.isPlayerDead() and (uiOpen or IsNuiFocused()) then
            MidnightRedeem.Death.forceCloseUI()
        end
    end
end)
