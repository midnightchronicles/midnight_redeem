local SHADOW_DEFAULT_MODEL = "gpt-4.1-mini"
local SHADOW_AI_CONTEXT_MESSAGES = 30
local ShadowBridge = exports['community_bridge']:Bridge()

local function getAIWelcomeMessage()
    return Config.AIWelcomeMessage or "hello, i'm shadow. tell me what code you want and i'll help draft it, validate it, and execute it when you're ready."
end

local function shadowGetIdentifier(src)
    local ids = GetPlayerIdentifiers(src) or {}
    for _, id in ipairs(ids) do
        if id:find("license2:", 1, true) then
            return id
        end
    end
    for _, id in ipairs(ids) do
        if id:find("license:", 1, true) then
            return id
        end
    end
    return ids[1]
end

local function shadowGenerateSessionId()
    local chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local out = {}
    for _ = 1, 24 do
        local idx = math.random(1, #chars)
        out[#out + 1] = chars:sub(idx, idx)
    end
    return "SID-" .. table.concat(out)
end

local function ensureRateLimitTable()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS midnight_ai_chat_rate_limit (
            id INT AUTO_INCREMENT PRIMARY KEY,
            identifier VARCHAR(255) NOT NULL COLLATE 'utf8mb3_general_ci',
            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_identifier_timestamp (identifier, timestamp),
            INDEX idx_timestamp (timestamp)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci
    ]])
end

local function shadowCheckRateLimit(identifier)
    local limit = tonumber(Config.AIChatRateLimit) or 0
    if limit <= 0 then
        return true
    end

    ensureRateLimitTable()
    local windowHours = tonumber(Config.AIChatRateLimitWindow) or 24
    local cutoffTime = os.time() - (windowHours * 3600)
    local result = MySQL.query.await(
        'SELECT COUNT(*) as count FROM midnight_ai_chat_rate_limit WHERE identifier = ? AND timestamp >= FROM_UNIXTIME(?)',
        { identifier, cutoffTime }
    )
    local count = (result and result[1] and tonumber(result[1].count)) or 0
    if count >= limit then
        return false, ("Shadow fair-use threshold reached (%d/%d in %dh). Ask an owner to raise limits if needed."):format(count, limit, windowHours)
    end
    return true
end

local function shadowRecordRateLimit(identifier)
    local limit = tonumber(Config.AIChatRateLimit) or 0
    if limit <= 0 then
        return
    end
    ensureRateLimitTable()
    MySQL.insert.await('INSERT INTO midnight_ai_chat_rate_limit (identifier, timestamp) VALUES (?, NOW())', { identifier })
end

local _shadowExecuteRateLimit = {}
local _shadowExecuteState = {}
local SHADOW_EXECUTE_COOLDOWN_MS = 2000
local SHADOW_EXECUTE_WAIT_MS = 15000

local function shadowWaitForExecuteResult(source)
    local start = GetGameTimer()
    while (GetGameTimer() - start) < SHADOW_EXECUTE_WAIT_MS do
        local state = _shadowExecuteState[source]
        if not state or not state.inFlight then
            return state and state.lastResult or nil
        end
        Wait(50)
    end
    return nil
end

local function shadowRunExecuteAction(source, action, payload, sessionId)
    local state = _shadowExecuteState[source]
    if state and state.inFlight then
        local waited = shadowWaitForExecuteResult(source)
        if waited then
            return waited
        end
        return { success = false, error = "Please wait before executing another action." }
    end

    local now = GetGameTimer()
    local last = _shadowExecuteRateLimit[source] or 0
    if (now - last) < SHADOW_EXECUTE_COOLDOWN_MS then
        if state and state.lastResult and state.lastResult.success then
            return state.lastResult
        end
        return { success = false, error = "Please wait before executing another action." }
    end

    _shadowExecuteState[source] = { inFlight = true, lastResult = nil }

    local ok, result = pcall(function()
        return shadowExecuteActionInternal(source, action, payload)
    end)
    if not ok or type(result) ~= "table" then
        result = { success = false, error = "Action failed due to a server error." }
    end

    _shadowExecuteState[source] = { inFlight = false, lastResult = result }
    _shadowExecuteRateLimit[source] = GetGameTimer()

    if sessionId and sessionId ~= "" then
        local displayMessage = result.message or result.error
        if displayMessage and displayMessage ~= "" then
            shadowStoreMessage(sessionId, "assistant", displayMessage)
        end
    end

    return result
end

local function shadowVerifySessionOwnership(source, sessionId)
    if not sessionId or sessionId == "" then
        return true
    end
    local identifier = shadowGetIdentifier(source)
    if not identifier then
        return false
    end
    local owner = MySQL.scalar.await('SELECT identifier FROM midnight_ai_chat_sessions WHERE session_id = ? LIMIT 1', { sessionId })
    return owner == identifier
end

