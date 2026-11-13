"""
PT2 · Totals de cada equip de l'ACB (temporada regular), llegits dels HTML ja descarregats.
No fa cap petició nova: reaprofita data/raw/acb/equips_<temporada>/*.html (D18).
Els totals d'equip inclouen els rebots i les pèrdues d'equip (no atribuïts a cap jugador).
La web no publica els totals dels rivals.
Ús: python extract/acb_totals_equip.py
"""
import json
import re
from pathlib import Path

import pandas as pd

TEMPORADA = "2025-26"
CARPETA = Path(f"data/raw/acb/equips_{TEMPORADA}")
TROSSOS = re.compile(r'self\.__next_f\.push\(\[1,"((?:[^"\\]|\\.)*)"\]\)')


def text_dades(html):
    """Ajunta els trossos de dades que la web envia dins l'HTML."""
    return "".join(json.loads(f'"{t}"') for t in TROSSOS.findall(html))


files = []
for html in sorted(CARPETA.glob("*.html")):
    txt = text_dades(html.read_text(encoding="utf-8"))
    pos = txt.find('"teamTotals":')
    obj, _ = json.JSONDecoder().raw_decode(txt, pos + len('"teamTotals":'))
    fila = {"EQUIP": html.stem}
    fila.update(obj["totals"])
    files.append(fila)

df = pd.DataFrame(files)
df["SEASON"], df["LEAGUE"], df["PHASE"] = TEMPORADA, "ACB", "regular"
sortida = Path(f"data/raw/acb/acb_equips_{TEMPORADA}.csv")
df.to_csv(sortida, index=False)
print(f"Fet! {len(df)} equips -> {sortida}")
print(df[["EQUIP", "numGames", "points", "offensiveRebounds", "turnovers"]].to_string(index=False))
