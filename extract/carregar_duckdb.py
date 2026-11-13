"""
Càrrega de NBA, ACB i Euroliga a DuckDB amb l'esquema comú (D13).
Taules:
  - jugadors, equips, estadistiques (totals de jugador, temporada regular)
  - totals_equip (totals de l'equip i dels seus rivals, per al PT2). Euroliga amb rivals;
    ACB sense rivals, perquè la web no els publica (columnes rival_* buides, D18)
L'NBA es manté a la base de dades però queda fora de la v1 (D16).
Ús: python extract/carregar_duckdb.py
"""
import json
from pathlib import Path

import duckdb
import pandas as pd

TEMPORADA = "2025-26"
BD = Path("data/miralls.duckdb")
RAW = Path("data/raw")

COMPTADORS = ["partits", "punts", "t2_anot", "t2_int", "t3_anot", "t3_int",
              "tl_anot", "tl_int", "reb_of", "reb_def", "assist", "robatoris",
              "perdues", "taps", "faltes"]

nba = pd.read_csv(RAW / f"nba/nba_jugadors_{TEMPORADA}.csv")
acb = pd.read_csv(RAW / f"acb/acb_jugadors_{TEMPORADA}.csv")
acb_eq = pd.read_csv(RAW / f"acb/acb_equips_{TEMPORADA}.csv")  # extract/acb_totals_equip.py


def llegeix_json(nom, clau):
    dades = json.loads((RAW / f"euroleague/euroleague_{nom}_{TEMPORADA}.json").read_text(encoding="utf-8"))
    return pd.json_normalize(dades[clau])


eur = llegeix_json("jugadors", "players")
eur_eq = llegeix_json("equips", "teams")
eur_riv = llegeix_json("rivals", "teams")


def stats_euroliga(df):
    """Columnes comunes a partir del format de l'API de l'Euroliga."""
    return pd.DataFrame({
        "partits": df["gamesPlayed"], "minuts": df["minutesPlayed"].round(1),
        "punts": df["pointsScored"],
        "t2_anot": df["twoPointersMade"], "t2_int": df["twoPointersAttempted"],
        "t3_anot": df["threePointersMade"], "t3_int": df["threePointersAttempted"],
        "tl_anot": df["freeThrowsMade"], "tl_int": df["freeThrowsAttempted"],
        "reb_of": df["offensiveRebounds"], "reb_def": df["defensiveRebounds"],
        "assist": df["assists"], "robatoris": df["steals"], "perdues": df["turnovers"],
        "taps": df["blocks"], "faltes": df["foulsCommited"],
    })


# --- Estadístiques de jugador amb noms comuns ---
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
# Euroliga: els jugadors traspassats surten en una sola fila amb els equips units ("MUN;PAR")
est_eur = pd.concat([
    pd.DataFrame({
        "jugador_id": "EUR_" + eur["player.code"].astype(str),
        "equip_id": "EUR_" + eur["player.team.code"],
        "lliga": "EUROLIGA", "temporada": TEMPORADA, "fase": "regular",
    }),
    stats_euroliga(eur),
], axis=1)

est = pd.concat([est_nba, est_acb, est_eur], ignore_index=True)
est[COMPTADORS] = est[COMPTADORS].astype(int)
est["diversos_equips"] = est["equip_id"].str.contains(";")
sense_partits = (est["partits"] == 0).sum()
est = est[est["partits"] > 0]

# --- Jugadors i equips ---
jugadors = pd.concat([
    pd.DataFrame({"jugador_id": "NBA_" + nba["PLAYER_ID"].astype(str), "lliga": "NBA",
                  "id_font": nba["PLAYER_ID"].astype(str), "nom": nba["PLAYER_NAME"]}),
    pd.DataFrame({"jugador_id": "ACB_" + acb["JUGADOR_ID"].astype(str), "lliga": "ACB",
                  "id_font": acb["JUGADOR_ID"].astype(str), "nom": acb["JUGADOR"]}),
    pd.DataFrame({"jugador_id": "EUR_" + eur["player.code"].astype(str), "lliga": "EUROLIGA",
                  "id_font": eur["player.code"].astype(str), "nom": eur["player.name"]}),
]).drop_duplicates("jugador_id")
equips = pd.concat([
    pd.DataFrame({"equip_id": "NBA_" + nba["TEAM_ID"].astype(str), "lliga": "NBA",
                  "nom": nba["TEAM_ABBREVIATION"]}),
    pd.DataFrame({"equip_id": "ACB_" + acb["EQUIP"], "lliga": "ACB", "nom": acb["EQUIP"]}),
    pd.DataFrame({"equip_id": "EUR_" + eur_eq["team.code"], "lliga": "EUROLIGA",
                  "nom": eur_eq["team.name"]}),
]).drop_duplicates("equip_id")

# --- Totals d'equip i dels rivals (Euroliga) ---
# Atenció: "minuts" aquí són minuts de partit de l'equip (~40 per partit), no minuts de jugador.
propis = pd.concat([pd.DataFrame({"equip_id": "EUR_" + eur_eq["team.code"]}),
                    stats_euroliga(eur_eq)], axis=1)
rivals = stats_euroliga(eur_riv).add_prefix("rival_")
rivals.insert(0, "equip_id", "EUR_" + eur_riv["team.code"])
totals_equip = propis.merge(rivals.drop(columns=["rival_partits", "rival_minuts"]), on="equip_id")
totals_equip.insert(1, "lliga", "EUROLIGA")
totals_equip.insert(2, "temporada", TEMPORADA)
totals_equip.insert(3, "fase", "regular")

