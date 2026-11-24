local J=VoidMarkJourney; local L=J.Link
local function eq(a,b,m) if a~=b then error((m or 'mismatch')..': expected '..tostring(b)..', got '..tostring(a),2) end end
SENT={}
C_ChatInfo={RegisterAddonMessagePrefix=function() return true end,
  SendAddonMessage=function(prefix,body,ch,target) SENT[#SENT+1]={prefix=prefix,body=body,ch=ch,target=target}; return true end}
local function msg(body,from) Emit('CHAT_MSG_ADDON','VMJrn1',body,'WHISPER',from) end
local function row(name,level,savedAt) return table.concat({'C',name,'CAMWOW US2',level,100,1000,500,'1','HUNTER',savedAt},'\t') end

VoidMarkJourneyDB.characters['Voidmark Bank - CAMWOW US2']=nil -- earlier tests put Bank on this account
-- Name forms Forever whispers use.
eq(L.Norm('Voidmark Bank'),'voidmark bank'); eq(L.Norm('Voidmark-Bank'),'voidmark bank')
eq(L.Norm('Voidmark Bank-CAMWOW US2'),'voidmark bank'); eq(L.Norm('Voidmark-Bank-CAMWOW US2'),'voidmark bank')

-- Nothing linked: no probes, nothing trusted.
VoidMarkMarketDB=nil; L.nextProbe=0; L.Tick(); eq(#SENT,0,'no probe without a partner')
msg(row('Random Guy',30,CLOCK),'Random Guy'); assert(not next(VoidMarkJourneyDB.remote or {}),'stranger ignored')

-- Market's sync partner is linked automatically and probed.
VoidMarkMarketDB={syncPeer='voidmark bank-camwow us2',syncAddress='Voidmark Bank-CAMWOW US2'}
L.nextProbe=0; L.Tick(); eq(#SENT,1,"probe"); eq(SENT[1].body,'H'); eq(SENT[1].ch,'WHISPER')
assert(SENT[1].target=='Voidmark Bank' or SENT[1].target=='Voidmark-Bank',SENT[1].target)
assert(L.HideOffline("No player named 'Voidmark Bank' is currently playing."),'own probe error hidden')
assert(not L.HideOffline("No player named 'Someone Else' is currently playing."),'other errors kept')

-- The bank's account sends its characters; they show as the other account.
msg(row('Voidmark Bank',1,CLOCK-50),'Voidmark-Bank')
msg(row('Voidmark Kitty',1,CLOCK-3600),'Voidmark-Bank')
msg(row('Voidmark Herbstorage',1,CLOCK-7200),'Voidmark-Bank')
local r=VoidMarkJourneyDB.remote
assert(r['Voidmark Kitty - CAMWOW US2'] and r['Voidmark Kitty - CAMWOW US2'].remote,'kitty stored')
eq(r['Voidmark Kitty - CAMWOW US2'].maxXP,1000); eq(r['Voidmark Kitty - CAMWOW US2'].resting,true)
assert(L.Connected(),'connected after an answer')
local text=table.concat(J.ListLines('alts'),'\n')
assert(text:find('Voidmark Soulreaver',1,true) and text:find('Voidmark Kitty  |cffb88cffLv 1|r',1,true),text)
assert(text:find('(other account)',1,true),'marked as other account')
assert(not text:find('have one character from each account',1,true),'hint gone once linked')

-- An older copy never replaces a newer one; this account's own character is never overwritten.
msg(row('Voidmark Kitty',1,CLOCK-99999),'Voidmark Bank'); eq(r['Voidmark Kitty - CAMWOW US2'].savedAt,CLOCK-3600)
msg(row('Voidmark Soulreaver',5,CLOCK),'Voidmark Bank'); assert(not r['Voidmark Soulreaver - CAMWOW US2'],'local character not taken')
-- Malformed lines are ignored.
msg('C\tX','Voidmark Bank'); msg(table.concat({'C','Voidmark Kitty','CAMWOW US2','abc',1,1,1,'0','',CLOCK},'\t'),'Voidmark Bank')
eq(r['Voidmark Kitty - CAMWOW US2'].level,1)

-- Characters listed by the partner are trusted too (Kitty online instead of Bank).
msg(row('Voidmark Kitty',2,CLOCK),'Voidmark-Kitty'); eq(r['Voidmark Kitty - CAMWOW US2'].level,2,'kitty trusted')

-- A hello gets every character on this account back, and one hello in return.
SENT={}; L.queue={}; msg('H','Voidmark-Bank')
for _=1,5 do L.Tick() end
local gotMine,gotHello=false,false
for _,m in ipairs(SENT) do
  if m.body:find('^C\tVoidmark Soulreaver\t') then gotMine=true; eq(m.target,'Voidmark-Bank') end
  if m.body=='H' then gotHello=true end
end
assert(gotMine,'own characters sent'); assert(not gotHello,'no hello back: already heard from them')

-- First contact: their hello is answered with ours too, so both accounts fill in.
SENT={}; L.queue={}; L.contact=nil; L.rowsAt=nil; L.askedAt=nil; msg('H','Voidmark-Bank'); for _=1,5 do L.Tick() end
local hello=false; for _,m in ipairs(SENT) do if m.body=='H' then hello=true end end; assert(hello,'hello back on first contact')
SENT={}; L.queue={}; msg('H','Voidmark-Bank'); for _=1,5 do L.Tick() end
for _,m in ipairs(SENT) do assert(m.body~='H','no hello loop') end
-- /journey link shows and removes the link.
SlashCmdList.VOIDMARKJOURNEY('link'); assert(printed[#printed]:find('Voidmark Bank',1,true),printed[#printed])
SlashCmdList.VOIDMARKJOURNEY('link Somebody'); assert(printed[#printed]:find('First Surname',1,true))
SlashCmdList.VOIDMARKJOURNEY('link Voidmark Alt'); assert(VoidMarkJourneyDB.link.manual['voidmark alt'])
SlashCmdList.VOIDMARKJOURNEY('link off'); assert(not next(VoidMarkJourneyDB.remote) and not next(VoidMarkJourneyDB.link.manual))
VoidMarkMarketDB=nil
print('link tests passed')
