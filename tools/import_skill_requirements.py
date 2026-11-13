"""Extract numeric Classic skill requirements from the user's local AtlasLoot data."""
from pathlib import Path
import re
import sys
source = Path(sys.argv[1])
text = source.read_text().split('PROFESSION_DATA.CLASSIC = {', 1)[1].split('\n}', 1)[0]
rows = []
for spell, output, profession, rank in re.findall(r'^\s*\[(\d+)\] = \{ (\d+), ([26]), (\d+),', text, re.M):
    rows.append((int(spell), int(output), 164 if profession == '2' else 185, int(rank)))
assert rows and len({r[0] for r in rows}) == len(rows)
lines = ['-- Classic fallback requirements extracted from AtlasLootClassic/Data/Profession.lua.',
         '-- Not a complete or verified Forever catalogue. See THIRD_PARTY.md.',
         'local _, F = ...', 'F.skillRequirements = {']
for spell, output, profession, rank in sorted(rows):
    lines.append(f'  [{spell}] = {{ {rank}, {profession}, {output} }},')
lines.append('}')
Path('tools/legacy-classic-data/SkillData.lua').write_text('\n'.join(lines) + '\n')
print(f'Extracted {len(rows)} skill requirements')
