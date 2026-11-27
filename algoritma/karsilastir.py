"""Claude'un çukur noktalarını ve puanlarını sürücünün işaret ve puanlarıyla karşılaştırır (hocanın ölçütü).

Kullanım:
    python3 algoritma/karsilastir.py veri/gelistirme               # klasördeki bütün günler (ham + insan + claude)
    python3 algoritma/karsilastir.py veri/gelistirme --esik 6      # seçilen eşik de tabloya eklenir
    python3 algoritma/karsilastir.py veri/test                     # test: eşik veri/test/esik.json'dan, mühür denetimi

Kural (README'de ayrıntı):
- Konum: iki nokta da ham GPS izinde, t_s anına doğrusal ara değer (`konum_at`). Dosyadaki konumlar bu kuralla 1 cm'den
  fazla uyuşmazsa durur: QGIS'te elle ölçülen mesafe rapordakiyle aynı olmalı.
- Eşleştirme: aynı kayıt içinde, bire bir, en yakın çift önce, mesafe <= eşik. Doğru = eşleşen işaret; kaçırılan =
  eşleşmeyen işaret; fazladan = eşleşmeyen Claude noktası. Duyarlılık = doğru / işaret; kesinlik = doğru / Claude noktası.
- Dışlanan: ekran / telefon tuşu işaretleri (basış telefonu sarsar, algoritma basışın kendisini bulabilir) ve onlara
  1 sn'den yakın Claude noktaları. Sayıları raporlanır.
- Test verisi (veri/test/): Claude dosyası origin/main'dekiyle aynı olmalı (önce GitHub'a), eşik komut satırından değil
  veri/test/esik.json'dan (o da origin/main'de), "0-" (yer tutucu) sürüm kabul edilmez.
"""

import argparse
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from okuma import claude_oku, ham_oku, insan_oku  # noqa: E402
from ortak import KOK, VeriHatasi, ac, icerik_ozeti, konum_at, mesafe_m, yuzdelik  # noqa: E402

from gpkg import GeoPackage, cizgi, nokta  # noqa: E402  (qgis/gpkg.py)

EK_ESIKLER = [5.0, 10.0, 15.0]
DISLANAN_KAYNAKLAR = ("ekran", "tus")
DISLAMA_S = 1.0
KONUM_TOLERANSI_M = 0.01
HAREKET_KMH = 3.0
TEST_KLASORU = os.path.join(KOK, "veri", "test")
GELISTIRME_KLASORU = os.path.join(KOK, "veri", "gelistirme")
TUR_ADI = {"test": "TEST", "gelistirme": "geliştirme",
           "diger": "veri/ dışında (bekçiler UYGULANMADI; resmî sonuç değildir)"}


ACIKLAMALAR = [
    ("(dosya)", "", "", "", "Claude ile sürücünün çukur noktalarının karşılaştırması (algoritma/karsilastir.py). Konumlar "
     "ham GPS izinde t_s anına doğrusal ara değerdir (iki taraf için aynı kural); mesafe büyük daire mesafesidir."),
    ("(tümü)", "esik_m", "ondalık", "m", "Eşik: mesafesi bu değer ve altında olan işaret-Claude çifti doğru sayılır. "
     "Her eşik için ayrı satırlar vardır; QGIS'te esik_m ile süzün."),
    ("eslesmeler", "(geometri)", "çizgi", "", "Sürücünün işaretinden eşleştiği Claude noktasına çizgi."),
    ("eslesmeler", "fark_s", "ondalık", "s", "insan_t_s − claude_t_s: basış darbeden ne kadar sonra (eksi: önce)."),
    ("eslesmeler", "mesafe_m", "ondalık", "m", "İki nokta arasındaki mesafe."),
    ("eslesmeyenler", "taraf, sonuc", "metin", "", "insan / kacirilan: sürücü işaretledi, Claude bulmadı; "
     "claude / fazladan: Claude buldu, sürücü işaretlemedi."),
    ("eslesmeyenler", "en_yakin_m", "ondalık", "m", "Aynı kayıtta öteki taraftaki en yakın noktaya mesafe. Eşikten küçükse "
     "o nokta başka bir noktayla eşleşmiştir (eşleşme bire birdir)."),
    ("dislananlar", "neden", "metin", "", "Karşılaştırma dışı: ekran / telefon tuşu işareti (basış telefonu sarsar) "
     "veya böyle bir işarete 1 sn'den yakın Claude noktası."),
    ("ozet", "duyarlilik, kesinlik", "ondalık", "0-1", "Duyarlılık = doğru / işaret; kesinlik = doğru / Claude noktası. "
     "Payda sıfırsa boş."),
]


