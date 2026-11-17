-- VoidMark Journey help: FAQ and every command, opened from the ? button or /journey help.
-- Help window renderer. The same code ships in every VoidMark addon (one copy
-- per addon, own frame name), so each addon works on its own.
-- HELP = { title=..., intro=..., sections={ {title=..., commands={{'/cmd','what it does'},...}}
--                                            or {title=..., faq={{'Question?','Answer.'},...}} } }
local function HelpText(help,filter)
  filter=type(filter)=='string' and filter:lower():match('^%s*(.-)%s*$') or ''
  local function hit(...)
    if filter=='' then return true end
    for i=1,select('#',...) do
      local s=select(i,...)
      if type(s)=='string' and s:lower():find(filter,1,true) then return true end
    end
    return false
  end
  local out={}
  if filter=='' and help.intro then out[#out+1]=help.intro;out[#out+1]='' end
  local found=0
  for _,section in ipairs(help.sections or {}) do
    local lines={}
    for _,c in ipairs(section.commands or {}) do
      if hit(c[1],c[2],section.title) then lines[#lines+1]='|cffffd200'..c[1]..'|r  '..c[2];found=found+1 end
    end
    for _,q in ipairs(section.faq or {}) do
      if hit(q[1],q[2],section.title) then lines[#lines+1]='|cffffd200Q: '..q[1]..'|r';lines[#lines+1]='A: '..q[2];lines[#lines+1]='';found=found+1 end
    end
    if #lines>0 then
      out[#out+1]='|cffb86cff'..section.title:upper()..'|r'
      for _,l in ipairs(lines) do out[#out+1]=l end
      if lines[#lines]~='' then out[#out+1]='' end
    end
  end
  if found==0 then out[#out+1]='Nothing matches "'..filter..'".' end
  return table.concat(out,'\n'),found
end

local function HelpWindow(frameName,help)
  local w={help=help}
  local f,text,search
  local function render()
    if not f then return end
    local s=HelpText(help,search and search:GetText() or '')
    w.current=s
    text:SetText(s)
    local _,breaks=s:gsub('\n','\n')
    text:SetHeight(math.max(400,(breaks+1)*15+40))
  end
  local function build()
    f=CreateFrame('Frame',frameName,UIParent,BackdropTemplateMixin and 'BackdropTemplate' or nil)
    f:SetSize(580,620);f:SetPoint('CENTER');f:SetFrameStrata('DIALOG')
    if f.SetToplevel then f:SetToplevel(true) end
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    f:EnableMouse(true);f:SetMovable(true);f:RegisterForDrag('LeftButton')
    f:SetScript('OnDragStart',function() f:StartMoving() end)
    f:SetScript('OnDragStop',function() f:StopMovingOrSizing() end)
    if f.SetBackdrop then
      f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
      f:SetBackdropColor(.035,.025,.06,.97);f:SetBackdropBorderColor(.48,.25,.72,1)
    end
    local title=f:CreateFontString(nil,'OVERLAY','GameFontNormalLarge')
    title:SetPoint('TOPLEFT',16,-14);title:SetText(help.title or 'Help')
    local close=CreateFrame('Button',nil,f,'UIPanelCloseButton')
    close:SetPoint('TOPRIGHT',-2,-2);close:SetScript('OnClick',function() f:Hide() end)
    local label=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    label:SetPoint('TOPLEFT',18,-48);label:SetText('Search:')
    search=CreateFrame('EditBox',frameName..'Search',f,'InputBoxTemplate')
    search:SetSize(220,20);search:SetPoint('TOPLEFT',70,-43)
    if search.SetAutoFocus then search:SetAutoFocus(false) end
    search:SetScript('OnTextChanged',function() render() end)
    search:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
    search:SetScript('OnEnterPressed',function(self) self:ClearFocus() end)
    local hint=f:CreateFontString(nil,'OVERLAY','GameFontDisableSmall')
    hint:SetPoint('LEFT',search,'RIGHT',12,0);hint:SetText('Click the text, Ctrl+A, Ctrl+C to copy.')
    local scroll=CreateFrame('ScrollFrame',frameName..'Scroll',f,'UIPanelScrollFrameTemplate')
    scroll:SetPoint('TOPLEFT',16,-72);scroll:SetPoint('BOTTOMRIGHT',-34,16)
    text=CreateFrame('EditBox',nil,scroll)
    if text.SetMultiLine then text:SetMultiLine(true) end
    if text.SetFontObject then text:SetFontObject(GameFontHighlight) end
    if text.SetAutoFocus then text:SetAutoFocus(false) end
    text:SetWidth(520)
    text:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
    -- Read only: typing puts the help text back.
    text:SetScript('OnTextChanged',function(self,user) if user and w.current then self:SetText(w.current) end end)
    scroll:SetScrollChild(text)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames+1]=frameName end
    f:Hide()
  end
  function w.Open(filter)
    if not f then build() end
    if filter~=nil and search then search:SetText(filter) end
    render();f:Show()
    return f
  end
  function w.Toggle()
    if f and f:IsShown() then f:Hide() else w.Open() end
  end
  function w.Text(filter) return HelpText(help,filter) end
  function w.Frame() return f end
  return w
end

local HELP={title='VoidMark Journey: Help & commands',
 intro='Open this window with the ? button on the Journey window, or type /journey help. Type in Search to filter.',
 sections={
 {title='Commands',commands={
  {'/journey  (or /vmj)','Show or hide the Journey window.'},
  {'/journey help [word]','This window; a word searches it.'},
  {'/journey alts','List every character with level and rested XP.'},
  {'/journey dings','Each level with date, zone, time played that level and deaths.'},
  {'/journey lock','Lock or unlock the window position.'},
  {'/journey reset','Restart the XP/hour clock.'},
  {'/journey bagalert','Turn the Cozy Sleeping Bag 3/3 alert on or off.'},
  {'/journey food','Show or hide the XP food icon (same as the Food button).'},
  {'/journey foodalert','Turn the XP food alerts on or off.'}}},
 {title='Every VoidMark addon',commands={
  {'Whisper "inv" or "invite"','From one of your Voidmark characters: you get a group invite.'}}},
 {title='FAQ',faq={
  {'How is XP/hour worked out?','From the XP you earned in the last 10 minutes. It handles level-ups. /journey reset starts it again.'},
  {'Why does XP/hour say "earn some XP to start the clock"?','It needs some XP first. Kill something or turn in a quest.'},
  {'What does the blue part of the bar mean?','Your rested XP, shown on top of the XP bar.'},
  {'How does the Cozy Sleeping Bag timer work?','It shows Well-Rested stacks (up to 3) and time to the next one, plays a sound and a raid warning at 3/3, and shows the bag cooldown when you are not using it.'},
  {'How does the XP food icon work?','Click Food on the Journey window. Drag your XP food onto the icon, then left-click the icon to eat it. It stays hidden while your food buff is up and pops up with 1 minute left or when it runs out (warning you each time). Shift+drag moves it, Shift+right-click clears it.'},
  {'The food icon says EAT but I just ate?','The first time you eat a new food, Journey learns which buff it gives. Eat it from the icon (or your bags) once and the countdown starts.'},
  {'Does Journey change my quests or guides?','No. It sits next to Questie and RestedXP and only shows numbers they do not.'},
  {'Why are alts\' rested XP higher than when I logged out?','Rested XP builds while you are offline, so Journey adds it for you (more in a rest area).'},
  {'At max level?','Journey shows "Max level - nothing left to track here."'}}}}}
_G.VoidMarkJourneyHelp=HelpWindow('VoidMarkJourneyHelpWindow',HELP)
