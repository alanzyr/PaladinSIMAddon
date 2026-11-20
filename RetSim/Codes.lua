-- The export code: what you wear, your talents, race and rotation, as one line of text the website reads under
-- Import > Addon. A code is "RSA1:" + base64 of JSON text. JSON and base64 are written out here (no game API in this
-- file; Core.lua gathers the items). The idea of codes between addon and website comes from Xn's Warlock Sim.
--   RS.talentString(ranks)   the website's talent string, e.g. "050250002-501-05233011201301351"
--   RS.encodeExport(data)    the code
local ADDON, RS = ...
if RS.notPaladin then return end

-- ---------------------------------------------------------------------------------------------------------------------
-- JSON (what the export needs: tables with string keys, lists, numbers, strings, booleans)
-- ---------------------------------------------------------------------------------------------------------------------
local function jsonString(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' elseif c == '\\' then return '\\\\' elseif c == '\n' then return '\\n' end
    return string.format('\\u%04x', c:byte())
  end) .. '"'
end
local function json(v)
  local t = type(v)
  if t == 'number' then
    if v == math.floor(v) and math.abs(v) < 1e15 then return string.format('%d', v) end
    return (string.format('%.6f', v):gsub('0+$', ''):gsub('%.$', ''))
  elseif t == 'boolean' then return v and 'true' or 'false'
  elseif t == 'string' then return jsonString(v)
  elseif t == 'table' then
    if #v > 0 or next(v) == nil and v.__list then
      local parts = {}
      for i = 1, #v do parts[i] = json(v[i]) end
      return '[' .. table.concat(parts, ',') .. ']'
    end
    local keys = {}
    for k in pairs(v) do if k ~= '__list' then keys[#keys + 1] = tostring(k) end end
    table.sort(keys)
    local parts = {}
    for i = 1, #keys do
      local k = keys[i]
      local x = v[k]
      if x == nil then x = v[tonumber(k)] end
      parts[i] = jsonString(k) .. ':' .. json(x)
    end
    return '{' .. table.concat(parts, ',') .. '}'
  end
  return 'null'
end
RS.jsonEncode = json

-- ---------------------------------------------------------------------------------------------------------------------
-- base64 (the standard alphabet, with padding)
-- ---------------------------------------------------------------------------------------------------------------------
local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64(s)
  local out = {}
  for i = 1, #s, 3 do
    local a, b, c = s:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1, c2, c3, c4 = math.floor(n / 262144) % 64, math.floor(n / 4096) % 64, math.floor(n / 64) % 64, n % 64
    out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1) .. (b and B64:sub(c3 + 1, c3 + 1) or '=') .. (c and B64:sub(c4 + 1, c4 + 1) or '=')
  end
  return table.concat(out)
end
RS.base64 = base64