# ------------------------------------------------------------------------------------------------ eşleştirme

def eslestir(isaretler, noktalar, esik):
    """Bire bir, aynı kayıt içinde, en yakın çift önce. isaretler / noktalar: [{'kayit_no', 't_s', 'enlem', 'boylam', ...}].
    Döner: (çiftler [(i, c, mesafe)], eşleşmeyen işaret indeksleri, eşleşmeyen nokta indeksleri)."""
    adaylar = []
    for i, a in enumerate(isaretler):
        for c, b in enumerate(noktalar):
            if a["kayit_no"] != b["kayit_no"]:
                continue
            d = mesafe_m(a["enlem"], a["boylam"], b["enlem"], b["boylam"])
            if d <= esik:
                adaylar.append((d, abs(a["t_s"] - b["t_s"]), i, c))
    adaylar.sort()
    kullanilan_i, kullanilan_c, ciftler = set(), set(), []
    for d, _, i, c in adaylar:
        if i in kullanilan_i or c in kullanilan_c:
            continue
        kullanilan_i.add(i)
        kullanilan_c.add(c)
        ciftler.append((i, c, d))
    ciftler.sort(key=lambda p: (isaretler[p[0]]["kayit_no"], isaretler[p[0]]["t_s"]))
    return (ciftler, [i for i in range(len(isaretler)) if i not in kullanilan_i],
            [c for c in range(len(noktalar)) if c not in kullanilan_c])


def oran(pay, payda):
    return None if payda == 0 else pay / payda


def sayilar(isaretler, noktalar, esik):
    ciftler, kacirilan, fazladan = eslestir(isaretler, noktalar, esik)
    return {"esik_m": esik, "dogru": len(ciftler), "kacirilan": len(kacirilan), "fazladan": len(fazladan),
            "duyarlilik": oran(len(ciftler), len(isaretler)), "kesinlik": oran(len(ciftler), len(noktalar)),
            "ciftler": ciftler, "kacirilan_i": kacirilan, "fazladan_c": fazladan}


NEDEN_KONUMSUZ = "konumu yok (kayıtta GPS yok)"
NEDEN_KAYNAK = "ekran / telefon tuşu işareti (telefonu sarsar)"
NEDEN_YAKIN = "dışlanan bir işarete 1 sn'den yakın"


def dislama(isaretler, noktalar):
    """Karşılaştırma dışı: konumsuz işaretler, ekran / telefon tuşu işaretleri ve bu ikincilere 1 sn'den yakın Claude
    noktaları. Dışlananlara 'neden' yazılır. Döner: (dahil işaretler, dahil noktalar, dışı işaretler, dışı noktalar)."""
    dahil_i, disi_i, kaynakli = [], [], []
    for a in isaretler:
        if a["enlem"] is None:
            disi_i.append(dict(a, neden=NEDEN_KONUMSUZ))
        elif a["kaynak"] in DISLANAN_KAYNAKLAR:
            disi_i.append(dict(a, neden=NEDEN_KAYNAK))
            kaynakli.append(a)
        else:
            dahil_i.append(a)
    dahil_c, disi_c = [], []
    for b in noktalar:
        if any(a["kayit_no"] == b["kayit_no"] and abs(a["t_s"] - b["t_s"]) <= DISLAMA_S for a in kaynakli):
            disi_c.append(dict(b, neden=NEDEN_YAKIN))
        else:
            dahil_c.append(b)
    return dahil_i, dahil_c, disi_i, disi_c


