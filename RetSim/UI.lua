-- The window: your DPS with its margin, a line per damage source, the notes from reading your character, and buttons
-- for Sim, the rotation, the raid buffs and the dump. Deliberately small for now; the pages of Xn's window come later.
local ADDON, RS = ...
if RS.notPaladin then return end

local W, H, ROWS = 400, 530, 16
local frame, dumpFrame
local ui = {}

local function fill(f, r, g, b, a)
  local t = f:CreateTexture(nil, 'BACKGROUND')
  t:SetAllPoints(f)
  t:SetColorTexture(r, g, b, a)
  return t
end
local function text(parent, font, justify)
  local s = parent:CreateFontString(nil, 'OVERLAY', font or 'GameFontHighlightSmall')
  s:SetJustifyH(justify or 'LEFT')
  return s
end
local function button(parent, label, width, onClick)
  local b = CreateFrame('Button', nil, parent, 'UIPanelButtonTemplate')
  b:SetSize(width, 22)
  b:SetText(label)
  b:SetScript('OnClick', onClick)
  return b
end

local function build()
  frame = CreateFrame('Frame', 'RetSimFrame', UIParent)
  frame:SetSize(W, H)
  frame:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
  frame:SetFrameStrata('DIALOG')
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag('LeftButton')
  frame:SetScript('OnDragStart', function(self) self:StartMoving() end)
  frame:SetScript('OnDragStop', function(self) self:StopMovingOrSizing() end)
  fill(frame, 0.06, 0.07, 0.10, 0.95)
  if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = 'RetSimFrame' end     -- Escape closes it

  local title = text(frame, 'GameFontNormalLarge')
  title:SetPoint('TOPLEFT', frame, 'TOPLEFT', 14, -12)
  title:SetText('|cfff58cbaForever Ret Sim|r')
  local ver = text(frame, 'GameFontDisableSmall')
  ver:SetPoint('LEFT', title, 'RIGHT', 8, -1)
  ver:SetText('v' .. tostring(RS.VERSION))
  local close = CreateFrame('Button', nil, frame, 'UIPanelCloseButton')
  close:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -2, -2)

  ui.dps = text(frame, 'GameFontNormalHuge')
  ui.dps:SetPoint('TOPLEFT', frame, 'TOPLEFT', 14, -44)
  ui.sub = text(frame, 'GameFontHighlightSmall')
  ui.sub:SetPoint('TOPLEFT', ui.dps, 'BOTTOMLEFT', 0, -4)
  ui.sub:SetWidth(W - 28)
  ui.sub:SetWordWrap(true)

  ui.rows = {}
  for i = 1, ROWS do
    local y = -100 - (i - 1) * 16
    local name, val = text(frame), text(frame, nil, 'RIGHT')
    name:SetPoint('TOPLEFT', frame, 'TOPLEFT', 14, y)
    name:SetWidth(210)
    val:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -14, y)
    val:SetWidth(160)
    ui.rows[i] = { name = name, val = val }
  end

  ui.notes = text(frame, 'GameFontDisableSmall')
  ui.notes:SetPoint('TOPLEFT', frame, 'TOPLEFT', 14, -100 - ROWS * 16 - 8)
  ui.notes:SetWidth(W - 28)
  ui.notes:SetWordWrap(true)
  ui.notes:SetJustifyV('TOP')

  ui.sim = button(frame, 'Sim', 70, function()
    if RS.jobRunning() then RS.cancelJob(); return end
    local ok, why = RS.simCharacter()
    if not ok then RS.refresh(why) end
  end)
  ui.sim:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 12, 12)
  ui.mode = button(frame, 'Rotation', 150, function()
    local order, cur, at = { 'auto' }, RS.db.options.mode, 1
    for i = 1, #RS.MODE_ORDER do order[#order + 1] = RS.MODE_ORDER[i] end
    for i = 1, #order do if order[i] == cur then at = i end end
    RS.db.options.mode = order[at % #order + 1]
    RS.refresh()
  end)
  ui.mode:SetPoint('LEFT', ui.sim, 'RIGHT', 6, 0)
  ui.buffs = button(frame, 'Buffs', 90, function() RS.setBuffs(not RS.buffsOn()); RS.refresh() end)
  ui.buffs:SetPoint('LEFT', ui.mode, 'RIGHT', 6, 0)
  ui.export = button(frame, 'Export', 64, function() SlashCmdList['RETSIM']('export') end)
  ui.export:SetPoint('BOTTOMLEFT', ui.sim, 'TOPLEFT', 0, 6)
  ui.settings = button(frame, 'Settings code', 104, function() SlashCmdList['RETSIM']('settings') end)
  ui.settings:SetPoint('LEFT', ui.export, 'RIGHT', 6, 0)
  ui.import = button(frame, 'Import', 64, function() RS.showImport() end)
  ui.import:SetPoint('LEFT', ui.settings, 'RIGHT', 6, 0)
  ui.dump = button(frame, 'Dump', 56, function() RS.showDump(RS.dumpText()) end)
  ui.dump:SetPoint('LEFT', ui.buffs, 'RIGHT', 6, 0)
  ui.list = button(frame, 'Gear list', 76, function() RS.toggleGearList() end)
  ui.list:SetPoint('LEFT', ui.import, 'RIGHT', 6, 0)

  -- progress while a sim runs
  frame:SetScript('OnUpdate', function()
    if not RS.jobRunning() then return end
    local done, total = RS.jobProgress()
    ui.dps:SetText(string.format('|cffaaaaaa%d / %d|r', done or 0, total or 0))
    ui.sim:SetText('Stop')
  end)
  frame:Hide()
end

local function fmt(x, d) return string.format('%.' .. (d or 0) .. 'f', x) end

-- Draws the window from the last result. `message`: a sentence to show instead (why a sim could not start).
function RS.refresh(message)
  if not frame then return end
  ui.sim:SetText(RS.jobRunning() and 'Stop' or 'Sim')
  ui.mode:SetText(RS.modeName(RS.db.options.mode))
  ui.buffs:SetText('Buffs: ' .. (RS.buffsOn() and 'on' or 'off'))
  local r = RS.last
  for i = 1, ROWS do ui.rows[i].name:SetText(''); ui.rows[i].val:SetText('') end
  local notes = {}
  if message then notes[#notes + 1] = '|cffff6060' .. message .. '|r' end
  if not r then
    ui.dps:SetText('|cffaaaaaa-|r')
    ui.sub:SetText('Press Sim to read your character and play ' .. RS.db.options.fights .. ' fights.')
  else
    ui.dps:SetText(fmt(r.mean, 1) .. ' DPS')
    ui.sub:SetText(string.format('+/- %s  |  %d fights, lowest %s, highest %s  |  %s%s', fmt(r.margin, 1), r.fights, fmt(r.lo), fmt(r.hi), r.mode.name,
      r.mode.auto and ' (picked)' or ''))
    for i = 1, math.min(ROWS, #r.rows) do
      local x = r.rows[i]
      ui.rows[i].name:SetText(x.name)
      ui.rows[i].val:SetText(string.format('%s  |cffaaaaaa%s%%|r', fmt(x.dps, 1), fmt(r.mean > 0 and x.dps / r.mean * 100 or 0, 1)))
    end
    local t = r.totals
    if t then notes[#notes + 1] = string.format('Simmed with %s Strength, %s Attack Power, %s%% crit, %s%% hit, %s Holy spell power.', fmt(t.str), fmt(t.ap), fmt(t.crit, 1), fmt(t.hit, 1), fmt(t.spHoly)) end
  end
  local cons = RS.consumablesNow()
  if #cons > 0 then notes[#notes + 1] = 'Consumables from your settings: ' .. table.concat(cons, ', ') .. '.' end
  if RS.char then for i = 1, #RS.char.notes do notes[#notes + 1] = RS.char.notes[i] end end
  if RS.valueNotes then for i = 1, #RS.valueNotes do notes[#notes + 1] = RS.valueNotes[i] end end
  ui.notes:SetText(table.concat(notes, '\n'))
end

RS.onJobEnd = function(result, err)
  if result and result.mean then RS.print(string.format('%.1f DPS (+/- %.1f, %d fights, %s).', result.mean, result.margin, result.fights, result.mode.name)) end
  RS.refresh(err)
end

function RS.showWindow() if not frame then build() end; frame:Show(); RS.refresh() end
function RS.toggleWindow()
  if not frame then build() end
  if frame:IsShown() then frame:Hide() else frame:Show(); RS.refresh() end
end

-- A window with the dump as text: Ctrl+A, Ctrl+C copies it.
function RS.showDump(body, heading, onImport)
  if not dumpFrame then
    dumpFrame = CreateFrame('Frame', 'RetSimDumpFrame', UIParent)
    dumpFrame:SetSize(520, 420)
    dumpFrame:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
    dumpFrame:SetFrameStrata('FULLSCREEN_DIALOG')
    dumpFrame:EnableMouse(true)
    fill(dumpFrame, 0.04, 0.05, 0.08, 0.97)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = 'RetSimDumpFrame' end
    local head = text(dumpFrame, 'GameFontNormal')
    head:SetPoint('TOPLEFT', dumpFrame, 'TOPLEFT', 12, -10)
    dumpFrame.head = head
    local close = CreateFrame('Button', nil, dumpFrame, 'UIPanelCloseButton')
    close:SetPoint('TOPRIGHT', dumpFrame, 'TOPRIGHT', -2, -2)
    local scroll = CreateFrame('ScrollFrame', 'RetSimDumpScroll', dumpFrame, 'UIPanelScrollFrameTemplate')
    scroll:SetPoint('TOPLEFT', dumpFrame, 'TOPLEFT', 12, -34)
    scroll:SetPoint('BOTTOMRIGHT', dumpFrame, 'BOTTOMRIGHT', -30, 12)
    local box = CreateFrame('EditBox', nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    box:SetWidth(470)
    box:SetScript('OnEscapePressed', function(self) self:ClearFocus(); dumpFrame:Hide() end)
    scroll:SetScrollChild(box)
    dumpFrame.box = box
    dumpFrame.go = button(dumpFrame, 'Import', 80, function() if dumpFrame.onImport then dumpFrame.onImport(dumpFrame.box:GetText()) end end)
    dumpFrame.go:SetPoint('TOPRIGHT', dumpFrame, 'TOPRIGHT', -30, -6)
  end
  dumpFrame.onImport = onImport
  dumpFrame.go:SetShown(onImport ~= nil)
  dumpFrame.head:SetText(heading or 'Click in the text, press Ctrl+A, then Ctrl+C to copy it.')
  dumpFrame.box:SetText(body or '')
  dumpFrame:Show()
  dumpFrame.box:SetFocus()
  if not onImport then dumpFrame.box:HighlightText() end
end

-- The window to paste a settings code into: Ctrl+V, then Import.
function RS.showImport()
  RS.showDump('', 'Paste a settings code or a gear list code from the website here (Ctrl+V), then press Import.', function(text)
    local ok, msg = RS.importCode(text)
    RS.print(msg)
    if ok then dumpFrame:Hide(); if tostring(text):find('RSG1:', 1, true) then RS.showGearList() else RS.showWindow() end else dumpFrame.head:SetText('|cffff6060' .. msg .. '|r') end
  end)
end

RS.onLoaded = function()
  RS.print('loaded. Type /rsim to open the window, /rsim help for the commands.')
end
