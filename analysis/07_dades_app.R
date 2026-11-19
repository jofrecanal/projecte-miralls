# analysis/07_dades_app.R
# PT3 · Dades de l'app de validació (D27): només el que l'app necessita.
# Miralls (sense distàncies ni res del motor) + box score de temporada + grup de posició.
# Escriu app/validacio/dades_app.rds (fora de Git: conté estadístiques de les lligues).
# Cal tornar-lo a executar cada cop que canviï el motor (06_miralls.R).
library(DBI)
library(dplyr)

con <- dbConnect(duckdb::duckdb(), "data/miralls.duckdb", read_only = TRUE)
miralls <- dbGetQuery(con, "
  SELECT jugador_id, nom, lliga, equips, posicio, alcada_cm, rang,
         mirall_id, mirall_nom, mirall_lliga, mirall_equips, mirall_posicio, mirall_alcada_cm
  FROM miralls")
per100 <- dbGetQuery(con, "
  SELECT jugador_id, partits, minuts, punts, reb_of, reb_def, assist, robatoris, taps,
         perdues, faltes, faltes_reb, t2_anot, t2_int, t3_anot, t3_int, tl_anot, tl_int
  FROM per100")
pl <- dbGetQuery(con, "SELECT jugador_id, grup FROM plantilles")
dbDisconnect(con, shutdown = TRUE)

ids <- union(miralls$jugador_id, miralls$mirall_id)
dades <- list(miralls    = miralls,
              per100     = per100 |> filter(jugador_id %in% ids),
              plantilles = pl |> filter(jugador_id %in% ids))
saveRDS(dades, "app/validacio/dades_app.rds")
cat(sprintf("dades_app.rds: %d miralls, %d jugadors amb box score\n",
            nrow(dades$miralls), nrow(dades$per100)))