def en_yakin(isaretler, noktalar):
    """Her işaret için aynı kayıttaki en yakın Claude noktası: [(mesafe, basış − darbe s, işaret hızı)]."""
    sonuc = []
    for a in isaretler:
        aday = [(mesafe_m(a["enlem"], a["boylam"], b["enlem"], b["boylam"]), a["t_s"] - b["t_s"])
                for b in noktalar if b["kayit_no"] == a["kayit_no"]]
        if aday:
            d, dt = min(aday)
            sonuc.append((d, dt, a.get("hiz_kmh")))
    return sonuc


# ------------------------------------------------------------------------------------------------ denetimler

def konum_denetle(gun, kayitlar, ad):
    """Dosyadaki konum, ham izde konum_at(t_s) ile aynı mı? En büyük farkı döner; tolerans aşılırsa durur."""
    en_buyuk = 0.0
    for r in kayitlar:
        if r["enlem"] is None:
            continue  # konumsuz işaret: dışlanır
        k = gun.kayitlar.get(r["kayit_no"])
        if k is None:
            raise VeriHatasi(f"{ad}: ham dosyada olmayan kayıt {r['kayit_no']}")
        p = konum_at(k.gps, r["t_s"])
        if p is None:
            raise VeriHatasi(f"{ad}: {r['kayit_no']} kaydında GPS yok")
        d = mesafe_m(p[0], p[1], r["enlem"], r["boylam"])
        if d > KONUM_TOLERANSI_M:
            raise VeriHatasi(f"{ad}: {r['kayit_no']} t_s={r['t_s']} konumu ham izden {d:.3f} m farklı "
                             f"(konum kuralı uyuşmuyor; karşılaştırma yapılmaz)")
        en_buyuk = max(en_buyuk, d)
    return en_buyuk


def git(*arg):
    r = subprocess.run(["git", "-C", KOK, *arg], capture_output=True, text=True)
    return r.returncode, r.stdout.strip()


def muhur_denetle(yol):
    """Dosya origin/main'de birebir aynı mı (önce GitHub'a gönderilmiş mi)?"""
    rel = os.path.relpath(os.path.abspath(yol), KOK).replace(os.sep, "/")
    kod, uzak = git("rev-parse", f"origin/main:{rel}")
    if kod != 0:
        raise VeriHatasi(f"mühür yok: {rel} origin/main'de bulunamadı (önce commit + push; gerekirse git fetch)")
    _, yerel = git("hash-object", rel)
    if uzak != yerel:
        raise VeriHatasi(f"mühür bozuk: {rel} origin/main'dekinden farklı")


def tur_bul(on):
    yol = os.path.abspath(on)
    if yol.startswith(TEST_KLASORU + os.sep):
        return "test"
    if yol.startswith(GELISTIRME_KLASORU + os.sep):
        return "gelistirme"
    return "diger"


def bekciler(gunler_yol, esik):
    """Verinin türü ve seçilen eşik. Test verisinde mühür ve eşik dosyası denetlenir. Döner: (tür, eşik)."""
    turler = {tur_bul(on) for on, *_ in gunler_yol}
    if len(turler) > 1:
        raise VeriHatasi("test, geliştirme ve öteki veriler aynı raporda karşılaştırılmaz")
    tur = turler.pop()
    if tur != "test":
        return tur, esik
    if esik is not None:
        raise VeriHatasi("test verisinde eşik komut satırından verilmez; veri/test/esik.json kullanılır")
    esik_yol = os.path.join(TEST_KLASORU, "esik.json")
    if not os.path.exists(esik_yol):
        raise VeriHatasi("veri/test/esik.json yok (eşik testten önce kararlaştırılıp GitHub'a konmalı)")
    muhur_denetle(esik_yol)
    with open(esik_yol, encoding="utf-8") as f:
        secilen = float(json.load(f)["esik_m"])
    for _, _, _, claude in gunler_yol:
        muhur_denetle(claude)
    return tur, secilen


# ------------------------------------------------------------------------------------------------ gün

