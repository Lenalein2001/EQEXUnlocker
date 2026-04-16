local Files = {}

local function getJsonApi()
    if type(json) == 'table' then
        return json
    end
    return nil
end

local jsonApi = getJsonApi()

local function escapeString(value)
    return '"' .. tostring(value)
        :gsub('\\', '\\\\')
        :gsub('"', '\\"')
        :gsub('\n', '\\n')
        :gsub('\r', '\\r') .. '"'
end

local function isArray(tbl)
    if type(tbl) ~= 'table' then
        return false
    end

    local count = 0
    for key, _ in pairs(tbl) do
        if type(key) ~= 'number' then
            return false
        end
        count = count + 1
    end

    for index = 1, count do
        if tbl[index] == nil then
            return false
        end
    end

    return true
end

local function encodeValue(value, depth)
    depth = depth or 0
    local indent = string.rep('  ', depth)
    local nextIndent = string.rep('  ', depth + 1)

    if type(value) == 'nil' then
        return 'null'
    elseif type(value) == 'boolean' then
        return value and 'true' or 'false'
    elseif type(value) == 'number' then
        return tostring(value)
    elseif type(value) == 'string' then
        return escapeString(value)
    elseif type(value) ~= 'table' then
        return escapeString(tostring(value))
    end

    if isArray(value) then
        local parts = {}
        for _, item in ipairs(value) do
            table.insert(parts, nextIndent .. encodeValue(item, depth + 1))
        end

        if #parts == 0 then
            return '[]'
        end

        return '[\n' .. table.concat(parts, ',\n') .. '\n' .. indent .. ']'
    end

    local keys = {}
    for key, _ in pairs(value) do
        table.insert(keys, key)
    end
    table.sort(keys)

    local parts = {}
    for _, key in ipairs(keys) do
        table.insert(parts, nextIndent .. escapeString(key) .. ': ' .. encodeValue(value[key], depth + 1))
    end

    if #parts == 0 then
        return '{}'
    end

    return '{\n' .. table.concat(parts, ',\n') .. '\n' .. indent .. '}'
end

local function parseFlatObject(text)
    local data = {}
    for key, raw in text:gmatch('"([^"]+)"%s*:%s*([^,%}%]]+)') do
        local value = raw:gsub('^%s+', ''):gsub('%s+$', '')

        if value == 'true' then
            data[key] = true
        elseif value == 'false' then
            data[key] = false
        elseif value == 'null' then
            data[key] = nil
        elseif tonumber(value) ~= nil then
            data[key] = tonumber(value)
        elseif value:match('^".*"$') then
            data[key] = value:sub(2, -2):gsub('\\n', '\n'):gsub('\\r', '\r'):gsub('\\"', '"'):gsub('\\\\', '\\')
        end
    end
    return data
end

local function parseStringArray(text)
    local values = {}
    for value in text:gmatch('"([^"]*)"') do
        table.insert(values, value)
    end
    return values
end

function Files.readAll(path)
    local file = io.open(path, 'r')
    if not file then
        return nil
    end

    local text = file:read('*a')
    file:close()
    return text
end

function Files.writeAll(path, content)
    local file, err = io.open(path, 'w')
    if not file then
        return false, err
    end

    file:write(content or '')
    file:close()
    return true
end

function Files.appendLine(path, line)
    local file, err = io.open(path, 'a')
    if not file then
        return false, err
    end

    file:write(tostring(line or ''), '\n')
    file:close()
    return true
end

function Files.loadJson(path, fallback)
    local text = Files.readAll(path)
    if not text or text == '' then
        return fallback or {}
    end

    if jsonApi and jsonApi.decode then
        local ok, decoded = pcall(jsonApi.decode, text)
        if ok and type(decoded) == 'table' then
            return decoded
        end
    end

    if text:match('^%s*%[') then
        return parseStringArray(text)
    end

    return parseFlatObject(text)
end

function Files.saveJson(path, data)
    if jsonApi and jsonApi.encode then
        local ok, encoded = pcall(jsonApi.encode, data)
        if ok and encoded then
            return Files.writeAll(path, encoded)
        end
    end

    return Files.writeAll(path, encodeValue(data, 0))
end

function Files.saveQueue(path, candidates)
    local lines = {}
    for _, item in ipairs(candidates or {}) do
        table.insert(lines, tostring(item.id or '') .. '\t' .. tostring(item.name or ''))
    end
    return Files.writeAll(path, table.concat(lines, '\n'))
end

function Files.loadQueue(path)
    local text = Files.readAll(path)
    local queue = {}

    if not text or text == '' then
        return queue
    end

    for line in text:gmatch('[^\r\n]+') do
        local id, name = line:match('^(.-)\t(.*)$')
        if id and id ~= '' then
            table.insert(queue, { id = id, name = name or id })
        end
    end

    return queue
end

return Files