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
