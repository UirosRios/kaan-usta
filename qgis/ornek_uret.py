"""Yapay bir sürüş günü üretir ve QGIS için üç GeoPackage dosyası yazar.

Amaç yalnızca dosya biçimini (katmanlar, alanlar, birimler) göstermek ve onaylatmaktır; **gerçek sürüş değildir**.
Konum YTÜ Davutpaşa Yerleşkesi iç yollarıdır (uygulamadaki test sürüşü turunun parçaları). Sarsıntı, darbeler,
GPS hatası ve gecikmesi, sürücünün tepki süresi yapay olarak üretilir. Claude katmanındaki değerler gerçek algoritma
değildir (henüz yok): basit bir yer tutucu hesapla doldurulur.

Çalıştırma (deponun kökünden):  python qgis/ornek_uret.py
Çıktı: qgis/ornek/ornek_20261120_ham.gpkg, _insan.gpkg, _claude.gpkg
Sabit tohum ve sabit tarih kullanılır: aynı kod her seferinde aynı dosyaları üretir.
"""

import math
import os
import random
import sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gpkg import GeoPackage, cizgi, nokta  # noqa: E402

TOHUM = 20261120
GUN = "20261120"
SON_DEGISIKLIK = "2026-11-20T12:00:00.000Z"
YEREL = timezone(timedelta(hours=3))  # İstanbul
CIKTI = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ornek")
NOT = "YAPAY ÖRNEK VERİ: gerçek sürüş değildir, yalnızca dosya biçimini göstermek için üretildi. "
STIL_KLASORU = os.path.join(os.path.dirname(os.path.abspath(__file__)), "stiller")
STIL_NOTU = "Kullanıcının QGIS projesinden alınan görünüm (qgis/stil_cikar.py)."
CLAUDE_NOT = "YER TUTUCU: algoritma henüz yok; değerler biçimi göstermek için basit bir hesapla dolduruldu. "

# Uygulamadaki test sürüşü turu (lib/test_surusu.dart), YTÜ Davutpaşa iç yolları
TUR = [
    (41.027878, 28.889648), (41.027248, 28.889079), (41.026890, 28.888808), (41.026509, 28.888473),
    (41.026281, 28.888188), (41.025124, 28.886972), (41.025025, 28.886894), (41.024961, 28.886894),
    (41.024931, 28.886935), (41.024910, 28.887032), (41.024844, 28.887174), (41.024468, 28.887703),
    (41.022462, 28.891055), (41.022316, 28.891373), (41.022288, 28.891791), (41.022294, 28.891899),
    (41.022317, 28.891978), (41.023058, 28.893564), (41.023402, 28.893673), (41.024208, 28.893578),
    (41.024384, 28.893583), (41.024557, 28.893640),
]
KESITLER = {"K01": (0, 4), "K02": (11, 12), "K03": (17, 21)}  # turdaki nokta aralıkları
# Kullanıcının Kayıtlar sayfasında verdiği kesit adı (K03'e ad verilmemiş: boş görünür)
KESIT_ADI = {"K01": "Kuzey yolu", "K02": "Parke yol", "K03": None}

# Zemin: 15 km/h'te dikey sarsıntı RMS'i (m/s², telefon gidonda; v1 Kadıköy ölçümleri düzeyinde)
ZEMIN_RMS = {"iyi_asfalt": 3.6, "yamali_asfalt": 5.2, "parke": 9.5}
# Darbe türleri: sönümlü salınım frekansı (Hz), sönüm süresi (s), arka tekerin ön tekere oranı
DARBE = {"cukur": (11.0, 0.05, 0.55), "rogar": (13.0, 0.04, 0.6), "kasis": (4.5, 0.10, 0.8), "ray": (15.0, 0.035, 0.9)}

# Beş kayıt: K01 iki yönde, K02 bir kez, K03 iki yönde. Olay konumları kesitin ileri yönünde metre cinsinden.
# vurulan: bu geçişte tekerin denk geldiği olaylar; isaret: sürücünün bastıkları; puan None = "Hatırlamıyorum".
KAYITLAR = [
    dict(kesit="K01", ters=False, saat=(10, 15, 2), zemin="iyi_asfalt", hiz=16.5,
         olaylar=[(70, "cukur", 38.0), (150, "rogar", 22.0)], vurulan={70, 150}, isaret={70, 150}, puan=4),
    dict(kesit="K01", ters=True, saat=(10, 19, 40), zemin="iyi_asfalt", hiz=17.0,
         olaylar=[(70, "cukur", 38.0), (150, "rogar", 22.0)], vurulan={150}, isaret={150}, puan=4),
    dict(kesit="K02", ters=False, saat=(10, 26, 15), zemin="parke", hiz=11.5,
         olaylar=[(120, "kasis", 30.0), (250, "ray", 28.0)], vurulan={120, 250}, isaret={120, 250}, puan=2),
    dict(kesit="K03", ters=False, saat=(10, 34, 5), zemin="yamali_asfalt", hiz=15.0,
         olaylar=[(90, "cukur", 35.0)], vurulan={90}, isaret={90}, puan=None),
    dict(kesit="K03", ters=True, saat=(10, 37, 30), zemin="yamali_asfalt", hiz=15.5,
         olaylar=[(90, "cukur", 35.0)], vurulan=set(), isaret=set(), puan=3),
]

