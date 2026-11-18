"""
PT3 (D26) · Plantilles 2025-26 de l'ACB i l'Euroliga: posició i alçada de cada jugador.
  ACB:      18 pàgines de plantilla (acb.com/es/liga/equipos/{slug}/plantilla?editionId=90)
  Euroliga: 20 plantilles de l'API pública (api-live.euroleague.net/v2/.../clubs/{codi}/people)
Pausa de 3 s entre peticions (FONTS.md). El brut es guarda a data/raw/ (fora de Git, D10).
Resultat: data/raw/plantilles_2025-26.csv i taula `plantilles` a DuckDB.
Grups (D26): Base/Escolta/Guard -> exterior · Alero/Ala-pívot/Forward -> aler · Pívot/Center -> interior
Ús: python extract/plantilles_temporada.py             (descarrega: 38 peticions)
    python extract/plantilles_temporada.py --del-disc  (rellegeix el brut, sense peticions)
"""
import json
import re
import sys
import time
from pathlib import Path

import duckdb
import pandas as pd
import requests

CAP = {"User-Agent": "ProjecteMiralls/0.1 (projecte personal no comercial)",
       "Accept": "text/html,application/json"}
PAUSA = 3
TEMPORADA, EDICIO, ANY_EUR = "2025-26", 90, 2025
DIR_ACB = Path(f"data/raw/acb/plantilles_{TEMPORADA}")
DIR_EUR = Path(f"data/raw/euroleague/plantilles_{TEMPORADA}")

EQUIPS_ACB = [
    "asisa-joventut-8", "barca-2", "casademont-zaragoza-16", "fiatc-girona-591",
    "ilerna-lleida-658", "kidsandus-manresa-10", "kosner-baskonia-3",
    "la-laguna-tenerife-28", "morabanc-andorra-22", "real-madrid-9",
    "recoletas-salud-san-pablo-burgos-549", "rio-breogan-25", "surne-bilbao-4",
    "ucam-murcia-12", "unicaja-14", "valencia-basket-13",
    "dreamland-gran-canaria-5", "coviran-granada-592",
]
GRUPS = {"Base": "exterior", "Escolta": "exterior", "Guard": "exterior",
         "Alero": "aler", "Ala-pívot": "aler", "Forward": "aler",
         "Pívot": "interior", "Center": "interior"}
TROSSOS = re.compile(r'self\.__next_f\.push\(\[1,"((?:[^"\\]|\\.)*)"\]\)')


def text_dades(html):
    return "".join(json.loads(f'"{t}"') for t in TROSSOS.findall(html))


def baixa(url, fitxer, del_disc):
    if del_disc:
        return fitxer.read_text(encoding="utf-8")
    time.sleep(PAUSA)  # norma del projecte: peticions lentes i respectuoses
    r = requests.get(url, headers=CAP, timeout=30)
    r.raise_for_status()
    fitxer.parent.mkdir(parents=True, exist_ok=True)
    fitxer.write_text(r.text, encoding="utf-8")
    return r.text


def llegir_acb(html, slug):
    txt = text_dades(html)
    i = txt.find('"currentRoster":')
    if i < 0:
        print(f"   ! {slug}: no s'ha trobat la plantilla")
        return []
    roster, _ = json.JSONDecoder().raw_decode(txt, i + len('"currentRoster":'))
    files = []
    for clau in ("players", "playerAbsences"):
        for e in roster.get(clau) or []:
            p = e.get("player", e)
            if not p.get("id"):
                continue
            files.append({"lliga": "ACB", "jugador_id": f"ACB_{p['id']}", "nom": p.get("nickname"),
                          "equip": slug, "posicio": p.get("gameRole"),
                          "alcada_cm": e.get("height") or p.get("height") or None,
                          "baixa": clau == "playerAbsences"})
    return files


def codis_euroliga():
    df = pd.read_csv(f"data/raw/euroleague/euroleague_jugadors_{TEMPORADA}.csv", dtype=str)
    return sorted({c for v in df["player.team.code"].dropna() for c in v.split(";")})


