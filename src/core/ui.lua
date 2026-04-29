local UI = {}

-- HUD overlay state
local hudCompletedAt = 0
local HUD_LINGER_SECONDS = 5

-- CET panel tab state
local activeTab = 'status' -- 'status' or 'settings'

local function formatDuration(seconds)
    local totalSeconds = math.max(0, math.floor((seconds or 0) + 0.5))
    local hours = math.floor(totalSeconds / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local secs = totalSeconds % 60

    if hours > 0 then
        return string.format('%d:%02d:%02d', hours, minutes, secs)
    end

    return string.format('%02d:%02d', minutes, secs)
end

local function calculateEta(elapsed, completed, total)
    if (total or 0) <= 0 then
        return nil
    end

    if (completed or 0) >= total then
        return 0
    end

    if (completed or 0) <= 0 or (elapsed or 0) <= 0 then
        return nil
    end

    return (elapsed / completed) * (total - completed)
end

local function formatEta(seconds, approximate)
    if seconds == nil then
        return '--:--'
    end

    if approximate then
        return '~' .. formatDuration(seconds)
    end

    return formatDuration(seconds)
end

local function getScanEta(state)
    return calculateEta(state.scanElapsed, state.scanned, state.totalRecords)
end

local function getEstimatedImportEta(state, config)
    local queued = math.max(0, tonumber(state.queued or 0))
    if queued <= 0 then
        return nil
    end

    local batchSize = math.max(1, tonumber((config and config.batchSize) or 1))
    local importDelay = math.max(0, tonumber((config and config.importDelay) or 0))
    local batches = math.ceil(queued / batchSize)
    return batches * importDelay
end

local function getImportEta(state, config)
    if state.phase == 'done' and (state.queued or 0) > 0 then
        return 0, false
    end

    local processed = math.max(0, (state.lastIndex or 1) - 1)
    local liveEta = calculateEta(state.importElapsed, processed, state.queued)
    if liveEta ~= nil then
        return liveEta, false
    end

    if state.phase ~= 'scan' and state.phase ~= 'import' and processed == 0 and (state.importElapsed or 0) <= 0 then
        return getEstimatedImportEta(state, config), true
    end

    return nil, false
end

function UI.draw(ctx)
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
    local scanEta = getScanEta(ctx.state)
    local importEta, importEtaApprox = getImportEta(ctx.state, ctx.config)
    local importFps = 0
    local smartScale = 1.0
    if Importer and Importer.getSmoothedFps then
        importFps = tonumber(Importer.getSmoothedFps()) or 0
    end
    if Importer and Importer.getSmartScale then
        smartScale = tonumber(Importer.getSmartScale()) or 1.0
    end

    -- Phase and counters
    ImGui.Text('Phase: ' .. tostring(ctx.state.phase))
    ImGui.Text('Scanned: ' .. tostring(ctx.state.scanned) .. ' / ' .. tostring(ctx.state.totalRecords))
    ImGui.Text('Queued: ' .. tostring(ctx.state.queued) .. ' | Imported: ' .. tostring(ctx.state.imported))
    ImGui.Text('Skipped: ' .. tostring(ctx.state.skipped) .. ' | Failed: ' .. tostring(ctx.state.failed))
    ImGui.Text('Scan time: ' .. formatDuration(ctx.state.scanElapsed) .. ' | ETA: ' .. formatEta(scanEta))
    ImGui.Text('Import time: ' .. formatDuration(ctx.state.importElapsed) .. ' | ETA: ' .. formatEta(importEta, importEtaApprox))
    if ctx.config.smartImport then
        local fpsText = '--'
        if importFps > 0 then
            fpsText = tostring(math.floor(importFps + 0.5))
        end
        local scalePct = math.floor((smartScale * 100) + 0.5)
        ImGui.Text('Smart import: ON | Min FPS: ' .. tostring(ctx.config.smartImportMinFps) .. ' | Current: ' .. fpsText .. ' | Speed: ' .. tostring(scalePct) .. '%')
    else
        ImGui.Text('Smart import: OFF')
    end

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

    if ImGui.Button('Re-add All', 290, 30) then
        ctx.forceRescanAll()
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
        ctx.config.scanBatchSize = math.max(1, math.min(1000, scanBatch))
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
    
    -- Smart Import
    local smartImport = ImGui.Checkbox('Smart import (respect FPS threshold)', ctx.config.smartImport)
    if smartImport ~= ctx.config.smartImport then
        ctx.config.smartImport = smartImport
        changed = true
    end

    -- Smart Import FPS Threshold
    ImGui.Text('Smart import minimum FPS:')
    ImGui.SameLine()
    local minFps, minFpsUsed = ImGui.InputInt('##smartImportMinFps', ctx.config.smartImportMinFps, 1, 5)
    if minFpsUsed and minFps ~= ctx.config.smartImportMinFps then
        ctx.config.smartImportMinFps = math.max(20, math.min(240, minFps))
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
    local eta = nil
    local etaApprox = false

    if phase == 'scan' then
        title = 'EQEXUnlocker: Scanning'
        local total = math.max(1, state.totalRecords)
        progress = state.scanned / total
        eta = getScanEta(state)
        detail = tostring(state.scanned) .. ' / ' .. tostring(state.totalRecords) .. ' records  |  ' .. formatDuration(state.scanElapsed) .. ' elapsed  |  ETA ' .. formatEta(eta)
    elseif phase == 'scan-complete' then
        title = 'EQEXUnlocker: Scan Complete'
        progress = 1.0
        eta, etaApprox = getImportEta(state, ctx.config)
        detail = tostring(state.queued) .. ' queued, ' .. tostring(state.skipped) .. ' skipped  |  ' .. formatDuration(state.scanElapsed)
        if eta ~= nil then
            detail = detail .. '  |  Est. import ETA ' .. formatEta(eta, etaApprox)
        end
    elseif phase == 'import' then
        title = 'EQEXUnlocker: Importing'
        local total = math.max(1, state.queued)
        progress = math.max(0, state.lastIndex - 1) / total
        eta, etaApprox = getImportEta(state, ctx.config)
        local importFps = 0
        local smartScale = 1.0
        if Importer and Importer.getSmoothedFps then
            importFps = tonumber(Importer.getSmoothedFps()) or 0
        end
        if Importer and Importer.getSmartScale then
            smartScale = tonumber(Importer.getSmartScale()) or 1.0
        end
        detail = tostring(state.imported) .. ' / ' .. tostring(state.queued)
        if state.failed > 0 then
            detail = detail .. '  (' .. tostring(state.failed) .. ' failed)'
        end
        detail = detail .. '  |  ' .. formatDuration(state.importElapsed) .. ' elapsed  |  ETA ' .. formatEta(eta, etaApprox)
        if ctx.config.smartImport and importFps > 0 then
            detail = detail .. '  |  FPS ' .. tostring(math.floor(importFps + 0.5)) .. '/' .. tostring(ctx.config.smartImportMinFps)
            detail = detail .. '  |  Speed ' .. tostring(math.floor((smartScale * 100) + 0.5)) .. '%'
        end
    elseif isDone then
        title = 'EQEXUnlocker: Import Complete'
        progress = 1.0
        detail = tostring(state.imported) .. ' imported, ' .. tostring(state.failed) .. ' failed  |  ' .. formatDuration(state.importElapsed)
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
    ImGui.TextWrapped(detail)
    ImGui.PopStyleColor()

    ImGui.End()

    ImGui.PopStyleVar(2)
    ImGui.PopStyleColor(2)
end

return UI