
local Importer = {
    running = false,
    index = 1,
    accumulator = 0,
    smoothedFps = 0,
    smartScale = 1.0,
    batchCarry = 0
}

local FPS_SMOOTHING = 0.20
local SMART_DEADBAND_FPS = 1.0
local SMART_RAMP_UP_PER_SEC = 0.55
local SMART_RAMP_DOWN_PER_SEC = 3.20
local SMART_MIN_SCALE = 0.05

local function normalizeDeltaSeconds(deltaTime)
    local dt = tonumber(deltaTime or 0) or 0
    if dt <= 0 then
        return nil
    end

    -- Some CET setups report seconds, some report milliseconds.
    if dt > 1 then
        dt = dt / 1000
    end

    if dt <= 0 then
        return nil
    end

    return dt
end

local function updateFpsEstimate(ctx, deltaTime)
    local renderFps = tonumber((ctx and ctx.renderFps) or 0) or 0
    if renderFps > 0 then
        if Importer.smoothedFps <= 0 then
            Importer.smoothedFps = renderFps
        else
            Importer.smoothedFps = (Importer.smoothedFps * (1 - FPS_SMOOTHING)) + (renderFps * FPS_SMOOTHING)
        end
        return
    end

    local dt = normalizeDeltaSeconds(deltaTime)
    if not dt then
        return
    end

    local instantFps = 1 / dt
    if instantFps <= 0 then
        return
    end

    if Importer.smoothedFps <= 0 then
        Importer.smoothedFps = instantFps
    else
        Importer.smoothedFps = (Importer.smoothedFps * (1 - FPS_SMOOTHING)) + (instantFps * FPS_SMOOTHING)
    end
end

local function updateSmartScale(ctx, deltaTime)
    if not ctx.config.smartImport then
        Importer.smartScale = 1.0
        return
    end

    local dt = normalizeDeltaSeconds(deltaTime)
    if not dt or dt <= 0 then
        return
    end

    local fps = tonumber(Importer.smoothedFps or 0) or 0
    local minFps = math.max(10, tonumber(ctx.config.smartImportMinFps or 55) or 55)

    if fps <= 0 then
        return
    end

    local error = fps - minFps
    if math.abs(error) <= SMART_DEADBAND_FPS then
        return
    end

    local normalizedError = math.min(1.0, math.abs(error) / math.max(1, minFps))
    if error > 0 then
        Importer.smartScale = Importer.smartScale + (SMART_RAMP_UP_PER_SEC * normalizedError * dt)
    else
        Importer.smartScale = Importer.smartScale - (SMART_RAMP_DOWN_PER_SEC * normalizedError * dt)
    end

    if Importer.smartScale < SMART_MIN_SCALE then
        Importer.smartScale = SMART_MIN_SCALE
    end
end

local function getSmartBatchSize(ctx, baseBatchSize)
    if not ctx.config.smartImport then
        return baseBatchSize
    end

    local scaledBatch = math.max(SMART_MIN_SCALE, baseBatchSize * Importer.smartScale)
    Importer.batchCarry = Importer.batchCarry + scaledBatch

    local dynamicBatch = math.floor(Importer.batchCarry)
    if dynamicBatch <= 0 then
        return 0
    end

    Importer.batchCarry = Importer.batchCarry - dynamicBatch
    return math.max(1, dynamicBatch)
end

local function resolveTdbid(item)
    if item.tdbid then
        return item.tdbid
    end

    local ok, record = pcall(function()
        return TweakDB:GetRecord(item.id)
    end)

    if ok and record then
        local okId, tdbid = pcall(function()
            return record:GetID()
        end)

        if okId then
            return tdbid
        end
    end

    return nil
end

function Importer.begin(ctx)
    if Importer.running then
        return
    end

    local resumeImport = ctx.state.phase == 'import' and (ctx.state.lastIndex or 1) > 1

    if not ctx.state.candidates or #ctx.state.candidates == 0 then
        ctx.state.candidates = Config.loadQueue(ctx.config)
        ctx.state.queued = #ctx.state.candidates
    end

    if #ctx.state.candidates == 0 then
        ctx.state.phase = 'idle'
        Logger.warn('Import requested with an empty queue')
        return
    end

    -- Load previously imported set so we can append to it
    if not ctx.importedSet then
        ctx.importedSet = Config.loadImported(ctx.config)
    end

    Importer.running = true
    Importer.index = 1
    Importer.smoothedFps = 0
    Importer.smartScale = 1.0
    Importer.batchCarry = 0
    if not resumeImport then
        ctx.state.importElapsed = 0
    end
    -- Only resume from saved index when we're actually resuming an interrupted import
    if resumeImport then
        Importer.index = math.max(1, tonumber(ctx.state.lastIndex))
    end
    Importer.accumulator = 0
    ctx.state.phase = 'import'
    ctx.state.paused = false
    ctx.state.readyToImport = false

    Config.saveState(ctx.config, State.snapshot(ctx.state, Importer.index))
    Logger.info('Beginning batched import from index ' .. tostring(Importer.index))
end