def llegir_euroliga(text, codi):
    dades = json.loads(text)
    entrades = dades if isinstance(dades, list) else next(
        (v for v in dades.values() if isinstance(v, list)), [])
    files = []
    for e in entrades:
        if e.get("type") != "J":  # només jugadors (fora entrenadors, metges, etc.)
            continue
        p = e["person"]
        files.append({"lliga": "EUROLIGA", "jugador_id": f"EUR_{p['code']}", "nom": p.get("name"),
                      "equip": codi, "posicio": e.get("positionName"),
                      "alcada_cm": p.get("height") or None, "baixa": not e.get("active", True)})
    return files


def main():
    del_disc = "--del-disc" in sys.argv
    files = []

    print("== ACB ==")
    for i, slug in enumerate(EQUIPS_ACB, 1):
        url = f"https://acb.com/es/liga/equipos/{slug}/plantilla?editionId={EDICIO}"
        f = llegir_acb(baixa(url, DIR_ACB / f"{slug}.html", del_disc), slug)
        print(f"[{i:>2}/{len(EQUIPS_ACB)}] {slug:<40} {len(f):>3} jugadors")
        files += f

    print("\n== Euroliga ==")
    codis = codis_euroliga()
    for i, codi in enumerate(codis, 1):
        url = (f"https://api-live.euroleague.net/v2/competitions/E/seasons/E{ANY_EUR}"
               f"/clubs/{codi}/people")
        f = llegir_euroliga(baixa(url, DIR_EUR / f"{codi}.json", del_disc), codi)
        print(f"[{i:>2}/{len(codis)}] {codi:<6} {len(f):>3} jugadors")
        files += f

    df = pd.DataFrame(files)
    df["grup"] = df["posicio"].map(GRUPS)
    df["temporada"] = TEMPORADA
    # un jugador traspassat surt a dues plantilles: ens en quedem una fila (l'alçada és la mateixa)
    df = (df.sort_values(["baixa", "alcada_cm"], na_position="last")
            .drop_duplicates("jugador_id").sort_values(["lliga", "equip", "nom"]))
    csv = Path(f"data/raw/plantilles_{TEMPORADA}.csv")
    df.to_csv(csv, index=False)
    print(f"\n{len(df)} jugadors -> {csv}")

    print("\n== Controls ==")
    print(df.groupby(["lliga", "grup"], dropna=False).size().to_string())
    sense = df[df["grup"].isna()]["posicio"].value_counts(dropna=False)
    if len(sense):
        print("\nPosicions sense grup:\n" + sense.to_string())
    print(f"\nSense alçada: {df['alcada_cm'].isna().sum()}")
    print(df.groupby("lliga")["alcada_cm"].describe()[["min", "50%", "max"]].to_string())

    con = duckdb.connect("data/miralls.duckdb")
    con.execute("CREATE OR REPLACE TABLE plantilles AS SELECT * FROM df")
    print("\n== Jugadors per sobre del llindar amb posició i alçada ==")
    print(con.execute("""
        SELECT v.lliga, COUNT(*) AS jugadors, COUNT(p.jugador_id) AS amb_plantilla,
               COUNT(p.alcada_cm) AS amb_alcada
        FROM variables_z v LEFT JOIN plantilles p USING (jugador_id)
        WHERE v.supera_llindar GROUP BY v.lliga ORDER BY v.lliga
    """).df().to_string(index=False))
    falten = con.execute("""
        SELECT v.lliga, v.jugador_id, v.nom FROM variables_z v
        LEFT JOIN plantilles p USING (jugador_id)
        WHERE v.supera_llindar AND p.jugador_id IS NULL ORDER BY 1, 3 LIMIT 15
    """).df()
    if len(falten):
        print("\nExemples de jugadors sense plantilla:\n" + falten.to_string(index=False))
    con.close()


if __name__ == "__main__":
    main()
