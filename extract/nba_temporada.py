"""
PT1 · Extractor de la NBA per a una temporada.
Ús: python extract/nba_temporada.py [temporada, p. ex. 2024-25]
"""
import sys
import time
from datetime import date
from pathlib import Path

from nba_api.stats.endpoints import leaguedashplayerstats

TEMPORADA_PER_DEFECTE = "2025-26"
CARPETA_RAW = Path("data/raw/nba")


def descarregar_temporada(temporada):
    print(f"Descarregant NBA {temporada} (temporada regular)...")
    resposta = leaguedashplayerstats.LeagueDashPlayerStats(
        season=temporada,
        season_type_all_star="Regular Season",
        per_mode_detailed="Totals",
        timeout=60,
    )
    time.sleep(1)  # peticions lentes i respectuoses
    return resposta.get_data_frames()[0]


def main():
    temporada = sys.argv[1] if len(sys.argv) > 1 else TEMPORADA_PER_DEFECTE
    df = descarregar_temporada(temporada)
    df["SEASON"] = temporada
    df["LEAGUE"] = "NBA"
    df["EXTRACTED_AT"] = date.today().isoformat()

    CARPETA_RAW.mkdir(parents=True, exist_ok=True)
    fitxer = CARPETA_RAW / f"nba_jugadors_{temporada}.csv"
    df.to_csv(fitxer, index=False)

    print(f"\nFet! {len(df)} jugadors, {df.shape[1]} columnes -> {fitxer}")
    print("\nTop 5 anotadors (punts totals):")
    for _, f in df.sort_values("PTS", ascending=False).head(5).iterrows():
        print(f"  {f['PLAYER_NAME']:<28} {f['TEAM_ABBREVIATION']:<4} "
              f"{int(f['PTS']):>5} pts en {int(f['GP'])} partits")


if __name__ == "__main__":
    main()
