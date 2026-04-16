local modSettingsReady = false
local modSettingsTimer = 3.0
local overlayOpen = false
local pendingAutoScan = false
local pendingImportResume = false
local inGameCached = false

local function isInGame()
    local ok, result = pcall(function()
        local player = Game.GetPlayer()
        if not player or not player:IsAttached() then
            return false
        end
        if GetSingleton('inkMenuScenario'):GetSystemRequestsHandler():IsPreGame() then
            return false
        end
        return true
    end)
    return ok and result == true
end

SafeUnlocker = SafeUnlocker or {}
SafeUnlocker.name = 'Robust Equipment-EX Unlocker'
SafeUnlocker.version = '0.2.0'
SafeUnlocker.config = Config.load()
SafeUnlocker.state = State.new()
SafeUnlocker.ts = nil
SafeUnlocker.player = nil
SafeUnlocker.wardrobeSystem = nil
SafeUnlocker.outfitSystem = nil
SafeUnlocker.equipData = nil
SafeUnlocker.blacklist = Config.loadBlacklist(SafeUnlocker.config)

local function safeCall(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then
        return result
    end
    return nil
end

local function resolveSystems(ctx)
    ctx.player = safeCall(Game.GetPlayer)
    ctx.ts = safeCall(Game.GetTransactionSystem)
    ctx.wardrobeSystem = safeCall(Game.GetWardrobeSystem)

    local container = safeCall(Game.GetScriptableSystemsContainer)
    if container then
        ctx.outfitSystem = safeCall(function()
            return container:Get('EquipmentEx.OutfitSystem')
        end)

        ctx.equipData = safeCall(function()
            local equipmentSystem = container:Get('EquipmentSystem')
            if equipmentSystem and ctx.player then
                return equipmentSystem:GetPlayerData(ctx.player)
            end
            return nil
        end)
    end
end

local function restoreSavedProgress(ctx)
    State.restore(ctx.state, Config.loadState(ctx.config))
    local savedQueue = Config.loadQueue(ctx.config)
    if #savedQueue > 0 then
        ctx.state.candidates = savedQueue
        ctx.state.queued = #savedQueue
    end
end

function SafeUnlocker.startScan()
    if not SafeUnlocker.config.enabled then
        return
    end
    resolveSystems(SafeUnlocker)
    Scanner.begin(SafeUnlocker)
end

function SafeUnlocker.startImport()
    if not SafeUnlocker.config.enabled then
        return
    end
    resolveSystems(SafeUnlocker)
    Importer.begin(SafeUnlocker)
end

function SafeUnlocker.pauseImport()
    Importer.pause(SafeUnlocker)
end

function SafeUnlocker.resumeImport()
    resolveSystems(SafeUnlocker)
    Importer.resume(SafeUnlocker)
end

function SafeUnlocker.resetSession()
    Importer.stop(SafeUnlocker)
    Scanner.stop(SafeUnlocker)
    SafeUnlocker.state = State.new()
    Config.saveState(SafeUnlocker.config, State.snapshot(SafeUnlocker.state, 1))
    Config.saveQueue(SafeUnlocker.config, {})
    Logger.info('Session state reset')
end

function SafeUnlocker.blacklistFailures()
    local added = Config.addFailureIdsToBlacklist(
        SafeUnlocker.config,
        SafeUnlocker.blacklist,
        SafeUnlocker.state.badItems,
        SafeUnlocker.state.currentItemId
    )
    Logger.info('Added ' .. tostring(added) .. ' failed item ids to blacklist')
end

registerForEvent('onInit', function()
    print('[SafeUnlocker] onInit starting — ' .. SafeUnlocker.name .. ' v' .. SafeUnlocker.version)

    local ok, err = pcall(function()
        Logger.init(SafeUnlocker.config)

        -- Start with a clean state every session; persisted state is only used
        -- for the previous record-count so we can detect new mods.
        local savedState = Config.loadState(SafeUnlocker.config)
        local previousRecordCount = (type(savedState) == 'table' and savedState.totalRecords) or 0
        SafeUnlocker.state = State.new()

        Logger.info('Initialized ' .. SafeUnlocker.name .. ' v' .. SafeUnlocker.version)

        pcall(function()
            registerHotkey('safeunlocker_scan', 'SafeUnlocker Start Scan', function()
                SafeUnlocker.startScan()
            end)

            registerHotkey('safeunlocker_import', 'SafeUnlocker Start Import', function()
                SafeUnlocker.startImport()
            end)

            registerHotkey('safeunlocker_toggle_window', 'SafeUnlocker Toggle Window', function()
                SafeUnlocker.config.showWindow = not SafeUnlocker.config.showWindow
                Config.save(SafeUnlocker.config)
                Logger.info('Overlay window toggled to ' .. tostring(SafeUnlocker.config.showWindow))
            end)
        end)

        -- Check if clothing record count changed (new mods added/removed)
        -- or if the previous session didn't finish (phase wasn't 'done')
        local currentCount = 0
        pcall(function()
            local records = TweakDB:GetRecords('gamedataClothing_Record')
            if records then currentCount = #records end
        end)

        local previousPhase = (type(savedState) == 'table' and savedState.phase) or 'idle'
        local previousImported = (type(savedState) == 'table' and savedState.imported) or 0
        local previousQueued = (type(savedState) == 'table' and savedState.queued) or 0
        local wasImporting = (previousPhase == 'import') and (previousQueued > 0) and (previousImported < previousQueued)
        local wasIncomplete = (previousPhase ~= 'idle' and previousPhase ~= 'done')
            or (previousQueued > 0 and previousImported < previousQueued)

        if currentCount > 0 and currentCount ~= previousRecordCount then
            Logger.info('Record count changed: ' .. tostring(previousRecordCount) .. ' -> ' .. tostring(currentCount) .. ', auto-scan pending until in-game')
            pendingAutoScan = true
        elseif currentCount > 0 and wasImporting then
            Logger.info('Previous import interrupted (imported=' .. tostring(previousImported) .. '/' .. tostring(previousQueued) .. '), import resume pending until in-game')
            pendingImportResume = true
        elseif currentCount > 0 and wasIncomplete then
            Logger.info('Previous session incomplete (phase=' .. tostring(previousPhase) .. ', imported=' .. tostring(previousImported) .. '/' .. tostring(previousQueued) .. '), auto-scan pending until in-game')
            pendingAutoScan = true
        elseif currentCount > 0 then
            Logger.info('Record count unchanged (' .. tostring(currentCount) .. ') and wardrobe complete, skipping auto-scan')
        end
    end)

    if not ok then
        print('[SafeUnlocker] ERROR in onInit: ' .. tostring(err))
    else
        print('[SafeUnlocker] onInit OK')
    end
end)

