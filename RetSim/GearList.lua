-- The gear list: the pieces of a set you built on the website, where each comes from, and which you already have.
-- The website makes the code under Export > Addon gear list: "RSG1:" + base64 of JSON
--   { v = 1, name = "...", items = { { s = inventory slot, id = item id, n = name, q = quality, src = where it comes from,
--     e = enchant name, ei = enchant id }, ... } }
-- Paste it with Import (or /rsim import <code>); /rsim list opens the list. It is kept between sessions.
local ADDON, RS = ...
if RS.notPaladin then return end

local SLOT_NAME = { [1] = 'Head', [2] = 'Neck', [3] = 'Shoulders', [15] = 'Back', [5] = 'Chest', [9] = 'Wrists', [10] = 'Hands', [6] = 'Waist',
  [7] = 'Legs', [8] = 'Feet', [11] = 'Ring', [12] = 'Ring', [13] = 'Trinket', [14] = 'Trinket', [16] = 'Weapon', [18] = 'Libram' }
local ORDER = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 18 }
-- a ring or trinket counts as worn in either of its two slots
local PAIR = { [11] = { 11, 12 }, [12] = { 11, 12 }, [13] = { 13, 14 }, [14] = { 13, 14 } }
local QUALITY = { [0] = 'ff9d9d9d', [1] = 'ffffffff', [2] = 'ff1eff00', [3] = 'ff0070dd', [4] = 'ffa335ee', [5] = 'ffff8000' }
local MAX_ITEMS = 20

-- Takes a decoded code. Returns true and a sentence, or false and why not.
function RS.setGearList(data)
  if type(data) ~= 'table' or type(data.items) ~= 'table' then return false, 'That gear list code holds no items.' end
  local items = {}
  for i = 1, #data.items do
    local x = data.items[i]
    if type(x) == 'table' and type(x.id) == 'number' and SLOT_NAME[x.s] and #items < MAX_ITEMS then
      items[#items + 1] = { s = x.s, id = x.id, n = type(x.n) == 'string' and x.n:sub(1, 80) or ('Item ' .. x.id), q = type(x.q) == 'number' and x.q or 1,
        src = type(x.src) == 'string' and x.src:sub(1, 200) or '', e = type(x.e) == 'string' and x.e:sub(1, 60) or nil, ei = type(x.ei) == 'number' and x.ei or nil }
    end
  end
  if #items == 0 then return false, 'That gear list code holds no items the addon can show.' end
  local at = {}
  for i = 1, #ORDER do at[ORDER[i]] = i end
  table.sort(items, function(a, b) if at[a.s] ~= at[b.s] then return at[a.s] < at[b.s] end return a.id < b.id end)
  RS.db.gearList = { name = type(data.name) == 'string' and data.name:sub(1, 60) or nil, items = items }
  return true, 'Gear list taken from the code: ' .. #items .. ' pieces. Type /rsim list to see it.'
end

local function call(f, ...)
  if type(f) ~= 'function' then return nil end
  local ok, a = pcall(f, ...)
  if ok then return a end
  return nil
end
-- every item id in your bags
local function bagItems()
  local have = {}
  local C = C_Container
  if not C then return have end
  for bag = 0, 4 do
    local n = call(C.GetContainerNumSlots, bag) or 0
    for slot = 1, n do
      local link = call(C.GetContainerItemLink, bag, slot)
      local id = type(link) == 'string' and tonumber(link:match('item:(%d+)'))
      if id then have[id] = true end
    end
  end
  return have
end

-- The list with what you have: each piece is 'worn', 'bags' (in your bags) or 'need'; enchant = true / false / nil (none asked).
function RS.gearListStatus()
  local list = RS.db and RS.db.gearList
  if not list then return nil end
  local bags, rows, have = bagItems(), {}, 0
  for i = 1, #list.items do
    local x = list.items[i]
    local state, wornSlot = 'need', nil
    local slots = PAIR[x.s] or { x.s }
    for j = 1, #slots do if call(GetInventoryItemID, 'player', slots[j]) == x.id then state, wornSlot = 'worn', slots[j] end end
    if state == 'need' and bags[x.id] then state = 'bags' end
    local enchant = nil
    if x.ei and wornSlot then
      local link = call(GetInventoryItemLink, 'player', wornSlot)
      enchant = type(link) == 'string' and tonumber(link:match('item:%d+:(%d+)')) == x.ei
    end
    if state ~= 'need' then have = have + 1 end
    rows[i] = { item = x, state = state, enchant = enchant }
  end
  return rows, have, list.name
