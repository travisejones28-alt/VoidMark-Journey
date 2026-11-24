"""Lua 5.1 syntax + TOC check + mocked client tests for VoidMark Journey. Needs lupa."""
from pathlib import Path
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
L=LuaRuntime(unpack_returned_tuples=True)
for line in (ROOT/'VoidMarkJourney.toc').read_text().splitlines():
    line=line.strip()
    if line and not line.startswith('#'): assert (ROOT/line).exists(), line
L.execute((Path(__file__).parent/'mock.lua').read_text())
L.globals().HELP=(ROOT/'Help.lua').read_text()
L.execute('assert(loadstring(HELP,"Help.lua"))("VoidMarkJourney",{})')
L.globals().SRC=(ROOT/'VoidMarkJourney.lua').read_text()
L.execute('assert(loadstring(SRC,"VoidMarkJourney.lua"))("VoidMarkJourney",{})')
L.globals().LINK=(ROOT/'Link.lua').read_text()
L.execute('assert(loadstring(LINK,"Link.lua"))("VoidMarkJourney",{})')
L.globals().FOOD=(ROOT/'Food.lua').read_text()
L.execute('assert(loadstring(FOOD,"Food.lua"))("VoidMarkJourney",{})')
L.execute((Path(__file__).parent/'journey_tests.lua').read_text())
L.execute((Path(__file__).parent/'food_tests.lua').read_text())
L.execute((Path(__file__).parent/'link_tests.lua').read_text())

# Help window lists every /journey subcommand the handler accepts.
import re
src=(ROOT/'VoidMarkJourney.lua').read_text()
handler=src[src.index('SlashCmdList.VOIDMARKJOURNEY'):]
words=set(re.findall(r'msg *== *"(\w+)"',handler))-{'faq','commands'}
listed=set()
for entry in re.findall(r"\{'(/journey[^']*)'",(ROOT/'Help.lua').read_text()): listed.update(re.findall(r'\w+',entry))
missing=sorted(words-listed)
assert len(words)>=5 and not missing, f'Help.lua missing /journey {missing}'
L.execute("""
SlashCmdList.VOIDMARKJOURNEY('help rested')
assert(VoidMarkJourneyHelpWindow and VoidMarkJourneyHelpWindow:IsShown(),'help opens')
local t,n=VoidMarkJourneyHelp.Text('bag'); assert(n>0 and t:find('/journey bagalert',1,true))
""")
print('PASS: Help lists all /journey commands and opens')
