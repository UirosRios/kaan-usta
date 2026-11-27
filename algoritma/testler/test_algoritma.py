"""Altyapı sınamaları: python3 -m unittest discover -s algoritma/testler

Veri:
- testler/veri/dart21_*.gpkg: uygulamanın (Dart, sürüm 2.1) yazdığı yapay gün (test/donusturucu_test.dart, "çeviri" testi;
  jiroskop satırları boyut için silindi). Konum kuralının Dart ile Python'da aynı olduğunu sınar.
- veri/gelistirme/20261125: gerçek deneme sürüşü (sürüm 2.0 biçimi, fazla alanlarla).
- qgis/ornek: Python örnek üreticisinin yapay günü (çukur yerleri biliniyor).
"""

import os
import shutil
import sqlite3
import struct
import sys
import tempfile
import unittest

BURASI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(BURASI))

import karsilastir as K  # noqa: E402
import tespit  # noqa: E402
import uret as U  # noqa: E402
from okuma import ham_oku  # noqa: E402
from ortak import (KOK, VeriHatasi, cizgi_oku, icerik_ozeti, konum_at, mesafe_m, nokta_oku,  # noqa: E402
                   yuzdelik)

from sema_karsilastir import sema  # noqa: E402  (qgis/)

DART = os.path.join(BURASI, "veri", "dart21")
GERCEK = os.path.join(KOK, "veri", "gelistirme", "20261125", "mikromobilite_20261125")
ORNEK = os.path.join(KOK, "qgis", "ornek", "ornek_20261120")


def isaret(kayit, t, enlem, boylam, kaynak="kumanda"):
    return {"kayit_no": kayit, "t_s": t, "enlem": enlem, "boylam": boylam, "kaynak": kaynak, "hiz_kmh": 15.0}


def kuzeye(enlem, m):
    return enlem + m / 111195.0


class Ortak(unittest.TestCase):
    gps = [{"t": 1.0, "enlem": 41.0, "boylam": 29.0, "hiz_kmh": 10.0},
           {"t": 2.0, "enlem": 41.001, "boylam": 29.002, "hiz_kmh": None},
           {"t": 3.0, "enlem": 41.002, "boylam": 29.004, "hiz_kmh": 20.0}]

    def test_konum_at(self):
        self.assertEqual(konum_at(self.gps, 0.5), (41.0, 29.0, 10.0))  # ilk noktadan önce
        e, b, h = konum_at(self.gps, 1.25)
        self.assertAlmostEqual(e, 41.00025)
        self.assertAlmostEqual(b, 29.0005)
        self.assertEqual(h, 10.0)  # bir uç hızı yoksa diğeri
        self.assertEqual(konum_at(self.gps, 9.0), (41.002, 29.004, 20.0))  # sondan sonra
        self.assertIsNone(konum_at([], 1.0))
        ayni = [dict(self.gps[0]), dict(self.gps[0], enlem=41.5)]
        self.assertEqual(konum_at(ayni, 1.0)[0], 41.0)

    def test_mesafe_ve_geometri(self):
        self.assertAlmostEqual(mesafe_m(41.0, 29.0, kuzeye(41.0, 100), 29.0), 100.0, delta=0.2)
        p = b"GP\x00\x01" + struct.pack("<i", 4326) + struct.pack("<BIdd", 1, 1, 29.5, 41.25)
        self.assertEqual(nokta_oku(p), (41.25, 29.5))
        zarfli = b"GP\x00\x03" + struct.pack("<i", 4326) + struct.pack("<4d", 0, 1, 0, 1) + \
            struct.pack("<BII", 1, 2, 2) + struct.pack("<4d", 29.0, 41.0, 29.1, 41.1)
        self.assertEqual(cizgi_oku(zarfli), [(29.0, 41.0), (29.1, 41.1)])

    def test_yuzdelik(self):
        self.assertEqual(yuzdelik([3, 1, 2], 50), 2)
        self.assertAlmostEqual(yuzdelik([0, 10], 68), 6.8)
        self.assertIsNone(yuzdelik([], 50))


