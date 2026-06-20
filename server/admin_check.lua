local Bridge = exports['community_bridge']:Bridge()
local ADMIN_ACE = "midnight_redeem.admin"
local resourceName = GetCurrentResourceName()

--- Returns true when community_bridge reports framework admin, or ACE grants midnight_redeem.admin.
function AdminIsBridgeOrAceAdmin(source)
    if type(source) ~= "number" or source <= 0 then
        return false
    end

    local ok, isFrameworkAdmin = pcall(function()
        return Bridge.Framework.GetIsFrameworkAdmin(source)
    end)
    if ok and isFrameworkAdmin == true then
        return true
    end

    if type(IsPlayerAceAllowed) == "function" then
        local aceOk, hasAce = pcall(IsPlayerAceAllowed, source, ADMIN_ACE)
        if aceOk and hasAce == true then
            return true
        end
    end

    return false
end

--- Checks RBAC when enabled, otherwise falls back to AdminIsBridgeOrAceAdmin.
function AdminHasPermission(source, permission)
    local requirePermission = exports[resourceName]:GetRequirePermission() ~= false
    if requirePermission then
        pcall(function()
            exports[resourceName]:PrepareAdminAccess(source)
        end)
        local ok, result = pcall(function()
            return exports[resourceName]:hasPermission(source, permission)
        end)
        if ok then
            return result == true
        end
        print(("[midnight_redeem] hasPermission check failed (%s): %s"):format(tostring(permission), tostring(result)))
        return false
    end
    return AdminIsBridgeOrAceAdmin(source)
end

exports('AdminIsBridgeOrAceAdmin', AdminIsBridgeOrAceAdmin)
exports('AdminHasPermission', AdminHasPermission)