def gunleri_bul(yollar):
    gunler = []
    for y in yollar:
        adaylar = []
        if os.path.isdir(y):
            for kok, _, dosyalar in sorted(os.walk(y)):
                adaylar += [os.path.join(kok, d) for d in sorted(dosyalar) if d.endswith("_ham.gpkg")]
        else:
            adaylar.append(y)
        for ham in adaylar:
            if not ham.endswith("_ham.gpkg"):
                raise VeriHatasi(f"ham dosya adı '_ham.gpkg' ile bitmeli: {ham}")
            on = ham[: -len("_ham.gpkg")]
            eksik = [s for s in ("_insan.gpkg", "_claude.gpkg") if not os.path.exists(on + s)]
            if eksik:
                raise VeriHatasi(f"{os.path.basename(on)}: eksik dosya {', '.join(eksik)}")
            gunler.append((on, ham, on + "_insan.gpkg", on + "_claude.gpkg"))
    if not gunler:
        raise VeriHatasi("karşılaştırılacak gün bulunamadı (*_ham.gpkg + _insan.gpkg + _claude.gpkg)")
    return gunler


def gun_oku(on, ham, insan, claude):
    gun = ham_oku(ham)
    isaretler, insan_puan = insan_oku(insan)
    noktalar, claude_puan = claude_oku(claude)
    ad = os.path.basename(on)
    # Kayıtlar üç dosyada aynı olmalı (eksik kayıt sıfır sayılmaz, hata)
    h, i = set(gun.kayitlar), set(insan_puan)
    if h != i:
        raise VeriHatasi(f"{ad}: ham ve insan dosyasındaki kayıtlar farklı; yalnız hamda: {sorted(h - i)}, "
                         f"yalnız insanda: {sorted(i - h)}")
    gpsli = {n for n, k in gun.kayitlar.items() if len(k.gps) >= 2}
    if not gpsli <= set(claude_puan):
        raise VeriHatasi(f"{ad}: Claude dosyasında puan satırı olmayan kayıt: {sorted(gpsli - set(claude_puan))}")
    surumler = {r["algoritma"] for r in list(noktalar) + list(claude_puan.values())}
    fark = {"insan": konum_denetle(gun, isaretler, f"{ad} insan"), "claude": konum_denetle(gun, noktalar, f"{ad} claude")}
    return {"ad": ad, "on": on, "gun": gun, "isaretler": isaretler, "insan_puan": insan_puan, "noktalar": noktalar,
            "claude_puan": claude_puan, "surumler": surumler, "konum_farki": fark, "claude_yol": claude,
            "claude_ozet": icerik_ozeti(claude)}


# ------------------------------------------------------------------------------------------------ çıktı

def yuzde(v):
    return "tanımsız" if v is None else f"%{100 * v:.0f}"


def sayi(v, b=1):
    return "-" if v is None else f"{v:.{b}f}".replace(".", ",")


def dagilim(degerler, b=1):
    if not degerler:
        return "veri yok"
    return (f"en küçük {sayi(min(degerler), b)}, ortanca {sayi(yuzdelik(degerler, 50), b)}, "
            f"%68 {sayi(yuzdelik(degerler, 68), b)}, "
            f"%90 {sayi(yuzdelik(degerler, 90), b)}, %95 {sayi(yuzdelik(degerler, 95), b)}, "
            f"en büyük {sayi(max(degerler), b)} (n = {len(degerler)})")