G = 9.81
BETA = math.radians(35)  # telefonun gidondaki eğimi
U = (0.0, math.sin(BETA), math.cos(BETA))  # yukarı, telefon eksenlerinde
F = (0.0, math.cos(BETA), -math.sin(BETA))  # ileri
L = (-1.0, 0.0, 0.0)  # sol

# Yerel düzlem (metre) <-> enlem/boylam
LAT0, LON0 = 41.025, 28.890
MX = 111320.0 * math.cos(math.radians(LAT0))
MY = 110574.0


def xy(enlem, boylam):
    return ((boylam - LON0) * MX, (enlem - LAT0) * MY)


def enlem_boylam(x, y):
    return (LAT0 + y / MY, LON0 + x / MX)


class Yol:
    def __init__(self, noktalar):
        self.p = [xy(a, b) for a, b in noktalar]
        self.s = [0.0]
        for i in range(1, len(self.p)):
            self.s.append(self.s[-1] + math.dist(self.p[i - 1], self.p[i]))
        self.uzunluk = self.s[-1]

    def konum(self, s):
        s = min(max(s, 0.0), self.uzunluk)
        for i in range(1, len(self.s)):
            if s <= self.s[i] or i == len(self.s) - 1:
                f = (s - self.s[i - 1]) / max(self.s[i] - self.s[i - 1], 1e-9)
                (x0, y0), (x1, y1) = self.p[i - 1], self.p[i]
                return (x0 + f * (x1 - x0), y0 + f * (y1 - y0))

    def yon(self, s):  # doğudan saat yönünün tersine açı (radyan)
        a, b = self.konum(s - 3), self.konum(s + 3)
        return math.atan2(b[1] - a[1], b[0] - a[0])


def renkli_gurultu(rng, n, f0=14.0, fs=200.0, r=0.93):
    """Birim RMS'li, f0 çevresinde yoğunlaşan titreşim (ikinci dereceden rezonatör)."""
    th = 2 * math.pi * f0 / fs
    a1, a2 = 2 * r * math.cos(th), -r * r
    y1 = y2 = 0.0
    out = []
    for i in range(n + 400):
        y = a1 * y1 + a2 * y2 + rng.gauss(0, 1)
        y2, y1 = y1, y
        if i >= 400:
            out.append(y)
    s = math.sqrt(sum(v * v for v in out) / len(out))
    return [v / s for v in out]


def salinim(tau, f, sonum):
    if tau < 0 or tau > 8 * sonum:
        return 0.0
    return math.exp(-tau / sonum) * math.sin(2 * math.pi * f * tau)


def salinim_tepesi(f, sonum):
    return max(salinim(i * 0.0002, f, sonum) for i in range(1, 2000))


def ara(dizi, t, dt):
    """Düzenli zaman ızgarasındaki diziden doğrusal ara değer."""
    k = t / dt
    i = int(math.floor(k))
    if i < 0:
        return dizi[0]
    if i >= len(dizi) - 1:
        return dizi[-1]
    f = k - i
    return dizi[i] + f * (dizi[i + 1] - dizi[i])


def zaman_utc(t):
    return t.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def zaman_yerel(t):
    return t.astimezone(YEREL).strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]


