print('[SafeUnlocker] init.lua parsing OK')

local function safeRequire(path)
    local ok, result = pcall(require, path)
    if not ok then
        print('[SafeUnlocker] REQUIRE FAILED: ' .. path)
        print('[SafeUnlocker] Error: ' .. tostring(result))
        return nil
    end
    if result == nil then
        print('[SafeUnlocker] REQUIRE RETURNED NIL: ' .. path)
        return nil
    end
    print('[SafeUnlocker] loaded: ' .. path)
    return result
end

Files       = safeRequire('src/core/files')
Config      = safeRequire('src/core/config')
Logger      = safeRequire('src/core/logger')
State       = safeRequire('src/core/state')
Scanner     = safeRequire('src/core/scanner')
Importer    = safeRequire('src/core/importer')
UI          = safeRequire('src/core/ui')
ModSettings = safeRequire('src/core/modsettings')

print('[SafeUnlocker] all modules loaded, running src/init.lua')
dofile('src/init.lua')