def gpkg_yaz(g, esikler, yol):
    db = ac(g["claude_yol"])
    son = db.execute("SELECT max(last_change) FROM gpkg_contents").fetchone()[0] or "1970-01-01T00:00:00.000Z"
    db.close()
    ad_kesit = {n: (k.oz["kesit"], k.oz["kesit_adi"]) for n, k in g["gun"].kayitlar.items()}
    gp = GeoPackage(yol, son)
    gp.katman("eslesmeler", "LINESTRING", [
        ("esik_m", "REAL"), ("kayit_no", "TEXT"), ("kesit", "TEXT"), ("kesit_adi", "TEXT"), ("insan_t_s", "REAL"),
        ("claude_t_s", "REAL"), ("fark_s", "REAL"), ("mesafe_m", "REAL"), ("kaynak", "TEXT"),
    ], "Doğru sayılan eşleşmeler: sürücünün işaretinden Claude noktasına çizgi (her eşik için ayrı satırlar; esik_m ile süzün).")
    gp.katman("eslesmeyenler", "POINT", [
        ("esik_m", "REAL"), ("kayit_no", "TEXT"), ("kesit", "TEXT"), ("kesit_adi", "TEXT"), ("taraf", "TEXT"),
        ("sonuc", "TEXT"), ("t_s", "REAL"), ("en_yakin_m", "REAL"), ("kaynak", "TEXT"),
    ], "Eşleşmeyen noktalar: kaçırılan (sürücü işaretledi, Claude bulmadı) ve fazladan (Claude buldu, sürücü işaretlemedi).")
    gp.katman("dislananlar", "POINT", [
        ("kayit_no", "TEXT"), ("taraf", "TEXT"), ("t_s", "REAL"), ("kaynak", "TEXT"), ("neden", "TEXT"),
    ], "Karşılaştırma dışı: ekran / telefon tuşu işaretleri ve onlara 1 sn'den yakın Claude noktaları.")
    gp.katman("ozet", None, [
        ("esik_m", "REAL"), ("isaret", "INTEGER"), ("claude", "INTEGER"), ("dogru", "INTEGER"), ("kacirilan", "INTEGER"),
        ("fazladan", "INTEGER"), ("duyarlilik", "REAL"), ("kesinlik", "REAL"),
    ], "Eşik başına sayılar (bu gün).")
    I, C = g["dahil_i"], g["dahil_c"]
    for e in esikler:
        s = sayilar(I, C, e)
        cizgiler = []
        for i, c, d in s["ciftler"]:
            a, b = I[i], C[c]
            cizgiler.append((cizgi([(a["boylam"], a["enlem"]), (b["boylam"], b["enlem"])]), e, a["kayit_no"],
                             *ad_kesit[a["kayit_no"]], a["t_s"], b["t_s"], round(a["t_s"] - b["t_s"], 3), round(d, 2),
                             a["kaynak"]))
        if cizgiler:
            gp.ekle("eslesmeler", cizgiler)
        tek = []
        for i in s["kacirilan_i"]:
            a = I[i]
            yakin = [mesafe_m(a["enlem"], a["boylam"], b["enlem"], b["boylam"]) for b in C if b["kayit_no"] == a["kayit_no"]]
            tek.append((nokta(a["boylam"], a["enlem"]), e, a["kayit_no"], *ad_kesit[a["kayit_no"]], "insan", "kacirilan",
                        a["t_s"], round(min(yakin), 2) if yakin else None, a["kaynak"]))
        for c in s["fazladan_c"]:
            b = C[c]
            yakin = [mesafe_m(a["enlem"], a["boylam"], b["enlem"], b["boylam"]) for a in I if a["kayit_no"] == b["kayit_no"]]
            tek.append((nokta(b["boylam"], b["enlem"]), e, b["kayit_no"], *ad_kesit[b["kayit_no"]], "claude", "fazladan",
                        b["t_s"], round(min(yakin), 2) if yakin else None, None))
        if tek:
            gp.ekle("eslesmeyenler", tek)
        gp.ekle("ozet", [(e, len(I), len(C), s["dogru"], s["kacirilan"], s["fazladan"],
                          None if s["duyarlilik"] is None else round(s["duyarlilik"], 4),
                          None if s["kesinlik"] is None else round(s["kesinlik"], 4))])
    disi = [(nokta(a["boylam"], a["enlem"]), a["kayit_no"], "insan", a["t_s"], a["kaynak"], a["neden"])
            for a in g["disi_i"] if a["enlem"] is not None]  # konumsuz işaretler yalnızca raporda sayılır
    disi += [(nokta(b["boylam"], b["enlem"]), b["kayit_no"], "claude", b["t_s"], None, b["neden"]) for b in g["disi_c"]]
    if disi:
        gp.ekle("dislananlar", disi)
    gp.katman("aciklamalar", None, [("katman", "TEXT"), ("alan", "TEXT"), ("tur", "TEXT"), ("birim", "TEXT"),
                                    ("aciklama", "TEXT")], "Bu dosyadaki katman ve alanların açıklaması (veri sözlüğü).")
    gp.ekle("aciklamalar", ACIKLAMALAR)
    gp.kapat()


