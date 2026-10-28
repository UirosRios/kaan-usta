#!/usr/bin/env python3
"""Mikromobilite sarsıntı kaydı analizi.

Uygulamanın ürettiği CSV dosyalarını (Türkçe Excel biçimi: ';' ayırıcı, ',' ondalık) okur ve
her kayıt için şunları üretir:

  <ad>_ozet.txt        Veri kalitesi, haritaya oturtma, hıza göre sarsıntı tablosu, işaretli çukurlar, darbeler
  <ad>_satirlar.csv    Tüm satırlar: düzeltilmiş konum/hız, durum, darbe ve çukur işaretleri
  <ad>_isaretler.csv   Eski sürümün çukur butonu basışları ve eşleşen çukurlar (yalnızca basış varsa)
  <ad>_olaylar.csv     Otomatik bulunan darbeler
  <ad>_harita.html     Uydu görüntüsü üzerinde güzergâh (renk = sarsıntı), işaretli çukurlar ve darbeler
  <ad>_harita.geojson  Aynı veri, QGIS / ArcGIS için
  <ad>_grafik.png      Hız, sarsıntı, hız-sarsıntı ilişkisi ve güzergâh (matplotlib kuruluysa)
  <ad>_osm.json        İndirilen OpenStreetMap yolları (sonraki çalıştırmalarda yeniden indirilmez)

Yapılan düzeltmeler:
  * GPS gecikmesi: telefonun GPS yongası hızı ve konumu yaklaşık 1 sn geç bildirir. Her satırın
    sarsıntısı, --gecikme kadar sonra gelen GPS değeriyle eşleştirilir.
  * Haritaya oturtma: GPS noktaları OpenStreetMap yollarına oturtulur (haritaya_oturtma.py). Yana
    doğru hata düzelir; yol bulunamayan yerlerde (meydan vb.) nokta olduğu yerde kalır.
  * Konum enterpolasyonu: GPS saniyede 1 kez güncellenir; satırlar (0,5 sn) arasındaki konum ve hız
    iki GPS ölçümü arasında doğrusal enterpolasyonla bulunur.
  * Duruş ayıklama: düzeltilmiş hız --min-hiz altındaysa satır "duruş" sayılır ve analize girmez.
  * Butona basma etkisi: ekrana dokunmak telefonu kısa bir an sarsar; basılan satır ve sonraki
    --isaret-dislama saniye analize girmez.

Çukur işaretleri (Isaret sütunu): sürücü çukurdan geçtikten sonra butona basar. Betik, basıştan önceki
--isaret-arama saniye içindeki hareket satırlarından tepe değeri çevresindeki sarsıntıya göre en büyük
olanı çukur olarak seçer (bir önceki basıştan öncesine bakılmaz).

Darbe tespiti (otomatik): bir satırın tepe değeri max(|Dikey_Min|, Dikey_Max), çevresindeki ±10 sn'lik
hareket satırlarının Dikey_RMS medyanının --darbe-orani katını VE --darbe-esik değerini aşıyorsa o satır
darbe sayılır. Farklı geçişlerde aynı noktada (--kume-yaricap) bulunan darbeler / çukurlar gruplanır.

Kullanım:
  python surus_analizi.py kayit.csv [kayit2.csv ...] [--cikti klasor] [--osm yollar.json] ...
  python surus_analizi.py -h        (tüm ayarlar)
"""

import argparse
import bisect
import csv
import glob
import html
import json
import math
import os
import re
import statistics as st
from collections import defaultdict
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import haritaya_oturtma  # noqa: E402

DEG_M = 111320.0  # 1 derece enlemin metre karşılığı (yaklaşık)


# ---------------------------------------------------------------- okuma

def sayi(metin):
    """'9,8100' -> 9.81; boş hücre -> None"""
    metin = (metin or '').strip()
    return float(metin.replace(',', '.')) if metin else None


def zaman(metin):
    """'2026-10-23 23:43:05,265464' -> Unix zamanı (s)"""
    metin = metin.strip().replace(',', '.')
    for bicim in ('%Y-%m-%d %H:%M:%S.%f', '%Y-%m-%d %H:%M:%S'):
        try:
            return datetime.strptime(metin, bicim).timestamp()
        except ValueError:
            pass
    raise ValueError(f'Tarih_Saat okunamadı: {metin}')


class KayitHatasi(Exception):
    """Dosya uygulamanın kayıt biçiminde değil (betik bu dosyayı atlar)"""


def oku(yol):
    with open(yol, encoding='utf-8-sig') as f:
        okuyucu = csv.DictReader(f, delimiter=';')
        gerekli = {'Tarih_Saat', 'Enlem', 'Boylam', 'GPS_Doppler_Hiz_kmh', 'Dikey_RMS', 'Dikey_Min', 'Dikey_Max'}
        eksik = gerekli - set(okuyucu.fieldnames or [])
        if eksik:
            raise KayitHatasi(f'{yol}: beklenen sütunlar yok: {", ".join(sorted(eksik))} '
                              '(uygulamanın kayıt dosyası değil ya da eski biçim)')
        satirlar = []
        for d in okuyucu:
            satirlar.append(dict(
                zaman_metin=d['Tarih_Saat'],
                t=zaman(d['Tarih_Saat']),
                enlem=sayi(d['Enlem']),
                boylam=sayi(d['Boylam']),
                hiz=sayi(d['GPS_Doppler_Hiz_kmh']),
                dogruluk=sayi(d.get('GPS_Dogruluk_m')),
                rms=sayi(d['Dikey_RMS']),
                dmin=sayi(d['Dikey_Min']),
                dmax=sayi(d['Dikey_Max']),
                ornek=int(d.get('Ivme_Ornek_Sayisi') or 0),
                isaret=int(sayi(d.get('Isaret')) or 0),  # eski sürümün çukur butonu (yeni kayıtlarda yok)
                uyg_cukur=bool(sayi(d.get('Cukur'))),  # uygulamanın anlık çukur uyarısı (eski kayıtlarda yok)
            ))
    if not satirlar:
        raise KayitHatasi(f'{yol}: veri satırı yok')
    return satirlar


# ---------------------------------------------------------------- GPS

def gps_olcumleri(satirlar):
    """Art arda tekrar eden satırlardan tekil GPS ölçümlerini çıkarır (her biri ilk göründüğü an)."""
    olcumler, onceki = [], None
    for s in satirlar:
        if s['enlem'] is None:
            onceki = None
            continue
        anahtar = (s['enlem'], s['boylam'], s['hiz'], s['dogruluk'])
        if anahtar != onceki:
            olcumler.append(dict(t=s['t'], enlem=s['enlem'], boylam=s['boylam'], hiz=s['hiz'], dogruluk=s['dogruluk'],
                                 o_enlem=s['enlem'], o_boylam=s['boylam'], yolda=None, kayma_m=0.0, yol=None))
            onceki = anahtar
    return olcumler


def gps_degeri(olcumler, tq, max_bosluk=3.0):
    """tq anındaki konum/hız: iki GPS ölçümü arasında doğrusal enterpolasyon.
    Ölçümler arası boşluk max_bosluk sn'den uzunsa (GPS kesintisi) None döner."""
    if not olcumler or tq < olcumler[0]['t'] or tq > olcumler[-1]['t'] + 1.0:
        return None
    lo, hi = 0, len(olcumler) - 1
    while lo < hi:  # tq'dan küçük veya eşit son ölçüm
        orta = (lo + hi + 1) // 2
        if olcumler[orta]['t'] <= tq:
            lo = orta
        else:
            hi = orta - 1
    a = olcumler[lo]
    if lo + 1 >= len(olcumler):
        return dict(a) if tq - a['t'] <= 1.0 else None
    b = olcumler[lo + 1]
    if b['t'] - a['t'] > max_bosluk:
        return None
    k = (tq - a['t']) / (b['t'] - a['t'])
    sonuc = {alan: a[alan] + k * (b[alan] - a[alan]) if a[alan] is not None and b[alan] is not None else a[alan]
             for alan in ('enlem', 'boylam', 'hiz', 'dogruluk', 'o_enlem', 'o_boylam')}
    sonuc['yolda'] = (a if k < 0.5 else b)['yolda']
    sonuc['yol'] = (a if k < 0.5 else b)['yol']
    return sonuc


def mesafe(e1, b1, e2, b2):
    """İki nokta arası mesafe (m), haversine"""
    r = 6371000.0
    p1, p2 = math.radians(e1), math.radians(e2)
    dp, dl = p2 - p1, math.radians(b2 - b1)
    return 2 * r * math.asin(math.sqrt(math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2))


def osm_yukle(olcumler, ayar, onbellek):
    """Yol ağı: --osm dosyası, yoksa önbellek (sürüşün alanını kapsıyorsa), yoksa Overpass'tan indir. Olmazsa None."""
    if ayar.oturtma == 'kapali' or not olcumler:
        return None, 'kapalı'
    if ayar.osm:
        with open(ayar.osm, encoding='utf-8') as f:
            return json.load(f), os.path.basename(ayar.osm)
    gerek = (min(o['enlem'] for o in olcumler), min(o['boylam'] for o in olcumler),
             max(o['enlem'] for o in olcumler), max(o['boylam'] for o in olcumler))
    if onbellek and os.path.exists(onbellek):
        with open(onbellek, encoding='utf-8') as f:
            osm = json.load(f)
        kutu = osm.get('_kutu')  # indirilen alan (güney, batı, kuzey, doğu)
        if kutu and kutu[0] <= gerek[0] and kutu[1] <= gerek[1] and kutu[2] >= gerek[2] and kutu[3] >= gerek[3]:
            return osm, os.path.basename(onbellek)
    pay = 0.001  # ~100 m
    kutu = [gerek[0] - pay, gerek[1] - pay, gerek[2] + pay, gerek[3] + pay]
    try:
        osm = haritaya_oturtma.osm_indir(*kutu)
    except RuntimeError as e:
        print(f'  UYARI: {e} - haritaya oturtma yapılmadı')
        return None, 'indirilemedi'
    osm['_kutu'] = kutu
    if onbellek:
        os.makedirs(os.path.dirname(os.path.abspath(onbellek)), exist_ok=True)
        with open(onbellek, 'w', encoding='utf-8') as f:
            json.dump(osm, f)
    return osm, 'OpenStreetMap (Overpass)'


