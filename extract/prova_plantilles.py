"""
PT3 (D26) · Prova: una plantilla de cada lliga per veure on hi ha la posició i l'alçada.
Només 2 peticions (3 si cal la ruta alternativa de l'Euroliga), amb pausa (FONTS.md).
Guarda el brut a data/raw/ (fora de Git, D10).
  ACB:      acb.com/es/liga/equipos/barca-2/plantilla?editionId=90   (2025-26)
  Euroliga: api-live.euroleague.net/v2/competitions/E/seasons/E2025/clubs/BAR/people
Ús: python extract/prova_plantilles.py
"""
import json
import re
import time
from pathlib import Path

import requests

CAP = {"User-Agent": "ProjecteMiralls/0.1 (projecte personal no comercial)",
       "Accept": "text/html,application/json"}
PAUSA = 3
TEMPORADA = "2025-26"

TROSSOS = re.compile(r'self\.__next_f\.push\(\[1,"((?:[^"\\]|\\.)*)"\]\)')


def text_dades(html):
    return "".join(json.loads(f'"{t}"') for t in TROSSOS.findall(html))


def prova_acb():
    url = "https://acb.com/es/liga/equipos/barca-2/plantilla?editionId=90"
    print(f"\n== ACB: {url}")
    r = requests.get(url, headers=CAP, timeout=30)
    print(f"Estat: {r.status_code} · {len(r.text):,} caràcters")
    r.raise_for_status()
    carpeta = Path(f"data/raw/acb/plantilles_{TEMPORADA}")
    carpeta.mkdir(parents=True, exist_ok=True)
    (carpeta / "barca-2.html").write_text(r.text, encoding="utf-8")

    txt = text_dades(r.text)
    print(f"Dades internes: {len(txt):,} caràcters")
    for clau in ["height", "altura", "position", "posicion", "editionId", "season"]:
        print(f"  '{clau}': {len(re.findall(clau, txt, flags=re.I))} aparicions")
    m = re.search(r'.{0,200}"height".{0,200}', txt)
    if m:
        print("\nExemple al voltant de 'height':\n", m.group(0))
    noms = re.findall(r'"nickname":"([^"]+)"', txt)
    print(f"\nNoms trobats ({len(set(noms))}): {sorted(set(noms))[:25]}")


def prova_euroliga():
    rutes = [
        "https://api-live.euroleague.net/v2/competitions/E/seasons/E2025/clubs/BAR/people",
        "https://feeds.incrowdsports.com/provider/euroleague-feeds/v2/competitions/E/seasons/E2025/clubs/BAR/people",
    ]
    for i, url in enumerate(rutes):
        if i > 0:
            time.sleep(PAUSA)
        print(f"\n== Euroliga: {url}")
        r = requests.get(url, headers=CAP, timeout=30)
        print(f"Estat: {r.status_code}")
        if r.ok:
            break
    else:
        print("Cap de les dues rutes ha funcionat.")
        return
    dades = r.json()
    carpeta = Path(f"data/raw/euroleague/plantilles_{TEMPORADA}")
    carpeta.mkdir(parents=True, exist_ok=True)
    (carpeta / "BAR.json").write_text(json.dumps(dades, ensure_ascii=False, indent=1), encoding="utf-8")

    files = dades if isinstance(dades, list) else next(
        (v for v in dades.values() if isinstance(v, list)), [])
    print(f"Entrades: {len(files)}")
    if files:
        print("\nPrimera entrada (resumida):")
        print(json.dumps(files[0], ensure_ascii=False, indent=1)[:2500])


if __name__ == "__main__":
    prova_acb()
    time.sleep(PAUSA)
    prova_euroliga()
