
local Importer = {
    running = false,
    index = 1,
    accumulator = 0
}

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
    -- Only resume from saved index when we're actually resuming an interrupted import
    if ctx.state.phase == 'import' and (ctx.state.lastIndex or 1) > 1 then
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

    Importer.accumulator = Importer.accumulator + (deltaTime or 0)
    if Importer.accumulator < ctx.config.importDelay then
        return
    end

    Importer.accumulator = 0
    local processed = 0
    local batchSize = math.max(1, tonumber(ctx.config.batchSize or 1))

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
    Logger.info('Import resumed at index ' .. tostring(Importer.index))
end

function Importer.stop(ctx)
    Importer.running = false
    Importer.index = 1
    Importer.accumulator = 0
    ctx.state.paused = false
end

function Importer.isRunning()
    return Importer.running
end

return Importer
