# analysis/06_miralls.R
# PT3 · Motor de miralls, MVP (D3, D22, D24)
# - Distància euclidiana ponderada sobre els z-scores: cada dimensió pesa igual.
# - Similitud total = 80% estil + 20% nivell (D3), en forma de distància.
# - Comparació amb Mahalanobis i PCA (només estil): coincidència del top 3.
# - Validació: els jugadors que juguen ACB i Euroliga s'haurien de trobar a si mateixos.
# - Resultat: taula `miralls` a DuckDB (top 3 en totes dues direccions, sense el mateix jugador).

library(DBI)
library(dplyr)
library(tidyr)
library(purrr)
library(stringr)
library(stringi)

TEMPORADA <- "2025-26"
W_ESTIL   <- 0.8   # D3
N_TOP     <- 3

con <- dbConnect(duckdb::duckdb(), "data/miralls.duckdb")

dims <- dbGetQuery(con, "SELECT * FROM dimensions")
vz   <- dbGetQuery(con, "SELECT * FROM variables_z WHERE temporada = ?",
                   params = list(TEMPORADA))

# 1. Pesos: cada variable val 1 / (variables de la seva dimensió) ---------------
pesos <- dims |>
  group_by(tipus, dimensio) |>
  mutate(pes = 1 / n()) |>
  ungroup() |>
  mutate(col = paste0("z_", variable))
pesos_estil  <- pesos |> filter(tipus == "estil")
pesos_nivell <- pesos |> filter(tipus == "nivell")
cat("\n== Pesos ==\n")
print(pesos |> select(tipus, dimensio, variable, pes), n = Inf)

# 2. Jugadors que superen el llindar (D22) --------------------------------------
jug <- vz |> filter(supera_llindar)
cat("\n== Jugadors per sobre del llindar ==\n")
print(count(jug, lliga))

n_na <- colSums(is.na(jug[pesos$col]))
if (any(n_na > 0)) { print(n_na[n_na > 0]); stop("Hi ha valors NA a les variables z") }

acb <- jug |> filter(lliga == "ACB")
eur <- jug |> filter(lliga == "EUROLIGA")
mat <- function(df, p) as.matrix(df[p$col])

# Distància euclidiana ponderada entre les files de A i les de B
dist_ponderada <- function(A, B, w = rep(1, ncol(A))) {
  A  <- sweep(A, 2, sqrt(w), `*`)
  B  <- sweep(B, 2, sqrt(w), `*`)
  d2 <- outer(rowSums(A^2), rowSums(B^2), "+") - 2 * A %*% t(B)
  D  <- sqrt(pmax(d2, 0) / sum(w))
  dimnames(D) <- list(acb$jugador_id, eur$jugador_id)
  D
}

# 3. Mètode principal (D24) -----------------------------------------------------
d_estil  <- dist_ponderada(mat(acb, pesos_estil),  mat(eur, pesos_estil),  pesos_estil$pes)
d_nivell <- dist_ponderada(mat(acb, pesos_nivell), mat(eur, pesos_nivell), pesos_nivell$pes)
d_total  <- W_ESTIL * d_estil + (1 - W_ESTIL) * d_nivell

# 4. Mètodes de comparació (només estil) ----------------------------------------
Z_estil <- rbind(mat(acb, pesos_estil), mat(eur, pesos_estil))

# Mahalanobis amb la covariància conjunta de les dues lligues
Rinv    <- solve(chol(cov(Z_estil)))
d_mahal <- dist_ponderada(mat(acb, pesos_estil) %*% Rinv, mat(eur, pesos_estil) %*% Rinv)

# PCA: components fins al 80% de la variància
pca      <- prcomp(Z_estil, center = TRUE, scale. = FALSE)
var_acum <- cumsum(pca$sdev^2) / sum(pca$sdev^2)
k        <- which(var_acum >= 0.8)[1]
cat(sprintf("\n== PCA: %d components expliquen el %.0f%% de la variància d'estil ==\n",
            k, 100 * var_acum[k]))
d_pca <- dist_ponderada(predict(pca, mat(acb, pesos_estil))[, 1:k, drop = FALSE],
                        predict(pca, mat(eur, pesos_estil))[, 1:k, drop = FALSE])

# 5. Jugadors que juguen totes dues competicions (per nom) ----------------------
clau_nom <- function(x) {
  x |> stri_trans_general("Latin-ASCII") |> str_to_lower() |>
    str_replace_all("[^a-z]+", " ") |> str_squish() |>
    str_split(" ") |> map_chr(~ paste(sort(.x), collapse = " "))
}
parells <- inner_join(
  vz |> filter(lliga == "ACB")      |> transmute(acb_id = jugador_id, nom_acb = nom, clau = clau_nom(nom)),
  vz |> filter(lliga == "EUROLIGA") |> transmute(eur_id = jugador_id, nom_eur = nom, clau = clau_nom(nom)),
  by = "clau", relationship = "many-to-many")
