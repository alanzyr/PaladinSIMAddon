-- Loaded first. The addon is a Paladin's: on any other class nothing else of it loads (every other file stops at its
-- first line), and what is left is a line in chat at login and the same line from /rsim.
-- When the class cannot be read, the addon loads as usual (reading the character still refuses a non-Paladin).
local ADDON, RS = ...
local ok, _, class = pcall(UnitClass, 'player')
if not ok or type(class) ~= 'string' or (issecretvalue and issecretvalue(class)) or class == 'PALADIN' then return end

RS.notPaladin = true
local MSG = '|cfff58cbaForever Ret Sim|r cannot be used on other classes. It only loads on a Paladin.'
local function say() if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(MSG) end end
SLASH_RETSIM1, SLASH_RETSIM2 = '/rsim', '/retsim'
SlashCmdList['RETSIM'] = say
local login = CreateFrame('Frame')
login:RegisterEvent('PLAYER_LOGIN')
login:SetScript('OnEvent', function(self) self:UnregisterAllEvents(); say() end)
