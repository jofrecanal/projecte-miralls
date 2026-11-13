# PT2 · Dimensions d'estil i de nivell (ACB i Euroliga)
# Decisions: D20 (z-scores dins de cada lliga i temporada, limitats a ±3),
#            D21 (shrinkage beta-binomial amb el volum a la prior), D22 (llindar),
#            D23 (usage a l'estil; rebot defensiu i taps per 100 possessions)
# Llegeix la taula per100 (analysis/03_possessions.R) i escriu `variables_z` i `dimensions`.
library(tidyverse)
library(DBI)

con <- dbConnect(duckdb::duckdb(), "data/miralls.duckdb")
per100 <- dbGetQuery(con, "SELECT * FROM per100")

# --- 1. Shrinkage dels percentatges de tir (D21) ---
# Regressió beta-binomial: la mitjana de la prior depèn del log dels intents,
# perquè els bons tiradors són els que tiren més. Es calcula per lliga i temporada.
ajusta_prior <- function(anot, intents) {
  ok <- intents > 0
  x <- anot[ok]; n <- intents[ok]
  logverosimilitud <- function(par) {
    mu <- plogis(par[1] + par[2] * log(n))
    phi <- exp(par[3])
    a <- mu * phi; b <- (1 - mu) * phi
    -sum(lchoose(n, x) + lbeta(x + a, n - x + b) - lbeta(a, b))
  }
  # Límits perquè la prior no degeneri amb els jugadors que gairebé no tiren (p. ex. pivots al triple)
  inici <- c(qlogis(sum(x) / sum(n)), 0, log(50))
  fit <- optim(inici, logverosimilitud, method = "L-BFGS-B",
               lower = c(-5, -0.5, log(2)), upper = c(5, 0.5, log(5000)))
  list(a = fit$par[1], b = fit$par[2], phi = exp(fit$par[3]), convergeix = fit$convergence == 0)
}

encongeix <- function(anot, intents, prior) {
  mu <- plogis(prior$a + prior$b * log(pmax(intents, 1)))
  (anot + mu * prior$phi) / (intents + prior$phi)
}

tirs <- list(t2 = c("t2_anot", "t2_int"), t3 = c("t3_anot", "t3_int"), tl = c("tl_anot", "tl_int"))
priors <- list()

per100 <- per100 |>
  group_by(lliga, temporada) |>
  group_modify(function(d, clau) {
    for (t in names(tirs)) {
      p <- ajusta_prior(d[[tirs[[t]][1]]], d[[tirs[[t]][2]]])
      priors[[paste(clau$lliga, clau$temporada, t)]] <<- c(clau, p)
      d[[paste0(t, "_pct_eb")]] <- 100 * encongeix(d[[tirs[[t]][1]]], d[[tirs[[t]][2]]], p)
    }
    d
  }) |>
  ungroup() |>
  mutate(
    # True shooting amb els percentatges encongits: punts esperats / (2 · intents de tir)
    ts_eb = 100 * (2 * t2_int * t2_pct_eb / 100 + 3 * t3_int * t3_pct_eb / 100 +
                     tl_int * tl_pct_eb / 100) / (2 * (fga + 0.44 * tl_int))
  )

cat("\n=== Priors del shrinkage (mitjana per a 10 i 200 intents, força phi) ===\n")
bind_rows(lapply(priors, as_tibble), .id = "clau") |>
  mutate(tir = str_extract(clau, "\\w+$"),
         mitjana_10 = 100 * plogis(a + b * log(10)),
         mitjana_200 = 100 * plogis(a + b * log(200))) |>
  select(lliga, tir, mitjana_10, mitjana_200, phi, convergeix) |>
  mutate(across(where(is.double), ~ round(.x, 1))) |> print()

# --- 2. Variables d'estil i de nivell ---
dimensions <- tribble(
  ~variable,         ~dimensio,             ~tipus,
  "t3_rati",         "Dieta de tir",        "estil",
  "tl_rati",         "Dieta de tir",        "estil",
  "ast_pct",         "Creació",             "estil",
  "ast_perd",        "Creació",             "estil",
  "orb_pct",         "Rebot",               "estil",
  "reb_def_100",     "Rebot",               "estil",
  "robatoris_100",   "Activitat defensiva", "estil",
  "taps_100",        "Activitat defensiva", "estil",
  "usg",             "Pes a l'atac",        "estil",
  "ts_eb",           "Nivell",              "nivell",
  "t3_pct_eb",       "Nivell",              "nivell",
  "tl_pct_eb",       "Nivell",              "nivell",
  "punts_100",       "Nivell",              "nivell",
  "pct_minuts",      "Nivell",              "nivell"
)