class Eslestirme(unittest.TestCase):
    def test_bire_bir_en_yakin_once(self):
        c = [isaret("k1", 10.0, kuzeye(41.0, 0), 29.0)]
        i = [isaret("k1", 10.5, kuzeye(41.0, 3), 29.0), isaret("k1", 10.2, kuzeye(41.0, 1), 29.0)]
        s = K.sayilar(i, c, 5.0)
        self.assertEqual((s["dogru"], s["kacirilan"], s["fazladan"]), (1, 1, 0))
        self.assertEqual(s["ciftler"][0][0], 1)  # 1 m'deki işaret eşleşti

    def test_esik_siniri_dahil(self):
        c = [isaret("k1", 1.0, 41.0, 29.0)]
        i = [isaret("k1", 1.0, kuzeye(41.0, 5.0), 29.0)]
        d = mesafe_m(41.0, 29.0, kuzeye(41.0, 5.0), 29.0)
        self.assertEqual(K.sayilar(i, c, d)["dogru"], 1)
        self.assertEqual(K.sayilar(i, c, d - 1e-6)["dogru"], 0)

    def test_farkli_kayit_eslesmez(self):
        c = [isaret("k2", 1.0, 41.0, 29.0)]
        i = [isaret("k1", 1.0, 41.0, 29.0)]
        s = K.sayilar(i, c, 10.0)
        self.assertEqual((s["dogru"], s["kacirilan"], s["fazladan"]), (0, 1, 1))

    def test_bos_durumlar(self):
        c = [isaret("k1", 1.0, 41.0, 29.0)]
        s = K.sayilar([], c, 10.0)
        self.assertEqual((s["dogru"], s["fazladan"], s["duyarlilik"], s["kesinlik"]), (0, 1, None, 0.0))
        s = K.sayilar(c, [], 10.0)
        self.assertEqual((s["kacirilan"], s["duyarlilik"], s["kesinlik"]), (1, 0.0, None))

    def test_dislama(self):
        i = [isaret("k1", 10.0, 41.0, 29.0, "ekran"), isaret("k1", 20.0, 41.0, 29.0)]
        c = [isaret("k1", 10.8, 41.0, 29.0), isaret("k1", 11.5, 41.0, 29.0), isaret("k2", 10.0, 41.0, 29.0)]
        dahil_i, dahil_c, disi_i, disi_c = K.dislama(i, c)
        self.assertEqual([a["t_s"] for a in dahil_i], [20.0])
        self.assertEqual([b["t_s"] for b in disi_c], [10.8])
        self.assertEqual(len(dahil_c), 2)
        self.assertEqual(len(disi_i), 1)


