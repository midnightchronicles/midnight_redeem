local Bridge = exports['community_bridge']:Bridge()

local RESOURCE = GetCurrentResourceName()
local GITHUB_API = "https://api.github.com/repos/midnightchronicles/midnight_redeem/releases/latest"
local RELEASES_URL = "https://github.com/midnightchronicles/midnight_redeem/releases"
local CACHE_TTL = 3600

VersionCheck = VersionCheck or {}

local cache = {
    checkedAt = 0,
    checking = false,
    current = nil,
    latest = nil,
    latestTag = nil,
    updateAvailable = false,
    aheadOfRelease = false,
    releaseNotes = nil,
    releaseUrl = nil,
    error = nil,
}

local function getCurrentVersion()
    return GetResourceMetadata(RESOURCE, "version", 0) or "0.0.0"
end

local function normalizeVersionTag(tag)
    return tostring(tag or ""):gsub("^[vV]%s*", "")
end

local function parseVersionParts(version)
    local normalized = normalizeVersionTag(version)
    local major, minor, patch = normalized:match("^(%d+)%.(%d+)%.(%d+)")
    if not major then
        major, minor = normalized:match("^(%d+)%.(%d+)")
        patch = 0
    end
    if not major then
        return nil
    end
    return tonumber(major), tonumber(minor), tonumber(patch or 0)
end

local function compareVersions(a, b)
    local am, an, ap = parseVersionParts(a)
    local bm, bn, bp = parseVersionParts(b)
    if not am or not bm then
        return 0
    end
    if am ~= bm then return am > bm and 1 or -1 end
    if an ~= bn then return an > bn and 1 or -1 end
    if ap ~= bp then return ap > bp and 1 or -1 end
    return 0
end

local function isRemoteNewer(current, remote)
    return compareVersions(current, remote) < 0
end

local function isLocalAhead(current, remote)
    return compareVersions(current, remote) > 0
end

local function formatReleaseNotes(body)
    body = tostring(body or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    body = body:gsub("^%s+", ""):gsub("%s+$", "")
    if body == "" then
        return nil
    end
    return body
end

local function logCheckResult(info)
    local current = info.current or getCurrentVersion()
    if info.error then
        print(("^1[midnight_redeem] Version check failed (%s). Installed: %s^7"):format(tostring(info.error), current))
        return
    end

    if info.updateAvailable then
        print(("^1[midnight_redeem] UPDATE AVAILABLE: installed %s -> latest %s^7"):format(current, info.latestTag or info.latest))
        print(("^1[midnight_redeem] Download: %s^7"):format(info.releaseUrl or RELEASES_URL))
        if info.releaseNotes and info.releaseNotes ~= "" then
            print("^1[midnight_redeem] Release notes:^7")
            for line in info.releaseNotes:gmatch("[^\n]+") do
                local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
                if trimmed ~= "" then
                    print(("^1  - %s^7"):format(trimmed))
                end
            end
        end
    elseif info.aheadOfRelease then
        print(("^3[midnight_redeem] Installed version %s is ahead of the latest public release (%s)^7"):format(
            current,
            info.latestTag or info.latest or "unknown"
        ))
    else
        print(("^2[midnight_redeem] Version %s is up to date (latest: %s)^7"):format(current, info.latestTag or info.latest or "unknown"))
    end
end

local function notifyAdminsIfUpdate(info)
    if not info.updateAvailable or info.error then
        return
    end

    local message = ("Midnight Redeem update available: %s"):format(info.latestTag or info.latest or "new version")
    for _, src in ipairs(GetPlayers()) do
        local playerId = tonumber(src)
        if playerId then
            pcall(function()
                if AdminIsBridgeOrAceAdmin(playerId) then
                    Bridge.Notify.SendNotify(playerId, message, "info", 10000)
                end
            end)
        end
    end
end

function VersionCheck.getInfo()
    if cache.current == nil then
        cache.current = getCurrentVersion()
    end

    return {
        current = cache.current,
        latest = cache.latest,
        latestTag = cache.latestTag,
        updateAvailable = cache.updateAvailable == true,
        aheadOfRelease = cache.aheadOfRelease == true,
        releaseNotes = cache.releaseNotes,
        releaseUrl = cache.releaseUrl or RELEASES_URL,
        error = cache.error,
        checkedAt = cache.checkedAt,
    }
end

function VersionCheck.refresh(force, done)
    if cache.checking then
        if done then done(VersionCheck.getInfo()) end
        return
    end

    if not force and cache.checkedAt > 0 and (os.time() - cache.checkedAt) < CACHE_TTL then
        if done then done(VersionCheck.getInfo()) end
        return
    end

    cache.checking = true
    cache.current = getCurrentVersion()

    PerformHttpRequest(GITHUB_API, function(status, body)
        cache.checking = false
        cache.checkedAt = os.time()

        if status ~= 200 or not body or body == "" then
            cache.error = "http_" .. tostring(status)
            if done then done(VersionCheck.getInfo()) end
            return
        end

        local ok, data = pcall(json.decode, body)
        if not ok or type(data) ~= "table" then
            cache.error = "parse_failed"
            if done then done(VersionCheck.getInfo()) end
            return
        end

        cache.latestTag = data.tag_name or data.name
        cache.latest = normalizeVersionTag(cache.latestTag)
        cache.releaseNotes = formatReleaseNotes(data.body)
        cache.releaseUrl = data.html_url or RELEASES_URL
        cache.updateAvailable = isRemoteNewer(cache.current, cache.latestTag)
        cache.aheadOfRelease = isLocalAhead(cache.current, cache.latestTag)
        cache.error = nil

        if done then done(VersionCheck.getInfo()) end
    end, "GET", "", { ["User-Agent"] = "midnight_redeem-version-check" })
end

lib.callback.register("midnight-redeem:getVersionInfo", function(_, forceRefresh)
    if not forceRefresh and cache.checkedAt > 0 and (os.time() - cache.checkedAt) < CACHE_TTL then
        return VersionCheck.getInfo()
    end

    local p = promise.new()
    VersionCheck.refresh(forceRefresh == true, function(info)
        p:resolve(info)
    end)
    return Citizen.Await(p)
end)

exports("GetVersionInfo", VersionCheck.getInfo)

AddEventHandler("onResourceStart", function(resource)
    if resource ~= RESOURCE then return end

    CreateThread(function()
        Wait(1500)
        VersionCheck.refresh(true, function(info)
            logCheckResult(info)
            notifyAdminsIfUpdate(info)
        end)
    end)
end)
