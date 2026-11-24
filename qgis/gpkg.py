"""Küçük GeoPackage (.gpkg) yazıcısı: yalnızca Python'un standart kütüphanesi (sqlite3, struct).

GeoPackage, QGIS'in kendi önerdiği biçimdir: tek SQLite dosyasında birden çok katman (nokta, çizgi) ve geometrisiz
tablo bulunur. Bu yazıcı OGC GeoPackage 1.3'ün en küçük gerekli kısmını yazar: koordinat sistemi tablosu,
içerik tablosu, geometri sütunları tablosu ve katman tabloları. Koordinatlar WGS84 (EPSG:4326), x = boylam, y = enlem.
Mekânsal dizin (R-tree) yazılmaz; QGIS onsuz da açar (birkaç bin noktada fark edilmez).

Kullanım:
    gp = GeoPackage("dosya.gpkg", son_degisiklik="2026-11-20T12:00:00.000Z")
    gp.katman("noktalar", "POINT", [("ad", "TEXT"), ("hiz", "REAL")], "açıklama")
    gp.ekle("noktalar", [(nokta(28.89, 41.02), "a", 12.5)])
    gp.kapat()
"""

import math
import os
import sqlite3
import struct

WGS84_WKT = (
    'GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563,AUTHORITY["EPSG","7030"]],'
    'AUTHORITY["EPSG","6326"]],PRIMEM["Greenwich",0,AUTHORITY["EPSG","8901"]],'
    'UNIT["degree",0.0174532925199433,AUTHORITY["EPSG","9122"]],'
    'AXIS["Latitude",NORTH],AXIS["Longitude",EAST],AUTHORITY["EPSG","4326"]]'
)
SRS = 4326


class Geometri:
    """GeoPackage geometri ikili verisi (GP başlığı + WKB) ve kapsamı."""

    def __init__(self, blob, kapsam):
        self.blob = blob
        self.kapsam = kapsam  # (min_x, min_y, max_x, max_y)


def _gp_baslik(zarf):
    # 'GP', sürüm 0, bayraklar: bit0 = küçük sonlu (little endian), bit1-3 = zarf türü (1: xy zarfı)
    bayrak = 1 | ((1 << 1) if zarf else 0)
    b = b"GP" + bytes([0, bayrak]) + struct.pack("<i", SRS)
    if zarf:
        min_x, min_y, max_x, max_y = zarf
        b += struct.pack("<4d", min_x, max_x, min_y, max_y)
    return b


def nokta(boylam, enlem):
    wkb = struct.pack("<BIdd", 1, 1, boylam, enlem)
    return Geometri(_gp_baslik(None) + wkb, (boylam, enlem, boylam, enlem))


def cizgi(koordinatlar):
    """koordinatlar: [(boylam, enlem), ...] (en az 2 nokta)."""
    xs = [k[0] for k in koordinatlar]
    ys = [k[1] for k in koordinatlar]
    kapsam = (min(xs), min(ys), max(xs), max(ys))
    wkb = struct.pack("<BII", 1, 2, len(koordinatlar)) + b"".join(struct.pack("<dd", x, y) for x, y in koordinatlar)
    return Geometri(_gp_baslik(kapsam) + wkb, kapsam)


