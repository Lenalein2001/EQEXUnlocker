local ModSettings = {}
local missingDependencyWarned = false

local function saveAndLog(ctx, label, value)
    Config.save(ctx.config)
    Logger.info(label .. ': ' .. tostring(value))
end

function ModSettings.initialize(ctx)
    local nativeSettings = nil

    local ok = pcall(function()
        nativeSettings = GetMod('nativeSettings')
    end)

    if not ok or not nativeSettings then
        if not missingDependencyWarned then
            missingDependencyWarned = true
            print('[SafeUnlocker] nativeSettings mod NOT found.')
            print('[SafeUnlocker] To get an in-game settings menu, install the Native Settings UI mod:')
            print('[SafeUnlocker] https://www.nexusmods.com/cyberpunk2077/mods/3518')
            Logger.warn('nativeSettings not found; install https://www.nexusmods.com/cyberpunk2077/mods/3518 for in-game settings')
        end
        return false
    end

    missingDependencyWarned = false

    local registered, registerError = pcall(function()
        nativeSettings.addTab('/EQEXUnlocker', 'EQEX Unlocker')
        nativeSettings.addSubcategory('/EQEXUnlocker/Main', 'General')

        nativeSettings.addSwitch('/EQEXUnlocker/Main', 'Enabled', 'Enable or disable the mod', ctx.config.enabled, true, function(state)
            ctx.config.enabled = state
            saveAndLog(ctx, 'Enabled', state)
        end)

        nativeSettings.addSwitch('/EQEXUnlocker/Main', 'Auto import', 'Automatically start importing after scan', ctx.config.autoImport, true, function(state)
            ctx.config.autoImport = state
            saveAndLog(ctx, 'Auto import', state)
        end)

        nativeSettings.addSwitch('/EQEXUnlocker/Main', 'Include vanilla items', 'Include base game clothing records in the queue', ctx.config.includeVanilla, true, function(state)
            ctx.config.includeVanilla = state
            saveAndLog(ctx, 'Include vanilla items', state)
        end)

        nativeSettings.addSwitch('/EQEXUnlocker/Main', 'Keep items in inventory', 'Keep the temporary item instead of removing it after wardrobe unlock', ctx.config.keepInInventory, true, function(state)
            ctx.config.keepInInventory = state
            saveAndLog(ctx, 'Keep items in inventory', state)
        end)

        nativeSettings.addSwitch('/EQEXUnlocker/Main', 'Show CET window', 'Show the built-in CET overlay window for this mod', ctx.config.showWindow, true, function(state)
            ctx.config.showWindow = state
            saveAndLog(ctx, 'Show CET window', state)
        end)

        nativeSettings.addSwitch('/EQEXUnlocker/Main', 'Stop on error', 'Pause immediately after the first import error', ctx.config.stopOnError, true, function(state)
            ctx.config.stopOnError = state
            saveAndLog(ctx, 'Stop on error', state)
        end)

        nativeSettings.addSwitch('/EQEXUnlocker/Main', 'Smart import', 'Automatically throttle import speed to stay above a target FPS', ctx.config.smartImport, true, function(state)
            ctx.config.smartImport = state
            saveAndLog(ctx, 'Smart import', state)
        end)

        nativeSettings.addRangeFloat('/EQEXUnlocker/Main', 'Scan delay', 'Delay between clothing scan batches (seconds)', 0.00, 1.00, 0.01, '%.2f', ctx.config.scanDelay, 0.02, function(value)
            ctx.config.scanDelay = value
            saveAndLog(ctx, 'Scan delay', value)
        end)

        nativeSettings.addRangeFloat('/EQEXUnlocker/Main', 'Import delay', 'Delay between import batches (seconds)', 0.05, 3.00, 0.05, '%.2f', ctx.config.importDelay, 0.35, function(value)
            ctx.config.importDelay = value
            saveAndLog(ctx, 'Import delay', value)
        end)

        nativeSettings.addRangeFloat('/EQEXUnlocker/Main', 'Smart import min FPS', 'Importer slows down when FPS falls below this threshold', 20, 240, 1, '%.0f', ctx.config.smartImportMinFps, 55, function(value)
            ctx.config.smartImportMinFps = math.floor(value)
            saveAndLog(ctx, 'Smart import min FPS', ctx.config.smartImportMinFps)
        end)

        nativeSettings.addRangeFloat('/EQEXUnlocker/Main', 'Scan batch size', 'Records validated per scan tick (higher = faster but more risky)', 1, 1000, 1, '%.0f', ctx.config.scanBatchSize, 25, function(value)
            ctx.config.scanBatchSize = math.floor(value)
            saveAndLog(ctx, 'Scan batch size', ctx.config.scanBatchSize)
        end)

        nativeSettings.addRangeFloat('/EQEXUnlocker/Main', 'Import batch size', 'Items imported per batch (lower = safer)', 1, 50, 1, '%.0f', ctx.config.batchSize, 5, function(value)
            ctx.config.batchSize = math.floor(value)
            saveAndLog(ctx, 'Import batch size', ctx.config.batchSize)
        end)

        nativeSettings.addRangeFloat('/EQEXUnlocker/Main', 'Max failures before pause', 'Auto-pause after this many failed imports', 1, 500, 1, '%.0f', ctx.config.maxFailuresBeforePause, 10, function(value)
            ctx.config.maxFailuresBeforePause = math.floor(value)
            saveAndLog(ctx, 'Max failures before pause', ctx.config.maxFailuresBeforePause)
        end)

        nativeSettings.addButton('/EQEXUnlocker/Main', 'Start scan', 'Begin the clothing scan', 'Scan', 50, function()
            ctx.startScan()
        end)

        nativeSettings.addButton('/EQEXUnlocker/Main', 'Start import', 'Begin importing queued clothing', 'Import', 50, function()
            ctx.startImport()
        end)

        nativeSettings.addButton('/EQEXUnlocker/Main', 'Re-scan and re-add all', 'Queue all eligible clothing again, including already unlocked/imported items', 'Re-add All', 50, function()
            ctx.forceRescanAll()
        end)

        nativeSettings.addButton('/EQEXUnlocker/Main', 'Pause import', 'Pause the running import', 'Pause', 50, function()
            ctx.pauseImport()
        end)

        nativeSettings.addButton('/EQEXUnlocker/Main', 'Resume import', 'Resume the import from the last saved index', 'Resume', 50, function()
            ctx.resumeImport()
        end)

        nativeSettings.addButton('/EQEXUnlocker/Main', 'Blacklist failed ids', 'Add the current suspect and logged failures to the blacklist', 'Blacklist', 50, function()
            ctx.blacklistFailures()
        end)

        nativeSettings.addButton('/EQEXUnlocker/Main', 'Reset session', 'Clear the current queue and reset progress state', 'Reset', 50, function()
            ctx.resetSession()
        end)
    end)

    if not registered then
        Logger.error('nativeSettings registration failed: ' .. tostring(registerError))
        return false
    end

    Logger.info('nativeSettings integration initialized')
    return true
end

return ModSettings