# ---------------------------------------------------------------- analiz

def belirsizlik(s, yolda):
    """Konum belirsizliği (m, ~%68): GPS + darbenin 0,5 sn'lik pencere içindeki yeri (±0,25 sn) + gecikme
    belirsizliği (±0,5 sn). Yola oturtulmuşsa yalnızca yol boyunca bileşen kalır (dik bileşen yolun içinde)."""
    v = (s['d_hiz'] or 0.0) / 3.6
    gps = s['d_dogruluk'] or 10.0
    if yolda:
        gps /= 1.5  # %68 yarıçap (2 boyut) -> tek eksen sigma
    return math.sqrt(gps ** 2 + (v * 0.25) ** 2 + (v * 0.5) ** 2)


def analiz_et(satirlar, ayar, osm=None):
    olcumler = gps_olcumleri(satirlar)
    oturtma = None
    if osm is not None:
        oturtma = haritaya_oturtma.oturt(olcumler, osm, beta=ayar.oturtma_beta, yol_disi_ceza=ayar.yol_disi_ceza)

    for i, s in enumerate(satirlar):
        # Satır, yazıldığı andan önceki 0,5 sn'yi özetler: pencere ortası = yazılma anı − 0,25 sn
        s['merkez'] = s['t'] - 0.25
        g = gps_degeri(olcumler, s['merkez'] + ayar.gecikme)
        s['h_enlem'] = g['enlem'] if g else None  # gecikmesi düzeltilmiş ham konum
        s['h_boylam'] = g['boylam'] if g else None
        s['d_enlem'] = g['o_enlem'] if g else None  # + yola oturtulmuş konum
        s['d_boylam'] = g['o_boylam'] if g else None
        s['yolda'] = g['yolda'] if g else None
        s['yol'] = g['yol'] if g else None  # oturtulduğu OSM yolu (id, ad, tür)
        s['d_hiz'] = g['hiz'] if g else None
        s['d_dogruluk'] = g['dogruluk'] if g else None
        s['tepe'] = max(abs(s['dmin']), s['dmax'])
        s['darbe'] = s['cukur'] = False
        s['zemin_rms'] = s['zemin_rms_ortak'] = None

    # Butona basma etkisi: basılan satır ve sonraki --isaret-dislama sn
    etkili = set()
    for i, s in enumerate(satirlar):
        if s['isaret']:
            for j in range(i, len(satirlar)):
                if satirlar[j]['t'] - s['t'] > ayar.isaret_dislama + 0.01:
                    break
                etkili.add(j)
    for i, s in enumerate(satirlar):
        if s['d_hiz'] is None:
            s['durum'] = 'gps_yok'
        elif i in etkili:
            s['durum'] = 'isaret'
        elif s['d_hiz'] < ayar.min_hiz:
            s['durum'] = 'durus'
        else:
            s['durum'] = 'hareket'

    hareket = [s for s in satirlar if s['durum'] == 'hareket']
    genel_rms = st.median(s['rms'] for s in hareket) if hareket else 1.0

    # Çevre sarsıntısı (taban) ve otomatik darbe tespiti. Satırlar zamana göre sıralı: pencereler ikili aramayla bulunur.
    zamanlar = [k['t'] for k in hareket]
    rmsler = [k['rms'] for k in hareket]
    for i, s in enumerate(hareket):
        once = rmsler[bisect.bisect_left(zamanlar, s['t'] - 10.0):i]
        sonra = rmsler[i + 1:bisect.bisect_right(zamanlar, s['t'] + 10.0)]
        # Darbe tabanı: önceki ve sonraki 10 sn ayrı ayrı, büyük olanı. Düzgünden bozuk zemine geçişte bozuk kısmın
        # sıradan tepeleri, düzgün kısmın düşük tabanına göre "darbe" sayılmasın.
        yanlar = [st.median(g) for g in (once, sonra) if len(g) >= 3]
        s['zemin_rms'] = max(yanlar) if yanlar else genel_rms
        # ±10 sn'nin tek medyanı: eski çukur butonu eşleştirmesi bununla ayarlandı; --darbe-taban ortak ile darbe tespiti de kullanır
        s['zemin_rms_ortak'] = st.median(once + sonra) if len(once) + len(sonra) >= 5 else genel_rms
        if ayar.darbe_taban == 'ortak':
            s['zemin_rms'] = s['zemin_rms_ortak']
        if s['tepe'] >= ayar.darbe_orani * s['zemin_rms'] and s['tepe'] >= ayar.darbe_esik:
            s['darbe'] = True

    # Art arda (1 sn içinde) işaretlenen satırlar tek darbedir: en büyük tepeli satır kalır
    gruplar = []
    for s in hareket:
        if not s['darbe']:
            continue
        if gruplar and s['t'] - gruplar[-1][-1]['t'] <= 1.01:
            gruplar[-1].append(s)
        else:
            gruplar.append([s])
    olaylar = []
    for g in gruplar:
        en_buyuk = max(g, key=lambda x: x['tepe'])
        for s in g:
            s['darbe'] = s is en_buyuk
        olaylar.append(en_buyuk)
    for o in olaylar:
        o['belirsizlik_m'] = belirsizlik(o, o['yolda'])

    isaretler = isaret_esle(satirlar, ayar)
    cukurlar = [i['cukur'] for i in isaretler if i['cukur'] is not None]
    for c in cukurlar:
        c['belirsizlik_m'] = belirsizlik(c, c['yolda'])

    b = hiz_ussu(hareket)
    sokaklar = sokak_tablosu(hareket, olaylar, b)
    return dict(olcumler=olcumler, oturtma=oturtma, hareket=hareket, olaylar=olaylar, hiz_ussu=b, sokaklar=sokaklar,
                kumeler=kumele(olaylar, ayar.kume_yaricap), isaretler=isaretler,
                cukur_kumeleri=kumele(cukurlar, ayar.kume_yaricap))


def isaret_esle(satirlar, ayar):
    """Her basış için, basıştan önceki --isaret-arama sn içindeki en belirgin sarsıntı tepesini bul.

    Sonuç: 'eşleşti' (tek belirgin tepe), 'belirsiz' (zemin de çukur kadar sarsıyor: başka bir anda
    benzer büyüklükte tepe var), 'belirgin tepe yok', 'GPS kesintisi' veya 'hareket yok'. Eşleşmeyen
    basışlar için konum, basıştan tipik tepki süresi kadar önceki ana göre yaklaşık verilir."""
    isaretler, onceki_basis = [], -math.inf
    for s in satirlar:
        if not s['isaret']:
            continue
        basis = s['t'] - 0.25  # basış bu 0,5 sn'lik pencerenin içinde bir anda
        alt = max(s['t'] - 0.5 - ayar.isaret_arama, onceki_basis)
        pencere = [k for k in satirlar if alt <= k['merkez'] < s['t'] - 0.5]
        adaylar = sorted((k for k in pencere if k['durum'] == 'hareket'), key=lambda k: -k['tepe'] / k['zemin_rms_ortak'])
        kayit = dict(basis=s, cukur=None, tahmini=None, oran=None, tepki_s=None)
        if not adaylar:
            kayit['sonuc'] = 'GPS kesintisi' if any(k['durum'] == 'gps_yok' for k in pencere) else 'hareket yok'
        else:
            en_iyi = adaylar[0]
            kayit['oran'] = en_iyi['tepe'] / en_iyi['zemin_rms_ortak']
            # Rakip: en iyiden 0,6 sn'den uzak (aynı çukurun arka tekerleği değil) en büyük ikinci tepe
            rakip = next((k for k in adaylar[1:] if abs(k['merkez'] - en_iyi['merkez']) > 0.6), None)
            if kayit['oran'] < ayar.isaret_min_oran:
                kayit['sonuc'] = 'belirgin tepe yok'
            elif rakip is not None and rakip['tepe'] / rakip['zemin_rms_ortak'] >= ayar.isaret_belirsiz * kayit['oran']:
                kayit['sonuc'] = 'belirsiz'
            else:
                kayit['cukur'] = en_iyi
                kayit['tepki_s'] = basis - en_iyi['merkez']
                kayit['sonuc'] = 'eşleşti'
                en_iyi['cukur'] = True
        isaretler.append(kayit)
        onceki_basis = s['t']

    # Eşleşmeyen basışlar için yaklaşık konum: bu sürüşteki tipik tepki süresi (en az 3 eşleşme yoksa 1,5 sn)
    tepkiler = [k['tepki_s'] for k in isaretler if k['cukur'] is not None]
    tipik = st.median(tepkiler) if len(tepkiler) >= 3 else 1.5
    konumlu = [x for x in satirlar if x['d_enlem'] is not None and x['durum'] != 'gps_yok']
    for i, k in enumerate(isaretler, 1):
        k['no'] = i
        if k['cukur'] is None and konumlu:
            hedef = k['basis']['t'] - 0.25 - tipik
            x = min(konumlu, key=lambda r: abs(r['merkez'] - hedef))
            if abs(x['merkez'] - hedef) <= 1.0:
                # Tepki süresinin kişiden kişiye / andan ana ~1 sn değişmesi yol boyunca belirsizlik ekler
                k['tahmini'] = x
                k['tahmini_belirsizlik'] = math.hypot(belirsizlik(x, x['yolda']), (x['d_hiz'] or 0) / 3.6 * 1.0)
    return isaretler


