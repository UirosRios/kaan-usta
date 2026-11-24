"""İki GeoPackage dosyasının biçimini (katmanlar, alan adları, alan türleri, geometri türleri) karşılaştırır.

Uygulamanın ürettiği dosyanın onaylanmış örnekle aynı biçimde olduğunu denetlemek için:
    python3 qgis/sema_karsilastir.py qgis/ornek/ornek_20261120_ham.gpkg <uygulamanın>_ham.gpkg
Örnekte olup diğerinde olmayan katman / alan veya tür farkı varsa hata kodu 1 ile çıkar.
Yalnızca Python'un standart kütüphanesini kullanır.
"""

import sqlite3
import sys


def sema(yol):
    db = sqlite3.connect(f"file:{yol}?mode=ro", uri=True)
    katmanlar = {}
    for ad, tur in db.execute("SELECT table_name, data_type FROM gpkg_contents"):
        geo = db.execute("SELECT geometry_type_name, srs_id FROM gpkg_geometry_columns WHERE table_name = ?", (ad,)).fetchone()
        alanlar = [(r[1], r[2].upper()) for r in db.execute(f'PRAGMA table_info("{ad}")')]
        katmanlar[ad] = (tur, geo, alanlar)
    kimlik = db.execute("PRAGMA application_id").fetchone()[0], db.execute("PRAGMA user_version").fetchone()[0]
    db.close()
    return katmanlar, kimlik


def main():
    ornek, ornek_kimlik = sema(sys.argv[1])
    diger, diger_kimlik = sema(sys.argv[2])
    sorun = []
    if ornek_kimlik != diger_kimlik:
        sorun.append(f"GeoPackage kimliği farklı: {ornek_kimlik} / {diger_kimlik}")
    for ad, (tur, geo, alanlar) in ornek.items():
        if ad not in diger:
            sorun.append(f"katman yok: {ad}")
            continue
        d_tur, d_geo, d_alanlar = diger[ad]
        if (tur, geo) != (d_tur, d_geo):
            sorun.append(f"{ad}: tür/geometri farklı {tur, geo} / {d_tur, d_geo}")
        if alanlar != d_alanlar:
            sorun.append(f"{ad}: alanlar farklı\n   örnek: {alanlar}\n   diğer: {d_alanlar}")
    for ad in diger:
        if ad not in ornek:
            sorun.append(f"örnekte olmayan katman: {ad}")
    if sorun:
        print("FARK VAR:\n- " + "\n- ".join(sorun))
        sys.exit(1)
    print(f"Biçim aynı: {len(ornek)} katman ({', '.join(ornek)})")


if __name__ == "__main__":
    main()