class GeoPackage:
    def __init__(self, yol, son_degisiklik):
        if os.path.exists(yol):
            os.remove(yol)
        self.yol = yol
        self.son_degisiklik = son_degisiklik  # sabit tutulursa aynı veri aynı dosyayı verir
        self.db = sqlite3.connect(yol)
        self.katmanlar = {}  # ad -> (geometri türü veya None, alan adları, kapsam)
        d = self.db
        d.execute("PRAGMA application_id = 1196444487")  # 0x47504B47 = 'GPKG'
        d.execute("PRAGMA user_version = 10300")  # GeoPackage 1.3
        d.execute(
            "CREATE TABLE gpkg_spatial_ref_sys (srs_name TEXT NOT NULL, srs_id INTEGER NOT NULL PRIMARY KEY, "
            "organization TEXT NOT NULL, organization_coordsys_id INTEGER NOT NULL, definition TEXT NOT NULL, "
            "description TEXT)"
        )
        d.executemany(
            "INSERT INTO gpkg_spatial_ref_sys VALUES (?,?,?,?,?,?)",
            [
                ("Undefined cartesian SRS", -1, "NONE", -1, "undefined", "undefined cartesian coordinate reference system"),
                ("Undefined geographic SRS", 0, "NONE", 0, "undefined", "undefined geographic coordinate reference system"),
                ("WGS 84 geodetic", SRS, "EPSG", SRS, WGS84_WKT, "longitude/latitude coordinates in decimal degrees on the WGS 84 spheroid"),
            ],
        )
        d.execute(
            "CREATE TABLE gpkg_contents (table_name TEXT NOT NULL PRIMARY KEY, data_type TEXT NOT NULL, "
            "identifier TEXT UNIQUE, description TEXT DEFAULT '', "
            "last_change DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')), "
            "min_x DOUBLE, min_y DOUBLE, max_x DOUBLE, max_y DOUBLE, srs_id INTEGER, "
            "CONSTRAINT fk_gc_r_srs_id FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys(srs_id))"
        )
        d.execute(
            "CREATE TABLE gpkg_geometry_columns (table_name TEXT NOT NULL, column_name TEXT NOT NULL, "
            "geometry_type_name TEXT NOT NULL, srs_id INTEGER NOT NULL, z TINYINT NOT NULL, m TINYINT NOT NULL, "
            "CONSTRAINT pk_geom_cols PRIMARY KEY (table_name, column_name), "
            "CONSTRAINT uk_gc_table_name UNIQUE (table_name), "
            "CONSTRAINT fk_gc_tn FOREIGN KEY (table_name) REFERENCES gpkg_contents(table_name), "
            "CONSTRAINT fk_gc_srs FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys (srs_id))"
        )

    def katman(self, ad, geometri_turu, alanlar, aciklama):
        """geometri_turu: 'POINT', 'LINESTRING' veya None (geometrisiz tablo).
        alanlar: [(ad, tür)], tür: TEXT, INTEGER, REAL, DATETIME (UTC, 'YYYY-MM-DDTHH:MM:SS.SSSZ')."""
        sutunlar = ['"fid" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL']
        if geometri_turu:
            sutunlar.append(f'"geom" {geometri_turu}')
        sutunlar += [f'"{a}" {t}' for a, t in alanlar]
        self.db.execute(f'CREATE TABLE "{ad}" ({", ".join(sutunlar)})')
        if geometri_turu:
            self.db.execute(
                "INSERT INTO gpkg_contents (table_name, data_type, identifier, description, last_change, srs_id) "
                "VALUES (?, 'features', ?, ?, ?, ?)",
                (ad, ad, aciklama, self.son_degisiklik, SRS),
            )
            self.db.execute(
                "INSERT INTO gpkg_geometry_columns VALUES (?, 'geom', ?, ?, 0, 0)", (ad, geometri_turu, SRS)
            )
        else:
            self.db.execute(
                "INSERT INTO gpkg_contents (table_name, data_type, identifier, description, last_change) "
                "VALUES (?, 'attributes', ?, ?, ?)",
                (ad, ad, aciklama, self.son_degisiklik),
            )
        self.katmanlar[ad] = [geometri_turu, [a for a, _ in alanlar], None]

    def ekle(self, ad, satirlar):
        """Geometrili katmanda her satır (Geometri, alan1, alan2, ...); geometrisizde (alan1, alan2, ...)."""
        geometri_turu, alanlar, kapsam = self.katmanlar[ad]
        adlar = (["geom"] if geometri_turu else []) + alanlar
        sql = f'INSERT INTO "{ad}" ({", ".join(chr(34) + a + chr(34) for a in adlar)}) VALUES ({", ".join("?" * len(adlar))})'
        hazir = []
        for s in satirlar:
            if geometri_turu:
                g = s[0]
                k = g.kapsam
                kapsam = k if kapsam is None else (
                    min(kapsam[0], k[0]), min(kapsam[1], k[1]), max(kapsam[2], k[2]), max(kapsam[3], k[3]))
                s = (g.blob,) + tuple(s[1:])
            hazir.append(tuple(None if (isinstance(v, float) and math.isnan(v)) else v for v in s))
        self.db.executemany(sql, hazir)
        self.katmanlar[ad][2] = kapsam

    def stiller(self, qml_sozlugu, aciklama):
        """QGIS'in GeoPackage'da varsayılan stil sakladığı `layer_styles` tablosunu yazar (QGIS'in kendi yazdığı biçim).
        qml_sozlugu: {katman adı: QML metni}. QGIS katmanı eklerken useAsDefault = 1 olan stili kendiliğinden uygular."""
        satirlar = []
        for ad, qml in qml_sozlugu.items():
            if ad in self.katmanlar:
                geo = "geom" if self.katmanlar[ad][0] else ""
                satirlar.append(("", "", ad, geo, ad, qml, None, 1, aciklama, "", None, self.son_degisiklik))
        if not satirlar:
            return
        self.katman("layer_styles", None, [
            ("f_table_catalog", "TEXT(256)"), ("f_table_schema", "TEXT(256)"), ("f_table_name", "TEXT(256)"),
            ("f_geometry_column", "TEXT(256)"), ("styleName", "TEXT(30)"), ("styleQML", "TEXT"), ("styleSLD", "TEXT"),
            ("useAsDefault", "BOOLEAN"), ("description", "TEXT"), ("owner", "TEXT(30)"), ("ui", "TEXT(30)"),
            ("update_time", "DATETIME"),
        ], "QGIS katman stilleri (QGIS katmanı eklerken kendiliğinden uygular).")
        self.ekle("layer_styles", satirlar)

    def kapat(self):
        for ad, (geometri_turu, _, kapsam) in self.katmanlar.items():
            if geometri_turu and kapsam:
                self.db.execute(
                    "UPDATE gpkg_contents SET min_x=?, min_y=?, max_x=?, max_y=? WHERE table_name=?", (*kapsam, ad)
                )
        self.db.commit()
        self.db.execute("VACUUM")
        self.db.close()
