"""
PT1 · Extractor de l'ACB per a una temporada (totals exactes).
Cada pàgina d'equip porta dins un JSON amb 'totals', 'averages' i 'per40'
per jugador. Llegim els totals.
Ús: python extract/acb_temporada.py
editionId=90 -> 2025-26 · phaseId=107 -> Liga Regular
"""
import json
import re
import time
from datetime import date
from pathlib import Path

import pandas as pd
import requests

CAP = {"User-Agent": "ProjecteMiralls/0.1 (projecte personal no comercial)"}
EDICIO, FASE, TEMPORADA = 90, 107, "2025-26"
CARPETA_RAW = Path("data/raw/acb")

EQUIPS = [
    "asisa-joventut-8", "barca-2", "casademont-zaragoza-16", "fiatc-girona-591",
    "ilerna-lleida-658", "kidsandus-manresa-10", "kosner-baskonia-3",
    "la-laguna-tenerife-28", "morabanc-andorra-22", "real-madrid-9",
    "recoletas-salud-san-pablo-burgos-549", "rio-breogan-25", "surne-bilbao-4",
    "ucam-murcia-12", "unicaja-14", "valencia-basket-13",
    "dreamland-gran-canaria-5", "coviran-granada-592",
]

TROSSOS = re.compile(r'self\.__next_f\.push\(\[1,"((?:[^"\\]|\\.)*)"\]\)')


def text_dades(html):
    """Ajunta els trossos de dades que la web envia dins l'HTML."""
    return "".join(json.loads(f'"{t}"') for t in TROSSOS.findall(html))


def llegir_equip(slug):
    url = (f"https://acb.com/es/liga/equipos/{slug}/estadisticas"
           f"?editionId={EDICIO}&phaseId={FASE}")
    r = requests.get(url, headers=CAP, timeout=30)
    r.raise_for_status()
    carpeta = CARPETA_RAW / f"equips_{TEMPORADA}"
    carpeta.mkdir(parents=True, exist_ok=True)
    (carpeta / f"{slug}.html").write_text(r.text, encoding="utf-8")

    txt = text_dades(r.text)
    lector = json.JSONDecoder()
    jugadors = {}
    pos = txt.find('{"player":{"id":')
    while pos >= 0:
        try:
            obj, _ = lector.raw_decode(txt, pos)
            if "totals" in obj:
                p = obj["player"]
                fila = {"JUGADOR_ID": p["id"], "JUGADOR": p.get("nickname"), "EQUIP": slug}
                fila.update(obj["totals"])
                jugadors[p["id"]] = fila  # sense duplicats
        except json.JSONDecodeError:
            pass
        pos = txt.find('{"player":{"id":', pos + 1)
    return list(jugadors.values())


def main():
    totes = []
    for i, slug in enumerate(EQUIPS, 1):
        files = llegir_equip(slug)
        print(f"[{i:>2}/{len(EQUIPS)}] {slug:<40} {len(files):>3} jugadors")
        totes.extend(files)
        time.sleep(3)  # norma del projecte: peticions lentes i respectuoses

    df = pd.DataFrame(totes)
    df["minutes"] = (df["timePlayed"] / 60).round(1)
    df["SEASON"], df["LEAGUE"], df["PHASE"] = TEMPORADA, "ACB", "regular"
    df["EXTRACTED_AT"] = date.today().isoformat()
    fitxer = CARPETA_RAW / f"acb_jugadors_{TEMPORADA}.csv"
    df.to_csv(fitxer, index=False)

    print(f"\nFet! {len(df)} files ({df['JUGADOR_ID'].nunique()} jugadors), "
          f"{df.shape[1]} columnes -> {fitxer}")
    print("\nTop 5 anotadors (punts totals):")
    for _, f in df.sort_values("points", ascending=False).head(5).iterrows():
        print(f"  {f['JUGADOR']:<26} {f['EQUIP']:<28} {int(f['points']):>4} pts "
              f"en {int(f['numGames'])} partits")


if __name__ == "__main__":
    main()