registerForEvent('onShutdown', function()
    overlayOpen = false
    pendingAutoScan = false
    pendingImportResume = false
    -- Stop any running operations and reset transient state so
    -- stale results don't show in the main menu HUD
    Scanner.stop(SafeUnlocker)
    Importer.stop(SafeUnlocker)
    SafeUnlocker.state.phase = 'idle'
end)

registerForEvent('onOverlayOpen', function()
    overlayOpen = true
end)

registerForEvent('onOverlayClose', function()
    overlayOpen = false
end)

registerForEvent('onUpdate', function(deltaTime)
    inGameCached = isInGame()
    if not inGameCached or not SafeUnlocker.config.enabled then
        return
    end

    -- Deferred resume: interrupted import takes priority over re-scan
    if pendingImportResume then
        pendingImportResume = false
        Logger.info('Player loaded, resuming interrupted import')
        restoreSavedProgress(SafeUnlocker)
        resolveSystems(SafeUnlocker)
        Importer.begin(SafeUnlocker)
    elseif pendingAutoScan then
        pendingAutoScan = false
        Logger.info('Player loaded, starting deferred auto-scan')
        resolveSystems(SafeUnlocker)
        Scanner.begin(SafeUnlocker)
    end

    if not modSettingsReady then
        modSettingsTimer = modSettingsTimer - (deltaTime or 0)
        if modSettingsTimer <= 0 then
            modSettingsReady = true
            ModSettings.initialize(SafeUnlocker)
        end
    end

    Scanner.tick(SafeUnlocker, deltaTime or 0)
    Importer.tick(SafeUnlocker, deltaTime or 0)

    if SafeUnlocker.state.readyToImport and SafeUnlocker.config.autoImport then
        SafeUnlocker.state.readyToImport = false
        SafeUnlocker.startImport()
    end
end)

registerForEvent('onDraw', function()
    if not SafeUnlocker.config.enabled then
        return
    end
    -- HUD shows during gameplay regardless of overlay
    if inGameCached then
        UI.drawHUD(SafeUnlocker)
    end
    -- Panel only shows when CET overlay is open AND in game
    if overlayOpen and inGameCached then
        UI.draw(SafeUnlocker)
    end
end)

return SafeUnlocker