def kayit_uret(rng, spec):
    i0, i1 = KESITLER[spec["kesit"]]
    noktalar = TUR[i0:i1 + 1]
    if spec["ters"]:
        noktalar = noktalar[::-1]
    yol = Yol(noktalar)
    Ly = yol.uzunluk

    # --- Hareket: 5 sn duruş, hızlanma, seyir, yavaşlama, 5 sn duruş ---
    dt = 0.01
    T, S, V, A = [], [], [], []
    t = s = v = 0.0
    durdu = None
    while True:
        if t < 5.0 or durdu is not None:
            hedef = 0.0
        else:
            seyir = spec["hiz"] / 3.6 * (1 + 0.07 * math.sin(2 * math.pi * t / 23))
            hedef = min(seyir, math.sqrt(2 * 1.0 * max(Ly - s, 0.0)))
        dv = max(-1.5 * dt, min(1.2 * dt, hedef - v))
        v = max(0.0, v + dv)
        s = min(Ly, s + v * dt)
        T.append(t), S.append(s), V.append(v), A.append(dv / dt)
        if durdu is None and t > 5.0 and Ly - s < 0.3 and v < 0.25:
            durdu = t
            v = 0.0
        if durdu is not None and t >= durdu + 5.0:
            break
        t += dt
    sure = T[-1]
    X, Y, PSI = [], [], []
    onceki = None
    for s_ in S:
        x_, y_ = yol.konum(s_)
        X.append(x_), Y.append(y_)
        p = yol.yon(s_)
        if onceki is not None:  # açıyı sürekli tut
            while p - onceki > math.pi:
                p -= 2 * math.pi
            while p - onceki < -math.pi:
                p += 2 * math.pi
        PSI.append(p)
        onceki = p
    PSID = [0.0] * len(PSI)
    for i in range(1, len(PSI)):
        PSID[i] = (PSI[i] - PSI[i - 1]) / dt
    w = 15  # 0,3 sn kayan ortalama (köşelerdeki ani sıçramayı yumuşat)
    PSID = [sum(PSID[max(0, i - w):i + w + 1]) / len(PSID[max(0, i - w):i + w + 1]) for i in range(len(PSID))]

    # Olayların vurulduğu anlar (kesitin ileri yönündeki konum → bu geçişin yönü)
    vuruslar = []
    for s_e, tur, genlik in spec["olaylar"]:
        if s_e not in spec["vurulan"]:
            continue
        s_gecis = Ly - s_e if spec["ters"] else s_e
        t_e = next(T[i] for i in range(len(S)) if S[i] >= s_gecis)
        vuruslar.append((t_e, tur, genlik, s_e))

    # --- İvmeölçer ve jiroskop (kendi örnekleme anlarında, ~200 Hz, küçük zaman titremesi) ---
    def ornek_anlari(t0, hz):
        anlar, k = [], 0
        while True:
            ta = t0 + k / hz + rng.gauss(0, 0.00015)
            if ta > sure:
                return anlar
            anlar.append(ta)
            k += 1

    ta_ivme = ornek_anlari(0.0021, 199.6)
    ta_jiro = ornek_anlari(0.0037, 199.2)
    n = len(ta_ivme)
    g_dikey = renkli_gurultu(rng, n)
    g_ileri = renkli_gurultu(rng, n, f0=9.0)
    g_yan = renkli_gurultu(rng, n, f0=11.0)
    z_rms = ZEMIN_RMS[spec["zemin"]]
    dokunmalar = [1.6, sure - 1.8]  # BAŞLAT ve DURDUR'a basarken telefon sarsılır (durağanken)
    tepe = {k: salinim_tepesi(f, so) for k, (f, so, _) in DARBE.items()}

    def darbe_dikey(t_):
        a = 0.0
        for t_e, tur, genlik, _ in vuruslar:
            f, so, arka = DARBE[tur]
            gecikme = 0.85 / max(ara(V, t_e, dt), 0.5)  # arka teker
            a += genlik * (salinim(t_ - t_e, f, so) + arka * salinim(t_ - t_e - gecikme, f, so)) / tepe[tur]
        return a

    ivme = []
    for k, ta in enumerate(ta_ivme):
        v_ = ara(V, ta, dt)
        rms = z_rms * (max(v_, 0.0) * 3.6 / 15) ** 0.65 if v_ > 0.8 else 0.06
        a_d = g_dikey[k] * rms + darbe_dikey(ta)
        a_i = ara(A, ta, dt) + 0.3 * rms * g_ileri[k]
        a_y = v_ * ara(PSID, ta, dt) + 0.35 * rms * g_yan[k]
        dok = sum(5.0 * salinim(ta - td, 7.0, 0.08) for td in dokunmalar)
        ivme.append((ta, *[
            round(G * U[j] + a_d * U[j] + a_i * F[j] + a_y * L[j] + dok * (U[j] + F[j]) * 0.7 + rng.gauss(0, 0.03), 4)
            for j in range(3)]))

    jiro = []
    for ta in ta_jiro:
        v_ = ara(V, ta, dt)
        rms = z_rms * (max(v_, 0.0) * 3.6 / 15) ** 0.65 if v_ > 0.8 else 0.06
        q = sum(g * 0.033 * salinim(ta - t_e, 6.0, 0.08) / 0.66 for t_e, _, g, _ in vuruslar)  # gidonun öne-arkaya dönmesi
        dok = sum(0.6 * salinim(ta - td, 7.0, 0.08) for td in dokunmalar)
        r = ara(PSID, ta, dt)
        jiro.append((ta, *[
            round(r * U[j] + (q + dok) * L[j] + 0.02 * rms / 5 * rng.gauss(0, 1) + rng.gauss(0, 0.004) + 0.002, 5)
            for j in range(3)]))

    # --- Ham GPS: saniyede bir; gerçek konumdan 1 sn geride, zamanla ilişkili hata ---
    fixler = []
    nx = ny = 0.0
    rho = math.exp(-1 / 15)
    uydu = 11
    yuk = rng.gauss(0, 1)
    tf = 0.62
    while tf <= sure:
        nx = rho * nx + math.sqrt(1 - rho * rho) * 2.2 * rng.gauss(0, 1)
        ny = rho * ny + math.sqrt(1 - rho * rho) * 2.2 * rng.gauss(0, 1)
        tg = max(0.0, tf - 1.0)
        x_ = ara(X, tg, dt) + nx + rng.gauss(0, 0.5)
        y_ = ara(Y, tg, dt) + ny + rng.gauss(0, 0.5)
        v_ = ara(V, max(0.0, tf - 0.2), dt)
        hiz = max(0.0, v_ + rng.gauss(0, 0.12)) if v_ > 0.3 else abs(rng.gauss(0, 0.08))
        yon = None
        if hiz > 1.0:
            yon = round((90 - math.degrees(ara(PSI, tg, dt)) + rng.gauss(0, 2)) % 360, 1)
        uydu = min(15, max(8, uydu + rng.choice([-1, 0, 0, 0, 1])))
        yuk = 0.9 * yuk + rng.gauss(0, 0.6)
        enl, boy = enlem_boylam(x_, y_)
        fixler.append(dict(
            t=round(tf, 4), enlem=enl, boylam=boy, hiz_kmh=round(hiz * 3.6, 2), yon=yon,
            dogruluk=round(3.8 + abs(rng.gauss(0, 1.2)), 1), hiz_dog=round(0.4 + abs(rng.gauss(0, 0.2)), 2),
            yukseklik=round(72 + 0.01 * ara(S, tg, dt) + yuk, 1), dikey_dog=round(5 + abs(rng.gauss(0, 1.5)), 1), uydu=uydu))
        tf += 1.0 + rng.gauss(0, 0.002)

    return dict(spec=spec, sure=sure, ivme=ivme, jiro=jiro, fixler=fixler, vuruslar=vuruslar, V=V, dt=dt)


