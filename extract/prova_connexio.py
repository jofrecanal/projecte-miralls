import duckdb

con = duckdb.connect("data/miralls.duckdb")
con.execute("""
    CREATE OR REPLACE TABLE prova AS
    SELECT 'NBA' AS lliga, 48 AS minuts_partit
    UNION ALL SELECT 'Euroliga', 40
    UNION ALL SELECT 'ACB', 40
""")
con.close()
print("Taula creada a data/miralls.duckdb")
