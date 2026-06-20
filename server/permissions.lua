-- ========================================
-- OWNER LICENSES
-- ========================================
-- To add an owner once you have added the identifier below use the command: /midnight_admin_init
-- Supported identifier types: license2(recommended), license, steam, discord
-- ========================================

OWNER_LICENSES = {
    "place_owners_identifier",  -- Owner 1 - Replace with actual license (license2(recommended), license,  steam, discord)
    "place_owners_identifier",  -- Owner 2 - Replace with actual license (license2(recommended), license,  steam, discord)
    "place_owners_identifier",  -- Owner 3 - Replace with actual license (license2(recommended), license,  steam, discord)
}

-- ========================================
-- PERMISSION SYSTEM CONFIGURATION
-- ========================================
-- RequirePermission: Set to false to use framework admin check instead of custom permission system
--                    This loses granular control - all framework admins will have full permissions
-- DefaultRole: The role that framework admins will be auto-assigned when they first access the dashboard
--              Options: "staff", "manager", "owner"
-- ========================================

REQUIRE_PERMISSION = true  -- Set to false to use framework admin check (all admins get full permissions)

DEFAULT_ROLE = "staff"  -- Default role for auto-assigned framework admins (staff, manager, or owner)

-- ========================================
-- PERMISSION ACTIONS CONFIGURATION
-- ========================================
-- Configure which roles can perform each action (please contact support if you need different levels adding
-- Options: "owner", "manager", "staff"
--"owner" → level 3
--"manager" → level 2
--"staff" → level 1
-- ========================================
PERMISSION_ACTIONS_CONFIG = {
    CREATE_CODES = { "owner", "manager", "staff" },
    EDIT_CODES = { "owner", "manager" },
    DELETE_CODES = { "owner", "manager" },
    BULK_DELETE = { "owner", "manager" },
    VIEW_DASHBOARD = { "owner", "manager", "staff" },
    VIEW_TRANSCRIPTS = { "owner", "manager", "staff" },
    MANAGE_PERMISSIONS = { "owner", "manager" },
    COLOR_SETTINGS = { "owner", "manager", "staff" },
    FULL_ACCESS = { "owner" }
}

-- =================
-- DO NOT TOUCH THIS
-- =================

exports('GetOwnerLicenses', function()
    return OWNER_LICENSES
end)

exports('GetRequirePermission', function()
    return REQUIRE_PERMISSION
end)

exports('GetDefaultRole', function()
    return DEFAULT_ROLE
end)

exports('GetPermissionActionsConfig', function()
    return PERMISSION_ACTIONS_CONFIG
end)