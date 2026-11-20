-- Sim an item: your character as it is against your character with one item changed. After Xn's Warlock Sim (ItemUI.lua).
--   * Shift + right-click an item in your bags, on your character sheet, at a vendor, in a loot or quest window: a small
--     panel opens at the mouse and the sim starts at once. An item you are wearing is simmed against an empty slot:
--     what it is worth to you.
--   * Click an item link in chat: under the window that opens there is a "Sim this item" button.
--   * A small "Sim" button beside each loot roll popup (Need / Greed) of an item the sim can compare.
--   * /rsim item [link] does the same from the chat line.
-- The panel is the addon's own frame, parented to the screen. Nothing of the game's is changed; the click comes in
-- through a post-hook on the game's own handler for modified item clicks (hooksecurefunc: runs after it, cannot block it).
local ADDON, RS = ...
if RS.notPaladin then return end

local try = RS.try
local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) or false end
local function itemID(link) return link and tonumber(link:match('item:(%d+)')) end

-- What the game says about an item: name, where it goes, its stats, and what was read (kept for /rsim dump).
local function readItem(link)
  local item = { link = link, id = itemID(link) }
  item.name = (C_Item and try(C_Item.GetItemNameByID, link)) or link:match('%[(.-)%]') or 'this item'
  if C_Item then
    local _, _, _, equipLoc, _, classID, subclassID = try(C_Item.GetItemInfoInstant, link)
    item.equipLoc, item.classID, item.subclassID = equipLoc, classID, subclassID
  end
  local api = C_Item and try(C_Item.GetItemStats, link)
  local lines = {}
  local data = C_TooltipInfo and try(C_TooltipInfo.GetHyperlink, link)
  local types = Enum and Enum.TooltipDataLineType
  local enchanted = type(ENCHANTED_TOOLTIP_LINE) == 'string' and ENCHANTED_TOOLTIP_LINE:match('^(.-)%%s') or nil
  if type(data) == 'table' and type(data.lines) == 'table' then
    for i = 1, #data.lines do
      local l = data.lines[i]
      local text = type(l) == 'table' and l.leftText
      if type(text) == 'string' and not isSecret(text) then
        local plain = text:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')
        local isEnchant = (types and l.type == types.ItemEnchantmentPermanent) or (enchanted and enchanted ~= '' and plain:sub(1, #enchanted) == enchanted)
        -- an item's own stats never include its enchant; the right-hand text carries a weapon's speed
        if not isEnchant and not (types and l.type == types.GemSocket) then
          local right = l.rightText
          lines[#lines + 1] = (type(right) == 'string' and not isSecret(right)) and (text .. '\t' .. right) or text
        end
      end
    end
  end
  item.stats, item.unknown = RS.itemStats(type(api) == 'table' and api or nil, lines)
  item.raw = { api = type(api) == 'table' and api or nil, lines = lines }
  return item
end
RS.readItemInfo = readItem
local function equipped(slot)
  local link = try(GetInventoryItemLink, 'player', slot)
  if type(link) ~= 'string' then return nil end
  return readItem(link)
end

-- The swaps an item stands for: one per slot it could go into. `worn` = the item was clicked on the character sheet.
-- Returns a list of { label, olds = { stats, ... }, slot, worth } or nil and a plain sentence.
local function alternatives(item, worn)
  local slots = RS.ITEM_SLOTS[item.equipLoc or '']
  if not slots then return nil, RS.ITEM_NOT_PLAYED[item.equipLoc or ''] or 'This is not something the sim can compare.' end
  if item.equipLoc == 'INVTYPE_2HWEAPON' and not item.stats.weapon then return nil, 'This weapon\'s damage and speed could not be read from its tooltip.' end
  local function worth(slot) return { { worth = true, label = item.name, olds = { item.stats }, items = { item }, slot = slot } } end
  local list, same, sameSlot = {}, 0, nil
  for i = 1, #slots do
    local old = equipped(slots[i])
    if old and old.id == item.id then same, sameSlot = same + 1, sameSlot or slots[i]
    else list[#list + 1] = { label = old and old.name or 'the empty slot', olds = old and { old.stats } or {}, items = { old }, slot = slots[i] } end
  end
  if worn or #list == 0 then return worth(sameSlot or slots[1]) end
  if same > 0 and #list == 1 then list[1].note = 'You wear one of these already; this is it in your other slot.' end
  return list
end

-- mean of the differences fight by fight and its +-, over the fights both sides played
local function pairedDiff(base, list)
  local n = math.min(#base, #list)
  local s, s2 = 0, 0
  for f = 1, n do local d = list[f] - base[f]; s = s + d; s2 = s2 + d * d end
  if n < 2 then return n == 1 and s or 0, 0, n end
  local mean = s / n
  return mean, 1.96 * math.sqrt(math.max(0, (s2 - n * mean * mean) / (n - 1)) / n), n
end

-- Starts the job. Returns true, or false and a plain sentence.
function RS.simItem(link, worn)
  if RS.jobRunning() then return false, 'A sim is running. Wait for it to finish.' end
  if not (InCombatLockdown and InCombatLockdown()) then
    local ok, why = RS.doReadCharacter()
    if not ok and not RS.char then return false, why end
  elseif not RS.char then
    return false, 'You are in combat and your character has not been read yet. Try again after the fight.'
  end
  local item = readItem(link)
  local alts, why = alternatives(item, worn)
  if not alts then return false, why end
  local v, n = RS.values, RS.db.options.itemFights
  for i = 1, #alts do
    local a = alts[i]
    a.values, a.delta = RS.valuesWithSwap(v, (not a.worth) and item.stats or nil, a.olds, a.slot, (not a.worth) and item.id or nil)
  end
  RS.db.lastItem = { link = link, name = item.name, equipLoc = item.equipLoc, stats = item.stats, unknown = item.unknown, raw = item.raw, worn = worn or nil, against = {} }
  for i = 1, #alts do
    for _, old in pairs(alts[i].items or {}) do
      if old ~= item then RS.db.lastItem.against[#RS.db.lastItem.against + 1] = { link = old.link, name = old.name, stats = old.stats, unknown = old.unknown, raw = old.raw } end
    end
  end
  local picking = RS.wantsTwistPick(v)
  local seed = math.random(1, 999999)
  return RS.startJob('Item', (n + (picking and 180 or 0)) * (#alts + 1), function(j)
    local function onFight() j.done = j.done + 1 end
    local function play(values)
      local c = RS.derive(values)
      local mode = RS.resolveMode(RS.db.options.mode, values.wSpeed, picking and RS.pickTwist(c, values, seed, onFight) or nil)
      local list, sum = {}, 0
      for i = 0, n - 1 do
        local d = RS.simulateOnce(c, mode, seed * 7919 + i * 104729).dps
        list[i + 1] = d; sum = sum + d
        onFight(); RS.tick()
      end
      return { dps = sum / n, list = list, mode = mode }
    end
    local base = play(v)
    for i = 1, #alts do
      local r = play(alts[i].values)
      alts[i].dps, alts[i].mode = r.dps, r.mode
      alts[i].diff, alts[i].err = pairedDiff(base.list, r.list)
    end
    local r = j.result
    r.kind, r.link, r.worn, r.item, r.alts, r.n, r.base = 'item', link, worn, item, alts, n, base
  end)
end

local function resultText(res)
  local lines = {}
  for i = 1, #res.alts do
    local a = res.alts[i]
    local pct = res.base.dps > 0 and 100 * a.diff / res.base.dps or 0
    if a.worth then
      lines[#lines + 1] = string.format('You are wearing this. It is worth:\n|cff40ff40%.1f DPS|r (%.1f%% of your damage)  |cff999999+-%.1f|r', -a.diff, -pct, a.err)
      lines[#lines + 1] = '|cffaaaaaaIt gives: ' .. RS.describeStats(res.item.stats, false) .. '|r'
    else
      local verdict
      if math.abs(a.diff) <= a.err then verdict = string.format('|cffcccccc%+.1f DPS: about the same|r', a.diff)
      elseif a.diff > 0 then verdict = string.format('|cff40ff40%+.1f DPS|r (%+.1f%%)', a.diff, pct)
      else verdict = string.format('|cffff5050%+.1f DPS|r (%+.1f%%)', a.diff, pct) end
      lines[#lines + 1] = string.format('Instead of %s:\n%s  |cff999999+-%.1f|r', a.label, verdict, a.err)
      lines[#lines + 1] = '|cffaaaaaaChange: ' .. RS.describeStats(a.delta, true) .. '|r'
    end
    if a.mode and a.mode.key ~= res.base.mode.key then lines[#lines + 1] = '|cffaaaaaaPlayed with ' .. a.mode.name .. ' (you: ' .. res.base.mode.name .. ').|r' end
    if a.note then lines[#lines + 1] = '|cffaaaaaa' .. a.note .. '|r' end
  end
  local function notCounted(name, unknown)
    if not unknown or #unknown == 0 then return end
    local first = unknown[1]
    if #first > 60 then first = first:sub(1, 57) .. '...' end
    lines[#lines + 1] = '|cffffb060Not counted on ' .. name .. ': ' .. first .. (#unknown > 1 and (' (and ' .. (#unknown - 1) .. ' more)') or '') .. '|r'
  end
  notCounted(res.item.name, res.item.unknown)
  local seen = {}
  for i = 1, #res.alts do
    for _, old in pairs(res.alts[i].items or {}) do
      if old ~= res.item and not seen[old.link] then seen[old.link] = true; notCounted(old.name, old.unknown) end
    end
  end
  lines[#lines + 1] = string.format('|cff777777%.1f DPS as you are. %d fights a side. Your enchant on the slot is taken to move to the new item; set bonuses are not counted.|r', res.base.dps, res.n)
  return table.concat(lines, '\n')
end

-- ---------------------------------------------------------------------------------------------------------------------
-- the panel
-- ---------------------------------------------------------------------------------------------------------------------
local panel
local shown                                               -- what the panel is showing: { link, worn, pinned, name }
local running                                             -- the key of the item whose sim is running
local results = {}                                        -- what was shown for an item: results[key]
local lastRefLink                                         -- the item the item link window showed last time we looked
local WAIT = '|cffaaaaaaPlaying the fights...|r'
local function keyOf(link, worn) return link .. (worn and '|worn' or '') end

local function layout(text)
  local head = (shown and shown.pinned) and 18 or 0
  panel.title:SetShown(head > 0); panel.close:SetShown(head > 0)
  panel.button:ClearAllPoints(); panel.button:SetPoint('TOPLEFT', panel, 'TOPLEFT', 6, -5 - head)
  panel.text:ClearAllPoints(); panel.text:SetPoint('TOPLEFT', panel, 'TOPLEFT', 8, -28 - head)
  panel.text:SetText(text or '')
  local h = (text and text ~= '') and ((panel.text.GetStringHeight and panel.text:GetStringHeight() or 40) + 8) or 0
  panel:SetHeight(30 + head + h)
end
local function start()
  if not shown then return end
  local ok, err = RS.simItem(shown.link, shown.worn)
  if ok then running = keyOf(shown.link, shown.worn); layout(WAIT)
  else layout('|cffffb060' .. tostring(err) .. '|r') end
end
local function create()
  panel = CreateFrame('Frame', 'RetSimItemPanel', UIParent)
  panel:SetFrameStrata('TOOLTIP')
  panel:SetSize(270, 30)
  panel:SetClampedToScreen(true); panel:EnableMouse(true)
  local bg = panel:CreateTexture(nil, 'BACKGROUND')
  bg:SetAllPoints(panel); bg:SetColorTexture(0.05, 0.05, 0.08, 0.96)
  panel.title = panel:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
  panel.title:SetPoint('TOPLEFT', panel, 'TOPLEFT', 8, -7); panel.title:SetWidth(230); panel.title:SetJustifyH('LEFT')
  if panel.title.SetWordWrap then panel.title:SetWordWrap(false) end
  panel.close = CreateFrame('Button', nil, panel, 'UIPanelCloseButton')
  panel.close:SetSize(22, 22); panel.close:SetPoint('TOPRIGHT', panel, 'TOPRIGHT', 1, 1)
  panel.close:SetScript('OnClick', function()
    shown = nil; panel:Hide()
    lastRefLink = nil                                     -- if the item link window is still open, its own panel comes back
  end)
  panel.button = CreateFrame('Button', nil, panel, 'UIPanelButtonTemplate')
  panel.button:SetSize(120, 20)
  panel.button:SetText('Sim this item')
  panel.button:SetScript('OnClick', start)
  panel.progress = panel:CreateFontString(nil, 'ARTWORK', 'GameFontDisableSmall')
  panel.progress:SetPoint('LEFT', panel.button, 'RIGHT', 8, 0)
  panel.text = panel:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
  panel.text:SetWidth(254)
  panel.text:SetJustifyH('LEFT'); panel.text:SetJustifyV('TOP')
  if panel.text.SetSpacing then panel.text:SetSpacing(2) end
  panel:Hide()
end
local function show(link, worn, underRef)
  if not panel then create() end
  local name = link:match('%[(.-)%]') or 'Item'
  shown = { link = link, worn = worn, pinned = not underRef, name = name }
  panel.title:SetText(name)
  panel.button:SetText(worn and 'Sim its worth' or 'Sim this item')
  panel:ClearAllPoints()
  if underRef then
    panel:SetPoint('TOPLEFT', ItemRefTooltip, 'BOTTOMLEFT', 0, 2)
  else
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    if type(scale) ~= 'number' or scale <= 0 then scale = 1 end
    panel:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', (x or 0) / scale + 18, (y or 0) / scale - 6)
  end
  local key = keyOf(link, worn)
  layout(results[key] or (running == key and WAIT) or '')
  panel:Show()
end
-- /rsim item [link]: the panel at the mouse, and the sim at once
function RS.showItem(link) show(link, false, false); start() end

local function comparable(link)
  if type(link) ~= 'string' or isSecret(link) or not link:find('item:', 1, true) then return false end
  if not C_Item then return false end
  local _, _, _, equipLoc = try(C_Item.GetItemInfoInstant, link)
  return RS.ITEM_SLOTS[equipLoc or ''] ~= nil or RS.ITEM_NOT_PLAYED[equipLoc or ''] ~= nil
end
local function refLink()
  local tt = ItemRefTooltip
  if not tt or not tt.IsShown or not tt:IsShown() then return nil end
  local link
  if TooltipUtil and TooltipUtil.GetDisplayedItem then
    local _, l = try(TooltipUtil.GetDisplayedItem, tt)
    link = l
  end
  if not link and tt.GetItem then
    local _, l = try(tt.GetItem, tt)
    link = l
  end
  return comparable(link) and link or nil
end
local function enabled() return RS.db ~= nil and RS.db.options.itemClick ~= false end
local function clickMatches()
  local button = GetMouseButtonClicked and GetMouseButtonClicked()
  if type(button) == 'string' and button ~= 'RightButton' then return false end
  local alt = IsAltKeyDown and IsAltKeyDown() and true or false
  local shift = IsShiftKeyDown and IsShiftKeyDown() and true or false
  local ctrl = IsControlKeyDown and IsControlKeyDown() and true or false
  return shift and not alt and not ctrl
end

-- the loot roll popups: a small Sim button beside each
local rollButtons = {}
local function rollLink(f)
  if not f or not f.IsShown or not f:IsShown() then return nil end
  local id = f.rollID
  if id == nil or isSecret(id) or not GetLootRollItemLink then return nil end
  local link = try(GetLootRollItemLink, id)
  return comparable(link) and link or nil
end
local function rollButton(i)
  local b = CreateFrame('Button', nil, UIParent, 'UIPanelButtonTemplate')
  b:SetSize(44, 22); b:SetText('Sim'); b:SetFrameStrata('DIALOG')
  b:SetScript('OnClick', function(self)
    if not self.link then return end
    show(self.link, false, false)
    start()
  end)
  b:SetScript('OnEnter', function(self)
    GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
    GameTooltip:SetText('Forever Ret Sim')
    GameTooltip:AddLine('Sims this item against the one you wear in its slot.', 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript('OnLeave', function() GameTooltip:Hide() end)
  b:Hide()
  rollButtons[i] = b
  return b
end
local function updateRollButtons()
  local on = enabled()
  for i = 1, 8 do
    local f = _G['GroupLootFrame' .. i]
    if not f and not rollButtons[i] then break end
    local link = on and rollLink(f) or nil
    local b = rollButtons[i] or (link and rollButton(i))
    if b then
      if link then
        if b.owner ~= f then b:ClearAllPoints(); b:SetPoint('RIGHT', f, 'LEFT', -2, 0); b.owner = f end
        b.link = link
        if not b:IsShown() then b:Show() end
      elseif b:IsShown() then b.link = nil; b:Hide() end
    end
  end
end

local watcher, since = CreateFrame('Frame'), 0
watcher:SetScript('OnUpdate', function(_, elapsed)
  since = since + (elapsed or 0)
  if since < 0.2 then return end
  since = 0
  if not RS.db then return end
  updateRollButtons()
  if not enabled() then
    if panel and panel:IsShown() and shown and not shown.pinned then panel:Hide(); shown = nil end
    return
  end
  local link = refLink()
  if link ~= lastRefLink then
    lastRefLink = link
    if link then show(link, nil, true)
    elseif shown and not shown.pinned then shown = nil; panel:Hide() end
  end
  if not shown or not panel then return end
  local done, total = RS.jobProgress()
  panel.progress:SetText((done and running == keyOf(shown.link, shown.worn)) and string.format('%d%%', math.floor(total > 0 and 100 * done / total or 0)) or '')
  if panel.button.SetEnabled then panel.button:SetEnabled(not RS.jobRunning()) end
end)

local function onModifiedItemClick(link, itemLocation)
  if not enabled() or not clickMatches() or not comparable(link) then return end
  if type(itemLocation) == 'table' and itemLocation.IsEquipmentSlot and try(itemLocation.IsEquipmentSlot, itemLocation) then return end
  show(link, false, false)
  start()
end
local function onCharacterSlotClick(slot)
  if not enabled() or not clickMatches() then return end
  local id = type(slot) == 'table' and slot.GetID and try(slot.GetID, slot)
  if type(id) ~= 'number' then return end
  local link = try(GetInventoryItemLink, 'player', id)
  if not comparable(link) then return end
  show(link, true, false)
  start()
end
local hooked = {}
local function hookClicks()
  if not hooksecurefunc then return end
  if not hooked.items and HandleModifiedItemClick then
    hooked.items = true
    hooksecurefunc('HandleModifiedItemClick', function(link, itemLocation) pcall(onModifiedItemClick, link, itemLocation) end)
  end
  if not hooked.slots and PaperDollItemSlotButton_OnModifiedClick then
    hooked.slots = true
    hooksecurefunc('PaperDollItemSlotButton_OnModifiedClick', function(slot) pcall(onCharacterSlotClick, slot) end)
  end
end
hookClicks()
local late = CreateFrame('Frame')                           -- once more at login, in case the game made its functions after this file was read
late:RegisterEvent('PLAYER_LOGIN')
late:SetScript('OnEvent', hookClicks)

-- The job's end: an item sim's answer goes to the panel, anything else to the window as before.
local windowEnd = RS.onJobEnd
RS.onJobEnd = function(result, err)
  if not running then return windowEnd(result, err) end
  local key = (result and result.kind == 'item' and keyOf(result.link, result.worn)) or running
  running = nil
  local text = result and result.kind == 'item' and resultText(result) or ('|cffffb060' .. tostring(err or 'The sim stopped.') .. '|r')
  results[key] = text
  if result and result.kind == 'item' then RS.lastItemResult = result end
  if shown and panel and keyOf(shown.link, shown.worn) == key then layout(text) end
  if RS.refresh then RS.refresh() end
end
