local State = {}

local function defaults()
    return {
        phase = 'idle',
        scanned = 0,
        totalRecords = 0,
        queued = 0,
        imported = 0,
        skipped = 0,
        failed = 0,
        lastIndex = 1,
        currentItemId = '',
        currentItemName = '',
        lastReason = '',
        candidates = {},
        badItems = {},
        paused = false,
        readyToImport = false,
        scanElapsed = 0,
        importElapsed = 0,
        skipReasons = {}
    }
end

function State.new()
    return defaults()
end

function State.reset(state)
    local clean = defaults()
    for key, value in pairs(clean) do
        state[key] = value
    end
    return state
end

function State.snapshot(state, nextIndex)
    return {
        phase = state.phase,
        scanned = state.scanned,
        totalRecords = state.totalRecords,
        queued = state.queued,
        imported = state.imported,
        skipped = state.skipped,
        failed = state.failed,
        paused = state.paused,
        lastIndex = nextIndex or state.lastIndex or 1,
        currentItemId = state.currentItemId or '',
        currentItemName = state.currentItemName or '',
        lastReason = state.lastReason or '',
        scanElapsed = state.scanElapsed or 0,
        importElapsed = state.importElapsed or 0
    }
end

function State.restore(state, saved)
    if type(saved) ~= 'table' then
        return state
    end

    for key, value in pairs(saved) do
        if state[key] ~= nil and type(value) ~= 'table' then
            state[key] = value
        end
    end

    return state
end

return State