-- The website's talent string: every talent's rank, tree by tree in the website's order, zeros at the end of a tree left out.
function RS.talentString(ranks)
  local trees = { {}, {}, {} }
  for i = 1, #RS.TALENTS do
    local t = RS.TALENTS[i]
    local list = trees[t.tree]
    list[#list + 1] = string.format('%d', math.min(t.max, math.max(0, math.floor((ranks or {})[t.name] or 0))))
  end
  local parts = {}
  for i = 1, 3 do parts[i] = (table.concat(trees[i]):gsub('0+$', '')) end
  return table.concat(parts, '-')
end

-- data: { race = 'human', talents = { name = rank }, mode = 'auto', items = { [slot] = { id = 19323, enchant = 1900 } } }
function RS.encodeExport(data)
  local items = {}
  for slot, it in pairs(data.items or {}) do
    if type(it) == 'table' and type(it.id) == 'number' then items[tostring(slot)] = { id = it.id, enchant = (type(it.enchant) == 'number' and it.enchant > 0) and it.enchant or nil } end
  end
  local body = { v = 1, addon = RS.VERSION, race = data.race, talents = RS.talentString(data.talents), mode = data.mode, items = items }
  return 'RSA1:' .. base64(json(body))
end

-- ---------------------------------------------------------------------------------------------------------------------
-- reading a code: base64 and JSON back into a table
-- ---------------------------------------------------------------------------------------------------------------------
local B64_INDEX = {}
for i = 1, #B64 do B64_INDEX[B64:byte(i)] = i - 1 end
B64_INDEX[('-'):byte()], B64_INDEX[('_'):byte()] = 62, 63      -- the URL-safe alphabet is read too
-- Returns the bytes as a string, or nil when the text is not base64.
local function unbase64(s)
  s = s:gsub('%s', ''):gsub('=+$', '')
  if #s % 4 == 1 then return nil end
  local out = {}
  for i = 1, #s, 4 do
    local b1, b2, b3, b4 = s:byte(i, i + 3)
    local a, b = B64_INDEX[b1], b2 and B64_INDEX[b2]
    local c, d = b3 and B64_INDEX[b3], b4 and B64_INDEX[b4]
    if not a or not b or (b3 and not c) or (b4 and not d) then return nil end
    local n = a * 262144 + b * 4096 + (c or 0) * 64 + (d or 0)
    out[#out + 1] = string.char(math.floor(n / 65536) % 256)
    if c then out[#out + 1] = string.char(math.floor(n / 256) % 256) end
    if d then out[#out + 1] = string.char(n % 256) end
  end
  return table.concat(out)
end
RS.unbase64 = unbase64

-- JSON text -> value. Returns the value, or nil and a word about what went wrong. null becomes nil.
local function jsonDecode(text)
  local pos = 1
  local value
  local function skip() pos = text:find('[^ \t\r\n]', pos) or #text + 1 end
  local function fail(what) error({ json = what .. ' at character ' .. pos }) end
  local function str()
    pos = pos + 1
    local out = {}
    while true do
      local c = text:sub(pos, pos)
      if c == '' then fail('unfinished text') end
      if c == '"' then pos = pos + 1; return table.concat(out) end
      if c == '\\' then
        local e = text:sub(pos + 1, pos + 1)
        if e == 'u' then
          local code = tonumber(text:sub(pos + 2, pos + 5), 16)
          if not code then fail('bad \\u') end
          out[#out + 1] = code < 128 and string.char(code) or '?'
          pos = pos + 6
        else
          out[#out + 1] = (e == 'n' and '\n') or (e == 't' and '\t') or (e == 'r' and '\r') or (e == 'b' and '\b') or (e == 'f' and '\f') or e
          pos = pos + 2
        end
      else out[#out + 1] = c; pos = pos + 1 end
    end
  end
  function value()
    skip()
    local c = text:sub(pos, pos)
    if c == '{' then
      local o = {}
      pos = pos + 1; skip()
      if text:sub(pos, pos) == '}' then pos = pos + 1; return o end
      while true do
        skip()
        if text:sub(pos, pos) ~= '"' then fail('a name was expected') end
        local k = str()
        skip()
        if text:sub(pos, pos) ~= ':' then fail('":" was expected') end
        pos = pos + 1
        o[k] = value()
        skip()
        local d = text:sub(pos, pos)
        pos = pos + 1
        if d == '}' then return o end
        if d ~= ',' then fail('"," or "}" was expected') end
      end
    elseif c == '[' then
      local o = {}
      pos = pos + 1; skip()
      if text:sub(pos, pos) == ']' then pos = pos + 1; return o end
      while true do
        o[#o + 1] = value()
        skip()
        local d = text:sub(pos, pos)
        pos = pos + 1
        if d == ']' then return o end
        if d ~= ',' then fail('"," or "]" was expected') end
      end
    elseif c == '"' then return str()
    elseif text:sub(pos, pos + 3) == 'true' then pos = pos + 4; return true
    elseif text:sub(pos, pos + 4) == 'false' then pos = pos + 5; return false
    elseif text:sub(pos, pos + 3) == 'null' then pos = pos + 4; return nil
    else
      local num = text:match('^-?%d+%.?%d*[eE]?[+-]?%d*', pos)
      if not num or num == '' or not tonumber(num) then fail('a value was expected') end
      pos = pos + #num
      return tonumber(num)
    end
  end
  local ok, res = pcall(function() local v = value(); skip(); if pos <= #text then fail('text after the end') end; return v end)
  if ok then return res end
  return nil, type(res) == 'table' and res.json or tostring(res)
end
RS.jsonDecode = jsonDecode

-- The settings code: your raid buffs and debuffs, consumables, encounter and rotation, as the website reads and writes
-- it. "RSS1:" + base64 of JSON { v = 1, settings = { key = value, ... } }, the keys being the website's own.
function RS.encodeSettings(settings)
  return 'RSS1:' .. base64(json({ v = 1, addon = RS.VERSION, settings = settings }))
end
-- A pasted code -> its kind ('settings' or 'gear') and its content, or nil and a plain sentence.
function RS.decodeCode(text)
  text = tostring(text or ''):gsub('%s', '')
  local prefix, body = text:match('^(RS[SA]1):(.+)$')
  if not prefix then
    if text == '' then return nil, 'Paste a settings code first. The website makes one under Export > Addon settings.' end
    if text:find('^RS[01]:') then return nil, 'That is a share code of the website. The addon reads settings codes: on the website, choose Export > Addon settings.' end
    return nil, 'That is not a code the addon knows. On the website, choose Export > Addon settings and copy all of it.'
  end
  local raw = unbase64(body)
  local data, why = nil, nil
  if raw then data, why = jsonDecode(raw) end
  if type(data) ~= 'table' then return nil, 'That code is incomplete or damaged' .. (why and (' (' .. why .. ')') or '') .. '. Copy all of it and try again.' end
  if prefix == 'RSA1' then return 'gear', data end
  if type(data.settings) ~= 'table' then return nil, 'That settings code holds no settings.' end
  return 'settings', data
end
