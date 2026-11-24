# VoidMark Journey

Leveling companion for **WoW Forever**. Made to sit next to Questie and RestedXP guides —
it doesn't touch quests or routes, only the numbers they don't show.

- **XP/hour and time to level** — based on your last 10 minutes, handles level-ups.
- **Rested XP** — amount and bubbles, shown as a blue overlay on the XP bar.
- **Cozy Sleeping Bag** — `Well-Rested 2/3 · next in 0:41`, a sound + raid-warning alert at 3/3,
  and the bag cooldown when you're not using it.
- **XP food reminder** — click **Food** for a small icon: drag your XP food onto it, left-click to eat. It stays hidden while the buff is up and pops up with 1 minute left or when it runs out.
  Counts down the buff and alerts (sound + raid warning) at 60 sec left and when it runs out.
  Shift+drag to move, Shift+right-click to clear.
- **Alts** — every character's level and rested XP, including rested built up while logged out.
  Characters on your **other WoW account** are listed too (marked *other account*): whenever a character from each account is online at the same time, the two swap their character lists. Your VoidMark Market sync partner is linked automatically; otherwise `/journey link First Surname` with one of the other account's characters.
- **Dings** — each level with date, zone, time played that level, and deaths.

## Commands
`/journey` (or `/vmj`) show/hide · `/journey alts` · `/journey link` · `/journey dings` · `/journey lock` ·
`/journey reset` (restart XP/hr) · `/journey bagalert` (toggle the 3/3 alert) · `/journey food` (food icon) · `/journey foodalert` · `/journey help` (or the **?** button: searchable FAQ and every command)

Drag the window to move it. Saved per account in `VoidMarkJourneyDB`.

## Tests
`pip install lupa==2.8` then `python tests/validate.py`.