vars <- per100 |>
  mutate(
    t3_rati = 100 * t3_int / fga,                       # proporció de triples entre els tirs de camp
    tl_rati = 100 * tl_int / fga,                       # tirs lliures provocats per tir de camp
    ast_perd = log((assist + 1) / (perdues + 1))        # relació assistències/pèrdues (escala log)
  )

# --- 3. Z-scores dins de cada lliga i temporada (D20) ---
# Mitjana i desviació amb els jugadors que superen el llindar (D22); limitats a ±3.
z <- function(x, ref) pmin(pmax((x - mean(x[ref], na.rm = TRUE)) / sd(x[ref], na.rm = TRUE), -3), 3)

variables_z <- vars |>
  group_by(lliga, temporada) |>
  mutate(across(all_of(dimensions$variable), ~ z(.x, supera_llindar), .names = "z_{.col}")) |>
  ungroup() |>
  select(jugador_id, nom, lliga, temporada, equips, traspassat, minuts, supera_llindar,
         all_of(dimensions$variable), starts_with("z_"), t2_pct_eb)

# --- 4. Controls ---
cat("\n=== Shrinkage: els 5 jugadors amb més triples encertats en percentatge (ACB) ===\n")
variables_z |> filter(lliga == "ACB", supera_llindar) |>
  left_join(per100 |> select(jugador_id, t3_anot, t3_int), by = "jugador_id") |>
  mutate(t3_brut = 100 * t3_anot / t3_int) |>
  slice_max(t3_pct_eb, n = 5) |>
  select(nom, t3_anot, t3_int, t3_brut, t3_pct_eb) |>
  mutate(across(where(is.double), ~ round(.x, 1))) |> print()

cat("\n=== Correlacions entre variables d'estil (jugadors per sobre del llindar) ===\n")
variables_z |> filter(supera_llindar) |>
  select(starts_with("z_") & any_of(paste0("z_", dimensions$variable[dimensions$tipus == "estil"]))) |>
  cor(use = "pairwise.complete.obs") |> round(2) |> print()

# Validació de la D20: els jugadors dels equips ACB que juguen l'Euroliga surten a les dues
# lligues. Si estandarditzar dins de cada lliga funciona, el seu estil s'hi ha d'assemblar.
normalitza <- function(nom) {
  nom <- if_else(str_detect(nom, ","), str_replace(nom, "^(.*),\\s*(.*)$", "\\2 \\1"), nom)
  nom |> stringi::stri_trans_general("Latin-ASCII") |> str_to_lower() |> str_squish()
}
parells <- variables_z |> filter(supera_llindar) |>
  mutate(clau = normalitza(nom)) |>
  add_count(lliga, clau) |> filter(n == 1) |>   # fora els noms repetits (dos Jaime Fernández)
  select(clau, lliga, starts_with("z_")) |>
  pivot_longer(starts_with("z_"), names_to = "variable", values_to = "z") |>
  pivot_wider(names_from = lliga, values_from = z) |>
  filter(!is.na(ACB), !is.na(EUROLIGA))

cat("\n=== Mateix jugador a l'ACB i a l'Euroliga: correlació dels z-scores ===\n")
cat("Jugadors trobats a totes dues lligues:", n_distinct(parells$clau), "\n")
parells |> group_by(variable) |>
  summarise(correlacio = round(cor(ACB, EUROLIGA, use = "complete.obs"), 2)) |>
  arrange(desc(correlacio)) |> print(n = 20)

# --- 5. Guardar a DuckDB ---
dbWriteTable(con, "variables_z", variables_z, overwrite = TRUE)
dbWriteTable(con, "dimensions", dimensions, overwrite = TRUE)
cat("\nTaules guardades: variables_z (", nrow(variables_z), "files) i dimensions (",
    nrow(dimensions), "variables)\n")
dbDisconnect(con, shutdown = TRUE)
