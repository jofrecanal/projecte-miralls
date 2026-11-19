# app/validacio/app.R
# PT3 · Validació interactiva dels miralls (D27)
# Mostra un jugador triat a l'atzar (equilibrat per lliga i grup) i els seus 3 miralls
# només amb estadístiques de box score (sense res del motor), en ordre barrejat (A, B, C).
# Cada mirall es valora com a Bo / Dubtós / Dolent, amb un comentari opcional.
# Les valoracions es guarden a analysis/valoracions/valoracions.csv amb el nom de qui valora
# i la versió del motor (sí que van a Git: són criteri propi, no dades de les lligues).
# Ús (Consola de RStudio): shiny::runApp("app/validacio")

library(shiny)
library(DBI)
library(dplyr)
library(readr)

ARREL  <- normalizePath(file.path("..", ".."))
BD     <- file.path(ARREL, "data", "miralls.duckdb")
FITXER <- file.path(ARREL, "analysis", "valoracions", "valoracions.csv")
VERSIO <- "v2: 12 variables d'estil, filtre exterior-interior i ±7 cm (D26)"

# --- Dades: es llegeixen un cop i es tanca la connexió (no bloqueja DuckDB) ---
con <- dbConnect(duckdb::duckdb(), BD, read_only = TRUE)
miralls <- dbGetQuery(con, "SELECT * FROM miralls")
per100  <- dbGetQuery(con, "SELECT * FROM per100")
pl      <- dbGetQuery(con, "SELECT jugador_id, grup FROM plantilles")
dbDisconnect(con, shutdown = TRUE)

neteja_equip <- function(x) {
  x |> gsub("ACB_|EUR_", "", x = _) |> gsub("-[0-9]+", "", x = _) |> gsub(";", " / ", x = _)
}

# Box score per partit (temporada regular)
box <- per100 |>
  transmute(jugador_id,
            PJ = partits, Min = minuts / partits, Pts = punts / partits,
            Reb = (reb_of + reb_def) / partits, RO = reb_of / partits,
            Ast = assist / partits, Rob = robatoris / partits, Tap = taps / partits,
            `Pèr` = perdues / partits, Falt = faltes / partits, `F. reb` = faltes_reb / partits,
            `T2%` = 100 * t2_anot / t2_int, `T3%` = 100 * t3_anot / t3_int,
            `TL%` = 100 * tl_anot / tl_int)

# Fitxa de cada jugador (nom, lliga, equip, posició, alçada)
fitxes <- bind_rows(
  miralls |> distinct(jugador_id, nom, lliga, equips, posicio, alcada_cm),
  miralls |> distinct(jugador_id = mirall_id, nom = mirall_nom, lliga = mirall_lliga,
                      equips = mirall_equips, posicio = mirall_posicio,
                      alcada_cm = mirall_alcada_cm)
) |> distinct(jugador_id, .keep_all = TRUE)

jugadors <- miralls |>
  distinct(jugador_id, nom, lliga) |>
  left_join(pl, by = "jugador_id") |>
  mutate(grup = coalesce(grup, "sense grup"), estrat = paste(lliga, grup))

llegir_valoracions <- function() {
  if (file.exists(FITXER)) {
    read_csv(FITXER, show_col_types = FALSE, col_types = cols(.default = "c"))
  } else {
    tibble(valorador = character(), versio = character(), jugador_id = character(),
           rang = character(), valoracio = character())
  }
}

# A l'atzar però equilibrat: primer una combinació lliga-grup, després un jugador
# que aquesta persona encara no hagi valorat amb aquesta versió del motor
tria <- function(vals, valorador) {
  fets <- vals$jugador_id[vals$versio == VERSIO & vals$valorador == valorador]
  pendents <- jugadors |> filter(!jugador_id %in% fets)
  if (nrow(pendents) == 0) return(NULL)
  e <- sample(unique(pendents$estrat), 1)
  pendents |> filter(estrat == e) |> slice_sample(n = 1)
}

taula_box <- function(ids, etiquetes) {
  tibble(jugador_id = ids, ` ` = etiquetes) |>
    left_join(fitxes, by = "jugador_id") |>
    left_join(box, by = "jugador_id") |>
    mutate(Jugador = nom, Lliga = lliga, Equip = neteja_equip(equips),
           `Posició` = posicio, `Alçada` = alcada_cm) |>
    select(` `, Jugador, Lliga, Equip, `Posició`, `Alçada`, PJ, Min, Pts, Reb, RO, Ast, Rob,
           Tap, `Pèr`, Falt, `F. reb`, `T2%`, `T3%`, `TL%`) |>
    mutate(across(c(Min:`F. reb`), ~ sprintf("%.1f", .x)),
           across(c(`T2%`, `T3%`, `TL%`), ~ ifelse(is.finite(.x), sprintf("%.1f", .x), "-")),
           PJ = as.integer(PJ), `Alçada` = as.integer(`Alçada`))
}