def dikey_sarsinti(ivme):
    """v1 uygulamasındaki yöntem: üç eksene 0,4 Hz birinci dereceden yüksek geçiren (Tustin), yerçekimi = ham − süzülmüş,
    dikey sarsıntı = süzülmüş titreşimin yerçekimi yönüne izdüşümü. Çıktı: [(t, dikey)]"""
    tau = 1 / (2 * math.pi * 0.4)
    onceki = None
    y = [0.0, 0.0, 0.0]
    out = []
    for t, ax, ay, az in ivme:
        a = (ax, ay, az)
        if onceki is not None:
            dt = max(t - onceki[0], 1e-4)
            k = 2 * tau / dt
            y = [k / (k + 1) * (a[j] - onceki[1][j]) + (k - 1) / (k + 1) * y[j] for j in range(3)]
        onceki = (t, a)
        g = [a[j] - y[j] for j in range(3)]
        gn = math.sqrt(sum(v * v for v in g)) or 1.0
        out.append((t, sum(y[j] * g[j] for j in range(3)) / gn))
    return out


def gps_ara(fixler, t, alan):
    if t <= fixler[0]["t"]:
        return fixler[0][alan]
    for i in range(1, len(fixler)):
        if t <= fixler[i]["t"]:
            a, b = fixler[i - 1], fixler[i]
            f = (t - a["t"]) / (b["t"] - a["t"])
            return a[alan] + f * (b[alan] - a[alan])
    return fixler[-1][alan]