class UctanUca(unittest.TestCase):
    def setUp(self):
        self.gecici = tempfile.mkdtemp(prefix="kaan_algoritma_")

    def tearDown(self):
        shutil.rmtree(self.gecici)

    def kopyala(self, on, ad, insan=True):
        hedef = os.path.join(self.gecici, ad)
        shutil.copy(on + "_ham.gpkg", hedef + "_ham.gpkg")
        if insan:
            shutil.copy(on + "_insan.gpkg", hedef + "_insan.gpkg")
        return hedef

    def calistir(self, on, ad, **kw):
        h = self.kopyala(on, ad)
        U.uret(h + "_ham.gpkg", **kw)
        g = K.gun_oku(h, h + "_ham.gpkg", h + "_insan.gpkg", h + "_claude.gpkg")
        g["dahil_i"], g["dahil_c"], g["disi_i"], g["disi_c"] = K.dislama(g["isaretler"], g["noktalar"])
        return h, g

    def tutarli(self, g):
        for e in (5.0, 10.0, 15.0):
            s = K.sayilar(g["dahil_i"], g["dahil_c"], e)
            self.assertEqual(s["dogru"] + s["kacirilan"], len(g["dahil_i"]))
            self.assertEqual(s["dogru"] + s["fazladan"], len(g["dahil_c"]))

    def test_uygulama_dosyasi_dart21(self):
        h, g = self.calistir(DART, "dart")
        self.assertLess(g["konum_farki"]["insan"], 0.001)  # Dart konumAt == Python konum_at
        self.assertEqual(len(g["isaretler"]), 3)
        self.tutarli(g)
        self.assertEqual(sema(h + "_claude.gpkg"), sema(ORNEK + "_claude.gpkg"))

    def test_gercek_deneme_20(self):
        h, g = self.calistir(GERCEK, "gercek")
        self.assertLess(g["konum_farki"]["insan"], 0.001)
        self.assertEqual(len(g["isaretler"]), 9)
        self.assertEqual(len(g["gun"].kayitlar), 4)
        self.tutarli(g)

    def test_python_ornek(self):
        h, g = self.calistir(ORNEK, "ornek")
        self.assertLess(g["konum_farki"]["insan"], 0.001)
        self.tutarli(g)

    def test_belirlenimci(self):
        a = self.kopyala(GERCEK, "a", insan=False)
        b = self.kopyala(GERCEK, "b", insan=False)
        U.uret(a + "_ham.gpkg")
        U.uret(b + "_ham.gpkg")
        tablolar = ["claude_cukurlar", "claude_puanlar"]
        self.assertEqual(icerik_ozeti(a + "_claude.gpkg", tablolar), icerik_ozeti(b + "_claude.gpkg", tablolar))

    def test_hic_tespit_yok(self):
        p = dict(tespit.PARAMETRELER, en_az_ms2=1e9)
        h, g = self.calistir(DART, "bos", parametreler=p)
        self.assertEqual(len(g["noktalar"]), 0)
        s = K.sayilar(g["dahil_i"], g["dahil_c"], 10.0)
        self.assertEqual((s["kacirilan"], s["kesinlik"]), (3, None))
        K.rapor([g], [5.0, 10.0, 15.0], None, "diger")  # tanımsız oranlarla da rapor ve katman yazılır
        K.gpkg_yaz(g, [5.0, 10.0, 15.0], h + "_karsilastirma.gpkg")
        db = sqlite3.connect(h + "_karsilastirma.gpkg")
        self.assertEqual(db.execute("SELECT count(*), max(kesinlik) FROM ozet").fetchone(), (3, None))
        self.assertEqual(db.execute("SELECT count(*) FROM eslesmeyenler WHERE sonuc = 'kacirilan'").fetchone()[0], 9)
        db.close()

    def test_hic_isaret_yok(self):
        h = self.kopyala(DART, "isaretsiz")
        db = sqlite3.connect(h + "_insan.gpkg")
        db.execute("DELETE FROM insan_cukurlar")
        db.commit()
        db.close()
        U.uret(h + "_ham.gpkg")
        g = K.gun_oku(h, h + "_ham.gpkg", h + "_insan.gpkg", h + "_claude.gpkg")
        s = K.sayilar(g["isaretler"], g["noktalar"], 10.0)
        self.assertEqual((s["dogru"], s["fazladan"], s["duyarlilik"]), (0, len(g["noktalar"]), None))

    def test_insanda_eksik_kayit_hata(self):
        h = self.kopyala(DART, "eksik")
        db = sqlite3.connect(h + "_insan.gpkg")
        db.execute("DELETE FROM insan_puanlar WHERE kayit_no = '20261125_102102'")
        db.commit()
        db.close()
        U.uret(h + "_ham.gpkg")
        with self.assertRaisesRegex(VeriHatasi, "kayıtlar farklı"):
            K.gun_oku(h, h + "_ham.gpkg", h + "_insan.gpkg", h + "_claude.gpkg")

    def test_konum_kurali_bozuksa_hata(self):
        h = self.kopyala(DART, "kayik")
        U.uret(h + "_ham.gpkg")
        db = sqlite3.connect(h + "_claude.gpkg")
        fid, blob = db.execute("SELECT fid, geom FROM claude_cukurlar LIMIT 1").fetchone()
        blob = bytearray(blob)
        x, y = struct.unpack_from("<dd", blob, 8 + 5)
        struct.pack_into("<dd", blob, 8 + 5, x, y + 0.00005)  # ~5 m kuzeye
        db.execute("UPDATE claude_cukurlar SET geom = ? WHERE fid = ?", (bytes(blob), fid))
        db.commit()
        db.close()
        with self.assertRaisesRegex(VeriHatasi, "konum kuralı uyuşmuyor"):
            K.gun_oku(h, h + "_ham.gpkg", h + "_insan.gpkg", h + "_claude.gpkg")


    def test_konumsuz_isaret_dislanir(self):
        h = self.kopyala(DART, "konumsuz")
        db = sqlite3.connect(h + "_insan.gpkg")
        db.execute("UPDATE insan_cukurlar SET geom = NULL WHERE kayit_no = '20261125_102102'")
        db.commit()
        db.close()
        U.uret(h + "_ham.gpkg")
        g = K.gun_oku(h, h + "_ham.gpkg", h + "_insan.gpkg", h + "_claude.gpkg")
        dahil_i, _, disi_i, _ = K.dislama(g["isaretler"], g["noktalar"])
        self.assertEqual((len(dahil_i), [a["neden"] for a in disi_i]), (2, [K.NEDEN_KONUMSUZ]))


def git_calistir(klasor, *arg):
    import subprocess
    subprocess.run(["git", "-C", klasor, "-c", "user.name=t", "-c", "user.email=t@t", *arg], check=True,
                   capture_output=True)


