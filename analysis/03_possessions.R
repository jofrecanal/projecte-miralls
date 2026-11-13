# PT2 · Possessions i estadístiques per 100 possessions (ACB i Euroliga)
# Decisions: D15 (per 100 possessions a pista, 0,44), D18 (totals d'equip i rivals),
#            D19 (jugadors traspassats), D22 (llindar del 15% dels minuts possibles)
# Llegeix data/miralls.duckdb i hi escriu la taula nova `per100` (fora de Git, D10).
library(tidyverse)
library(DBI)

con <- dbConnect(duckdb::duckdb(), "data/miralls.duckdb")

equips_tot <- dbGetQuery(con, "SELECT * FROM totals_equip WHERE lliga IN ('ACB', 'EUROLIGA')")
jug <- dbGetQuery(con, "
  SELECT e.*, j.nom FROM estadistiques e JOIN jugadors j USING (jugador_id)
  WHERE e.lliga IN ('ACB', 'EUROLIGA')")

# --- 1. Possessions de cada equip (D15 i D18) ---
possessions <- function(fga, fta, orb, tov, k = 0.44) fga + k * fta - orb + tov

equips <- equips_tot |>
  mutate(
    fga = t2_int + t3_int, fgm = t2_anot + t3_anot,
    rival_fga = rival_t2_int + rival_t3_int,
    poss_propi = possessions(fga, tl_int, reb_of, perdues),
    poss_rival = possessions(rival_fga, rival_tl_int, rival_reb_of, rival_perdues),
    # Mitjana de les dues quan hi ha rivals (Euroliga); si no, les pròpies (ACB, D18)
    poss = if_else(is.na(poss_rival), poss_propi, (poss_propi + poss_rival) / 2),
    poss_047 = possessions(fga, tl_int, reb_of, perdues, k = 0.47),  # prova de robustesa
    ritme = 40 * poss / minuts,  # possessions per 40 minuts
    # Rebots disponibles quan l'equip falla: exacte amb rivals; si no, tirs de camp fallats (D18)
    reb_disp_of = if_else(is.na(rival_reb_def), fga - fgm, reb_of + rival_reb_def),
    reb_disp_def = reb_def + rival_reb_of,                # només Euroliga
    acaba = fga + 0.44 * tl_int + perdues,                # possessions acabades (usage)
    across(c(poss, poss_047, fgm, reb_disp_of, reb_disp_def, acaba, rival_t2_int),
           ~ .x / minuts, .names = "{.col}_min")           # per minut de partit
  )

# --- 2. Cada fila de jugador amb el seu equip ---
# Euroliga: els traspassats tenen els equips units ("EUR_MCO;PAR"). Fem servir la mitjana
# dels equips per minut, perquè no sabem quants minuts va jugar a cada equip (D19).
per_min <- equips |> select(equip_id, ends_with("_min"))
context <- jug |>
  distinct(equip_id, lliga) |>
  mutate(codi = str_remove(equip_id, "^EUR_|^ACB_"),
         prefix = str_extract(equip_id, "^[A-Z]+_")) |>
  separate_rows(codi, sep = ";") |>
  mutate(equip_unic = paste0(prefix, codi)) |>
  left_join(per_min, by = c("equip_unic" = "equip_id")) |>
  group_by(equip_id) |>
  summarise(across(ends_with("_min"), mean), .groups = "drop")

# Possessions i oportunitats del jugador a pista: minuts del jugador × valor per minut de l'equip
files <- jug |>
  left_join(context, by = "equip_id") |>
  mutate(
    fga = t2_int + t3_int, fgm = t2_anot + t3_anot,
    poss_pista = minuts * poss_min,
    poss_pista_047 = minuts * poss_047_min,
    fg_comp = minuts * fgm_min - fgm,          # tirs anotats pels companys a pista (AST%)
    reb_of_disp = minuts * reb_disp_of_min,
    reb_def_disp = minuts * reb_disp_def_min,
    acaba_equip = minuts * acaba_min,
    t2_rival = minuts * rival_t2_int_min
  )

# --- 3. Una fila per jugador i temporada (a l'ACB, els traspassats tenen dues files) ---
comptadors <- c("partits", "minuts", "punts", "t2_anot", "t2_int", "t3_anot", "t3_int",
                "tl_anot", "tl_int", "reb_of", "reb_def", "assist", "robatoris", "perdues",
                "taps", "faltes", "fga", "fgm", "poss_pista", "poss_pista_047", "fg_comp",
                "reb_of_disp", "reb_def_disp", "acaba_equip", "t2_rival")

minuts_possibles <- c(ACB = 34 * 40, EUROLIGA = 38 * 40)  # temporada regular 2025-26

per100 <- files |>
  group_by(jugador_id, nom, lliga, temporada) |>
  summarise(across(all_of(comptadors), sum),
            equips = paste(equip_id, collapse = ";"),
            traspassat = n() > 1 | any(diversos_equips), .groups = "drop") |>
  mutate(
    # Per 100 possessions a pista (D15)
    across(c(punts, t2_int, t3_int, tl_int, reb_of, reb_def, assist, robatoris, perdues, taps),
           ~ 100 * .x / poss_pista, .names = "{.col}_100"),
    punts_100_047 = 100 * punts / poss_pista_047,
    # Percentatges sobre les oportunitats a pista (fórmules de Basketball-Reference)
    usg = 100 * (fga + 0.44 * tl_int + perdues) / acaba_equip,
    ast_pct = 100 * assist / fg_comp,
    orb_pct = 100 * reb_of / reb_of_disp,
    drb_pct = 100 * reb_def / reb_def_disp,   # NA a l'ACB fins que tinguem els rivals (D18)
    stl_pct = 100 * robatoris / poss_pista,   # possessions del rival ≈ pròpies (D18)
    blk_pct = 100 * taps / t2_rival,          # NA a l'ACB fins que tinguem els rivals
    ts_pct = 100 * punts / (2 * (fga + 0.44 * tl_int)),
    pct_minuts = minuts / minuts_possibles[lliga],
    supera_llindar = pct_minuts >= 0.15       # D22
  )

# --- 4. Controls ---
cat("\n=== Ritme (possessions per 40 minuts) ===\n")
equips |> group_by(lliga) |>
  summarise(equips = n(), ritme_mitja = mean(ritme), minim = min(ritme), maxim = max(ritme),
            dif_propi_rival_pct = mean(100 * (poss_rival - poss_propi) / poss_propi)) |>
  print()

cat("\n=== Possessions a pista dels jugadors vs 5 × possessions de l'equip ===\n")
cat("(només equips sense jugadors traspassats en una fila conjunta)\n")
equips_traspas <- files |> filter(diversos_equips) |>
  mutate(codi = str_remove(equip_id, "^EUR_")) |> separate_rows(codi, sep = ";") |>
  pull(codi) |> unique()
files |> filter(!diversos_equips, !str_remove(equip_id, "^EUR_|^ACB_") %in% equips_traspas) |>
  group_by(lliga, equip_id) |> summarise(suma = sum(poss_pista), .groups = "drop") |>
  left_join(equips |> select(equip_id, poss), by = "equip_id") |>
  group_by(lliga) |> summarise(desviacio_max_pct = max(abs(suma / (5 * poss) - 1)) * 100) |>
  print()

cat("\n=== Jugadors que superen el llindar (15% dels minuts possibles) ===\n")
per100 |> count(lliga, supera_llindar) |> print()

cat("\n=== Prova de robustesa: rànquing de punts per 100 amb 0,44 i amb 0,47 ===\n")
per100 |> filter(supera_llindar) |> group_by(lliga) |>
  summarise(spearman = cor(punts_100, punts_100_047, method = "spearman")) |> print()

cat("\n=== Top 5 d'usage per lliga (jugadors per sobre del llindar) ===\n")
per100 |> filter(supera_llindar) |> group_by(lliga) |> slice_max(usg, n = 5) |>
  select(lliga, nom, minuts, usg, punts_100, ast_pct, ts_pct) |>
  mutate(across(where(is.double), ~ round(.x, 1))) |> print(n = 10)

# --- 5. Guardar a DuckDB ---
dbWriteTable(con, "per100", per100, overwrite = TRUE)
cat("\nTaula per100 guardada:", nrow(per100), "files\n")
dbDisconnect(con, shutdown = TRUE)
