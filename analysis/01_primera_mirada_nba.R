# PT1 · Primera mirada a les dades de la NBA 2025-26
library(tidyverse)

nba <- read_csv("data/raw/nba/nba_jugadors_2025-26.csv")

# Només jugadors amb un mínim de partits; valors per partit
nba_filtrat <- nba |>
  filter(GP >= 20) |>
  mutate(PPG = PTS / GP, APG = AST / GP)

ggplot(nba_filtrat, aes(x = APG, y = PPG)) +
  geom_point(alpha = 0.4) +
  geom_text(
    data = slice_max(nba_filtrat, PPG, n = 8),
    aes(label = PLAYER_NAME), vjust = -0.8, size = 3
  ) +
  labs(
    title = "NBA 2025-26: anotació i creació",
    x = "Assistències per partit", y = "Punts per partit"
  ) +
  theme_minimal()