parells_ll <- parells |> filter(acb_id %in% acb$jugador_id, eur_id %in% eur$jugador_id)
cat(sprintf("\n== Jugadors a totes dues competicions: %d (superen el llindar a totes dues: %d) ==\n",
            nrow(parells), nrow(parells_ll)))

# 6. Validació: on queda el mateix jugador a l'altra lliga? ---------------------
rang_propi <- function(D, p) {
  r_ae <- map2_int(p$acb_id, p$eur_id, ~ as.integer(rank(D[.x, ], ties.method = "min")[.y]))
  r_ea <- map2_int(p$acb_id, p$eur_id, ~ as.integer(rank(D[, .y], ties.method = "min")[.x]))
  tibble(direccio = c("ACB -> Euroliga", "Euroliga -> ACB"),
         top1    = c(mean(r_ae == 1), mean(r_ea == 1)),
         top3    = c(mean(r_ae <= 3), mean(r_ea <= 3)),
         mediana = c(median(r_ae), median(r_ea)))
}
metodes <- list(principal_total = d_total, principal_estil = d_estil,
                mahalanobis = d_mahal, pca = d_pca)
validacio <- imap_dfr(metodes, ~ rang_propi(.x, parells_ll) |> mutate(metode = .y, .before = 1))
cat("\n== Validació: es troben a si mateixos? ==\n")
print(validacio |> mutate(across(c(top1, top3), ~ round(.x, 2))), n = Inf)

# 7. Coincidència del top 3 entre mètodes (estil) -------------------------------
top_ids <- function(D) apply(D, 1, function(r) names(sort(r))[1:N_TOP], simplify = FALSE)
coincidencia <- function(D1, D2) {
  f <- function(A, B) mean(map2_dbl(top_ids(A), top_ids(B),
                                    ~ length(intersect(.x, .y)) / N_TOP))
  mean(c(f(D1, D2), f(t(D1), t(D2))))
}
cat("\n== Coincidència del top 3 amb el mètode principal (estil) ==\n")
print(tibble(metode = c("mahalanobis", "pca"),
             coincidencia = round(c(coincidencia(d_estil, d_mahal),
                                    coincidencia(d_estil, d_pca)), 2)))

# 8. Taula de miralls (sense el mateix jugador) ---------------------------------
taula_miralls <- function(D, De, Dn, excloure) {
  map_dfr(rownames(D), function(id) {
    d    <- D[id, ]
    d    <- d[!names(d) %in% excloure$desti_id[excloure$origen_id == id]]
    top  <- names(sort(d))[1:N_TOP]
    tibble(jugador_id = id, rang = seq_len(N_TOP), mirall_id = top,
           d_total = unname(d[top]), d_estil = unname(De[id, top]),
           d_nivell = unname(Dn[id, top]))
  })
}
m_ae <- taula_miralls(d_total, d_estil, d_nivell,
                      parells |> transmute(origen_id = acb_id, desti_id = eur_id))
m_ea <- taula_miralls(t(d_total), t(d_estil), t(d_nivell),
                      parells |> transmute(origen_id = eur_id, desti_id = acb_id))

info <- jug |> select(jugador_id, nom, lliga, equips)
miralls <- bind_rows(m_ae, m_ea) |>
  left_join(info, by = "jugador_id") |>
  left_join(info |> rename(mirall_id = jugador_id, mirall_nom = nom,
                           mirall_lliga = lliga, mirall_equips = equips),
            by = "mirall_id") |>
  mutate(temporada = TEMPORADA, metode = "euclidiana_ponderada") |>
  relocate(jugador_id, nom, lliga, equips, rang, mirall_id, mirall_nom, mirall_lliga, mirall_equips)

dbWriteTable(con, "miralls", miralls, overwrite = TRUE)
cat(sprintf("\n== Taula miralls: %d files (%d jugadors) ==\n",
            nrow(miralls), n_distinct(miralls$jugador_id)))

cat("\n== Distància total del primer mirall ==\n")
print(summary(miralls$d_total[miralls$rang == 1]))

# 9. Exemples: els 3 jugadors amb més usage de cada lliga -----------------------
veure_miralls <- function(patro) {
  miralls |>
    filter(str_detect(nom, fixed(patro, ignore_case = TRUE))) |>
    select(nom, lliga, rang, mirall_nom, mirall_equips, d_total, d_estil, d_nivell) |>
    mutate(across(starts_with("d_"), ~ round(.x, 2)))
}
cat("\n== Exemples ==\n")
jug |> group_by(lliga) |> slice_max(usg, n = 3) |> pull(nom) |>
  walk(~ print(veure_miralls(.x)))

dbDisconnect(con, shutdown = TRUE)
