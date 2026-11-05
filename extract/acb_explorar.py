"""
PT1 · Exploració de la web de l'ACB (una sola pàgina d'equip).
Serveix per descobrir l'estructura abans d'escriure el scraper.
"""
import re
import time
from pathlib import Path

import requests
from bs4 import BeautifulSoup

CAP = {"User-Agent": "ProjecteMiralls/0.1 (projecte personal no comercial)"}
CARPETA_RAW = Path("data/raw/acb")
CARPETA_RAW.mkdir(parents=True, exist_ok=True)

# 1. Normes de la web
print("=== robots.txt ===")
r = requests.get("https://www.acb.com/robots.txt", headers=CAP, timeout=30)
for linia in r.text.splitlines():
    if re.match(r"(?i)(user-agent|disallow|allow|crawl-delay)", linia):
        print(" ", linia)
time.sleep(3)

# 2. Una pàgina d'equip, guardada en brut
url = "https://www.acb.com/club/estadisticas/id/4"
r = requests.get(url, headers=CAP, timeout=30)
print(f"\n=== {url} -> codi {r.status_code} ===")
(CARPETA_RAW / "explorar_club4.html").write_text(r.text, encoding="utf-8")
sopa = BeautifulSoup(r.text, "html.parser")

print("\n=== Textos amb 'TEMPORADA' ===")
for t in sorted({s.strip() for s in sopa.find_all(string=re.compile("TEMPORADA"))})[:5]:
    print(" ", t)

print("\n=== Selectors (select) ===")
for sel in sopa.find_all("select"):
    opcions = [(o.get("value"), o.get_text(strip=True)) for o in sel.find_all("option")]
    print(f"  name={sel.get('name')} id={sel.get('id')}: {opcions[:8]}")

print("\n=== Enllaços amb 'estadisticas' ===")
enllacos = sorted({a["href"] for a in sopa.find_all("a", href=True) if "estadisticas" in a["href"]})
for e in enllacos[:30]:
    print(" ", e)

print("\n=== Taules ===")
for i, taula in enumerate(sopa.find_all("table")):
    files = taula.find_all("tr")
    print(f"  Taula {i}: {len(files)} files")
