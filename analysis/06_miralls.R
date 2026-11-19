# analysis/06_miralls.R
# PT3 · Motor de miralls (D3, D22, D24, D25, D26)
# - Distància euclidiana ponderada sobre els z-scores: cada dimensió pesa igual (D24).
# - Distància total = 80% estil + 20% nivell (D3).
# - Filtre de posició i alçada (D26): fora exterior <-> interior; alçada a ±7 cm
#   (s'amplia de 5 en 5 cm si queden menys de N_TOP + 1 candidats).
# - Comparació amb Mahalanobis i PCA (només estil): coincidència del top 3.
# - Validació: els jugadors que juguen ACB i Euroliga s'haurien de trobar a si mateixos.
# - Resultat: taula `miralls` a DuckDB (top 3 en totes dues direccions, sense el mateix jugador).

library(DBI)
library(dplyr)
library(tidyr)
library(purrr)
library(stringr)
library(stringi)

TEMPORADA    <- "2025-26"
W_ESTIL      <- 0.8   # D3
N_TOP        <- 3
MARGE_ALCADA <- 7     # cm (D26)

con <- dbConnect(duckdb::duckdb(), "data/miralls.duckdb")

dims <- dbGetQuery(con, "SELECT * FROM dimensions")
vz   <- dbGetQuery(con, "SELECT * FROM variables_z WHERE temporada = ?",
                   params = list(TEMPORADA))
pl   <- dbGetQuery(con, "SELECT jugador_id, posicio, grup, alcada_cm FROM plantilles")

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

# 2. Jugadors que superen el llindar (D22), amb posició i alçada ----------------
jug <- vz |> filter(supera_llindar) |> left_join(pl, by = "jugador_id")
cat("\n== Jugadors per sobre del llindar ==\n")
print(count(jug, lliga, grup))

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

# 3b. Filtre de posició i alçada (D26) ------------------------------------------
compatibles <- function(g1, g2) {
  is.na(g1) | is.na(g2) |
    !((g1 == "exterior" & g2 == "interior") | (g1 == "interior" & g2 == "exterior"))
}
G <- outer(acb$grup, eur$grup, compatibles)
H <- abs(outer(acb$alcada_cm, eur$alcada_cm, "-"))
filtre <- function(marge) G & (is.na(H) | H <= marge)

# Cada direcció amplia el marge només per als seus propis jugadors:
# permes_ae (files = jugadors de l'ACB) i permes_ea (columnes = jugadors de l'Euroliga)
base <- filtre(MARGE_ALCADA)
curts_f0 <- sum(rowSums(base) < N_TOP + 1)
curts_c0 <- sum(colSums(base) < N_TOP + 1)
permes_ae <- base
permes_ea <- base
for (marge in seq(MARGE_ALCADA + 5, 60, by = 5)) {
  curts_f <- rowSums(permes_ae) < N_TOP + 1
  curts_c <- colSums(permes_ea) < N_TOP + 1
  if (!any(curts_f) && !any(curts_c)) break
  nou <- filtre(marge)
  permes_ae[curts_f, ] <- nou[curts_f, ]
  permes_ea[, curts_c] <- nou[, curts_c]
}
permes <- base
dimnames(permes) <- dimnames(permes_ae) <- dimnames(permes_ea) <- dimnames(d_total)
aplica <- function(D, P) { D[!P] <- Inf; D }
d_total_f    <- aplica(d_total, permes_ae)   # ACB -> Euroliga
d_total_f_ea <- aplica(d_total, permes_ea)   # Euroliga -> ACB

fora_top3 <- function(D, P) {
  f <- function(D, P) mean(sapply(seq_len(nrow(D)),
                                  function(i) mean(!P[i, order(D[i, ])[1:N_TOP]])))
  mean(c(f(D, P), f(t(D), t(P))))
}
cat("\n== Filtre de posició i alçada (D26) ==\n")
cat(sprintf("Parells permesos: %.0f%%\n", 100 * mean(permes)))
cat(sprintf("Jugadors amb marge ampliat: %d de l'ACB i %d de l'Euroliga\n", curts_f0, curts_c0))
cat(sprintf("Miralls del top 3 sense filtre que el filtre exclou: %.1f%%\n",
            100 * fora_top3(d_total, permes)))

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

# 5. Jugadors que juguen totes dues competicions --------------------------------
# 5a. Per nom normalitzat (sense accents, paraules ordenades)
clau_nom <- function(x) {
  x |> stri_trans_general("Latin-ASCII") |> str_to_lower() |>
    str_replace_all("[^a-z]+", " ") |> str_squish() |>
    str_split(" ") |> map_chr(~ paste(sort(.x), collapse = " "))
}
parells <- inner_join(
  vz |> filter(lliga == "ACB")      |> transmute(acb_id = jugador_id, nom_acb = nom, clau = clau_nom(nom)),
  vz |> filter(lliga == "EUROLIGA") |> transmute(eur_id = jugador_id, nom_eur = nom, clau = clau_nom(nom)),
  by = "clau", relationship = "many-to-many")

# 5b. Per cognom i inicial dins dels equips de totes dues competicions (D25)
equips_dobles <- tibble::tribble(
  ~patro_acb,    ~codi_eur,
  "real-madrid", "MAD",
  "barc",        "BAR",
  "valencia",    "PAM",
  "baskonia",    "BAS")