end

-- ----- the window -----
local frame, lines
local W, ROW_H = 500, 30
local STATE_TEXT = { worn = '|cff40ff40worn|r', bags = '|cffffd100in your bags|r', need = '|cffff6060missing|r' }

local function build()
  frame = CreateFrame('Frame', 'RetSimGearFrame', UIParent)
  frame:SetSize(W, 86 + MAX_ITEMS * ROW_H)
  frame:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
  frame:SetFrameStrata('DIALOG')
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag('LeftButton')
  frame:SetScript('OnDragStart', function(self) self:StartMoving() end)
  frame:SetScript('OnDragStop', function(self) self:StopMovingOrSizing() end)
  local bg = frame:CreateTexture(nil, 'BACKGROUND')
  bg:SetAllPoints(frame)
  bg:SetColorTexture(0.06, 0.07, 0.10, 0.95)
  if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = 'RetSimGearFrame' end     -- Escape closes it
  local close = CreateFrame('Button', nil, frame, 'UIPanelCloseButton')
  close:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -2, -2)
  frame.title = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
  frame.title:SetPoint('TOPLEFT', frame, 'TOPLEFT', 14, -12)
  frame.sub = frame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
  frame.sub:SetPoint('TOPLEFT', frame.title, 'BOTTOMLEFT', 0, -6)
  frame.sub:SetWidth(W - 28)
  frame.sub:SetJustifyH('LEFT')
  lines = {}
  for i = 1, MAX_ITEMS do
    local y = -62 - (i - 1) * ROW_H
    local slot = frame:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
    slot:SetPoint('TOPLEFT', frame, 'TOPLEFT', 14, y)
    slot:SetWidth(64); slot:SetJustifyH('LEFT')
    local name = frame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    name:SetPoint('TOPLEFT', frame, 'TOPLEFT', 80, y)
    name:SetWidth(W - 80 - 110); name:SetJustifyH('LEFT')
    local state = frame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    state:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -14, y)
    state:SetWidth(100); state:SetJustifyH('RIGHT')
    local src = frame:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
    src:SetPoint('TOPLEFT', frame, 'TOPLEFT', 80, y - 13)
    src:SetWidth(W - 80 - 14); src:SetJustifyH('LEFT')
    if src.SetWordWrap then src:SetWordWrap(false) end
    lines[i] = { slot = slot, name = name, state = state, src = src }
  end
  -- what you wear or carry changes: the list follows while it is open
  frame:SetScript('OnEvent', function() if frame:IsShown() then RS.refreshGearList() end end)
  for _, ev in ipairs({ 'BAG_UPDATE', 'PLAYER_EQUIPMENT_CHANGED', 'UNIT_INVENTORY_CHANGED' }) do pcall(frame.RegisterEvent, frame, ev) end
  frame:Hide()
end

function RS.refreshGearList()
  if not frame then return end
  local rows, have, name = RS.gearListStatus()
  frame.title:SetText('|cfff58cbaGear list|r' .. (name and (': ' .. name) or ''))
  for i = 1, MAX_ITEMS do local l = lines[i]; l.slot:SetText(''); l.name:SetText(''); l.state:SetText(''); l.src:SetText('') end
  if not rows then
    frame.sub:SetText('No gear list yet. On the website, build your set, choose Export > Addon gear list, copy the code and paste it here with Import.')
    frame:SetHeight(110)
    return
  end
  frame.sub:SetText(string.format('You have %d of %d pieces. Where the missing ones come from is under each name.', have, #rows))
  for i = 1, #rows do
    local r, l = rows[i], lines[i]
    local x = r.item
    l.slot:SetText(SLOT_NAME[x.s])
    l.name:SetText('|c' .. (QUALITY[x.q] or QUALITY[1]) .. x.n .. '|r')
    l.state:SetText(STATE_TEXT[r.state])
    local under = x.src ~= '' and x.src or 'Source not recorded'
    if x.e then
      under = under .. '  |  ' .. (r.enchant == true and '|cff40ff40' .. x.e .. '|r' or r.enchant == false and '|cffff6060needs ' .. x.e .. '|r' or 'enchant: ' .. x.e)
    end
    l.src:SetText(under)
  end
  frame:SetHeight(76 + #rows * ROW_H)
end

function RS.showGearList()
  if not frame then build() end
  frame:Show()
  RS.refreshGearList()
end
function RS.toggleGearList()
  if not frame then build() end
  if frame:IsShown() then frame:Hide() else RS.showGearList() end
end
