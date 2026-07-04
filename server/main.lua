local Bridge = exports['community_bridge']:Bridge()

if not json_encode and json and json.encode then
    json_encode = json.encode
end

local resourceName = GetCurrentResourceName()
local OWNER_LICENSES = exports[resourceName]:GetOwnerLicenses() or {}
local REQUIRE_PERMISSION = exports[resourceName]:GetRequirePermission() ~= false
local DEFAULT_ROLE = exports[resourceName]:GetDefaultRole() or "staff"
local PERMISSION_ACTIONS_CONFIG = exports[resourceName]:GetPermissionActionsConfig() or {}

local function GetRequirePermission()
    return exports[resourceName]:GetRequirePermission() ~= false
end

PERMISSIONS = {
    OWNER = 3,
    MANAGER = 2,
    STAFF = 1
}

local function getDefaultRole()
    local defaultRole = exports[resourceName]:GetDefaultRole() or DEFAULT_ROLE or "staff"
    local roleUpper = string.upper(defaultRole)
    local defaultLevel = PERMISSIONS[roleUpper] or PERMISSIONS.STAFF
    
    if defaultLevel == nil then
        defaultRole = "staff"
        defaultLevel = PERMISSIONS.STAFF
    end
    
    return defaultRole:lower(), defaultLevel
end

local function autoAssignDefaultRole(source, identifier)
    local requirePermission = exports[resourceName]:GetRequirePermission() ~= false
    if not requirePermission then
        return false
    end
    
    if not AdminIsBridgeOrAceAdmin(source) then
        return false
    end
    
    local existingRecord = MySQL.single.await('SELECT identifier FROM midnight_user_permissions WHERE identifier = ? LIMIT 1', { identifier })
    if existingRecord then
        return false
    end
    
    local defaultRole, defaultLevel = getDefaultRole()
    local playerName = GetPlayerName(source) or "Unknown"
    
    local success = pcall(function()
        MySQL.insert.await([[
            INSERT INTO midnight_user_permissions (identifier, role, permission_level, player_name) 
            VALUES (?, ?, ?, ?)
        ]], { identifier, defaultRole, defaultLevel, playerName })
    end)
    
    if success then
        print(string.format("[midnight_redeem] Auto-assigned %s role to framework admin: %s (%s)", defaultRole, playerName, identifier))
        return true
    end
    
    return false
end

function PrepareAdminAccess(source)
    if not GetRequirePermission() then
        return
    end

    local identifier = getUserIdentifier(source)
    if identifier then
        autoAssignDefaultRole(source, identifier)
    end
end

function Checkadmin(src)
    if AdminHasPermission(src, "VIEW_DASHBOARD") then
        return true
    end

    local message = GetRequirePermission()
        and "You don't have permission to access the admin dashboard. Contact an owner/manager for access."
        or (locales("NOTIFY_PERMISSION_DENIED") or "Permission denied.")
    Bridge.Notify.SendNotify(src, message, "error", 6000)
    return false
end

local function requireAdmin(source, permission)
    return AdminHasPermission(source, permission or "VIEW_DASHBOARD")
end

local function isPlayerDead(src)
    local ok, dead = pcall(function()
        return Bridge.Framework.GetIsPlayerDead(src)
    end)
    return ok and dead == true
end

local function blockIfDead(src)
    if isPlayerDead(src) then
        Bridge.Notify.SendNotify(
            src,
            locales("NOTIFY_UI_UNAVAILABLE_WHILE_DEAD") or "You cannot use this while dead.",
            "error",
            6000
        )
        return true
    end
    return false
end

local buildUserPermissionFlags
local hasPermission

local _openAdminClients = {}
local _refreshPending = false
local _dashboardData = {
    stats = { total = 0, full = 0, expired = 0, active = 0, unlimited = 0, recent = {} },
    weekly = {
        generated = { current = 0, previous = 0, change = 0 },
        thisWeek = { current = 0, previous = 0, change = 0 },
        lastWeek = { current = 0, previous = 0, change = 0 },
        active = { current = 0, previous = 0, change = 0 },
        redeemed = { current = 0, previous = 0, change = 0 },
        expired = { current = 0, previous = 0, change = 0 }
    },
    daily = {
        monday = { current = 0, previous = 0, change = 0 },
        tuesday = { current = 0, previous = 0, change = 0 },
        wednesday = { current = 0, previous = 0, change = 0 },
        thursday = { current = 0, previous = 0, change = 0 },
        friday = { current = 0, previous = 0, change = 0 },
        saturday = { current = 0, previous = 0, change = 0 },
        sunday = { current = 0, previous = 0, change = 0 }
    },
    codes = {},
    allCodes = {},
    rewards = {},
    lastRefresh = 0
}
local _permissionCache = {}
local PERM_CACHE_TTL = 120
local _redeemRateLimit = {}
local REDEEM_COOLDOWN_MS = 1500
local MAX_REWARDS_PER_CODE = 50
local MAX_REWARD_AMOUNT = 100000000
local MAX_ITEMS_JSON_BYTES = 65536

local function invalidatePermissionCache(identifier)
    if identifier then
        _permissionCache[identifier] = nil
    else
        _permissionCache = {}
    end
end

local function checkRedeemRateLimit(source)
    local now = GetGameTimer()
    local last = _redeemRateLimit[source] or 0
    if (now - last) < REDEEM_COOLDOWN_MS then
        return false
    end
    _redeemRateLimit[source] = now
    return true
end

local function registerAdminClient(source)
    if source and source > 0 then
        _openAdminClients[source] = true
    end
end

local function unregisterAdminClient(source)
    if source and source > 0 then
        _openAdminClients[source] = nil
    end
end

local function pushDashboardToAdmins(allData, primarySource)
    if primarySource and primarySource > 0 then
        TriggerClientEvent("midnight-redeem:sendAllDashboardData", primarySource, allData)
    end
    for adminSrc, _ in pairs(_openAdminClients) do
        if adminSrc ~= primarySource and GetPlayerPing(adminSrc) > 0 then
            TriggerClientEvent("midnight-redeem:sendAllDashboardData", adminSrc, allData)
        end
    end
end

local function buildAllDashboardData()
    return {
        stats = _dashboardData.stats or {},
        weekly = _dashboardData.weekly or {},
        daily = _dashboardData.daily or {},
        codes = _dashboardData.codes or {},
        allCodes = _dashboardData.allCodes or {},
        rewards = _dashboardData.rewards or {}
    }
end

local function broadcastDashboardAfterRefresh(primarySource)
    CreateThread(function()
        while _isRefreshing do
            Wait(50)
        end
        pushDashboardToAdmins(buildAllDashboardData(), primarySource)
    end)
end

local _permissionsTableReady = false

local function validateNewCodeName(codeName)
    if not codeName or type(codeName) ~= "string" then
        return false, { "Invalid code name" }
    end
    local issues = {}
    if #codeName < (Config.mincustomchar or 6) then
        table.insert(issues, "Code must be at least " .. (Config.mincustomchar or 6) .. " characters long")
    end
    local exists = MySQL.scalar.await('SELECT COUNT(*) FROM midnight_codes WHERE code = ?', { codeName })
    if exists and exists > 0 then
        table.insert(issues, "Code already exists")
    end
    if ContentFilter and ContentFilter.checkCodeName then
        local isValid, contentIssues = ContentFilter.checkCodeName(codeName)
        if not isValid then
            for _, issue in ipairs(contentIssues) do
                table.insert(issues, issue)
            end
        end
    end
    return #issues == 0, issues
end

AddEventHandler('playerDropped', function()
    local src = source
    unregisterAdminClient(src)
    _redeemRateLimit[src] = nil
end)

local function validateRewardsPayload(rawRewards)
    if type(rawRewards) ~= "table" then
        return false, "Invalid rewards payload."
    end
    if #rawRewards > MAX_REWARDS_PER_CODE then
        return false, ("Too many rewards (max %d)."):format(MAX_REWARDS_PER_CODE)
    end
    for _, reward in ipairs(rawRewards) do
        if type(reward) == "table" then
            local amount = tonumber(reward.amount) or 0
            if amount > MAX_REWARD_AMOUNT then
                return false, "Reward amount exceeds server limit."
            end
        end
    end
    local encoded = json_encode(rawRewards)
    if encoded and #encoded > MAX_ITEMS_JSON_BYTES then
        return false, "Rewards payload is too large."
    end
    return true, nil
end

local function slimCodeListRow(row, includeDetails)
    local redeemedBy = safe_json_decode(row.redeemed_by, {})
    local redemptionCount = 0
    if type(redeemedBy) == "table" then
        for _, count in pairs(redeemedBy) do
            if type(count) == "number" then
                redemptionCount = redemptionCount + count
            end
        end
    end
    local entry = {
        code = row.code,
        uses = tonumber(row.uses) or 0,
        expiry = row.expiry,
        per_user_limit = tonumber(row.per_user_limit) or 1,
        created_by = row.created_by or "Unknown",
        created_at = row.created_at,
        updated_at = row.updated_at,
        unlimited = row.unlimited == 1 or row.unlimited == true,
        restricted_to_enabled = row.restricted_to_enabled == 1 or row.restricted_to_enabled == true,
        restricted_to_type = row.restricted_to_type,
        restricted_to_value = row.restricted_to_value,
        redemption_count = redemptionCount
    }
    if includeDetails then
        entry.items = safe_json_decode(row.items, {})
        entry.redeemed_by = redeemedBy
    end
    return entry
end

local json_decode = json.decode
local json_encode = json.encode
local fmt = string.format
local insert = table.insert
local concat = table.concat

      function iso_to_unix(iso)
    if type(iso) ~= "string" or #iso < 19 then return nil end
    local y, mo, d, h, mi, s = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d):(%d%d)$")
    y, mo, d, h, mi, s = tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi), tonumber(s)
    if not y then return nil end
    return os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s })
end

      function _toMinutes(hhmm)
    if type(hhmm) == "string" then
        local h, m = hhmm:match("^(%d+)%D(%d+)$")
        if not h then
            if #hhmm == 4 then
                h, m = hhmm:sub(1,2), hhmm:sub(3,4)
            else
                h, m = hhmm, "0"
            end
        end
        h, m = tonumber(h) or 0, tonumber(m) or 0
        if h < 0 then h = 0 elseif h > 23 then h = 23 end
        if m < 0 then m = 0 elseif m > 59 then m = 59 end
        return h * 60 + m
    elseif type(hhmm) == "number" then
        local h = math.floor(hhmm)
        if h < 0 then h = 0 elseif h > 23 then h = 23 end
        return h * 60
    else
        return nil
    end
end

local _timeCache = {}
local _cacheExpiry = 0
local _cacheDuration = 60

local _refreshInterval = Config.DashboardRefreshInterval or 180
local _refreshTimer = nil
local _isRefreshing = false

local _queryCache = {}
local _cacheExpiry = 30

local _performanceCounters = {
    cacheHits = 0,
    cacheMisses = 0,
    queriesExecuted = 0,
    cacheEvictions = 0
}

      function safe_json_decode(str, fallback)
    local ok, t = pcall(json_decode, str or "[]")
    return (ok and t) or (fallback or {})
end

local function trim_string(value)
    if type(value) ~= "string" then
        return nil
    end
    local trimmed = value:match("^%s*(.-)%s*$")
    if trimmed == "" then
        return nil
    end
    return trimmed
end