def rapor(gunler, esikler, secilen, tur):
    I = [a for g in gunler for a in g["dahil_i"]]
    C = [b for g in gunler for b in g["dahil_c"]]
    surumler = sorted(set().union(*(g["surumler"] for g in gunler)))
    s = []
    s.append("# Karşılaştırma raporu: Claude ↔ sürücü\n")
    s.append(f"- Veri: {TUR_ADI[tur]}; günler: {', '.join(g['ad'] for g in gunler)}")
    s.append(f"- Algoritma sürümü: {', '.join(surumler) or '-'}")
    for g in gunler:
        s.append(f"- {g['ad']}_claude.gpkg içerik özeti: `{g['claude_ozet']}`")
    s.append(f"- Seçilen eşik: {sayi(secilen) + ' m' if secilen is not None else 'henüz seçilmedi'}\n")
    s.append("## Kural\n")
    kf = max(max(g["konum_farki"].values()) for g in gunler)
    s.append(f"- Konum: iki nokta da ham GPS izinde t_s anına doğrusal ara değer. Dosyalardaki konumlar bu kurala "
             f"uyuyor (en büyük fark {sayi(kf * 1000)} mm).")
    s.append("- Eşleştirme: aynı kayıt içinde, bire bir, en yakın çift önce, mesafe ≤ eşik.")
    s.append("- Doğru = eşleşen işaret; kaçırılan = eşleşmeyen işaret; fazladan = eşleşmeyen Claude noktası.")
    s.append("- Duyarlılık = doğru / işaret sayısı; kesinlik = doğru / Claude noktası sayısı.")
    def say(liste, neden):
        return sum(1 for g in gunler for r in g[liste] if r["neden"] == neden)
    s.append(f"- Dışlanan: ekran / telefon tuşu işaretleri ({say('disi_i', NEDEN_KAYNAK)}), onlara 1 sn'den yakın Claude "
             f"noktaları ({say('disi_c', NEDEN_YAKIN)}), konumu olmayan işaretler ({say('disi_i', NEDEN_KONUMSUZ)}).\n")
    s.append("## Sonuç\n")
    s.append(f"İşaret: {len(I)}, Claude noktası: {len(C)}\n")
    s.append("| Eşik | Doğru | Kaçırılan | Fazladan | Duyarlılık | Kesinlik |")
    s.append("|---|---|---|---|---|---|")
    for e in esikler:
        t = sayilar(I, C, e)
        isim = f"**{sayi(e)} m (seçilen)**" if e == secilen else f"{sayi(e)} m"
        s.append(f"| {isim} | {t['dogru']} | {t['kacirilan']} | {t['fazladan']} | {yuzde(t['duyarlilik'])} | "
                 f"{yuzde(t['kesinlik'])} |")
    s.append("")
    s.append("## Eşik kararı için\n")
    dog = [p["dogruluk_m"] for g in gunler for k in g["gun"].kayitlar.values() for p in k.gps
           if p["dogruluk_m"] is not None and (p["hiz_kmh"] or 0) >= HAREKET_KMH]
    s.append(f"- GPS doğruluğu (`dogruluk_m`, hareket halindeki noktalar, m): {dagilim(dog)}")
    ey = en_yakin(I, C)
    s.append(f"- Her işaretin aynı kayıttaki en yakın Claude noktasına uzaklığı (m): {dagilim([d for d, _, _ in ey])}")
    s.append(f"- Aynı çiftlerde zaman farkı, basış − darbe (s; eksi: basış darbeden önce): "
             f"{dagilim([dt for _, dt, _ in ey], 2)}")
    s.append(f"- İşaret anındaki hız (km/h): {dagilim([h for _, _, h in ey if h is not None])}")
    s.append("- Not: işaret ve Claude noktası aynı GPS izinden konum aldığı için GPS'in kendi hatası büyük ölçüde "
             "sadeleşir; mesafeyi çoğunlukla basış gecikmesi × hız belirler.\n")
    s.append("## Kayıt başına\n")
    ana = secilen if secilen is not None else 10.0
    s.append(f"Doğru sütunu {sayi(ana)} m eşikle.\n")
    s.append("| Kayıt | Kesit | Ad | İşaret | Claude | Doğru | İnsan puanı | Claude puanı |")
    s.append("|---|---|---|---|---|---|---|---|")
    puan_ciftleri = []
    for g in gunler:
        for n, k in g["gun"].kayitlar.items():
            ik = [a for a in g["dahil_i"] if a["kayit_no"] == n]
            ck = [b for b in g["dahil_c"] if b["kayit_no"] == n]
            t = sayilar(ik, ck, ana)
            ip, cp = g["insan_puan"].get(n, {}), g["claude_puan"].get(n, {})
            ins = ip.get("puan") if ip.get("durum") == "puanlandi" else None
            cla = cp.get("puan")
            if ins is not None and cla is not None:
                puan_ciftleri.append((ins, cla))
            s.append(f"| {n} | {k.oz['kesit'] or '-'} | {k.oz['kesit_adi'] or ''} | {len(ik)} | {len(ck)} | {t['dogru']} | "
                     f"{ins if ins is not None else (ip.get('durum') or '-')} | {cla if cla is not None else '-'} |")
    s.append("")
    s.append("## Konfor puanı\n")
    if puan_ciftleri:
        n = len(puan_ciftleri)
        tam = sum(1 for a, b in puan_ciftleri if a == b)
        bir = sum(1 for a, b in puan_ciftleri if abs(a - b) <= 1)
        maf = sum(abs(a - b) for a, b in puan_ciftleri) / n
        s.append(f"Puanlanmış {n} kayıtta: tam uyum {tam} ({yuzde(tam / n)}), ±1 içinde {bir} ({yuzde(bir / n)}), "
                 f"ortalama mutlak fark {sayi(maf, 2)} puan.")
    else:
        s.append("Karşılaştırılacak puan yok.")
    if any(v.startswith("0-") for v in surumler):
        s.append("\n**Uyarı:** algoritma yer tutucu (\"0-\" sürüm); sonuçlar yalnızca altyapının çalıştığını gösterir.")
    return "\n".join(s) + "\n"