class TestGunuMuhru(unittest.TestCase):
    """veri/test yolu: geçici bir git deposunda (KOK ve TEST_KLASORU geçici olarak değiştirilir)."""

    def setUp(self):
        self.kok = tempfile.mkdtemp(prefix="kaan_muhur_")
        self.eski = (K.KOK, K.TEST_KLASORU, K.GELISTIRME_KLASORU)
        K.KOK = self.kok
        K.TEST_KLASORU = os.path.join(self.kok, "veri", "test")
        K.GELISTIRME_KLASORU = os.path.join(self.kok, "veri", "gelistirme")
        gun = os.path.join(K.TEST_KLASORU, "20261201")
        os.makedirs(gun)
        self.on = os.path.join(gun, "mikromobilite_20261201")
        for son in ("_ham.gpkg", "_insan.gpkg", "_claude.gpkg"):
            with open(self.on + son, "w") as f:
                f.write(son)
        with open(os.path.join(K.TEST_KLASORU, "esik.json"), "w") as f:
            f.write('{"esik_m": 6.5}')
        git_calistir(self.kok, "init", "-q")
        git_calistir(self.kok, "add", "-A")
        git_calistir(self.kok, "commit", "-q", "-m", "mühür")
        git_calistir(self.kok, "update-ref", "refs/remotes/origin/main", "HEAD")
        self.yollar = [(self.on, self.on + "_ham.gpkg", self.on + "_insan.gpkg", self.on + "_claude.gpkg")]

    def tearDown(self):
        K.KOK, K.TEST_KLASORU, K.GELISTIRME_KLASORU = self.eski
        shutil.rmtree(self.kok)

    def test_muhurlu_gecer_esik_dosyadan(self):
        self.assertEqual(K.bekciler(self.yollar, None), ("test", 6.5))

    def test_komut_satiri_esigi_reddedilir(self):
        with self.assertRaisesRegex(VeriHatasi, "komut satırından"):
            K.bekciler(self.yollar, 10.0)

    def test_degisen_claude_dosyasi_reddedilir(self):
        with open(self.on + "_claude.gpkg", "a") as f:
            f.write("değişti")
        with self.assertRaisesRegex(VeriHatasi, "mühür bozuk"):
            K.bekciler(self.yollar, None)

    def test_gonderilmemis_esik_reddedilir(self):
        git_calistir(self.kok, "update-ref", "-d", "refs/remotes/origin/main")
        with self.assertRaisesRegex(VeriHatasi, "mühür yok"):
            K.bekciler(self.yollar, None)

    def test_tur_etiketleri(self):
        self.assertEqual(K.tur_bul(self.on), "test")
        self.assertEqual(K.tur_bul(os.path.join(K.GELISTIRME_KLASORU, "x", "y")), "gelistirme")
        self.assertEqual(K.tur_bul("/tmp/x/y"), "diger")
        with self.assertRaisesRegex(VeriHatasi, "aynı raporda"):
            K.bekciler(self.yollar + [("/tmp/x/y", "", "", "")], None)


class Sozluk(unittest.TestCase):
    def test_uygulama_sozlugu_python_ile_ayni(self):
        """lib/katmanlar.dart'ın yazdığı veri sözlüğü qgis/sozluk.py ile aynı olmalı (dart21 dosyaları uygulama
        değişince yeniden üretilir: KAAN_TEST_CIKTI=<klasör> flutter test ... --plain-name "çeviri: katmanlar")."""
        import sozluk
        for ad, beklenen in (("ham", sozluk.ACIKLAMA_HAM), ("insan", sozluk.ACIKLAMA_INSAN)):
            db = sqlite3.connect(f"{DART}_{ad}.gpkg")
            satirlar = [tuple(r) for r in db.execute("SELECT katman, alan, tur, birim, aciklama FROM aciklamalar ORDER BY fid")]
            db.close()
            self.assertEqual(satirlar, [tuple(r) for r in beklenen], ad)


class Bekciler(unittest.TestCase):
    def test_insan_dosyasi_tahminde_okunmaz(self):
        with self.assertRaisesRegex(VeriHatasi, "bağımsızlık"):
            ham_oku(DART + "_insan.gpkg")
        gecici = tempfile.mkdtemp()
        try:
            sahte = os.path.join(gecici, "gun_ham.gpkg")
            shutil.copy(DART + "_insan.gpkg", sahte)  # adı ham, içi insan
            with self.assertRaisesRegex(VeriHatasi, "bağımsızlık"):
                ham_oku(sahte)
        finally:
            shutil.rmtree(gecici)

    def test_test_verisine_yer_tutucu_yazilmaz(self):
        cikti = os.path.join(U.TEST_KLASORU, "20990101", "x_claude.gpkg")
        with self.assertRaisesRegex(VeriHatasi, "yer tutucu"):
            U.uret(DART + "_ham.gpkg", cikti=cikti)
        self.assertFalse(os.path.exists(os.path.dirname(cikti)))

    def test_onayli_ornege_yazilmaz(self):
        with self.assertRaisesRegex(VeriHatasi, "onaylı örnek"):
            U.uret(ORNEK + "_ham.gpkg")

    def test_muhursuz_dosya_reddedilir(self):
        gecici = tempfile.mkdtemp()
        try:
            yol = os.path.join(gecici, "x_claude.gpkg")
            open(yol, "w").close()
            with self.assertRaisesRegex(VeriHatasi, "mühür"):
                K.muhur_denetle(yol)
        finally:
            shutil.rmtree(gecici)


if __name__ == "__main__":
    unittest.main()