local function normalize_rewards_input(rawRewards)
    if type(rawRewards) ~= "table" then
        return {}, 0
    end

    local normalized = {}
    local totalItems = 0

    local function push(entry)
        normalized[#normalized + 1] = entry
    end

    for _, reward in ipairs(rawRewards) do
        if type(reward) == "table" then
            if reward.item ~= nil or reward.itemName ~= nil or type(reward.item) == "table" then
                local nameSource = reward.item or reward.itemName
                if type(nameSource) == "table" then
                    nameSource = nameSource.name or nameSource.label
                end
                if not nameSource and reward.label then
                    nameSource = reward.label
                end
                local itemName = trim_string(nameSource)
                local amountSource = reward.amount
                if amountSource == nil and type(reward.item) == "table" then
                    amountSource = reward.item.amount
                end
                local amount = tonumber(amountSource or reward.count or reward.quantity) or 0
                amount = math.floor(amount + 0.0001)
                if itemName and amount > 0 then
                    push({
                        item = itemName,
                        amount = amount,
                        label = reward.label,
                        metadata = reward.metadata
                    })
                    totalItems = totalItems + amount
                end
            elseif reward.money ~= nil then
                local amount = tonumber(reward.amount) or 0
                if amount > 0 then
                    local account = reward.option or reward.account
                    if not account and type(reward.money) == "string" then
                        account = reward.money
                    end
                    push({
                        money = true,
                        amount = amount,
                        option = account or "cash"
                    })
                end
            elseif reward.vehicle ~= nil or reward.model ~= nil then
                local modelSource = reward.model
                if not modelSource then
                    if type(reward.vehicle) == "string" then
                        modelSource = reward.vehicle
                    elseif type(reward.vehicle) == "table" then
                        modelSource = reward.vehicle.model or reward.vehicle.name
                    end
                end
                local model = trim_string(modelSource)
                if model then
                    push({
                        vehicle = true,
                        model = model,
                        metadata = reward.metadata,
                        plate = reward.plate
                    })
                end
            end
        end
    end

    return normalized, totalItems
end

      function getCachedQuery(key)
    local cached = _queryCache[key]
    if cached and (os.time() - cached.timestamp) < _cacheExpiry then
        return cached.data
    end
    return nil
end

      function setCachedQuery(key, data)
    _queryCache[key] = {
        data = data,
        timestamp = os.time()
    }
end

      function cleanCache()
    local now = os.time()
    for key, cached in pairs(_queryCache) do
        if (now - cached.timestamp) > _cacheExpiry then
            _queryCache[key] = nil
        end
    end
end

local _reusableObjects = {
    emptyArray = {},
    emptyObject = {}
}

      function optimizedJsonEncode(data)
    if data == nil then
        return "null"
    elseif type(data) == "table" then
        if next(data) == nil then
            return "{}"
        end
    end
    return json_encode(data)
end

      function logMemoryUsage(context)
    if Config.Debug then
        local memUsage = collectgarbage("count")
        print(string.format("[midnight_redeem] Memory usage (%s): %.2f KB", context, memUsage))
    end
end

      function sanitizeNumbersForJSON(value)
    if type(value) == 'table' then
        local newTable = {}
        for k, v in pairs(value) do
            newTable[k] = sanitizeNumbersForJSON(v)
        end
        return newTable
    elseif type(value) == 'number' then
        if value ~= value then
            return 0
        elseif value == math.huge then
            return 0
        elseif value == -math.huge then
            return 0
        end
    end
    return value
end

function getDashboardStats()
    local success, result = pcall(function()
        local statsQuery = MySQL.query.await([[
            SELECT 
                COUNT(*) as total,
                SUM(CASE WHEN uses <= 0 THEN 1 ELSE 0 END) as full,
                SUM(CASE WHEN expiry IS NOT NULL 
                         AND expiry != 'Never' 
                         AND (
                             (expiry > 1000000000000 AND FLOOR(expiry / 1000) <= UNIX_TIMESTAMP(NOW())) OR 
                             (expiry <= 1000000000000 AND expiry <= UNIX_TIMESTAMP(NOW())) OR
                             (expiry REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' AND expiry <= NOW())
                         ) THEN 1 ELSE 0 END) as expired,
                SUM(CASE WHEN unlimited = 1 THEN 1 ELSE 0 END) as unlimited
            FROM midnight_codes
        ]])
        
        if not statsQuery or #statsQuery == 0 then
            return { total = 0, full = 0, expired = 0, active = 0, unlimited = 0, recent = {} }
        end
        
        local stats = statsQuery[1]
        local total = stats.total or 0
        local full = stats.full or 0
        local expired = stats.expired or 0
        local unlimited = stats.unlimited or 0
        local active = total - (full + expired)
        
        local recentCodes = MySQL.query.await([[
            SELECT code, uses, expiry, created_by, created_at, 
                   COALESCE(updated_at, created_at) as updated_at,
                   CASE 
                       WHEN updated_at IS NOT NULL AND updated_at > created_at THEN updated_at
                       ELSE created_at 
                   END as sort_time
            FROM midnight_codes 
            ORDER BY sort_time DESC 
            LIMIT 20
        ]]) or {}
        
        local recent = {}
        for _, code in ipairs(recentCodes) do
            local status = "Active"
            if code.uses <= 0 then
                status = "Fully Redeemed"
            elseif code.expiry and code.expiry ~= "Never" then
                local expiryTime = nil
                if type(code.expiry) == "number" then
                    expiryTime = code.expiry > 1000000000000 and math.floor(code.expiry / 1000) or code.expiry
                elseif type(code.expiry) == "string" and code.expiry:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$") then
                    expiryTime = os.time(os.date("*t", code.expiry))
                end
                
                if expiryTime and expiryTime <= os.time() then
                    status = "Expired"
                end
            end
            
            local createdTime = "N/A"
            if code.created_at then
                if type(code.created_at) == "string" then
                    createdTime = code.created_at
                elseif type(code.created_at) == "number" then
                    local timestamp = code.created_at > 1000000000000 and math.floor(code.created_at / 1000) or code.created_at
                    local success, formatted = pcall(os.date, "%m/%d/%Y, %H:%M", timestamp)
                    createdTime = success and formatted or "N/A"
                end
            end
            
            local updatedTime = "N/A"
            if code.updated_at and code.updated_at ~= code.created_at then
                if type(code.updated_at) == "string" then
                    updatedTime = code.updated_at
                elseif type(code.updated_at) == "number" then
                    local timestamp = code.updated_at > 1000000000000 and math.floor(code.updated_at / 1000) or code.updated_at
                    local success, formatted = pcall(os.date, "%m/%d/%Y, %H:%M", timestamp)
                    updatedTime = success and formatted or "N/A"
                end
            end
            
            table.insert(recent, {
                code = code.code or "?",
                uses = code.uses or 0,
                status = status,
                creator = code.created_by or "Unknown",
                created = createdTime,
                edited = updatedTime,
                expiry = code.expiry or "Never"
            })
        end
        
        return {
            total = total,
            full = full,
            expired = expired,
            active = active,
            unlimited = unlimited,
            recent = recent
        }
    end)
    
    if not success then
        return { total = 0, full = 0, expired = 0, active = 0, unlimited = 0, recent = {} }
    end
    
    return result
end

function getWeeklyStats()
    local success, result = pcall(function()
        local now = os.time()
        local sevenDaysAgo = now - (7 * 24 * 60 * 60)
        local fourteenDaysAgo = now - (14 * 24 * 60 * 60)
        local twentyOneDaysAgo = now - (21 * 24 * 60 * 60)
        local nowMs = now * 1000

        local function calculateChange(current, previous)
            if previous == 0 then
                return current > 0 and 100 or 0
            end
            return math.floor(((current - previous) / previous) * 100)
        end

        local function isExpiryActive(expiry)
            if expiry == nil or expiry == '' or expiry == 'Never' then
                return true
            end
            if type(expiry) == 'number' then
                local expirySec = expiry > 1000000000000 and math.floor(expiry / 1000) or expiry
                return expirySec > now
            end
            if type(expiry) == 'string' then
                local y, m, d, h, mi, s = expiry:match('(%d+)-(%d+)-(%d+)%s+(%d+):(%d+):(%d+)')
                if y then
                    return os.time({
                        year = tonumber(y), month = tonumber(m), day = tonumber(d),
                        hour = tonumber(h), min = tonumber(mi), sec = tonumber(s)
                    }) > now
                end
                local expiryNum = tonumber(expiry)
                if expiryNum then
                    local expirySec = expiryNum > 1000000000000 and math.floor(expiryNum / 1000) or expiryNum
                    return expirySec > now
                end
            end
            return true
        end

        local function createdAtToUnix(createdAt)
            if type(createdAt) == 'number' then
                return createdAt > 1000000000000 and math.floor(createdAt / 1000) or createdAt
            end
            if type(createdAt) == 'string' then
                local y, m, d, h, mi, s = createdAt:match('(%d+)-(%d+)-(%d+)%s+(%d+):(%d+):(%d+)')
                if y then
                    return os.time({
                        year = tonumber(y), month = tonumber(m), day = tonumber(d),
                        hour = tonumber(h), min = tonumber(mi), sec = tonumber(s)
                    })
                end
            end
            return nil
        end

        local thisWeekGenerated = MySQL.scalar.await([[
            SELECT COUNT(*) FROM midnight_codes
            WHERE created_at >= FROM_UNIXTIME(?)
        ]], { sevenDaysAgo }) or 0

        local lastWeekGenerated = MySQL.scalar.await([[
            SELECT COUNT(*) FROM midnight_codes
            WHERE created_at >= FROM_UNIXTIME(?) AND created_at < FROM_UNIXTIME(?)
        ]], { fourteenDaysAgo, sevenDaysAgo }) or 0

        local lastTwoWeeksGenerated = MySQL.scalar.await([[
            SELECT COUNT(*) FROM midnight_codes
            WHERE created_at >= FROM_UNIXTIME(?)
        ]], { fourteenDaysAgo }) or 0

        local previousTwoWeeksGenerated = MySQL.scalar.await([[
            SELECT COUNT(*) FROM midnight_codes
            WHERE created_at >= FROM_UNIXTIME(?) AND created_at < FROM_UNIXTIME(?)
        ]], { twentyOneDaysAgo, fourteenDaysAgo }) or 0

        local allCodesForActive = MySQL.query.await([[
            SELECT code, expiry, unlimited, uses, created_at FROM midnight_codes
            WHERE (unlimited = 1 OR uses > 0)
        ]]) or {}

        local currentWeekActive = 0
        local previousWeekActive = 0
        for _, code in ipairs(allCodesForActive) do
            if isExpiryActive(code.expiry) then
                currentWeekActive = currentWeekActive + 1
            end
            local createdUnix = createdAtToUnix(code.created_at)
            if createdUnix and createdUnix >= fourteenDaysAgo and createdUnix < sevenDaysAgo and isExpiryActive(code.expiry) then
                previousWeekActive = previousWeekActive + 1
            end
        end

        local currentWeekRedeemed = MySQL.scalar.await([[
            SELECT COUNT(*) FROM midnight_codes
            WHERE created_at >= FROM_UNIXTIME(?)
            AND unlimited = 0 AND uses <= 0
        ]], { sevenDaysAgo }) or 0

        local allCodes = MySQL.query.await([[
            SELECT code, expiry, created_at FROM midnight_codes
            WHERE expiry IS NOT NULL AND expiry != 'Never'
        ]]) or {}

        local currentWeekExpired = 0
        for _, code in ipairs(allCodes) do
            if not isExpiryActive(code.expiry) then
                local createdUnix = createdAtToUnix(code.created_at)
                if createdUnix and createdUnix >= sevenDaysAgo then
                    currentWeekExpired = currentWeekExpired + 1
                end
            end
        end

        local previousWeekRedeemed = MySQL.scalar.await([[
            SELECT COUNT(*) FROM midnight_codes
            WHERE created_at >= FROM_UNIXTIME(?) AND created_at < FROM_UNIXTIME(?)
            AND unlimited = 0 AND uses <= 0
        ]], { fourteenDaysAgo, sevenDaysAgo }) or 0

        local previousWeekExpired = 0
        for _, code in ipairs(allCodes) do
            if not isExpiryActive(code.expiry) then
                local createdUnix = createdAtToUnix(code.created_at)
                if createdUnix and createdUnix >= fourteenDaysAgo and createdUnix < sevenDaysAgo then
                    previousWeekExpired = previousWeekExpired + 1
                end
            end
        end

        return {
            generated = {
                current = lastTwoWeeksGenerated,
                previous = previousTwoWeeksGenerated,
                change = calculateChange(lastTwoWeeksGenerated, previousTwoWeeksGenerated)
            },
            thisWeek = {
                current = thisWeekGenerated,
                previous = lastWeekGenerated,
                change = calculateChange(thisWeekGenerated, lastWeekGenerated)
            },
            lastWeek = {
                current = lastWeekGenerated,
                previous = previousTwoWeeksGenerated,
                change = calculateChange(lastWeekGenerated, previousTwoWeeksGenerated)
            },
            active = {
                current = currentWeekActive,
                previous = previousWeekActive,
                change = calculateChange(currentWeekActive, previousWeekActive)
            },
            redeemed = {
                current = currentWeekRedeemed,
                previous = previousWeekRedeemed,
                change = calculateChange(currentWeekRedeemed, previousWeekRedeemed)
            },
            expired = {
                current = currentWeekExpired,
                previous = previousWeekExpired,
                change = calculateChange(currentWeekExpired, previousWeekExpired)
            }
        }
    end)

    local emptyWeekly = {
        generated = { current = 0, previous = 0, change = 0 },
        thisWeek = { current = 0, previous = 0, change = 0 },
        lastWeek = { current = 0, previous = 0, change = 0 },
        active = { current = 0, previous = 0, change = 0 },
        redeemed = { current = 0, previous = 0, change = 0 },
        expired = { current = 0, previous = 0, change = 0 }
    }

    if not success then
        if Config.Debug then
            print('[midnight_redeem] getWeeklyStats failed:', result)
        end
        return emptyWeekly
    end

    return result or emptyWeekly
end

function getDailyStats()
    local success, result = pcall(function()
        local now = os.time()
        local currentWeekStart = getWeekStart(now)
        local previousWeekStart = currentWeekStart - (7 * 24 * 60 * 60)
        local currentWeekEnd = currentWeekStart + (7 * 24 * 60 * 60)

        local mysqlDowToDay = {
            [1] = "sunday",
            [2] = "monday",
            [3] = "tuesday",
            [4] = "wednesday",
            [5] = "thursday",
            [6] = "friday",
            [7] = "saturday"
        }

        local dailyStats = {}
        for _, day in ipairs({"monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"}) do
            dailyStats[day] = { current = 0, previous = 0, change = 0 }
        end

        local currentRows = MySQL.query.await([[
            SELECT DAYOFWEEK(created_at) as dow, COUNT(*) as cnt
            FROM midnight_codes
            WHERE created_at >= FROM_UNIXTIME(?) AND created_at < FROM_UNIXTIME(?)
            GROUP BY DAYOFWEEK(created_at)
        ]], { currentWeekStart, currentWeekEnd }) or {}

        local previousRows = MySQL.query.await([[
            SELECT DAYOFWEEK(created_at) as dow, COUNT(*) as cnt
            FROM midnight_codes
            WHERE created_at >= FROM_UNIXTIME(?) AND created_at < FROM_UNIXTIME(?)
            GROUP BY DAYOFWEEK(created_at)
        ]], { previousWeekStart, currentWeekStart }) or {}

        for _, row in ipairs(currentRows) do
            local day = mysqlDowToDay[tonumber(row.dow)]
            if day then
                dailyStats[day].current = tonumber(row.cnt) or 0
            end
        end

        for _, row in ipairs(previousRows) do
            local day = mysqlDowToDay[tonumber(row.dow)]
            if day then
                dailyStats[day].previous = tonumber(row.cnt) or 0
            end
        end

        for _, day in ipairs({"monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"}) do
            local entry = dailyStats[day]
            if entry.previous > 0 then
                entry.change = math.floor(((entry.current - entry.previous) / entry.previous) * 100)
            elseif entry.current > 0 then
                entry.change = 100
            end
        end

        return dailyStats
    end)
    
    if not success then
        return {
            monday = { current = 0, previous = 0, change = 0 },
            tuesday = { current = 0, previous = 0, change = 0 },
            wednesday = { current = 0, previous = 0, change = 0 },
            thursday = { current = 0, previous = 0, change = 0 },
            friday = { current = 0, previous = 0, change = 0 },
            saturday = { current = 0, previous = 0, change = 0 },
            sunday = { current = 0, previous = 0, change = 0 }
        }
    end
    
    return result
end

function getAllCodesWithDetails()
    local success, result = pcall(function()
        local results = MySQL.query.await([[
            SELECT code, uses, expiry, items, per_user_limit, created_by, created_at, updated_at, redeemed_by, unlimited, restricted_to_enabled, restricted_to_type, restricted_to_value
            FROM midnight_codes 
            ORDER BY created_at DESC
        ]]) or {}
        
        
        local codes = {}
        for _, row in ipairs(results) do
            table.insert(codes, slimCodeListRow(row, false))
        end
        
        return codes
    end)
    
    if not success then
        return {}
    end
    
    return result
end

function getAllCodesForSearch()
    local success, result = pcall(function()
        local results = MySQL.query.await([[
            SELECT code, uses, expiry, items, per_user_limit, created_by, created_at, updated_at, redeemed_by, unlimited, restricted_to_enabled, restricted_to_type, restricted_to_value
            FROM midnight_codes 
            ORDER BY created_at DESC
        ]]) or {}
        
        local codes = {}
        for _, row in ipairs(results) do
            table.insert(codes, slimCodeListRow(row, false))
        end
        
        return codes
    end)
    
    if not success then
        return {}
    end
    
    return result
end

function getRewardsStats()
    local success, result = pcall(function()
        local topRewards = MySQL.query.await([[
            SELECT 
                reward_type,
                reward_name,
                reward_amount,
                redemption_count,
                last_redeemed
            FROM midnight_redeem_stats
            ORDER BY redemption_count DESC
            LIMIT 10
        ]]) or {}
        
        local stats = {
            topItems = {},
            topMoney = {},
            topVehicles = {},
            topOverall = {}
        }
        
        for _, row in ipairs(topRewards) do
            local rewardData = {
                name = row.reward_name,
                amount = row.reward_amount,
                count = row.redemption_count,
                lastRedeemed = row.last_redeemed
            }
            
            if row.reward_type == "item" and #stats.topItems < 3 then
                table.insert(stats.topItems, rewardData)
            elseif row.reward_type == "money" and #stats.topMoney < 3 then
                table.insert(stats.topMoney, rewardData)
            elseif row.reward_type == "vehicle" and #stats.topVehicles < 3 then
                table.insert(stats.topVehicles, rewardData)
            end
            
            if #stats.topOverall < 3 then
                table.insert(stats.topOverall, rewardData)
            end
        end
        
        return stats
    end)
    
    if not success then
        return {
            topItems = {},
            topMoney = {},
            topVehicles = {},
            topOverall = {}
        }
    end
    
    return result
end

function refreshDashboardData(source)
    if _refreshPending then
        return
    end
    _refreshPending = true
    _isRefreshing = true
    _dashboardData.lastRefresh = os.time()
    
    CreateThread(function()
        local success, result = pcall(function()
            _dashboardData.stats = getDashboardStats()
            
            _dashboardData.weekly = sanitizeNumbersForJSON(getWeeklyStats())
            _dashboardData.daily = sanitizeNumbersForJSON(getDailyStats())
            _dashboardData.codes = getAllCodesWithDetails()
            _dashboardData.allCodes = getAllCodesForSearch()
            _dashboardData.rewards = getRewardsStats()
        end)
        
        if not success then
            _dashboardData.stats = { total = 0, full = 0, expired = 0, active = 0, unlimited = 0, recent = {} }
            _dashboardData.weekly = {
                generated = { current = 0, previous = 0, change = 0 },
                thisWeek = { current = 0, previous = 0, change = 0 },
                lastWeek = { current = 0, previous = 0, change = 0 },
                active = { current = 0, previous = 0, change = 0 },
                redeemed = { current = 0, previous = 0, change = 0 },
                expired = { current = 0, previous = 0, change = 0 }
            }
            _dashboardData.daily = { monday = { current = 0, previous = 0, change = 0 }, tuesday = { current = 0, previous = 0, change = 0 }, wednesday = { current = 0, previous = 0, change = 0 }, thursday = { current = 0, previous = 0, change = 0 }, friday = { current = 0, previous = 0, change = 0 }, saturday = { current = 0, previous = 0, change = 0 }, sunday = { current = 0, previous = 0, change = 0 } }
            _dashboardData.codes = {}
            _dashboardData.allCodes = {}
            _dashboardData.rewards = { topItems = {}, topMoney = {}, topVehicles = {}, topOverall = {} }
        end
        
        _isRefreshing = false
        _refreshPending = false
        
        cleanCache()
    end)
end

      function sanitizeForJSON(data)
    if type(data) == "table" then
        local sanitized = {}
        for k, v in pairs(data) do
            if type(k) == "string" or type(k) == "number" then
                sanitized[k] = sanitizeForJSON(v)
            end
        end
        return sanitized
    elseif type(data) == "string" then
        return data
    elseif type(data) == "number" then
        return data
    elseif type(data) == "boolean" then
        return data
    else
        return tostring(data or "")
    end
end


      function _getConfiguredTimesInMinutes()
    local currentTime = os.time()
    

    if _timeCache.times and currentTime < _cacheExpiry then
        return _timeCache.times
    end
    
    local raw = Config.RewardTimes or { Config.RewardTime }
    local out, seen = {}, {}
    if type(raw) ~= "table" then raw = { raw } end
    for _, v in ipairs(raw) do
        local mins = _toMinutes(v)
        if mins and not seen[mins] then
            table.insert(out, mins)
            seen[mins] = true
        end
    end
    table.sort(out)
    

    _timeCache.times = out
    _cacheExpiry = currentTime + _cacheDuration
    
    return out
end

      function _nowMinutes()
    local t = os.date("*t")
    return t.hour * 60 + t.min
end


      function build_reward_lines(items)
    local lines = {}
    for _, r in ipairs(items or {}) do
        if r.item then
            insert(lines, fmt("📦 %dx %s", r.amount or 1, r.item))
        elseif r.money then
            insert(lines, fmt("💰 $%s (%s)", r.amount or 0, r.option or "cash"))
        elseif r.vehicle then
            insert(lines, fmt("🚗 Vehicle: %s", r.model or "Unknown"))
        end
    end
    return lines, (next(lines) and concat(lines, "\n") or "None")
end

      function parse_expiry_flexible(expiryFlexible)
    if expiryFlexible == nil then return nil end
    local t = type(expiryFlexible)
    if t == "number" then
        if expiryFlexible > 0 then
            return os.date("%Y-%m-%d %H:%M:%S", os.time() + (expiryFlexible * 86400))
        else
            return nil
        end
    elseif t == "string" then
        if #expiryFlexible >= 19 and expiryFlexible:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$") then
            return expiryFlexible
        end
        local maybeDays = tonumber(expiryFlexible)
        if maybeDays and maybeDays > 0 then
            return os.date("%Y-%m-%d %H:%M:%S", os.time() + (maybeDays * 86400))
        end
    end
    return nil
end

function CheckExpiredUnusedCodes()
    local now = os.date("%Y-%m-%d %H:%M:%S")
    local results = MySQL.query.await([[
        SELECT code, items, expiry, uses
        FROM midnight_codes
        WHERE expiry IS NOT NULL
          AND expiry <= ?
          AND uses > 0
          AND expired_notified = 0
    ]], { now })
    if not results or #results == 0 then return end

    local toMark = {}
    for _, row in ipairs(results) do
        local items = safe_json_decode(row.items, {})
        local _, rewardText = build_reward_lines(items)

        local expiryDisplay = row.expiry
        if tonumber(expiryDisplay) then
            expiryDisplay = math.floor(tonumber(expiryDisplay) / 1000)
            expiryDisplay = os.date("%Y-%m-%d %H:%M:%S", expiryDisplay)
        end

        local msg = fmt("**Code:** `%s`\n**Expired:** `%s`\n**Uses Left:** `%s`\n\n**Rewards:**\n%s\n\n*This code expired without being fully used!*",
            row.code, expiryDisplay or "N/A", row.uses, rewardText)
        SendToDiscord("Code Expired & Unused", msg, 15158332)
        insert(toMark, row.code)
    end

    if #toMark > 0 then
        local placeholders = {}
        for i=1,#toMark do placeholders[i] = "?" end
        MySQL.query.await("UPDATE midnight_codes SET expired_notified = 1 WHERE code IN (" .. table.concat(placeholders, ",") .. ")", toMark)
    end
end

RegisterServerEvent("midnight-redeem:deleteCode", function(code)
    local src = source
    
    if not requireAdmin(src, "DELETE_CODES") then
        TriggerClientEvent("midnight-redeem:sendUIToast", src, "Delete Code", "You don't have permission to delete codes.", "error")
        return
    end

    local affected = MySQL.update.await('DELETE FROM midnight_codes WHERE code = ?', { code })
    
    if (affected or 0) > 0 then
        refreshDashboardData(nil)
        broadcastDashboardAfterRefresh(src)
        
        TriggerClientEvent("midnight-redeem:sendUIToast", src, "Delete Code", locales("NOTIFY_CODE_DELETED", code), "success")
        SendToDiscord("Code Deleted", string.format("**Code:** `%s`\n**admin** `%s`.", code, GetPlayerName(src)), 15158332)
    else
        TriggerClientEvent("midnight-redeem:sendUIToast", src, "Delete Code", locales("NOTIFY_CODE_NOT_FOUND", code), "error")
    end
end)

RegisterServerEvent("midnight-redeem:deleteTranscript", function(sessionId)
    local src = source
    if Config and Config.AIEnabled == false then
        TriggerClientEvent("midnight-redeem:sendUIToast", src, "Delete Transcript", "Shadow is disabled.", "error")
        return
    end
    
    if not sessionId or sessionId == "" then
        TriggerClientEvent("midnight-redeem:sendUIToast", src, "Delete Transcript", "Invalid session ID", "error")
        return
    end
    
    if not requireAdmin(src, "VIEW_TRANSCRIPTS") then
        TriggerClientEvent("midnight-redeem:sendUIToast", src, "Delete Transcript", "You don't have permission to delete transcripts.", "error")
        return
    end
    
    -- Verify session exists
    local session = MySQL.query.await('SELECT identifier, player_name FROM midnight_ai_chat_sessions WHERE session_id = ? LIMIT 1', { sessionId })
    if not session or not session[1] then
        TriggerClientEvent("midnight-redeem:sendUIToast", src, "Delete Transcript", "Transcript session not found", "error")
        return
    end
    
    local playerName = session[1].player_name or "Unknown"
    
    -- Delete messages first (due to foreign key constraint or to clean up)
    local messagesDeleted = MySQL.update.await('DELETE FROM midnight_ai_chat_messages WHERE session_id = ?', { sessionId })
    
    -- Delete session
    local sessionDeleted = MySQL.update.await('DELETE FROM midnight_ai_chat_sessions WHERE session_id = ?', { sessionId })
    
    if (sessionDeleted or 0) > 0 then
        TriggerClientEvent("midnight-redeem:sendUIToast", src, "Delete Transcript", string.format("Transcript session %s deleted successfully", sessionId), "success")
        SendToDiscord("Transcript Deleted", string.format("**Session ID:** `%s`\n**Player:** `%s`\n**Messages Deleted:** `%d`\n**Deleted by:** `%s`", sessionId, playerName, messagesDeleted or 0, GetPlayerName(src)), 15158332)
    else
        TriggerClientEvent("midnight-redeem:sendUIToast", src, "Delete Transcript", "Failed to delete transcript session", "error")
    end
end)

local function normalizeIdentifierValue(identifierType, identifierValue)
    local value = tostring(identifierValue or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local kind = tostring(identifierType or ""):lower()
    if kind == "license" and value ~= "" and not value:find("^license:") then
        value = "license:" .. value
    elseif kind == "license2" and value ~= "" and not value:find("^license2:") then
        value = "license2:" .. value
    end
    return value
end

local function parsePlayerRestriction(raw)
    if type(raw) ~= "table" then
        return { enabled = false, type = nil, value = nil }
    end
    local enabled = raw.enabled == true or raw.enabled == 1
    local kind = tostring(raw.type or ""):lower()
    local value = normalizeIdentifierValue(kind, raw.value)
    if not enabled or kind == "" or value == "" then
        return { enabled = false, type = nil, value = nil }
    end
    if kind ~= "citizenid" and kind ~= "characterid" and kind ~= "license" and kind ~= "license2" then
        return { enabled = false, type = nil, value = nil }
    end
    return { enabled = true, type = kind, value = value }
end

local function getPlayerIdentifiersForRestriction(source)
    local identifiers = {
        citizenid = nil,
        characterid = nil,
        license = nil,
        license2 = nil
    }

    local allIds = GetPlayerIdentifiers(source) or {}
    for _, id in ipairs(allIds) do
        if type(id) == "string" then
            if id:find("^license2:") and not identifiers.license2 then
                identifiers.license2 = id
            elseif id:find("^license:") and not identifiers.license then
                identifiers.license = id
            end
        end
    end

    local playerData = Bridge.Framework.GetPlayer(source)
    if type(playerData) == "table" then
        identifiers.citizenid = playerData.citizenid or playerData.citizenId or playerData.cid or playerData.identifier
        identifiers.characterid = playerData.characterid or playerData.characterId or playerData.charid
    end

    return identifiers
end

local function playerMatchesRestriction(source, restrictionType, restrictionValue)
    if not restrictionType or not restrictionValue then
        return true
    end
    local ids = getPlayerIdentifiersForRestriction(source)
    local playerValue = ids[restrictionType]
    if not playerValue then
        return false
    end
    return tostring(playerValue):lower() == normalizeIdentifierValue(restrictionType, restrictionValue):lower()
end

local function enforcePlayerRestrictionForRow(src, row)
    local enabled = row.restricted_to_enabled == 1 or row.restricted_to_enabled == true
    if not enabled then
        return true, nil
    end
    local restrictionType = tostring(row.restricted_to_type or "")
    local restrictionValue = tostring(row.restricted_to_value or "")
    if restrictionType == "" or restrictionValue == "" then
        return true, nil
    end
    if not playerMatchesRestriction(src, restrictionType, restrictionValue) then
        return false, locales("NOTIFY_CODE_NOT_FOR_YOU") or "This code is restricted to another player."
    end
    return true, nil
end

function HandleRedeemCode(source, itemsJson, uses, expiryFlexible, customCode, perUserLimit, createdByOverride, timeRestrictions, playerRestriction)
    local hasPlayer = (type(source) == "number" and source > 0)

    if hasPlayer and not AdminHasPermission(source, "CREATE_CODES") then
        local message = GetRequirePermission()
            and "You don't have permission to create codes. Contact an owner/manager for access."
            or (locales("NOTIFY_PERMISSION_DENIED") or "Permission denied.")
        Bridge.Notify.SendNotify(source, message, "error", 6000)
        return
    end
    
    local playerName = createdByOverride
                      or (hasPlayer and (GetPlayerName(source) or "ingame moderator"))
                      or "discord admin"

    if customCode and customCode ~= "" then
        local nameOk, issues = validateNewCodeName(customCode)
        if not nameOk then
            ContentFilter.logFilteredAttempt(source, customCode, table.concat(issues, ", "))
            if hasPlayer then
                return Bridge.Notify.SendNotify(source, "Code creation failed: " .. table.concat(issues, ", "), "error", 6000)
            end
            return
        end
    end

    local ok, itemsTable = pcall(json_decode, itemsJson)
    if not ok or type(itemsTable) ~= "table" then
        if hasPlayer then
            return Bridge.Notify.SendNotify(source, locales("NOTIFY_INVALID_ITEM_DATA"), "error", 6000)
        else
            return
        end
    end

    local rewards = (type(itemsTable[1]) == "table") and itemsTable or { itemsTable }
    local rewardsOk, rewardsErr = validateRewardsPayload(rewards)
    if not rewardsOk then
        if hasPlayer then
            return Bridge.Notify.SendNotify(source, rewardsErr or "Invalid rewards.", "error", 6000)
        end
        return
    end

    uses = tonumber(uses)
    if not uses or uses <= 0 then
        if hasPlayer then
            return Bridge.Notify.SendNotify(source, locales("NOTIFY_INVALID_USES"), "error", 6000)
        else
            return
        end
    end

    local expiryDate = parse_expiry_flexible(expiryFlexible)
    local expiryRawUnix = nil
    do
        local days = tonumber(expiryFlexible)
        if days ~= nil then
            if days > 0 then
                expiryRawUnix = os.time() + (days * 86400)
            else
                expiryRawUnix = nil
            end
        else
            local ts = iso_to_unix(expiryDate or expiryFlexible)
            ts = ts and tonumber(ts) or nil
            if ts and ts > 9999999999 then ts = math.floor(ts / 1000) end
            expiryRawUnix = ts
        end
    end

    if expiryRawUnix and expiryRawUnix <= os.time() then
        local msg = (locales and (locales("NOTIFY_EXPIRY_IN_PAST") or nil)) or "The expiry date/time is already in the past."
        if hasPlayer then
            return Bridge.Notify.SendNotify(source, msg, "error", 6000)
        else
            return
        end
    end

    perUserLimit = tonumber(perUserLimit)
    if perUserLimit == nil or perUserLimit < 0 then perUserLimit = 1 end

    local totalItemCount = 0
    for _, reward in ipairs(rewards) do
        if reward.item then
            totalItemCount = totalItemCount + (tonumber(reward.amount) or 0)
        end
    end

    local restriction = parsePlayerRestriction(playerRestriction)

    local timeLocked = 0
    local timeRestrictionsJson = nil
    local timeRestrictionsActive = 0
    local cycleBasedLimit = 0
    
    if timeRestrictions and timeRestrictions.enabled then
        timeLocked = 1
        timeRestrictionsActive = 1
        
        
        timeRestrictionsJson = json_encode(timeRestrictions)
        
        if timeRestrictions.cycle_based_limit then
            cycleBasedLimit = 1
        end
    end
    
    local redeemedByJson = json_encode({})
    local userCycleRedemptionsJson = json_encode({})
    
    if redeemedByJson == "[]" then
        redeemedByJson = "{}"
    end
    if userCycleRedemptionsJson == "[]" then
        userCycleRedemptionsJson = "{}"
    end
    
    
    local insertId = MySQL.insert.await(
        'INSERT INTO midnight_codes (code, total_item_count, items, uses, created_by, expiry, redeemed_by, expired_notified, per_user_limit, restricted_to_enabled, restricted_to_type, restricted_to_value, time_locked, time_restrictions, time_restrictions_active, cycle_based_limit, user_cycle_redemptions, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW())',
        { customCode, totalItemCount, itemsJson, uses, playerName, expiryDate, redeemedByJson, perUserLimit, restriction.enabled and 1 or 0, restriction.type, restriction.value, timeLocked, timeRestrictionsJson, timeRestrictionsActive, cycleBasedLimit, userCycleRedemptionsJson }
    )

    if insertId then
        refreshDashboardData(nil)
        broadcastDashboardAfterRefresh(source)

        local _, rewardText = build_reward_lines(rewards)

        local expiryHuman
        if not expiryRawUnix then
            expiryHuman = "Never"
        else
            local ts = math.floor(expiryRawUnix)
            expiryHuman = "<t:" .. ts .. ":f> (<t:" .. ts .. ":R>)"
        end

        local perUserHuman = (perUserLimit == 0) and "Unlimited" or tostring(perUserLimit)

        local timeRestrictionsInfo = ""
        if timeRestrictions and timeRestrictions.enabled then
            local restrictions = timeRestrictions.restrictions or {}
            local restrictionText = ""
            
            if timeRestrictions.type == "daily_hours" then
                restrictionText = string.format("Daily: %02d:00 - %02d:00", 
                    restrictions.start_hour or 0, restrictions.end_hour or 23)
            elseif timeRestrictions.type == "weekly_days" then
                local dayNames = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}
                local days = {}
                for _, dayNum in ipairs(restrictions.allowed_days or {}) do
                    table.insert(days, dayNames[dayNum] or "Unknown")
                end
                restrictionText = "Weekly: " .. table.concat(days, ", ")
            elseif timeRestrictions.type == "specific_dates" then
                restrictionText = "Specific dates: " .. table.concat(restrictions.specific_dates or {}, ", ")
            elseif timeRestrictions.type == "recurring" then
                restrictionText = string.format("Recurring: %s - %s", 
                    restrictions.recurring_type or "daily", restrictions.recurring_pattern or "Every day")
            end
            
            timeRestrictionsInfo = string.format("\n**Time Restrictions:** `%s`", restrictionText)
            
            if timeRestrictions.cycle_based_limit then
                timeRestrictionsInfo = timeRestrictionsInfo .. "\n**Cycle-Based Limit:** `User limit resets after each cycle`"
            end
            
            if timeRestrictions.message and timeRestrictions.message ~= "" then
                timeRestrictionsInfo = timeRestrictionsInfo .. string.format("\n**Custom Message:** `%s`", timeRestrictions.message)
            end
        end

        local message = string.format(
            "**Admin:** `%s`\n**Code:** `%s`\n**Uses:** `%s`\n**Per-User Limit:** `%s`\n**Expiry:** %s%s\n\n**Rewards:**\n%s",
            playerName, customCode, uses, perUserHuman, expiryHuman, timeRestrictionsInfo, rewardText
        )

        SendToDiscord("Redeem Code Created", message, 3066993, nil, "admin")

        return true
    else
        if hasPlayer then
            Bridge.Notify.SendNotify(source, locales("NOTIFY_FAILED_INSERT"), "error", 6000)
        end
        return false
    end
end

      function CreateRedeemCodeDirectly(code, itemsJson, uses, expiryDays, perUserLimit, createdBy)
    local ok, itemsTable = pcall(json_decode, itemsJson)
    if not ok or type(itemsTable) ~= "table" then
        return false
    end

    uses = tonumber(uses)
    if not uses or uses <= 0 then
        return false
    end

    perUserLimit = tonumber(perUserLimit)
    if perUserLimit == nil or perUserLimit < 0 then perUserLimit = 1 end

    local rewards = (type(itemsTable[1]) == "table") and itemsTable or { itemsTable }

    local totalItemCount = 0
    for _, reward in ipairs(rewards) do
        if reward.item then
            totalItemCount = totalItemCount + (tonumber(reward.amount) or 0)
        end
    end

    local expiryDate = nil
    if expiryDays and expiryDays > 0 then
        local currentTime = os.time()
        local expiryTime = currentTime + (expiryDays * 86400)
        expiryDate = os.date("%Y-%m-%d %H:%M:%S", expiryTime)
    end

    local insertId = MySQL.insert.await(
        'INSERT INTO midnight_codes (code, total_item_count, items, uses, created_by, expiry, redeemed_by, expired_notified, per_user_limit, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, NOW(), NOW())',
        { code, totalItemCount, itemsJson, uses, createdBy, expiryDate, json_encode({}), perUserLimit }
    )

    if insertId then
        return true
    else
        return false
    end
end


RegisterServerEvent("midnight-redeem:generateCode", function(itemsJson, uses, expiryDays, customCode, perUserLimit, timeRestrictions, playerRestriction)
    local src = source
    if not requireAdmin(src, "CREATE_CODES") then
        return Bridge.Notify.SendNotify(src, locales("NOTIFY_PERMISSION_DENIED"), "error", 6000)
    end
    HandleRedeemCode(src, itemsJson, uses, expiryDays, customCode, perUserLimit, nil, timeRestrictions, playerRestriction)
end)


function GetFrameworkVersion()
    if GetResourceState('qb-core') == 'started' then
        return 'qb'
    elseif GetResourceState('qbx-core') == 'started' then
        return 'qbx'

    elseif GetResourceState('es_extended') == 'started' then
        return 'esx'
    else
        print('Unknown framework')
        return 'unknown'
    end
end

function addVehicleToGarage(model, playerName, ownerIdentifier)
    if not model or not ownerIdentifier then return nil end

    local fw = string.lower(GetFrameworkVersion() or "")

    local letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local plate = ""

    plate = plate .. string.format("%02d", math.random(0, 99))

    for i = 1, 3 do
        local randomIndex = math.random(1, #letters)
        plate = plate .. string.sub(letters, randomIndex, randomIndex)
    end

    plate = plate .. string.format("%03d", math.random(0, 999))
    local primaryColor = math.random(0, 160)
    local secondaryColor = math.random(0, 160)
    local pearlescentColor = math.random(0, 160)
    local wheelColor = math.random(0, 160)
    
    local props = {
        model = GetHashKey(model),
        plate = plate,
        color1 = primaryColor,
        color2 = secondaryColor,
        pearlescentColor = pearlescentColor,
        wheelColor = wheelColor
    }

    local parking, stored, vtype = "legion", 1, "car"

    if fw == "esx" or fw == "es_extended" then
        local success = pcall(function()
            MySQL.query.await(
                'INSERT INTO `owned_vehicles` (owner, plate, vehicle, type, job, parking, stored) VALUES (?, ?, ?, ?, ?, ?, ?)',
                { ownerIdentifier, plate, json.encode(props), vtype, nil, parking, stored }
            )
        end)
        
        if not success then
            local cdGarageSuccess = pcall(function()
                MySQL.query.await(
                    'INSERT INTO `owned_vehicles` (owner, plate, vehicle, type, job) VALUES (?, ?, ?, ?, ?)',
                    { ownerIdentifier, plate, json.encode(props), vtype, nil }
                )
            end)
            
            if not cdGarageSuccess then
                MySQL.query.await(
                    'INSERT INTO `player_vehicles` (license, citizenid, vehicle, hash, mods, plate, state, garage) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                    { ownerIdentifier, ownerIdentifier, model, GetHashKey(model), json.encode(props), plate, stored, parking }
                )
            end
        end
    elseif fw == "qb-core" or fw == "qb" or fw == "qbx_core" or fw == "qbx" then
        MySQL.query.await(
            'INSERT INTO `player_vehicles` (license, citizenid, vehicle, hash, mods, plate, state, garage) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            { ownerIdentifier, ownerIdentifier, model, GetHashKey(model), json.encode(props), plate, stored, parking }
        )
    else
        print(('[addVehicleToGarage] Unsupported framework: %s'):format(tostring(fw)))
        return nil
    end

    return plate
end

      function handleCodeRedemption(src, code, option)
    local uniqueId  = Bridge.Framework.GetPlayerIdentifier(src)
    local playerName= GetPlayerName(src)
    local row = (MySQL.query.await(
        'SELECT items, per_user_limit, redeemed_by, restricted_to_enabled, restricted_to_type, restricted_to_value, time_locked, time_restrictions, time_restrictions_active, cycle_based_limit, user_cycle_redemptions FROM midnight_codes WHERE code = ? AND (expiry IS NULL OR expiry > NOW()) LIMIT 1',
        { code }
    ) or {})[1]

    if not row then
        return Bridge.Notify.SendNotify(src, locales("NOTIFY_INVALID_OR_EXPIRED"), "error", 6000)
    end

    local restrictionPass, restrictionError = enforcePlayerRestrictionForRow(src, row)
    if not restrictionPass then
        return Bridge.Notify.SendNotify(src, restrictionError, "error", 6000)
    end
    

    if (row.time_locked == 1 or row.time_locked == true) and (row.time_restrictions_active == 1 or row.time_restrictions_active == true) then
        local timeRestrictions = safe_json_decode(row.time_restrictions, {})
        
        local isValid, errorMessage = TimeValidation.isCodeTimeValid(timeRestrictions)
        
        if not isValid then
            local message = errorMessage
            if timeRestrictions.message and timeRestrictions.message ~= "" then
                message = timeRestrictions.message
            end
            return Bridge.Notify.SendNotify(src, message, "error", 6000)
        end
    end

    if (row.cycle_based_limit == 1 or row.cycle_based_limit == true) and (row.time_locked == 1 or row.time_locked == true) and (row.time_restrictions_active == 1 or row.time_restrictions_active == true) then
        local timeRestrictions = safe_json_decode(row.time_restrictions, {})
        local currentCycle = TimeValidation.getCurrentCycle(timeRestrictions)
        
        if currentCycle then
            local userCycleRedemptions = TimeValidation.getUserCycleRedemptions(row.user_cycle_redemptions, currentCycle)
            local userRedemptionsInCycle = userCycleRedemptions[uniqueId] or 0
            
            if userRedemptionsInCycle >= row.per_user_limit then
                local cycleType = timeRestrictions.type or "time"
                local cycleText = ""
                
                if timeRestrictions.type == "daily_hours" then
                    cycleText = "today"
                elseif timeRestrictions.type == "weekly_days" then
                    cycleText = "this week"
                elseif timeRestrictions.type == "specific_dates" then
                    cycleText = "on this date"
                elseif timeRestrictions.type == "recurring" then
                    cycleText = "this cycle"
                end
                
                return Bridge.Notify.SendNotify(src, "You have already redeemed this code " .. row.per_user_limit .. " times " .. cycleText .. ". Try again next cycle!", "error", 6000)
            end
        end
    end

    local items = safe_json_decode(row.items, {})
    local jsonPath = '$."' .. uniqueId .. '"'
    local cycleUpdateSql = ""
    local cycleUpdateParams = {}
    
    if (row.cycle_based_limit == 1 or row.cycle_based_limit == true) and (row.time_locked == 1 or row.time_locked == true) and (row.time_restrictions_active == 1 or row.time_restrictions_active == true) then
        local timeRestrictions = safe_json_decode(row.time_restrictions, {})
        local currentCycle = TimeValidation.getCurrentCycle(timeRestrictions)
        
        if currentCycle then
            local updatedCycleRedemptions = TimeValidation.updateUserCycleRedemptions(row.user_cycle_redemptions, currentCycle, uniqueId)
            cycleUpdateSql = ", user_cycle_redemptions = ?"
            table.insert(cycleUpdateParams, updatedCycleRedemptions)
        end
    end

    local checkRow = MySQL.query.await(
        'SELECT uses, per_user_limit, redeemed_by FROM midnight_codes WHERE code = ? AND (expiry IS NULL OR expiry > NOW()) LIMIT 1',
        { code }
    )
    
    if not checkRow or #checkRow == 0 then
        return Bridge.Notify.SendNotify(src, (locales("NOTIFY_INVALID_OR_EXPIRED") or "Invalid or expired code."), "error", 6000)
    end
    
    local row = checkRow[1]
    
    if row.uses <= 0 then
        return Bridge.Notify.SendNotify(src, (locales("NOTIFY_CODE_FULLY_REDEEMED") or "This code has been fully redeemed."), "error", 6000)
    end
    
    local limit = tonumber(row.per_user_limit or 1) or 1
    if limit > 0 then
        local curCount = 0
        if row.redeemed_by then
            local okJ, parsed = pcall(json.decode, row.redeemed_by)
            if okJ and type(parsed) == "table" then
                local v = parsed[uniqueId]
                if type(v) == "number" then curCount = v end
            end
        end
        
        if curCount >= limit then
            return Bridge.Notify.SendNotify(src, (locales("NOTIFY_PER_USER_LIMIT_REACHED") or "You have reached the per-user redemption limit for this code."), "error", 6000)
        end
    end

    local reserved = MySQL.update.await(
        'UPDATE midnight_codes SET uses = uses - 1 WHERE code = ? AND uses > 0 AND (expiry IS NULL OR expiry > NOW())',
        { code }
    )
    if not reserved or reserved <= 0 then
        return Bridge.Notify.SendNotify(src, (locales("NOTIFY_CODE_FULLY_REDEEMED") or "This code has been fully redeemed."), "error", 6000)
    end

    local receivedSummary = {}
    local allRewardsSuccessful = true
    
    for _, reward in ipairs(items) do
        if reward.item then
            local success = false
            if Bridge.Inventory and Bridge.Inventory.AddItem then
                local bridgeResult = Bridge.Inventory.AddItem(src, reward.item, reward.amount)
                if not bridgeResult then
                    if Bridge.Framework and Bridge.Framework.AddItem then
                        success = Bridge.Framework.AddItem(src, reward.item, reward.amount)
                    else
                        success = false
                    end
                else
                    success = true
                end
            elseif Bridge.Framework and Bridge.Framework.AddItem then
                success = Bridge.Framework.AddItem(src, reward.item, reward.amount)
            end
            
            if not success then
                allRewardsSuccessful = false
            else
                insert(receivedSummary, fmt("📦 %dx %s", reward.amount or 1, reward.item))
            end
            
        elseif reward.money then
            local account = option or reward.option or "cash"
            local success = Bridge.Framework.AddAccountBalance(src, account, reward.amount)
            
            if not success then
                allRewardsSuccessful = false
            else
                insert(receivedSummary, fmt("💰 $%s (%s)", reward.amount or 0, account))
            end
            
        elseif reward.vehicle then
            local model = nil
            if type(reward.vehicle) == "string" then
                model = reward.vehicle
            else
                model = reward.model
            end
            local plate = addVehicleToGarage(model, playerName, uniqueId)
            
            if not plate then
                allRewardsSuccessful = false
            else
                insert(receivedSummary, fmt("🚗 Vehicle: %s%s", model or "Unknown", plate and (" (Plate: " .. plate .. ")") or ""))
            end
        end
    end
    
    if not allRewardsSuccessful then
        MySQL.update.await('UPDATE midnight_codes SET uses = uses + 1 WHERE code = ?', { code })
        return Bridge.Notify.SendNotify(src, "Failed to give rewards. Please try again.", "error", 6000)
    end
    
    local currentRedeemed = row.redeemed_by or '{}'
    local ok, parsed = pcall(json.decode, currentRedeemed)
    if not ok or type(parsed) ~= "table" then
        parsed = {}
    end
    
    parsed[uniqueId] = (parsed[uniqueId] or 0) + 1
    local newRedeemed = json.encode(parsed)
    
    MySQL.update.await('UPDATE midnight_codes SET redeemed_by = ? WHERE code = ?', { newRedeemed, code })
    
    if #cycleUpdateParams > 0 then
        MySQL.update.await('UPDATE midnight_codes SET user_cycle_redemptions = ? WHERE code = ?', { cycleUpdateParams[1], code })
    end

    refreshDashboardData(nil)

    local notifyMsg = table.concat(receivedSummary, "\n")
    TriggerClientEvent("midnight-redeem:notifyUser", src, "Code Redeemed Successfully!", notifyMsg, "success")

    local infoRow = (MySQL.query.await(
        'SELECT per_user_limit, redeemed_by, uses, expiry FROM midnight_codes WHERE code = ? LIMIT 1',
        { code }
    ) or {})[1]

    local perUserLeftText, usesLeftText, expiryText = "N/A", "N/A", "Never"
    if infoRow then
        local limitVal = tonumber(infoRow.per_user_limit or 0) or 0
        local used = 0
        if infoRow.redeemed_by then
            local okJ, parsed = pcall(json.decode, infoRow.redeemed_by)
            if okJ and type(parsed) == "table" then
                local v = parsed[uniqueId]
                if type(v) == "number" then used = v end
            end
        end
        if limitVal == 0 then
            perUserLeftText = "Unlimited"
        else
            local left = math.max(limitVal - used, 0)
            perUserLeftText = string.format("%d left (used %d/%d)", left, used, limitVal)
        end

        local usesLeft = tonumber(infoRow.uses)
        if usesLeft ~= nil then
            usesLeftText = tostring(usesLeft)
        end

        local ts
        local e = infoRow.expiry
        if e ~= nil then
            local et = type(e)
            if et == "string" then
                ts = iso_to_unix(e)
                if not ts then
                    local y, mo, d, h, mi = e:match("^(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d)$")
                    if y then
                        ts = os.time({
                            year = tonumber(y), month = tonumber(mo), day = tonumber(d),
                            hour = tonumber(h), min = tonumber(mi), sec = 0
                        })
                    end
                end
            elseif et == "number" then
                ts = (e > 1e12) and math.floor(e / 1000) or e
            elseif et == "table" then
                if e.year and e.month and e.day then
                    ts = os.time({
                        year = tonumber(e.year), month = tonumber(e.month), day = tonumber(e.day),
                        hour = tonumber(e.hour or 0), min = tonumber(e.min or 0), sec = tonumber(e.sec or 0)
                    })
                end
            end
        end

        if ts and ts > 0 then
            expiryText = "<t:" .. tostring(ts) .. ":f> (<t:" .. tostring(ts) .. ":R>)"
        else
            expiryText = "Never"
        end
    end

    local PlayerName = playerName or "N/A"
    local Code = code or "N/A"
    local Summary = (#receivedSummary > 0 and table.concat(receivedSummary, "\n")) or "N/A"
    local UniqueId = uniqueId or "N/A"

    local message = ("**Redeemed By:** `%s`\n**Code:** `%s`\n**Uses Left:** `%s`\n**User limit Remaining:** %s\n**Expiry:** %s\n**Rewards:**\n%s\n**Identifiers:**\n- UniqueID: `%s`")
        :format(PlayerName, Code, usesLeftText, perUserLeftText, expiryText, Summary, UniqueId)
    SendToDiscord("Code Redeemed", message, 15844367)
    CreateThread(function()
        pcall(function()
            for _, reward in ipairs(items) do
                local rewardType, rewardName, rewardAmount = nil, nil, nil
                
                if reward.item then
                    rewardType = "item"
                    rewardName = reward.item
                    rewardAmount = reward.amount or 1
                elseif reward.money then
                    rewardType = "money"
                    rewardName = option or reward.option or "cash"
                    rewardAmount = reward.amount or 0
                elseif reward.vehicle then
                    rewardType = "vehicle"
                    local model = nil
                    if type(reward.vehicle) == "string" then
                        model = reward.vehicle
                    else
                        model = reward.model
                    end
                    rewardName = model
                    rewardAmount = 1
                end
                
                if rewardType and rewardName then
                    MySQL.query.await([[
                        INSERT INTO midnight_redeem_stats (reward_type, reward_name, reward_amount, redemption_count, last_redeemed)
                        VALUES (?, ?, ?, 1, NOW())
                        ON DUPLICATE KEY UPDATE
                            redemption_count = redemption_count + 1,
                            last_redeemed = NOW(),
                            updated_at = NOW()
                    ]], { rewardType, rewardName, rewardAmount })
                end
            end
        end)
    end)
end

RegisterServerEvent("midnight-redeem:redeemCode", function(code, option)
    if not checkRedeemRateLimit(source) then
        return Bridge.Notify.SendNotify(source, "Please wait before redeeming again.", "error", 6000)
    end
    handleCodeRedemption(source, code, option)
end)

lib.callback.register("midnight-redeem:redeemCodeWithResult", function(src, code, option)
    if not checkRedeemRateLimit(src) then
        return { success = false, error = "Please wait before redeeming again." }
    end
    local uniqueId  = Bridge.Framework.GetPlayerIdentifier(src)
    local playerName= GetPlayerName(src)
    local row = (MySQL.query.await(
        'SELECT items, per_user_limit, redeemed_by, restricted_to_enabled, restricted_to_type, restricted_to_value, time_locked, time_restrictions, time_restrictions_active, cycle_based_limit, user_cycle_redemptions FROM midnight_codes WHERE code = ? AND (expiry IS NULL OR expiry > NOW()) LIMIT 1',
        { code }
    ) or {})[1]

    if not row then
        return { success = false, error = locales("NOTIFY_INVALID_OR_EXPIRED") or "Invalid or expired code." }
    end

    local restrictionPass, restrictionError = enforcePlayerRestrictionForRow(src, row)
    if not restrictionPass then
        return { success = false, error = restrictionError }
    end
    

    if (row.time_locked == 1 or row.time_locked == true) and (row.time_restrictions_active == 1 or row.time_restrictions_active == true) then
        local timeRestrictions = safe_json_decode(row.time_restrictions, {})
        
        local isValid, errorMessage = TimeValidation.isCodeTimeValid(timeRestrictions)
        
        if not isValid then
            local message = errorMessage
            if timeRestrictions.message and timeRestrictions.message ~= "" then
                message = timeRestrictions.message
            end
            return { success = false, error = message }
        end
    end

    if (row.cycle_based_limit == 1 or row.cycle_based_limit == true) and (row.time_locked == 1 or row.time_locked == true) and (row.time_restrictions_active == 1 or row.time_restrictions_active == true) then
        local timeRestrictions = safe_json_decode(row.time_restrictions, {})
        local currentCycle = TimeValidation.getCurrentCycle(timeRestrictions)
        
        if currentCycle then
            local userCycleRedemptions = TimeValidation.getUserCycleRedemptions(row.user_cycle_redemptions, currentCycle)
            local userRedemptionsInCycle = userCycleRedemptions[uniqueId] or 0
            
            if userRedemptionsInCycle >= row.per_user_limit then
                local cycleType = timeRestrictions.type or "time"
                local cycleText = ""
                
                if timeRestrictions.type == "daily_hours" then
                    cycleText = "today"
                elseif timeRestrictions.type == "weekly_days" then
                    cycleText = "this week"
                elseif timeRestrictions.type == "specific_dates" then
                    cycleText = "on this date"
                elseif timeRestrictions.type == "recurring" then
                    cycleText = "this cycle"
                end
                
                local errorMsg = "You have already redeemed this code " .. row.per_user_limit .. " times " .. cycleText .. ". Try again next cycle!"
                return { success = false, error = errorMsg }
            end
        end
    end

    local items = safe_json_decode(row.items, {})
    local jsonPath = '$."' .. uniqueId .. '"'
    local cycleUpdateSql = ""
    local cycleUpdateParams = {}
    
    if (row.cycle_based_limit == 1 or row.cycle_based_limit == true) and (row.time_locked == 1 or row.time_locked == true) and (row.time_restrictions_active == 1 or row.time_restrictions_active == true) then
        local timeRestrictions = safe_json_decode(row.time_restrictions, {})
        local currentCycle = TimeValidation.getCurrentCycle(timeRestrictions)
        
        if currentCycle then
            local updatedCycleRedemptions = TimeValidation.updateUserCycleRedemptions(row.user_cycle_redemptions, currentCycle, uniqueId)
            cycleUpdateSql = ", user_cycle_redemptions = ?"
            table.insert(cycleUpdateParams, updatedCycleRedemptions)
        end
    end

    local checkRow = MySQL.query.await(
        'SELECT uses, per_user_limit, redeemed_by FROM midnight_codes WHERE code = ? AND (expiry IS NULL OR expiry > NOW()) LIMIT 1',
        { code }
    )
    
    if not checkRow or #checkRow == 0 then
        local errorMsg = locales("NOTIFY_INVALID_OR_EXPIRED") or "Invalid or expired code."
        return { success = false, error = errorMsg }
    end
    
    local checkRowData = checkRow[1]
    
    if checkRowData.uses <= 0 then
        local errorMsg = locales("NOTIFY_CODE_FULLY_REDEEMED") or "This code has been fully redeemed."
        return { success = false, error = errorMsg }
    end
    
    local limit = tonumber(checkRowData.per_user_limit or 1) or 1
    if limit > 0 then
        local curCount = 0
        if checkRowData.redeemed_by then
            local okJ, parsed = pcall(json.decode, checkRowData.redeemed_by)
            if okJ and type(parsed) == "table" then
                local v = parsed[uniqueId]
                if type(v) == "number" then curCount = v end
            end
        end
        
        if curCount >= limit then
            local errorMsg = locales("NOTIFY_PER_USER_LIMIT_REACHED") or "You have reached the per-user redemption limit for this code."
            return { success = false, error = errorMsg }
        end
    end

    local reserved = MySQL.update.await(
        'UPDATE midnight_codes SET uses = uses - 1 WHERE code = ? AND uses > 0 AND (expiry IS NULL OR expiry > NOW())',
        { code }
    )
    if not reserved or reserved <= 0 then
        local errorMsg = locales("NOTIFY_CODE_FULLY_REDEEMED") or "This code has been fully redeemed."
        return { success = false, error = errorMsg }
    end

    local receivedSummary = {}
    local allRewardsSuccessful = true
    
    for _, reward in ipairs(items) do
        if reward.item then
            local success = false
            if Bridge.Inventory and Bridge.Inventory.AddItem then
                local bridgeResult = Bridge.Inventory.AddItem(src, reward.item, reward.amount)
                if not bridgeResult then
                    if Bridge.Framework and Bridge.Framework.AddItem then
                        success = Bridge.Framework.AddItem(src, reward.item, reward.amount)
                    else
                        success = false
                    end
                else
                    success = true
                end
            elseif Bridge.Framework and Bridge.Framework.AddItem then
                success = Bridge.Framework.AddItem(src, reward.item, reward.amount)
            end
            
            if not success then
                allRewardsSuccessful = false
            else
                table.insert(receivedSummary, string.format("📦 %dx %s", reward.amount or 1, reward.item))
            end
            
        elseif reward.money then
            local account = option or reward.option or "cash"
            local success = Bridge.Framework.AddAccountBalance(src, account, reward.amount)
            
            if not success then
                allRewardsSuccessful = false
            else
                table.insert(receivedSummary, string.format("💰 $%s (%s)", reward.amount or 0, account))
            end
            
        elseif reward.vehicle then
            local model = nil
            if type(reward.vehicle) == "string" then
                model = reward.vehicle
            else
                model = reward.model
            end
            local plate = addVehicleToGarage(model, playerName, uniqueId)
            
            if plate then
                table.insert(receivedSummary, string.format("🚗 %s (Plate: %s)", model, plate))
            else
                allRewardsSuccessful = false
                table.insert(receivedSummary, string.format("❌ Failed to add vehicle: %s", model))
            end
        end
    end

    if not allRewardsSuccessful then
        MySQL.update.await('UPDATE midnight_codes SET uses = uses + 1 WHERE code = ?', { code })
        local errorMsg = "Some rewards failed to be added."
        return { success = false, error = errorMsg }
    end

    local currentRedeemed = checkRowData.redeemed_by or '{}'
    local ok, parsed = pcall(json.decode, currentRedeemed)
    if not ok or type(parsed) ~= "table" then
        parsed = {}
    end
    
    parsed[uniqueId] = (parsed[uniqueId] or 0) + 1
    local newRedeemed = json.encode(parsed)
    
    MySQL.update.await('UPDATE midnight_codes SET redeemed_by = ? WHERE code = ?', { newRedeemed, code })
    
    if cycleUpdateSql ~= "" and #cycleUpdateParams > 0 then
        MySQL.update.await('UPDATE midnight_codes SET user_cycle_redemptions = ? WHERE code = ?', { cycleUpdateParams[1], code })
    end

    local notifyMsg = table.concat(receivedSummary, "\n")
    TriggerClientEvent("midnight-redeem:notifyUser", src, "Code Redeemed Successfully!", notifyMsg, "success")

    local rewardData = { money = nil, items = {}, vehicles = {} }
    for _, reward in ipairs(items) do
        if reward.item then
            rewardData.items[#rewardData.items + 1] = {
                name = reward.item,
                amount = reward.amount or 1
            }
        elseif reward.money then
            rewardData.money = (rewardData.money or 0) + (reward.amount or 0)
        elseif reward.vehicle then
            local model = type(reward.vehicle) == "string" and reward.vehicle or reward.model
            if model then
                rewardData.vehicles[#rewardData.vehicles + 1] = model
            end
        end
    end
    if not rewardData.money or rewardData.money <= 0 then
        rewardData.money = nil
    end
    if #rewardData.items == 0 then rewardData.items = nil end
    if #rewardData.vehicles == 0 then rewardData.vehicles = nil end
    
    CreateThread(function()
        SendToDiscord("Code Redeemed", string.format("**Code:** `%s`\n**Player:** `%s`\n**Rewards:**\n%s", code, playerName, notifyMsg), 16776960)
    end)
    
    CreateThread(function()
        local infoRow = (MySQL.query.await(
            'SELECT items, per_user_limit, redeemed_by, uses, expiry FROM midnight_codes WHERE code = ? LIMIT 1',
            { code }
        ) or {})[1]

        if infoRow then
            local rewardStats = safe_json_decode(infoRow.items, {})
            for _, reward in ipairs(rewardStats or {}) do
                local rewardType, rewardName, rewardAmount = nil, nil, nil
                
                if reward.item then
                    rewardType = "item"
                    rewardName = reward.item
                    rewardAmount = reward.amount or 1
                elseif reward.money then
                    rewardType = "money"
                    rewardName = option or reward.option or "cash"
                    rewardAmount = reward.amount or 0
                elseif reward.vehicle then
                    rewardType = "vehicle"
                    local model = nil
                    if type(reward.vehicle) == "string" then
                        model = reward.vehicle
                    else
                        model = reward.model
                    end
                    rewardName = model
                    rewardAmount = 1
                end
                
                if rewardType and rewardName then
                    MySQL.query.await([[
                        INSERT INTO midnight_redeem_stats (reward_type, reward_name, reward_amount, redemption_count, last_redeemed)
                        VALUES (?, ?, ?, 1, NOW())
                        ON DUPLICATE KEY UPDATE
                            redemption_count = redemption_count + 1,
                            last_redeemed = NOW(),
                            updated_at = NOW()
                    ]], { rewardType, rewardName, rewardAmount })
                end
            end
        end
    end)
    
    return { success = true, rewards = rewardData }
end)

lib.callback.register("midnight-redeem:validateCode", function(src, code, option)
    if not checkRedeemRateLimit(src) then
        return { success = false, error = "Please wait before redeeming again." }
    end
    local uniqueId  = Bridge.Framework.GetPlayerIdentifier(src)
    local row = (MySQL.query.await(
        'SELECT items, per_user_limit, redeemed_by, restricted_to_enabled, restricted_to_type, restricted_to_value, time_locked, time_restrictions, time_restrictions_active, cycle_based_limit, user_cycle_redemptions, uses FROM midnight_codes WHERE code = ? AND (expiry IS NULL OR expiry > NOW()) LIMIT 1',
        { code }
    ) or {})[1]

    if not row then
        return { success = false, error = locales("NOTIFY_INVALID_OR_EXPIRED") or "Invalid or expired code." }
    end

    local restrictionPass, restrictionError = enforcePlayerRestrictionForRow(src, row)
    if not restrictionPass then
        return { success = false, error = restrictionError }
    end
    
    if row.uses <= 0 then
        return { success = false, error = locales("NOTIFY_CODE_FULLY_REDEEMED") or "This code has been fully redeemed." }
    end
    
    if (row.time_locked == 1 or row.time_locked == true) and (row.time_restrictions_active == 1 or row.time_restrictions_active == true) then
        local timeRestrictions = safe_json_decode(row.time_restrictions, {})
        local isValid, errorMessage = TimeValidation.isCodeTimeValid(timeRestrictions)
        
        if not isValid then
            local message = errorMessage
            if timeRestrictions.message and timeRestrictions.message ~= "" then
                message = timeRestrictions.message
            end
            return { success = false, error = message }
        end
    end

    if (row.cycle_based_limit == 1 or row.cycle_based_limit == true) and (row.time_locked == 1 or row.time_locked == true) and (row.time_restrictions_active == 1 or row.time_restrictions_active == true) then
        local timeRestrictions = safe_json_decode(row.time_restrictions, {})
        local currentCycle = TimeValidation.getCurrentCycle(timeRestrictions)
        
        if currentCycle then
            local userCycleRedemptions = TimeValidation.getUserCycleRedemptions(row.user_cycle_redemptions, currentCycle)
            local userRedemptionsInCycle = userCycleRedemptions[uniqueId] or 0
            
            if userRedemptionsInCycle >= row.per_user_limit then
                local cycleText = ""
                if timeRestrictions.type == "daily_hours" then
                    cycleText = "today"
                elseif timeRestrictions.type == "weekly_days" then
                    cycleText = "this week"
                elseif timeRestrictions.type == "specific_dates" then
                    cycleText = "on this date"
                elseif timeRestrictions.type == "recurring" then
                    cycleText = "this cycle"
                end
                return { success = false, error = "You have already redeemed this code " .. row.per_user_limit .. " times " .. cycleText .. ". Try again next cycle!" }
            end
        end
    end
    
    local limit = tonumber(row.per_user_limit or 1) or 1
    if limit > 0 then
        local curCount = 0
        if row.redeemed_by then
            local okJ, parsed = pcall(json.decode, row.redeemed_by)
            if okJ and type(parsed) == "table" then
                local v = parsed[uniqueId]
                if type(v) == "number" then curCount = v end
            end
        end
        
        if curCount >= limit then
            return { success = false, error = locales("NOTIFY_PER_USER_LIMIT_REACHED") or "You have reached the per-user redemption limit for this code." }
        end
    end

    local checkRow = MySQL.query.await(
        'SELECT uses FROM midnight_codes WHERE code = ? AND (expiry IS NULL OR expiry > NOW()) LIMIT 1',
        { code }
    )
    
    if not checkRow or #checkRow == 0 or checkRow[1].uses <= 0 then
        return { success = false, error = locales("NOTIFY_INVALID_OR_EXPIRED") or "Invalid or expired code." }
    end

    return { success = true, validated = true }
end)

lib.callback.register("midnight-redeem:applyReward", function(src, code, option)
    if not checkRedeemRateLimit(src) then
        return { success = false, error = "Please wait before redeeming again." }
    end
    return { success = false, error = "Direct reward application is disabled. Please redeem again." }
end)

exports('GenerateRedeemCode', function(source, itemsJson, uses, expiryDays, customCode, perUserLimit, createdByOverride, timeRestrictions, playerRestriction)
    HandleRedeemCode(source, itemsJson, uses, expiryDays, customCode, perUserLimit, createdByOverride, timeRestrictions, playerRestriction)
end)

RegisterServerEvent("zdiscord:generateRedeemCode", function(itemsJson, uses, expiryFlexible, customCode, perUserLimit)
        if source ~= 0 then
            local invoker = GetInvokingResource()
            if invoker ~= "zdiscord" then
                return
            end
        end
    
        local usesNum = tonumber(uses)
        local expArg  = tonumber(expiryFlexible) or expiryFlexible
        local perUser = tonumber(perUserLimit)
    
        if itemsJson and usesNum and expArg ~= nil and customCode then
            exports["midnight_redeem"]:GenerateRedeemCode(0, itemsJson, usesNum, expArg, customCode, perUser)
            
        end
    end)

lib.callback.register("midnight-redeem:getAllCodes", function(source)
    if not requireAdmin(source, "VIEW_DASHBOARD") then
        return {}
    end
    local results = exports.oxmysql:executeSync("SELECT code FROM midnight_codes")
    local options = {}
    for _, row in ipairs(results or {}) do
        table.insert(options, { label = row.code, value = row.code })
    end
    return options
end)

lib.callback.register("midnight-redeem:getAllCodesWithDetails", function(source)
    if not requireAdmin(source, "VIEW_DASHBOARD") then
        return {}
    end
    return _dashboardData.codes or getAllCodesWithDetails()
end)

lib.callback.register("midnight-redeem:getAllCodesForSearch", function(source)
    if not requireAdmin(source, "VIEW_DASHBOARD") then
        return {}
    end
    return _dashboardData.allCodes or getAllCodesForSearch()
end)

RegisterServerEvent("midnight-redeem:adminCheckCode", function(code)
    local src = source
    if not requireAdmin(src, "VIEW_DASHBOARD") then return end
    exports.oxmysql:execute('SELECT * FROM midnight_codes WHERE code = ?', { code }, function(result)
        if result[1] then
            local row = result[1]
            local items = json.decode(row.items or "[]")
            local rewardList = {}
            for _, reward in ipairs(items) do
                if reward.item then
                    table.insert(rewardList, string.format("📦 %dx %s", reward.amount or 1, reward.item))
                elseif reward.money then
                    table.insert(rewardList, string.format("💰 $%s (%s)", reward.amount or 0, reward.option or "cash"))
                elseif reward.vehicle then
                    local model = nil
                    if type(reward.vehicle) == "string" then
                        model = reward.vehicle
                    else
                        model = reward.model
                    end
                    table.insert(rewardList, string.format("🚗 Vehicle: %s", model or "Unknown"))
                end
            end

            local daysLeft = "Never"
            if row.expiry then
                local expiryTime
                if type(row.expiry) == "number" then
                    expiryTime = math.floor(row.expiry / 1000)
                elseif type(row.expiry) == "string" and #row.expiry >= 10 then
                    expiryTime = os.time({
                        year = tonumber(row.expiry:sub(1,4)),
                        month = tonumber(row.expiry:sub(6,7)),
                        day = tonumber(row.expiry:sub(9,10)),
                        hour = tonumber(row.expiry:sub(12,13)) or 0,
                        min = tonumber(row.expiry:sub(15,16)) or 0,
                        sec = tonumber(row.expiry:sub(18,19)) or 0
                    })
                end
                if expiryTime then
                    local now = os.time()
                    local diff = math.floor((expiryTime - now) / 86400)
                    daysLeft = diff >= 0 and tostring(diff) or "Expired"
                end
            end

            local info = ("Code: %s\nUses Left: %s\nDays Left: %s\nRewards:\n%s"):format(
                row.code, row.uses, daysLeft, table.concat(rewardList, "\n")
            )
            Bridge.Notify.SendNotify(src, info, locales("NOTIFY_INFO"), 15000)
        else
            Bridge.Notify.SendNotify(src, locales("NOTIFY_NO_CODE_FOUND"), "error", 6000)
        end
    end)
end)

lib.callback.register("midnight-redeem:checkEditPermission", function(source)
    return requireAdmin(source, "EDIT_CODES")
end)

lib.callback.register("midnight-redeem:getCodeDetails", function(source, code)
    if not requireAdmin(source, "VIEW_DASHBOARD") then
        return { success = false, data = nil }
    end
    if not code or type(code) ~= "string" then
        return { success = false, data = nil }
    end
    
    local result = MySQL.query.await(
        'SELECT * FROM midnight_codes WHERE code = ? LIMIT 1',
        { code }
    )
    
    if result and #result > 0 then
        local codeData = result[1]
        
        if codeData.time_restrictions then
            local success, parsed = pcall(json.decode, codeData.time_restrictions)
            if success then
                codeData.time_restrictions = parsed
            end
        end
        
        if codeData.user_cycle_redemptions then
            local success, parsed = pcall(json.decode, codeData.user_cycle_redemptions)
            if success then
                codeData.user_cycle_redemptions = parsed
            end
        end
        
        return { success = true, data = codeData }
    else
        return { success = false, data = nil }
    end
end)

local function updateRedeemCodeInternal(src, payload, options)
    options = options or {}
    local silent = options.silent == true

    if src and src > 0 and not options.skipAuth then
        if not requireAdmin(src, "EDIT_CODES") then
            return { success = false, error = "Permission denied." }
        end
    end

    if type(payload) ~= "table" or not payload.originalCode or payload.originalCode == "" then
        return { success = false, error = locales("NOTIFY_INVALID_DATA") or "Invalid edit payload." }
    end

    local cur = MySQL.query.await('SELECT * FROM midnight_codes WHERE code = ?', { payload.originalCode })
    if not cur or not cur[1] then
        return { success = false, error = locales("NOTIFY_NO_CODE_FOUND") or "Code not found." }
    end
    cur = cur[1]

    local newPerUser = cur.per_user_limit
    if payload.perUserLimit ~= nil then
        local p = tonumber(payload.perUserLimit)
        if p and p >= 0 then newPerUser = p end
    end

    local newItemsJson = payload.itemsJson or cur.items
    local newUses = payload.uses or cur.uses
    local newCode = payload.newCode or cur.code

    local newExpiry = cur.expiry
    if payload.expiryAbs ~= nil then
        if type(payload.expiryAbs) == "string" and #payload.expiryAbs >= 19
           and payload.expiryAbs:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$") then
            newExpiry = payload.expiryAbs
        else
            newExpiry = nil
        end
    elseif payload.expiryDays ~= nil then
        local days = tonumber(payload.expiryDays) or 0
        if days <= 0 then
            newExpiry = nil
        else
            newExpiry = os.date("%Y-%m-%d %H:%M:%S", os.time() + (days * 86400))
        end
    elseif payload.expiry ~= nil then
        if type(payload.expiry) == "string" then
            if payload.expiry:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d") then
                local year, month, day, hour, min = payload.expiry:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d)")
                if year and month and day and hour and min then
                    newExpiry = string.format("%s-%s-%s %s:%s:00", year, month, day, hour, min)
                else
                    newExpiry = nil
                end
            else
                newExpiry = nil
            end
        elseif type(payload.expiry) == "number" then
            local timestamp = payload.expiry
            if timestamp > 1000000000000 then
                timestamp = math.floor(timestamp / 1000)
            end
            newExpiry = os.date("%Y-%m-%d %H:%M:%S", timestamp)
        end
    end

    local totalItemCount = cur.total_item_count
    if payload.itemsJson then
        local ok, tbl = pcall(json.decode, newItemsJson or "[]")
        tbl = ok and tbl or {}
        local sum = 0
        for _, r in ipairs(tbl) do
            if r.item then sum = sum + (tonumber(r.amount) or 0) end
        end
        totalItemCount = sum
    end

    local restriction = parsePlayerRestriction(payload.playerRestriction)

    if newCode ~= cur.code then
        local exists = MySQL.query.await('SELECT code FROM midnight_codes WHERE code = ?', { newCode })
        if exists and exists[1] then
            return { success = false, error = locales("NOTIFY_CODE_EXISTS") or "That code already exists." }
        end
    end

    local q = [[
        UPDATE midnight_codes
        SET code = ?, items = ?, uses = ?, expiry = ?, total_item_count = ?, per_user_limit = ?, restricted_to_enabled = ?, restricted_to_type = ?, restricted_to_value = ?
        WHERE code = ?
    ]]

    local affected = MySQL.update.await(q, {
        newCode, newItemsJson, newUses, newExpiry, totalItemCount, newPerUser,
        restriction.enabled and 1 or 0, restriction.type, restriction.value, cur.code
    })

    if (affected or 0) <= 0 then
        return { success = false, error = locales("NOTIFY_FAILED_UPDATE") or "Failed to update code." }
    end

    refreshDashboardData(nil)
    broadcastDashboardAfterRefresh(src)

    local rewardsPreview = {}
    local ok2, tbl2 = pcall(json.decode, newItemsJson or "[]")
    tbl2 = ok2 and tbl2 or {}
    for _, reward in ipairs(tbl2) do
        if reward.item then
            table.insert(rewardsPreview, string.format("📦 %dx %s", reward.amount or 1, reward.item))
        elseif reward.money then
            table.insert(rewardsPreview, string.format("💰 $%s (%s)", reward.amount or 0, reward.option or "cash"))
        elseif reward.vehicle then
            local model = type(reward.vehicle) == "string" and reward.vehicle or reward.model
            table.insert(rewardsPreview, string.format("🚗 Vehicle: %s", model or "Unknown"))
        end
    end

    local msg = ("**Admin:** `%s`\n**Old Code:** `%s`\n**New Code:** `%s`\n**Uses:** `%s`\n**Expiry:** `%s`\n**Player Restriction:** `%s`\n\n**Rewards:**\n%s")
        :format(GetPlayerName(src) or "Unknown", cur.code, newCode, newUses or "?", newExpiry or "Never",
            restriction.enabled and ((restriction.type or "id") .. " => " .. (restriction.value or "")) or "None",
            table.concat(rewardsPreview, "\n"))
    SendToDiscord("Redeem Code Updated", msg, 3447003)

    if not silent then
        Bridge.Notify.SendNotify(src, locales("NOTIFY_CODE_UPDATED") or "Code updated.", "success", 6000)
    end

    return { success = true, data = { code = newCode } }
end

exports('UpdateRedeemCodeInternal', function(source, payload, opts)
    if not requireAdmin(source, "EDIT_CODES") then
        return { success = false, error = "Permission denied" }
    end
    return updateRedeemCodeInternal(source, payload, opts or {})
end)

RegisterServerEvent("midnight-redeem:updateCode", function(payload)
    local src = source
    if not requireAdmin(src, "EDIT_CODES") then
        return Bridge.Notify.SendNotify(src, locales("NOTIFY_PERMISSION_DENIED_DELETE") or "You do not have permission.", "error", 6000)
    end

    local result = updateRedeemCodeInternal(src, payload, { silent = false })
    if not result.success then
        Bridge.Notify.SendNotify(src, result.error or (locales("NOTIFY_FAILED_UPDATE") or "Failed to update code."), "error", 6000)
    end
end)


function CreateDailyCode()
    if not (Config and Config.DailyRewardEnabled) then
        return
    end

    local usesNum       = tonumber(Config.DailyRewarduses) or 1
    local perUserLimit  = tonumber(Config.DailyRewardperuserlimit) or 1
    local hoursNum      = tonumber(Config.DailyRewardhours) or 6

    if usesNum <= 0 or perUserLimit < 0 or hoursNum <= 0 then
        return
    end

    local times = _getConfiguredTimesInMinutes()
    if #times == 0 then
        return
    end

    local nowMins = _nowMinutes()
    local chosenSlotMins = nil
    for _, m in ipairs(times) do
        if m <= nowMins then chosenSlotMins = m end
    end
    if not chosenSlotMins then
        local nextMins = times[1]
        return
    end

    local todayKey  = os.date("%Y%m%d")
    local slotKey   = _formatHHMM(chosenSlotMins)
    local likeKey   = ("D-%s-%s-%%%%"):format(todayKey, slotKey)
    local existsForSlot = MySQL.query.await(
        'SELECT code FROM midnight_codes WHERE code LIKE ? LIMIT 1',
        { likeKey }
    )
    if existsForSlot and existsForSlot[1] then
        local existingCode = existsForSlot[1].code
        local slotHuman = slotKey:sub(1,2) .. "." .. slotKey:sub(3,4)

        SendToDiscord(
            "Daily Code Skipped",
            ("A code was **not** generated because today's **%s** slot already has one.\n\n• **Date:** `%s`\n• **Slot:** `%s`\n• **Existing Code:** `%s`")
                :format(slotHuman, os.date("%Y-%m-%d"), slotHuman, existingCode),
            15158332, 
            nil,      
            "admin"   
        )

        
        return
    end

    local pickedRewards = nil
    if type(Config.DailyRewards) == "table" and #Config.DailyRewards > 0 then
        local candidates = {}
        for _, e in ipairs(Config.DailyRewards) do
            local r = _parseDailyReward(e)
            if r then table.insert(candidates, r) end
        end
        if #candidates > 0 then
            local seedExtra = (GetGameTimer and GetGameTimer() or 0)
            math.randomseed(os.time() + seedExtra)
            local picked = candidates[math.random(#candidates)]
            -- If picked reward is an array (multiple rewards), use it directly; otherwise wrap in array
            -- Check if it's an array by seeing if it has a numeric index 1 and the key "item"/"money" doesn't exist at top level
            if type(picked) == "table" and picked[1] and not (picked.item or picked.money) then
                pickedRewards = picked
            else
                pickedRewards = { picked }
            end
        end
    end

    if not pickedRewards then
        local rewardName = tostring(Config.DailyRewardItem or "cash")
        local amountNum  = tonumber(Config.DailyRewardamount) or 0
        if amountNum <= 0 then
            return
        end
        local rn = rewardName:lower()
        if rn == "cash" or rn == "bank" then
            pickedRewards = { { money = true, amount = amountNum, option = rn } }
        else
            pickedRewards = { { item = rewardName, amount = amountNum } }
        end
    end

    local itemsJson = json.encode(pickedRewards)
    local expiryAbs = os.date("%Y-%m-%d %H:%M:%S", os.time() + (hoursNum * 3600))

          function _randCode(len)
        local chars = "AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz123456789"
        local out = {}
        for i = 1, len do
            local idx = math.random(#chars)
            out[i] = chars:sub(idx, idx)
        end
        return table.concat(out)
    end

    local seedExtra = (GetGameTimer and GetGameTimer() or 0)
    math.randomseed(os.time() + seedExtra)

    local code
    for _ = 1, 10 do
        local candidate = ("D-%s-%s-%s"):format(todayKey, slotKey, _randCode(6))
        local exists = MySQL.query.await('SELECT code FROM midnight_codes WHERE code = ? LIMIT 1', { candidate })
        if not (exists and exists[1]) then
            code = candidate
            break
        end
    end
    if not code then
        code = ("D-%s-%s-%06d"):format(todayKey, slotKey, math.random(0, 999999))
    end

    HandleRedeemCode(0, itemsJson, usesNum, expiryAbs, code, perUserLimit, "Daily Code")

    local expiryTs = (iso_to_unix and iso_to_unix(expiryAbs)) or (os.time() + (tonumber(Config.DailyRewardhours) or 0) * 3600)
    local expiry   = expiryTs and (("<t:%d:f> (<t:%d:R>)"):format(expiryTs, expiryTs)) or "Never"
    local codeFmt  = ("`%s`"):format(code)

    SendToDiscord("🎁 Daily Reward Code",
        ("Use this code for today's %s slot:"):format(slotKey),
        3447003,
        { fields = {
            { name = "Redeem Code", value = codeFmt, inline = false },
            { name = "Expiry",      value = expiry,  inline = false },
        }},
        "daily"
    )
end

function CleanupOldCodes()
    local daysThreshold = tonumber(Config.codeclean) or 30
    local cutoffTs = os.time() - (daysThreshold * 86400)
    local cutoffISO = os.date("%Y-%m-%d %H:%M:%S", cutoffTs)

    local oldCodes = MySQL.query.await(
        "SELECT code, DATE_FORMAT(expiry, '%Y-%m-%d %H:%i:%s') AS expiry_str FROM midnight_codes WHERE expiry IS NOT NULL AND expiry < ?",
        { cutoffISO }
    )

    if not oldCodes or #oldCodes == 0 then
        return
    end

    MySQL.query.await(
        'DELETE FROM midnight_codes WHERE expiry IS NOT NULL AND expiry < ?',
        { cutoffISO }
    )

    local codeList = {}
    for _, row in ipairs(oldCodes) do
        local niceExpiry = "unknown"
        if row.expiry_str and row.expiry_str ~= "" then
            niceExpiry = row.expiry_str
        end

        table.insert(codeList, ("? `%s` (expired %s)"):format(row.code, niceExpiry))
    end

    local codeListStr = table.concat(codeList, "\n")

    SendToDiscord(
        "🧹 Expired Code Cleanup",
        ("**%d expired codes** older than %d days were removed.\n\n%s")
            :format(#oldCodes, daysThreshold, codeListStr),
        15158332,
        nil,
        "admin"
    )

    
end

RegisterCommand("cleanupcodes", function(src)
    if src ~= 0 then return end
    
    CleanupOldCodes()
end)

RegisterCommand("clearcodes", function(src)
    if src ~= 0 then return end

    local totalCodes = MySQL.query.await("SELECT COUNT(*) as count FROM midnight_codes")
    local count = totalCodes and totalCodes[1] and totalCodes[1].count or 0
    
    if count > 0 then

        MySQL.query.await("DELETE FROM midnight_codes")

        SendToDiscord(
            "🗑️ All Codes Cleared",
            string.format("**Console Command Executed:** All %d codes have been cleared from the database.\n\n**Warning:** This action cannot be undone!", count),
            15158332,
            nil,
            "admin"
        )
        
        
        print(("[midnight_redeem] SUCCESS: All %d codes have been cleared from database"):format(count))
    else
        
        print("[midnight_redeem] No codes found to clear")
    end
end)

RegisterCommand("adminredeem", function(src)
    if src == 0 then
        print("[MR][SERVER] /adminredeem cannot be used from console")
        return
    end

    if blockIfDead(src) then
        return
    end

    if not Checkadmin(src) then
        return
    end
    
    local allData = {
        stats = _dashboardData.stats or {},
        weekly = _dashboardData.weekly or {},
        daily = _dashboardData.daily or {},
        codes = _dashboardData.codes or {},
        allCodes = _dashboardData.allCodes or {},
        rewards = _dashboardData.rewards or {}
    }
    
    TriggerClientEvent("midnight-redeem:openAdminMenu", src)
    registerAdminClient(src)
    TriggerClientEvent("midnight-redeem:sendAllDashboardData", src, allData)
end, false)

RegisterCommand("redeemcode", function(src)
    if src == 0 then
        print("[MR][SERVER] /redeemcode cannot be used from console")
        return
    end
    if blockIfDead(src) then
        return
    end
    TriggerClientEvent("midnight-redeem:redeemcode", src)
end, false)

      function generateCodeFromPattern(pattern, index)
    local code = pattern

    code = code:gsub("{RANDOM:(%d+)}", function(length)
        local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        local result = ""
        for i = 1, tonumber(length) do
            result = result .. chars:sub(math.random(1, #chars), math.random(1, #chars))
        end
        return result
    end)
    
    code = code:gsub("{NUMBER:(%d+)}", function(length)
        return string.format("%0" .. length .. "d", index)
    end)
    
    code = code:gsub("{DATE}", function()
        return os.date("%Y-%m-%d")
    end)
    
    code = code:gsub("{TIME}", function()
        return os.date("%H-%M")
    end)
    
    code = code:gsub("{PREFIX:(%d+)}", function(length)
        local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        local result = ""
        for i = 1, tonumber(length) do
            result = result .. chars:sub(math.random(1, #chars), math.random(1, #chars))
        end
        return result
    end)
    
    code = code:gsub("{SUFFIX:(%d+)}", function(length)
        local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        local result = ""
        for i = 1, tonumber(length) do
            result = result .. chars:sub(math.random(1, #chars), math.random(1, #chars))
        end
        return result
    end)

    if #code > 60 then
        code = code:sub(1, 60)
    end
    
    return code
end

function HandleBulkCodeGeneration(source, amount, pattern, uses, perUserLimit, expiryHours, rewards)
    local hasPlayer = (type(source) == "number" and source > 0)

    if hasPlayer and not AdminHasPermission(source, "CREATE_CODES") then
        local message = GetRequirePermission()
            and "You don't have permission to create codes. Contact an owner/manager for access."
            or (locales("NOTIFY_PERMISSION_DENIED") or "Permission denied.")
        if hasPlayer then
            Bridge.Notify.SendNotify(source, message, "error", 6000)
        end
        return false
    end

    if not amount or amount < 1 or amount > 10000 then
        if hasPlayer then
            Bridge.Notify.SendNotify(source, "Invalid amount. Must be between 1 and 10,000.", "error", 6000)
        end
        return false
    end
    
    if not pattern or pattern:gsub("^%s*(.-)%s*$", "%1") == "" then
        if hasPlayer then
            Bridge.Notify.SendNotify(source, "Invalid pattern. Please provide a valid code pattern.", "error", 6000)
        end
        return false
    end
    
    if not uses or uses < 1 then
        if hasPlayer then
            Bridge.Notify.SendNotify(source, "Invalid uses. Must be at least 1.", "error", 6000)
        end
        return false
    end
    
    if not perUserLimit or perUserLimit < 1 then
        perUserLimit = 1
    end
    
    if not expiryHours or expiryHours < 1 then
        expiryHours = 24
    end
    
    if not rewards or #rewards == 0 then
        if hasPlayer then
            Bridge.Notify.SendNotify(source, "No rewards specified. Please add at least one reward.", "error", 6000)
        end
        return false
    end
    
    local playerName = hasPlayer and (GetPlayerName(source) or "ingame moderator") or "bulk generation"
    local itemsJson = json_encode(rewards)
    local expiryDays = expiryHours / 24
    
    local generatedCodes = {}
    local failedCodes = {}
    local duplicateCodes = {}

    local existingCodes = {}
    local modifiedPattern = pattern:gsub("{[^}]+}", "%%")
    local result = MySQL.query.await("SELECT code FROM midnight_codes WHERE code LIKE ?", { modifiedPattern })
    if result then
        for _, row in ipairs(result) do
            existingCodes[row.code] = true
        end
    end

    for i = 1, amount do
        local code = generateCodeFromPattern(pattern, i)

        local attempts = 0
        while (existingCodes[code] or generatedCodes[code]) and attempts < 10 do
            code = generateCodeFromPattern(pattern, i + attempts * 1000)
            attempts = attempts + 1
        end
        
        if attempts >= 10 then
            table.insert(failedCodes, { pattern = pattern, index = i, reason = "Could not generate unique code after 10 attempts" })
        elseif existingCodes[code] then
            table.insert(duplicateCodes, code)
        else

            local success = CreateRedeemCodeDirectly(code, itemsJson, uses, expiryDays, perUserLimit, playerName)
            
            if success then
                generatedCodes[code] = true
                existingCodes[code] = true
            else
                table.insert(failedCodes, { pattern = pattern, index = i, reason = "Database insertion failed" })
            end
        end
    end

    if hasPlayer then
        local successCount = 0
        for _ in pairs(generatedCodes) do successCount = successCount + 1 end
        
        local message = string.format("Bulk generation complete!\n\n✅ Successfully generated: %d codes\n❌ Failed: %d codes\n⚠️ Duplicates found: %d codes",
            successCount, #failedCodes, #duplicateCodes)
        
        if #failedCodes > 0 then
            message = message .. "\n\nFailed codes:"
            for i, fail in ipairs(failedCodes) do
                if i <= 5 then
                    message = message .. string.format("\n❌ Pattern %s (index %d): %s", fail.pattern, fail.index, fail.reason)
                end
            end
            if #failedCodes > 5 then
                message = message .. string.format("\n... and %d more failures", #failedCodes - 5)
            end
        end
        
        TriggerClientEvent("midnight-redeem:sendUIToast", source, "Bulk Generation Complete", message, "success")
    end

    local successCount = 0
    for _ in pairs(generatedCodes) do successCount = successCount + 1 end

    local codeList = {}
    for code in pairs(generatedCodes) do
        table.insert(codeList, code)
    end
    table.sort(codeList)

    local displayCodes = {}
    
    for i = 1, #codeList do
        local code = ("`%s`"):format(codeList[i])
        table.insert(displayCodes, code)
    end
    
    local codesDisplay = table.concat(displayCodes, "\n")

    if #codeList > 15 then
        codesDisplay = codesDisplay .. ("\n\n**Total Codes Generated:** %d"):format(#codeList)
    end

    local _, rewardText = build_reward_lines(rewards)
    local message = string.format(
"**Admin:** `%s`\n**Action:** Bulk Code Generation\n**Pattern:** `%s`\n**Amount Requested:** `%d`\n**Successfully Generated:** `%d`\n**Failed:** `%d`\n**Duplicates Found:** `%d`\n\n**Settings:**\n⚙️ Uses per code: `%d`\n👤 Per-user limit: `%d`\n⏰ Expiry: `%d hours`\n\n**Rewards:**\n%s\n\n**Generated Codes:**\n%s",
        playerName, pattern, amount, successCount, #failedCodes, #duplicateCodes, uses, perUserLimit, expiryHours, rewardText, codesDisplay
    )

    SendToDiscordBulk("📦 Bulk Code Generation", message, 3066993)

    if successCount > 0 then
        refreshDashboardData(nil)
        broadcastDashboardAfterRefresh(hasPlayer and source or nil)
    end
    
    return successCount > 0
end

RegisterServerEvent("midnight-redeem:bulkGenerateCodes", function(amount, pattern, uses, perUserLimit, expiryHours, rewards)
    local src = source
    if not requireAdmin(src, "CREATE_CODES") then
        return Bridge.Notify.SendNotify(src, locales("NOTIFY_PERMISSION_DENIED"), "error", 6000)
    end
    HandleBulkCodeGeneration(src, amount, pattern, uses, perUserLimit, expiryHours, rewards)
end)

lib.callback.register("midnight-redeem:checkCodeName", function(source, codeName)
    if not requireAdmin(source, "CREATE_CODES") then
        return { valid = false, issues = { "Permission denied" } }
    end
    if not codeName or type(codeName) ~= "string" then
        return { valid = false, issues = {"Invalid code name"} }
    end
    
    local nameOk, issues = validateNewCodeName(codeName)
    return { valid = nameOk, issues = issues }
end)

lib.callback.register("midnight-redeem:getContentFilterStats", function(source)
    if not requireAdmin(source, "VIEW_DASHBOARD") then
        return { error = "Permission denied" }
    end
    
    local stats = ContentFilter.getStats()
    if stats then
        stats.categoriesList = nil
    end
    return stats
end)

lib.callback.register("midnight-redeem:getPreFilledRewards", function(source)
    if not requireAdmin(source, "VIEW_DASHBOARD") then
        return { success = false, error = "Permission denied" }
    end
    if Config.PreFilledRewards then
        return { success = true, data = Config.PreFilledRewards }
    else
        return { success = false, error = "No pre-filled rewards configured" }
    end
end)

lib.callback.register("midnight-redeem:saveTemplate", function(source, templateName, rewards)
    if not Checkadmin(source) then
        return { success = false, error = "Permission denied" }
    end
    
    if not templateName or not rewards then
        return { success = false, error = "Invalid template data" }
    end

    local rewardsOk, rewardsErr = validateRewardsPayload(rewards)
    if not rewardsOk then
        return { success = false, error = rewardsErr or "Invalid rewards." }
    end
    
    local playerName = GetPlayerName(source) or "Unknown"
    local identifier = Bridge.Framework.GetPlayerIdentifier(source)
    
    local success, err = pcall(function()

        local existing = MySQL.query.await('SELECT id FROM midnight_templates WHERE name = ? AND created_by = ?', {
            templateName, identifier
        })
        
        if existing and #existing > 0 then

            MySQL.update.await('UPDATE midnight_templates SET rewards = ?, updated_at = CURRENT_TIMESTAMP WHERE name = ? AND created_by = ?', {
                json_encode(rewards), templateName, identifier
            })
        else

            MySQL.insert.await('INSERT INTO midnight_templates (name, category, rewards, created_by) VALUES (?, ?, ?, ?)', {
                templateName, 'custom', json_encode(rewards), identifier
            })
        end
        
        print(string.format("[midnight_redeem] Template '%s' saved by player %s", templateName, playerName))
        return { success = true }
    end)
    
    if not success then
        print(string.format("[midnight_redeem] Error saving template '%s': %s", templateName, err))
        return { success = false, error = "Database error" }
    end
    
    return { success = true }
end)

lib.callback.register("midnight-redeem:getSavedTemplates", function(source)
    if not Checkadmin(source) then
        return { success = false, error = "Permission denied" }
    end
    
    local identifier = Bridge.Framework.GetPlayerIdentifier(source)
    
    local success, result = pcall(function()
        local templates = MySQL.query.await('SELECT name, category, rewards, created_at FROM midnight_templates WHERE created_by = ? ORDER BY created_at DESC', {
            identifier
        })
        
        if templates then

            for i, template in ipairs(templates) do
                if template.rewards then
                    template.rewards = json_decode(template.rewards)
                end
            end
            
            return { success = true, data = templates }
        else
            return { success = true, data = {} }
        end
    end)
    
    if not success then
        print(string.format("[midnight_redeem] Error loading templates: %s", result))
        return { success = false, error = "Database error" }
    end
    
    return result
end)

lib.callback.register("midnight-redeem:deleteSavedTemplate", function(source, templateName)
    if not Checkadmin(source) then
        return { success = false, error = "Permission denied" }
    end
    if not templateName or templateName == "" then
        return { success = false, error = "Invalid template name" }
    end
    local identifier = Bridge.Framework.GetPlayerIdentifier(source)
    local affected = MySQL.update.await('DELETE FROM midnight_templates WHERE name = ? AND created_by = ?', {
        templateName, identifier
    })
    if (affected or 0) > 0 then
        return { success = true }
    end
    return { success = false, error = "Template not found" }
end)

lib.callback.register("midnight-redeem:checkCodeRewards", function(source, code)
    if not code or code == "" then
        return { success = true, hasMoneyRewards = false }
    end
    
    local success, result = pcall(function()
        local rows = MySQL.query.await(
            'SELECT items FROM midnight_codes WHERE code = ? AND (expiry IS NULL OR expiry > NOW()) LIMIT 1',
            { code }
        )
        
        if not rows or #rows == 0 then
            return { success = true, hasMoneyRewards = false }
        end
        
        local items = rows[1].items
        if not items or items == "" then
            return { success = true, hasMoneyRewards = false }
        end

        local parsedItems = safe_json_decode(items, {})
        if type(parsedItems) ~= "table" then
            return { success = true, hasMoneyRewards = false }
        end

        local hasMoney = false
        for _, item in ipairs(parsedItems) do
            if (item.category == "money_options" and item.money) or item.money then
                hasMoney = true
                break
            end
        end
        
        return { success = true, hasMoneyRewards = hasMoney }
    end)
    
    if not success then
        return { success = true, hasMoneyRewards = false }
    end
    
    return result
end)

lib.callback.register("midnight-redeem:createCode", function(source, codeData)
    if not requireAdmin(source, "CREATE_CODES") then
        return { success = false, error = "Permission denied" }
    end
    
    if not codeData or not codeData.code or not codeData.rewards then
        return { success = false, error = "Invalid code data" }
    end

    local rewardsOk, rewardsErr = validateRewardsPayload(codeData.rewards)
    if not rewardsOk then
        return { success = false, error = rewardsErr or "Invalid rewards." }
    end

    local nameOk, issues = validateNewCodeName(codeData.code)
    if not nameOk then
        return { success = false, error = table.concat(issues, ", ") }
    end

    local itemsJson = json_encode(codeData.rewards)
    local expiryArg = codeData.expiryDays or codeData.expiry or 0
    HandleRedeemCode(
        source,
        itemsJson,
        codeData.uses or 1,
        expiryArg,
        codeData.code,
        codeData.perUserLimit or 1,
        nil,
        codeData.timeRestrictions,
        codeData.playerRestriction
    )

    local inserted = MySQL.scalar.await('SELECT code FROM midnight_codes WHERE code = ? LIMIT 1', { codeData.code })
    if inserted then
        return { success = true }
    end
    return { success = false, error = "Failed to create code." }
end)

      function OptimizeDatabaseConnection()
    local success = pcall(function()
        MySQL.query.await("SET SESSION wait_timeout = 28800")
        MySQL.query.await("SET SESSION interactive_timeout = 28800")
        MySQL.query.await("SET SESSION sql_mode = 'STRICT_TRANS_TABLES,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO'")
    end)
end

lib.callback.register("midnight-redeem:addReward", function(source, rewardData)
    if not requireAdmin(source, "VIEW_DASHBOARD") then
        return { success = false, error = "Permission denied" }
    end
    return { success = true, reward = rewardData }
end)

lib.callback.register("midnight-redeem:removeReward", function(source, rewardIndex)
    if not requireAdmin(source, "VIEW_DASHBOARD") then
        return { success = false, error = "Permission denied" }
    end
    return { success = true }
end)

lib.callback.register("midnight-redeem:updateReward", function(source, rewardIndex, rewardData)
    if not requireAdmin(source, "VIEW_DASHBOARD") then
        return { success = false, error = "Permission denied" }
    end
    return { success = true, reward = rewardData }
end)

      function CleanupExpiredCodes()
    if not Config.sqlCleanUpDays or Config.sqlCleanUpDays <= 0 then
        return
    end
    
    local success, result = pcall(function()
        local currentTime = os.time()
        local cleanupThreshold = currentTime - (Config.sqlCleanUpDays * 24 * 60 * 60)
        
        local codesToDelete = MySQL.query.await([[
            SELECT code, created_by, expiry, created_at
            FROM midnight_codes 
            WHERE expiry IS NOT NULL 
            AND expiry != 'Never'
            AND (
                (expiry > 1000000000000 AND FLOOR(expiry / 1000) <= ?) OR 
                (expiry <= 1000000000000 AND expiry <= ?) OR
                (expiry REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' AND expiry <= FROM_UNIXTIME(?))
            )
        ]], { cleanupThreshold, cleanupThreshold, cleanupThreshold })
        
        if codesToDelete and #codesToDelete > 0 then
            for _, codeData in ipairs(codesToDelete) do
                local expiryTime = "Unknown"
                if codeData.expiry then
                    if type(codeData.expiry) == "number" then
                        local timestamp = codeData.expiry
                        if timestamp > 1000000000000 then
                            timestamp = math.floor(timestamp / 1000)
                        end
                        expiryTime = os.date("%m/%d/%Y %H:%M", timestamp)
                    else
                        expiryTime = tostring(codeData.expiry)
                    end
                end
                
                local createdTime = "Unknown"
                if codeData.created_at then
                    if type(codeData.created_at) == "number" then
                        local timestamp = codeData.created_at
                        if timestamp > 1000000000000 then
                            timestamp = math.floor(timestamp / 1000)
                        end
                        createdTime = os.date("%m/%d/%Y %H:%M", timestamp)
                    else
                        createdTime = tostring(codeData.created_at)
                    end
                end
                
                local message = string.format(
                    "**Code:** `%s`\n**Creator:** `%s`\n**Created:** `%s`\n**Expired:** `%s`\n**Reason:** Auto-cleanup after %d days",
                    codeData.code or "Unknown",
                    codeData.created_by or "Unknown",
                    createdTime,
                    expiryTime,
                    Config.sqlCleanUpDays
                )
                
                SendToDiscord("🗑️ Code Auto-Cleaned", message, 15158332)
            end
            
            local deletedCount = MySQL.query.await([[
                DELETE FROM midnight_codes 
                WHERE expiry IS NOT NULL 
                AND expiry != 'Never'
                AND (
                    (expiry > 1000000000000 AND FLOOR(expiry / 1000) <= ?) OR 
                    (expiry <= 1000000000000 AND expiry <= ?) OR
                    (expiry REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' AND expiry <= FROM_UNIXTIME(?))
                )
            ]], { cleanupThreshold, cleanupThreshold, cleanupThreshold })
            
            return deletedCount and deletedCount.affectedRows or 0
        end
        
        return 0
    end)
    
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    
    Wait(250)
    
    OptimizeDatabaseConnection()
    
    CleanupExpiredCodes()
    if CleanupOldTranscripts then
        CleanupOldTranscripts()
    end
    
    CreateDailyCode()
    CheckExpiredUnusedCodes()
    CleanupOldCodes()
    
    refreshDashboardData(nil)
    
          function startRefreshTimer()
        if _refreshTimer then
            _refreshTimer = nil
        end
        
        _refreshTimer = CreateThread(function()
            while _refreshTimer do
                Wait(_refreshInterval * 1000)
                if not _isRefreshing and _refreshTimer then
                    refreshDashboardData(nil)
                end
            end
        end)
    end
    
    startRefreshTimer()
    
    CreateThread(function()
        while true do
            Wait(24 * 60 * 60 * 1000)
            CleanupExpiredCodes()
            if CleanupOldTranscripts then
                CleanupOldTranscripts()
            end
        end
    end)
end)

lib.callback.register("midnight-redeem:getUserPermissions", function(source)
    if not Checkadmin(source) then
        local defaultRole, defaultLevel = getDefaultRole()
        return { role = defaultRole, level = defaultLevel, permissions = buildUserPermissionFlags(source) }
    end

    local identifiers = GetPlayerIdentifiers(source)
    local userIdentifier = nil
    
    if identifiers then


        for _, identifier in ipairs(identifiers) do
            if string.find(identifier, "license2:") then
                userIdentifier = identifier
                break
            end
        end
        
        if not userIdentifier then
            for _, identifier in ipairs(identifiers) do
                if string.find(identifier, "discord:") then
                    userIdentifier = identifier
                    break
                end
            end
        end
        
        if not userIdentifier then
            for _, identifier in ipairs(identifiers) do
                if string.find(identifier, "steam:") then
                    userIdentifier = identifier
                    break
                end
            end
        end
        
        if not userIdentifier then
            for _, identifier in ipairs(identifiers) do
                if string.find(identifier, "license:") then
                    userIdentifier = identifier
                    break
                end
            end
        end
    end
    
    if not userIdentifier then
        local defaultRole, defaultLevel = getDefaultRole()
        return { role = defaultRole, level = defaultLevel }
    end

    -- Auto-assign DefaultRole to framework admins who don't have a permission record
    autoAssignDefaultRole(source, userIdentifier)

    local result = MySQL.single.await('SELECT role, permission_level FROM midnight_user_permissions WHERE identifier = ?', { userIdentifier })
    
    if result then
        return {
            role = result.role,
            level = result.permission_level,
            permissions = buildUserPermissionFlags(source)
        }
    else
        local defaultRole, defaultLevel = getDefaultRole()
        return {
            role = defaultRole,
            level = defaultLevel,
            permissions = buildUserPermissionFlags(source)
        }
    end
end)


lib.callback.register("midnight-redeem:dashboardStats", function(source)
    if not requireAdmin(source, "VIEW_DASHBOARD") then
        return {}
    end
    return _dashboardData.stats or {}
end)

RegisterNetEvent("midnight-redeem:registerAdminClient", function()
    if requireAdmin(source, "VIEW_DASHBOARD") then
        registerAdminClient(source)
        if RuntimeConfig and RuntimeConfig.syncToClient then
            RuntimeConfig.syncToClient(source)
        end
    end
end)

RegisterNetEvent("midnight-redeem:getDashboardStats", function()
    local src = source
    if not requireAdmin(src, "VIEW_DASHBOARD") then return end
    local result = _dashboardData.stats or {}
    local sanitizedResult = sanitizeForJSON(result)
    TriggerClientEvent("midnight-redeem:sendDashboardData", src, sanitizedResult)
end)

RegisterNetEvent("midnight-redeem:getAllCodesWithDetails", function()
    local src = source
    if not requireAdmin(src, "VIEW_DASHBOARD") then return end
    registerAdminClient(src)
    local result = _dashboardData.codes or {}
    TriggerClientEvent("midnight-redeem:sendCodesData", src, result)
end)

RegisterNetEvent("midnight-redeem:getAllCodesForSearch", function()
    local src = source
    if not requireAdmin(src, "VIEW_DASHBOARD") then return end
    registerAdminClient(src)
    local result = _dashboardData.allCodes or getAllCodesForSearch()
    TriggerClientEvent("midnight-redeem:sendAllCodesData", src, result)
end)

RegisterNetEvent("midnight-redeem:getWeeklyStats", function()
    local src = source
    if not requireAdmin(src, "VIEW_DASHBOARD") then return end
    local result = _dashboardData.weekly or {}
    TriggerClientEvent("midnight-redeem:sendWeeklyStats", src, result)
end)

RegisterNetEvent("midnight-redeem:getDailyStats", function()
    local src = source
    if not requireAdmin(src, "VIEW_DASHBOARD") then return end
    local result = _dashboardData.daily or {}
    TriggerClientEvent("midnight-redeem:sendDailyStats", src, result)
end)


RegisterNetEvent("midnight-redeem:refreshData", function()
    local src = source
    if not requireAdmin(src, "VIEW_DASHBOARD") then return end
    registerAdminClient(src)
    
    refreshDashboardData(src)
    
    CreateThread(function()
        while _isRefreshing do
            Wait(50)
        end
        
        pushDashboardToAdmins(buildAllDashboardData(), src)
        TriggerClientEvent("midnight-redeem:refreshComplete", src)
    end)
    
    if _refreshTimer then
        _refreshTimer = nil
    end
    
    CreateThread(function()
        Wait(100)
        _refreshTimer = CreateThread(function()
            while _refreshTimer do
                Wait(_refreshInterval * 1000)
                if not _isRefreshing and _refreshTimer then
                    refreshDashboardData(nil)
                end
            end
        end)
    end)
end)

RegisterCommand("refreshdashboard", function(source, args, rawCommand)
    if source > 0 and not requireAdmin(source, "VIEW_DASHBOARD") then
        return
    end
    refreshDashboardData(nil)
    if source > 0 then
        TriggerClientEvent("midnight-redeem:notifyUser", source, "Dashboard Refresh", "Dashboard data refreshed manually", "success")
    end
end, false)

RegisterCommand("mrperf", function(source, args, rawCommand)
    local totalQueries = _performanceCounters.queriesExecuted
    local cacheHits = _performanceCounters.cacheHits
    local cacheMisses = _performanceCounters.cacheMisses
    local cacheHitRate = totalQueries > 0 and (cacheHits / totalQueries) * 100 or 0
    
    local message = string.format(
        "[%s] Server Performance Stats:\n" ..
        "  Queries Executed: %d\n" ..
        "  Cache Hits: %d\n" ..
        "  Cache Misses: %d\n" ..
        "  Cache Hit Rate: %.2f%%\n" ..
        "  Cache Evictions: %d",
        GetCurrentResourceName(),
        totalQueries,
        cacheHits,
        cacheMisses,
        cacheHitRate,
        _performanceCounters.cacheEvictions
    )
    
    if source > 0 then
        TriggerClientEvent("midnight-redeem:notifyUser", source, "Performance Stats", message, "info")
    else
        print(message)
    end
end, false)

RegisterCommand("mrsetperm", function(source, args, rawCommand)
    if source ~= 0 then
        print("[midnight_redeem] mrsetperm is console-only.")
        return
    end

    if #args < 2 then
        local message = "Usage: mrsetperm <player_id> <role>\nRoles: staff, manager, owner"
        if source == 0 then
            print(message)
        else
            TriggerClientEvent("midnight-redeem:notifyUser", source, "Command Usage", message, "error")
        end
        return
    end
    
    local targetId = tonumber(args[1])
    local role = string.lower(args[2])
    
    if not targetId or not role then
        local message = "Invalid player ID or role"
        if source == 0 then
            print(message)
        else
            TriggerClientEvent("midnight-redeem:notifyUser", source, "Error", message, "error")
        end
        return
    end
    
    if not (role == "staff" or role == "manager" or role == "owner") then
        local message = "Invalid role. Use: staff, manager, or owner"
        if source == 0 then
            print(message)
        else
            TriggerClientEvent("midnight-redeem:notifyUser", source, "Error", message, "error")
        end
        return
    end
    
    local identifier = getUserIdentifier(targetId)
    if not identifier then
        local message = "Could not get identifier for player " .. targetId
        if source == 0 then
            print(message)
        else
            TriggerClientEvent("midnight-redeem:notifyUser", source, "Error", message, "error")
        end
        return
    end
    
    local level = PERMISSIONS[role:upper()]
    if not level then
        local message = "Invalid permission level for role: " .. role
        if source == 0 then
            print(message)
        else
            TriggerClientEvent("midnight-redeem:notifyUser", source, "Error", message, "error")
        end
        return
    end
    
    local success, error = pcall(function()
        MySQL.insert.await([[
            INSERT INTO midnight_user_permissions (identifier, role, permission_level) 
            VALUES (?, ?, ?) 
            ON DUPLICATE KEY UPDATE 
            role = VALUES(role), 
            permission_level = VALUES(permission_level)
        ]], { identifier, role, level })
    end)
    
    if success then
        invalidatePermissionCache(identifier)
        local message = string.format("Set player %d (%s) to %s (level %d)", targetId, identifier, role, level)
        print(message)
    else
        local message = "Failed to update permissions: " .. tostring(error)
        if source == 0 then
            print(message)
        else
            TriggerClientEvent("midnight-redeem:notifyUser", source, "Error", message, "error")
        end
    end
end, false)


RegisterNetEvent("midnight-redeem:getRewardsStats", function()
    local src = source
    if not requireAdmin(src, "VIEW_DASHBOARD") then return end
    local result = _dashboardData.rewards or getRewardsStats()
    TriggerClientEvent("midnight-redeem:sendRewardsStats", src, result)
end)

function getWeekStart(timestamp)
    local date = os.date("*t", timestamp)
    local dayOfWeek = date.wday
    local mondayOffset = (dayOfWeek == 1) and 6 or (dayOfWeek - 2)
    local weekStart = timestamp - (mondayOffset * 24 * 60 * 60)
    
    local weekStartDate = os.date("*t", weekStart)
    weekStartDate.hour = 0
    weekStartDate.min = 0
    weekStartDate.sec = 0
    
    return os.time(weekStartDate)
end

local TimeValidation = {}

function TimeValidation.isCodeTimeValid(timeRestrictions)
    if not timeRestrictions or not timeRestrictions.enabled then
        return true, nil
    end
    
    local currentTime = os.time()
    local currentDate = os.date("*t", currentTime)
    local currentHour = currentDate.hour
    local currentDay = currentDate.wday
    
    local restrictions = timeRestrictions.restrictions
    
    if timeRestrictions.type == "daily_hours" then
        return TimeValidation.checkDailyHours(currentHour, restrictions)
    elseif timeRestrictions.type == "weekly_days" then
        return TimeValidation.checkWeeklyDays(currentDay, restrictions)
    elseif timeRestrictions.type == "specific_dates" then
        return TimeValidation.checkSpecificDates(currentTime, restrictions)
    elseif timeRestrictions.type == "recurring" then
        return TimeValidation.checkRecurring(currentTime, currentDate, restrictions)
    end
    
    return true, nil
end

function TimeValidation.checkDailyHours(currentHour, restrictions)
    local startHour = restrictions.start_hour or 0
    local endHour = restrictions.end_hour or 23
    
    if startHour <= endHour then
        if currentHour >= startHour and currentHour <= endHour then
            return true, nil
        end
    else
        if currentHour >= startHour or currentHour <= endHour then
            return true, nil
        end
    end
    
    return false, "Code is only available between " .. startHour .. ":00 and " .. endHour .. ":00"
end

function TimeValidation.checkWeeklyDays(currentDay, restrictions)
    local allowedDays = restrictions.allowed_days or {}
    
    for _, day in ipairs(allowedDays) do
        if currentDay == day then
            return true, nil
        end
    end
    
    local dayNames = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}
    local allowedDayNames = {}
    for _, day in ipairs(allowedDays) do
        table.insert(allowedDayNames, dayNames[day])
    end
    
    return false, "Code is only available on " .. table.concat(allowedDayNames, ", ")
end

function TimeValidation.checkSpecificDates(currentTime, restrictions)
    local specificDates = restrictions.specific_dates or {}
    local currentDateStr = os.date("%Y-%m-%d", currentTime)
    
    for _, dateStr in ipairs(specificDates) do
        if currentDateStr == dateStr then
            return true, nil
        end
    end
    
    return false, "Code is only available on specific dates"
end

function TimeValidation.checkRecurring(currentTime, currentDate, restrictions)
    local recurringType = restrictions.recurring_type or "daily"
    local allowedDays = restrictions.recurring_days or {}
    local allowedHours = restrictions.recurring_hours or {}
    
    if recurringType == "daily" then
        if #allowedHours > 0 then
            return TimeValidation.checkDailyHours(currentDate.hour, {start_hour = allowedHours[1], end_hour = allowedHours[#allowedHours]})
        end
        return true, nil
    elseif recurringType == "weekly" then
        return TimeValidation.checkWeeklyDays(currentDate.wday, {allowed_days = allowedDays})
    elseif recurringType == "monthly" then
        local currentDay = currentDate.day
        for _, day in ipairs(allowedDays) do
            if currentDay == day then
                return true, nil
            end
        end
        return false, "Code is only available on specific days of the month"
    end
    
    return true, nil
end

function TimeValidation.getCurrentCycle(timeRestrictions)
    if not timeRestrictions or not timeRestrictions.enabled then
        return nil
    end
    
    local currentTime = os.time()
    local currentDate = os.date("*t", currentTime)
    local restrictions = timeRestrictions.restrictions
    
    if timeRestrictions.type == "daily_hours" then
        local today = os.date("%Y-%m-%d", currentTime)
        return "daily_" .. today
    elseif timeRestrictions.type == "weekly_days" then
        local weekStart = TimeValidation.getWeekStart(currentTime)
        return "weekly_" .. weekStart
    elseif timeRestrictions.type == "specific_dates" then
        local today = os.date("%Y-%m-%d", currentTime)
        for _, dateStr in ipairs(restrictions.specific_dates or {}) do
            if today == dateStr then
                return "specific_" .. dateStr
            end
        end
        return nil
    elseif timeRestrictions.type == "recurring" then
        local recurringType = restrictions.recurring_type or "daily"
        if recurringType == "daily" then
            local today = os.date("%Y-%m-%d", currentTime)
            return "recurring_daily_" .. today
        elseif recurringType == "weekly" then
            local weekStart = TimeValidation.getWeekStart(currentTime)
            return "recurring_weekly_" .. weekStart
        elseif recurringType == "monthly" then
            local monthStart = os.date("%Y-%m-01", currentTime)
            return "recurring_monthly_" .. monthStart
        end
    end
    
    return nil
end

function TimeValidation.getWeekStart(timestamp)
    local date = os.date("*t", timestamp)
    local daysSinceMonday = (date.wday - 2) % 7
    if daysSinceMonday < 0 then
        daysSinceMonday = daysSinceMonday + 7
    end
    local weekStart = timestamp - (daysSinceMonday * 24 * 60 * 60)
    return os.date("%Y-%m-%d", weekStart)
end

function TimeValidation.getUserCycleRedemptions(userCycleRedemptions, currentCycle)
    if not userCycleRedemptions or not currentCycle then
        return {}
    end
    
    local redemptions = json.decode(userCycleRedemptions or "{}")
    return redemptions[currentCycle] or {}
end

function TimeValidation.updateUserCycleRedemptions(userCycleRedemptions, currentCycle, userId)
    local redemptions = json.decode(userCycleRedemptions or "{}")
    
    if not redemptions[currentCycle] then
        redemptions[currentCycle] = {}
    end
    
    redemptions[currentCycle][userId] = (redemptions[currentCycle][userId] or 0) + 1
    
    return json.encode(redemptions)
end

function TimeValidation.cleanupOldCycles(userCycleRedemptions, timeRestrictions)
    if not userCycleRedemptions then
        return userCycleRedemptions
    end
    
    local redemptions = json.decode(userCycleRedemptions or "{}")
    local currentTime = os.time()
    local cleaned = {}
    
    local thirtyDaysAgo = currentTime - (30 * 24 * 60 * 60)
    
    for cycleId, cycleData in pairs(redemptions) do
        local cycleTime = TimeValidation.getCycleTimestamp(cycleId, timeRestrictions)
        if cycleTime and cycleTime > thirtyDaysAgo then
            cleaned[cycleId] = cycleData
        end
    end
    
    return json.encode(cleaned)
end

function TimeValidation.getCycleTimestamp(cycleId, timeRestrictions)
    if not cycleId then return nil end
    
    if string.find(cycleId, "^daily_") then
        local dateStr = string.gsub(cycleId, "^daily_", "")
        return os.time(os.date("*t", dateStr .. " 00:00:00"))
    elseif string.find(cycleId, "^weekly_") then
        local dateStr = string.gsub(cycleId, "^weekly_", "")
        return os.time(os.date("*t", dateStr .. " 00:00:00"))
    elseif string.find(cycleId, "^specific_") then
        local dateStr = string.gsub(cycleId, "^specific_", "")
        return os.time(os.date("*t", dateStr .. " 00:00:00"))
    elseif string.find(cycleId, "^recurring_") then
        local dateStr = string.gsub(cycleId, "^recurring_[^_]+_", "")
        return os.time(os.date("*t", dateStr .. " 00:00:00"))
    end
    
    return nil
end

local function roleToLevel(roleName)
    local roleUpper = string.upper(roleName or "")
    return PERMISSIONS[roleUpper] or 0
end

local function buildPermissionActions()
    local actions = {}
    
    local config = exports[resourceName]:GetPermissionActionsConfig() or PERMISSION_ACTIONS_CONFIG
    
    if config then
        for actionName, roles in pairs(config) do
            if type(roles) == "table" then
                actions[actionName] = {}
                for _, role in ipairs(roles) do
                    local level = roleToLevel(role)
                    if level > 0 then
                        table.insert(actions[actionName], level)
                    end
                end
                table.sort(actions[actionName], function(a, b) return a > b end)
            end
        end
    end
    
    if not actions.CREATE_CODES then
        actions.CREATE_CODES = { PERMISSIONS.OWNER, PERMISSIONS.MANAGER, PERMISSIONS.STAFF }
        actions.EDIT_CODES = { PERMISSIONS.OWNER, PERMISSIONS.MANAGER }
        actions.DELETE_CODES = { PERMISSIONS.OWNER, PERMISSIONS.MANAGER }
        actions.VIEW_DASHBOARD = { PERMISSIONS.OWNER, PERMISSIONS.MANAGER, PERMISSIONS.STAFF }
        actions.MANAGE_PERMISSIONS = { PERMISSIONS.OWNER, PERMISSIONS.MANAGER }
        actions.COLOR_SETTINGS = { PERMISSIONS.OWNER, PERMISSIONS.MANAGER, PERMISSIONS.STAFF }
        actions.FULL_ACCESS = { PERMISSIONS.OWNER, PERMISSIONS.MANAGER }
        print("[midnight_redeem] WARNING: PERMISSION_ACTIONS_CONFIG not found in permissions.lua, using defaults")
    end
    
    return actions
end

local PERMISSION_ACTIONS = buildPermissionActions()

function getUserIdentifier(source)
    local identifiers = GetPlayerIdentifiers(source)
    if identifiers then


        for _, identifier in ipairs(identifiers) do
            if string.find(identifier, "license2:") then
                return identifier
            end
        end

        for _, identifier in ipairs(identifiers) do
            if string.find(identifier, "license:") then
                return identifier
            end
        end

        for _, identifier in ipairs(identifiers) do
            if string.find(identifier, "steam:") then
                return identifier
            end
        end

        for _, identifier in ipairs(identifiers) do
            if string.find(identifier, "discord:") then
                return identifier
            end
        end
    end

    local player = Bridge.Framework.GetPlayer(source)
    if player then 

        local license = player.getIdentifier and player.getIdentifier('license') or player.license
        if license then 
            return license 
        end

        local steam = player.getIdentifier and player.getIdentifier('steam') or player.steam
        if steam then 
            return steam 
        end

        local discord = player.getIdentifier and player.getIdentifier('discord') or player.discord
        if discord then 
            return discord 
        end
    end

    local playerName = GetPlayerName(source)
    if playerName then

    end

    return nil
end

local function isOwner(source)
    local playerIdentifier = getUserIdentifier(source)
    if not playerIdentifier then
        return false
    end
    
    -- Reload from exports in case it was updated (required for escrow communication)
    local ownerLicenses = exports[resourceName]:GetOwnerLicenses() or OWNER_LICENSES
    for _, ownerLicense in ipairs(ownerLicenses) do
        if playerIdentifier == ownerLicense then
            return true
        end
    end
    
    return false
end

local function getUserPermissionLevel(source)
    
    local identifier = getUserIdentifier(source)
    
    if not identifier then 
         return nil
    end

    if isOwner(source) then
        return PERMISSIONS.OWNER or 3
    end

    local cached = _permissionCache[identifier]
    if cached and (os.time() - cached.ts) < PERM_CACHE_TTL then
        return cached.level
    end

    if not _permissionsTableReady then
        local tableExists = MySQL.query.await('SHOW TABLES LIKE "midnight_user_permissions"')
        if not tableExists or #tableExists == 0 then
            local defaultRole, defaultLevel = getDefaultRole()
            MySQL.query.await(string.format([[
                CREATE TABLE IF NOT EXISTS midnight_user_permissions (
                    identifier VARCHAR(255) NOT NULL COLLATE 'utf8mb3_general_ci',
                    role VARCHAR(20) NOT NULL DEFAULT '%s' COLLATE 'utf8mb3_general_ci',
                    permission_level INT NOT NULL DEFAULT %d,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                    PRIMARY KEY (identifier),
                    INDEX idx_role (role),
                    INDEX idx_permission_level (permission_level)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci
            ]], defaultRole, defaultLevel))
        end
        _permissionsTableReady = true
    end

    local success, result = pcall(function()
        local queryResult = MySQL.query.await('SELECT permission_level FROM midnight_user_permissions WHERE identifier = ? LIMIT 1', { identifier })
        if queryResult and #queryResult > 0 then
            return queryResult[1]
        end
        return nil
    end)
    
    if not success then
        return nil
    end
       
    if result then
        _permissionCache[identifier] = { level = result.permission_level, ts = os.time() }
        return result.permission_level
    end

    _permissionCache[identifier] = { level = 0, ts = os.time() }
    return 0
end

local function getUserRole(source)
    local identifier = getUserIdentifier(source)
    if not identifier then return nil end

    if isOwner(source) then
        return "owner"
    end

    local result = MySQL.query.await('SELECT role FROM midnight_user_permissions WHERE identifier = ? LIMIT 1', { identifier })
    if result and #result > 0 then
        return result[1].role
    end

    return nil
end

function getUserRoleByIdentifier(identifier)
    if not identifier then return nil end

    local tableExists = MySQL.query.await('SHOW TABLES LIKE "midnight_user_permissions"')
    if not tableExists or #tableExists == 0 then
        local defaultRole, defaultLevel = getDefaultRole()
        MySQL.query.await(string.format([[
            CREATE TABLE IF NOT EXISTS midnight_user_permissions (
                identifier VARCHAR(255) NOT NULL COLLATE 'utf8mb3_general_ci',
                role VARCHAR(20) NOT NULL DEFAULT '%s' COLLATE 'utf8mb3_general_ci',
                permission_level INT NOT NULL DEFAULT %d,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (identifier),
                INDEX idx_role (role),
                INDEX idx_permission_level (permission_level)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci
        ]], defaultRole, defaultLevel))
    end
    
    local result = MySQL.single.await('SELECT role FROM midnight_user_permissions WHERE identifier = ?', { identifier })
     return result and result.role or nil
end

function getUserPermissionLevelByIdentifier(identifier)
    if not identifier then return 0 end
    
    local role = getUserRoleByIdentifier(identifier)
    if not role then return 0 end
    
    return PERMISSIONS[role:upper()] or 0
end

buildUserPermissionFlags = function(source)
    return {
        canCreate = AdminHasPermission(source, "CREATE_CODES"),
        canEdit = AdminHasPermission(source, "EDIT_CODES"),
        canDelete = AdminHasPermission(source, "DELETE_CODES"),
        canViewDashboard = AdminHasPermission(source, "VIEW_DASHBOARD"),
        canManagePermissions = AdminHasPermission(source, "MANAGE_PERMISSIONS"),
        canAccessColorSettings = AdminHasPermission(source, "COLOR_SETTINGS"),
        hasFullAccess = AdminHasPermission(source, "FULL_ACCESS")
    }
end

hasPermission = function(source, action) 
    if not GetRequirePermission() then
         return true
    end
    
    local userLevel = getUserPermissionLevel(source)
    
    if not userLevel then
        return false
    end
    
    local requiredLevels = PERMISSION_ACTIONS[action]
    
    if not requiredLevels then
        return false
    end
    
    for _, level in ipairs(requiredLevels) do
        if userLevel >= level then
            return true
        end
    end
    
    return false
end

local function setUserRole(source, targetSource, newRole)
    if not AdminHasPermission(source, "MANAGE_PERMISSIONS") then
        return false, "Insufficient permissions"
    end
    
    if not PERMISSIONS[newRole:upper()] then
        return false, "Invalid role"
    end
    
    -- Prevent users from changing their own permissions
    if source == targetSource then
        return false, "You cannot change your own permissions"
    end
    
    local sourceIdentifier = getUserIdentifier(source)
    local targetIdentifier = getUserIdentifier(targetSource)
    
    if not targetIdentifier then
        return false, "Target player not found"
    end
    
    -- Double check: prevent changing own permissions by identifier
    if sourceIdentifier and targetIdentifier and sourceIdentifier == targetIdentifier then
        return false, "You cannot change your own permissions"
    end

    MySQL.insert.await([[
        INSERT INTO midnight_user_permissions (identifier, role, permission_level) 
        VALUES (?, ?, ?) 
        ON DUPLICATE KEY UPDATE 
        role = VALUES(role), 
        permission_level = VALUES(permission_level)
    ]], {
        targetIdentifier,
        newRole:lower(),
        PERMISSIONS[newRole:upper()]
    })

    invalidatePermissionCache(targetIdentifier)
    
    return true, "Role updated successfully"
end

local function setUserRoleByIdentifier(source, targetIdentifier, newRole)
    if not AdminHasPermission(source, "MANAGE_PERMISSIONS") then
        return false, "Insufficient permissions"
    end
    
    if not PERMISSIONS[newRole:upper()] then
        return false, "Invalid role"
    end
    
    if not targetIdentifier or targetIdentifier == "" then
        return false, "Target identifier not provided"
    end
    
    local sourceIdentifier = getUserIdentifier(source)
    
    -- Prevent users from changing their own permissions
    if sourceIdentifier and targetIdentifier and sourceIdentifier == targetIdentifier then
        return false, "You cannot change your own permissions"
    end
    
    -- Verify the target user exists in the database
    local existingUser = MySQL.single.await('SELECT identifier, role FROM midnight_user_permissions WHERE identifier = ?', { targetIdentifier })
    if not existingUser then
        return false, "User not found in database"
    end
    
    -- Prevent non-owners from changing owner roles
    if existingUser.role == "owner" and getUserRole(source) ~= "owner" then
        return false, "Only owners can change other owners' roles"
    end

    MySQL.insert.await([[
        INSERT INTO midnight_user_permissions (identifier, role, permission_level) 
        VALUES (?, ?, ?) 
        ON DUPLICATE KEY UPDATE 
        role = VALUES(role), 
        permission_level = VALUES(permission_level)
    ]], {
        targetIdentifier,
        newRole:lower(),
        PERMISSIONS[newRole:upper()]
    })
    
    invalidatePermissionCache(targetIdentifier)

    -- Notify the player if they're online
    for _, player in pairs(GetPlayers()) do
        local playerId = tonumber(player)
        local playerIdentifier = getUserIdentifier(playerId)
        if playerIdentifier == targetIdentifier then
            Bridge.Notify.SendNotify(playerId, "Your role has been updated to: " .. newRole, "info", 5000)
            break
        end
    end
    
    return true, "Role updated successfully"
end

local function grantOwnerPermission(source)
    if not isOwner(source) then
        print("SECURITY: owner attempted to use owner command from source please add in server/permissions.lua:", source)
        return false, "Hardcoded owner license required"
    end
    
    local identifier = getUserIdentifier(source)
    if not identifier then
        print("SECURITY: Could not get identifier for owner command from source:", source)
        return false, "Could not get user identifier"
    end

    local playerName = GetPlayerName(source)
    
    local existingRole = getUserRoleByIdentifier(identifier)
    if existingRole == "owner" then
        return false, "You already have owner permissions"
    end

    MySQL.insert.await([[
        INSERT INTO midnight_user_permissions (identifier, role, permission_level) 
        VALUES (?, ?, ?) 
        ON DUPLICATE KEY UPDATE 
        role = VALUES(role), 
        permission_level = VALUES(permission_level)
    ]], {
        identifier,
        "owner",
        PERMISSIONS.OWNER
    })
    
    return true, "Owner permission granted to owner"
end

local function removeUserPermissions(source)
    local identifier = getUserIdentifier(source)
    if identifier then
        MySQL.query.await('DELETE FROM midnight_user_permissions WHERE identifier = ?', { identifier })
    end
end

local function getAllUserPermissions()
    local results = MySQL.query.await('SELECT * FROM midnight_user_permissions ORDER BY permission_level DESC, identifier ASC')
    if not results then
        return {}
    end

    local identifierToSource = {}
    for _, player in pairs(GetPlayers()) do
        local playerId = tonumber(player)
        if playerId then
            local playerIdentifier = getUserIdentifier(playerId)
            if playerIdentifier then
                identifierToSource[playerIdentifier] = playerId
            end
        end
    end

    local users = {}
    local existingUsers = {}
    for _, row in ipairs(results) do
        local playerSource = identifierToSource[row.identifier]
        local playerName = row.player_name or "Unknown Player"

        if playerSource then
            local player = Bridge.Framework.GetPlayer(playerSource)
            if player then
                if player.getName then
                    playerName = player.getName()
                elseif player.name then
                    playerName = player.name
                elseif player.get then
                    playerName = player.get('name') or player.get('firstname') or (player.get('charinfo') and player.get('charinfo').firstname)
                end
            end

            if playerName == "Unknown Player" or not playerName then
                local fallbackName = GetPlayerName(playerSource)
                if fallbackName and fallbackName ~= "Unknown Player" then
                    playerName = fallbackName
                end
            end

            if playerName and playerName ~= "Unknown Player" then
                local nameParts = {}
                for part in string.gmatch(playerName, "[^%s]+") do
                    table.insert(nameParts, part)
                end
                if #nameParts > 0 then
                    playerName = nameParts[1]
                end

                if row.player_name ~= playerName then
                    MySQL.update.await(
                        'UPDATE midnight_user_permissions SET player_name = ? WHERE identifier = ?',
                        { playerName, row.identifier }
                    )
                end
            end
        elseif playerName and playerName ~= "Unknown Player" then
            local nameParts = {}
            for part in string.gmatch(playerName, "[^%s]+") do
                table.insert(nameParts, part)
            end
            if #nameParts > 0 then
                playerName = nameParts[1]
            end
        end

        table.insert(users, {
            source = playerSource,
            identifier = row.identifier,
            name = playerName,
            role = row.role,
            level = row.permission_level,
            online = playerSource ~= nil
        })

        existingUsers[row.identifier] = true
    end
    
    for _, player in pairs(GetPlayers()) do
        local playerSource = tonumber(player)
        local identifier = getUserIdentifier(playerSource)
        
        if identifier and not existingUsers[identifier] then
            local playerName = "Unknown Player"
            local player = Bridge.Framework.GetPlayer(playerSource)
            
            if player then
                if player.getName then
                    playerName = player.getName()
                elseif player.name then
                    playerName = player.name
                elseif player.get then
                    playerName = player.get('name') or player.get('firstname') or player.get('charinfo') and player.get('charinfo').firstname
                end
            end

            if playerName == "Unknown Player" or not playerName then
                local fallbackName = GetPlayerName(playerSource)
                if fallbackName and fallbackName ~= "Unknown Player" then
                    playerName = fallbackName
                end
            end

            if playerName and playerName ~= "Unknown Player" then
                local nameParts = {}
                for part in string.gmatch(playerName, "[^%s]+") do
                    table.insert(nameParts, part)
                end
                if #nameParts > 0 then
                    playerName = nameParts[1]
                end
            end
            
            table.insert(users, {
                source = playerSource,
                identifier = identifier,
                name = playerName,
                role = nil,
                level = 0,
                online = true
            })
        end
    end

    return users
end

exports('PrepareAdminAccess', PrepareAdminAccess)
exports('hasPermission', hasPermission)
exports('getUserRole', getUserRole)
exports('getUserPermissionLevel', getUserPermissionLevel)
exports('setUserRole', setUserRole)
exports('grantOwnerPermission', grantOwnerPermission)
exports('removeUserPermissions', removeUserPermissions)
exports('getAllUserPermissions', getAllUserPermissions)

AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local source = source
    local identifier = getUserIdentifier(source)
    
    if identifier then

        local playerName = GetPlayerName(source)
        if playerName and playerName ~= "Unknown Player" then

            MySQL.query.await([[
                UPDATE midnight_user_permissions 
                SET player_name = ? 
                WHERE identifier = ?
            ]], { playerName, identifier })
        end
    end
end)

AddEventHandler('playerJoining', function(oldID)
    local source = source
    local identifier = getUserIdentifier(source)
    
    if identifier then

        Wait(2000)
        
        local playerName = GetPlayerName(source)
        if playerName and playerName ~= "Unknown Player" then

            MySQL.query.await([[
                UPDATE midnight_user_permissions 
                SET player_name = ? 
                WHERE identifier = ?
            ]], { playerName, identifier })
        end
    end
end)






RegisterCommand("midnight_admin_init", function(source, args)
    local success, message = grantOwnerPermission(source)
    if success then
        Bridge.Notify.SendNotify(source, "Owner permission granted successfully!", "success", 5000)
    else
        if message == "owner license required" then
            Bridge.Notify.SendNotify(source, "You are not added as an owner. Contact server admin to add your license to server/permissions.lua", "error", 8000)
        else
            Bridge.Notify.SendNotify(source, message, "error", 5000)
        end
    end
end, false)

RegisterCommand("checkowner", function(source, args)
    local isOwner = isOwner(source)
    
    if isOwner then
        Bridge.Notify.SendNotify(source, "You are a owner", "success", 5000)
    else
        Bridge.Notify.SendNotify(source, "You are NOT a owner", "error", 5000)
    end
end, false)

RegisterCommand('redeemrole', function(source, args)
    if not AdminHasPermission(source, "MANAGE_PERMISSIONS") then
        Bridge.Notify.SendNotify(source, "You don't have permission to manage roles. Contact an owner/manager for access.", "error", 8000)
        return
    end
    
    if #args < 2 then
        Bridge.Notify.SendNotify(source, "Usage: /redeemrole <player_id> <role>", "error", 5000)
        return
    end
    
    local targetId = tonumber(args[1])
    local newRole = args[2]:lower()
    
    if not targetId or not newRole then
        Bridge.Notify.SendNotify(source, "Invalid arguments", "error", 5000)
        return
    end
    
    local success, message = setUserRole(source, targetId, newRole)
    if success then
        Bridge.Notify.SendNotify(source, "Role updated successfully", "success", 5000)
        Bridge.Notify.SendNotify(targetId, "Your role has been updated to: " .. newRole, "info", 5000)
    else
        Bridge.Notify.SendNotify(source, message, "error", 5000)
    end
end, false)


lib.callback.register("midnight-redeem:getAllUserPermissions", function(source)
     local userRole = getUserRole(source)
     local userLevel = getUserPermissionLevel(source)
     
     if not AdminHasPermission(source, "MANAGE_PERMISSIONS") then
        return {}
    end
    
    local users = getAllUserPermissions()
    return users
end)

lib.callback.register("midnight-redeem:updateUserPermission", function(source, identifier, newRole)
    if not AdminHasPermission(source, "MANAGE_PERMISSIONS") then
        return { success = false, message = "Insufficient permissions" }
    end
    
    if not identifier or identifier == "" then
        return { success = false, message = "Identifier not provided" }
    end
    
    local targetIdentifier = identifier
    
    -- Backwards compatibility: If identifier is a number, it might be a playerId (source ID)
    -- Try to get identifier from online player first
    local numericId = tonumber(identifier)
    if numericId and numericId > 0 then
        local playerIdentifier = getUserIdentifier(numericId)
        if playerIdentifier then
            -- Player is online, use their identifier
            targetIdentifier = playerIdentifier
        end
        -- If player not online, use identifier as-is (will be checked in setUserRoleByIdentifier)
    end
    
    local success, message = setUserRoleByIdentifier(source, targetIdentifier, newRole)
    return { success = success, message = message }
end)

lib.callback.register("midnight-redeem:purgeCodes", function(source, period, includeActive)
    if not AdminHasPermission(source, "DELETE_CODES") then
        local message = GetRequirePermission()
            and "You don't have permission to purge codes. Contact an owner/manager for access."
            or "You do not have permission."
        return { success = false, message = message }
    end
    
    local days = 0
    local isAllPeriod = false
    
    if not period then
        return { success = false, message = "Period not specified." }
    end
    
    period = tostring(period):lower()
    
    if period == "day" then
        days = 1
    elseif period == "week" then
        days = 7
    elseif period == "month" then
        days = 30
    elseif period == "all" then
        isAllPeriod = true
    else
        return { success = false, message = "Invalid period specified: " .. tostring(period) }
    end
    
    includeActive = includeActive == true
    
    CreateThread(function()
        local codesToDelete
        if isAllPeriod then
            -- Get all codes when period is "all"
            local query = [[
                SELECT code, created_by, created_at, uses, expiry 
                FROM midnight_codes
            ]]
            codesToDelete = MySQL.query.await(query, {})
        else
            local currentTime = os.time()
            local cutoffTimestamp = currentTime - (days * 86400)
            local cutoffDate = os.date("%Y-%m-%d", cutoffTimestamp)
            
            local query = [[
                SELECT code, created_by, created_at, uses, expiry 
                FROM midnight_codes 
                WHERE DATE(created_at) >= ?
            ]]
            
            codesToDelete = MySQL.query.await(query, { cutoffDate })
        end
        
        if not codesToDelete or #codesToDelete == 0 then
            TriggerClientEvent("midnight-redeem:sendUIToast", source, "Purge Codes", "No codes found to purge.", "info")
            return
        end
        
        local codesToRemove = {}
        local now = os.time()
        
        for _, codeData in ipairs(codesToDelete) do
            local shouldDelete = true
            
            if not includeActive then
                local isActive = false
                local uses = tonumber(codeData.uses) or 0
                
                if uses > 0 then
                    local expiry = codeData.expiry
                    if not expiry or expiry == "Never" or expiry == "" then
                        isActive = true
                    else
                        local expiryTime = nil
                        if type(expiry) == "string" and expiry:match("^%d%d%d%d%-%d%d%-%d%d") then
                            expiryTime = os.time({year = tonumber(expiry:sub(1,4)), month = tonumber(expiry:sub(6,7)), day = tonumber(expiry:sub(9,10)), hour = tonumber(expiry:sub(12,13)) or 0, min = tonumber(expiry:sub(15,16)) or 0, sec = tonumber(expiry:sub(18,19)) or 0})
                        elseif type(expiry) == "number" then
                            if expiry > 1000000000000 then
                                expiryTime = math.floor(expiry / 1000)
                            else
                                expiryTime = expiry
                            end
                        end
                        
                        if expiryTime and expiryTime > now then
                            isActive = true
                        end
                    end
                end
                
                if isActive then
                    shouldDelete = false
                end
            end
            
            if shouldDelete then
                table.insert(codesToRemove, codeData.code)
            end
        end
        
        if #codesToRemove == 0 then
            TriggerClientEvent("midnight-redeem:sendUIToast", source, "Purge Codes", "No codes found to purge (all codes are active and you chose to exclude them).", "info")
            return
        end
        
        local placeholders = {}
        for i = 1, #codesToRemove do
            placeholders[i] = "?"
        end
        
        local deleteQuery = string.format([[
            DELETE FROM midnight_codes 
            WHERE code IN (%s)
        ]], table.concat(placeholders, ","))
        
        local affected = MySQL.update.await(deleteQuery, codesToRemove)
        
        if (affected or 0) > 0 then
            refreshDashboardData(nil)
            local adminName = GetPlayerName(source) or "Unknown"
            local periodText = period == "day" and "1 day" or (period == "week" and "1 week" or (period == "month" and "1 month" or "all codes"))
            local activeText = includeActive and " (including active)" or " (excluding active)"
            SendToDiscord(
                "🗑️ Codes Purged",
                string.format("**Admin:** `%s`\n**Period:** `%s`%s\n**Codes Deleted:** `%d`\n\n**Warning:** This action cannot be undone!", adminName, periodText, activeText, affected),
                15158332,
                nil,
                "admin"
            )
            TriggerClientEvent("midnight-redeem:sendUIToast", source, "Purge Codes", string.format("Successfully purged %d codes.", affected), "success")
        else
            TriggerClientEvent("midnight-redeem:sendUIToast", source, "Purge Codes", "Failed to purge codes.", "error")
        end
    end)
    
    return { success = true, count = 0, message = "Purge operation started. You will be notified when it completes." }
end)

lib.callback.register("midnight-redeem:deleteUser", function(source, identifier)
    if not AdminHasPermission(source, "MANAGE_PERMISSIONS") then
        return { success = false, message = "Insufficient permissions" }
    end

    local userIdentifier = getUserIdentifier(source)
    if userIdentifier == identifier then
        return { success = false, message = "You cannot delete yourself" }
    end

    local userRole = getUserRoleByIdentifier(identifier)
    if not userRole then
        return { success = false, message = "User not found" }
    end

    if userRole == "owner" and getUserRole(source) ~= "owner" then
         return { success = false, message = "Only owners can delete other owners" }
    end

    local tableExists = MySQL.query.await('SHOW TABLES LIKE "midnight_user_permissions"')
    if not tableExists or #tableExists == 0 then
        local defaultRole, defaultLevel = getDefaultRole()
        MySQL.query.await(string.format([[
            CREATE TABLE IF NOT EXISTS midnight_user_permissions (
                identifier VARCHAR(255) NOT NULL COLLATE 'utf8mb3_general_ci',
                role VARCHAR(20) NOT NULL DEFAULT '%s' COLLATE 'utf8mb3_general_ci',
                permission_level INT NOT NULL DEFAULT %d,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (identifier),
                INDEX idx_role (role),
                INDEX idx_permission_level (permission_level)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci
        ]], defaultRole, defaultLevel))
        
    end

    local success = MySQL.query.await('DELETE FROM midnight_user_permissions WHERE identifier = ?', { identifier })
    if success then
        return { success = true, message = "User deleted successfully" }
    else
        return { success = false, message = "Failed to delete user" }
    end
end)

local function _resolveWebhook(routeOrUrl)
    if type(routeOrUrl) == "string" and routeOrUrl:find("^https?://") then
        return routeOrUrl
    end

    local key = tostring(routeOrUrl or "default")
    local convarName = "mredeem:webhook_" .. key
    local cv = (GetConvar and GetConvar(convarName, "")) or ""
    if cv and cv ~= "" then
        return cv
    end

    if Config and Config.Webhooks and routeOrUrl and Config.Webhooks[routeOrUrl] then
        return Config.Webhooks[routeOrUrl]
    end
    if Config and Config.Webhooks and Config.Webhooks.default then
        return Config.Webhooks.default
    end

    if webhookUrl and webhookUrl ~= "" then
        return webhookUrl
    end

    return nil
end

local function _dbg(msg)
    if msg then
        print("[midnight_redeem] " .. tostring(msg))
    end
end

local _fivemanageSystemUsed = nil

local function IsFiveManageSDKAvailable()
    local sdkInfo = DiscoverFMExports()
    return sdkInfo ~= nil and (sdkInfo.logExport ~= nil or #sdkInfo.availableExports > 0)
end

local _fmsdkExportInfo = nil

local function DiscoverFMExports()
    if _fmsdkExportInfo then
        return _fmsdkExportInfo
    end
    
    local resourceNames = {"fmsdk", "fivemanage_sdk", "fivemanage"}
    local foundResource = nil
    
    for _, name in ipairs(resourceNames) do
        if GetResourceState(name) == "started" then
            foundResource = name
            break
        end
    end
    
    if not foundResource then
        return nil
    end
    
    local sdkExports = exports[foundResource] or exports.fmsdk
    if not sdkExports then
        return nil
    end
    
    local availableExports = {}
    local logExport = nil
    
    local success, exportsTable = pcall(function()
        return sdkExports
    end)
    
    if success and type(exportsTable) == "table" then
        local exportNames = {"Log", "LogMessage", "Info", "Error", "Warn", "Debug"}
        for _, name in ipairs(exportNames) do
            local exportSuccess, exportFunc = pcall(function()
                if foundResource then
                    local res = exports[foundResource]
                    if res then
                        return res[name]
                    end
                end
                local fm = exports.fmsdk
                if fm then
                    return fm[name]
                end
                return nil
            end)
            
            if exportSuccess and exportFunc and type(exportFunc) == "function" then
                table.insert(availableExports, name)
                if not logExport and (name == "LogMessage" or name == "Log") then
                    logExport = name
                end
            end
        end
        
        if not logExport and #availableExports == 0 then
            local pairsSuccess, _ = pcall(function()
                for k, v in pairs(exportsTable) do
                    if type(v) == "function" then
                        table.insert(availableExports, tostring(k))
                        if not logExport and (k == "LogMessage" or k == "Log") then
                            logExport = tostring(k)
                        end
                    end
                end
            end)
        end
    end
    
    _fmsdkExportInfo = {
        resource = foundResource,
        exports = sdkExports,
        availableExports = availableExports,
        logExport = logExport
    }
    
    return _fmsdkExportInfo
end

local function SendToFiveManage(level, message, metadata)
    local sdkInfo = DiscoverFMExports()
    if sdkInfo then
        local success, err = pcall(function()
            local dataset = metadata and metadata.dataset or "default"
            local sdkMetadata = {}
            if metadata then
                for k, v in pairs(metadata) do
                    if k ~= "dataset" then
                        sdkMetadata[k] = v
                    end
                end
            end
            
            local sdkExports = sdkInfo.exports
            
            if sdkInfo.logExport then
                if sdkInfo.logExport == "LogMessage" then
                    sdkExports:LogMessage(level or "info", message or "", sdkMetadata)
                elseif sdkInfo.logExport == "Log" then
                    sdkExports:Log(dataset, level or "info", message or "", sdkMetadata)
                else
                    local logFunc = sdkExports[sdkInfo.logExport]
                    if type(logFunc) == "function" then
                        logFunc(level or "info", message or "", sdkMetadata)
                    end
                end
            elseif sdkExports.Info and (level == "info" or not level) then
                sdkExports:Info(dataset, message or "", sdkMetadata)
            elseif sdkExports.Error and level == "error" then
                sdkExports:Error(dataset, message or "", sdkMetadata)
            elseif sdkExports.Warn and level == "warn" then
                sdkExports:Warn(dataset, message or "", sdkMetadata)
            else
                if #sdkInfo.availableExports > 0 then
                    local firstExport = sdkInfo.availableExports[1]
                    local exportFunc = sdkExports[firstExport]
                    if exportFunc then
                        exportFunc(dataset, level or "info", message or "", sdkMetadata)
                    else
                        error(string.format("No usable export found. Available: %s", table.concat(sdkInfo.availableExports, ", ")))
                    end
                else
                    error("SDK exports found but no usable log function")
                end
            end
        end)
        
        if success then
            return true
        else
            if _fivemanageSystemUsed ~= "sdk_failed" then
                print(string.format("^3[midnight_redeem]^7 FiveManage SDK detected but call failed: %s. Falling back to API.^7", tostring(err)))
                _fivemanageSystemUsed = "sdk_failed"
            end
            _dbg(string.format("^3[FiveManage] SDK call failed, falling back to API: %s^7", tostring(err)))
        end
    end
    
    local resourceState = GetResourceState("fmsdk")
    if resourceState ~= "started" and _fivemanageSystemUsed ~= "api" and _fivemanageSystemUsed ~= "sdk_failed" then
        print(string.format("^3[midnight_redeem]^7 FiveManage SDK not found (resource state: %s). Checking for API key...^7", tostring(resourceState)))
    end
    
    local apiKey = GetConvar("FIVEMANAGE_LOGS_API_KEY", "")
    if not apiKey or apiKey == "" then
        if resourceState ~= "started" then
            if _fivemanageSystemUsed ~= "error" then
                print("^1[midnight_redeem]^7 FiveManage logging: ^1ERROR^7 - No SDK found (fmsdk not started) and no API key found. Ensure fmsdk is started or set FIVEMANAGE_LOGS_API_KEY in server.cfg")
                _fivemanageSystemUsed = "error"
            end
            _dbg("^1[FiveManage] No SDK found and no API key found. Install fmsdk resource or set FIVEMANAGE_LOGS_API_KEY in server.cfg^7")
        end
        return false
    end

    if _fivemanageSystemUsed ~= "api" then
        print("^3[midnight_redeem]^7 FiveManage logging: Using ^3Direct API^7 (FIVEMANAGE_LOGS_API_KEY from server.cfg)")
        _fivemanageSystemUsed = "api"
    end

    local url = "https://api.fivemanage.com/api/logs"
    local headers = {
        ['Authorization'] = apiKey,
        ['Content-Type'] = 'application/json',
        ['X-Fivemanage-Dataset'] = (metadata and metadata.dataset) or 'default'
    }

    local payload = {
        level = level or "info",
        message = message or "",
        metadata = metadata or {}
    }

    PerformHttpRequest(url, function(err, text, headers)
        if err ~= 200 and err ~= 201 then
            _dbg(string.format("^1[FiveManage] Failed to send log. HTTP %s | Response: %s^7", tostring(err), tostring(text)))
        end
    end, 'POST', json.encode(payload), headers)

    return true
end

local function SendToDiscordWebhook(title, message, color, extraFields, routeOrUrl)
    local routeKey = routeOrUrl or (extraFields and extraFields.__webhook) or "default"
    local url = _resolveWebhook(routeKey)
    if not url or url == "" then
        print("[midnight_redeem] [ERROR] No Discord webhook URL found for route: " .. tostring(routeKey))
        print("[midnight_redeem] [INFO] Please set: setr mredeem:webhook_" .. tostring(routeKey) .. " <your_webhook_url>")
        return
    end

    local embed = {{
        ["title"]       = title,
        ["description"] = message,
        ["color"]       = color or 16777215,
        ["footer"]      = { ["text"] = "Midnight Redeem System" },
        ["timestamp"]   = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time())
    }}

    if extraFields and type(extraFields) == "table" then
        for k, v in pairs(extraFields) do
            if k ~= "__webhook" and k ~= "__webhook_url" then
                embed[1][k] = v
            end
        end
    end

    local payload = json.encode({ embeds = embed })
    PerformHttpRequest(url, function(err, text, headers)
        if err ~= 204 then
            print("[midnight_redeem] [ERROR] Discord webhook failed!")
            print("[midnight_redeem] [ERROR] Route: " .. tostring(routeKey))
            print("[midnight_redeem] [ERROR] HTTP Status: " .. tostring(err))
            print("[midnight_redeem] [ERROR] Response: " .. tostring(text))
        else
            print("[midnight_redeem] [SUCCESS] Discord webhook sent to route: " .. tostring(routeKey))
        end
    end, 'POST', payload, { ['Content-Type'] = 'application/json' })
end

function SendToDiscord(title, message, color, extraFields, routeOrUrl)
    local logSystem = (Config and Config.Logsystem) or "discord"
    
    local level = "info"
    if title and (string.find(title, "[Ee]rror") or string.find(title, "[Ff]ailed") or string.find(title, "[Ww]arning")) then
        level = "error"
    elseif title and (string.find(title, "[Ww]arn")) then
        level = "warn"
    elseif title and (string.find(title, "[Dd]ebug")) then
        level = "debug"
    end

    local metadata = {
        title = title,
        color = color or 16777215,
        route = routeOrUrl or "default",
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time())
    }

    if extraFields and type(extraFields) == "table" then
        for k, v in pairs(extraFields) do
            if k ~= "__webhook" and k ~= "__webhook_url" then
                metadata[k] = v
            end
        end
    end

    if logSystem == "discord" or logSystem == "both" then
        SendToDiscordWebhook(title, message, color, extraFields, routeOrUrl)
    end

    if logSystem == "fivemanage" or logSystem == "both" then
        local fullMessage = string.format("[%s] %s", title or "Log", message or "")
        SendToFiveManage(level, fullMessage, metadata)
    end
end

function SendToDiscordDaily(title, message, color, extraFields)
    return SendToDiscord(title, message, color, extraFields, "daily")
end

function SendToDiscordBulk(title, message, color, extraFields)
    return SendToDiscord(title, message, color, extraFields, "admin")
end