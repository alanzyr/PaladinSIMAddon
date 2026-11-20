-- The minimap button. Click: open the window and sim your character. Right-click: open or close the window only.
-- Drag: move the button around the minimap. After Xn's Warlock Sim (Minimap.lua).
-- The button is the addon's own frame, a child of the minimap; nothing of the game's is changed.
local ADDON, RS = ...
if RS.notPaladin then return end

local ICON = 'Interface\\Icons\\Spell_Holy_AuraOfLight'   -- Retribution Aura: the Retribution tree's own icon
local button

local function minimap() return Minimap or (MinimapCluster and MinimapCluster.Minimap) end

local function place()
  local mm = minimap()
  if not (button and mm) then return end
  local a = math.rad(tonumber(RS.db.options.minimapAngle) or 215)
  local r = (mm.GetWidth and mm:GetWidth() or 140) / 2 + 10
  button:ClearAllPoints()
  button:SetPoint('CENTER', mm, 'CENTER', math.cos(a) * r, math.sin(a) * r)
end

-- while dragged: the angle from the minimap's centre to the mouse
local function follow()
  local mm = minimap()
  local mx, my = mm:GetCenter()
  local cx, cy = GetCursorPosition()
  local scale = mm:GetEffectiveScale()
  if not (mx and cx and scale and scale > 0) then return end
  local atan2 = math.atan2 or math.atan                  -- the game's Lua 5.1 has atan2; the test runner's 5.3 takes two arguments in atan
  RS.db.options.minimapAngle = math.floor(math.deg(atan2(cy / scale - my, cx / scale - mx)) + 0.5) % 360
  place()
end

-- Open the window and sim the character; while a sim runs, just show the window.
function RS.simFromButton()
  if RS.showWindow then RS.showWindow() end
  if RS.jobRunning() then return end
  local ok, why = RS.simCharacter()
  if not ok then RS.print(why); if RS.refresh then RS.refresh(why) end end
end

local function create()
  local mm = minimap()
  if button or not mm then return end
  button = CreateFrame('Button', 'RetSimMinimapButton', mm)
  button:SetSize(31, 31)
  button:SetFrameStrata('MEDIUM')
  button:SetFrameLevel((mm.GetFrameLevel and mm:GetFrameLevel() or 0) + 8)
  button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
  button:RegisterForDrag('LeftButton')
  local bg = button:CreateTexture(nil, 'BACKGROUND')
  bg:SetTexture('Interface\\Minimap\\UI-Minimap-Background'); bg:SetSize(20, 20); bg:SetPoint('TOPLEFT', button, 'TOPLEFT', 7, -5)
  local icon = button:CreateTexture(nil, 'ARTWORK')
  icon:SetTexture(ICON); icon:SetSize(17, 17); icon:SetPoint('TOPLEFT', button, 'TOPLEFT', 7, -6); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local border = button:CreateTexture(nil, 'OVERLAY')
  border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder'); border:SetSize(53, 53); border:SetPoint('TOPLEFT', button, 'TOPLEFT', 0, 0)
  button:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
  button:SetScript('OnClick', function(_, mouse)
    if mouse == 'RightButton' then if RS.toggleWindow then RS.toggleWindow() end else RS.simFromButton() end
  end)
  button:SetScript('OnDragStart', function(self) self:SetScript('OnUpdate', follow) end)
  button:SetScript('OnDragStop', function(self) self:SetScript('OnUpdate', nil) end)
  button:SetScript('OnEnter', function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
    GameTooltip:SetText('Forever Ret Sim', 0.96, 0.55, 0.73)
    GameTooltip:AddLine('Click: sim my character', 1, 1, 1)
    GameTooltip:AddLine('Right-click: open or close the window', 1, 1, 1)
    GameTooltip:AddLine('Drag: move this button', 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  button:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
  place()
end

function RS.updateMinimapButton()
  if not RS.db then return end
  if RS.db.options.minimapButton ~= false then
    create()
    if button then place(); button:Show() end
  elseif button then button:Hide() end
end

-- made at login: the minimap is there by then, and the saved settings were read when the addon loaded
local login = CreateFrame('Frame')
login:RegisterEvent('PLAYER_LOGIN')
login:SetScript('OnEvent', function(self) self:UnregisterAllEvents(); RS.updateMinimapButton() end)