function Importer.tick(ctx, deltaTime)
    if not Importer.running or ctx.state.paused then
        return
    end

    updateFpsEstimate(ctx, deltaTime)
    updateSmartScale(ctx, deltaTime)
    ctx.state.importElapsed = (ctx.state.importElapsed or 0) + (deltaTime or 0)

    Importer.accumulator = Importer.accumulator + (deltaTime or 0)
    if Importer.accumulator < ctx.config.importDelay then
        return
    end

    local processed = 0
    local baseBatchSize = math.max(1, tonumber(ctx.config.batchSize or 1))
    local batchSize = getSmartBatchSize(ctx, baseBatchSize)

    -- Reset the cadence timer every cycle; smart batching uses token carry
    -- to gradually ramp work instead of hard skip/start oscillation.
    Importer.accumulator = 0

    if batchSize <= 0 then
        return
    end

    while processed < batchSize and Importer.index <= #ctx.state.candidates do
        local item = ctx.state.candidates[Importer.index]
        ctx.state.currentItemId = tostring(item.id or '')
        ctx.state.currentItemName = tostring(item.name or '')
        ctx.state.lastIndex = Importer.index
        ctx.state.lastReason = 'pending import'
        Config.saveState(ctx.config, State.snapshot(ctx.state, Importer.index))

        if ctx.blacklist and item.id and ctx.blacklist[item.id] then
            ctx.state.skipped = ctx.state.skipped + 1
            ctx.state.lastReason = 'skipped due to blacklist'
            Importer.index = Importer.index + 1
            processed = processed + 1
            Config.saveState(ctx.config, State.snapshot(ctx.state, Importer.index))
        else
            local ok, err = pcall(function()
                if not ctx.ts then
                    error('transaction system unavailable')
                end

                local player = Game.GetPlayer()
                if not player then
                    error('player unavailable')
                end

                local tdbid = resolveTdbid(item)
                if not tdbid then
                    error('failed to resolve TDBID')
                end

                ctx.ts:GiveItemByTDBID(player, tdbid, 1)
                if not ctx.config.keepInInventory then
                    ctx.ts:RemoveItemByTDBID(player, tdbid, 1)
                end
            end)

            if ok then
                ctx.state.imported = ctx.state.imported + 1
                ctx.state.lastReason = 'imported successfully'
                -- Track this item so re-scans skip it
                if item.id and ctx.importedSet then
                    ctx.importedSet[item.id] = true
                end
                -- Periodically persist imported set for crash safety
                if ctx.state.imported % 50 == 0 and ctx.importedSet then
                    Config.saveImported(ctx.config, ctx.importedSet)
                end
            else
                ctx.state.failed = ctx.state.failed + 1
                ctx.state.lastReason = tostring(err)
                table.insert(ctx.state.badItems, {
                    id = item.id,
                    name = item.name,
                    reason = tostring(err)
                })
                Logger.badItem('import', item.id, item.name, err)

                if ctx.config.stopOnError or ctx.state.failed >= ctx.config.maxFailuresBeforePause then
                    ctx.state.paused = true
                    Config.saveState(ctx.config, State.snapshot(ctx.state, Importer.index))
                    Logger.warn('Import paused after failure threshold was reached')
                    return
                end
            end

            Importer.index = Importer.index + 1
            processed = processed + 1
            Config.saveState(ctx.config, State.snapshot(ctx.state, Importer.index))
        end
    end

    if Importer.index > #ctx.state.candidates then
        Importer.running = false
        ctx.state.phase = 'done'
        ctx.state.lastIndex = 1
        Config.saveState(ctx.config, State.snapshot(ctx.state, 1))
        -- Persist imported set so future scans skip these items
        if ctx.importedSet then
            Config.saveImported(ctx.config, ctx.importedSet)
        end
        Logger.info('Import complete. Imported=' .. tostring(ctx.state.imported) .. ', failed=' .. tostring(ctx.state.failed))
    end
end

function Importer.pause(ctx)
    ctx.state.paused = true
    Config.saveState(ctx.config, State.snapshot(ctx.state, Importer.index))
    Logger.info('Import paused by user')
end

function Importer.resume(ctx)
    if #ctx.state.candidates == 0 then
        ctx.state.candidates = Config.loadQueue(ctx.config)
        ctx.state.queued = #ctx.state.candidates
    end

    if #ctx.state.candidates == 0 then
        Logger.warn('Resume requested but no queued items were found')
        return
    end

    Importer.running = true
    ctx.state.phase = 'import'
    ctx.state.paused = false
    Importer.index = math.max(1, tonumber(ctx.state.lastIndex or 1))
    Importer.smartScale = 1.0
    Importer.batchCarry = 0
    Logger.info('Import resumed at index ' .. tostring(Importer.index))
end

function Importer.stop(ctx)
    Importer.running = false
    Importer.index = 1
    Importer.accumulator = 0
    Importer.smoothedFps = 0
    Importer.smartScale = 1.0
    Importer.batchCarry = 0
    ctx.state.paused = false
end

function Importer.isRunning()
    return Importer.running
end

function Importer.getSmoothedFps()
    return Importer.smoothedFps or 0
end

function Importer.getSmartScale()
    return Importer.smartScale or 1.0
end

return Importer
