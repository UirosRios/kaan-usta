#!/usr/bin/env python3
"""Analiz betiğinin simülasyonla doğrulanması.

Gerçeği bilinen yapay sürüşler üretir ve surus_analizi.py'nin sonuçlarını bu gerçekle karşılaştırır.
Her senaryoda:

  * Yapay yol ağı (OpenStreetMap JSON biçiminde) ve bu ağ üzerinde scooter güzergâhı
    (hızlanma, dönüşlerde yavaşlama, U dönüşleri).
  * 125 Hz dikey ivme sinyali: zemin pürüzlülüğü (hızla artan, 12 Hz civarı rezonanslı gürültü),
    çukur / rögar darbeleri (ön ve arka tekerlek), butona dokunma etkisi, sensör gürültüsü,
    uygulamadaki 0,4 Hz yüksek geçiren filtre ve ±78,5 m/s² sensör sınırı.
  * 1 Hz GPS: zamanla ilişkili (Gauss-Markov) konum hatası, bina arası yansıma sapması,
    gecikme, hız gürültüsü ve kesintiler; satırlar uygulamanın CSV biçiminde yazılır.
  * Sürücü: çukurdan sonra tepki süresiyle (log-normal) butona basar; bazen unutur, bazen yanlış basar.

Ölçülen başarı: GPS konum hatası (oturtma öncesi / sonrası), işaretli çukurun doğru ana ve yere
eşleşmesi, otomatik darbe tespitinin duyarlılığı ve yanlış alarm sayısı.

Kullanım:
  python simulasyon.py                 (tüm senaryolar, her biri 12 tekrar; rapor ekrana ve dosyaya)
  python simulasyon.py --tekrar 30 --ornek klasor
"""

import argparse
import json
import math
import os
import random
import sys
import tempfile
from datetime import datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import surus_analizi as sa  # noqa: E402

DEG_M = 111320.0
ENLEM0, BOYLAM0 = 40.98, 29.02
KX = DEG_M * math.cos(math.radians(ENLEM0))
FS = 125.0  # Samsung M21 ivmeölçerinin verdiği hız
BASLANGIC = datetime(2026, 10, 24, 10, 0, 0)


def cografi(x, y):
    return ENLEM0 + y / DEG_M, BOYLAM0 + x / KX


def yerel(enlem, boylam):
    return (boylam - BOYLAM0) * KX, (enlem - ENLEM0) * DEG_M


# ---------------------------------------------------------------- yol ağı

class Ag:
    def __init__(self):
        self.dugumler, self.yollar = {}, []
        self._sira = 1

    def dugum(self, x, y):
        for i, p in self.dugumler.items():
            if abs(p[0] - x) < 0.01 and abs(p[1] - y) < 0.01:
                return i
        i = self._sira
        self._sira += 1
        self.dugumler[i] = (x, y)
        return i

    def yol(self, noktalar, etiket=None):
        self.yollar.append(([self.dugum(x, y) for x, y in noktalar], etiket or {'highway': 'residential'}))

    def osm(self):
        e = [{'type': 'node', 'id': i, 'lat': cografi(*p)[0], 'lon': cografi(*p)[1]} for i, p in self.dugumler.items()]
        e += [{'type': 'way', 'id': 1000 + k, 'nodes': n, 'tags': t} for k, (n, t) in enumerate(self.yollar)]
        return {'elements': e}


def izgara(paralel=False, meydan=False):
    """Ana cadde y=0 (x 0-300 m), dik sokaklar x=50,150,250; isteğe bağlı 15 m yanda paralel sokak / meydan."""
    ag = Ag()
    if meydan:  # x 100-160 arası meydan: haritada yol yok, yalnızca alan sınırı
        ag.yol([(0, 0), (50, 0), (100, 0)])
        ag.yol([(160, 0), (250, 0), (300, 0)])
        ag.yol([(100, -30), (160, -30), (160, 30), (100, 30), (100, -30)], {'highway': 'pedestrian', 'area': 'yes'})
    else:
        ag.yol([(0, 0), (50, 0), (150, 0), (250, 0), (300, 0)])
    for x in (50, 150, 250):
        if meydan and x == 150:
            continue
        ag.yol([(x, -60), (x, 0), (x, 15) if paralel else (x, 60), (x, 60)] if paralel else [(x, -60), (x, 0), (x, 60)])
    if paralel:
        ag.yol([(0, 15), (50, 15), (150, 15), (250, 15), (300, 15)])
    ag.yol([(0, 0), (0, 15) if paralel else (0, -40)], {'highway': 'footway'})
    return ag


