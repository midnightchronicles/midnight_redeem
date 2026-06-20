local RES = GetCurrentResourceName()

local messageQueue = {}
local messageTimer = nil
local BATCH_DELAY = 16
local MAX_BATCH_SIZE = 10

local performanceCounters = {
    messagesSent = 0,
    messagesBatched = 0
}

local function flushMessageQueue()
    if #messageQueue == 0 then return end

    local batchSize = math.min(#messageQueue, MAX_BATCH_SIZE)
    local batch = {}

    for i = 1, batchSize do
        table.insert(batch, table.remove(messageQueue, 1))
    end

    if #batch > 0 then
        SendNUIMessage({
            action = 'batch',
            messages = batch,
            timestamp = GetGameTimer()
        })
        performanceCounters.messagesBatched = performanceCounters.messagesBatched + #batch
    end

    if #messageQueue > 0 then
        messageTimer = SetTimeout(BATCH_DELAY, flushMessageQueue)
    else
        messageTimer = nil
    end
end

local function queueMessage(message)
    table.insert(messageQueue, message)
    performanceCounters.messagesSent = performanceCounters.messagesSent + 1

    if not messageTimer then
        messageTimer = SetTimeout(BATCH_DELAY, flushMessageQueue)
    end
end

AddEventHandler("onClientResourceStop", function(res)
    if res ~= RES then return end
    pcall(function()
        exports[RES]:closeUI()
    end)
end)

RegisterCommand("mrcloseui", function()
    pcall(function()
        exports[RES]:closeUI()
    end)
end, false)

RegisterCommand("mrfixfocus", function()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end, false)

RegisterCommand("mrperf", function()
    print(string.format('[%s] Performance Stats:', RES))
    print(string.format('  Messages Sent: %d', performanceCounters.messagesSent))
    print(string.format('  Messages Batched: %d', performanceCounters.messagesBatched))
    print(string.format('  Batched Ratio: %.2f%%',
        (performanceCounters.messagesBatched / math.max(performanceCounters.messagesSent, 1)) * 100))
end, false)

exports('getPerformanceCounters', function() return performanceCounters end)

RegisterNetEvent("midnight-redeem:sendDashboardData", function(data)
    queueMessage({ action = "dashboardData", data = data })
end)

RegisterNetEvent("midnight-redeem:sendCodesData", function(data)
    queueMessage({ action = "codesData", data = data })
end)

RegisterNetEvent("midnight-redeem:sendAllCodesData", function(data)
    queueMessage({ action = "allCodesData", data = data })
end)

RegisterNetEvent("midnight-redeem:sendWeeklyStats", function(data)
    queueMessage({ action = "weeklyStats", data = data })
end)

RegisterNetEvent("midnight-redeem:sendDailyStats", function(data)
    queueMessage({ action = "dailyStats", data = data })
end)

RegisterNetEvent("midnight-redeem:sendRewardsStats", function(data)
    queueMessage({ action = "rewardsStats", data = data })
end)
