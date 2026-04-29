local Config = {}

local defaults = {
    enabled = true,
    autoScan = false,
    autoImport = false,
    scanDelay = 0.02,
    importDelay = 0.35,
    scanBatchSize = 25,
    batchSize = 5,
    smartImport = false,
    smartImportMinFps = 55,
    includeVanilla = false,
    keepInInventory = false,
    showProgress = true,
    showWindow = true,
    stopOnError = false,
    logBadItems = true,
    maxFailuresBeforePause = 10,
    paths = {
        config = 'config/config.json',
        blacklist = 'config/blacklist.json',
        basegame = 'config/basegame.json',
        state = 'config/state.json',
        queue = 'config/queue.txt',
        imported = 'config/imported.json',
        sessionLog = 'logs/session.log',
        badItemsLog = 'logs/bad-items.log'
    }
}

local function copyTable(source)
    local result = {}
    for key, value in pairs(source or {}) do
        if type(value) == 'table' then
            result[key] = copyTable(value)
        else
            result[key] = value
        end
    end
    return result
end

local function mergeTable(base, override)
    local result = copyTable(base)
    for key, value in pairs(override or {}) do
        if type(value) == 'table' and type(result[key]) == 'table' then
            result[key] = mergeTable(result[key], value)
        else
            result[key] = value
        end
    end
    return result
end

local function clampNumber(value, minValue, maxValue, fallback)
    local numberValue = tonumber(value)
    if numberValue == nil then
        numberValue = tonumber(fallback) or 0
    end
    if numberValue < minValue then
        return minValue
    end
    if numberValue > maxValue then
        return maxValue
    end
    return numberValue
end

local function toBoolean(value, fallback)
    if type(value) == 'boolean' then
        return value
    end
    if type(fallback) == 'boolean' then
        return fallback
    end
    return false
end

local function normalizeConfig(config)
    config.enabled = toBoolean(config.enabled, defaults.enabled)
    config.autoScan = toBoolean(config.autoScan, defaults.autoScan)
    config.autoImport = toBoolean(config.autoImport, defaults.autoImport)
    config.includeVanilla = toBoolean(config.includeVanilla, defaults.includeVanilla)
    config.keepInInventory = toBoolean(config.keepInInventory, defaults.keepInInventory)
    config.showProgress = toBoolean(config.showProgress, defaults.showProgress)
    config.showWindow = toBoolean(config.showWindow, defaults.showWindow)
    config.stopOnError = toBoolean(config.stopOnError, defaults.stopOnError)
    config.logBadItems = toBoolean(config.logBadItems, defaults.logBadItems)
    config.smartImport = toBoolean(config.smartImport, defaults.smartImport)

    config.scanDelay = clampNumber(config.scanDelay, 0, 1, defaults.scanDelay)
    config.importDelay = clampNumber(config.importDelay, 0, 5, defaults.importDelay)
    config.scanBatchSize = math.floor(clampNumber(config.scanBatchSize, 1, 1000, defaults.scanBatchSize))
    config.batchSize = math.floor(clampNumber(config.batchSize, 1, 100, defaults.batchSize))
    config.smartImportMinFps = math.floor(clampNumber(config.smartImportMinFps, 20, 240, defaults.smartImportMinFps))
    config.maxFailuresBeforePause = math.floor(clampNumber(config.maxFailuresBeforePause, 1, 1000, defaults.maxFailuresBeforePause))
end

function Config.load()
    local loaded = Files.loadJson(defaults.paths.config, {})
    local config = mergeTable(defaults, loaded)
    normalizeConfig(config)
    config.paths = copyTable(defaults.paths)
    return config
end

function Config.save(config)
    local toSave = copyTable(config)
    toSave.paths = nil
    return Files.saveJson(config.paths.config, toSave)
end

function Config.loadBlacklist(config)
    local list = Files.loadJson(config.paths.blacklist, {})
    local set = {}

    if type(list) == 'table' then
        for _, value in pairs(list) do
            if type(value) == 'string' and value ~= '' then
                set[value] = true
            end
        end
    end

    return set
end

function Config.saveBlacklist(config, set)
    local list = {}
    for id, isEnabled in pairs(set or {}) do
        if isEnabled then
            table.insert(list, id)
        end
    end
    table.sort(list)
    return Files.saveJson(config.paths.blacklist, list)
end

function Config.addFailureIdsToBlacklist(config, blacklistSet, badItems, suspectId)
    local added = 0

    if suspectId and suspectId ~= '' and not blacklistSet[suspectId] then
        blacklistSet[suspectId] = true
        added = added + 1
    end

    for _, item in ipairs(badItems or {}) do
        if item.id and item.id ~= '' and not blacklistSet[item.id] then
            blacklistSet[item.id] = true
            added = added + 1
        end
    end

    Config.saveBlacklist(config, blacklistSet)
    return added
end

function Config.loadBasegameSet(config)
    local set = {}
    local text = Files.readAll(config.paths.basegame)

    if not text or text == '' then
        return set
    end

    for id in text:gmatch('"id"%s*:%s*"([^"]+)"') do
        set[id] = true
    end

    return set
end

function Config.loadState(config)
    return Files.loadJson(config.paths.state, {})
end

function Config.saveState(config, snapshot)
    return Files.saveJson(config.paths.state, snapshot or {})
end

function Config.loadQueue(config)
    return Files.loadQueue(config.paths.queue)
end

function Config.saveQueue(config, candidates)
    return Files.saveQueue(config.paths.queue, candidates or {})
end

function Config.loadImported(config)
    local list = Files.loadJson(config.paths.imported, {})
    local set = {}
    if type(list) == 'table' then
        for _, id in ipairs(list) do
            if type(id) == 'string' and id ~= '' then
                set[id] = true
            end
        end
    end
    return set
end

function Config.saveImported(config, set)
    local list = {}
    for id, _ in pairs(set or {}) do
        table.insert(list, id)
    end
    table.sort(list)
    return Files.saveJson(config.paths.imported, list)
end

return Config
