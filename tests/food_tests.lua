-- XP food reminder icon.
local J=VoidMarkJourney
local function eq(a,b,m) if a~=b then error((m or 'mismatch')..': expected '..tostring(b)..', got '..tostring(a),2) end end
local S=VoidMarkJourneyDB.settings
local btn=VoidMarkJourneyFood
assert(btn,'food icon built on login')
-- Food button / slash command shows it.
SlashCmdList.VOIDMARKJOURNEY('food'); eq(S.foodShown,true,'food icon shown'); assert(btn:IsShown())
assert(btn.Time:GetText():find('drag food'),'empty icon hint')
local function click(button) -- one real click (key-up)
  btn:GetScript('PreClick')(btn,button,false); btn:GetScript('PostClick')(btn,button,false)
end

-- Drag food onto the icon sets it and the secure "eat" attribute.
CURSOR=999; btn:GetScript('OnReceiveDrag')(btn)
eq(S.foodItem,999,'food set by drag'); eq(btn:GetAttribute('type1'),'item'); eq(btn:GetAttribute('item'),'item:999')
eq(CURSOR,nil,'cursor cleared')
-- Clicking with a food on the cursor sets it instead of eating.
CURSOR=999; click('LeftButton'); eq(S.foodItem,999); eq(btn:GetAttribute('type1'),'item','attribute restored')
-- Not eaten yet: EAT, no alert.
Advance(1); assert(btn.Time:GetText():find('EAT'),'shows EAT: '..btn.Time:GetText())
local a0=alerts

-- Eat: a short "Food" channel + Well-Rested are ignored; the new 30 min buff is learned.
BUFFS={{spellId=429959,expirationTime=NOW+3000,duration=3600}}
click('LeftButton')
BUFFS={{spellId=429959,expirationTime=NOW+3000,duration=3600},{spellId=5005,expirationTime=NOW+20,duration=20}}
Advance(1)
BUFFS={{spellId=429959,expirationTime=NOW+3000,duration=3600},{spellId=7777,expirationTime=NOW+1800,duration=1800}}
Emit('UNIT_AURA','player')
eq(S.foodBuffs[999],7777,'learned XP buff')
assert(btn.Time:GetText():find('30m') or btn.Time:GetText():find('29m'),'countdown: '..btn.Time:GetText())
Advance(1); assert(not btn:IsShown(),'icon hides while food buff has plenty of time')

-- Forever hiding auras mid-countdown: no false expired alert.
local saved=BUFFS
BUFFS=SECRET; for i=1,20 do Advance(1) end
BUFFS={}; for i=1,10 do Advance(1) end   -- briefly missing (< 15s)
BUFFS=saved; Emit('UNIT_AURA','player')
eq(alerts,a0,'false alert from hidden/flickering buff')

-- 60 seconds left: one warning; then expired: one more.
Advance(1800-30-60-5)
eq(alerts,a0,'warned too early')
for i=1,10 do Advance(1) end
eq(alerts,a0+1,'60 sec warning'); assert(printed[#printed]:find('runs out in'),printed[#printed])
assert(btn:IsShown(),'icon pops up in the last minute')
assert(btn.Time:GetText():find('0:'),'last-minute clock')
BUFFS={}; for i=1,70 do Advance(1) end
eq(alerts,a0+2,'expired alert once'); assert(printed[#printed]:find('Savory Leveling Stew expired'),printed[#printed])
assert(btn.Time:GetText():find('EAT'))
for i=1,60 do Advance(1) end; eq(alerts,a0+2,'expired alert repeated')

-- Eat again (buff known now): countdown restarts, alerts re-arm.
BUFFS={{spellId=7777,expirationTime=NOW+1800,duration=1800}}; Emit('UNIT_AURA','player')
assert(not btn:IsShown(),'icon hides after eating')
eq(VoidMarkJourneyDB.characters['Voidmark Soulreaver - CAMWOW US2'].food.warned,false,'re-armed')
-- Died / cancelled: gone for 15s+ counts as expired.
BUFFS={}; for i=1,20 do Advance(1) end
eq(alerts,a0+3,'early loss alerts')

-- Alerts can be turned off.
SlashCmdList.VOIDMARKJOURNEY('foodalert'); eq(S.foodAlert,false)
BUFFS={{spellId=7777,expirationTime=NOW+100,duration=1800}}; Emit('UNIT_AURA','player'); BUFFS={}
for i=1,120 do Advance(1) end; eq(alerts,a0+3,'alert while off'); SlashCmdList.VOIDMARKJOURNEY('foodalert')

-- Combat: can't hide a secure button, so it waits for combat to end.
BUFFS={}; for i=1,20 do Advance(1) end; assert(btn:IsShown(),'shown when expired')
COMBAT=true; BUFFS={{spellId=7777,expirationTime=NOW+1800,duration=1800}}; Emit('UNIT_AURA','player')
assert(btn:IsShown(),'hid in combat'); COMBAT=false; Emit('PLAYER_REGEN_ENABLED'); assert(not btn:IsShown(),'hid after combat')
BUFFS={}; for i=1,20 do Advance(1) end
-- Max level: never needed.
local c=VoidMarkJourneyDB.characters['Voidmark Soulreaver - CAMWOW US2']; local lv=c.level
c.level=60; Advance(1); assert(not btn:IsShown(),'shown at max level'); c.level=lv; Advance(1)
-- Out of food in bags.
ITEMS[999].count=0; J.Food.Update(); assert(btn.Time:GetText():find('none left')); ITEMS[999].count=5
-- Combat: setting waits, attribute untouched.
COMBAT=true; CURSOR=1234; btn:GetScript('OnReceiveDrag')(btn); eq(S.foodItem,999,'changed in combat'); COMBAT=false; CURSOR=nil
-- Down-half of a click is ignored (no double set/clear).
SHIFT=true; btn:GetScript('PostClick')(btn,'RightButton',true); eq(S.foodItem,999,'down click acted')
click('RightButton'); eq(S.foodItem,nil,'shift-right clears'); eq(btn:GetAttribute('type1'),nil); SHIFT=false
SlashCmdList.VOIDMARKJOURNEY('food'); eq(S.foodShown,false,'hide')
print('PASS: XP food icon - drag to set, click to eat, learns buff, 60s + expired alerts once, flicker-safe, combat-safe, clear')