local function shadowLoadRecentMessages(sessionId, maxCount)
    local rows = MySQL.query.await([[
        SELECT role, content FROM midnight_ai_chat_messages
        WHERE session_id = ?
        ORDER BY timestamp DESC
        LIMIT ?
    ]], { sessionId, maxCount }) or {}
    local out = {}
    for i = #rows, 1, -1 do
        local row = rows[i]
        if row.role and row.content then
            out[#out + 1] = { role = row.role, content = row.content }
        end
    end
    return out
end

local function shadowStoreMessage(sessionId, role, content)
    if not sessionId or sessionId == "" or not role or not content then
        return false
    end
    local ok = pcall(function()
        MySQL.insert.await('INSERT INTO midnight_ai_chat_messages (session_id, role, content) VALUES (?, ?, ?)', {
            sessionId, role, content
        })
        MySQL.update.await('UPDATE midnight_ai_chat_sessions SET updated_at = CURRENT_TIMESTAMP WHERE session_id = ?', { sessionId })
    end)
    return ok
end

local function shadowCreateSession(identifier, playerName)
    local attempts = 0
    while attempts < 12 do
        local sid = shadowGenerateSessionId()
        local exists = MySQL.scalar.await('SELECT session_id FROM midnight_ai_chat_sessions WHERE session_id = ? LIMIT 1', { sid })
        if not exists then
            MySQL.insert.await('INSERT INTO midnight_ai_chat_sessions (session_id, identifier, player_name) VALUES (?, ?, ?)', {
                sid, identifier, playerName
            })
            return sid
        end
        attempts = attempts + 1
    end
    return nil
end

local function tobool(v)
    return v == true or v == 1 or v == "1"
end

local function shadowIsEnabled()
    return Config.AIEnabled ~= false
end

local function AdminCanUse(src, permission)
    if not shadowIsEnabled() then
        return false
    end
    return AdminHasPermission(src, permission)
end

local function shadowFetchCodeByName(code)
    if not code or code == "" then
        return nil
    end
    local row = MySQL.query.await('SELECT * FROM midnight_codes WHERE code = ? LIMIT 1', { code })
    return row and row[1] or nil
end

local function shadowBuildCodeSummary(row)
    if not row then
        return "Code not found."
    end
    local restriction = "anyone"
    if tobool(row.restricted_to_enabled) then
        restriction = ("%s:%s"):format(tostring(row.restricted_to_type or "id"), tostring(row.restricted_to_value or ""))
    end
    return ("Code `%s` | uses `%s` | per-user `%s` | expiry `%s` | restriction `%s`"):format(
        tostring(row.code or "unknown"),
        tostring(row.uses or 0),
        tostring(row.per_user_limit or 1),
        tostring(row.expiry or "never"),
        restriction
    )
end

local function shadowBuildSystemPrompt()
    local webSearchEnabled = GetConvarInt("MREDEEM_AI_WEB_SEARCH", 0) == 1
    local webLine = webSearchEnabled
        and "You have live web search for general topics ONLY (weather, news, trivia). NEVER use web search for redeem codes — those always live in this server's Midnight Redeem database."
        or "You do not have web search in this environment — answer from general knowledge and say when something may be outdated."

    return ([[You are Shadow, a friendly assistant in the Midnight Redeem admin panel.
Personality:
- Relaxed, light humour, conversational, helpful with any topic.
- You specialise in redeem-code admin work, but normal chat is welcome (small talk, weather, general questions).

%s

CRITICAL — what "codes" means here:
- Any question about redeem codes, active codes, expired codes, or listing codes refers to THIS server's `midnight_codes` database only.
- Never list promo codes from the internet, other games, or external websites.
- For list/search/lookup requests, output the search or lookup action JSON — the server runs the database query and returns results.

Redeem-code specialty (when the admin asks):
1) Help create or update redeem codes.
2) Ensure required fields are complete: code, uses, perUserLimit, expiry, rewards, optional player restriction.
3) Support multiple rewards (item, money, vehicle).
4) Support lookup/search/edit for existing codes in the local database.

Action protocol (ONLY when the user wants create, update, lookup, or search — never for casual chat):
- Include ONE fenced JSON block:
```json
{
  "action": "create|update|lookup|search",
  "summary": "short human summary",
  "payload": { ... }
}
```
- `create.payload`: code, uses, perUserLimit, expiryDays (0 = never), rewards (array), playerRestriction { enabled, type, value } (optional)
- Rewards MUST be an array. Each entry uses one of these shapes:
  - Item: `{ "type": "item", "item": "water", "amount": 10 }`
  - Money: `{ "type": "money", "amount": 50000, "option": "cash" }`
  - Vehicle: `{ "type": "vehicle", "model": "asbo" }`
- Always include a unique `code` string in the payload (generate one if the user gave only a prefix).
- `update.payload`: originalCode, newCode (optional), uses, perUserLimit, expiry, rewards, playerRestriction (optional)
- `lookup.payload`: code
- `search.payload`: query (optional), filter (optional: active, expired, all). Use filter=active for non-expired codes with uses remaining.

Read-only actions (search, lookup) run automatically on the server — never paste raw JSON to the user for those.
For create/update, include the JSON block plus a short summary; the admin confirms before execution.
For general conversation, reply naturally with no JSON block.]]):format(webLine)
end

local function shadowMessageLooksCreateIntent(message)
    if type(message) ~= "string" then
        return false
    end
    local lower = message:lower()

    if lower:find("create", 1, true) or lower:find("generate", 1, true) or lower:find("add a code", 1, true) then
        return true
    end
    if lower:find("new code", 1, true) or lower:find("make .- code", 1) or lower:find("make me a code", 1, true) then
        return true
    end
    if lower:find("want a code", 1, true) or lower:find("want a new", 1, true) or lower:find("need a code", 1, true) then
        return true
    end
    if lower:find("with the prefix", 1, true) or lower:find("prefix is", 1, true) then
        return true
    end
    if (lower:find("i want", 1, true) or lower:find("i need", 1, true)) and lower:find("code", 1, true) then
        return true
    end
    if lower:find("reward", 1, true) and (lower:find("make", 1, true) or lower:find("want", 1, true) or lower:find("need", 1, true)) then
        return true
    end
    return false
end

local function shadowMessageLooksCodeRelated(message)
    if type(message) ~= "string" then
        return false
    end
    local lower = message:lower()
    local hints = {
        "code", "redeem", "reward", "expir", "uses", "lookup", "search",
        "create", "update", "edit", "coupon", "promo", "midnight", "restrict"
    }
    for _, word in ipairs(hints) do
        if lower:find(word, 1, true) then
            return true
        end
    end
    return false
end

local function shadowBuildActionHint(message)
    if shadowMessageLooksCreateIntent(message) then
        return [[The user wants to CREATE a new redeem code in the Midnight Redeem database.
Respond with a create action JSON (code, uses, perUserLimit, expiryDays, rewards).
If they gave a prefix (e.g. REFUND), generate a unique code like REFUND-A1B2.
Do NOT search, lookup, or use web search. Do NOT list external promo codes.]]
    end
    return [[The user wants to list or find existing codes in the Midnight Redeem database.
Respond with search or lookup action JSON only — never web search or external promo codes.
For "active" / "not expired" lists use action "search" with filter "active".]]
end

