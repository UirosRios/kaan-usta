"""Ortak araçlar: GeoPackage okuma, konum ara değeri, dikey sarsıntı, mesafe.

Yalnızca Python'un standart kütüphanesi kullanılır. Konum kuralı (`konum_at`) uygulamadaki `konumAt` (lib/donusturucu.dart)
ile birebir aynıdır: insan işaretleri de Claude noktaları da ham GPS izinde, t anına doğrusal ara değerle konur.
"""

import hashlib
import math
import os
import pathlib
import sqlite3
import struct
import sys
from datetime import datetime, timedelta, timezone

KOK = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
QGIS_KLASORU = os.path.join(KOK, "qgis")
STIL_KLASORU = os.path.join(QGIS_KLASORU, "stiller")
# qgis/gpkg.py ve qgis/sozluk.py: paket olarak değil yol olarak alınır ("qgis" adı QGIS'in kendi paketiyle çakışmasın)
if QGIS_KLASORU not in sys.path:
    sys.path.insert(0, QGIS_KLASORU)

ISTANBUL = timezone(timedelta(hours=3))  # Türkiye 2016'dan beri yaz saati uygulamıyor


class VeriHatasi(Exception):
    """Girdi dosyası beklenen biçimde değil veya kurala aykırı."""


# ---------------------------------------------------------------------------------------------------------- okuma

def ac(yol):
    """Salt okunur açar. Yol URI olarak kodlanır: klasör adındaki '#', '?', '%' veya boşluk dosyayı yanlış yere açtırmasın."""
    if not os.path.exists(yol):
        raise VeriHatasi(f"dosya yok: {yol}")
    return sqlite3.connect(pathlib.Path(yol).resolve().as_uri() + "?mode=ro", uri=True)


def gercek_yol(yol):
    """Karşılaştırma için: sembolik bağlantılar çözülmüş, Windows'ta harf büyüklüğü eşitlenmiş tam yol."""
    return os.path.normcase(os.path.realpath(yol))


def altinda(yol, klasor):
    """yol, klasor'un içinde mi (ikisi de karşılaştırma anında gerçek yola çevrilir)?"""
    return gercek_yol(yol).startswith(gercek_yol(klasor) + os.sep)


def katmanlar(db):
    return [r[0] for r in db.execute("SELECT table_name FROM gpkg_contents")]


def alanlar(db, tablo):
    return [r[1] for r in db.execute(f'PRAGMA table_info("{tablo}")')]


def satirlar(db, tablo, istenen, siralama="fid"):
    """Tablodan adıyla istenen alanları sözlük olarak okur (fazla alanlar yok sayılır, eksik alan None)."""
    var = set(alanlar(db, tablo))
    secim = ", ".join(f'"{a}"' if a in var else f"NULL AS \"{a}\"" for a in istenen)
    db.row_factory = sqlite3.Row
    try:
        return [dict(r) for r in db.execute(f'SELECT {secim} FROM "{tablo}" ORDER BY {siralama}')]
    finally:
        db.row_factory = None


def _wkb_basi(blob):
    """GeoPackage geometrisinde WKB'nin başladığı yer (GP başlığı + zarf)."""
    if blob is None or len(blob) < 8 or blob[:2] != b"GP":
        raise VeriHatasi("GeoPackage geometrisi değil")
    zarf = (blob[3] >> 1) & 7
    return 8 + {0: 0, 1: 32, 2: 48, 3: 48, 4: 64}[zarf]


def nokta_oku(blob):
    """GeoPackage nokta geometrisi -> (enlem, boylam)."""
    o = _wkb_basi(blob)
    bo = "<" if blob[o] == 1 else ">"
    x, y = struct.unpack_from(bo + "dd", blob, o + 5)
    return y, x


def cizgi_oku(blob):
    """GeoPackage çizgi geometrisi -> [(boylam, enlem), ...]."""
    o = _wkb_basi(blob)
    bo = "<" if blob[o] == 1 else ">"
    (n,) = struct.unpack_from(bo + "I", blob, o + 5)
    return [struct.unpack_from(bo + "dd", blob, o + 9 + 16 * i) for i in range(n)]


def icerik_ozeti(yol, tablolar=None):
    """Dosyanın içeriğinin (sıralı satırlar) SHA-256 özeti. Dosyanın kendi baytları SQLite sürümüne göre değişebilir;
    "aynı girdi, aynı sonuç" bununla denetlenir."""
    db = ac(yol)
    h = hashlib.sha256()
    for t in sorted(tablolar or katmanlar(db)):
        h.update(t.encode())
        h.update(repr(alanlar(db, t)).encode())
        for r in db.execute(f'SELECT * FROM "{t}" ORDER BY fid'):
            h.update(repr(r).encode())
    db.close()
    return h.hexdigest()


