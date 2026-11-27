"""Telefonun ve Claude'un GeoPackage dosyalarını okur.

Alanlar adıyla okunur: 2.0 ile yazılmış dosyalardaki fazla alanlar (ör. `zaman`, `yukseklik_m`) yok sayılır.

BAĞIMSIZLIK BEKÇİSİ: `ham_oku`, adında `_insan` geçen veya içinde `insan_` katmanı bulunan dosyayı reddeder. Claude'un
tahmini yalnızca ham dosyadan üretilir; insan dosyası yalnızca `karsilastir.py` tarafından okunur.
"""

import os

from ortak import VeriHatasi, ac, cizgi_oku, katmanlar, nokta_oku, satirlar


class Kayit:
    """Bir kayıt (bir kesitin bir geçişi): öznitelikler, ham GPS izi ve gerekirse ivme."""

    def __init__(self, oz, gps, guzergah):
        self.oz = oz  # kayitlar katmanının satırı (sözlük)
        self.kayit_no = oz["kayit_no"]
        self.gps = gps  # t'ye göre sıralı [{'t', 'enlem', 'boylam', 'hiz_kmh', 'yon_derece', 'dogruluk_m', 'uydu'}]
        self.guzergah = guzergah  # [(boylam, enlem)] veya None
        self.ivme = None  # (t, x, y, z) listeleri; ivme_yukle ile


class HamGun:
    def __init__(self, yol, kayitlar):
        self.yol = yol
        self.kayitlar = kayitlar  # kayit_no -> Kayit (dosyadaki sırayla)

    def ivme_yukle(self, kayit):
        """Kaydın ivme örneklerini (zamana göre sıralı) yükler."""
        db = ac(self.yol)
        t, x, y, z = [], [], [], []
        for r in db.execute('SELECT t_s, x, y, z FROM ivme WHERE kayit_no = ? ORDER BY t_s, fid', (kayit.kayit_no,)):
            t.append(r[0])
            x.append(r[1])
            y.append(r[2])
            z.append(r[3])
        db.close()
        kayit.ivme = (t, x, y, z)
        return kayit.ivme


KAYIT_ALANLARI = ["kayit_no", "kesit", "kesit_adi", "yon", "baslangic_yerel", "sure_s", "uzunluk_m", "ort_hiz_kmh",
                  "gps_nokta", "ivme_hz", "jiro_hz", "veri_kaynagi", "uygulama_surumu"]


def ham_oku(yol):
    ad = os.path.basename(yol)
    if "_insan" in ad:
        raise VeriHatasi(f"bağımsızlık kuralı: insan dosyası tahmin için okunmaz ({ad})")
    db = ac(yol)
    kat = katmanlar(db)
    if any(k.startswith("insan_") for k in kat):
        db.close()
        raise VeriHatasi(f"bağımsızlık kuralı: dosyada insan katmanı var ({ad})")
    for gerekli in ("kayitlar", "gps_noktalari", "ivme"):
        if gerekli not in kat:
            db.close()
            raise VeriHatasi(f"{ad}: '{gerekli}' katmanı yok (ham dosya değil mi?)")
    kayitlar = {}
    for r in satirlar(db, "kayitlar", ["geom"] + KAYIT_ALANLARI):
        g = r.pop("geom")
        kayitlar[r["kayit_no"]] = Kayit(r, [], cizgi_oku(g) if g else None)
    for r in satirlar(db, "gps_noktalari", ["geom", "kayit_no", "t_s", "hiz_kmh", "yon_derece", "dogruluk_m", "uydu"],
                      siralama="kayit_no, t_s, fid"):
        k = kayitlar.get(r["kayit_no"])
        if k is None:
            db.close()
            raise VeriHatasi(f"{ad}: gps_noktalari'nda kayitlar'da olmayan kayıt {r['kayit_no']}")
        enlem, boylam = nokta_oku(r["geom"])
        k.gps.append({"t": r["t_s"], "enlem": enlem, "boylam": boylam, "hiz_kmh": r["hiz_kmh"],
                      "yon_derece": r["yon_derece"], "dogruluk_m": r["dogruluk_m"], "uydu": r["uydu"]})
    db.close()
    return HamGun(yol, kayitlar)


def insan_oku(yol):
    """İnsan dosyası: işaretler ve puanlar. YALNIZCA karsilastir.py kullanır."""
    db = ac(yol)
    kat = katmanlar(db)
    if "insan_puanlar" not in kat:
        db.close()
        raise VeriHatasi(f"{os.path.basename(yol)}: insan_puanlar katmanı yok")
    isaretler = []
    if "insan_cukurlar" in kat:
        for r in satirlar(db, "insan_cukurlar", ["geom", "kayit_no", "kesit", "t_s", "hiz_kmh", "kaynak"]):
            r["enlem"], r["boylam"] = nokta_oku(r.pop("geom"))
            isaretler.append(r)
    puanlar = {r["kayit_no"]: r for r in satirlar(db, "insan_puanlar", ["kayit_no", "kesit", "kesit_adi", "puan", "durum"])}
    db.close()
    return isaretler, puanlar


def claude_oku(yol):
    db = ac(yol)
    kat = katmanlar(db)
    for gerekli in ("claude_cukurlar", "claude_puanlar"):
        if gerekli not in kat:
            db.close()
            raise VeriHatasi(f"{os.path.basename(yol)}: '{gerekli}' katmanı yok")
    noktalar = []
    for r in satirlar(db, "claude_cukurlar", ["geom", "kayit_no", "kesit", "t_s", "hiz_kmh", "guven", "tepe_ms2",
                                              "algoritma"]):
        r["enlem"], r["boylam"] = nokta_oku(r.pop("geom"))
        noktalar.append(r)
    puanlar = {r["kayit_no"]: r for r in satirlar(db, "claude_puanlar", ["kayit_no", "kesit", "puan", "puan_ondalik",
                                                                         "indeks_ms2", "algoritma"])}
    db.close()
    return noktalar, puanlar
