"""Claude dosyasını üretir: <gün>_ham.gpkg -> <gün>_claude.gpkg (claude_cukurlar, claude_puanlar, aciklamalar, stiller).

Kullanım:
    python3 algoritma/uret.py veri/gelistirme/20261125/mikromobilite_20261125_ham.gpkg
    python3 algoritma/uret.py veri/gelistirme            # klasördeki (alt klasörler dahil) bütün *_ham.gpkg

Yalnızca ham dosya okunur (bağımsızlık kuralı). Aynı girdi her zaman aynı içeriği verir; içerik özeti (SHA-256) yazdırılır.
`veri/test/` altına "0-" sürümüyle yazılmaz ve var olan (mühürlenmiş) bir Claude dosyasının üstüne yazılmaz.
"""

import argparse
import json
import os
import sys
from datetime import timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import tespit  # noqa: E402
from okuma import ham_oku  # noqa: E402
from ortak import (KOK, STIL_KLASORU, VeriHatasi, icerik_ozeti, konum_at, utc_yazim, yerel_metinden,  # noqa: E402
                   yerel_yazim)

import sozluk  # noqa: E402  (qgis/sozluk.py)
from gpkg import GeoPackage, cizgi, nokta  # noqa: E402  (qgis/gpkg.py)

TEST_KLASORU = os.path.join(KOK, "veri", "test")
STIL_NOTU = "Kullanıcının QGIS projesinden alınan görünüm (qgis/stil_cikar.py)."


def test_verisi_mi(yol):
    return os.path.abspath(yol).startswith(TEST_KLASORU + os.sep)


def cikti_yolu(ham_yol):
    if not ham_yol.endswith("_ham.gpkg"):
        raise VeriHatasi(f"ham dosya adı '_ham.gpkg' ile bitmeli: {ham_yol}")
    return ham_yol[: -len("_ham.gpkg")] + "_claude.gpkg"


def stiller():
    sonuc = {}
    for ad in sorted(os.listdir(STIL_KLASORU)):
        if ad.endswith(".qml"):
            with open(os.path.join(STIL_KLASORU, ad), encoding="utf-8") as f:
                sonuc[ad[:-4]] = f.read()
    return sonuc