def main():
    ap = argparse.ArgumentParser(description="Claude ↔ sürücü karşılaştırması (hocanın ölçütü).")
    ap.add_argument("yollar", nargs="+", help="klasörler veya *_ham.gpkg dosyaları (yanında _insan ve _claude olmalı)")
    ap.add_argument("--esik", type=float, help="seçilen eşik (m); yalnızca geliştirme verisinde")
    ap.add_argument("--cikti", help="raporun yazılacağı klasör (varsayılan: ilk yol)")
    a = ap.parse_args()
    try:
        gunler_yol = gunleri_bul(a.yollar)
        tur, secilen = bekciler(gunler_yol, a.esik)
        gunler = []
        for on, ham, insan, claude in gunler_yol:
            g = gun_oku(on, ham, insan, claude)
            if tur == "test" and any(v.startswith("0-") for v in g["surumler"]):
                raise VeriHatasi(f"{g['ad']}: yer tutucu (\"0-\") sürümle test karşılaştırması yapılmaz")
            g["dahil_i"], g["dahil_c"], g["disi_i"], g["disi_c"] = dislama(g["isaretler"], g["noktalar"])
            gunler.append(g)
    except VeriHatasi as e:
        print(f"HATA: {e}")
        sys.exit(1)
    esikler = sorted(set(EK_ESIKLER + ([secilen] if secilen is not None else [])))
    for g in gunler:
        gpkg_yaz(g, esikler, g["on"] + "_karsilastirma.gpkg")
        print(f"QGIS katmanı: {g['on']}_karsilastirma.gpkg")
    cikti = a.cikti or (a.yollar[0] if os.path.isdir(a.yollar[0]) else os.path.dirname(a.yollar[0]))
    yol = os.path.join(cikti, "karsilastirma_raporu.md")
    metin = rapor(gunler, esikler, secilen, tur)
    with open(yol, "w", encoding="utf-8") as f:
        f.write(metin)
    print(f"Rapor: {yol}\n")
    print(metin)


if __name__ == "__main__":
    main()
