"""
PT1 · Extractor de l'ACB per a una temporada (una pàgina per equip).
Ús: python extract/acb_temporada.py
editionId=90 -> temporada 2025-26 (89 = 2024-25, 91 = 2026-27)
"""
import re
import time
from datetime import date
from pathlib import Path

import pandas as pd
import requests
from bs4 import BeautifulSoup

CAP = {"User-Agent": "ProjecteMiralls/0.1 (projecte personal no comercial)"}
EDICIO, TEMPORADA = 90, "2025-26"
CARPETA_RAW = Path("data/raw/acb")

# Equips de la Liga Endesa 2025-26 (slug de la web nova)
EQUIPS = [
    "asisa-joventut-8", "barca-2", "casademont-zaragoza-16", "fiatc-girona-591",
    "ilerna-lleida-658", "kidsandus-manresa-10", "kosner-baskonia-3",
    "la-laguna-tenerife-28", "morabanc-andorra-22", "real-madrid-9",
    "recoletas-salud-san-pablo-burgos-549", "rio-breogan-25", "surne-bilbao-4",
    "ucam-murcia-12", "unicaja-14", "valencia-basket-13",
    "dreamland-gran-canaria-5",
    "coviran-granada-592",
]

COLUMNES = [
    "JUGADOR", "PAR", "MIN", "TITULAR_PCT", "PT",
    "T3_CON", "T3_INT", "T3_PCT", "T2_CON", "T2_INT", "T2_PCT",
    "TL_CON", "TL_INT", "TL_PCT", "REB_OFE", "REB_DEF", "REB_TOT",
    "ASI", "BAL_REC", "BAL_PER", "TAP_FAV", "TAP_CON", "MAT",
    "FAL_COM", "FAL_REC", "MES_MENYS", "VAL",
]


def a_numero(text):
    t = text.strip().replace("%", "")
    if ":" in t:
        m, s = t.split(":")
        return round(int(m) + int(s) / 60, 2)
    try:
        return float(t.replace(",", "."))
    except ValueError:
        return None


def llegir_equip(slug):
    url = f"https://acb.com/es/liga/equipos/{slug}/estadisticas?editionId={EDICIO}&phaseId=107"
    r = requests.get(url, headers=CAP, timeout=30)
    r.raise_for_status()
    carpeta = CARPETA_RAW / f"equips_{TEMPORADA}"
    carpeta.mkdir(parents=True, exist_ok=True)
    (carpeta / f"{slug}.html").write_text(r.text, encoding="utf-8")

    sopa = BeautifulSoup(r.text, "html.parser")
    files = []
    for tr in sopa.select("table tbody tr"):
        enllac = tr.select_one('a[href*="/jugadores/"]')
        if not enllac:
            continue  # files buides o de totals
        cel = [td.get_text(" ", strip=True) for td in tr.find_all("td")]
        if len(cel) != len(COLUMNES):
            print(f"  Avís {slug}: fila amb {len(cel)} columnes")
            continue
        fila = {col: a_numero(v) for col, v in zip(COLUMNES, cel)}
        fila["JUGADOR"] = re.sub(r"^\d+\s+", "", cel[0])  # treu el dorsal
        fila["SLUG"] = enllac["href"].split("?")[0].split("/")[-1]
        fila["EQUIP"] = slug
        files.append(fila)
    return files


def main():
    totes = []
    for i, slug in enumerate(EQUIPS, 1):
        files = llegir_equip(slug)
        print(f"[{i:>2}/{len(EQUIPS)}] {slug:<40} {len(files):>3} jugadors")
        totes.extend(files)
        time.sleep(3)  # norma del projecte: peticions lentes i respectuoses

    df = pd.DataFrame(totes)
    df["SEASON"], df["LEAGUE"] = TEMPORADA, "ACB"
    df["EXTRACTED_AT"] = date.today().isoformat()
    fitxer = CARPETA_RAW / f"acb_jugadors_{TEMPORADA}.csv"
    df.to_csv(fitxer, index=False)

    print(f"\nFet! {len(df)} files ({df['SLUG'].nunique()} jugadors) -> {fitxer}")
    print("\nTop 5 anotadors (punts per partit, mínim 15 partits):")
    top = df[df["PAR"] >= 15].sort_values("PT", ascending=False).head(5)
    for _, f in top.iterrows():
        print(f"  {f['JUGADOR']:<26} {f['EQUIP']:<28} {f['PT']:>5} pt en {int(f['PAR'])} partits")


if __name__ == "__main__":
    main()