codi_doble <- function(equips, lliga) {
  map2_chr(equips, lliga, function(e, l) {
    hit <- if (l == "ACB") str_detect(e, fixed(equips_dobles$patro_acb))
           else str_detect(e, paste0("(EUR_|;)", equips_dobles$codi_eur, "\\b"))
    if (any(hit)) equips_dobles$codi_eur[which(hit)[1]] else NA_character_
  })
}
norm_nom <- function(x) {
  x |> stri_trans_general("Latin-ASCII") |> str_to_lower() |>
    str_replace_all("[^a-z, ]+", " ") |> str_squish()
}
clau_cognom <- function(nom, lliga) {
  n <- norm_nom(nom)
  ifelse(lliga == "EUROLIGA",
         paste(str_trim(str_remove(n, ",.*")), str_sub(str_trim(str_remove(n, "^[^,]*,")), 1, 1)),
         paste(str_remove(n, "^\\S+\\s*"), str_sub(n, 1, 1)))
}
dobles <- vz |>
  mutate(codi = codi_doble(equips, lliga), clau2 = clau_cognom(nom, lliga)) |>
  filter(!is.na(codi))
parells_cognom <- inner_join(
  dobles |> filter(lliga == "ACB")      |> transmute(acb_id = jugador_id, nom_acb = nom, codi, clau2),
  dobles |> filter(lliga == "EUROLIGA") |> transmute(eur_id = jugador_id, nom_eur = nom, codi, clau2),
  by = c("codi", "clau2"), relationship = "many-to-many")
nous <- anti_join(parells_cognom, parells, by = c("acb_id", "eur_id"))
parells <- bind_rows(parells |> select(acb_id, nom_acb, eur_id, nom_eur),
                     nous   |> select(acb_id, nom_acb, eur_id, nom_eur)) |>
  distinct(acb_id, eur_id, .keep_all = TRUE)
dup <- parells |> filter(duplicated(acb_id) | duplicated(eur_id))
if (nrow(dup) > 0) { print(dup); warning("Hi ha jugadors emparellats més d'un cop") }

parells_ll <- parells |> filter(acb_id %in% acb$jugador_id, eur_id %in% eur$jugador_id)
cat(sprintf("\n== Jugadors a totes dues competicions: %d (superen el llindar a totes dues: %d) ==\n",
            nrow(parells), nrow(parells_ll)))
cat(sprintf("   ... dels quals el filtre exclou el parell amb ell mateix: %d\n",
            sum(!permes[cbind(parells_ll$acb_id, parells_ll$eur_id)])))

# 6. Validació: on queda el mateix jugador a l'altra lliga? ---------------------
rang_propi <- function(D, p, D_ea = D) {
  r_ae <- map2_int(p$acb_id, p$eur_id, ~ as.integer(rank(D[.x, ], ties.method = "min")[.y]))
  r_ea <- map2_int(p$acb_id, p$eur_id, ~ as.integer(rank(D_ea[, .y], ties.method = "min")[.x]))
  tibble(direccio = c("ACB -> Euroliga", "Euroliga -> ACB"),
         top1    = c(mean(r_ae == 1), mean(r_ea == 1)),
         top3    = c(mean(r_ae <= 3), mean(r_ea <= 3)),
         mediana = c(median(r_ae), median(r_ea)))
}
metodes <- list(principal_filtrat = d_total_f, principal_total = d_total,
                principal_estil = d_estil, mahalanobis = d_mahal, pca = d_pca)
validacio <- imap_dfr(metodes, ~ rang_propi(.x, parells_ll,
                                            if (.y == "principal_filtrat") d_total_f_ea else .x) |> mutate(metode = .y, .before = 1))
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

# 8. Taula de miralls amb el filtre (sense el mateix jugador) -------------------
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
m_ae <- taula_miralls(d_total_f, d_estil, d_nivell,
                      parells |> transmute(origen_id = acb_id, desti_id = eur_id))
m_ea <- taula_miralls(t(d_total_f_ea), t(d_estil), t(d_nivell),
                      parells |> transmute(origen_id = eur_id, desti_id = acb_id))

info <- jug |> select(jugador_id, nom, lliga, equips, posicio, alcada_cm)
miralls <- bind_rows(m_ae, m_ea) |>
  left_join(info, by = "jugador_id") |>
  left_join(info |> rename(mirall_id = jugador_id, mirall_nom = nom, mirall_lliga = lliga,
                           mirall_equips = equips, mirall_posicio = posicio,
                           mirall_alcada_cm = alcada_cm),
            by = "mirall_id") |>
  mutate(temporada = TEMPORADA, metode = "euclidiana_ponderada_filtre") |>
  relocate(jugador_id, nom, lliga, equips, posicio, alcada_cm, rang,
           mirall_id, mirall_nom, mirall_lliga, mirall_equips, mirall_posicio, mirall_alcada_cm)

if (any(!is.finite(miralls$d_total))) warning("Hi ha miralls amb distància infinita")
dbWriteTable(con, "miralls", miralls, overwrite = TRUE)
cat(sprintf("\n== Taula miralls: %d files (%d jugadors) ==\n",
            nrow(miralls), n_distinct(miralls$jugador_id)))

cat("\n== Distància total del primer mirall ==\n")
print(summary(miralls$d_total[miralls$rang == 1]))

# 9. Exemples: els 3 jugadors amb més usage de cada lliga -----------------------
veure_miralls <- function(patro) {
  miralls |>
    filter(str_detect(nom, fixed(patro, ignore_case = TRUE))) |>
    select(nom, posicio, alcada_cm, rang, mirall_nom, mirall_posicio, mirall_alcada_cm,
           d_total, d_estil, d_nivell) |>
    mutate(across(starts_with("d_"), ~ round(.x, 2))) |> as.data.frame()
}
cat("\n== Exemples ==\n")
jug |> group_by(lliga) |> slice_max(usg, n = 3) |> pull(nom) |>
  walk(~ print(veure_miralls(.x)))

dbDisconnect(con, shutdown = TRUE)
