-- Minimal WoW client mock for VoidMark Journey tests.
NOW=1000; CLOCK=1800000000
SECRET={secret=true}
function issecretvalue(v) return v==SECRET end
function GetTime() return NOW end
function time() return CLOCK end
date=os.date
unpack=unpack or table.unpack
P={level=20,xp=1000,max=10000,rested=0,resting=false,name={'Voidmark','Soulreaver'},zone='Stranglethorn Vale'}
function UnitName(u) if u=='player' then return P.name[1],P.name[2] end end
function GetRealmName() return 'CAMWOW US2' end
function UnitClass() return 'Priest','PRIEST' end
function UnitLevel() return P.level end
function UnitXP() return P.xp end
function UnitXPMax() return P.max end
function GetXPExhaustion() if P.rested>0 then return P.rested end end
function IsResting() return P.resting end
function GetMaxPlayerLevel() return 60 end
function GetZoneText() return P.zone end
AURA=nil -- {applications=,expirationTime=}
C_UnitAuras={GetPlayerAuraBySpellID=function(id) if id==429959 then return AURA end end}
BAGCD={0,0}; BAGCOUNT=1
C_Container={GetItemCooldown=function(id) return BAGCD[1],BAGCD[2],1 end}
function GetItemCount() return BAGCOUNT end
printed={}; alerts=0; sounds=0
DEFAULT_CHAT_FRAME={AddMessage=function(_,m) printed[#printed+1]=m end}
RaidWarningFrame={}; function RaidNotice_AddMessage() alerts=alerts+1 end
function PlaySound() sounds=sounds+1 end
SOUNDKIT={READY_CHECK=8960}
ChatTypeInfo={RAID_WARNING={r=1,g=1,b=1}}
BackdropTemplateMixin={}
local frames={}
local function obj()
  local o={_shown=true,_events={},_scripts={},_text='',_value=0}
  return setmetatable(o,{__index=function(t,k)
    if k=='SetText' then return function(s,v) s._text=v end end
    if k=='GetText' then return function(s) return s._text end end
    if k=='SetValue' then return function(s,v) s._value=v end end
    if k=='GetValue' then return function(s) return s._value end end
    if k=='SetScript' then return function(s,n,f) s._scripts[n]=f end end
    if k=='GetScript' then return function(s,n) return s._scripts[n] end end
    if k=='RegisterEvent' then return function(s,e) s._events[e]=true end end
    if k=='Show' then return function(s) s._shown=true; if s._scripts.OnShow then s._scripts.OnShow(s) end end end
    if k=='Hide' then return function(s) s._shown=false end end
    if k=='IsShown' then return function(s) return s._shown end end
    if k=='CreateFontString' or k=='CreateTexture' then return function() return obj() end end
    if k=='GetPoint' then return function() return 'TOP',nil,'TOP',0,-140 end end
    if k=='SetHeight' then return function(s,h) s._h=h end end
    return function() end
  end})
end
UIParent=obj()
function CreateFrame(kind,name) local f=obj(); f._kind=kind; frames[#frames+1]=f; if name then _G[name]=f end; return f end
TICKERS={}
C_Timer={NewTicker=function(_,fn) TICKERS[#TICKERS+1]=fn; return {Cancel=function() end} end, After=function() end}
SlashCmdList={}
function Emit(e,...) for _,f in ipairs(frames) do if f._events[e] and f._scripts.OnEvent then f._scripts.OnEvent(f,e,...) end end end
function Advance(sec) NOW=NOW+sec; CLOCK=CLOCK+sec; for _,t in ipairs(TICKERS) do t() end end
