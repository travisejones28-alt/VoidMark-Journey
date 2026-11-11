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
assert(VoidMarkJourneyList.Body:GetText():find('Lv 21'),'dings list')

-- Secret XP values never crash the window.
P.xp=SECRET; Emit('PLAYER_XP_UPDATE','player'); J.Refresh(); P.xp=500
-- Max level shows a quiet message.
P.level=60; J.Refresh(); assert(VoidMarkJourneyFrame.Pace:GetText():find('Max level'),'max level text'); P.level=21
-- Toggle and settings persist.
SlashCmdList.VOIDMARKJOURNEY(''); eq(VoidMarkJourneyDB.settings.shown,false,'hide not saved')
SlashCmdList.VOIDMARKJOURNEY(''); eq(VoidMarkJourneyDB.settings.shown,true,'show not saved')
SlashCmdList.VOIDMARKJOURNEY('lock'); eq(VoidMarkJourneyDB.settings.locked,true,'lock')
print('PASS: XP/hr + level crossing, dings/deaths/played, rested bubbles, sleeping bag countdown + single alert, alts offline rested, secrets, slash commands')
