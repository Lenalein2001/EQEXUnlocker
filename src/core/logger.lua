local Logger = {
    sessionPath = 'logs/session.log',
    badItemsPath = 'logs/bad-items.log'
}

local function stamp()
    return os.date('%Y-%m-%d %H:%M:%S')
end

local function emit(level, message)
    local line = '[' .. stamp() .. '] [' .. tostring(level) .. '] ' .. tostring(message)
    print('[SafeUnlocker] ' .. line)
    Files.appendLine(Logger.sessionPath, line)
end

function Logger.init(config)
    if config and config.paths then
        Logger.sessionPath = config.paths.sessionLog or Logger.sessionPath
        Logger.badItemsPath = config.paths.badItemsLog or Logger.badItemsPath
    end

    -- CET's Lua sandbox does not provide os.mkdir / lfs, so we try lfs if available.
    local ok = pcall(function()
        local lfs = require('lfs')
        local dir = Logger.sessionPath:match('^(.+)[/\\][^/\\]+$')
        if dir then lfs.mkdir(dir) end
    end)

    Files.writeAll(Logger.sessionPath, '')
    Files.appendLine(Logger.badItemsPath, '--- session ' .. stamp() .. ' ---')
    emit('INFO', 'logger initialized')
end

function Logger.info(message)
    emit('INFO', message)
end

function Logger.warn(message)
    emit('WARN', message)
end

function Logger.error(message)
    emit('ERROR', message)
end

function Logger.badItem(phase, itemId, itemName, reason)
    local line = table.concat({
        '[' .. stamp() .. ']',
        tostring(phase or 'unknown'),
        tostring(itemId or 'unknown-id'),
        tostring(itemName or 'unknown-name'),
        tostring(reason or 'unknown-reason')
    }, ' | ')

    Files.appendLine(Logger.badItemsPath, line)
    emit('WARN', 'bad item recorded for ' .. tostring(itemId or 'unknown-id'))
end

return Logger
