
local Scanner = {
    running = false,
    records = {},
    index = 1,
    accumulator = 0
}

local function safeRecordId(record)
    local ok, value = pcall(function()
        return TDBID.ToStringDEBUG(record:GetID())
    end)
    if ok then
        return value
    end
    return nil
end

local function safeDisplayName(record)
    local ok, displayName = pcall(function()
        return record:DisplayName()
    end)

    if ok and displayName then
        local okText, localized = pcall(function()
            return Game.GetLocalizedTextByKey(displayName)
        end)

        if okText and localized and localized ~= '' then
            return localized
        end
    end

    return 'Unknown clothing item'
end

local function isQuestItem(record)
    local ok, value = pcall(function()
        return record:TagsContains('Quest')
    end)
    return ok and value == true
end

local function indexUnlockedItems(ctx)
    ctx.unlocked = {}

    if not ctx.wardrobeSystem then
        return
    end

    local ok, stored = pcall(function()
        return ctx.wardrobeSystem:GetStoredItemIDs()
    end)

    if not ok or type(stored) ~= 'table' then
        return
    end

    for _, item in pairs(stored) do
        local id = nil
        local okId = pcall(function()
            id = TDBID.ToStringDEBUG(item.id)
        end)

        if okId and id and id ~= '' then
            ctx.unlocked[id] = true
        end
    end
end

local function evaluateRecord(ctx, record, scanIndex)
    local ok, result = pcall(function()
        local tdbid = record:GetID()
        local itemId = safeRecordId(record)
        local itemName = safeDisplayName(record)

        if not itemId or itemId == '' then
            return { status = 'bad', reason = 'missing item id', id = 'scan-index-' .. tostring(scanIndex), name = itemName }
        end

        if ctx.blacklist[itemId] then
            return { status = 'skip', reason = 'user blacklist', id = itemId, name = itemName }
        end

        if not ctx.config.includeVanilla and ctx.basegame and ctx.basegame[itemId] then
            return { status = 'skip', reason = 'vanilla item', id = itemId, name = itemName }
        end

        if isQuestItem(record) then
            return { status = 'skip', reason = 'quest item', id = itemId, name = itemName }
        end

        if not ctx.forceScanAll and ctx.unlocked and ctx.unlocked[itemId] then
            return { status = 'skip', reason = 'already unlocked', id = itemId, name = itemName }
        end

        if not ctx.forceScanAll and ctx.importedSet and ctx.importedSet[itemId] then
            return { status = 'skip', reason = 'already unlocked', id = itemId, name = itemName }
        end

        if ctx.outfitSystem then
            local okEquip, isEquippable = pcall(function()
                return ctx.outfitSystem:IsEquippable(tdbid)
            end)

            if okEquip and not isEquippable then
                return { status = 'skip', reason = 'not equippable in Equipment-EX', id = itemId, name = itemName }
            end
        end

        return {
            status = 'ok',
            item = {
                id = itemId,
                name = itemName,
                tdbid = tdbid,
                index = scanIndex
            }
        }
    end)

    if ok then
        return result
    end

    return { status = 'bad', reason = tostring(result), id = 'scan-index-' .. tostring(scanIndex), name = 'Unknown clothing item' }
end

function Scanner.begin(ctx)
    if Scanner.running then
        return
    end

    State.reset(ctx.state)
    ctx.state.scanElapsed = 0
    ctx.blacklist = Config.loadBlacklist(ctx.config)
    ctx.basegame = Config.loadBasegameSet(ctx.config)
    ctx.importedSet = Config.loadImported(ctx.config)
    indexUnlockedItems(ctx)

    local ok, records = pcall(function()
        return TweakDB:GetRecords('gamedataClothing_Record') or {}
    end)

    if not ok then
        ctx.forceScanAll = false
        ctx.state.phase = 'error'
        ctx.state.lastReason = tostring(records)
        Logger.error('Unable to enumerate clothing records: ' .. tostring(records))
        return
    end

    Scanner.running = true
    Scanner.records = records
    Scanner.index = 1
    Scanner.accumulator = 0

    ctx.state.phase = 'scan'
    ctx.state.totalRecords = #records
    ctx.state.readyToImport = false
    Config.saveState(ctx.config, State.snapshot(ctx.state, Scanner.index))

    if ctx.forceScanAll then
        Logger.info('Full re-add scan started with ' .. tostring(#records) .. ' clothing records')
    else
        Logger.info('Safe scan started with ' .. tostring(#records) .. ' clothing records')
    end
end

function Scanner.tick(ctx, deltaTime)
    if not Scanner.running then
        return
    end

    ctx.state.scanElapsed = (ctx.state.scanElapsed or 0) + (deltaTime or 0)

    Scanner.accumulator = Scanner.accumulator + (deltaTime or 0)
    if Scanner.accumulator < ctx.config.scanDelay then
        return
    end

    Scanner.accumulator = 0
    local processed = 0
    local batchSize = math.max(1, tonumber(ctx.config.scanBatchSize or 1))

    while processed < batchSize and Scanner.index <= #Scanner.records do
        local record = Scanner.records[Scanner.index]
        local outcome = evaluateRecord(ctx, record, Scanner.index)

        ctx.state.scanned = Scanner.index
        ctx.state.lastIndex = Scanner.index

        if outcome.status == 'ok' then
            table.insert(ctx.state.candidates, outcome.item)
        elseif outcome.status == 'skip' then
            ctx.state.skipped = ctx.state.skipped + 1
            local reason = outcome.reason or 'unknown'
            ctx.state.skipReasons[reason] = (ctx.state.skipReasons[reason] or 0) + 1
        else
            ctx.state.failed = ctx.state.failed + 1
            ctx.state.currentItemId = tostring(outcome.id or '')
            ctx.state.currentItemName = tostring(outcome.name or '')
            ctx.state.lastReason = tostring(outcome.reason or 'scan failure')
            table.insert(ctx.state.badItems, outcome)
            Logger.badItem('scan', outcome.id, outcome.name, outcome.reason)
        end

        Scanner.index = Scanner.index + 1
        processed = processed + 1
    end

    if Scanner.index > #Scanner.records then
        Scanner.running = false
        Scanner.records = {}
        ctx.state.phase = 'scan-complete'
        ctx.state.queued = #ctx.state.candidates
        ctx.state.readyToImport = true
        ctx.state.lastIndex = 1
        Config.saveQueue(ctx.config, ctx.state.candidates)
        Config.saveState(ctx.config, State.snapshot(ctx.state, 1))
        ctx.forceScanAll = false
        local skipSummary = {}
        for reason, count in pairs(ctx.state.skipReasons) do
            table.insert(skipSummary, reason .. '=' .. tostring(count))
        end
        table.sort(skipSummary)
        Logger.info('Scan complete. Queued=' .. tostring(ctx.state.queued) .. ', skipped=' .. tostring(ctx.state.skipped) .. ', failed=' .. tostring(ctx.state.failed))
        if #skipSummary > 0 then
            Logger.info('Skip breakdown: ' .. table.concat(skipSummary, ', '))
        end
    else
        Config.saveState(ctx.config, State.snapshot(ctx.state, Scanner.index))
    end
end

function Scanner.stop(ctx)
    Scanner.running = false
    Scanner.records = {}
    Scanner.index = 1
    Scanner.accumulator = 0
    ctx.forceScanAll = false
end

function Scanner.isRunning()
    return Scanner.running
end

return Scanner
