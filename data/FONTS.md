# Fonts de dades i condicions d'ús

Revisió: 7 d'octubre de 2026. Les condicions poden canviar: tornar-les a revisar abans de publicar res.

## NBA (stats.nba.com, via nba_api)
- Condicions: Terms of Use de NBA.com, secció 9 "NBA Statistics".
- Permès: ús privat i no comercial o periodístic, amb atribució visible a NBA.com.
- No permès: apostes, fantasy, patrocinis o productes comercials; webs amb una base de dades completa i actualitzada d'estadístiques NBA sense permís.
- nba_api és una API no oficial: pot canviar o deixar de funcionar.

## Euroliga (api-live.euroleague.net)
- API pública sense autenticació.
- No s'han trobat condicions d'ús específiques per a la web o l'API (la web només publica la política de privacitat).
- Estatuts 2025-26 (Bylaws): l'Euroliga es reserva els "Data Rights" (explotar i llicenciar totes les estadístiques dels partits). Article 123: fins i tot els clubs només poden fer servir les estadístiques en directe amb finalitats informatives, sense modificar-les i sense ús comercial.
- Conclusió: s'apliquen les normes generals del projecte. Opcional: demanar permís per a ús no comercial abans del PT4.

## ACB (acb.com, scraping)
- robots.txt: permet l'accés a tot el lloc.
- Avís legal, secció 3: permès visualitzar i descarregar per a ús personal o periodístic, citant acb.com. Distribuir o comunicar públicament fora d'això requereix consentiment previ.
- Avís legal, secció 6: no sobrecarregar el lloc web.

## Normes del projecte
1. Les dades en brut no es publiquen mai (data/ és al .gitignore).
2. Es publiquen resultats derivats (similituds, mètriques, gràfics), no taules d'estadístiques.
3. L'app mostra el resultat de l'anàlisi, no una base de dades d'estadístiques actualitzada.
4. Atribució visible a NBA.com, Euroleague i acb.com en tot el que es publiqui.
5. Pauses entre peticions, descàrrega única i cache local.
6. Cap ús comercial; si això canviés, demanar permís a les lligues.
