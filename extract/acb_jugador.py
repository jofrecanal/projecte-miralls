"""
PT1 · ACB: llegir les temporades d'un jugador des de la seva pàgina.
Ús: python extract/acb_jugador.py harald-frey-30003398
"""
import sys
import time
from pathlib import Path

import requests
from bs4 import BeautifulSoup

CAP = {"User-Agent": "ProjecteMiralls/0.1 (projecte personal no comercial)"}
BASE = "https://acb.com/es/liga/jugadores"
CARPETA_RAW = Path("data/raw/acb/jugadors")

COLUMNES = [
    "TEMP", "CLUB", "PAR", "MIN", "TITULAR_PCT", "PT", "PT_MAX",
    "T3_CON", "T3_INT", "T3_PCT", "T2_CON", "T2_INT", "T2_PCT",
    "TL_CON", "TL_INT", "TL_PCT", "REB_OFE", "REB_DEF", "REB_TOT",
    "ASI", "BAL_REC", "BAL_PER", "TAP_FAV", "TAP_CON", "MAT",
    "FAL_COM", "FAL_REC", "MES_MENYS", "VAL", "V", "D",
]


def a_numero(text):
    """'7,2' -> 7.2 · '29,7%' -> 29.7 · '17:48' -> 17.8 (minuts)."""
    t = text.strip().replace("%", "")
    if ":" in t:
        m, s = t.split(":")
        return round(int(m) + int(s) / 60, 2)
    try:
        return float(t.replace(",", "."))
    except ValueError:
        return t  # text (temporada, club)


def llegir_temporades(slug):
    url = f"{BASE}/{slug}/temporada"
    r = requests.get(url, headers=CAP, timeout=30)
    r.raise_for_status()
    CARPETA_RAW.mkdir(parents=True, exist_ok=True)
    (CARPETA_RAW / f"{slug}.html").write_text(r.text, encoding="utf-8")
    time.sleep(3)  # norma del projecte: peticions lentes

    sopa = BeautifulSoup(r.text, "html.parser")
    files = []
    for taula in sopa.select("table[class*=temporadaTable]"):
        for tr in taula.select("tbody tr"):
            cel = [td.get_text(strip=True) for td in tr.find_all("td")]
            if not cel or not cel[0][:2].isdigit():
                continue  # files buides, Totales, Promedios
            if len(cel) != len(COLUMNES):
                print(f"  Avís: fila amb {len(cel)} columnes (n'esperava {len(COLUMNES)}): {cel[:3]}")
                continue
            fila = {col: a_numero(v) for col, v in zip(COLUMNES, cel)}
            fila["TEMP"], fila["CLUB"] = cel[0], cel[1]
            fila["SLUG"] = slug
            files.append(fila)
    return files


if __name__ == "__main__":
    slug = sys.argv[1] if len(sys.argv) > 1 else "harald-frey-30003398"
    files = llegir_temporades(slug)
    print(f"{slug}: {len(files)} temporades trobades")
    for f in files:
        marca = "  <-- 2025-26" if f["TEMP"] == "25-26" else ""
        print(f"  {f['TEMP']}  {f['CLUB']:<22} {f['PAR']:>4.0f} par  "
              f"{f['MIN']:>5} min  {f['PT']:>5} pt  {f['ASI']:>4} asi  {f['REB_TOT']:>4} reb{marca}")
