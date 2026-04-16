local UI = {}

-- HUD overlay state
local hudCompletedAt = 0
local HUD_LINGER_SECONDS = 5

-- CET panel tab state
local activeTab = 'status' -- 'status' or 'settings'

function UI.draw(ctx)
    if not ctx.config.showWindow then
        return
    end

    if not ImGui.Begin('EQEXUnlocker', true) then
        ImGui.End()
        return
    end

    -- Tab bar
    if ImGui.Button('Status', 140, 30) then
        activeTab = 'status'
    end
    ImGui.SameLine()
    if ImGui.Button('Settings', 140, 30) then
        activeTab = 'settings'
    end

    ImGui.Separator()

    if activeTab == 'settings' then
        UI.drawSettings(ctx)
    else
        UI.drawStatus(ctx)
    end

    ImGui.End()
end

function UI.drawStatus(ctx)
    -- Phase and counters
    ImGui.Text('Phase: ' .. tostring(ctx.state.phase))
    ImGui.Text('Scanned: ' .. tostring(ctx.state.scanned) .. ' / ' .. tostring(ctx.state.totalRecords))
    ImGui.Text('Queued: ' .. tostring(ctx.state.queued) .. ' | Imported: ' .. tostring(ctx.state.imported))
    ImGui.Text('Skipped: ' .. tostring(ctx.state.skipped) .. ' | Failed: ' .. tostring(ctx.state.failed))

    if ctx.state.skipReasons and next(ctx.state.skipReasons) then
        local reasons = {}
        for reason, count in pairs(ctx.state.skipReasons) do
            table.insert(reasons, '  ' .. reason .. ': ' .. tostring(count))
        end
        table.sort(reasons)
        for _, line in ipairs(reasons) do
            ImGui.Text(line)
        end
    end

    if ctx.state.currentItemId and ctx.state.currentItemId ~= '' then
        ImGui.Text('Item: ' .. tostring(ctx.state.currentItemId))
    end

    ImGui.Separator()

    -- Action buttons
    if ImGui.Button('Start Scan', 140, 30) then
        ctx.startScan()
    end
    ImGui.SameLine()
    if ImGui.Button('Start Import', 140, 30) then
        ctx.startImport()
    end

    if Importer.isRunning() and not ctx.state.paused then
        if ImGui.Button('Pause Import', 140, 30) then
            ctx.pauseImport()
        end
    elseif ctx.state.paused then
        if ImGui.Button('Resume Import', 140, 30) then
            ctx.resumeImport()
        end
    end

    if ImGui.Button('Reset Session', 140, 30) then
        ctx.resetSession()
    end
    ImGui.SameLine()
    if ImGui.Button('Blacklist Failed', 140, 30) then
        ctx.blacklistFailures()
    end

    ImGui.Separator()

    -- Recent failures
    ImGui.Text('Recent failures:')
    local startIndex = math.max(1, #ctx.state.badItems - 9)
    for index = startIndex, #ctx.state.badItems do
        local item = ctx.state.badItems[index]
        ImGui.TextWrapped(tostring(index) .. '. ' .. tostring(item.id or '?') .. ' :: ' .. tostring(item.reason or '?'))
    end

    ImGui.Text('Scanner: ' .. tostring(Scanner.isRunning()) .. ' | Importer: ' .. tostring(Importer.isRunning()))
end

function UI.drawSettings(ctx)
    local changed = false

    -- Auto Import
    local autoImport = ImGui.Checkbox('Auto-Import after scan', ctx.config.autoImport)
    if autoImport ~= ctx.config.autoImport then
        ctx.config.autoImport = autoImport
        changed = true
    end

    -- Include Vanilla
    local includeVanilla = ImGui.Checkbox('Include vanilla items', ctx.config.includeVanilla)
    if includeVanilla ~= ctx.config.includeVanilla then
        ctx.config.includeVanilla = includeVanilla
        changed = true
    end

    -- Keep In Inventory
    local keepInInventory = ImGui.Checkbox('Keep items in inventory', ctx.config.keepInInventory)
    if keepInInventory ~= ctx.config.keepInInventory then
        ctx.config.keepInInventory = keepInInventory
        changed = true
    end

    -- Show HUD Progress
    local showProgress = ImGui.Checkbox('Show HUD progress bar', ctx.config.showProgress)
    if showProgress ~= ctx.config.showProgress then
        ctx.config.showProgress = showProgress
        changed = true
    end

    -- Stop On Error
    local stopOnError = ImGui.Checkbox('Stop on first error', ctx.config.stopOnError)
    if stopOnError ~= ctx.config.stopOnError then
        ctx.config.stopOnError = stopOnError
        changed = true
    end

    ImGui.Separator()

    -- Batch Size
    ImGui.Text('Import batch size:')
    ImGui.SameLine()
    local batchSize, batchUsed = ImGui.InputInt('##batchSize', ctx.config.batchSize, 1, 5)
    if batchUsed and batchSize ~= ctx.config.batchSize then
        ctx.config.batchSize = math.max(1, math.min(100, batchSize))
        changed = true
    end

    -- Scan Batch Size
    ImGui.Text('Scan batch size:')
    ImGui.SameLine()
    local scanBatch, scanUsed = ImGui.InputInt('##scanBatch', ctx.config.scanBatchSize, 1, 10)
    if scanUsed and scanBatch ~= ctx.config.scanBatchSize then
        ctx.config.scanBatchSize = math.max(1, math.min(500, scanBatch))
        changed = true
    end

    -- Import Delay
    ImGui.Text('Import delay (sec):')
    ImGui.SameLine()
    local importDelay, delayUsed = ImGui.InputFloat('##importDelay', ctx.config.importDelay, 0.05, 0.1, '%.2f')
    if delayUsed and importDelay ~= ctx.config.importDelay then
        ctx.config.importDelay = math.max(0, math.min(5, importDelay))
        changed = true
    end

    -- Max Failures
    ImGui.Text('Max failures before pause:')
    ImGui.SameLine()
    local maxFail, failUsed = ImGui.InputInt('##maxFail', ctx.config.maxFailuresBeforePause, 1, 5)
    if failUsed and maxFail ~= ctx.config.maxFailuresBeforePause then
        ctx.config.maxFailuresBeforePause = math.max(1, math.min(1000, maxFail))
        changed = true
    end

    if changed then
        Config.save(ctx.config)
    end
end

function UI.drawHUD(ctx)
    if not ctx.config.showProgress then
        return
    end

    local state = ctx.state
    local phase = state.phase
    local isRunning = (phase == 'scan' or phase == 'import')
    local isDone = (phase == 'scan-complete' or phase == 'done')

    -- Track when activity ends so we can linger then hide
    if isRunning then
        hudCompletedAt = 0
    elseif isDone and hudCompletedAt == 0 then
        hudCompletedAt = os.clock()
    end

    -- Only show while running or briefly after completion
    if not isRunning and not isDone then
        return
    end
    if isDone and hudCompletedAt > 0 and (os.clock() - hudCompletedAt) > HUD_LINGER_SECONDS then
        return
    end

    -- Compute display values
    local title = ''
    local progress = 0
    local detail = ''

    if phase == 'scan' then
        title = 'EQEXUnlocker: Scanning'
        local total = math.max(1, state.totalRecords)
        progress = state.scanned / total
        detail = tostring(state.scanned) .. ' / ' .. tostring(state.totalRecords) .. ' records'
    elseif phase == 'scan-complete' then
        title = 'EQEXUnlocker: Scan Complete'
        progress = 1.0
        detail = tostring(state.queued) .. ' queued, ' .. tostring(state.skipped) .. ' skipped'
    elseif phase == 'import' then
        title = 'EQEXUnlocker: Importing'
        local total = math.max(1, state.queued)
        progress = math.max(0, state.lastIndex - 1) / total
        detail = tostring(state.imported) .. ' / ' .. tostring(state.queued)
        if state.failed > 0 then
            detail = detail .. '  (' .. tostring(state.failed) .. ' failed)'
        end
    elseif isDone then
        title = 'EQEXUnlocker: Import Complete'
        progress = 1.0
        detail = tostring(state.imported) .. ' imported, ' .. tostring(state.failed) .. ' failed'
    end

    if state.paused then
        title = title .. '  [Paused]'
    end

    progress = math.max(0, math.min(1, progress))

    local resX, _ = GetDisplayResolution()
    local hudW = 350
    local posX = (resX - hudW) / 2
    local posY = 40

    ImGui.SetNextWindowPos(posX, posY, ImGuiCond.Always)
    ImGui.SetNextWindowSize(hudW, 0, ImGuiCond.Always)

    local flags = ImGuiWindowFlags.NoTitleBar
        + ImGuiWindowFlags.NoResize
        + ImGuiWindowFlags.NoMove
        + ImGuiWindowFlags.NoScrollbar
        + ImGuiWindowFlags.NoCollapse
        + ImGuiWindowFlags.NoSavedSettings
        + ImGuiWindowFlags.NoFocusOnAppearing
        + ImGuiWindowFlags.NoBringToFrontOnFocus
        + ImGuiWindowFlags.AlwaysAutoResize

    -- Window style: dark translucent background
    ImGui.PushStyleColor(ImGuiCol.WindowBg, 0.08, 0.08, 0.10, 0.82)
    ImGui.PushStyleColor(ImGuiCol.Border, 0.35, 0.35, 0.40, 0.50)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, 6)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 12, 8)

    ImGui.Begin('##EQEXHud', true, flags)

    -- Gold title text, centered
    ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.82, 0.0, 1.0)
    local textW = ImGui.CalcTextSize(title)
    local padX = (hudW - textW) / 2
    if padX > 0 then
        ImGui.SetCursorPosX(padX)
    end
    ImGui.Text(title)
    ImGui.PopStyleColor()

    ImGui.Spacing()

    -- Gold progress bar on dark background
    local pct = math.floor(progress * 100)
    ImGui.PushStyleColor(ImGuiCol.PlotHistogram, 0.92, 0.73, 0.0, 1.0)
    ImGui.PushStyleColor(ImGuiCol.FrameBg, 0.15, 0.15, 0.18, 0.90)
    ImGui.ProgressBar(progress, -1, 20, tostring(pct) .. '%')
    ImGui.PopStyleColor(2)

    -- Gray detail text
    ImGui.PushStyleColor(ImGuiCol.Text, 0.70, 0.70, 0.70, 1.0)
    ImGui.Text(detail)
    ImGui.PopStyleColor()

    ImGui.End()

    ImGui.PopStyleVar(2)
    ImGui.PopStyleColor(2)
end

return UI