"""
PT1 · Càrrega de NBA i ACB a DuckDB amb l'esquema comú (D13).
Taules: jugadors, equips, estadistiques (totals, temporada regular).
Ús: python extract/carregar_duckdb.py
"""
from pathlib import Path

import duckdb
import pandas as pd

TEMPORADA = "2025-26"
BD = Path("data/miralls.duckdb")

nba = pd.read_csv(f"data/raw/nba/nba_jugadors_{TEMPORADA}.csv")
acb = pd.read_csv(f"data/raw/acb/acb_jugadors_{TEMPORADA}.csv")

# --- Estadístiques amb noms comuns ---
est_nba = pd.DataFrame({
    "jugador_id": "NBA_" + nba["PLAYER_ID"].astype(str),
    "equip_id": "NBA_" + nba["TEAM_ID"].astype(str),
    "lliga": "NBA", "temporada": TEMPORADA, "fase": "regular",
    "partits": nba["GP"], "minuts": nba["MIN"].round(1), "punts": nba["PTS"],
    "t2_anot": nba["FGM"] - nba["FG3M"], "t2_int": nba["FGA"] - nba["FG3A"],
    "t3_anot": nba["FG3M"], "t3_int": nba["FG3A"],
    "tl_anot": nba["FTM"], "tl_int": nba["FTA"],
    "reb_of": nba["OREB"], "reb_def": nba["DREB"], "assist": nba["AST"],
    "robatoris": nba["STL"], "perdues": nba["TOV"], "taps": nba["BLK"],
    "faltes": nba["PF"],
})
est_acb = pd.DataFrame({
    "jugador_id": "ACB_" + acb["JUGADOR_ID"].astype(str),
    "equip_id": "ACB_" + acb["EQUIP"],
    "lliga": "ACB", "temporada": TEMPORADA, "fase": "regular",
    "partits": acb["numGames"], "minuts": (acb["timePlayed"] / 60).round(1),
    "punts": acb["points"],
    "t2_anot": acb["twoPointersMade"], "t2_int": acb["twoPointersAttempted"],
    "t3_anot": acb["threePointersMade"], "t3_int": acb["threePointersAttempted"],
    "tl_anot": acb["freeThrowsMade"], "tl_int": acb["freeThrowsAttempted"],
    "reb_of": acb["offensiveRebounds"], "reb_def": acb["defensiveRebounds"],
    "assist": acb["assists"], "robatoris": acb["steals"], "perdues": acb["turnovers"],
    "taps": acb["blocks"], "faltes": acb["personalFouls"],
})
est = pd.concat([est_nba, est_acb], ignore_index=True)
sense_partits = (est["partits"] == 0).sum()
est = est[est["partits"] > 0]

# --- Jugadors i equips ---
jugadors = pd.concat([
    pd.DataFrame({"jugador_id": "NBA_" + nba["PLAYER_ID"].astype(str), "lliga": "NBA",
                  "id_font": nba["PLAYER_ID"].astype(str), "nom": nba["PLAYER_NAME"]}),
    pd.DataFrame({"jugador_id": "ACB_" + acb["JUGADOR_ID"].astype(str), "lliga": "ACB",
                  "id_font": acb["JUGADOR_ID"].astype(str), "nom": acb["JUGADOR"]}),
]).drop_duplicates("jugador_id")
equips = pd.concat([
    pd.DataFrame({"equip_id": "NBA_" + nba["TEAM_ID"].astype(str), "lliga": "NBA",
                  "nom": nba["TEAM_ABBREVIATION"]}),
    pd.DataFrame({"equip_id": "ACB_" + acb["EQUIP"], "lliga": "ACB", "nom": acb["EQUIP"]}),
]).drop_duplicates("equip_id")

# --- Controls de qualitat ---
print("=== Controls de qualitat ===")
print(f"Files amb 0 partits descartades: {sense_partits}")
calc = 2 * est["t2_anot"] + 3 * est["t3_anot"] + est["tl_anot"]
for lliga in ["NBA", "ACB"]:
    mal = ((calc != est["punts"]) & (est["lliga"] == lliga)).sum()
    print(f"{lliga}: files on punts != 2*T2 + 3*T3 + TL -> {mal}")
dup = est.duplicated(["jugador_id", "equip_id", "temporada"]).sum()
print(f"Files duplicades (jugador, equip, temporada): {dup}")

# --- Escriure a DuckDB ---
con = duckdb.connect(str(BD))
for nom, df in {"jugadors": jugadors, "equips": equips, "estadistiques": est}.items():
    con.register("tmp", df)
    con.execute(f"CREATE OR REPLACE TABLE {nom} AS SELECT * FROM tmp")
    con.unregister("tmp")

print(f"\n=== Base de dades: {BD} ===")
con.sql("""
    SELECT lliga, COUNT(*) AS files, COUNT(DISTINCT jugador_id) AS jugadors,
           COUNT(DISTINCT equip_id) AS equips, SUM(punts) AS punts_totals
    FROM estadistiques GROUP BY lliga ORDER BY lliga
""").show()
con.close()