def kumele(olaylar, yaricap):
    """Farklı geçişlerde aynı noktada ölçülen olayları grupla.
    En büyük olaydan başlayarak her olay, merkezi yaricap metre içindeki en yakın gruba katılır;
    yoksa yeni grup açar (zincirleme birleşme olmasın diye grup merkezine bakılır)."""
    gruplar = []
    for o in sorted(olaylar, key=lambda x: -x['tepe']):
        en_yakin, en_kisa = None, yaricap
        for g in gruplar:
            e = st.mean(x['d_enlem'] for x in g)
            b = st.mean(x['d_boylam'] for x in g)
            d = mesafe(o['d_enlem'], o['d_boylam'], e, b)
            if d <= en_kisa:
                en_yakin, en_kisa = g, d
        if en_yakin is None:
            gruplar.append([o])
        else:
            en_yakin.append(o)
    kumeler = []
    for g in gruplar:
        # Ağırlık: belirsizliğin karesinin tersi (daha doğru ölçüm daha çok sayılır)
        w = [1 / max(x['belirsizlik_m'], 1.0) ** 2 for x in g]
        enlem = sum(wi * x['d_enlem'] for wi, x in zip(w, g)) / sum(w)
        boylam = sum(wi * x['d_boylam'] for wi, x in zip(w, g)) / sum(w)
        # n ölçümün ortalaması ~1/√n küçülür; ancak GPS hatası zamanla ilişkili olduğundan
        # kısa aralıklı geçişlerde gerçek iyileşme bundan az olabilir
        kumeler.append(dict(enlem=enlem, boylam=boylam, belirsizlik_m=math.sqrt(1 / sum(w)),
                            olaylar=sorted(g, key=lambda x: x['t']), en_buyuk=max(x['tepe'] for x in g)))
    kumeler.sort(key=lambda k: (-len(k['olaylar']), -k['en_buyuk']))
    return kumeler


# ---------------------------------------------------------------- sokak ve hücre bazında özet

HIZ_REF = 15.0  # km/h: hız düzeltmeli sarsıntı indeksinin başvuru hızı
HUCRE_M = 25.0  # m: konum hücresi (sokak bilgisi olmayan yerlerde ve birleşik haritada)
HUCRE_ENLEM = 41.0  # hücre ızgarasının boylam ölçeği için sabit enlem (İstanbul); her yerde aynı ızgara, kopukluk yok
HUCRE_KX = DEG_M * math.cos(math.radians(HUCRE_ENLEM))
YOL_DISI = 'Yol dışı / haritaya oturtulmadı'


def sokak_adi(s):
    y = s.get('yol')
    if y is None:
        return YOL_DISI
    return y['ad'] or f"İsimsiz {y['tur'] or 'yol'} (OSM {y['id']})"


def hucre(s):
    """25 m'lik sabit konum hücresi (aynı yer farklı sürüşlerde aynı hücreye düşer)"""
    return (math.floor(s['d_enlem'] * DEG_M / HUCRE_M), math.floor(s['d_boylam'] * HUCRE_KX / HUCRE_M))


def hucre_sinirlari(h):
    return [[h[0] * HUCRE_M / DEG_M, h[1] * HUCRE_M / HUCRE_KX], [(h[0] + 1) * HUCRE_M / DEG_M, (h[1] + 1) * HUCRE_M / HUCRE_KX]]


def hiz_ussu(hareket):
    """Sarsıntının hıza bağlılığı: RMS ∝ hız^b. Aynı 25 m'lik hücre içinde (yüzey sabitken) log-log eğimi;
    farklı yüzeylerde farklı hızla gidilmesinin karıştırıcı etkisi böylece dışarıda kalır. Sokak bazında
    tahmin edilmez: uzun bir sokağın bir kısmı bozuk, bir kısmı düzgün olabilir. Yetersiz veride None."""
    gruplar = defaultdict(list)
    for s in hareket:
        if s['rms'] > 0 and s['d_hiz'] > 0:
            gruplar[hucre(s)].append((math.log(s['d_hiz']), math.log(s['rms'])))
    xs, ys = [], []
    for g in gruplar.values():
        if len(g) < 5:
            continue
        mx, my = st.mean(x for x, _ in g), st.mean(y for _, y in g)
        xs += [x - mx for x, _ in g]
        ys += [y - my for _, y in g]
    sxx = sum(x * x for x in xs)
    if len(xs) < 40 or sxx < 1.0:  # hız aralığı çok dar veya veri az
        return None
    return max(0.0, min(1.5, sum(x * y for x, y in zip(xs, ys)) / sxx))


def duzeltilmis_rms(s, b):
    """Hız düzeltmeli sarsıntı: bu satırın 15 km/h'te beklenen Dikey_RMS'si (çok düşük hızda düzeltme şişmesin diye
    hız en az 3 km/h alınır; --min-hiz 0 verilse de sıfıra bölünmez)"""
    return s['rms'] * (HIZ_REF / max(s['d_hiz'], 3.0)) ** b


def sokak_tablosu(hareket, olaylar, b, anahtar=sokak_adi):
    """Sokak (veya başka gruplama) başına: satır, yaklaşık yol, medyan hız / RMS, hız düzeltmeli indeks, darbe"""
    gruplar = defaultdict(list)
    for s in hareket:
        gruplar[anahtar(s)].append(s)
    darbe = defaultdict(int)
    for o in olaylar:
        darbe[anahtar(o)] += 1
    tablo = []
    for ad, g in gruplar.items():
        yol_m = sum(s['d_hiz'] / 3.6 * 0.5 for s in g)
        tablo.append(dict(ad=ad, n=len(g), yol_m=yol_m, hiz=st.median(s['d_hiz'] for s in g),
                          rms=st.median(s['rms'] for s in g),
                          indeks=st.median(duzeltilmis_rms(s, b) for s in g) if b is not None else None,
                          darbe=darbe[ad], darbe_100m=100 * darbe[ad] / yol_m if yol_m > 0 else 0.0,
                          suruslar={s.get('surus') for s in g}))
    tablo.sort(key=lambda t: -(t['indeks'] if t['indeks'] is not None else t['rms']))
    return tablo


def bilgi_oku(csv_yol):
    """Kaydın _bilgi.txt dosyasından scooter ve hava durumu etiketleri (yoksa boş)"""
    yol = re.sub(r'\.csv$', '', csv_yol) + '_bilgi.txt'
    etiket = {}
    if os.path.exists(yol):
        with open(yol, encoding='utf-8', errors='replace') as f:
            for satir in f:
                for anahtar, ad in (('Scooter:', 'scooter'), ('Hava durumu:', 'hava')):
                    if satir.startswith(anahtar):
                        etiket[ad] = satir[len(anahtar):].strip()
    return etiket


def hiz_tablosu(hareket, aralik):
    if not hareket:
        return []
    ust = max(s['d_hiz'] for s in hareket)
    tablo, a = [], 0.0
    while a <= ust:
        b = a + aralik
        grup = [s for s in hareket if a <= s['d_hiz'] < b]
        if grup:
            tablo.append(dict(alt=a, ust=b, n=len(grup),
                              rms_medyan=st.median(s['rms'] for s in grup),
                              rms_ort=st.mean(s['rms'] for s in grup),
                              tepe_medyan=st.median(s['tepe'] for s in grup)))
        a = b
    return tablo


# ---------------------------------------------------------------- çıktılar

def tr(x, basamak=2):
    """Sayıyı Türkçe ondalıkla yaz"""
    return '' if x is None else f'{x:.{basamak}f}'.replace('.', ',')


def maps_link(enlem, boylam):
    return f'https://www.google.com/maps/search/?api=1&query={enlem:.6f},{boylam:.6f}'