def main():
    rng = random.Random(TOHUM)
    os.makedirs(CIKTI, exist_ok=True)
    kayitlar = []
    for spec in KAYITLAR:
        k = kayit_uret(rng, spec)
        h, m, s = spec["saat"]
        k["baslangic"] = datetime(2026, 11, 20, h, m, s, tzinfo=YEREL)
        k["kayit_no"] = f"{GUN}_{h:02d}{m:02d}{s:02d}"
        k["yon"] = "donus" if spec["ters"] else "gidis"
        k["dikey"] = dikey_sarsinti(k["ivme"])
        kayitlar.append(k)

    # ------------------------------------------------------------------ ham
    ham = GeoPackage(os.path.join(CIKTI, f"ornek_{GUN}_ham.gpkg"), SON_DEGISIKLIK)
    ham.katman("kayitlar", "LINESTRING", [
        ("kayit_no", "TEXT"), ("kesit", "TEXT"), ("kesit_adi", "TEXT"), ("yon", "TEXT"), ("baslangic", "DATETIME"),
        ("bitis", "DATETIME"),
        ("baslangic_yerel", "TEXT"), ("sure_s", "REAL"), ("uzunluk_m", "REAL"), ("ort_hiz_kmh", "REAL"),
        ("gps_nokta", "INTEGER"), ("ivme_hz", "REAL"), ("jiro_hz", "REAL"), ("cihaz", "TEXT"), ("ivme_sensoru", "TEXT"),
        ("jiro_sensoru", "TEXT"), ("scooter", "TEXT"), ("hava", "TEXT"), ("sicaklik_c", "REAL"), ("yagis_mm", "REAL"),
        ("ruzgar_kmh", "REAL"), ("veri_kaynagi", "TEXT"), ("uygulama_surumu", "TEXT"),
    ], NOT + "Her kayıt (bir kesitin bir geçişi) bir çizgi: ham GPS noktalarının birleşimi.")
    ham.katman("gps_noktalari", "POINT", [
        ("kayit_no", "TEXT"), ("kesit", "TEXT"), ("t_s", "REAL"), ("zaman", "DATETIME"), ("yerel_saat", "TEXT"),
        ("hiz_kmh", "REAL"), ("yon_derece", "REAL"), ("dogruluk_m", "REAL"), ("hiz_dogrulugu_kmh", "REAL"),
        ("yukseklik_m", "REAL"), ("dikey_dogruluk_m", "REAL"), ("uydu", "INTEGER"),
        ("dikey_rms", "REAL"), ("dikey_tepe", "REAL"), ("ivme_ornek", "INTEGER"),
    ], NOT + "Telefonun GPS alıcısından gelen her konum (ham, düzeltilmemiş) ve iki konum arasındaki sarsıntı özeti.")
    ham.katman("ivme", None, [("kayit_no", "TEXT"), ("t_s", "REAL"), ("x", "REAL"), ("y", "REAL"), ("z", "REAL")],
               NOT + "Ham ivmeölçer (m/s², yerçekimi dahil, telefon eksenleri), ~200 Hz.")
    ham.katman("jiroskop", None, [("kayit_no", "TEXT"), ("t_s", "REAL"), ("x", "REAL"), ("y", "REAL"), ("z", "REAL")],
               NOT + "Ham jiroskop (rad/s, telefon eksenleri), ~200 Hz.")

    for k in kayitlar:
        sp, fx = k["spec"], k["fixler"]
        bas = k["baslangic"]
        uz, hizlar = 0.0, []
        for i in range(1, len(fx)):
            if fx[i]["hiz_kmh"] >= 3 and fx[i - 1]["hiz_kmh"] >= 3:
                uz += math.dist(xy(fx[i - 1]["enlem"], fx[i - 1]["boylam"]), xy(fx[i]["enlem"], fx[i]["boylam"]))
        hizlar = [f["hiz_kmh"] for f in fx if f["hiz_kmh"] >= 3]
        ham.ekle("kayitlar", [(
            cizgi([(f["boylam"], f["enlem"]) for f in fx]), k["kayit_no"], sp["kesit"], KESIT_ADI[sp["kesit"]], k["yon"],
            zaman_utc(bas), zaman_utc(bas + timedelta(seconds=k["sure"])), zaman_yerel(bas)[:19], round(k["sure"], 1),
            round(uz, 1), round(sum(hizlar) / len(hizlar), 1), len(fx),
            round((len(k["ivme"]) - 1) / (k["ivme"][-1][0] - k["ivme"][0][0]), 1),
            round((len(k["jiro"]) - 1) / (k["jiro"][-1][0] - k["jiro"][0][0]), 1),
            "Yapay örnek cihaz (Android 14)", "yapay ivmeölçer", "yapay jiroskop", "Örnek scooter",
            "Parçalı bulutlu (yapay)", 14.2, 0.0, 11.0, "yapay_ornek", "2.0.0 (örnek)",
        )])
        # Sarsıntı özeti: önceki GPS konumundan bu konuma kadar olan ivme örnekleri
        satirlar, j, onceki_t = [], 0, -1e9
        dk = k["dikey"]
        for f in fx:
            parca = []
            while j < len(dk) and dk[j][0] <= f["t"]:
                if dk[j][0] > onceki_t:
                    parca.append(dk[j][1])
                j += 1
            onceki_t = f["t"]
            rms = math.sqrt(sum(v * v for v in parca) / len(parca)) if parca else None
            tepe = max(abs(v) for v in parca) if parca else None
            an = bas + timedelta(seconds=f["t"])
            satirlar.append((
                nokta(f["boylam"], f["enlem"]), k["kayit_no"], sp["kesit"], f["t"], zaman_utc(an), zaman_yerel(an),
                f["hiz_kmh"], f["yon"], f["dogruluk"], f["hiz_dog"], f["yukseklik"], f["dikey_dog"], f["uydu"],
                round(rms, 3) if rms is not None else None, round(tepe, 2) if tepe is not None else None, len(parca)))
        ham.ekle("gps_noktalari", satirlar)
        ham.ekle("ivme", [(k["kayit_no"], round(t, 4), x, y, z) for t, x, y, z in k["ivme"]])
        ham.ekle("jiroskop", [(k["kayit_no"], round(t, 4), x, y, z) for t, x, y, z in k["jiro"]])
    aciklamalar_ekle(ham, ACIKLAMA_HAM)
    ham.stiller(stilleri_oku(), STIL_NOTU)
    ham.kapat()

    # ------------------------------------------------------------------ insan
    insan = GeoPackage(os.path.join(CIKTI, f"ornek_{GUN}_insan.gpkg"), SON_DEGISIKLIK)
    insan.katman("insan_cukurlar", "POINT", [
        ("kayit_no", "TEXT"), ("kesit", "TEXT"), ("t_s", "REAL"), ("zaman", "DATETIME"), ("yerel_saat", "TEXT"),
        ("hiz_kmh", "REAL"), ("kaynak", "TEXT"),
    ], NOT + "Sürücünün çukur basışları; konum basış anındaki ham GPS konumu (çukurun birkaç metre ilerisi).")
    insan.katman("insan_puanlar", "LINESTRING", [
        ("kayit_no", "TEXT"), ("kesit", "TEXT"), ("kesit_adi", "TEXT"), ("puan", "INTEGER"), ("durum", "TEXT"),
        ("puanlama_zamani", "DATETIME"), ("isaret_sayisi", "INTEGER"),
    ], NOT + "Sürücünün kesite verdiği konfor puanı (1 çok kötü - 5 çok iyi); çizgi kaydın güzergâhı.")
    for k in kayitlar:
        sp, fx, bas = k["spec"], k["fixler"], k["baslangic"]
        isaretler = []
        for t_e, _, _, s_e in k["vuruslar"]:
            if s_e in sp["isaret"]:
                tb = round(t_e + rng.uniform(1.05, 1.6), 4)
                an = bas + timedelta(seconds=tb)
                isaretler.append((nokta(gps_ara(fx, tb, "boylam"), gps_ara(fx, tb, "enlem")), k["kayit_no"], sp["kesit"],
                                  tb, zaman_utc(an), zaman_yerel(an), round(gps_ara(fx, tb, "hiz_kmh"), 2), "kulaklik"))
        if isaretler:
            insan.ekle("insan_cukurlar", isaretler)
        bitis = bas + timedelta(seconds=k["sure"])
        insan.ekle("insan_puanlar", [(
            cizgi([(f["boylam"], f["enlem"]) for f in fx]), k["kayit_no"], sp["kesit"], KESIT_ADI[sp["kesit"]], sp["puan"],
            "puanlandi" if sp["puan"] is not None else "hatirlamiyorum",
            zaman_utc(bitis + timedelta(seconds=rng.uniform(6, 12))), len(isaretler))])
    aciklamalar_ekle(insan, ACIKLAMA_INSAN)
    insan.stiller(stilleri_oku(), STIL_NOTU)
    insan.kapat()

    # ------------------------------------------------------------------ claude (yer tutucu)
    cl = GeoPackage(os.path.join(CIKTI, f"ornek_{GUN}_claude.gpkg"), SON_DEGISIKLIK)
    cl.katman("claude_cukurlar", "POINT", [
        ("kayit_no", "TEXT"), ("kesit", "TEXT"), ("t_s", "REAL"), ("zaman", "DATETIME"), ("yerel_saat", "TEXT"),
        ("hiz_kmh", "REAL"), ("guven", "REAL"), ("tepe_ms2", "REAL"), ("algoritma", "TEXT"),
    ], NOT + CLAUDE_NOT + "Claude'un bulduğu çukur / ani sarsıntı noktaları (darbe anı ve GPS gecikmesi düzeltilmiş konum).")
    cl.katman("claude_puanlar", "LINESTRING", [
        ("kayit_no", "TEXT"), ("kesit", "TEXT"), ("kesit_adi", "TEXT"), ("puan", "INTEGER"), ("puan_ondalik", "REAL"),
        ("indeks_ms2", "REAL"),
        ("algoritma", "TEXT"),
    ], NOT + CLAUDE_NOT + "Claude'un kesite verdiği konfor puanı (1-5); çizgi kaydın güzergâhı.")
    ALG = "yer tutucu (algoritma henüz yok)"
    for k in kayitlar:
        sp, fx, bas = k["spec"], k["fixler"], k["baslangic"]
        # 0,5 sn pencereler: RMS, tepe ve tepe anı; yalnızca hareket (GPS hızı >= 3 km/h)
        pen = {}
        for t, d in k["dikey"]:
            w = int(t // 0.5)
            p = pen.setdefault(w, [0.0, 0, 0.0, t])
            p[0] += d * d
            p[1] += 1
            if abs(d) > p[2]:
                p[2], p[3] = abs(d), t
        hareket = {w: (math.sqrt(p[0] / p[1]), p[2], p[3]) for w, p in pen.items()
                   if gps_ara(fx, (w + 0.5) * 0.5, "hiz_kmh") >= 3}
        adaylar = []
        for w, (rms, tepe, tt) in sorted(hareket.items()):
            once = sorted(hareket[i][0] for i in range(w - 20, w) if i in hareket)
            sonra = sorted(hareket[i][0] for i in range(w + 1, w + 21) if i in hareket)
            taban = max([x[len(x) // 2] for x in (once, sonra) if x] or [0])
            if taban > 0 and tepe >= 4 * taban and tepe >= 10:
                if adaylar and tt - adaylar[-1][0] < 1.0:
                    if tepe > adaylar[-1][1]:
                        adaylar[-1] = (tt, tepe, tepe / taban)
                else:
                    adaylar.append((tt, tepe, tepe / taban))
        satir = []
        for tt, tepe, oran in adaylar:
            tk = tt + 1.0  # GPS 1 sn geride: darbe anının konumu 1 sn sonraki GPS konumunda
            an = bas + timedelta(seconds=tt)
            satir.append((nokta(gps_ara(fx, tk, "boylam"), gps_ara(fx, tk, "enlem")), k["kayit_no"], sp["kesit"],
                          round(tt, 4), zaman_utc(an), zaman_yerel(an), round(gps_ara(fx, tk, "hiz_kmh"), 2),
                          round(min(1.0, 0.5 + (oran - 4) / 8), 2), round(tepe, 2), ALG))
        if satir:
            cl.ekle("claude_cukurlar", satir)
        hrms = [v[0] for v in hareket.values()]
        rms = math.sqrt(sum(v * v for v in hrms) / len(hrms))
        hizlar = [f["hiz_kmh"] for f in fx if f["hiz_kmh"] >= 3]
        indeks = rms * (15 / (sum(hizlar) / len(hizlar))) ** 0.65
        pd = min(5.0, max(1.0, 5.6 - 0.42 * indeks))
        cl.ekle("claude_puanlar", [(cizgi([(f["boylam"], f["enlem"]) for f in fx]), k["kayit_no"], sp["kesit"],
                                    KESIT_ADI[sp["kesit"]], int(pd + 0.5), round(pd, 2), round(indeks, 2), ALG)])
    aciklamalar_ekle(cl, ACIKLAMA_CLAUDE)
    cl.stiller(stilleri_oku(), STIL_NOTU)
    cl.kapat()

    for ad in ("ham", "insan", "claude"):
        yol = os.path.join(CIKTI, f"ornek_{GUN}_{ad}.gpkg")
        print(f"{yol}: {os.path.getsize(yol) / 1e6:.2f} MB")
    print(f"Toplam kayıt süresi: {sum(k['sure'] for k in kayitlar) / 60:.2f} dk")


def stilleri_oku():
    """qgis/stiller/<katman>.qml dosyaları (yoksa boş): QGIS'in kendiliğinden uygulayacağı varsayılan stiller."""
    if not os.path.isdir(STIL_KLASORU):
        return {}
    return {ad[:-4]: open(os.path.join(STIL_KLASORU, ad), encoding="utf-8").read()
            for ad in sorted(os.listdir(STIL_KLASORU)) if ad.endswith(".qml")}


def aciklamalar_ekle(gp, satirlar):
    gp.katman("aciklamalar", None, [("katman", "TEXT"), ("alan", "TEXT"), ("tur", "TEXT"), ("birim", "TEXT"),
                                    ("aciklama", "TEXT")], "Bu dosyadaki katman ve alanların açıklaması (veri sözlüğü).")
    gp.ekle("aciklamalar", satirlar)


ORTAK = [
    ("(tümü)", "kayit_no", "metin", "", "Kaydın kimliği: başlangıcın yerel tarih ve saati (YYYYMMDD_SSddss). Bütün dosyalarda aynı; katmanları bununla birleştirin."),
    ("(tümü)", "kesit", "metin", "", "Kesit kodu (K01, K02...). Telefon otomatik verir: başlangıç ve bitiş noktası önceki bir kayıtla ~30 m içinde örtüşen (ters yön dahil) kayıt aynı kesittir. Yanlışsa QGIS'te düzeltilebilir."),
    ("(tümü)", "kesit_adi", "metin", "", "Kesitin adı: kullanıcı Kayıtlar sayfasında verir (ör. sokak adı); aynı kesitin bütün kayıtlarına uygulanır. Verilmediyse boş."),
    ("(tümü)", "t_s", "ondalık", "s", "Kayıt başından (BAŞLAT) bu yana geçen süre. Bütün sensörler ve basışlar aynı saatle ölçülür; katmanları zamanla eşleştirmek için bu alan kullanılır."),
    ("(tümü)", "zaman", "tarih-saat", "UTC", "Mutlak zaman (GeoPackage kuralı gereği UTC; İstanbul = UTC+3)."),
    ("(tümü)", "yerel_saat", "metin", "UTC+3", "Aynı an, İstanbul saatiyle okunabilir yazım."),
]

ACIKLAMA_HAM = [
    ("(dosya)", "", "", "", NOT + "Telefonun ürettiği ham veri dosyası (*_ham.gpkg). Claude'a bu dosya verilir; sürücünün işaret ve puanları bu dosyada YOKTUR."),
    ("(dosya)", "", "", "", "Koordinat sistemi WGS84 (EPSG:4326). Konumlar ham GPS'tir: düzeltme yapılmamıştır; GPS konumu gerçek konumun yaklaşık 1 sn gerisindedir."),
] + ORTAK + [
    ("kayitlar", "(geometri)", "çizgi", "", "Kaydın güzergâhı: ham GPS noktalarının birleşimi. Bir kayıt = bir kesitin bir geçişi."),
    ("kayitlar", "yon", "metin", "", "gidis / donus: kesitin ilk kaydedildiği yöne göre."),
    ("kayitlar", "baslangic, bitis", "tarih-saat", "UTC", "BAŞLAT ve DURDUR anları."),
    ("kayitlar", "sure_s", "ondalık", "s", "Kayıt süresi (baştaki ve sondaki ~5 sn duruş dahil)."),
    ("kayitlar", "uzunluk_m", "ondalık", "m", "GPS noktaları arasındaki mesafelerin toplamı (yalnızca hız >= 3 km/h olan kısımlar)."),
    ("kayitlar", "ort_hiz_kmh", "ondalık", "km/h", "Hareket halindeki (>= 3 km/h) GPS hızlarının ortalaması."),
    ("kayitlar", "gps_nokta", "tam sayı", "", "Kayıttaki GPS konumu sayısı."),
    ("kayitlar", "ivme_hz, jiro_hz", "ondalık", "Hz", "Telefonun gerçekte verdiği örnekleme hızı (istenen ~200 Hz)."),
    ("kayitlar", "cihaz, ivme_sensoru, jiro_sensoru", "metin", "", "Telefon modeli, Android sürümü, sensör adları."),
    ("kayitlar", "scooter", "metin", "", "Ayarlar'daki scooter adı."),
    ("kayitlar", "hava, sicaklik_c, yagis_mm, ruzgar_kmh", "metin / ondalık", "°C, mm, km/h", "Kayıt başındaki hava durumu (Open-Meteo)."),
    ("kayitlar", "veri_kaynagi", "metin", "", "telefon / test_surusu (sanal GPS) / yapay_ornek."),
    ("kayitlar", "uygulama_surumu", "metin", "", "Kaydı yapan uygulama sürümü."),
    ("gps_noktalari", "(geometri)", "nokta", "", "Telefonun GPS alıcısından gelen her konum (yaklaşık saniyede bir), ham."),
    ("gps_noktalari", "hiz_kmh", "ondalık", "km/h", "GPS Doppler hızı."),
    ("gps_noktalari", "yon_derece", "ondalık", "°", "Hareket yönü (kuzeyden saat yönünde). Dururken boş."),
    ("gps_noktalari", "dogruluk_m", "ondalık", "m", "Yatay doğruluk (%68 güven yarıçapı)."),
    ("gps_noktalari", "hiz_dogrulugu_kmh", "ondalık", "km/h", "Hız doğruluğu."),
    ("gps_noktalari", "yukseklik_m, dikey_dogruluk_m", "ondalık", "m", "GPS yüksekliği (elipsoit) ve doğruluğu."),
    ("gps_noktalari", "uydu", "tam sayı", "", "Konumda kullanılan uydu sayısı."),
    ("gps_noktalari", "dikey_rms", "ondalık", "m/s²", "Önceki GPS konumundan bu konuma kadarki dikey sarsıntının RMS'i. Yöntem: ivmenin üç eksenine 0,4 Hz yüksek geçiren süzgeç, yerçekimi yönüne izdüşüm (telefonun açısından bağımsız). Renklendirme için."),
    ("gps_noktalari", "dikey_tepe", "ondalık", "m/s²", "Aynı aralıktaki en büyük mutlak dikey sarsıntı (darbe tepesi)."),
    ("gps_noktalari", "ivme_ornek", "tam sayı", "", "Aynı aralıktaki ivme örneği sayısı (~200 beklenir)."),
    ("ivme", "x, y, z", "ondalık", "m/s²", "Ham ivmeölçer, yerçekimi dahil, telefonun kendi eksenleri (x sağa, y ekranın üstüne, z ekrandan dışarı). Geometrisi yoktur; kayit_no ve t_s ile eşleştirilir."),
    ("jiroskop", "x, y, z", "ondalık", "rad/s", "Ham jiroskop (açısal hız), telefonun kendi eksenleri. Geometrisi yoktur."),
]

ACIKLAMA_INSAN = [
    ("(dosya)", "", "", "", NOT + "Sürücünün işaret ve puanları (*_insan.gpkg). Claude bu dosyayı o günün Claude katmanları GitHub'a gönderilmeden açmaz."),
] + ORTAK + [
    ("insan_cukurlar", "(geometri)", "nokta", "", "Basış anındaki ham GPS konumu. Sürücü çukurdan ~1,3 sn sonra bastığı ve GPS ~1 sn geride olduğu için nokta çukurdan birkaç metre sapabilir; Claude ile eşleştirmede t_s kullanın."),
    ("insan_cukurlar", "hiz_kmh", "ondalık", "km/h", "Basış anındaki GPS hızı."),
    ("insan_cukurlar", "kaynak", "metin", "", "kulaklik / kumanda / ekran / tus. Ekran ve telefon tuşu telefonu sarsar."),
    ("insan_puanlar", "(geometri)", "çizgi", "", "Kaydın güzergâhı (kayitlar katmanıyla aynı)."),
    ("insan_puanlar", "puan", "tam sayı", "1-5", "Konfor puanı: 1 çok kötü ... 5 çok iyi. Hatırlamıyorum ise boş."),
    ("insan_puanlar", "durum", "metin", "", "puanlandi / hatirlamiyorum."),
    ("insan_puanlar", "puanlama_zamani", "tarih-saat", "UTC", "Puanın verildiği an (DURDUR'dan hemen sonra olmalı)."),
    ("insan_puanlar", "isaret_sayisi", "tam sayı", "", "Bu kayıttaki çukur işareti sayısı."),
]

ACIKLAMA_CLAUDE = [
    ("(dosya)", "", "", "", NOT + CLAUDE_NOT + "Claude'un çıktıları (*_claude.gpkg): yalnızca *_ham.gpkg'den üretilir."),
] + ORTAK + [
    ("claude_cukurlar", "(geometri)", "nokta", "", "Darbe anının tahmini konumu (GPS gecikmesi düzeltilmiş)."),
    ("claude_cukurlar", "t_s", "ondalık", "s", "Darbe anı. Sürücünün basışı genellikle bundan ~1-2 sn sonradır."),
    ("claude_cukurlar", "guven", "ondalık", "0-1", "Tespitin güven puanı."),
    ("claude_cukurlar", "tepe_ms2", "ondalık", "m/s²", "Darbenin dikey sarsıntı tepesi."),
    ("claude_cukurlar", "algoritma", "metin", "", "Algoritmanın sürümü."),
    ("claude_puanlar", "puan", "tam sayı", "1-5", "Claude'un konfor puanı (insan puanıyla aynı ölçek)."),
    ("claude_puanlar", "puan_ondalik", "ondalık", "1-5", "Yuvarlanmamış puan."),
    ("claude_puanlar", "indeks_ms2", "ondalık", "m/s²", "Puanın dayandığı sarsıntı ölçüsü."),
]

if __name__ == "__main__":
    main()
