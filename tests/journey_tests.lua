local J=VoidMarkJourney
local function eq(a,b,m) if a~=b then error((m or 'mismatch')..': expected '..tostring(b)..', got '..tostring(a),2) end end
Emit('ADDON_LOADED','VoidMarkJourney'); Emit('PLAYER_LOGIN')
local key='Voidmark Soulreaver - CAMWOW US2'
local c=VoidMarkJourneyDB.characters[key]
assert(c,'character saved under full Forever name'); eq(c.name,'Voidmark Soulreaver','full name')
assert(VoidMarkJourneyFrame and VoidMarkJourneyFrame:IsShown(),'window not shown')
assert(VoidMarkJourneyFrame.Pace:GetText():find('start the clock'),'empty pace text')

-- XP/hour over the last 10 minutes; crossing a level counts correctly.
for i=1,10 do Advance(60); P.xp=P.xp+500; Emit('PLAYER_XP_UPDATE','player') end
local rate=J.XPPerHour()
eq(math.floor(rate+0.5),30000,'XP/hr after 10 min of 500/min')
P.xp=9800; Emit('PLAYER_XP_UPDATE','player')            -- +3800 jump
Advance(1); P.level=21; P.max=12000; P.xp=300; Emit('PLAYER_XP_UPDATE','player')   -- 200 to cap + 300
local text=VoidMarkJourneyFrame.Pace:GetText()
assert(text:find('XP/hr') and text:find('level in'),'pace line missing: '..text)

