# PT1 · Primer gràfic NBA vs ACB, llegint de DuckDB
library(tidyverse)
library(DBI)

con <- dbConnect(duckdb::duckdb(), "data/miralls.duckdb", read_only = TRUE)

# Sumem per jugador (a l'ACB, qui va canviar d'equip té dues files)
dades <- dbGetQuery(con, "
  SELECT e.jugador_id, j.nom, e.lliga,
         SUM(e.minuts) AS minuts,
         SUM(e.punts)  AS punts,
         SUM(e.assist) AS assist
  FROM estadistiques e
  JOIN jugadors j USING (jugador_id)
  GROUP BY e.jugador_id, j.nom, e.lliga
")
dbDisconnect(con, shutdown = TRUE)

# Valors per 36 minuts (iguala partits de 48 i 40 minuts)
dades36 <- dades |>
  filter(minuts >= 500) |>
  mutate(pts36 = punts / minuts * 36,
         ast36 = assist / minuts * 36)

# Els 5 jugadors més destacats de cada lliga
etiquetes <- dades36 |>
  group_by(lliga) |>
  slice_max(pts36 + ast36, n = 5)

ggplot(dades36, aes(x = ast36, y = pts36, colour = lliga)) +
  geom_point(alpha = 0.5) +
  geom_text(data = etiquetes, aes(label = nom),
            vjust = -0.8, size = 3, show.legend = FALSE) +
  labs(
    title = "NBA i ACB 2025-26: anotació i creació per 36 minuts",
    subtitle = "Jugadors amb 500 minuts o més · temporada regular",
    x = "Assistències per 36 min", y = "Punts per 36 min", colour = "Lliga"
  ) +
  theme_minimal()