ui <- fluidPage(
  titlePanel("Projecte Miralls · Validació de miralls"),
  p("S'assemblen aquests jugadors? Mira el jugador de dalt i valora cadascun dels tres ",
    "jugadors de l'altra lliga (A, B i C): estil de joc, paper a l'equip i nivell."),
  textInput("valorador", "El teu nom", placeholder = "Obligatori per desar"),
  p(textOutput("estat")),
  h3(textOutput("titol")),
  tableOutput("box"),
  p(em("Mitjanes per partit, temporada regular 2025-26. PJ: partits jugats. ",
       "RO: rebots ofensius. Pèr: pèrdues. Falt: faltes comeses. F. reb: faltes rebudes.")),
  uiOutput("valoracions_ui"),
  actionButton("desa", "Desa i següent", class = "btn-primary"),
  actionButton("salta", "Salta aquest jugador"),
  hr(),
  h4("Les teves valoracions"),
  tableOutput("resum"),
  p(em("Dades: acb.com i Euroleague. Ús personal i no comercial."))
)

server <- function(input, output, session) {
  vals   <- reactiveVal(llegir_valoracions())
  actual <- reactiveVal(NULL)
  ordre  <- reactiveVal(NULL)
  n      <- reactiveVal(0)
  nom_valorador <- reactive(trimws(input$valorador))

  seguent <- function() {
    isolate({
      actual(tria(vals(), nom_valorador()))
      ordre(sample(3))
      n(n() + 1)
    })
  }
  seguent()
  id <- function(prefix, i) paste0(prefix, i, "_", n())

  # Miralls del jugador actual, en l'ordre barrejat que es mostra (A, B, C)
  mostrats <- reactive({
    req(actual())
    m <- miralls |> filter(jugador_id == actual()$jugador_id) |> arrange(rang)
    m <- m[ordre()[seq_len(nrow(m))], ]
    m$lletra <- LETTERS[seq_len(nrow(m))]
    m
  })

  output$estat <- renderText({
    v <- vals() |> filter(versio == VERSIO, valorador == nom_valorador())
    if (nom_valorador() == "") return("Escriu el teu nom per començar a desar valoracions.")
    sprintf("%s: has valorat %d jugadors de %d.", nom_valorador(),
            n_distinct(v$jugador_id), nrow(jugadors))
  })

  output$titol <- renderText({
    if (is.null(actual())) return("Ja has valorat tots els jugadors. Moltes gràcies!")
    sprintf("Qui s'assembla a %s?", actual()$nom)
  })

  output$box <- renderTable({
    req(actual())
    m <- mostrats()
    taula_box(c(actual()$jugador_id, m$mirall_id), c("Jugador", m$lletra))
  }, align = "l", striped = TRUE)

  output$valoracions_ui <- renderUI({
    req(actual())
    m <- mostrats()
    lapply(seq_len(nrow(m)), function(i) {
      r <- m[i, ]
      wellPanel(
        strong(sprintf("%s. %s (%s)", r$lletra, r$mirall_nom, neteja_equip(r$mirall_equips))),
        radioButtons(id("val", i), NULL, c("Bo", "Dubtós", "Dolent"),
                     selected = character(0), inline = TRUE),
        textInput(id("com", i), NULL, placeholder = "Comentari (opcional)", width = "100%")
      )
    })
  })

  observeEvent(input$desa, {
    req(actual())
    if (nom_valorador() == "") {
      showNotification("Escriu el teu nom abans de desar.", type = "warning")
      return()
    }
    m <- mostrats()
    v <- vapply(seq_len(nrow(m)), function(i) input[[id("val", i)]] %||% NA_character_, "")
    if (anyNA(v)) {
      showNotification("Valora els tres jugadors abans de desar.", type = "warning")
      return()
    }
    com <- vapply(seq_len(nrow(m)), function(i) input[[id("com", i)]] %||% "", "")
    nou <- tibble(
      data_hora = format(Sys.time(), "%Y-%m-%d %H:%M:%S"), valorador = nom_valorador(),
      versio = VERSIO, jugador_id = actual()$jugador_id, nom = actual()$nom,
      lliga = actual()$lliga, lletra = m$lletra, rang = m$rang,
      mirall_id = m$mirall_id, mirall_nom = m$mirall_nom,
      valoracio = v, comentari = com, d_total = round(m$d_total, 3))
    dir.create(dirname(FITXER), showWarnings = FALSE, recursive = TRUE)
    write_csv(nou, FITXER, append = file.exists(FITXER))
    vals(llegir_valoracions())
    showNotification("Desat!", type = "message", duration = 2)
    seguent()
  })

  observeEvent(input$salta, seguent())

  output$resum <- renderTable({
    v <- vals() |> filter(versio == VERSIO, valorador == nom_valorador())
    if (nrow(v) == 0) return(NULL)
    v |>
      count(valoracio) |>
      mutate(valoracio = factor(valoracio, c("Bo", "Dubtós", "Dolent")),
             pct = sprintf("%.0f%%", 100 * n / sum(n))) |>
      arrange(valoracio) |>
      rename(`Valoració` = valoracio, Miralls = n, `%` = pct)
  })
}

shinyApp(ui, server)