def dosya_ozeti(yol):
    with open(yol, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


# --------------------------------------------------------------------------------------------- konum ve mesafe

def konum_at(gps, t):
    """Ham GPS izinde t anının konumu: iki GPS noktası arasında doğrusal ara değer; ilk noktadan önce ilk, sonuncudan
    sonra son nokta. gps: t'ye göre sıralı [{'t', 'enlem', 'boylam', 'hiz_kmh'}]. Döner: (enlem, boylam, hiz_kmh) veya None.
    Uygulamadaki konumAt (lib/donusturucu.dart) ile aynı kural."""
    if not gps:
        return None
    if t <= gps[0]["t"]:
        g = gps[0]
        return g["enlem"], g["boylam"], g["hiz_kmh"]
    for i in range(1, len(gps)):
        if t <= gps[i]["t"]:
            a, b = gps[i - 1], gps[i]
            f = (t - a["t"]) / (b["t"] - a["t"]) if b["t"] > a["t"] else 0.0
            ha, hb = a["hiz_kmh"], b["hiz_kmh"]
            hiz = (ha if ha is not None else hb) if ha is None or hb is None else ha + f * (hb - ha)
            return a["enlem"] + f * (b["enlem"] - a["enlem"]), a["boylam"] + f * (b["boylam"] - a["boylam"]), hiz
    g = gps[-1]
    return g["enlem"], g["boylam"], g["hiz_kmh"]


def mesafe_m(enlem1, boylam1, enlem2, boylam2):
    """Büyük daire mesafesi (haversine, R = 6371 km); uygulamadaki mesafeM ile aynı."""
    r = 6371000.0
    p1, p2 = math.radians(enlem1), math.radians(enlem2)
    dp, dl = p2 - p1, math.radians(boylam2 - boylam1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(a)))


# --------------------------------------------------------------------------------------------------- sinyal

def dikey_sarsinti(t, x, y, z):
    """Dikey sarsıntı (uygulamadaki dikeySarsinti ve v1 ile aynı): üç eksene 0,4 Hz birinci dereceden yüksek geçiren süzgeç
    (bilineer), yerçekimi = ham − süzülmüş, sarsıntı = titreşimin yerçekimi yönüne izdüşümü. İlk örnekte veya 1 sn'den
    uzun boşlukta süzgeç sıfırlanır."""
    tau = 1 / (2 * math.pi * 0.4)
    out = [0.0] * len(t)
    yx = yy = yz = 0.0
    for i in range(len(t)):
        if i > 0:
            dt = t[i] - t[i - 1]
            if dt <= 0 or dt > 1:
                yx = yy = yz = 0.0
            else:
                k = 2 * tau / dt
                c1, c2 = k / (k + 1), (k - 1) / (k + 1)
                yx = c1 * (x[i] - x[i - 1]) + c2 * yx
                yy = c1 * (y[i] - y[i - 1]) + c2 * yy
                yz = c1 * (z[i] - z[i - 1]) + c2 * yz
        gx, gy, gz = x[i] - yx, y[i] - yy, z[i] - yz
        gn = math.sqrt(gx * gx + gy * gy + gz * gz)
        out[i] = (yx * gx + yy * gy + yz * gz) / gn if gn > 0 else 0.0
    return out


# ------------------------------------------------------------------------------------------------------ saat

def yerel_metinden(metin):
    """'YYYY-MM-DD HH:MM:SS[.mmm]' (İstanbul saati) -> zaman dilimli datetime."""
    for bicim in ("%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%d %H:%M:%S"):
        try:
            return datetime.strptime(metin, bicim).replace(tzinfo=ISTANBUL)
        except (TypeError, ValueError):
            pass
    raise VeriHatasi(f"yerel saat okunamadı: {metin!r}")


def yerel_yazim(an):
    """Uygulamadaki yerelYazim ile aynı: 'YYYY-MM-DD HH:MM:SS.mmm' (İstanbul saati)."""
    y = an.astimezone(ISTANBUL)
    return y.strftime("%Y-%m-%d %H:%M:%S.") + f"{y.microsecond // 1000:03d}"


def utc_yazim(an):
    return an.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.") + f"{an.microsecond // 1000:03d}Z"


def yuzdelik(degerler, p):
    """Doğrusal ara değerli yüzdelik (p: 0-100). Boş listede None."""
    d = sorted(degerler)
    if not d:
        return None
    k = (len(d) - 1) * p / 100
    a = math.floor(k)
    b = min(a + 1, len(d) - 1)
    return d[a] + (d[b] - d[a]) * (k - a)
