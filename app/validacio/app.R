# app/validacio/app.R
# PT3 · Validació interactiva dels miralls (D27)
# Mostra un jugador triat a l'atzar (equilibrat per lliga i grup) i els seus 3 miralls
# només amb estadístiques de box score (sense res del motor), en ordre barrejat (A, B, C).
# Cada mirall es valora com a Bo / Dubtós / Dolent, amb un comentari opcional.
# - Dades: dades_app.rds (analysis/07_dades_app.R; fora de Git).
# - Configuració privada (fora de Git): privat/config.R (codi d'accés i full de Google Sheets)
#   i privat/clau_google.json (compte de servei). Sense configuració, les valoracions es
#   guarden a analysis/valoracions/valoracions.csv.
# Ús local (Consola de RStudio): shiny::runApp("app/validacio")

library(shiny)
library(dplyr)
library(readr)

VERSIO   <- "v2: 12 variables d'estil, filtre exterior-interior i ±7 cm (D26)"
COLUMNES <- c("data_hora", "valorador", "versio", "jugador_id", "nom", "lliga", "lletra",
              "rang", "mirall_id", "mirall_nom", "valoracio", "comentari")
FITXER_LOCAL <- file.path("..", "..", "analysis", "valoracions", "valoracions.csv")

# --- Dades ---
dades   <- readRDS("dades_app.rds")
miralls <- dades$miralls

# --- Configuració privada ---
CODI_ACCES <- NULL
FULL_ID    <- NULL
if (file.exists("privat/config.R")) source("privat/config.R", local = TRUE)
EN_LINIA <- !is.null(FULL_ID) && file.exists("privat/clau_google.json")
if (EN_LINIA) {
  library(googlesheets4)
  gs4_auth(path = "privat/clau_google.json")
}

neteja_equip <- function(x) {
  x |> gsub("ACB_|EUR_", "", x = _) |> gsub("-[0-9]+", "", x = _) |> gsub(";", " / ", x = _)
}

# Box score per partit (temporada regular)
box <- dades$per100 |>
  transmute(jugador_id,
            PJ = partits, Min = minuts / partits, Pts = punts / partits,
            Reb = (reb_of + reb_def) / partits, RO = reb_of / partits,
            Ast = assist / partits, Rob = robatoris / partits, Tap = taps / partits,
            `Pèr` = perdues / partits, Falt = faltes / partits, `F. reb` = faltes_reb / partits,
            `T2%` = 100 * t2_anot / t2_int, `T3%` = 100 * t3_anot / t3_int,
            `TL%` = 100 * tl_anot / tl_int)

fitxes <- bind_rows(
  miralls |> distinct(jugador_id, nom, lliga, equips, posicio, alcada_cm),
  miralls |> distinct(jugador_id = mirall_id, nom = mirall_nom, lliga = mirall_lliga,
                      equips = mirall_equips, posicio = mirall_posicio,
                      alcada_cm = mirall_alcada_cm)
) |> distinct(jugador_id, .keep_all = TRUE)

jugadors <- miralls |>
  distinct(jugador_id, nom, lliga) |>
  left_join(dades$plantilles, by = "jugador_id") |>
  mutate(grup = coalesce(grup, "sense grup"), estrat = paste(lliga, grup))

llegir_valoracions <- function() {
  v <- if (EN_LINIA) {
    read_sheet(FULL_ID, col_types = "c")
  } else if (file.exists(FITXER_LOCAL)) {
    read_csv(FITXER_LOCAL, show_col_types = FALSE, col_types = cols(.default = "c"))
  } else {
    tibble()
  }
  for (c in COLUMNES) if (!c %in% names(v)) v[[c]] <- rep(NA_character_, nrow(v))
  v
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
  uiOutput("pantalla")
)

server <- function(input, output, session) {
  entrat <- reactiveVal(is.null(CODI_ACCES))
  vals   <- reactiveVal(llegir_valoracions())
  actual <- reactiveVal(NULL)
  ordre  <- reactiveVal(NULL)
  n      <- reactiveVal(0)
  nom_valorador <- reactive(trimws(input$valorador %||% ""))

  seguent <- function() {
    isolate({
      actual(tria(vals(), nom_valorador()))
      ordre(sample(3))
      n(n() + 1)
    })
  }
  seguent()
  id <- function(prefix, i) paste0(prefix, i, "_", n())

  # --- Pantalla: codi d'accés o app ---
  output$pantalla <- renderUI({
    if (!entrat()) {
      return(tagList(
        p("Introdueix el codi d'accés que t'han donat."),
        passwordInput("codi", "Codi d'accés"),
        actionButton("entra", "Entra", class = "btn-primary")
      ))
    }
    tagList(
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
  })

  observeEvent(input$entra, {
    if (identical(trimws(input$codi), CODI_ACCES)) {
      entrat(TRUE)
    } else {
      showNotification("Codi incorrecte.", type = "error")
    }
  })

  # Quan canvia el nom, tria un jugador que aquesta persona no hagi valorat
  observeEvent(input$valorador, seguent(), ignoreInit = TRUE)

  # Miralls del jugador actual, en l'ordre barrejat que es mostra (A, B, C)
  mostrats <- reactive({
    req(actual())
    m <- miralls |> filter(jugador_id == actual()$jugador_id) |> arrange(rang)
    m <- m[ordre()[seq_len(nrow(m))], ]
    m$lletra <- LETTERS[seq_len(nrow(m))]
    m
  })

  output$estat <- renderText({
    if (nom_valorador() == "") return("Escriu el teu nom per començar a desar valoracions.")
    v <- vals() |> filter(versio == VERSIO, valorador == nom_valorador())
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
      lliga = actual()$lliga, lletra = m$lletra, rang = as.character(m$rang),
      mirall_id = m$mirall_id, mirall_nom = m$mirall_nom,
      valoracio = v, comentari = com)
    ok <- tryCatch({
      if (EN_LINIA) {
        sheet_append(FULL_ID, nou)
      } else {
        dir.create(dirname(FITXER_LOCAL), showWarnings = FALSE, recursive = TRUE)
        write_csv(nou, FITXER_LOCAL, append = file.exists(FITXER_LOCAL))
      }
      TRUE
    }, error = function(e) {
      showNotification(paste("No s'ha pogut desar:", conditionMessage(e)), type = "error")
      FALSE
    })
    if (!ok) return()
    vals(bind_rows(vals(), nou))
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