def ozet_yaz(yol, ad, satirlar, r, tablo, ayar, osm_kaynak):
    olcumler, hareket, olaylar, kumeler, isaretler = r['olcumler'], r['hareket'], r['olaylar'], r['kumeler'], r['isaretler']
    sure = satirlar[-1]['t'] - satirlar[0]['t'] + 0.5
    yol_m = sum(mesafe(olcumler[i]['enlem'], olcumler[i]['boylam'], olcumler[i + 1]['enlem'], olcumler[i + 1]['boylam'])
                for i in range(len(olcumler) - 1))
    ornek = [s['ornek'] for s in satirlar if s['ornek']]
    dogruluk = [o['dogruluk'] for o in olcumler if o['dogruluk'] is not None]
    satir = []
    y = satir.append
    y(f'SÜRÜŞ ANALİZİ - {ad}')
    y(f'Başlangıç: {satirlar[0]["zaman_metin"]}   Süre: {tr(sure, 0)} s   Satır: {len(satirlar)}')
    etiket = r.get('etiket', {})
    if etiket:
        y(f'Scooter: {etiket.get("scooter", "-")}   Hava durumu: {etiket.get("hava", "alınamadı")}')
    y(f'GPS ile ölçülen yol: ~{yol_m:.0f} m   En yüksek hız: {tr(max((o["hiz"] for o in olcumler), default=0), 1)} km/h')
    y('')
    y('AYARLAR')
    y(f'  GPS gecikme düzeltmesi: {tr(ayar.gecikme, 1)} s   Duruş eşiği: {tr(ayar.min_hiz, 1)} km/h')
    y(f'  Darbe: tepe ≥ {tr(ayar.darbe_orani, 1)} × çevre RMS ({ayar.darbe_taban}) ve ≥ {tr(ayar.darbe_esik, 0)} m/s²   '
      f'Gruplama yarıçapı: {tr(ayar.kume_yaricap, 0)} m')
    if r['isaretler']:  # eski sürümün çukur butonu
        y(f'  Çukur işareti: basıştan önceki {tr(ayar.isaret_arama, 0)} sn aranır, tepe ≥ {tr(ayar.isaret_min_oran, 1)} × çevre RMS; '
          f'basıştan sonraki {tr(ayar.isaret_dislama, 1)} sn analiz dışı')
    y('')
    y('VERİ KALİTESİ')
    if ornek:
        y(f'  İvmeölçer: 0,5 sn\'de {min(ornek)}-{max(ornek)} örnek (~{2 * st.mean(ornek):.0f} Hz)')
    y(f'  GPS ölçümü: {len(olcumler)} adet (~{tr(len(olcumler) / sure, 1)} Hz)')
    if dogruluk:
        y(f'  GPS doğruluğu: {tr(min(dogruluk), 1)}-{tr(max(dogruluk), 1)} m (ortalama {tr(st.mean(dogruluk), 1)} m)')
    say = {d: sum(1 for s in satirlar if s['durum'] == d) for d in ('hareket', 'durus', 'isaret', 'gps_yok')}
    buton = f', buton etkisi {say["isaret"]}' if say['isaret'] else ''
    y(f'  Satır durumu: hareket {say["hareket"]}, duruş {say["durus"]}{buton}, GPS yok {say["gps_yok"]}')
    y(f'  En büyük ivme tepesi (tüm satırlar): {tr(max(s["tepe"] for s in satirlar), 1)} m/s² '
      '(telefonun ölçüm aralığı _bilgi.txt dosyasında; yakınsa sensör doymuş olabilir)')
    y('')
    y('HARİTAYA OTURTMA')
    o = r['oturtma']
    if o is None:
        y(f'  Yapılmadı ({osm_kaynak}). Konumlar yalnızca gecikme düzeltmeli ham GPS.')
    else:
        y(f'  Yol verisi: {osm_kaynak} ({o["parca"]} yol parçası)')
        y(f'  GPS ölçümlerinin {o["yolda"]}/{o["toplam"]} tanesi bir yola oturtuldu (%{100 * o["yolda"] / max(o["toplam"], 1):.0f}); '
          f'kalanlar yol dışı (meydan, park, haritada olmayan geçit) sayılıp olduğu yerde bırakıldı.')
        y(f'  Ortalama kayma: {tr(o["ort_kayma"], 1)} m')
    y('')
    y('HIZA GÖRE DİKEY SARSINTI (yalnızca hareket satırları)')
    y(f'  {"Hız (km/h)":<12}{"Satır":>7}{"RMS medyan":>13}{"RMS ort.":>11}{"Tepe medyan":>14}')
    for t in tablo:
        y(f'  {tr(t["alt"], 0) + "-" + tr(t["ust"], 0):<12}{t["n"]:>7}{tr(t["rms_medyan"]):>13}{tr(t["rms_ort"]):>11}{tr(t["tepe_medyan"], 1):>14}')
    if len(hareket) >= 3:
        xs, ys = [s['d_hiz'] for s in hareket], [s['rms'] for s in hareket]
        try:
            rr = st.correlation(xs, ys)
            fit = st.linear_regression(xs, ys)
            y(f'  Korelasyon r = {tr(rr)}   Doğrusal uyum: RMS ≈ {tr(fit.intercept)} + {tr(fit.slope, 3)} × hız')
        except st.StatisticsError:
            pass
        y('  Not: farklı sokaklarda farklı hızla gidildiyse bu tablo hız ile yüzeyin etkisini karıştırır;')
        y('  yüzey karşılaştırması için aşağıdaki sokak tablosuna bakın.')
    y('')
    sokaklar = r['sokaklar']
    if sokaklar:
        y('SOKAKLARA GÖRE SARSINTI (en bozuktan en düzgüne)')
        if r['hiz_ussu'] is not None:
            y(f'  İndeks: hız düzeltmeli Dikey_RMS = bu sokakta {tr(HIZ_REF, 0)} km/h\'te beklenen sarsıntı (m/s²). Sarsıntının hıza bağlılığı')
            y(f'  aynı 25 m\'lik parçadaki hız farklarından tahmin edildi: RMS ∝ hız^{tr(r["hiz_ussu"])}.')
        else:
            y('  Hız düzeltmesi için veri yetersiz (aynı yerden yeterince farklı hızda geçilmemiş); sıralama medyan RMS\'ye göre.')
        y(f'  {"Sokak":<34}{"Yol (m)":>9}{"Hız":>7}{"RMS":>7}{"İndeks":>8}{"Darbe":>7}{"Darbe/100m":>12}')
        for t in sokaklar:
            y(f'  {t["ad"][:33]:<34}{t["yol_m"]:>9.0f}{tr(t["hiz"], 1):>7}{tr(t["rms"]):>7}{tr(t["indeks"]) or "-":>8}'
              f'{t["darbe"]:>7}{tr(t["darbe_100m"], 1):>12}')
        if r['oturtma'] is None:
            y('  (Haritaya oturtma yapılmadığı için sokak adları yok; internet bağlantısıyla yeniden çalıştırın.)')
        y('')
    uyarilar = [s for s in satirlar if s['uyg_cukur']]
    if uyarilar:
        darbe_t = [o['t'] for o in olaylar]
        ortak = sum(1 for u in uyarilar if any(abs(u['t'] - t) <= 1.0 for t in darbe_t))
        uyarisiz = sum(1 for t in darbe_t if not any(abs(u['t'] - t) <= 1.0 for u in uyarilar))
        y(f'UYGULAMANIN ANLIK ÇUKUR UYARILARI ({len(uyarilar)} uyarı; Cukur sütunu)')
        y(f'  {ortak} tanesi aşağıdaki otomatik darbelerle aynı an (±1 sn). Betiğin bulduğu {len(darbe_t)} darbenin '
          f'{uyarisiz} tanesinde uyarı yanmamış: uygulama sabit ve yüksek bir eşik kullanır (en sert darbeler),')
        y('  betik ise her darbeyi çevresindeki sarsıntıyla karşılaştırır.')
        for u in uyarilar:
            konum = f'{u["d_enlem"]:.6f}, {u["d_boylam"]:.6f}' if u['d_enlem'] is not None else 'konum yok'
            y(f'  - {u["zaman_metin"][11:22]}  {konum}  hız {tr(u["d_hiz"], 1)} km/h  Min {tr(u["dmin"], 1)} / Max {tr(u["dmax"], 1)} m/s²'
              f'{"  [betik: darbe]" if any(abs(u["t"] - t) <= 1.0 for t in darbe_t) else ""}')
        y('')
    eslesen = [i for i in isaretler if i['cukur'] is not None]
    if isaretler:
        y(f'ÇUKUR İŞARETLERİ - eski çukur butonu ({len(isaretler)} basış, {len(eslesen)} tanesi bir sarsıntı tepesiyle eşleşti)')
        if any(i['sonuc'] == 'belirsiz' for i in isaretler):
            y('  "belirsiz": arama aralığında çukura benzer büyüklükte başka tepe(ler) de var (zemin çok pürüzlü);')
            y('  konum yalnızca yaklaşıktır.')
        for i in isaretler:
            b = i['basis']
            if i['cukur'] is None:
                y(f'  Ç{i["no"]}: basış {b["zaman_metin"][11:22]} - {i["sonuc"]}'
                  + (f' (en büyük tepe çevre RMS\'nin {tr(i["oran"], 1)} katı)' if i['oran'] else ''))
                x = i['tahmini']
                if x is not None:
                    y(f'      yaklaşık konum (tipik tepki süresinden): {x["d_enlem"]:.6f}, {x["d_boylam"]:.6f} ±{i["tahmini_belirsizlik"]:.0f} m  '
                      f'{maps_link(x["d_enlem"], x["d_boylam"])}')
                continue
            c = i['cukur']
            y(f'  Ç{i["no"]}: {c["d_enlem"]:.6f}, {c["d_boylam"]:.6f}  {"yol boyunca " if c["yolda"] else ""}±{c["belirsizlik_m"]:.0f} m  '
              f'çukur {c["zaman_metin"][11:22]}, basış {tr(i["tepki_s"], 1)} sn sonra')
            y(f'      hız {tr(c["d_hiz"], 1)} km/h  Min {tr(c["dmin"], 1)} / Max {tr(c["dmax"], 1)} m/s²  '
              f'(çevre RMS\'nin {tr(i["oran"], 1)} katı){"  otomatik darbe olarak da bulundu" if c["darbe"] else ""}')
            y(f'      {maps_link(c["d_enlem"], c["d_boylam"])}')
        if len(r['cukur_kumeleri']) < len(eslesen):
            y('  Birden fazla geçişte işaretlenen çukurlar:')
            for k in r['cukur_kumeleri']:
                if len(k['olaylar']) > 1:
                    y(f'    {k["enlem"]:.6f}, {k["boylam"]:.6f} ±{k["belirsizlik_m"]:.0f} m ({len(k["olaylar"])} geçiş)  {maps_link(k["enlem"], k["boylam"])}')
        if eslesen:
            tepki = [i['tepki_s'] for i in eslesen]
            bulunan = sum(1 for i in eslesen if i['cukur']['darbe'])
            y(f'  Ortalama tepki süresi (çukur -> basış): {tr(st.mean(tepki), 1)} sn')
            y(f'  Otomatik darbe tespiti işaretli çukurların {bulunan}/{len(eslesen)} tanesini buldu.')
        y('')
    dogrulanan = sum(1 for o in olaylar if o['cukur'])
    y(f'OTOMATİK DARBELER ({len(olaylar)} darbe, {len(kumeler)} farklı nokta'
      + (f'; {dogrulanan} tanesi işaretli bir çukurla aynı an)' if isaretler else ')'))
    for n, k in enumerate(kumeler, 1):
        y(f'  Nokta {n}: {k["enlem"]:.6f}, {k["boylam"]:.6f}  ±{k["belirsizlik_m"]:.0f} m  '
          f'({len(k["olaylar"])} geçişte, en büyük tepe {tr(k["en_buyuk"], 1)} m/s²)')
        y(f'    {maps_link(k["enlem"], k["boylam"])}')
        for o in k['olaylar']:
            y(f'    - {o["zaman_metin"][11:22]}  hız {tr(o["d_hiz"], 1)} km/h  Min {tr(o["dmin"], 1)} / Max {tr(o["dmax"], 1)} m/s²  '
              f'çevre RMS {tr(o["zemin_rms"], 1)}  konum ±{o["belirsizlik_m"]:.0f} m{"  [işaretli çukur]" if o["cukur"] else ""}'
              f'{"  [uygulama uyarısı]" if any(u["uyg_cukur"] and abs(u["t"] - o["t"]) <= 1.0 for u in satirlar) else ""}')
    y('')
    y('NOT: Her darbe çukur olmak zorunda değildir (rögar kapağı, kot farkı, ray vb. de darbe verir).')
    y('Konumlar telefon GPS\'inin doğruluğuyla sınırlıdır; yerinde kontrol için noktayı belirsizlik')
    y('dairesi / aralığı içinde güzergâh boyunca arayın.')
    with open(yol, 'w', encoding='utf-8') as f:
        f.write('\n'.join(satir) + '\n')


