"""Lua 5.1 syntax + TOC check + mocked client tests for VoidMark Journey. Needs lupa."""
from pathlib import Path
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
L=LuaRuntime(unpack_returned_tuples=True)
for line in (ROOT/'VoidMarkJourney.toc').read_text().splitlines():
    line=line.strip()
    if line and not line.startswith('#'): assert (ROOT/line).exists(), line
L.execute((Path(__file__).parent/'mock.lua').read_text())
L.globals().SRC=(ROOT/'VoidMarkJourney.lua').read_text()
L.execute('assert(loadstring(SRC,"VoidMarkJourney.lua"))("VoidMarkJourney",{})')
L.execute((Path(__file__).parent/'journey_tests.lua').read_text())