# --- Totals d'equip de l'ACB (sense rivals) ---
# timePlayed de l'equip = segons sumats dels 5 jugadors -> minuts de partit = segons / 60 / 5
totals_acb = pd.DataFrame({
    "equip_id": "ACB_" + acb_eq["EQUIP"], "lliga": "ACB", "temporada": TEMPORADA, "fase": "regular",
    "partits": acb_eq["numGames"], "minuts": (acb_eq["timePlayed"] / 60 / 5).round(1),
    "punts": acb_eq["points"],
    "t2_anot": acb_eq["twoPointersMade"], "t2_int": acb_eq["twoPointersAttempted"],
    "t3_anot": acb_eq["threePointersMade"], "t3_int": acb_eq["threePointersAttempted"],
    "tl_anot": acb_eq["freeThrowsMade"], "tl_int": acb_eq["freeThrowsAttempted"],
    "reb_of": acb_eq["offensiveRebounds"], "reb_def": acb_eq["defensiveRebounds"],
    "assist": acb_eq["assists"], "robatoris": acb_eq["steals"], "perdues": acb_eq["turnovers"],
    "taps": acb_eq["blocks"], "faltes": acb_eq["personalFouls"],
})
totals_equip = pd.concat([totals_equip, totals_acb], ignore_index=True)
num = totals_equip.columns[totals_equip.columns.get_loc("partits"):]
totals_equip[[c for c in num if c != "minuts"]] = totals_equip[[c for c in num if c != "minuts"]].astype("Int64")

# --- Controls de qualitat ---
print("=== Controls de qualitat ===")
print(f"Files amb 0 partits descartades: {sense_partits}")
calc = 2 * est["t2_anot"] + 3 * est["t3_anot"] + est["tl_anot"]
for lliga in ["NBA", "ACB", "EUROLIGA"]:
    mal = ((calc != est["punts"]) & (est["lliga"] == lliga)).sum()
    print(f"{lliga}: files on punts != 2*T2 + 3*T3 + TL -> {mal}")
dup = est.duplicated(["jugador_id", "equip_id", "temporada"]).sum()
print(f"Files duplicades (jugador, equip, temporada): {dup}")
print(f"Euroliga: jugadors amb diversos equips en una sola fila -> {est['diversos_equips'].sum()}")

# Minuts dels jugadors = 5 x minuts de l'equip (només equips sense traspassos)
eur_ok = est[(est["lliga"] == "EUROLIGA") & ~est["diversos_equips"]]
equips_traspas = set(";".join(est.loc[est["diversos_equips"], "equip_id"].str[4:]).split(";"))
suma = eur_ok.groupby("equip_id")["minuts"].sum()
te_eur = totals_equip[totals_equip["lliga"] == "EUROLIGA"]
comp = te_eur.set_index("equip_id")["minuts"] * 5
nets = [e for e in comp.index if e[4:] not in equips_traspas]
desviacio = (suma[nets] - comp[nets]).abs().max()
print(f"Euroliga: {len(nets)} equips sense traspassos, desviació màxima minuts jugadors vs 5 x equip -> {desviacio:.1f} min")
punts_rivals = te_eur["rival_punts"].sum() == te_eur["punts"].sum()
print(f"Euroliga: punts a favor totals = punts dels rivals totals -> {punts_rivals}")

# ACB: punts i minuts dels jugadors (per equip) contra els totals de l'equip
acb_j = est[est["lliga"] == "ACB"].groupby("equip_id")[["punts", "minuts"]].sum()
acb_t = totals_acb.set_index("equip_id")
dif_punts = (acb_j["punts"] - acb_t["punts"]).abs().max()
dif_min = (acb_j["minuts"] - 5 * acb_t["minuts"]).abs().max()
print(f"ACB: {len(acb_t)} equips, diferència màxima de punts jugadors vs equip -> {dif_punts}")
print(f"ACB: desviació màxima minuts jugadors vs 5 x equip -> {dif_min:.1f} min")
print(f"ACB: rebots ofensius d'equip no atribuïts a cap jugador -> "
      f"{int(acb_t['reb_of'].sum() - est.loc[est['lliga'] == 'ACB', 'reb_of'].sum())}")

# --- Escriure a DuckDB ---
con = duckdb.connect(str(BD))
taules = {"jugadors": jugadors, "equips": equips, "estadistiques": est, "totals_equip": totals_equip}
for nom, df in taules.items():
    con.register("tmp", df)
    con.execute(f"CREATE OR REPLACE TABLE {nom} AS SELECT * FROM tmp")
    con.unregister("tmp")

print(f"\n=== Base de dades: {BD} ===")
con.sql("""
    SELECT lliga, COUNT(*) AS files, COUNT(DISTINCT jugador_id) AS jugadors,
           COUNT(DISTINCT equip_id) AS equips, SUM(punts) AS punts_totals
    FROM estadistiques GROUP BY lliga ORDER BY lliga
""").show()
con.sql("""
    SELECT j.nom, e.equip_id, e.partits, e.minuts, e.punts
    FROM estadistiques e JOIN jugadors j USING (jugador_id)
    WHERE e.lliga = 'EUROLIGA' ORDER BY e.punts DESC LIMIT 5
""").show()
con.close()