-- Level-up logs played time, zone and deaths; counters reset.
Emit('PLAYER_DEAD'); Emit('PLAYER_DEAD')
Emit('PLAYER_LEVEL_UP',21)
eq(c.dings[1].level,21,'ding level'); eq(c.dings[1].deaths,2,'ding deaths'); eq(c.dings[1].zone,'Stranglethorn Vale','ding zone')
assert(c.dings[1].played>=600,'played time not counted: '..tostring(c.dings[1].played))
eq(c.levelDeaths,0,'deaths not reset'); assert(c.levelPlayed<5,'played not reset')
assert(printed[#printed]:find('Level 21'),'ding message')

-- Rested shown with bubbles (1 bubble = 5% of a level).
P.rested=1800; Emit('UPDATE_EXHAUSTION'); J.Refresh()
assert(VoidMarkJourneyFrame.Rested:GetText():find('3.0 bubbles'),VoidMarkJourneyFrame.Rested:GetText())

-- Sleeping bag: placed -> countdown -> stacks -> one alert at 3/3 -> cooldown.
BAGCD={NOW,3600}
assert(J.BagLine():find('Well%-Rested 0/3 · next in 1:00'),J.BagLine())
Advance(20); assert(J.BagLine():find('next in 0:40'),J.BagLine())
Advance(40); AURA={applications=1,expirationTime=NOW+3600}; Emit('UNIT_AURA','player')
assert(J.BagLine():find('1/3 · next in 1:00'),J.BagLine())
Advance(60); AURA.applications=2; Emit('UNIT_AURA','player')
Advance(60); AURA.applications=3; Emit('UNIT_AURA','player')
eq(alerts,1,'3/3 alert'); eq(sounds,1,'3/3 sound')
Emit('UNIT_AURA','player'); eq(alerts,1,'alert repeated')
assert(J.BagLine():find('3/3 %(%+3%% XP%)'),J.BagLine())
AURA=nil; Emit('UNIT_AURA','player'); Advance(600)
assert(J.BagLine():find('Sleeping bag ready in'),J.BagLine())
BAGCD={0,0}; assert(J.BagLine():find('Sleeping bag ready'),J.BagLine())
BAGCOUNT=0; eq(J.BagLine(),nil,'no bag line without the bag')
-- Secret aura stacks don't crash and count as present.
AURA={applications=SECRET}; Emit('UNIT_AURA','player'); assert(J.BagLine(),'secret stacks broke bag line'); AURA=nil; Emit('UNIT_AURA','player')

-- Alts: rested keeps building offline (full rate resting, quarter rate outside).
local alt={name='Voidmark Bank',level=30,maxXP=20000,rested=0,resting=true,savedAt=CLOCK-8*3600}
eq(math.floor(J.EstimateRested(alt,CLOCK)+0.5),1000,'8h resting = 5% of level')
alt.resting=false; eq(math.floor(J.EstimateRested(alt,CLOCK)+0.5),250,'outside rest area = quarter rate')
alt.resting=true; alt.savedAt=CLOCK-400*86400; eq(J.EstimateRested(alt,CLOCK),30000,'capped at 150% of a level')
VoidMarkJourneyDB.characters['Voidmark Bank - CAMWOW US2']=alt
SlashCmdList.VOIDMARKJOURNEY('alts')
local body=VoidMarkJourneyList.Body:GetText()
assert(body:find('Voidmark Bank') and body:find('full rested') and body:find('Voidmark Soulreaver'),body)
SlashCmdList.VOIDMARKJOURNEY('dings')
local hr=J.HistoryRows(); assert(hr[1] and hr[1][1]:find('Lv 21'),'dings list')
eq(#hr[1],5,'history columns'); eq(hr[1][3],'Stranglethorn Vale','history zone column')
assert(not hr[1][4]:find('played'),'played column is just the time')

-- Secret XP values never crash the window.
P.xp=SECRET; Emit('PLAYER_XP_UPDATE','player'); J.Refresh(); P.xp=500
-- Max level shows a quiet message.
P.level=60; J.Refresh(); assert(VoidMarkJourneyFrame.Pace:GetText():find('Max level'),'max level text'); P.level=21
-- Toggle and settings persist.
SlashCmdList.VOIDMARKJOURNEY(''); eq(VoidMarkJourneyDB.settings.shown,false,'hide not saved')
SlashCmdList.VOIDMARKJOURNEY(''); eq(VoidMarkJourneyDB.settings.shown,true,'show not saved')
SlashCmdList.VOIDMARKJOURNEY('lock'); eq(VoidMarkJourneyDB.settings.locked,true,'lock')
-- Flicker: hidden/blocked aura reads must not reset and re-fire the 3/3 alert.
BAGCOUNT=1; local before=alerts
AURA={applications=3}; Emit('UNIT_AURA','player')
local real=C_UnitAuras.GetPlayerAuraBySpellID
for i=1,5 do
  C_UnitAuras.GetPlayerAuraBySpellID=function() error('Auras cannot be accessed when secret') end; Emit('UNIT_AURA','player')
  C_UnitAuras.GetPlayerAuraBySpellID=function() return SECRET end; Emit('UNIT_AURA','player')
  C_UnitAuras.GetPlayerAuraBySpellID=real; Emit('UNIT_AURA','player')
end
eq(alerts-before<=1,true,'alert repeated on hidden reads')
local after=alerts
-- Even a real drop and re-gain within 30 minutes doesn't alert again.
AURA=nil; Emit('UNIT_AURA','player'); Advance(60); AURA={applications=3}; Emit('UNIT_AURA','player')
eq(alerts,after,'re-alerted within 30 minutes')
-- An hour later, the buff "reappearing" at 3/3 (false missing read mid-fight) must NOT alert.
AURA=nil; Emit('UNIT_AURA','player'); Advance(3600); AURA={applications=3}; Emit('UNIT_AURA','player')
eq(alerts,after,'alerted on a buff that reappeared at 3/3')
-- A real new bag session (watched 1 -> 2 -> 3) alerts again.
AURA=nil; Emit('UNIT_AURA','player'); Advance(600)
for n=1,3 do AURA={applications=n}; Emit('UNIT_AURA','player'); Advance(60) end
eq(alerts,after+1,'new bag session did not alert'); AURA=nil; Emit('UNIT_AURA','player')
print('PASS: no repeat bag alerts on hidden reads, XP/hr + level crossing, dings/deaths/played, rested bubbles, sleeping bag countdown + single alert, alts offline rested, secrets, slash commands')

-- 0.1.10: realm name empty all session -> same character record, history kept;
-- a record already saved under "Name - " joins it.
do
 local DBc=VoidMarkJourneyDB.characters
 local real=DBc['Voidmark Soulreaver - CAMWOW US2']; assert(real and #real.dings>=1,'setup')
 local before=#real.dings
 DBc['Voidmark Soulreaver - ']={name='Voidmark Soulreaver',realm='',savedAt=real.savedAt+10,level=56,dings={{level=56,at=real.savedAt+5,zone='Winterspring',played=19440,deaths=1}},levelPlayed=0,levelDeaths=0}
 local g=GetRealmName; GetRealmName=function() return '' end
 Emit('ADDON_LOADED','VoidMarkJourney')
 GetRealmName=g
 eq(DBc['Voidmark Soulreaver - '],nil,'blank-realm record left')
 local c2=DBc['Voidmark Soulreaver - CAMWOW US2']; assert(c2,'real record gone')
 eq(#c2.dings,before+1,'history not combined'); eq(c2.dings[1].level,56,'newest ding first')
 eq(J.char,c2,'opened the wrong record')
end
