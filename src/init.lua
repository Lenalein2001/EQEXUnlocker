local modSettingsReady = false
local MOD_SETTINGS_RETRY_SECONDS = 3.0
local modSettingsTimer = MOD_SETTINGS_RETRY_SECONDS
local overlayOpen = false
local pendingAutoScan = false
local pendingImportResume = false
local inGameCached = false
local sessionReady = false
local lastDrawClock = 0
local drawFpsSmoothed = 0
local DRAW_FPS_SMOOTHING = 0.20

local function isMenuActive()
    local ok, result = pcall(function()
        local defs = Game.GetAllBlackboardDefs()
        if not defs then
            return false
        end

        local blackboardSystem = Game.GetBlackboardSystem()
        if not blackboardSystem then
            return false
        end

        local uiBoard = blackboardSystem:Get(defs.UI_System)
        if uiBoard and uiBoard:GetBool(defs.UI_System.IsInMenu) and not overlayOpen then
            return true
        end
        if uiBoard and uiBoard:GetBool(defs.UI_System.IsLoading) then
            return true
        end

        local photoBoard = blackboardSystem:Get(defs.PhotoMode)
        if photoBoard and photoBoard:GetBool(defs.PhotoMode.IsActive) then
            return true
        end

        return false
    end)

    if ok then
        return result == true
    end

    return false
end

local function isGameplayReadyNow()
    local player = Game.GetPlayer()
    if not player or not player:IsAttached() then
        return false
    end
    if GetSingleton('inkMenuScenario'):GetSystemRequestsHandler():IsPreGame() then
        return false
    end
    if isMenuActive() then
        return false
    end

    return true
end

local function isInGame()
    local ok, result = pcall(function()
        local gameplayReady = isGameplayReadyNow()
        if not gameplayReady then
            return false
        end

        -- When CET reloads mods mid-session, observer-based OnInitialize may not fire again.
        -- Recover readiness from the current live game state so actions still work.
        if not sessionReady then
            sessionReady = true
            if Logger and Logger.info then
                Logger.info('Recovered session readiness from live gameplay state')
            end
        end
        
        return true
    end)
    return ok and result == true
end

SafeUnlocker = SafeUnlocker or {}
SafeUnlocker.name = 'EQEX Unlocker'
SafeUnlocker.version = '0.2.2'
SafeUnlocker.config = Config.load()
SafeUnlocker.state = State.new()
SafeUnlocker.ts = nil
SafeUnlocker.player = nil
SafeUnlocker.wardrobeSystem = nil
SafeUnlocker.outfitSystem = nil
SafeUnlocker.equipData = nil
SafeUnlocker.blacklist = Config.loadBlacklist(SafeUnlocker.config)
SafeUnlocker.forceScanAll = false
SafeUnlocker.forceAutoImport = false
SafeUnlocker.renderFps = 0

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

local function canRunGameplayAction(actionName)
    if isInGame() then
        return true
    end

    Logger.warn(tostring(actionName or 'Action') .. ' requested outside gameplay; load into a save first')
    return false
end

function SafeUnlocker.startScan()
    if not SafeUnlocker.config.enabled then
        return
    end
    if not canRunGameplayAction('Scan') then
        return
    end
    SafeUnlocker.forceScanAll = false
    SafeUnlocker.forceAutoImport = false
    resolveSystems(SafeUnlocker)
    Scanner.begin(SafeUnlocker)
end

function SafeUnlocker.forceRescanAll()
    if not SafeUnlocker.config.enabled then
        return
    end
    if not canRunGameplayAction('Full re-add scan') then
        return
    end

    Importer.stop(SafeUnlocker)
    Scanner.stop(SafeUnlocker)
    SafeUnlocker.forceScanAll = true
    SafeUnlocker.forceAutoImport = true
    Logger.info('Starting full re-add scan; already unlocked/imported items will be queued again')
    resolveSystems(SafeUnlocker)
    Scanner.begin(SafeUnlocker)
end

function SafeUnlocker.startImport()
    if not SafeUnlocker.config.enabled then
        return
    end
    if not canRunGameplayAction('Import') then
        return
    end
    resolveSystems(SafeUnlocker)
    Importer.begin(SafeUnlocker)
end

function SafeUnlocker.pauseImport()
    Importer.pause(SafeUnlocker)
end

function SafeUnlocker.resumeImport()
    if not canRunGameplayAction('Resume import') then
        return
    end
    resolveSystems(SafeUnlocker)
    Importer.resume(SafeUnlocker)
end

function SafeUnlocker.resetSession()
    Importer.stop(SafeUnlocker)
    Scanner.stop(SafeUnlocker)
    SafeUnlocker.forceScanAll = false
    SafeUnlocker.forceAutoImport = false
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

        pcall(function()
            Observe('QuestTrackerGameController', 'OnInitialize', function()
                if not sessionReady then
                    sessionReady = true
                    Logger.info('Game session controller initialized')
                end
            end)

            Observe('QuestTrackerGameController', 'OnUninitialize', function()
                sessionReady = false
                Logger.info('Game session controller uninitialized')
            end)
        end)

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
    sessionReady = false
    lastDrawClock = 0
    drawFpsSmoothed = 0
    SafeUnlocker.forceScanAll = false
    SafeUnlocker.forceAutoImport = false
    SafeUnlocker.renderFps = 0
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

    if not modSettingsReady then
        modSettingsTimer = modSettingsTimer - (deltaTime or 0)
        if modSettingsTimer <= 0 then
            local initialized = ModSettings.initialize(SafeUnlocker)
            if initialized then
                modSettingsReady = true
            else
                modSettingsTimer = MOD_SETTINGS_RETRY_SECONDS
            end
        end
    end

    if not SafeUnlocker.config.enabled or not inGameCached then
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
        SafeUnlocker.forceScanAll = false
        Logger.info('Player loaded, starting deferred auto-scan')
        resolveSystems(SafeUnlocker)
        Scanner.begin(SafeUnlocker)
    end

    Scanner.tick(SafeUnlocker, deltaTime or 0)
    Importer.tick(SafeUnlocker, deltaTime or 0)

    if SafeUnlocker.state.readyToImport and (SafeUnlocker.config.autoImport or SafeUnlocker.forceAutoImport) then
        SafeUnlocker.forceAutoImport = false
        SafeUnlocker.state.readyToImport = false
        SafeUnlocker.startImport()
    end
end)

registerForEvent('onDraw', function()
    local now = os.clock()
    if lastDrawClock > 0 then
        local dt = now - lastDrawClock
        if dt > 0 then
            local fps = 1 / dt
            if drawFpsSmoothed <= 0 then
                drawFpsSmoothed = fps
            else
                drawFpsSmoothed = (drawFpsSmoothed * (1 - DRAW_FPS_SMOOTHING)) + (fps * DRAW_FPS_SMOOTHING)
            end
            SafeUnlocker.renderFps = drawFpsSmoothed
        end
    end
    lastDrawClock = now

    -- HUD shows during gameplay regardless of overlay
    if SafeUnlocker.config.enabled and inGameCached then
        UI.drawHUD(SafeUnlocker)
    end
    -- Panel shows whenever CET overlay is open
    if overlayOpen and SafeUnlocker.config.showWindow then
        UI.draw(SafeUnlocker)
    end
end)

return SafeUnlocker
