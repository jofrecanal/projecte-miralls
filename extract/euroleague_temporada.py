"""
Extractor de l'Euroliga: estadístiques de temporada regular (totals acumulats).

Fa servir l'API pública que alimenta la web de l'Euroliga (api-live.euroleague.net, v3).
Només 3 peticions per temporada, amb pausa entre elles (normes de data/FONTS.md):
  1. jugadors  -> /statistics/players/traditional
  2. equips    -> /statistics/teams/traditional
  3. rivals    -> /statistics/teams/opponentsTraditional  (totals dels rivals, per al PT2)

Guarda les respostes en brut (JSON) a data/raw/euroleague/ i una còpia aplanada dels
jugadors en CSV. Les dades en brut queden fora de Git (D10).

Ús:  python extract/euroleague_temporada.py 2025      (2025 = temporada 2025-26)
"""
import json
import sys
import time
from pathlib import Path

import pandas as pd
import requests

BASE = "https://api-live.euroleague.net/v3/competitions/E/statistics"
HEADERS = {
    "Accept": "application/json",
    "User-Agent": "projecte-miralls (projecte personal, no comercial)",
}
PAUSA = 3  # segons entre peticions


def descarrega(url, params):
    r = requests.get(url, params=params, headers=HEADERS, timeout=60)
    r.raise_for_status()
    return r.json()


def main():
    any_inici = int(sys.argv[1]) if len(sys.argv) > 1 else 2025
    temporada = f"{any_inici}-{str(any_inici + 1)[-2:]}"
    params = {
        "SeasonMode": "Single",
        "SeasonCode": f"E{any_inici}",
        "statisticMode": "Accumulated",
        "phaseTypeCode": "RS",
        "limit": 1000,
    }

    carpeta = Path("data/raw/euroleague")
    carpeta.mkdir(parents=True, exist_ok=True)

    peticions = {
        "jugadors": f"{BASE}/players/traditional",
        "equips": f"{BASE}/teams/traditional",
        "rivals": f"{BASE}/teams/opponentsTraditional",
    }

    respostes = {}
    for i, (nom, url) in enumerate(peticions.items()):
        if i > 0:
            time.sleep(PAUSA)
        print(f"Descarregant {nom}...")
        dades = descarrega(url, params)
        fitxer = carpeta / f"euroleague_{nom}_{temporada}.json"
        fitxer.write_text(json.dumps(dades, ensure_ascii=False, indent=1), encoding="utf-8")
        respostes[nom] = dades
        print(f"  guardat a {fitxer}")

    # Jugadors aplanats a CSV
    jugadors = pd.json_normalize(respostes["jugadors"]["players"])
    csv = carpeta / f"euroleague_jugadors_{temporada}.csv"
    jugadors.to_csv(csv, index=False)

    print()
    print(f"Jugadors: {len(jugadors)} files, {jugadors.shape[1]} columnes -> {csv}")
    for nom in ("equips", "rivals"):
        claus = [k for k, v in respostes[nom].items() if isinstance(v, list)]
        n = len(respostes[nom][claus[0]]) if claus else 0
        print(f"{nom.capitalize()}: {n} files (clau '{claus[0] if claus else '?'}')")
    print()
    print("Columnes dels jugadors:")
    print(jugadors.columns.tolist())
    print()
    print("Primer jugador:")
    print(jugadors.head(1).T.to_string())


if __name__ == "__main__":
    main()