def satirlar_yaz(yol, satirlar):
    with open(yol, 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.writer(f, delimiter=';')
        w.writerow(['Tarih_Saat', 'Duzeltilmis_Enlem', 'Duzeltilmis_Boylam', 'Yolda', 'Ham_Enlem', 'Ham_Boylam',
                    'Duzeltilmis_Hiz_kmh', 'GPS_Dogruluk_m', 'Dikey_RMS', 'Dikey_Min', 'Dikey_Max', 'Tepe', 'Cevre_RMS',
                    'Durum', 'Uygulama_Cukur', 'Darbe', 'Isaret', 'Isaretli_Cukur'])
        for s in satirlar:
            w.writerow([s['zaman_metin'], tr(s['d_enlem'], 6), tr(s['d_boylam'], 6),
                        '' if s['yolda'] is None else ('evet' if s['yolda'] else 'hayır'),
                        tr(s['h_enlem'], 6), tr(s['h_boylam'], 6), tr(s['d_hiz']), tr(s['d_dogruluk'], 1),
                        tr(s['rms'], 4), tr(s['dmin'], 4), tr(s['dmax'], 4), tr(s['tepe'], 4), tr(s['zemin_rms'], 4),
                        s['durum'], 'evet' if s['uyg_cukur'] else '', 'evet' if s['darbe'] else '',
                        s['isaret'] or '', 'evet' if s['cukur'] else ''])


def isaretler_yaz(yol, isaretler):
    with open(yol, 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.writer(f, delimiter=';')
        w.writerow(['No', 'Basis_Zamani', 'Sonuc', 'Cukur_Zamani', 'Tepki_s', 'Enlem', 'Boylam', 'Yolda', 'Belirsizlik_m',
                    'Hiz_kmh', 'Dikey_Min', 'Dikey_Max', 'Cevre_RMS', 'Tepe_Orani', 'Otomatik_Darbe', 'Google_Maps'])
        for i in isaretler:
            c = i['cukur']
            if c is None:
                x = i['tahmini']
                konum = ([tr(x['d_enlem'], 6), tr(x['d_boylam'], 6), 'evet' if x['yolda'] else 'hayır', tr(i['tahmini_belirsizlik'], 1)]
                         if x is not None else ['', '', '', ''])
                w.writerow([f'Ç{i["no"]}', i['basis']['zaman_metin'], i['sonuc'] + (' (yaklaşık konum)' if x is not None else ''),
                            '', '', *konum, '', '', '', '', tr(i['oran'], 2), '',
                            maps_link(x['d_enlem'], x['d_boylam']) if x is not None else ''])
                continue
            w.writerow([f'Ç{i["no"]}', i['basis']['zaman_metin'], i['sonuc'], c['zaman_metin'], tr(i['tepki_s'], 2),
                        tr(c['d_enlem'], 6), tr(c['d_boylam'], 6), 'evet' if c['yolda'] else 'hayır', tr(c['belirsizlik_m'], 1),
                        tr(c['d_hiz']), tr(c['dmin'], 2), tr(c['dmax'], 2), tr(c['zemin_rms'], 2), tr(i['oran'], 2),
                        'evet' if c['darbe'] else 'hayır', maps_link(c['d_enlem'], c['d_boylam'])])


def olaylar_yaz(yol, kumeler):
    with open(yol, 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.writer(f, delimiter=';')
        w.writerow(['Nokta', 'Tarih_Saat', 'Enlem', 'Boylam', 'Belirsizlik_m', 'Hiz_kmh', 'Dikey_Min', 'Dikey_Max',
                    'Cevre_RMS', 'Isaretli_Cukur', 'Nokta_Enlem', 'Nokta_Boylam', 'Nokta_Belirsizlik_m', 'Gecis_Sayisi',
                    'Google_Maps'])
        for i, k in enumerate(kumeler, 1):
            for o in k['olaylar']:
                w.writerow([i, o['zaman_metin'], tr(o['d_enlem'], 6), tr(o['d_boylam'], 6), tr(o['belirsizlik_m'], 1),
                            tr(o['d_hiz']), tr(o['dmin'], 2), tr(o['dmax'], 2), tr(o['zemin_rms'], 2),
                            'evet' if o['cukur'] else '', tr(k['enlem'], 6), tr(k['boylam'], 6),
                            tr(k['belirsizlik_m'], 1), len(k['olaylar']), maps_link(k['enlem'], k['boylam'])])


def sokaklar_yaz(yol, sokaklar, surus_sayisi=False):
    with open(yol, 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.writer(f, delimiter=';')
        w.writerow(['Sira', 'Sokak', 'Satir', 'Yol_m', 'Medyan_Hiz_kmh', 'Medyan_Dikey_RMS', f'Indeks_{HIZ_REF:.0f}kmh',
                    'Darbe', 'Darbe_100m'] + (['Surus_Sayisi'] if surus_sayisi else []))
        for i, t in enumerate(sokaklar, 1):
            w.writerow([i, t['ad'], t['n'], f'{t["yol_m"]:.0f}', tr(t['hiz'], 1), tr(t['rms'], 3), tr(t['indeks'], 3),
                        t['darbe'], tr(t['darbe_100m'], 2)] + ([len(t['suruslar'])] if surus_sayisi else []))


def geojson_yaz(yol, satirlar, r):
    ozellikler = []
    for s in satirlar:
        if s['d_enlem'] is None:
            continue
        ozellikler.append({'type': 'Feature', 'geometry': {'type': 'Point', 'coordinates': [s['d_boylam'], s['d_enlem']]},
                           'properties': {'tur': 'satir', 'zaman': s['zaman_metin'], 'hiz_kmh': round(s['d_hiz'], 2),
                                          'dikey_rms': s['rms'], 'tepe': s['tepe'], 'durum': s['durum'], 'yolda': s['yolda'],
                                          'ham_enlem': s['h_enlem'], 'ham_boylam': s['h_boylam'],
                                          'darbe': s['darbe'], 'isaretli_cukur': s['cukur']}})
    for i in r['isaretler']:
        c, x = i['cukur'], i['tahmini']
        if x is not None:
            ozellikler.append({'type': 'Feature', 'geometry': {'type': 'Point', 'coordinates': [x['d_boylam'], x['d_enlem']]},
                               'properties': {'tur': 'isaretli_cukur_yaklasik', 'no': f'Ç{i["no"]}', 'sonuc': i['sonuc'],
                                              'belirsizlik_m': round(i['tahmini_belirsizlik'], 1)}})
        if c is not None:
            ozellikler.append({'type': 'Feature', 'geometry': {'type': 'Point', 'coordinates': [c['d_boylam'], c['d_enlem']]},
                               'properties': {'tur': 'isaretli_cukur', 'no': f'Ç{i["no"]}', 'zaman': c['zaman_metin'],
                                              'tepki_s': round(i['tepki_s'], 2), 'tepe': c['tepe'],
                                              'belirsizlik_m': round(c['belirsizlik_m'], 1), 'yolda': c['yolda']}})
    for n, k in enumerate(r['kumeler'], 1):
        ozellikler.append({'type': 'Feature', 'geometry': {'type': 'Point', 'coordinates': [k['boylam'], k['enlem']]},
                           'properties': {'tur': 'darbe_noktasi', 'no': n, 'gecis_sayisi': len(k['olaylar']),
                                          'en_buyuk_tepe': k['en_buyuk'], 'belirsizlik_m': round(k['belirsizlik_m'], 1)}})
    with open(yol, 'w', encoding='utf-8') as f:
        json.dump({'type': 'FeatureCollection', 'features': ozellikler}, f, ensure_ascii=False)


# Sarsıntı renk sınıfları (Dikey_RMS, m/s²): az = yeşil, orta = sarı, çok = kırmızı. Sınırlar sabittir; böylece
# farklı sürüşlerin haritaları aynı renk ölçeğiyle karşılaştırılabilir.
SINIRLAR = [2, 4, 6, 8, 10]
RENKLER = ['#1a9850', '#66bd63', '#fdd835', '#fb8c00', '#e53935', '#8e0000']
MOR = '#6a1b9a'  # otomatik darbe işaretleri (sarsıntı renkleriyle karışmasın)


def renk(rms):
    return RENKLER[sum(1 for b in SINIRLAR if rms >= b)]


def yumusat(satirlar, yaricap=2):
    """Harita rengi için Dikey_RMS'nin kayan medyanı (±1 sn): tek tük tepeler sokağı alacalı göstermesin"""
    return [st.median(s['rms'] for s in satirlar[max(0, i - yaricap):i + yaricap + 1]) for i in range(len(satirlar))]


def harita_yaz(yol, ad, satirlar, r, ayar):
    noktalar = [s for s in satirlar if s['d_enlem'] is not None]
    if not noktalar:
        return
    duzgun = yumusat(noktalar)
    parcalar, ham = [], []
    for (a, b), rms in zip(zip(noktalar, noktalar[1:]), duzgun):
        if b['t'] - a['t'] > 1.5:
            continue
        parcalar.append(dict(p=[[a['d_enlem'], a['d_boylam']], [b['d_enlem'], b['d_boylam']]],
                             r=renk(rms) if a['durum'] == 'hareket' else '#898781',
                             d=a['durum'] != 'hareket',
                             i=f"{a['zaman_metin'][11:22]} · {tr(a['d_hiz'], 1)} km/h · RMS {tr(a['rms'])} m/s²"))
        ham.append([[a['h_enlem'], a['h_boylam']], [b['h_enlem'], b['h_boylam']]])
    darbeler = []
    for n, k in enumerate(r['kumeler'], 1):
        satir = ''.join(f"<br>{html.escape(o['zaman_metin'][11:22])} · {tr(o['d_hiz'], 1)} km/h · "
                        f"{tr(o['dmin'], 0)} / +{tr(o['dmax'], 0)} m/s²" for o in k['olaylar'])
        darbeler.append(dict(
            e=k['enlem'], b=k['boylam'], r=k['belirsizlik_m'], no=str(n),
            tek=[[o['d_enlem'], o['d_boylam']] for o in k['olaylar']],
            h=(f"<b>Otomatik darbe noktası {n}</b> ({len(k['olaylar'])} geçiş)<br>{k['enlem']:.6f}, {k['boylam']:.6f} "
               f"±{k['belirsizlik_m']:.0f} m{satir}<br><a href='{maps_link(k['enlem'], k['boylam'])}' target='_blank'>"
               "Google Haritalar'da aç</a>")))
    cukurlar = []
    for i in r['isaretler']:
        c, b, x = i['cukur'], i['basis'], i['tahmini']
        if c is None and x is not None:
            cukurlar.append(dict(
                e=x['d_enlem'], b=x['d_boylam'], r=i['tahmini_belirsizlik'], no=f'Ç{i["no"]}?', yaklasik=True,
                basis=[b['d_enlem'], b['d_boylam']] if b['d_enlem'] is not None else None,
                h=(f"<b>İşaretli çukur Ç{i['no']} - {html.escape(i['sonuc'])}</b><br>Sarsıntıdan kesin an bulunamadı; konum, "
                   f"basıştan tipik tepki süresi kadar önceki ana göre yaklaşık.<br>{x['d_enlem']:.6f}, {x['d_boylam']:.6f} "
                   f"±{i['tahmini_belirsizlik']:.0f} m<br><a href='{maps_link(x['d_enlem'], x['d_boylam'])}' target='_blank'>"
                   "Google Haritalar'da aç</a>")))
        if c is None or b['d_enlem'] is None:
            continue
        cukurlar.append(dict(
            e=c['d_enlem'], b=c['d_boylam'], r=c['belirsizlik_m'], no=f'Ç{i["no"]}', basis=[b['d_enlem'], b['d_boylam']],
            h=(f"<b>İşaretli çukur Ç{i['no']}</b><br>{c['d_enlem']:.6f}, {c['d_boylam']:.6f} "
               f"{'yol boyunca ' if c['yolda'] else ''}±{c['belirsizlik_m']:.0f} m<br>"
               f"Çukur {html.escape(c['zaman_metin'][11:22])} · {tr(c['d_hiz'], 1)} km/h · {tr(c['dmin'], 0)} / +{tr(c['dmax'], 0)} m/s²<br>"
               f"Butona {tr(i['tepki_s'], 1)} sn sonra basıldı (gri çizgi: basış yeri)<br>"
               f"<a href='{maps_link(c['d_enlem'], c['d_boylam'])}' target='_blank'>Google Haritalar'da aç</a>")))
    oturtuldu = r['oturtma'] is not None
    uyarilar = [dict(p=[s['d_enlem'], s['d_boylam']],
                     i=f"Uygulama uyarısı {s['zaman_metin'][11:22]} · {tr(s['d_hiz'], 1)} km/h · {tr(s['dmin'], 0)} / +{tr(s['dmax'], 0)} m/s²")
                for s in noktalar if s['uyg_cukur']]
    veri = json.dumps(dict(parcalar=parcalar, ham=ham, darbeler=darbeler, cukurlar=cukurlar, uyarilar=uyarilar), ensure_ascii=False)
    ad_h = html.escape(ad)
    sayfa = f"""<!doctype html>
<html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Sarsıntı haritası - {ad_h}</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>
  html, body {{ margin: 0; height: 100%; font-family: system-ui, sans-serif; background: #fcfcfb; }}
  #harita {{ position: absolute; inset: 0; }}
  .kutu {{ background: rgba(252,252,251,.94); padding: 8px 10px; border-radius: 6px; font-size: 12px; color: #0b0b0b; line-height: 1.5; max-width: 270px; }}
  .kutu b {{ font-size: 13px; }}
  .sade {{ filter: grayscale(1) brightness(1.08) contrast(0.85); }}
  .serit {{ display: flex; height: 14px; margin: 4px 0 2px; }} .serit span {{ flex: 1; }}
  .uclar {{ display: flex; justify-content: space-between; color: #52514e; }}
  .no, .cukur {{ color: #fff; border: 2px solid #fff; border-radius: 50%; font: bold 11px/18px system-ui, sans-serif;
         text-align: center; box-shadow: 0 1px 3px rgba(0,0,0,.45); }}
  .no {{ background: {MOR}; }}
  .cukur {{ background: #003366; border-radius: 4px; }}
  .cukur.yaklasik {{ background: #fcfcfb; color: #003366; border: 2px dashed #003366; }}
  .serit span {{ text-align: center; font-size: 10px; color: #0b0b0b; line-height: 14px; }}
  .ornek {{ display: inline-block; width: 12px; height: 12px; border: 2px solid #fff; box-shadow: 0 0 0 1px #898781; vertical-align: -2px; }}
</style></head><body><div id="harita"></div>
<script>
const V = {veri};
const harita = L.map('harita', {{ maxZoom: 21 }});
// Sade altlık: renkli Esri sokak haritasının soluklaştırılmışı (CARTO artık API anahtarı istiyor)
const sade = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{{z}}/{{y}}/{{x}}',
  {{ className: 'sade', maxNativeZoom: 19, maxZoom: 21, attribution: 'Esri, HERE, Garmin, &copy; OpenStreetMap katkıcıları' }});
const renkli = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{{z}}/{{y}}/{{x}}',
  {{ maxNativeZoom: 19, maxZoom: 21, attribution: 'Esri, HERE, Garmin, &copy; OpenStreetMap katkıcıları' }});
const uydu = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{{z}}/{{y}}/{{x}}',
  {{ maxNativeZoom: 19, maxZoom: 21, attribution: 'Uydu: Esri, Maxar, Earthstar Geographics' }});
const etiket = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{{z}}/{{y}}/{{x}}',
  {{ maxNativeZoom: 19, maxZoom: 21 }});
sade.addTo(harita);
const guzergah = L.layerGroup().addTo(harita), hamGps = L.layerGroup(), darbe = L.layerGroup().addTo(harita), cukur = L.layerGroup().addTo(harita),
  uyari = L.layerGroup().addTo(harita);
const sinir = [];
// Önce tüm güzergâhın koyu kenarı (açık altlıkta sarı da seçilsin), sonra renkli parçalar
L.polyline(V.parcalar.map(p => p.p), {{ color: '#0b0b0b', weight: 8, opacity: .25 }}).addTo(guzergah);
for (const p of V.parcalar) {{
  L.polyline(p.p, {{ color: p.r, weight: 5, opacity: 1, lineCap: 'butt', dashArray: p.d ? '4 6' : null }}).bindTooltip(p.i).addTo(guzergah);
  sinir.push(...p.p);
}}
for (const p of V.ham) L.polyline(p, {{ color: '#52514e', weight: 1.5, opacity: .9, dashArray: '2 4' }}).addTo(hamGps);
for (const d of V.darbeler) {{
  L.circle([d.e, d.b], {{ radius: d.r, color: '{MOR}', weight: 2, fillOpacity: .08 }}).addTo(darbe);
  for (const t of d.tek) L.circleMarker(t, {{ radius: 3, color: '{MOR}', weight: 1, fillOpacity: .8 }}).addTo(darbe);
  L.marker([d.e, d.b], {{ icon: L.divIcon({{ className: 'no', html: d.no, iconSize: [22, 22] }}) }}).bindPopup(d.h).addTo(darbe);
}}
for (const c of V.cukurlar) {{
  L.circle([c.e, c.b], {{ radius: c.r, color: '#003366', weight: 2, fillOpacity: c.yaklasik ? .04 : .12, dashArray: c.yaklasik ? '5 5' : null }}).addTo(cukur);
  if (c.basis) {{
    L.polyline([[c.e, c.b], c.basis], {{ color: '#898781', weight: 2, dashArray: '3 5' }}).addTo(cukur);
    L.circleMarker(c.basis, {{ radius: 4, color: '#ffffff', weight: 1.5, fillColor: '#52514e', fillOpacity: 1 }}).bindTooltip('Basış: ' + c.no).addTo(cukur);
  }}
  L.marker([c.e, c.b], {{ icon: L.divIcon({{ className: c.yaklasik ? 'cukur yaklasik' : 'cukur', html: c.no, iconSize: [30, 22] }}), zIndexOffset: 1000 }}).bindPopup(c.h).addTo(cukur);
}}
for (const u of V.uyarilar)
  L.circleMarker(u.p, {{ radius: 6, color: '#ffffff', weight: 2, fillColor: '#0b0b0b', fillOpacity: 1 }}).bindTooltip(u.i).addTo(uyari);
harita.fitBounds(sinir.length ? sinir : [[0, 0]], {{ padding: [30, 30] }});
const katmanlar = {{ 'Yer adları': etiket, 'Güzergâh': guzergah, 'Ham GPS (oturtma öncesi)': hamGps }};
if (V.uyarilar.length) katmanlar['Uygulama uyarıları'] = uyari;
katmanlar['Otomatik darbeler'] = darbe;
if (V.cukurlar.length) katmanlar['İşaretli çukurlar (eski buton)'] = cukur;
L.control.layers({{ 'Sokak haritası (sade)': sade, 'Sokak haritası (renkli)': renkli, 'Uydu görüntüsü': uydu }}, katmanlar).addTo(harita);
L.control.scale({{ imperial: false }}).addTo(harita);
const aciklama = L.control({{ position: 'bottomleft' }});
aciklama.onAdd = () => {{
  const k = L.DomUtil.create('div', 'kutu');
  k.innerHTML = `<b>{ad_h}</b><br>Güzergâh rengi: Dikey_RMS (m/s²){' - yola oturtulmuş' if oturtuldu else ''}
    <div class="serit">{''.join(f'<span style="background:{c}"></span>' for c in RENKLER)}</div>
    <div class="uclar"><span>0</span>{''.join(f'<span>{b}</span>' for b in SINIRLAR)}<span>+</span></div>
    yeşil: az, sarı: orta, kırmızı: çok sarsıntı<br>
    Kesikli gri: duruş{' / buton etkisi' if r['isaretler'] else ''}<br>
    {'<span class="ornek" style="background:#0b0b0b;border-radius:50%"></span> Uygulamanın anlık çukur uyarısı<br>' if any(s['uyg_cukur'] for s in noktalar) else ''}
    {'<span class="ornek" style="background:#003366;border-radius:3px"></span> Ç: butonla işaretlenen çukur (eski sürüm); Ç?: yaklaşık<br>' if r['isaretler'] else ''}
    <span class="ornek" style="background:{MOR};border-radius:50%"></span> Otomatik bulunan darbe noktası (numaralı)<br>
    Daireler: konum belirsizliği. Ayrıntı için işarete dokunun.`;
  return k;
}};
aciklama.addTo(harita);
</script></body></html>
"""
    with open(yol, 'w', encoding='utf-8') as f:
        f.write(sayfa)


def grafik_yaz(yol, ad, satirlar, r, tablo):
    try:
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
        from matplotlib.colors import BoundaryNorm, ListedColormap
    except ImportError:
        print('  (matplotlib kurulu değil, grafik atlandı: pip install matplotlib)')
        return
    INK, INK2, MUTED, GRID, AXIS, SURF = '#0b0b0b', '#52514e', '#898781', '#e1e0d9', '#c3c2b7', '#fcfcfb'
    MAVI, TURUNCU, KIRMIZI = '#2a78d6', '#eb6834', '#003366'
    UYARI = '#dc3545'  # uygulamanın anlık çukur uyarısı (ekrandaki kırmızı)
    plt.rcParams.update({'font.size': 10, 'axes.edgecolor': AXIS, 'axes.labelcolor': INK2, 'xtick.color': MUTED,
                         'ytick.color': MUTED, 'axes.facecolor': SURF, 'figure.facecolor': SURF, 'axes.grid': True,
                         'grid.color': GRID, 'grid.linewidth': 0.6, 'axes.spines.top': False, 'axes.spines.right': False,
                         'axes.titlesize': 11, 'axes.titleweight': 'bold', 'axes.titlecolor': INK, 'axes.titlelocation': 'left'})
    hareket = r['hareket']
    t0 = satirlar[0]['t']
    fig = plt.figure(figsize=(12, 9.5))
    gs = fig.add_gridspec(3, 2, height_ratios=[1, 1, 1.5], hspace=0.55, wspace=0.22)
    ax1 = fig.add_subplot(gs[0, :])
    ax2 = fig.add_subplot(gs[1, :], sharex=ax1)
    ax3, ax4 = fig.add_subplot(gs[2, 0]), fig.add_subplot(gs[2, 1])
    S = [s['t'] - t0 for s in satirlar]
    for ax in (ax1, ax2):  # analiz dışı satırlar (duruş, buton etkisi, GPS yok): gri bant
        bas = None
        for x, s in zip(S, satirlar):
            if s['durum'] != 'hareket' and bas is None:
                bas = x - 0.5
            elif s['durum'] == 'hareket' and bas is not None:
                ax.axvspan(bas, x - 0.5, color=GRID, alpha=0.6, lw=0)
                bas = None
        if bas is not None:
            ax.axvspan(bas, S[-1], color=GRID, alpha=0.6, lw=0)
        for i in r['isaretler']:  # basış anları
            ax.axvline(i['basis']['merkez'] - t0, color=INK2, lw=1, ls=':')
    ax1.plot(S, [s['d_hiz'] if s['d_hiz'] is not None else float('nan') for s in satirlar], color=MAVI, lw=2)
    ax1.set_title('Hız (km/h, GPS gecikmesi düzeltilmiş) – gri: analiz dışı'
                  + (', noktalı çizgi: butona basış' if r['isaretler'] else ''))
    ax1.set_ylim(bottom=0)
    ax2.plot(S, [s['rms'] for s in satirlar], color=TURUNCU, lw=2)
    for s in satirlar:
        if s['darbe']:
            ax2.plot([s['t'] - t0], [s['rms']], 'o', ms=8, color=INK, markeredgecolor=SURF, markeredgewidth=2, zorder=3)
        if s['uyg_cukur']:
            ax2.plot([s['t'] - t0], [s['rms']], 'o', ms=13, mfc='none', mec=UYARI, mew=2, zorder=4)
        if s['cukur']:
            ax2.plot([s['t'] - t0], [s['rms']], 's', ms=11, mfc='none', mec=KIRMIZI, mew=2.2, zorder=4)
    ax2.set_title('Dikey_RMS (m/s², 0,5 sn pencere) – siyah nokta: otomatik darbe'
                  + (', kırmızı halka: uygulamanın anlık uyarısı' if any(s['uyg_cukur'] for s in satirlar) else '')
                  + (', lacivert kare: işaretli çukur' if r['isaretler'] else ''))
    ax2.set_xlabel('Kayıt başından itibaren süre (s)')
    ax2.set_ylim(bottom=0)
    if hareket:
        ax3.scatter([s['d_hiz'] for s in hareket], [s['rms'] for s in hareket], s=22, color=TURUNCU, alpha=0.45, edgecolors='none')
        ax3.plot([(t['alt'] + t['ust']) / 2 for t in tablo], [t['rms_medyan'] for t in tablo], color=INK, lw=2, marker='o',
                 ms=7, markerfacecolor=INK, markeredgecolor=SURF, markeredgewidth=2)
    ax3.set_title('Hıza göre dikey sarsıntı (siyah: medyan)')
    ax3.set_xlabel('Hız (km/h)')
    ax3.set_ylabel('Dikey_RMS (m/s²)')
    ax3.set_xlim(left=0)
    ax3.set_ylim(bottom=0)
    noktalar = [s for s in satirlar if s['d_enlem'] is not None]
    if noktalar:
        e0 = min(s['d_enlem'] for s in noktalar)
        b0 = min(s['d_boylam'] for s in noktalar)
        kx = DEG_M * math.cos(math.radians(e0))

        def X(b):
            return (b - b0) * kx

        def Y(e):
            return (e - e0) * DEG_M
        if r['oturtma'] is not None:
            ax4.plot([X(s['h_boylam']) for s in noktalar], [Y(s['h_enlem']) for s in noktalar], color=MUTED, lw=0.8, ls=':', zorder=0,
                     label='ham GPS')
        ax4.plot([X(s['d_boylam']) for s in noktalar], [Y(s['d_enlem']) for s in noktalar], color=AXIS, lw=0.8, zorder=0)
        hn = [s for s in noktalar if s['durum'] == 'hareket']
        duzgun = dict(zip(map(id, noktalar), yumusat(noktalar)))
        sinir = [0] + SINIRLAR + [max(SINIRLAR[-1] + 2, max(s['rms'] for s in noktalar))]
        sc = ax4.scatter([X(s['d_boylam']) for s in hn], [Y(s['d_enlem']) for s in hn], c=[duzgun[id(s)] for s in hn],
                         cmap=ListedColormap(RENKLER), norm=BoundaryNorm(sinir, len(RENKLER)), s=26, edgecolors='#52514e', linewidths=0.4)
        for n, k in enumerate(r['kumeler'], 1):
            ax4.add_patch(plt.Circle((X(k['boylam']), Y(k['enlem'])), k['belirsizlik_m'], fill=False, color=MOR, lw=1.2))
        for i in r['isaretler']:
            c = i['cukur']
            if c is not None:
                ax4.plot([X(c['d_boylam'])], [Y(c['d_enlem'])], 's', ms=9, color=KIRMIZI, markeredgecolor=SURF, markeredgewidth=1.5, zorder=5)
                ax4.annotate(f'Ç{i["no"]}', (X(c['d_boylam']), Y(c['d_enlem'])), xytext=(6, 4), textcoords='offset points',
                             fontsize=8.5, fontweight='bold', color=KIRMIZI)
            elif i['tahmini'] is not None:
                x = i['tahmini']
                ax4.plot([X(x['d_boylam'])], [Y(x['d_enlem'])], 's', ms=9, mfc='none', mec=KIRMIZI, mew=1.5, zorder=5)
                ax4.annotate(f'Ç{i["no"]}?', (X(x['d_boylam']), Y(x['d_enlem'])), xytext=(6, 4), textcoords='offset points',
                             fontsize=8.5, color=KIRMIZI)
        ax4.set_aspect('equal', adjustable='datalim')
        cb = fig.colorbar(sc, ax=ax4, shrink=0.8, ticks=[0] + SINIRLAR)
        cb.set_label('Dikey_RMS (m/s²)', color=INK2)
        cb.outline.set_visible(False)
        if r['oturtma'] is not None:
            ax4.legend(loc='lower right', fontsize=8, frameon=False)
    ax4.set_title('Güzergâh – yeşil: az, sarı: orta, kırmızı: çok sarsıntı; mor: darbe')
    ax4.set_xlabel('Doğu (m)')
    ax4.set_ylabel('Kuzey (m)')
    fig.suptitle(f'Sürüş analizi – {ad}', x=0.06, ha='left', fontsize=13, fontweight='bold', color=INK)
    fig.savefig(yol, dpi=130, bbox_inches='tight')
    plt.close(fig)


# ---------------------------------------------------------------- ana akış

def ayristirici():
    p = argparse.ArgumentParser(description='Mikromobilite sarsıntı kaydı analizi (uygulamanın CSV dosyaları).')
    p.add_argument('csv', nargs='*', help='Analiz edilecek CSV dosya(lar)ı')
    p.add_argument('--cikti', help='Çıktı klasörü (varsayılan: CSV\'nin yanında <ad>_analiz)')
    p.add_argument('--gecikme', type=float, default=1.0, help='GPS gecikmesi, sn (varsayılan 1,0)')
    p.add_argument('--min-hiz', type=float, default=3.0, help='Bunun altı duruş sayılır, km/h (varsayılan 3)')
    p.add_argument('--oturtma', choices=['acik', 'kapali'], default='acik', help='Haritaya oturtma (varsayılan açık)')
    p.add_argument('--osm', help='Yol verisi olarak bu OSM JSON dosyasını kullan (internetten indirmek yerine)')
    p.add_argument('--oturtma-beta', type=float, default=5.0, help='Oturtma: yol/düz mesafe farkı ölçeği, m (varsayılan 5)')
    p.add_argument('--yol-disi-ceza', type=float, default=2.5,
                   help='Oturtma: yol bu kadar sigma\'dan uzaksa nokta yol dışı kalır (varsayılan 2,5)')
    p.add_argument('--isaret-arama', type=float, default=5.0, help='Basıştan önce çukur aranan süre, sn (varsayılan 5)')
    p.add_argument('--isaret-min-oran', type=float, default=3.0,
                   help='Eşleşme için tepe ≥ bu oran × çevre RMS (varsayılan 3)')
    p.add_argument('--isaret-belirsiz', type=float, default=0.8,
                   help='İkinci bir tepe en büyüğün bu oranına ulaşıyorsa eşleşme belirsiz sayılır (varsayılan 0,8)')
    p.add_argument('--isaret-dislama', type=float, default=0.5,
                   help='Basıştan sonra analiz dışı bırakılan süre, sn (varsayılan 0,5)')
    p.add_argument('--darbe-orani', type=float, default=4.0, help='Darbe: tepe ≥ oran × çevre RMS (varsayılan 4)')
    p.add_argument('--darbe-esik', type=float, default=10.0, help='Darbe: tepe ≥ bu değer, m/s² (varsayılan 10)')
    p.add_argument('--darbe-taban', choices=['iki-yan', 'ortak'], default='iki-yan',
                   help='Darbe tabanı: önceki / sonraki 10 sn medyanlarından büyüğü (iki-yan, varsayılan: yanlış alarm daha az) '
                        'veya ±10 sn tek medyan (ortak: daha çok çukur bulur, yüzey geçişlerinde yanlış alarm)')
    p.add_argument('--kume-yaricap', type=float, default=10.0,
                   help='Grup merkezine bu mesafedeki darbeler / çukurlar aynı nokta sayılır, m (varsayılan 10)')
    p.add_argument('--hiz-araligi', type=float, default=3.0, help='Hız tablosu aralığı, km/h (varsayılan 3)')
    return p


def dosyalari_bul(girdiler):
    """Dosya adları, klasörler (içindeki mikromobilite_*.csv) ve joker karakterli adlar (*.csv: Windows komut
    satırı bunları kendisi açmaz)"""
    kayit_adi = re.compile(r'^mikromobilite_\d{8}_\d{6}\.csv$')  # betiğin kendi çıktıları (_satirlar.csv vb.) hariç
    dosyalar = []
    for g in girdiler:
        if os.path.isdir(g):
            dosyalar += sorted(f for f in glob.glob(os.path.join(g, '*.csv')) if kayit_adi.match(os.path.basename(f)))
        elif any(c in g for c in '*?['):
            dosyalar += sorted(glob.glob(g))
        else:
            dosyalar.append(g)
    tekil = {}
    for d in dosyalar:  # aynı dosya farklı yazımla (klasör + tam yol) verilirse bir kez
        tekil.setdefault(os.path.realpath(d), d)
    return list(tekil.values())


def varsayilan_ayar(**degisiklik):
    """Komut satırı varsayılanlarıyla ayar nesnesi (başka betiklerden çağırmak için)"""
    ayar = ayristirici().parse_args([])
    for k, v in degisiklik.items():
        setattr(ayar, k, v)
    return ayar


def dosya_analiz(yol, ayar, klasor=None, yaz=True, onbellek=None):
    """Bir CSV'yi analiz et; yaz=True ise tüm çıktıları klasöre yaz. Sonuç sözlüğünü döndürür.
    onbellek: yol verisinin saklanacağı dosya (verilmezse yaz=True iken çıktı klasöründe)."""
    ad = os.path.splitext(os.path.basename(yol))[0]
    klasor = klasor or ayar.cikti or os.path.join(os.path.dirname(os.path.abspath(yol)), f'{ad}_analiz')
    satirlar = oku(yol)
    if onbellek is None and yaz:
        onbellek = os.path.join(klasor, f'{ad}_osm.json')
    if yaz:
        os.makedirs(klasor, exist_ok=True)
    osm, osm_kaynak = osm_yukle(gps_olcumleri(satirlar), ayar, onbellek)
    r = analiz_et(satirlar, ayar, osm)
    r['satirlar'] = satirlar
    r['etiket'] = bilgi_oku(yol)
    r['osm_kaynak'] = osm_kaynak
    if yaz:
        def cikti(son):
            return os.path.join(klasor, f'{ad}_{son}')
        tablo = hiz_tablosu(r['hareket'], ayar.hiz_araligi)
        ozet_yaz(cikti('ozet.txt'), ad, satirlar, r, tablo, ayar, osm_kaynak)
        satirlar_yaz(cikti('satirlar.csv'), satirlar)
        if r['isaretler']:  # yalnızca eski sürümün çukur butonuyla yapılmış kayıtlar
            isaretler_yaz(cikti('isaretler.csv'), r['isaretler'])
        olaylar_yaz(cikti('olaylar.csv'), r['kumeler'])
        sokaklar_yaz(cikti('sokaklar.csv'), r['sokaklar'])
        geojson_yaz(cikti('harita.geojson'), satirlar, r)
        harita_yaz(cikti('harita.html'), ad, satirlar, r, ayar)
        grafik_yaz(cikti('grafik.png'), ad, satirlar, r, tablo)
    return r


def main():
    p = ayristirici()
    ayar = p.parse_args()
    dosyalar = dosyalari_bul(ayar.csv)
    if not dosyalar:
        p.error('en az bir CSV dosyası veya kayıtların bulunduğu klasörü verin')
    for yol in dosyalar:
        print(yol)
        try:
            r = dosya_analiz(yol, ayar)
        except KayitHatasi as e:
            print(f'  ATLANDI: {e}')
            continue
        uyari = sum(1 for s in r['satirlar'] if s['uyg_cukur'])
        ek = ''
        if r['isaretler']:
            eslesen = sum(1 for i in r['isaretler'] if i['cukur'] is not None)
            ek = f', {len(r["isaretler"])} buton basışı ({eslesen} çukur eşleşti)'
        print(f'  {len(r["hareket"])} hareket satırı, {uyari} uygulama uyarısı, '
              f'{len(r["olaylar"])} otomatik darbe ({len(r["kumeler"])} nokta){ek}')


if __name__ == '__main__':
    main()