local function shadowRandomCodeSuffix(len)
    local chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    local out = {}
    for _ = 1, (len or 4) do
        local idx = math.random(1, #chars)
        out[#out + 1] = chars:sub(idx, idx)
    end
    return table.concat(out)
end

local function shadowParseRewardsFromMessage(message)
    local rewards = {}
    local lower = message:lower()

    local moneyAmount = message:match("[Mm]oney%s*:%s*(%d+)")
        or message:match("[Mm]oney%s+(%d+)")
        or message:match("(%d+)%s*[Mm]oney")
    if moneyAmount then
        rewards[#rewards + 1] = { money = true, option = "cash", amount = tonumber(moneyAmount) or 0 }
    end

    for amount, name in message:gmatch("(%d+)%s+([%w%-_]+)") do
        local word = name:lower()
        if word ~= "use" and word ~= "user" and word ~= "day" and word ~= "days" and word ~= "money" then
            if not lower:find("money", 1, true) or word ~= "money" then
                rewards[#rewards + 1] = { item = name, amount = tonumber(amount) or 1 }
            end
        end
    end

    for name, amount in message:gmatch("([%w%-_]+)%s*:%s*(%d+)") do
        if name:lower() ~= "money" then
            rewards[#rewards + 1] = { item = name, amount = tonumber(amount) or 1 }
        end
    end

    return #rewards > 0 and rewards or nil
end

local function shadowPickUniqueCode(baseCode)
    local code = tostring(baseCode or ""):gsub("^%s*(.-)%s*$", "%1"):upper()
    if code == "" then
        return nil
    end
    local existing = MySQL.scalar.await('SELECT code FROM midnight_codes WHERE code = ? LIMIT 1', { code })
    if not existing then
        return code
    end
    for _ = 1, 12 do
        local candidate = code .. "-" .. shadowRandomCodeSuffix(4)
        existing = MySQL.scalar.await('SELECT code FROM midnight_codes WHERE code = ? LIMIT 1', { candidate })
        if not existing then
            return candidate
        end
    end
    return code .. "-" .. shadowRandomCodeSuffix(6)
end

-- Build a create proposal directly from natural language when enough detail is present.
local function shadowParseCreateFromMessage(message)
    if not shadowMessageLooksCreateIntent(message) then
        return nil
    end

    local lower = message:lower()
    local uses = tonumber(message:match("(%d+)%s*uses?")) or tonumber(message:match("uses?%s*(%d+)")) or 1
    local perUserLimit = tonumber(message:match("(%d+)%s*user")) or tonumber(message:match("per%s*user%s*(%d+)")) or 1
    local expiryDays = tonumber(message:match("(%d+)%s*day")) or 0

    local prefix = message:match("[Pp]refix%s+([%w%-_]+)")
        or message:match("[Pp]refix%s+'([^']+)'")
        or message:match('[Pp]refix%s+"([^"]+)"')
    local explicitCode = message:match("[Cc]ode%s+['\"]([^'\"]+)['\"]")
        or message:match("[Cc]alled%s+([%w%-_]+)")

    local code = explicitCode
    if not code or code == "" then
        if prefix and prefix ~= "" then
            code = shadowPickUniqueCode(prefix:upper() .. "-" .. shadowRandomCodeSuffix(4))
        end
    else
        code = shadowPickUniqueCode(explicitCode)
    end

    local rewards = shadowParseRewardsFromMessage(message)
    if not code or not rewards then
        return nil
    end

    local rewardParts = {}
    for _, r in ipairs(rewards) do
        if r.money then
            rewardParts[#rewardParts + 1] = ("%d money"):format(r.amount or 0)
        elseif r.item then
            rewardParts[#rewardParts + 1] = ("%dx %s"):format(r.amount or 1, r.item)
        end
    end

    return {
        action = "create",
        summary = ("Create code `%s` with %d use(s), %d per user, %d day expiry — rewards: %s"):format(
            code, uses, perUserLimit, expiryDays, table.concat(rewardParts, ", ")
        ),
        payload = {
            code = code,
            uses = uses,
            perUserLimit = perUserLimit,
            expiryDays = expiryDays,
            rewards = rewards
        }
    }
end

-- Detect list/lookup requests and run them against midnight_codes directly (no web search).
local function shadowDetectLocalReadAction(message)
    if type(message) ~= "string" or message == "" then
        return nil
    end

    if shadowMessageLooksCreateIntent(message) then
        return nil
    end

    local lower = message:lower()
    if lower:find("update", 1, true) or lower:find("edit", 1, true) then
        return nil
    end

    if not lower:find("code", 1, true) and not lower:find("redeem", 1, true) then
        return nil
    end

    local lookupCode = message:match("[Ll]ookup%s+([%w%-_]+)")
        or message:match("[Dd]etails?%s+for%s+code%s+([%w%-_]+)")
        or message:match("[Ff]ind%s+code%s+([%w%-_]+)")
        or message:match("code%s+`([^`]+)`")
    if lookupCode and #lookupCode >= 2 then
        return { action = "lookup", payload = { code = lookupCode } }
    end

    local filter = nil
    if lower:find("not expired", 1, true) or lower:find("non%-expired", 1, true)
        or lower:find("still valid", 1, true) or lower:find("haven't expired", 1, true)
        or lower:find("have not expired", 1, true) then
        filter = "active"
    elseif lower:find("active", 1, true) and not lower:find("inactive", 1, true) then
        filter = "active"
    elseif lower:find("expired", 1, true) then
        filter = "expired"
    end

    local wantsList = filter ~= nil
        or lower:find("all code", 1, true)
        or lower:find("list code", 1, true)
        or lower:find("show code", 1, true)
        or lower:find("search code", 1, true)
        or lower:find("how many code", 1, true)
        or lower:find("find code", 1, true)
        or lower:find("lookup", 1, true)
        or (lower:find("give me", 1, true) and lower:find("code", 1, true) and not lower:find("give me a", 1, true))
        or (lower:find("get me", 1, true) and lower:find("code", 1, true) and not lower:find("get me a", 1, true))

    if not wantsList then
        return nil
    end

    local query = ""
    local partial = message:match("[Cc]ontaining%s+([%w%-_]+)")
        or message:match("[Nn]amed%s+([%w%-_]+)")
        or message:match("[Mm]atching%s+([%w%-_]+)")
    if partial then
        query = partial
    end

    return {
        action = "search",
        payload = {
            query = query,
            filter = filter or "all"
        }
    }
end

local function shadowExtractResponseText(data)
    if type(data) ~= "table" then
        return nil
    end

    if type(data.output_text) == "string" and data.output_text ~= "" then
        return data.output_text
    end

    local chunks = {}
    local seen = {}

    local function addChunk(text)
        if type(text) ~= "string" or text == "" or seen[text] then
            return
        end
        seen[text] = true
        chunks[#chunks + 1] = text
    end

    for _, entry in ipairs(data.output or {}) do
        if entry.type == "message" or entry.content then
            for _, c in ipairs(entry.content or {}) do
                if c.type == "output_text" and c.text then
                    addChunk(c.text)
                elseif c.type == "text" and c.text then
                    addChunk(c.text)
                end
            end
        elseif entry.type == "output_text" and entry.text then
            addChunk(entry.text)
        end
    end

    local text = table.concat(chunks, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
    return text ~= "" and text or nil
end

local function shadowCallOpenAI(messages, opts)
    opts = opts or {}
    local apiKey = GetConvar("MREDEEM_AI_API_KEY", "")
    if apiKey == "" then
        return nil, "AI API key missing. Set MREDEEM_AI_API_KEY in server.cfg."
    end

    local model = GetConvar("MREDEEM_AI_MODEL", SHADOW_DEFAULT_MODEL)
    local webSearchEnabled = GetConvarInt("MREDEEM_AI_WEB_SEARCH", 0) == 1
    if opts.allowWebSearch == false then
        webSearchEnabled = false
    end

    local payload = {
        model = model,
        input = messages,
        temperature = 0.5,
        max_output_tokens = 900
    }

    if webSearchEnabled then
        payload.tools = {
            { type = "web_search_preview" }
        }
    end

    local responseReady, responseText, responseError = false, nil, nil
    PerformHttpRequest("https://api.openai.com/v1/responses", function(statusCode, body)
        if statusCode ~= 200 and statusCode ~= 201 then
            local snippet = ""
            if type(body) == "string" and body ~= "" then
                snippet = body:sub(1, 180):gsub("%s+", " ")
            end
            responseError = ("OpenAI request failed (HTTP %s)%s"):format(
                tostring(statusCode),
                snippet ~= "" and (": " .. snippet) or ""
            )
            responseReady = true
            return
        end
        local ok, data = pcall(json.decode, body or "{}")
        if not ok or not data then
            responseError = "Failed to parse OpenAI response."
            responseReady = true
            return
        end

        responseText = shadowExtractResponseText(data)
        if not responseText then
            responseError = "AI returned an empty response."
        end
        responseReady = true
    end, "POST", json.encode(payload), {
        ["Authorization"] = "Bearer " .. apiKey,
        ["Content-Type"] = "application/json"
    })

    local start = GetGameTimer()
    while not responseReady and (GetGameTimer() - start) < 60000 do
        Wait(75)
    end
    if not responseReady then
        return nil, "OpenAI request timed out."
    end
    if responseError then
        return nil, responseError
    end
    return responseText, nil
end

local function shadowExtractAction(message)
    if type(message) ~= "string" then
        return nil
    end

    local candidates = {}
    local fenced = message:match("```json%s*(.-)%s*```")
    if fenced then
        candidates[#candidates + 1] = fenced
    end

    local trimmed = message:match("^%s*(.-)%s*$")
    if trimmed and trimmed:sub(1, 1) == "{" then
        candidates[#candidates + 1] = trimmed
    end

    local startPos = message:find('{"action"')
    if not startPos then
        startPos = message:find("{%s*\"action\"")
    end
    if startPos then
        candidates[#candidates + 1] = message:sub(startPos)
    end

    for _, raw in ipairs(candidates) do
        local ok, parsed = pcall(json.decode, raw)
        if ok and type(parsed) == "table" and type(parsed.action) == "string" and type(parsed.payload) == "table" then
            return parsed
        end
    end

    return nil
end

local function shadowStripActionJson(message)
    if type(message) ~= "string" then
        return ""
    end
    local cleaned = message:gsub("```json%s*.-%s*```", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if cleaned:sub(1, 1) == "{" then
        return ""
    end
    return cleaned
end

local function shadowInferSearchFilter(payload, summary)
    if type(payload) ~= "table" then
        return payload
    end
    if payload.filter and tostring(payload.filter) ~= "" then
        return payload
    end
    local hint = tostring(summary or ""):lower()
    if hint:find("not expired", 1, true) or hint:find("non%-expired", 1, true) then
        payload.filter = "active"
    elseif hint:find("active", 1, true) and not hint:find("inactive", 1, true) then
        payload.filter = "active"
    elseif hint:find("expired", 1, true) then
        payload.filter = "expired"
    end
    return payload
end

local function shadowSearchCodes(payload)
    payload = shadowInferSearchFilter(payload or {}, nil)
    local filter = tostring(payload.filter or ""):lower()
    local query = tostring(payload.query or ""):lower()
    local rows

    if filter == "active" then
        rows = MySQL.query.await([[
            SELECT code, uses, expiry, per_user_limit, restricted_to_enabled, restricted_to_type, restricted_to_value, created_by
            FROM midnight_codes
            WHERE uses > 0
              AND (expiry IS NULL OR expiry = '' OR expiry > NOW())
            ORDER BY created_at DESC
            LIMIT 50
        ]]) or {}
    elseif filter == "expired" then
        rows = MySQL.query.await([[
            SELECT code, uses, expiry, per_user_limit, restricted_to_enabled, restricted_to_type, restricted_to_value, created_by
            FROM midnight_codes
            WHERE expiry IS NOT NULL AND expiry <> '' AND expiry <= NOW()
            ORDER BY created_at DESC
            LIMIT 50
        ]]) or {}
    elseif query ~= "" then
        rows = MySQL.query.await([[
            SELECT code, uses, expiry, per_user_limit, restricted_to_enabled, restricted_to_type, restricted_to_value, created_by
            FROM midnight_codes
            WHERE LOWER(code) LIKE ? OR LOWER(created_by) LIKE ?
            ORDER BY created_at DESC
            LIMIT 25
        ]], { "%" .. query .. "%", "%" .. query .. "%" }) or {}
    else
        rows = MySQL.query.await([[
            SELECT code, uses, expiry, per_user_limit, restricted_to_enabled, restricted_to_type, restricted_to_value, created_by
            FROM midnight_codes
            ORDER BY created_at DESC
            LIMIT 25
        ]]) or {}
    end

    local lines = {}
    for _, row in ipairs(rows) do
        lines[#lines + 1] = shadowBuildCodeSummary(row)
    end

    local label = "codes"
    if filter == "active" then label = "active codes"
    elseif filter == "expired" then label = "expired codes"
    end

    if #lines == 0 then
        return { success = true, message = ("No %s in your Midnight Redeem database."):format(label), data = rows }
    end

    return {
        success = true,
        message = ("Found %d %s in your Midnight Redeem database:\n%s"):format(#lines, label, table.concat(lines, "\n")),
        data = rows
    }
end

local function shadowTrim(str)
    if type(str) ~= "string" then
        return ""
    end
    return str:gsub("^%s*(.-)%s*$", "%1")
end

local function shadowRewardAmount(reward)
    for _, key in ipairs({ "amount", "quantity", "count", "value", "qty" }) do
        local val = tonumber(reward[key])
        if val and val > 0 then
            return math.floor(val + 0.0001)
        end
    end
    return nil
end

local function shadowPushItem(out, name, amount)
    name = shadowTrim(tostring(name or ""))
    amount = math.floor(tonumber(amount) or 0)
    if name ~= "" and amount > 0 then
        out[#out + 1] = { item = name, amount = amount }
    end
end

local function shadowPushMoney(out, amount, option)
    amount = math.floor(tonumber(amount) or 0)
    if amount > 0 then
        out[#out + 1] = {
            money = true,
            option = shadowTrim(tostring(option or "cash")),
            amount = amount
        }
    end
end

local function shadowPushVehicle(out, model)
    model = shadowTrim(tostring(model or ""))
    if model ~= "" then
        out[#out + 1] = { vehicle = model, model = model, amount = 1 }
    end
end

local function shadowNormalizeSingleReward(reward, out)
    if type(reward) ~= "table" then
        return
    end

    local rtype = shadowTrim(tostring(reward.type or reward.rewardType or reward.kind or "")):lower()
    local itemName = reward.item or reward.itemName or reward.name
    if type(itemName) == "table" then
        itemName = itemName.name or itemName.label
    end

    local amount = shadowRewardAmount(reward)
    local isMoneyType = rtype == "money" or rtype == "cash" or rtype == "currency"
    local isVehicleType = rtype == "vehicle" or rtype == "car"
    local isItemType = rtype == "item"
    local looksLikeMoney = isMoneyType
        or (not isItemType and not isVehicleType and (
            reward.money == true
            or type(reward.money) == "number"
            or (type(reward.money) == "string" and tonumber(reward.money) ~= nil)
        ))

    if looksLikeMoney then
        local moneyAmount = amount
        if not moneyAmount and type(reward.money) == "number" then
            moneyAmount = math.floor(reward.money + 0.0001)
        elseif not moneyAmount and type(reward.money) == "string" then
            moneyAmount = tonumber(reward.money)
        end
        local option = reward.option or reward.account
        if not option and type(reward.money) == "string" and reward.money ~= "true" then
            option = reward.money
        end
        shadowPushMoney(out, moneyAmount, option)
        return
    end

    local model = reward.model or reward.vehicle
    if type(model) == "table" then
        model = model.model or model.name
    end
    if isVehicleType and not model and itemName then
        model = itemName
    end
    if model and (isVehicleType or reward.vehicle ~= nil or reward.model ~= nil) then
        shadowPushVehicle(out, model)
        return
    end

    if type(reward.item) == "string" and reward.item ~= "" then
        itemName = reward.item
    end
    if isItemType and not itemName and reward.label then
        itemName = reward.label
    end
    if itemName and not isMoneyType and not isVehicleType then
        shadowPushItem(out, itemName, amount or 1)
    end
end

local function shadowRewardsIsArrayLike(rawRewards)
    if #rawRewards > 0 then
        return true
    end
    for key in pairs(rawRewards) do
        if type(key) == "number" then
            return true
        end
    end
    return false
end

local function shadowRewardsIsStructuredContainer(rawRewards)
    return rawRewards.money ~= nil or rawRewards.items ~= nil or rawRewards.vehicles ~= nil
end

local function normalizeRewards(rawRewards)
    if type(rawRewards) == "string" then
        local ok, parsed = pcall(json.decode, rawRewards)
        if ok and type(parsed) == "table" then
            rawRewards = parsed
        else
            return nil
        end
    end
    if type(rawRewards) ~= "table" then
        return nil
    end

    local out = {}

    if shadowRewardsIsStructuredContainer(rawRewards) then
        if rawRewards.money ~= nil and type(rawRewards.money) ~= "boolean" then
            shadowPushMoney(out, rawRewards.money, rawRewards.option or rawRewards.account)
        end
        if type(rawRewards.items) == "table" then
            for key, value in pairs(rawRewards.items) do
                if type(key) == "number" and type(value) == "table" then
                    shadowNormalizeSingleReward(value, out)
                elseif type(key) == "string" and type(value) == "number" then
                    shadowPushItem(out, key, value)
                elseif type(value) == "string" then
                    shadowPushItem(out, value, 1)
                end
            end
        end
        if type(rawRewards.vehicles) == "table" then
            for _, value in ipairs(rawRewards.vehicles) do
                if type(value) == "string" then
                    shadowPushVehicle(out, value)
                else
                    shadowNormalizeSingleReward(value, out)
                end
            end
        end
    elseif shadowRewardsIsArrayLike(rawRewards) then
        for _, reward in ipairs(rawRewards) do
            shadowNormalizeSingleReward(reward, out)
        end
    else
        shadowNormalizeSingleReward(rawRewards, out)
    end

    return #out > 0 and out or nil
end

local function shadowNormalizeCreatePayload(payload)
    if type(payload) ~= "table" then
        return payload
    end

    local code = shadowTrim(tostring(payload.code or payload.codeName or payload.name or ""))
    if code == "" and payload.prefix then
        code = shadowPickUniqueCode(shadowTrim(tostring(payload.prefix)):upper() .. "-" .. shadowRandomCodeSuffix(4)) or ""
    end
    payload.code = code
    payload.uses = tonumber(payload.uses or payload.useLimit or 1) or 1
    payload.perUserLimit = tonumber(payload.perUserLimit or payload.per_user_limit or payload.perUser or 1) or 1
    payload.expiryDays = tonumber(payload.expiryDays or payload.expiry or payload.expiry_days or 0) or 0
    return payload
end

local function shadowExecuteActionInternal(source, action, payload)
    if type(action) ~= "string" then
        return { success = false, error = "Invalid action." }
    end
    if type(payload) ~= "table" then
        return { success = false, error = "Invalid action payload." }
    end

    if action == "create" then
        if not AdminCanUse(source, "CREATE_CODES") then
            return { success = false, error = "No permission to create codes." }
        end

        payload = shadowNormalizeCreatePayload(payload)

        local code = payload.code or ""
        local uses = payload.uses or 1
        local perUserLimit = payload.perUserLimit or 1
        local expiryDays = payload.expiryDays or 0
        local rewards = normalizeRewards(payload.rewards)
        if code == "" or not rewards then
            return { success = false, error = "Create payload missing code or valid rewards." }
        end

        if ContentFilter and ContentFilter.checkCodeName then
            local nameOk, _ = ContentFilter.checkCodeName(code)
            if not nameOk then
                return { success = false, error = "Code name is not allowed." }
            end
        end

        local restriction = payload.playerRestriction
        local itemsJson = json.encode(rewards)
        local existing = MySQL.scalar.await('SELECT code FROM midnight_codes WHERE code = ? LIMIT 1', { code })
        if existing then
            return { success = false, error = "That code already exists." }
        end

        local ok = pcall(function()
            exports["midnight_redeem"]:GenerateRedeemCode(
                source,
                itemsJson,
                uses,
                expiryDays,
                code,
                perUserLimit,
                "Shadow",
                nil,
                restriction
            )
        end)

        if not ok then
            return { success = false, error = "Failed to create code via server event." }
        end

        local inserted = MySQL.scalar.await('SELECT code FROM midnight_codes WHERE code = ? LIMIT 1', { code })
        if not inserted then
            return { success = false, error = "Create request was sent but code was not persisted." }
        end

        return { success = true, message = ("Code `%s` created successfully."):format(code) }
    end

    if action == "update" then
        if not AdminCanUse(source, "EDIT_CODES") then
            return { success = false, error = "No permission to edit codes." }
        end
        if not exports["midnight_redeem"] or not exports["midnight_redeem"].UpdateRedeemCodeInternal then
            return { success = false, error = "Update handler unavailable." }
        end

        local rewards = nil
        if payload.rewards ~= nil then
            local normalized = normalizeRewards(payload.rewards)
            if not normalized then
                return { success = false, error = "Update payload rewards are invalid." }
            end
            rewards = json.encode(normalized)
        end

        local updatePayload = {
            originalCode = payload.originalCode,
            newCode = payload.newCode,
            uses = payload.uses,
            perUserLimit = payload.perUserLimit,
            expiry = payload.expiry,
            itemsJson = rewards,
            playerRestriction = payload.playerRestriction
        }

        local result = exports["midnight_redeem"]:UpdateRedeemCodeInternal(source, updatePayload, { silent = true })
        if not result or not result.success then
            return { success = false, error = result and result.error or "Failed to update code." }
        end

        local outCode = (result.data and result.data.code) or payload.newCode or payload.originalCode
        return { success = true, message = ("Code `%s` updated successfully."):format(outCode), data = result.data or {} }
    end

    if action == "lookup" then
        if not AdminCanUse(source, "VIEW_DASHBOARD") then
            return { success = false, error = "No permission to view code details." }
        end
        local row = shadowFetchCodeByName(payload.code)
        if not row then
            return { success = false, error = "Code not found." }
        end
        return { success = true, message = shadowBuildCodeSummary(row), data = row }
    end

    if action == "search" then
        if not AdminCanUse(source, "VIEW_DASHBOARD") then
            return { success = false, error = "No permission to search codes." }
        end
        return shadowSearchCodes(payload)
    end

    return { success = false, error = "Unsupported action." }
end

lib.callback.register("midnight-redeem:createShadowChatSession", function(source)
    if not shadowIsEnabled() then
        return { success = false, error = "Shadow is disabled." }
    end
    if not AdminCanUse(source, "VIEW_DASHBOARD") then
        return { success = false, error = "You do not have permission to use Shadow." }
    end

    local identifier = shadowGetIdentifier(source)
    if not identifier then
        return { success = false, error = "Unable to identify user." }
    end

    local sessionId = shadowCreateSession(identifier, GetPlayerName(source) or "Unknown")
    if not sessionId then
        return { success = false, error = "Unable to create chat session." }
    end

    local welcome = getAIWelcomeMessage()
    shadowStoreMessage(sessionId, "assistant", welcome)
    return { success = true, sessionId = sessionId, welcome = welcome }
end)

lib.callback.register("midnight-redeem:shadowChatMessage", function(source, message, conversationHistory, sessionId, pendingAction, confirmPendingAction)
    if not shadowIsEnabled() then
        return { success = false, error = "Shadow is disabled." }
    end
    if not AdminCanUse(source, "VIEW_DASHBOARD") then
        return { success = false, error = "You do not have permission to use Shadow." }
    end
    if type(message) ~= "string" or message:gsub("%s+", "") == "" then
        return { success = false, error = "Message cannot be empty." }
    end

    if ContentFilter and ContentFilter.checkString then
        local blocked, badWords = ContentFilter.checkString(message)
        if blocked then
            ContentFilter.logFilteredAttempt(source, message, "Shadow message blocked")
            return { success = false, error = "Keep it clean and focused on redeem-code tasks." }
        end
    end

    local identifier = shadowGetIdentifier(source)
    if not identifier then
        return { success = false, error = "Unable to identify user." }
    end

    if not sessionId or sessionId == "" then
        sessionId = shadowCreateSession(identifier, GetPlayerName(source) or "Unknown")
    elseif not shadowVerifySessionOwnership(source, sessionId) then
        return { success = false, error = "Invalid session." }
    end

    local limitOk, limitError = shadowCheckRateLimit(identifier)
    if not limitOk then
        return { success = false, error = limitError }
    end

    if sessionId and sessionId ~= "" then
        shadowStoreMessage(sessionId, "user", message)
    end

    if confirmPendingAction and type(pendingAction) == "table" and pendingAction.action and pendingAction.payload then
        local action = pendingAction.action
        if action == "create" or action == "update" then
            shadowRecordRateLimit(identifier)
            local result = shadowRunExecuteAction(source, action, pendingAction.payload, sessionId)
            if type(result) == "table" then
                result.action = action
            end
            local displayMessage = result and result.message or result and result.error or "Action failed."
            return {
                success = true,
                message = displayMessage,
                actionProposal = nil,
                actionResult = result,
                sessionId = sessionId
            }
        end
    end

    local createProposal = shadowParseCreateFromMessage(message)
    if createProposal then
        local displayMessage = createProposal.summary
        shadowRecordRateLimit(identifier)
        if sessionId and sessionId ~= "" then
            shadowStoreMessage(sessionId, "assistant", displayMessage)
        end
        return {
            success = true,
            message = displayMessage,
            actionProposal = createProposal,
            sessionId = sessionId
        }
    end

    local localRead = shadowDetectLocalReadAction(message)
    if localRead then
        local payload = localRead.payload or {}
        if localRead.action == "search" then
            payload = shadowInferSearchFilter(payload, message)
        end
        local result = shadowExecuteActionInternal(source, localRead.action, payload)
        local displayMessage = result.success
            and result.message
            or (result.error or "Could not complete that request.")
        shadowRecordRateLimit(identifier)
        if sessionId and sessionId ~= "" then
            shadowStoreMessage(sessionId, "assistant", displayMessage)
        end
        return {
            success = true,
            message = displayMessage,
            actionProposal = nil,
            sessionId = sessionId
        }
    end

    local input = {
        { role = "system", content = shadowBuildSystemPrompt() }
    }

    local usedDbHistory = false
    if sessionId and sessionId ~= "" then
        local dbMessages = shadowLoadRecentMessages(sessionId, SHADOW_AI_CONTEXT_MESSAGES)
        for _, item in ipairs(dbMessages) do
            input[#input + 1] = {
                role = (item.role == "assistant") and "assistant" or "user",
                content = tostring(item.content)
            }
        end
        usedDbHistory = #dbMessages > 0
    elseif type(conversationHistory) == "table" and #conversationHistory > 0 then
        local start = math.max(1, #conversationHistory - SHADOW_AI_CONTEXT_MESSAGES + 1)
        for i = start, #conversationHistory do
            local item = conversationHistory[i]
            if type(item) == "table" and item.role and item.content then
                input[#input + 1] = {
                    role = (item.role == "assistant") and "assistant" or "user",
                    content = tostring(item.content)
                }
            end
        end
    end

    if not usedDbHistory then
        input[#input + 1] = { role = "user", content = message }
    end
    if shadowMessageLooksCreateIntent(message) or shadowDetectLocalReadAction(message) then
        input[#input + 1] = { role = "system", content = shadowBuildActionHint(message) }
    end

    local allowWebSearch = not shadowMessageLooksCodeRelated(message)
    local reply, err = shadowCallOpenAI(input, { allowWebSearch = allowWebSearch })
    if not reply then
        return { success = false, error = err or "Shadow could not respond." }
    end

    shadowRecordRateLimit(identifier)

    local actionProposal = shadowExtractAction(reply)
    local displayMessage = shadowStripActionJson(reply)
    local clientProposal = nil

    if actionProposal then
        local action = actionProposal.action
        local payload = actionProposal.payload or {}

        if action == "search" or action == "lookup" then
            if shadowMessageLooksCreateIntent(message) then
                actionProposal = nil
                clientProposal = nil
                if displayMessage == "" then
                    displayMessage = "I understood you want to create a code — let me draft that for you."
                end
            else
                if action == "search" then
                    payload = shadowInferSearchFilter(payload, actionProposal.summary)
                end
                local result = shadowExecuteActionInternal(source, action, payload)
                if result.success then
                    displayMessage = result.message
                else
                    displayMessage = result.error or "Could not complete that request."
                end
            end
        elseif action == "create" or action == "update" then
            clientProposal = actionProposal
            if displayMessage == "" then
                displayMessage = actionProposal.summary or ("Ready to " .. action .. " — please confirm below.")
            end
        else
            if displayMessage == "" then
                displayMessage = actionProposal.summary or reply
            end
        end
    elseif not shadowMessageLooksCreateIntent(message) and shadowDetectLocalReadAction(message) then
        local fallback = shadowDetectLocalReadAction(message)
        if fallback and (fallback.action == "search" or fallback.action == "lookup") then
            local payload = fallback.payload or {}
            if fallback.action == "search" then
                payload = shadowInferSearchFilter(payload, message)
            end
            local result = shadowExecuteActionInternal(source, fallback.action, payload)
            displayMessage = result.success
                and result.message
                or (result.error or "Could not complete that request.")
        end
    end

    if displayMessage == "" then
        displayMessage = reply
    end

    if sessionId and sessionId ~= "" then
        shadowStoreMessage(sessionId, "assistant", displayMessage)
    end

    return {
        success = true,
        message = displayMessage,
        actionProposal = clientProposal,
        sessionId = sessionId
    }
end)

lib.callback.register("midnight-redeem:shadowExecuteAction", function(source, action, payload, sessionId)
    if not shadowIsEnabled() then
        return { success = false, error = "Shadow is disabled." }
    end
    if not shadowVerifySessionOwnership(source, sessionId) then
        return { success = false, error = "Invalid session." }
    end
    local result = shadowRunExecuteAction(source, action, payload, sessionId)
    if type(result) == "table" then
        result.action = action
    end
    return result
end)

lib.callback.register("midnight-redeem:getAIChatSessions", function(source)
    if not shadowIsEnabled() then
        return { success = false, error = "Shadow is disabled.", sessions = {} }
    end
    local identifier = shadowGetIdentifier(source)
    if not identifier then
        return { success = false, sessions = {} }
    end

    local sessions = MySQL.query.await([[
        SELECT session_id, player_name, created_at, updated_at,
               (SELECT COUNT(*) FROM midnight_ai_chat_messages WHERE session_id = midnight_ai_chat_sessions.session_id) as message_count
        FROM midnight_ai_chat_sessions
        WHERE identifier = ?
        ORDER BY updated_at DESC
    ]], { identifier })

    return { success = true, sessions = sessions or {} }
end)

lib.callback.register("midnight-redeem:getAllAIChatSessions", function(source)
    if not shadowIsEnabled() then
        return { success = false, error = "Shadow is disabled.", sessions = {} }
    end
    if not AdminHasPermission(source, "VIEW_TRANSCRIPTS") then
        return { success = false, error = "Permission denied", sessions = {} }
    end

    local sessions = MySQL.query.await([[
        SELECT session_id, identifier, player_name, created_at, updated_at,
               (SELECT COUNT(*) FROM midnight_ai_chat_messages WHERE session_id = midnight_ai_chat_sessions.session_id) as message_count
        FROM midnight_ai_chat_sessions
        ORDER BY updated_at DESC
        LIMIT 1000
    ]])

    return { success = true, sessions = sessions or {} }
end)

lib.callback.register("midnight-redeem:getAIChatMessages", function(source, sessionId)
    if not shadowIsEnabled() then
        return { success = false, error = "Shadow is disabled.", messages = {} }
    end
    if not sessionId or sessionId == "" then
        return { success = false, error = "Invalid session ID", messages = {} }
    end

    local identifier = shadowGetIdentifier(source)
    if not identifier then
        return { success = false, error = "Unable to identify user", messages = {} }
    end

    local session = MySQL.query.await('SELECT identifier FROM midnight_ai_chat_sessions WHERE session_id = ? LIMIT 1', { sessionId })
    if not session or not session[1] then
        return { success = false, error = "Session not found", messages = {} }
    end

    local sessionOwner = session[1].identifier
    local hasAccess = (sessionOwner == identifier)

    if not hasAccess then
        hasAccess = AdminHasPermission(source, "VIEW_TRANSCRIPTS")
    end

    if not hasAccess then
        return { success = false, error = "Permission denied", messages = {} }
    end

    local messages = MySQL.query.await([[
        SELECT role, content, timestamp
        FROM midnight_ai_chat_messages
        WHERE session_id = ?
        ORDER BY timestamp ASC
    ]], { sessionId })

    return { success = true, messages = messages or {} }
end)

function CleanupOldTranscripts()
    local days = tonumber(Config.TranscriptRetentionDays) or 31
    if days <= 0 then return 0 end

    local cutoff = os.time() - (days * 24 * 60 * 60)

    local stats = MySQL.single.await([[
        SELECT
            (SELECT COUNT(*) FROM midnight_ai_chat_sessions WHERE updated_at < FROM_UNIXTIME(?)) AS session_count,
            (SELECT COUNT(*) FROM midnight_ai_chat_messages m
                INNER JOIN midnight_ai_chat_sessions s ON m.session_id = s.session_id
                WHERE s.updated_at < FROM_UNIXTIME(?)) AS message_count
    ]], { cutoff, cutoff })

    local sessionCount = stats and tonumber(stats.session_count) or 0
    if sessionCount <= 0 then
        return 0
    end

    local messageCount = stats and tonumber(stats.message_count) or 0

    MySQL.query.await([[
        DELETE m FROM midnight_ai_chat_messages m
        INNER JOIN midnight_ai_chat_sessions s ON m.session_id = s.session_id
        WHERE s.updated_at < FROM_UNIXTIME(?)
    ]], { cutoff })

    local deleted = MySQL.update.await([[
        DELETE FROM midnight_ai_chat_sessions WHERE updated_at < FROM_UNIXTIME(?)
    ]], { cutoff })

    deleted = deleted or sessionCount

    if SendToDiscord then
        local message = string.format(
            "**Sessions Deleted:** `%d`\n**Messages Deleted:** `%d`\n**Reason:** Auto-cleanup after %d days",
            deleted,
            messageCount,
            days
        )
        SendToDiscord("🗑️ Transcript Auto-Cleaned", message, 15158332)
    end

    if Config.Debug then
        print(("[midnight_redeem] Cleaned up %d transcript sessions older than %d days"):format(deleted, days))
    end

    return deleted
end