# ---------------------------------------------------------------- güzergâh ve hız

class Guzergah:
    def __init__(self, noktalar):
        self.p = noktalar
        self.s = [0.0]
        for a, b in zip(noktalar, noktalar[1:]):
            self.s.append(self.s[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
        self.uzunluk = self.s[-1]
        # Dönüş noktaları: açı büyüdükçe daha yavaş geçilir (U dönüşü ~3 km/h)
        self.donusler = []
        for i in range(1, len(noktalar) - 1):
            a, b, c = noktalar[i - 1], noktalar[i], noktalar[i + 1]
            h1 = math.atan2(b[1] - a[1], b[0] - a[0])
            h2 = math.atan2(c[1] - b[1], c[0] - b[0])
            aci = abs((h2 - h1 + math.pi) % (2 * math.pi) - math.pi)
            if aci > math.radians(25):
                self.donusler.append((self.s[i], max(0.8, 3.0 - 1.4 * aci / math.pi)))  # m/s

    def konum(self, s):
        s = max(0.0, min(self.uzunluk, s))
        lo, hi = 0, len(self.s) - 1
        while hi - lo > 1:
            m = (lo + hi) // 2
            if self.s[m] <= s:
                lo = m
            else:
                hi = m
        L = self.s[hi] - self.s[lo]
        k = (s - self.s[lo]) / L if L > 0 else 0
        a, b = self.p[lo], self.p[hi]
        return a[0] + k * (b[0] - a[0]), a[1] + k * (b[1] - a[1])

    def gecisler(self, x, y, tolerans=0.5):
        """Güzergâhın (x, y) noktasından geçtiği yaylar (s)"""
        sonuc = []
        for i in range(len(self.p) - 1):
            (ax, ay), (bx, by) = self.p[i], self.p[i + 1]
            L = self.s[i + 1] - self.s[i]
            k = ((x - ax) * (bx - ax) + (y - ay) * (by - ay)) / (L * L)
            if 0 <= k <= 1 and math.hypot(ax + k * (bx - ax) - x, ay + k * (by - ay) - y) <= tolerans:
                s = self.s[i] + k * L
                if not sonuc or s - sonuc[-1] > 1.0:
                    sonuc.append(s)
        return sonuc


def hareket_uret(g, seyir_kmh, rnd, duraklar=()):
    """125 Hz zaman, yay (s) ve hız dizileri. duraklar: [(s, süre_s)]"""
    T, S, V = [], [], []
    t = s = v = 0.0
    dt = 1 / FS
    duraklar = sorted(duraklar)
    durak_i = 0
    bekle = 0.0
    faz = rnd.uniform(0, 2 * math.pi)
    while s < g.uzunluk - 0.05:
        if bekle > 0:
            bekle -= dt
            v = 0.0
        else:
            hedef = seyir_kmh / 3.6 * (1 + 0.15 * math.sin(2 * math.pi * t / 23 + faz))
            for sd, vd in g.donusler + [(g.uzunluk, 0.0)] + [(d[0], 0.0) for d in duraklar[durak_i:]]:
                if sd > s:
                    hedef = min(hedef, math.sqrt(vd * vd + 2 * 1.5 * (sd - s)))
            ivme = max(-1.5, min(1.0, (hedef - v) / dt))
            v = max(0.0, v + ivme * dt)
            if durak_i < len(duraklar) and s >= duraklar[durak_i][0] - 0.3 and v < 0.3:
                bekle = duraklar[durak_i][1]
                durak_i += 1
                v = 0.0
            if v < 0.05 and hedef > 0.05:
                v = 0.05  # kalkış
        s += v * dt
        t += dt
        T.append(t)
        S.append(s)
        V.append(v)
    return T, S, V


# ---------------------------------------------------------------- ivme sinyali

def rezonans_katsayi():
    w = 2 * math.pi * 12.0 / FS
    r = 0.88
    return 2 * r * math.cos(w), -r * r


def birim_gurultu_rms(a1, a2):
    rnd = random.Random(0)
    y1 = y2 = 0.0
    top, n = 0.0, 0
    for i in range(40000):
        y = rnd.gauss(0, 1) + a1 * y1 + a2 * y2
        y2, y1 = y1, y
        if i > 1000:
            top += y * y
            n += 1
    return math.sqrt(top / n)


A1, A2 = rezonans_katsayi()
NORM = birim_gurultu_rms(A1, A2)


def darbe_ekle(sinyal, i0, genlik, frekans=15.0, sonum=0.04, sure=0.25, isaret=-1):
    """Sönümlü salınım; genlik = sürekli zamandaki tepe değer (örnekleme tepeyi biraz kaçırabilir)"""
    t_tepe = math.atan(2 * math.pi * frekans * sonum) / (2 * math.pi * frekans)
    genlik /= math.exp(-t_tepe / sonum) * math.sin(2 * math.pi * frekans * t_tepe)
    for k in range(int(sure * FS)):
        if i0 + k >= len(sinyal):
            break
        tt = k / FS
        sinyal[i0 + k] += isaret * genlik * math.exp(-tt / sonum) * math.sin(2 * math.pi * frekans * tt)


def ivme_uret(T, S, V, g, zemin, kusurlar, basislar, rnd):
    """zemin(s) -> pürüzlülük (m/s² RMS, 10 km/h'te); kusurlar: [(x, y, genlik_g)]"""
    n = len(T)
    sinyal = [0.0] * n
    y1 = y2 = 0.0
    carpan = 1.0
    for i in range(n):
        y = rnd.gauss(0, 1) + A1 * y1 + A2 * y2
        y2, y1 = y1, y
        carpan = min(1.4, max(0.6, carpan + rnd.gauss(0, 0.004)))  # zeminin yer yer değişmesi
        v = V[i]
        olcek = zemin(S[i]) * carpan * (v / (10 / 3.6)) ** 0.8 if v > 0.3 else 0.0
        sinyal[i] = olcek * y / NORM + rnd.gauss(0, 0.15)
    vurus = []
    for (x, y, genlik_g) in kusurlar:
        for s0 in g.gecisler(x, y):
            i = _ara(S, s0)
            v = max(V[i], 0.3)
            A = genlik_g * 9.81 * min(1.0, v / 4.17) ** 0.8
            darbe_ekle(sinyal, i, A)
            darbe_ekle(sinyal, i + int(0.9 / v * FS), 0.7 * A)  # arka tekerlek ~0,9 m sonra
            vurus.append(dict(t=T[i], x=x, y=y))
    for tb in basislar:  # ekrana dokunma: telefonu kısa bir an iter
        i = _ara(T, tb)
        darbe_ekle(sinyal, i, rnd.uniform(4, 9), frekans=25.0, sonum=0.02, sure=0.12, isaret=1)
    # Uygulamadaki yerçekimi filtresi (0,4 Hz bilineer yüksek geçiren) ve sensör sınırı
    tau = 1 / (2 * math.pi * 0.4)
    k = 2 * tau / (1 / FS)
    cikis, onceki, yo = [], 0.0, 0.0
    for i, a in enumerate(sinyal):
        a = a + 9.81  # yerçekimi (düşey eksen)
        yo = 0.0 if i == 0 else k / (k + 1) * (a - onceki) + (k - 1) / (k + 1) * yo
        onceki = a
        cikis.append(max(-78.5, min(78.5, yo)))
    return cikis, vurus


def _ara(dizi, deger):
    lo, hi = 0, len(dizi) - 1
    while lo < hi:
        m = (lo + hi) // 2
        if dizi[m] < deger:
            lo = m + 1
        else:
            hi = m
    return lo


# ---------------------------------------------------------------- GPS ve CSV

def zaman_metin(t):
    z = BASLANGIC + timedelta(seconds=t)
    return z.strftime('%Y-%m-%d %H:%M:%S,') + f'{z.microsecond:06d}'


def kayit_uret(sen, rnd, yol):
    """Senaryodan CSV ve OSM üretir; gerçeği (güzergâh, vuruşlar, basışlar) döndürür."""
    g = Guzergah(sen['guzergah'])
    T, S, V = hareket_uret(g, sen['hiz'], rnd, sen.get('duraklar', ()))
    kusurlar = sen['cukurlar'] + sen.get('rogarlar', [])
    # Önce çukur vuruş anları (basışları belirlemek için), sonra sinyal (basış dokunmalarıyla)
    vuruslar = []
    for (x, y, genlik_g) in sen['cukurlar']:
        for s0 in g.gecisler(x, y):
            vuruslar.append(dict(t=T[_ara(S, s0)], x=x, y=y, cukur=True))
    vuruslar.sort(key=lambda v: v['t'])
    # Sürücü: çukuru fark ederse tepki süresi sonra basar (uygulamadaki 1 sn çift basış koruması dahil)
    basislar = []
    for v in vuruslar:
        if rnd.random() > sen.get('fark_etme', 1.0):
            continue
        tb = v['t'] + rnd.lognormvariate(math.log(sen.get('tepki_medyan', 1.5)), sen.get('tepki_yayilim', 0.35))
        basislar.append((tb, v))
    for k in range(sen.get('yanlis_basis', 0)):
        basislar.append((rnd.uniform(10, T[-1] - 5), None))
    basislar.sort(key=lambda b: b[0])
    filtreli = []
    for tb, v in basislar:
        if tb < T[-1] - 1 and (not filtreli or tb - filtreli[-1][0] >= 1.0):
            filtreli.append((tb, v))
    sinyal, vurus_hepsi = ivme_uret(T, S, V, g, sen['zemin'], kusurlar, [b[0] for b in filtreli], rnd)

    # GPS ölçümleri (1 Hz): gerçek konum (gecikmeli) + zamanla ilişkili hata + bölgesel sapma
    sigma, tau = sen['gps_sigma'], sen.get('gps_tau', 15.0)
    phi = math.exp(-1.0 / tau)
    ex = rnd.gauss(0, sigma)
    ey = rnd.gauss(0, sigma)
    fixler = []
    tf = 0.3
    while tf < T[-1]:
        ex = phi * ex + math.sqrt(1 - phi * phi) * rnd.gauss(0, sigma)
        ey = phi * ey + math.sqrt(1 - phi * phi) * rnd.gauss(0, sigma)
        i = _ara(T, max(T[0], tf - sen.get('gecikme', 1.0)))
        x, y = g.konum(S[i])
        bx, by = sen['sapma'](x, y) if 'sapma' in sen else (0.0, 0.0)
        kesik = any(a <= S[_ara(T, tf)] <= b for a, b in sen.get('kesintiler', ()))
        if not kesik:
            hiz = V[i] * 3.6 + rnd.gauss(0, 0.3) if V[i] > 0.2 else abs(rnd.gauss(0, 1.2))
            dogruluk = round(1.5 * sigma * rnd.uniform(0.9, 1.25) * 2) / 2
            fixler.append((tf, *cografi(x + ex + bx, y + ey + by), max(0.0, hiz), dogruluk))
        tf += 1.0

    # 0,5 sn'lik satırlar (uygulamadaki gibi)
    satir_t = 0.5
    j = 0
    fi = -1
    isaret_i = 0
    with open(yol, 'w', encoding='utf-8') as f:
        f.write('Tarih_Saat;Enlem;Boylam;GPS_Doppler_Hiz_kmh;Duzeltilmis_GPS_Hiz_kmh;'
                'Dikey_RMS;Dikey_Min;Dikey_Max;Ivme_Ornek_Sayisi;GPS_Dogruluk_m;Isaret\n')
        while satir_t <= T[-1]:
            pencere = []
            while j < len(T) and T[j] <= satir_t:
                pencere.append(sinyal[j])
                j += 1
            while fi + 1 < len(fixler) and fixler[fi + 1][0] <= satir_t:
                fi += 1
            isaret = 0
            while isaret_i < len(filtreli) and filtreli[isaret_i][0] <= satir_t:
                isaret += 1
                isaret_i += 1
            rms = math.sqrt(sum(a * a for a in pencere) / len(pencere)) if pencere else 0.0
            n = lambda v, d: f'{v:.{d}f}'.replace('.', ',')  # noqa: E731
            if fi >= 0 and satir_t - fixler[fi][0] <= 3.0:
                _, e, b, h, d = fixler[fi]
                gps = [n(e, 6), n(b, 6), n(h, 2), n(h, 2)]
                dog = n(d, 1)
            else:
                gps, dog = ['', '', '', ''], ''
            f.write(';'.join([zaman_metin(satir_t), *gps, n(rms, 4), n(min(pencere or [0]), 4), n(max(pencere or [0]), 4),
                              str(len(pencere)), dog, str(isaret) if isaret else '']) + '\n')
            satir_t += 0.5
    return dict(g=g, T=T, S=S, V=V, vuruslar=vurus_hepsi, basislar=filtreli, cukur_noktalari=sen['cukurlar'],
                rogar_noktalari=sen.get('rogarlar', []))


# ---------------------------------------------------------------- değerlendirme

def gercek_konum(gercek, t):
    return gercek['g'].konum(gercek['S'][_ara(gercek['T'], t)])


def degerlendir(r, gercek, t0):
    sonuc = {}
    # Satır konum hatası (hareket satırları): tahmini konum ile sarsıntının ölçüldüğü andaki gerçek konum
    hatalar = []
    for s in r['satirlar']:
        if s['durum'] != 'hareket' or s['d_enlem'] is None:
            continue
        gx, gy = gercek_konum(gercek, s['merkez'] - t0)
        x, y = yerel(s['d_enlem'], s['d_boylam'])
        hatalar.append(math.hypot(x - gx, y - gy))
    sonuc['konum_hatalari'] = hatalar

    # İşaretli çukurlar
    dogru, yanlis_an, eslesmedi, yer_hatalari, belirsiz, yaklasik_hatalari = 0, 0, 0, [], 0, []
    yanlis_basis_eslesti = yanlis_basis = 0
    for i in r['isaretler']:
        tb_rel = i['basis']['t'] - t0
        # Satırın penceresine düşen gerçek basış
        aday = [(tb, v) for tb, v in gercek['basislar'] if tb_rel - 0.5 < tb <= tb_rel + 1e-6]
        v = aday[0][1] if aday else None
        if v is None:
            yanlis_basis += 1
            if i['cukur'] is not None:
                yanlis_basis_eslesti += 1
            continue
        if i['cukur'] is None:
            if i['sonuc'] == 'belirsiz':
                belirsiz += 1
            else:
                eslesmedi += 1
            if i['tahmini'] is not None:
                x, y = yerel(i['tahmini']['d_enlem'], i['tahmini']['d_boylam'])
                yaklasik_hatalari.append(math.hypot(x - v['x'], y - v['y']))
            continue
        c = i['cukur']
        ct = c['merkez'] - t0
        # Doğru eşleşme: aynı çukura ait (ön veya arka tekerlek) vuruş seçilen pencerede
        ayni = [w for w in gercek['vuruslar'] if abs(w['x'] - v['x']) < 6 and abs(w['y'] - v['y']) < 1 and abs(w['t'] - v['t']) < 2]
        if any(abs(w['t'] - ct) <= 0.6 for w in ayni) or abs(v['t'] - ct) <= 0.6:
            dogru += 1
            x, y = yerel(c['d_enlem'], c['d_boylam'])
            yer_hatalari.append(math.hypot(x - v['x'], y - v['y']))
        else:
            yanlis_an += 1
    sonuc.update(dogru=dogru, yanlis_an=yanlis_an, eslesmedi=eslesmedi, yer_hatalari=yer_hatalari,
                 belirsiz=belirsiz, yaklasik_hatalari=yaklasik_hatalari,
                 yanlis_basis=yanlis_basis, yanlis_basis_eslesti=yanlis_basis_eslesti, basis=len(r['isaretler']))

    # Birden fazla geçişin birleştirildiği çukur noktalarının gerçek çukura uzaklığı
    kume_hatalari = []
    for k in r['cukur_kumeleri']:
        x, y = yerel(k['enlem'], k['boylam'])
        en_yakin = min(gercek['cukur_noktalari'], key=lambda p: math.hypot(p[0] - x, p[1] - y))
        kume_hatalari.append((len(k['olaylar']), math.hypot(en_yakin[0] - x, en_yakin[1] - y)))
    sonuc['kume_hatalari'] = kume_hatalari

    # Otomatik darbe tespiti: çukur vuruşları (ön tekerlek) yakalandı mı, kaç yanlış alarm var
    on_vurus = [w for w in gercek['vuruslar']]
    darbe_t = [o['merkez'] - t0 for o in r['olaylar']]
    cukur_vurus = [w for w in on_vurus if any(abs(w['x'] - p[0]) < 1e-6 and abs(w['y'] - p[1]) < 1e-6 for p in gercek['cukur_noktalari'])]
    bulunan = sum(1 for w in cukur_vurus if any(abs(d - w['t']) <= 0.75 for d in darbe_t))
    yanlis = sum(1 for d in darbe_t if not any(abs(d - w['t']) <= 1.0 for w in on_vurus))
    sonuc.update(cukur_vurus=len(cukur_vurus), bulunan=bulunan, yanlis_alarm=yanlis)
    return sonuc


# ---------------------------------------------------------------- senaryolar

def ileri_geri(noktalar, tur=2):
    yol = list(noktalar)
    for k in range(2 * tur - 1):
        yol += list(reversed(noktalar))[1:] if k % 2 == 0 else list(noktalar)[1:]
    return yol


ANA = [(0, 0), (300, 0)]
CUKURLAR = [(70, 0, 3.0), (180, 0, 2.5), (240, 0, 2.0)]
ROGAR = [(125, 0, 1.8)]
ASFALT, PARKE, ARNAVUT = 1.2, 3.5, 6.5


def senaryolar():
    return [
        dict(ad='1. Asfalt, açık alan, iyi GPS', ag=izgara(), guzergah=ileri_geri(ANA), hiz=15, zemin=lambda s: ASFALT,
             cukurlar=CUKURLAR, rogarlar=ROGAR, gps_sigma=3.0),
        dict(ad='2. Parke, bina arası: kötü GPS + yansıma sapması', ag=izgara(), guzergah=ileri_geri(ANA), hiz=15,
             zemin=lambda s: PARKE, cukurlar=CUKURLAR, rogarlar=ROGAR, gps_sigma=7.0,
             sapma=lambda x, y: (0.0, 8.0) if 100 <= x <= 220 else (0.0, 0.0)),
        dict(ad='3. 15 m arayla paralel iki sokak', ag=izgara(paralel=True), guzergah=ileri_geri(ANA), hiz=15,
             zemin=lambda s: PARKE, cukurlar=CUKURLAR, rogarlar=ROGAR, gps_sigma=6.0),
        dict(ad='4. Haritada yolu olmayan meydan', ag=izgara(meydan=True),
             guzergah=ileri_geri([(0, 0), (100, 0), (130, 18), (160, 0), (300, 0)]), hiz=15, zemin=lambda s: PARKE,
             cukurlar=[(70, 0, 3.0), (115, 9, 2.5), (145, 9, 2.5), (240, 0, 2.0)], rogarlar=ROGAR, gps_sigma=5.0),
        dict(ad='5. Arnavut kaldırımı, küçük çukurlar', ag=izgara(), guzergah=ileri_geri(ANA), hiz=12,
             zemin=lambda s: ARNAVUT, cukurlar=[(70, 0, 2.0), (180, 0, 1.6), (240, 0, 1.2)], rogarlar=ROGAR, gps_sigma=5.0),
        dict(ad='6. Zor sürücü: geç basma, unutma, yanlış basış, 3 m arayla iki çukur', ag=izgara(),
             guzergah=ileri_geri(ANA), hiz=15, zemin=lambda s: PARKE,
             cukurlar=[(70, 0, 3.0), (180, 0, 2.5), (183, 0, 2.5), (240, 0, 2.0)], rogarlar=ROGAR, gps_sigma=5.0,
             fark_etme=0.8, tepki_medyan=2.3, tepki_yayilim=0.5, yanlis_basis=2),
        dict(ad='7. GPS kesintisi (40 m alt geçit, çukur içinde)', ag=izgara(), guzergah=ileri_geri(ANA), hiz=15,
             zemin=lambda s: ASFALT, cukurlar=CUKURLAR, rogarlar=ROGAR, gps_sigma=4.0,
             kesintiler=[(160, 200), (400, 440), (760, 800), (1000, 1040)]),
        dict(ad='8. Gerçek GPS gecikmesi 2 sn (betik 1 sn varsayar)', ag=izgara(), guzergah=ileri_geri(ANA), hiz=15,
             zemin=lambda s: PARKE, cukurlar=CUKURLAR, rogarlar=ROGAR, gps_sigma=5.0, gecikme=2.0),
        dict(ad='9. Duraklama + kalkış (U dönüşlerinde ve ortada durma)', ag=izgara(), guzergah=ileri_geri(ANA), hiz=15,
             zemin=lambda s: PARKE, cukurlar=CUKURLAR, rogarlar=ROGAR, gps_sigma=5.0, duraklar=[(150, 6), (750, 6)]),
    ]


def yuzde(a, b):
    return f'%{100 * a / b:.0f}' if b else '-'


def ceyrek(liste, q):
    if not liste:
        return float('nan')
    liste = sorted(liste)
    return liste[min(len(liste) - 1, int(q * (len(liste) - 1) + 0.5))]


def calistir(tekrar, ornek_klasor=None):
    satirlar = []
    for sen in senaryolar():
        toplam = {k: [] for k in ('ham', 'otur')}
        for tekrar_no in range(tekrar):
            rnd = random.Random(1000 * tekrar_no + sum(map(ord, sen['ad'])))
            with tempfile.TemporaryDirectory() as d:
                csv_yol = os.path.join(d, 'sim.csv')
                osm_yol = os.path.join(d, 'osm.json')
                with open(osm_yol, 'w', encoding='utf-8') as f:
                    json.dump(sen['ag'].osm(), f)
                gercek = kayit_uret(sen, rnd, csv_yol)
                t0 = sa.zaman(zaman_metin(0.0))
                for anahtar, ayar in (('ham', sa.varsayilan_ayar(oturtma='kapali')),
                                      ('otur', sa.varsayilan_ayar(osm=osm_yol))):
                    r = sa.dosya_analiz(csv_yol, ayar, yaz=False)
                    toplam[anahtar].append(degerlendir(r, gercek, t0))
        satirlar.append((sen['ad'], toplam))
        print(f'  {sen["ad"]}: tamam', file=sys.stderr)

    rapor = ['# Simülasyon sonuçları', '',
             f'Her senaryo {tekrar} kez (farklı rastgele GPS hatası, sürücü tepkisi, zemin) çalıştırıldı.',
             'Güzergâh: 300 m cadde, 2 tur ileri-geri (her çukurdan 4 geçiş, iki yönde), ~15 km/h.',
             'Konum hataları metre; "ham": gecikme düzeltmeli ham GPS, "oturtulmuş": haritaya oturtma sonrası.', '',
             '- **Satır konum hatası:** sarsıntının ölçüldüğü andaki gerçek konuma uzaklık (medyan / %95).',
             '- **İşaretli çukur: doğru an:** basışların yüzde kaçı doğru çukurun 0,5 sn\'lik penceresiyle eşleşti. '
             '"yanlış an": başka bir tepe seçildi; "belirsiz": betik emin olmadığını söyledi ve yaklaşık konum verdi; '
             '"eşleşmedi": belirgin tepe yok / GPS yok.',
             '- **Çukur yer hatası:** doğru eşleşen tek basışların gerçek çukura uzaklığı.',
             '- **Çok geçişli çukur noktası hatası:** en az 2 geçişte işaretlenip gruplanan çukur noktalarının gerçek çukura uzaklığı.',
             '- **Otomatik tespit duyarlılığı:** çukur geçişlerinin yüzde kaçında otomatik darbe bulundu. '
             '**Yanlış alarm:** hiçbir kusura (çukur / rögar) denk gelmeyen darbe sayısı.',
             '- **Yanlış basışın eşleşmesi:** çukur yokken basılan butonun bir tepeyle eşleştirildiği durum / yanlış basış sayısı.',
             '']
    rapor.append('| Senaryo | Satır konum hatası, medyan / %95 (ham → oturtulmuş) | İşaretli çukur: doğru an | '
                 'Çukur yer hatası, medyan (ham → oturtulmuş) | Çok geçişli çukur noktası hatası | Otomatik tespit duyarlılığı | '
                 'Yanlış alarm (sürüş başına) | Yanlış basışın eşleşmesi |')
    rapor.append('|---|---|---|---|---|---|---|---|')
    for ad, toplam in satirlar:
        def birlestir(anahtar, alan):
            out = []
            for d in toplam[anahtar]:
                out.extend(d[alan])
            return out

        def topla(anahtar, alan):
            return sum(d[alan] for d in toplam[anahtar])
        kh = birlestir('ham', 'konum_hatalari')
        ko = birlestir('otur', 'konum_hatalari')
        yh = birlestir('ham', 'yer_hatalari')
        yo = birlestir('otur', 'yer_hatalari')
        kume = [h for n, h in birlestir('otur', 'kume_hatalari') if n >= 2]
        gercek_basis = topla('otur', 'basis') - topla('otur', 'yanlis_basis')
        rapor.append(
            f'| {ad} | {ceyrek(kh, .5):.1f} / {ceyrek(kh, .95):.1f} → {ceyrek(ko, .5):.1f} / {ceyrek(ko, .95):.1f} '
            f'| {yuzde(topla("otur", "dogru"), gercek_basis)} ({topla("otur", "dogru")}/{gercek_basis}; '
            f'yanlış an {topla("otur", "yanlis_an")}, belirsiz {topla("otur", "belirsiz")}, eşleşmedi {topla("otur", "eslesmedi")}) '
            f'| {ceyrek(yh, .5):.1f} → {ceyrek(yo, .5):.1f} '
            f'| {ceyrek(kume, .5):.1f} (n={len(kume)}) '
            f'| {yuzde(topla("otur", "bulunan"), topla("otur", "cukur_vurus"))} '
            f'| {topla("otur", "yanlis_alarm") / tekrar:.1f} '
            f'| {topla("otur", "yanlis_basis_eslesti")}/{topla("otur", "yanlis_basis")} |')
    metin = '\n'.join(rapor) + '\n'
    print(metin)

    if ornek_klasor:  # örnek çıktı: 2. senaryo (bina arası parke), işaretli çukurlar ve oturtma ile
        os.makedirs(ornek_klasor, exist_ok=True)
        with open(os.path.join(ornek_klasor, 'simulasyon_raporu.md'), 'w', encoding='utf-8') as f:
            f.write(metin)
        sen = dict(senaryolar()[5])
        sen['ad'] = 'ornek'
        rnd = random.Random(7)
        csv_yol = os.path.join(ornek_klasor, 'ornek_surus.csv')
        osm_yol = os.path.join(ornek_klasor, 'ornek_surus_osm.json')
        with open(osm_yol, 'w', encoding='utf-8') as f:
            json.dump(sen['ag'].osm(), f)
        kayit_uret(sen, rnd, csv_yol)
        sa.dosya_analiz(csv_yol, sa.varsayilan_ayar(osm=osm_yol), klasor=ornek_klasor)
    return metin


def main():
    p = argparse.ArgumentParser(description='Analiz betiğinin simülasyonla doğrulanması')
    p.add_argument('--tekrar', type=int, default=12, help='Her senaryonun tekrar sayısı (varsayılan 12)')
    p.add_argument('--ornek', help='Örnek sürüş CSV\'si ve analiz çıktılarının yazılacağı klasör')
    a = p.parse_args()
    calistir(a.tekrar, a.ornek)


if __name__ == '__main__':
    main()