def uret(ham_yol, cikti=None, surum=tespit.SURUM, parametreler=tespit.PARAMETRELER):
    cikti = cikti or cikti_yolu(ham_yol)
    if os.path.abspath(cikti).startswith(os.path.join(KOK, "qgis") + os.sep):
        raise VeriHatasi(f"onaylı örnek klasörüne yazılmaz (örnekler qgis/ornek_uret.py ile üretilir): {cikti}")
    if test_verisi_mi(cikti):
        if surum.startswith("0-"):
            raise VeriHatasi(f"yer tutucu sürüm ({surum}) test verisine yazılamaz: {cikti}")
        if os.path.exists(cikti):
            raise VeriHatasi(f"test verisinin Claude dosyası zaten var (mühürlü olabilir), üstüne yazılmaz: {cikti}")
    gun = ham_oku(ham_yol)

    # Dosyanın değişiklik zamanı girdiden: son kaydın bitişi (aynı girdi -> aynı içerik)
    bitisler = []
    for k in gun.kayitlar.values():
        try:
            bitisler.append(yerel_metinden(k.oz["baslangic_yerel"]) + timedelta(seconds=k.oz["sure_s"] or 0))
        except VeriHatasi:
            pass
    son = utc_yazim(max(bitisler)) if bitisler else "1970-01-01T00:00:00.000Z"

    gp = GeoPackage(cikti, son)
    gp.katman("claude_cukurlar", "POINT", sozluk.CLAUDE_CUKUR_ALANLARI, sozluk.CLAUDE_CUKUR_ACIKLAMA)
    gp.katman("claude_puanlar", "LINESTRING", sozluk.CLAUDE_PUAN_ALANLARI, sozluk.CLAUDE_PUAN_ACIKLAMA)
    ozet = []
    for k in gun.kayitlar.values():
        darbeler, puan = tespit.hesapla(k, gun.ivme_yukle(k), parametreler)
        k.ivme = None  # bellek
        try:
            bas = yerel_metinden(k.oz["baslangic_yerel"])
        except VeriHatasi:
            bas = None
        satir = []
        for tt, tepe, oran in darbeler:
            t_s = round(tt, 4)
            enlem, boylam, hiz = konum_at(k.gps, t_s)
            satir.append((nokta(boylam, enlem), k.kayit_no, k.oz["kesit"], t_s,
                          yerel_yazim(bas + timedelta(seconds=t_s)) if bas else None,
                          None if hiz is None else round(hiz, 2), round(tespit.guven(oran, parametreler), 2),
                          round(tepe, 2), surum))
        if satir:
            gp.ekle("claude_cukurlar", satir)
        guzergah = k.guzergah if k.guzergah and len(k.guzergah) >= 2 else [(g["boylam"], g["enlem"]) for g in k.gps]
        if len(guzergah) >= 2:
            pd = puan["puan_ondalik"] if puan else None
            gp.ekle("claude_puanlar", [(cizgi(guzergah), k.kayit_no, k.oz["kesit"], k.oz["kesit_adi"],
                                        None if pd is None else int(pd + 0.5), None if pd is None else round(pd, 2),
                                        None if puan is None else round(puan["indeks_ms2"], 2), surum)])
        ozet.append((k.kayit_no, k.oz["kesit"], len(satir), None if puan is None else round(puan["puan_ondalik"], 2),
                     len(guzergah) >= 2))
    gp.katman("aciklamalar", None, [("katman", "TEXT"), ("alan", "TEXT"), ("tur", "TEXT"), ("birim", "TEXT"),
                                    ("aciklama", "TEXT")], "Bu dosyadaki katman ve alanların açıklaması (veri sözlüğü).")
    gp.ekle("aciklamalar", sozluk.ACIKLAMA_CLAUDE + [
        ("(dosya)", "algoritma", "", "", f"Sürüm: {surum}. Parametreler: "
                                          f"{json.dumps(parametreler, ensure_ascii=False, sort_keys=True)}"),
        ("(dosya)", "girdi", "", "", f"Ham dosya: {os.path.basename(ham_yol)}"),
    ])
    gp.stiller(stiller(), STIL_NOTU)
    gp.kapat()
    return cikti, ozet


def ham_dosyalari(yollar):
    for y in yollar:
        if os.path.isdir(y):
            for kok, _, dosyalar in sorted(os.walk(y)):
                for d in sorted(dosyalar):
                    if d.endswith("_ham.gpkg"):
                        yield os.path.join(kok, d)
        else:
            yield y


def main():
    ap = argparse.ArgumentParser(description="Ham dosyadan Claude dosyası üretir.")
    ap.add_argument("yollar", nargs="+", help="*_ham.gpkg dosyaları veya klasörler")
    ap.add_argument("--uzerine-yaz", action="store_true", help="var olan Claude dosyasının üstüne yaz (test verisi hariç)")
    a = ap.parse_args()
    hata = False
    for ham in ham_dosyalari(a.yollar):
        cikti = cikti_yolu(ham)
        if os.path.exists(cikti) and not a.uzerine_yaz and not test_verisi_mi(cikti):
            print(f"atlandı (Claude dosyası var; --uzerine-yaz): {cikti}")
            continue
        try:
            yol, ozet = uret(ham)
        except VeriHatasi as e:
            print(f"HATA: {e}")
            hata = True
            continue
        print(f"{yol}  (algoritma {tespit.SURUM})")
        for kayit_no, kesit, n, puan, cizgi_var in ozet:
            print(f"  {kayit_no} {kesit or '-'}: {n} çukur, puan {puan if puan is not None else '-'}"
                  + ("" if cizgi_var else "  (GPS yok: puan satırı yazılmadı)"))
        print(f"  içerik özeti (SHA-256): {icerik_ozeti(yol)}")
    sys.exit(1 if hata else 0)


if __name__ == "__main__":
    main()
