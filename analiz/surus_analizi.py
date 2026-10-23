#!/usr/bin/env python3
"""Mikromobilite sarsıntı kaydı analizi.

Uygulamanın ürettiği CSV dosyalarını (Türkçe Excel biçimi: ';' ayırıcı, ',' ondalık) okur ve
her kayıt için şunları üretir:

  <ad>_ozet.txt        Veri kalitesi, hız aralıklarına göre sarsıntı tablosu, darbe listesi
  <ad>_satirlar.csv    Düzeltilmiş hız/konum, durum (hareket / duruş) ve darbe işaretiyle tüm satırlar
  <ad>_olaylar.csv     Tespit edilen darbeler (konum, belirsizlik yarıçapı, hız, tepe değer)
  <ad>_harita.html     Uydu görüntüsü üzerinde güzergâh (renk = sarsıntı) ve darbeler (tarayıcıda açılır)
  <ad>_harita.geojson  Aynı veri, QGIS / ArcGIS için
  <ad>_grafik.png      Hız, sarsıntı, hız-sarsıntı ilişkisi ve güzergâh (matplotlib kuruluysa)

Yapılan düzeltmeler:
  * GPS gecikmesi: telefonun GPS yongası hızı ve konumu yaklaşık 1 sn geç bildirir. Her satırın
    sarsıntısı, --gecikme kadar sonra gelen GPS değeriyle eşleştirilir.
  * Konum enterpolasyonu: GPS saniyede 1 kez güncellenir; satırlar (0,5 sn) arasındaki konum ve hız
    iki GPS ölçümü arasında doğrusal enterpolasyonla bulunur.
  * Duruş ayıklama: düzeltilmiş hız --min-hiz altındaysa satır "duruş" sayılır ve analize girmez
    (scooter'ı elle çevirme, itme vb. sarsıntılar bu yolla ayıklanır).

Darbe tespiti: bir satırın tepe değeri max(|Dikey_Min|, Dikey_Max), çevresindeki ±10 sn'lik
hareket satırlarının Dikey_RMS medyanının --darbe-orani katını VE --darbe-esik değerini aşıyorsa
o satır darbe sayılır. Farklı geçişlerde birbirine --kume-yaricap metreden yakın darbeler aynı
noktanın tekrarı olarak gruplanır; grup merkezi tek ölçümden daha güvenilirdir.

Kullanım:
  python surus_analizi.py kayit.csv [kayit2.csv ...] [--cikti klasor] [--gecikme 1.0] ...
  python surus_analizi.py -h        (tüm ayarlar)
"""

import argparse
import csv
import html
import json
import math
import os
import statistics as st
import sys
from datetime import datetime

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


def oku(yol):
    with open(yol, encoding='utf-8-sig') as f:
        okuyucu = csv.DictReader(f, delimiter=';')
        gerekli = {'Tarih_Saat', 'Enlem', 'Boylam', 'GPS_Doppler_Hiz_kmh', 'Dikey_RMS', 'Dikey_Min', 'Dikey_Max'}
        eksik = gerekli - set(okuyucu.fieldnames or [])
        if eksik:
            sys.exit(f'{yol}: beklenen sütunlar yok: {", ".join(sorted(eksik))} '
                     '(eski biçimdeki kayıtlar bu betikle okunamaz)')
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
            ))
    if not satirlar:
        sys.exit(f'{yol}: veri satırı yok')
    return satirlar


# ---------------------------------------------------------------- GPS düzeltmeleri

def gps_olcumleri(satirlar):
    """Art arda tekrar eden satırlardan tekil GPS ölçümlerini çıkarır (her biri ilk göründüğü an)."""
    olcumler, onceki = [], None
    for s in satirlar:
        if s['enlem'] is None:
            onceki = None
            continue
        anahtar = (s['enlem'], s['boylam'], s['hiz'], s['dogruluk'])
        if anahtar != onceki:
            olcumler.append(dict(t=s['t'], enlem=s['enlem'], boylam=s['boylam'], hiz=s['hiz'], dogruluk=s['dogruluk']))
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
    return {alan: a[alan] + k * (b[alan] - a[alan]) if a[alan] is not None and b[alan] is not None else a[alan]
            for alan in ('enlem', 'boylam', 'hiz', 'dogruluk')}


def mesafe(e1, b1, e2, b2):
    """İki nokta arası mesafe (m), haversine"""
    r = 6371000.0
    p1, p2 = math.radians(e1), math.radians(e2)
    dp, dl = p2 - p1, math.radians(b2 - b1)
    return 2 * r * math.asin(math.sqrt(math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2))


# ---------------------------------------------------------------- analiz

def analiz_et(satirlar, ayar):
    olcumler = gps_olcumleri(satirlar)
    for s in satirlar:
        # Satır, yazıldığı andan önceki 0,5 sn'yi özetler: pencere ortası = yazılma anı − 0,25 sn
        merkez = s['t'] - 0.25
        g = gps_degeri(olcumler, merkez + ayar.gecikme)
        s['d_enlem'] = g['enlem'] if g else None
        s['d_boylam'] = g['boylam'] if g else None
        s['d_hiz'] = g['hiz'] if g else None
        s['d_dogruluk'] = g['dogruluk'] if g else None
        s['tepe'] = max(abs(s['dmin']), s['dmax'])
        if s['d_hiz'] is None:
            s['durum'] = 'gps_yok'
        elif s['d_hiz'] < ayar.min_hiz:
            s['durum'] = 'durus'
        else:
            s['durum'] = 'hareket'
        s['darbe'] = False
        s['zemin_rms'] = None

    hareket = [s for s in satirlar if s['durum'] == 'hareket']

    # Darbe tespiti: çevredeki (±10 sn) hareket satırlarının RMS medyanına göre
    for s in hareket:
        komsu = [k['rms'] for k in hareket if k is not s and abs(k['t'] - s['t']) <= 10.0]
        if len(komsu) < 5:
            continue
        s['zemin_rms'] = st.median(komsu)
        if s['tepe'] >= ayar.darbe_orani * s['zemin_rms'] and s['tepe'] >= ayar.darbe_esik:
            s['darbe'] = True

    # Art arda (1 sn içinde) işaretlenen satırlar tek darbedir: en büyük tepeli satır kalır
    olaylar = []
    for s in hareket:
        if not s['darbe']:
            continue
        if olaylar and s['t'] - olaylar[-1]['son_t'] <= 1.01:
            olaylar[-1]['son_t'] = s['t']
            if s['tepe'] > olaylar[-1]['satir']['tepe']:
                olaylar[-1]['satir']['darbe'] = False
                olaylar[-1]['satir'] = s
            else:
                s['darbe'] = False
            continue
        olaylar.append(dict(satir=s, son_t=s['t']))
    olaylar = [o['satir'] for o in olaylar]

    for o in olaylar:
        # Belirsizlik: GPS doğruluğu + pencere içinde darbenin yeri bilinmez (±0,25 sn) + gecikme belirsizliği (±0,5 sn)
        v = o['d_hiz'] / 3.6
        o['belirsizlik_m'] = math.sqrt((o['d_dogruluk'] or 10.0) ** 2 + (v * 0.25) ** 2 + (v * 0.5) ** 2)

    kumeler = kumele(olaylar, ayar.kume_yaricap)
    return olcumler, hareket, olaylar, kumeler


def kumele(olaylar, yaricap):
    """Farklı geçişlerde aynı noktada ölçülen darbeleri grupla.
    En büyük darbeden başlayarak her darbe, merkezi yaricap metre içindeki en yakın gruba katılır;
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
        # Ağırlık: GPS doğruluğunun karesinin tersi (daha doğru ölçüm daha çok sayılır)
        w = [1 / max(x['belirsizlik_m'], 1.0) ** 2 for x in g]
        enlem = sum(wi * x['d_enlem'] for wi, x in zip(w, g)) / sum(w)
        boylam = sum(wi * x['d_boylam'] for wi, x in zip(w, g)) / sum(w)
        belirsizlik = math.sqrt(1 / sum(w))  # n ölçümün ortalaması: ~1/√n küçülür
        kumeler.append(dict(enlem=enlem, boylam=boylam, belirsizlik_m=belirsizlik, olaylar=sorted(g, key=lambda x: x['t']),
                            en_buyuk=max(x['tepe'] for x in g)))
    kumeler.sort(key=lambda k: (-len(k['olaylar']), -k['en_buyuk']))
    return kumeler


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


def ozet_yaz(yol, ad, satirlar, olcumler, hareket, olaylar, kumeler, tablo, ayar):
    sure = satirlar[-1]['t'] - satirlar[0]['t'] + 0.5
    yol_m = sum(mesafe(olcumler[i]['enlem'], olcumler[i]['boylam'], olcumler[i + 1]['enlem'], olcumler[i + 1]['boylam'])
                for i in range(len(olcumler) - 1))
    ornek = [s['ornek'] for s in satirlar if s['ornek']]
    dogruluk = [o['dogruluk'] for o in olcumler if o['dogruluk'] is not None]
    satir = []
    y = satir.append
    y(f'SÜRÜŞ ANALİZİ - {ad}')
    y(f'Başlangıç: {satirlar[0]["zaman_metin"]}   Süre: {tr(sure, 0)} s   Satır: {len(satirlar)}')
    y(f'GPS ile ölçülen yol: ~{yol_m:.0f} m   En yüksek hız: {tr(max((o["hiz"] for o in olcumler), default=0), 1)} km/h')
    y('')
    y('AYARLAR')
    y(f'  GPS gecikme düzeltmesi: {tr(ayar.gecikme, 1)} s   Duruş eşiği: {tr(ayar.min_hiz, 1)} km/h')
    y(f'  Darbe: tepe ≥ {tr(ayar.darbe_orani, 1)} × çevre RMS ve ≥ {tr(ayar.darbe_esik, 0)} m/s²   Gruplama yarıçapı: {tr(ayar.kume_yaricap, 0)} m')
    y('')
    y('VERİ KALİTESİ')
    if ornek:
        y(f'  İvmeölçer: 0,5 sn\'de {min(ornek)}-{max(ornek)} örnek (~{2 * st.mean(ornek):.0f} Hz)')
    y(f'  GPS ölçümü: {len(olcumler)} adet (~{tr(len(olcumler) / sure, 1)} Hz)')
    if dogruluk:
        y(f'  GPS doğruluğu: {tr(min(dogruluk), 1)}-{tr(max(dogruluk), 1)} m (ortalama {tr(st.mean(dogruluk), 1)} m)')
    y(f'  GPS olmayan satır: {sum(1 for s in satirlar if s["durum"] == "gps_yok")}   '
      f'Duruş satırı: {sum(1 for s in satirlar if s["durum"] == "durus")}   Hareket satırı: {len(hareket)}')
    y(f'  En büyük ivme tepesi (tüm satırlar): {tr(max(s["tepe"] for s in satirlar), 1)} m/s² '
      '(telefonun ölçüm aralığı _bilgi.txt dosyasında; yakınsa sensör doymuş olabilir)')
    y('')
    y('HIZA GÖRE DİKEY SARSINTI (yalnızca hareket satırları)')
    y(f'  {"Hız (km/h)":<12}{"Satır":>7}{"RMS medyan":>13}{"RMS ort.":>11}{"Tepe medyan":>14}')
    for r in tablo:
        y(f'  {tr(r["alt"], 0) + "-" + tr(r["ust"], 0):<12}{r["n"]:>7}{tr(r["rms_medyan"]):>13}{tr(r["rms_ort"]):>11}{tr(r["tepe_medyan"], 1):>14}')
    if len(hareket) >= 3:
        xs, ys = [s['d_hiz'] for s in hareket], [s['rms'] for s in hareket]
        try:
            r = st.correlation(xs, ys)
            fit = st.linear_regression(xs, ys)
            y(f'  Korelasyon r = {tr(r)}   Doğrusal uyum: RMS ≈ {tr(fit.intercept)} + {tr(fit.slope, 3)} × hız')
        except st.StatisticsError:
            pass
    y('')
    y(f'DARBELER ({len(olaylar)} adet, {len(kumeler)} farklı nokta)')
    for i, k in enumerate(kumeler, 1):
        y(f'  Nokta {i}: {k["enlem"]:.6f}, {k["boylam"]:.6f}  ±{k["belirsizlik_m"]:.0f} m  '
          f'({len(k["olaylar"])} geçişte, en büyük tepe {tr(k["en_buyuk"], 1)} m/s²)')
        y(f'    {maps_link(k["enlem"], k["boylam"])}')
        for o in k['olaylar']:
            y(f'    - {o["zaman_metin"][11:22]}  hız {tr(o["d_hiz"], 1)} km/h  Min {tr(o["dmin"], 1)} / Max {tr(o["dmax"], 1)} m/s²  '
              f'çevre RMS {tr(o["zemin_rms"], 1)}  konum ±{o["belirsizlik_m"]:.0f} m')
    y('')
    y('NOT: Konumlar telefon GPS\'inin doğruluğuyla sınırlıdır. Yerinde kontrol için darbe noktasını,')
    y('harita dosyasındaki belirsizlik dairesi içinde güzergâh boyunca arayın.')
    with open(yol, 'w', encoding='utf-8') as f:
        f.write('\n'.join(satir) + '\n')


def satirlar_yaz(yol, satirlar):
    with open(yol, 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.writer(f, delimiter=';')
        w.writerow(['Tarih_Saat', 'Duzeltilmis_Enlem', 'Duzeltilmis_Boylam', 'Duzeltilmis_Hiz_kmh', 'GPS_Dogruluk_m',
                    'Dikey_RMS', 'Dikey_Min', 'Dikey_Max', 'Tepe', 'Cevre_RMS', 'Durum', 'Darbe'])
        for s in satirlar:
            w.writerow([s['zaman_metin'], tr(s['d_enlem'], 6), tr(s['d_boylam'], 6), tr(s['d_hiz']), tr(s['d_dogruluk'], 1),
                        tr(s['rms'], 4), tr(s['dmin'], 4), tr(s['dmax'], 4), tr(s['tepe'], 4), tr(s['zemin_rms'], 4),
                        s['durum'], 'evet' if s['darbe'] else ''])


def olaylar_yaz(yol, kumeler):
    with open(yol, 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.writer(f, delimiter=';')
        w.writerow(['Nokta', 'Tarih_Saat', 'Enlem', 'Boylam', 'Belirsizlik_m', 'Hiz_kmh', 'Dikey_Min', 'Dikey_Max',
                    'Cevre_RMS', 'Nokta_Enlem', 'Nokta_Boylam', 'Nokta_Belirsizlik_m', 'Gecis_Sayisi', 'Google_Maps'])
        for i, k in enumerate(kumeler, 1):
            for o in k['olaylar']:
                w.writerow([i, o['zaman_metin'], tr(o['d_enlem'], 6), tr(o['d_boylam'], 6), tr(o['belirsizlik_m'], 1),
                            tr(o['d_hiz']), tr(o['dmin'], 2), tr(o['dmax'], 2), tr(o['zemin_rms'], 2),
                            tr(k['enlem'], 6), tr(k['boylam'], 6), tr(k['belirsizlik_m'], 1), len(k['olaylar']),
                            maps_link(k['enlem'], k['boylam'])])


def geojson_yaz(yol, satirlar, kumeler):
    ozellikler = []
    for s in satirlar:
        if s['d_enlem'] is None:
            continue
        ozellikler.append({'type': 'Feature', 'geometry': {'type': 'Point', 'coordinates': [s['d_boylam'], s['d_enlem']]},
                           'properties': {'tur': 'satir', 'zaman': s['zaman_metin'], 'hiz_kmh': round(s['d_hiz'], 2),
                                          'dikey_rms': s['rms'], 'tepe': s['tepe'], 'durum': s['durum'], 'darbe': s['darbe']}})
    for i, k in enumerate(kumeler, 1):
        ozellikler.append({'type': 'Feature', 'geometry': {'type': 'Point', 'coordinates': [k['boylam'], k['enlem']]},
                           'properties': {'tur': 'darbe_noktasi', 'no': i, 'gecis_sayisi': len(k['olaylar']),
                                          'en_buyuk_tepe': k['en_buyuk'], 'belirsizlik_m': round(k['belirsizlik_m'], 1)}})
    with open(yol, 'w', encoding='utf-8') as f:
        json.dump({'type': 'FeatureCollection', 'features': ozellikler}, f, ensure_ascii=False)


RENKLER = ['#cde2fb', '#9ec5f4', '#6da7ec', '#3987e5', '#256abf', '#184f95', '#0d366b']  # açık -> koyu mavi


def renk(rms, ust):
    i = min(int(rms / ust * len(RENKLER)), len(RENKLER) - 1)
    return RENKLER[max(i, 0)]


def harita_yaz(yol, ad, satirlar, kumeler, ayar):
    noktalar = [s for s in satirlar if s['d_enlem'] is not None]
    if not noktalar:
        return
    ust = max(1.0, sorted(s['rms'] for s in noktalar)[int(0.95 * (len(noktalar) - 1))])
    parcalar = []
    for a, b in zip(noktalar, noktalar[1:]):
        if b['t'] - a['t'] > 1.5:
            continue
        parcalar.append(dict(p=[[a['d_enlem'], a['d_boylam']], [b['d_enlem'], b['d_boylam']]],
                             r=renk(a['rms'], ust) if a['durum'] == 'hareket' else '#898781',
                             d=a['durum'] != 'hareket',
                             i=f"{a['zaman_metin'][11:22]} · {tr(a['d_hiz'], 1)} km/h · RMS {tr(a['rms'])} m/s²"))
    darbeler = []
    for i, k in enumerate(kumeler, 1):
        satir = ''.join(f"<br>{html.escape(o['zaman_metin'][11:22])} · {tr(o['d_hiz'], 1)} km/h · "
                        f"{tr(o['dmin'], 0)} / +{tr(o['dmax'], 0)} m/s²" for o in k['olaylar'])
        darbeler.append(dict(
            e=k['enlem'], b=k['boylam'], r=k['belirsizlik_m'], no=i,
            tek=[[o['d_enlem'], o['d_boylam']] for o in k['olaylar']],
            h=(f"<b>Darbe noktası {i}</b> ({len(k['olaylar'])} geçiş)<br>{k['enlem']:.6f}, {k['boylam']:.6f} ±{k['belirsizlik_m']:.0f} m"
               f"{satir}<br><a href='{maps_link(k['enlem'], k['boylam'])}' target='_blank'>Google Haritalar'da aç</a>")))
    veri = json.dumps(dict(parcalar=parcalar, darbeler=darbeler), ensure_ascii=False)
    ad_h = html.escape(ad)
    sayfa = f"""<!doctype html>
<html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Sarsıntı haritası - {ad_h}</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>
  html, body {{ margin: 0; height: 100%; font-family: system-ui, sans-serif; background: #fcfcfb; }}
  #harita {{ position: absolute; inset: 0; }}
  .kutu {{ background: rgba(252,252,251,.94); padding: 8px 10px; border-radius: 6px; font-size: 12px; color: #0b0b0b; line-height: 1.5; max-width: 260px; }}
  .kutu b {{ font-size: 13px; }}
  .serit {{ display: flex; height: 10px; margin: 4px 0 2px; }} .serit span {{ flex: 1; }}
  .uclar {{ display: flex; justify-content: space-between; color: #52514e; }}
  .no {{ background: #eb6834; color: #fff; border: 2px solid #fff; border-radius: 50%; font: bold 12px/18px system-ui, sans-serif;
         text-align: center; box-shadow: 0 1px 3px rgba(0,0,0,.45); }}
</style></head><body><div id="harita"></div>
<script>
const V = {veri};
const harita = L.map('harita', {{ maxZoom: 21 }});
const uydu = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{{z}}/{{y}}/{{x}}',
  {{ maxNativeZoom: 19, maxZoom: 21, attribution: 'Uydu: Esri, Maxar, Earthstar Geographics' }});
const sokak = L.tileLayer('https://tile.openstreetmap.org/{{z}}/{{x}}/{{y}}.png',
  {{ maxNativeZoom: 19, maxZoom: 21, attribution: '&copy; OpenStreetMap katkıcıları' }});
const etiket = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{{z}}/{{y}}/{{x}}',
  {{ maxNativeZoom: 19, maxZoom: 21 }});
uydu.addTo(harita);
const guzergah = L.layerGroup().addTo(harita), darbe = L.layerGroup().addTo(harita);
const sinir = [];
for (const p of V.parcalar) {{
  L.polyline(p.p, {{ color: p.r, weight: 5, opacity: .95, dashArray: p.d ? '4 6' : null }}).bindTooltip(p.i).addTo(guzergah);
  sinir.push(...p.p);
}}
for (const d of V.darbeler) {{
  L.circle([d.e, d.b], {{ radius: d.r, color: '#eb6834', weight: 2, fillOpacity: .12 }}).addTo(darbe);
  for (const t of d.tek) L.circleMarker(t, {{ radius: 3, color: '#eb6834', weight: 1, fillOpacity: .8 }}).addTo(darbe);
  L.marker([d.e, d.b], {{ icon: L.divIcon({{ className: 'no', html: String(d.no), iconSize: [22, 22] }}) }})
    .bindPopup(d.h).addTo(darbe);
}}
harita.fitBounds(sinir.length ? sinir : [[0, 0]], {{ padding: [30, 30] }});
L.control.layers({{ 'Uydu görüntüsü': uydu, 'Sokak haritası': sokak }}, {{ 'Yer adları': etiket, 'Güzergâh': guzergah, 'Darbeler': darbe }}).addTo(harita);
L.control.scale({{ imperial: false }}).addTo(harita);
const aciklama = L.control({{ position: 'bottomleft' }});
aciklama.onAdd = () => {{
  const k = L.DomUtil.create('div', 'kutu');
  k.innerHTML = `<b>{ad_h}</b><br>Güzergâh rengi: Dikey_RMS (m/s²)
    <div class="serit">${{{json.dumps(RENKLER)}.map(c => `<span style="background:${{c}}"></span>`).join('')}}</div>
    <div class="uclar"><span>0</span><span>{tr(ust, 1)}+</span></div>
    Kesikli gri: duruş (&lt; {tr(ayar.min_hiz, 0)} km/h)<br>
    Turuncu daire: darbe noktası ve konum belirsizliği; küçük noktalar tek tek geçişler.
    Noktaya dokunun: ayrıntı ve Google Haritalar bağlantısı.`;
  return k;
}};
aciklama.addTo(harita);
</script></body></html>
"""
    with open(yol, 'w', encoding='utf-8') as f:
        f.write(sayfa)


def grafik_yaz(yol, ad, satirlar, hareket, tablo, kumeler):
    try:
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
        from matplotlib.colors import LinearSegmentedColormap
    except ImportError:
        print('  (matplotlib kurulu değil, grafik atlandı: pip install matplotlib)')
        return
    INK, INK2, MUTED, GRID, AXIS, SURF = '#0b0b0b', '#52514e', '#898781', '#e1e0d9', '#c3c2b7', '#fcfcfb'
    MAVI, TURUNCU = '#2a78d6', '#eb6834'
    plt.rcParams.update({'font.size': 10, 'axes.edgecolor': AXIS, 'axes.labelcolor': INK2, 'xtick.color': MUTED,
                         'ytick.color': MUTED, 'axes.facecolor': SURF, 'figure.facecolor': SURF, 'axes.grid': True,
                         'grid.color': GRID, 'grid.linewidth': 0.6, 'axes.spines.top': False, 'axes.spines.right': False,
                         'axes.titlesize': 11, 'axes.titleweight': 'bold', 'axes.titlecolor': INK, 'axes.titlelocation': 'left'})
    t0 = satirlar[0]['t']
    fig = plt.figure(figsize=(12, 9.5))
    gs = fig.add_gridspec(3, 2, height_ratios=[1, 1, 1.5], hspace=0.55, wspace=0.22)
    ax1, ax2 = fig.add_subplot(gs[0, :]), None
    ax2 = fig.add_subplot(gs[1, :], sharex=ax1)
    ax3, ax4 = fig.add_subplot(gs[2, 0]), fig.add_subplot(gs[2, 1])
    S = [s['t'] - t0 for s in satirlar]
    # Duruş bölgeleri gri bant
    for ax in (ax1, ax2):
        bas = None
        for x, s in zip(S, satirlar):
            if s['durum'] != 'hareket' and bas is None:
                bas = x - 0.5
            elif s['durum'] == 'hareket' and bas is not None:
                ax.axvspan(bas, x - 0.5, color=GRID, alpha=0.6, lw=0)
                bas = None
        if bas is not None:
            ax.axvspan(bas, S[-1], color=GRID, alpha=0.6, lw=0)
    ax1.plot(S, [s['d_hiz'] if s['d_hiz'] is not None else float('nan') for s in satirlar], color=MAVI, lw=2)
    ax1.set_title('Hız (km/h, GPS gecikmesi düzeltilmiş) – gri: duruş')
    ax1.set_ylim(bottom=0)
    ax2.plot(S, [s['rms'] for s in satirlar], color=TURUNCU, lw=2)
    for s in satirlar:
        if s['darbe']:
            ax2.plot([s['t'] - t0], [s['rms']], 'o', ms=8, color=INK, markeredgecolor=SURF, markeredgewidth=2)
    ax2.set_title('Dikey_RMS (m/s², 0,5 sn pencere) – siyah nokta: darbe')
    ax2.set_xlabel('Kayıt başından itibaren süre (s)')
    ax2.set_ylim(bottom=0)
    if hareket:
        ax3.scatter([s['d_hiz'] for s in hareket], [s['rms'] for s in hareket], s=22, color=TURUNCU, alpha=0.45, edgecolors='none')
        ax3.plot([(r['alt'] + r['ust']) / 2 for r in tablo], [r['rms_medyan'] for r in tablo], color=INK, lw=2, marker='o',
                 ms=7, markerfacecolor=INK, markeredgecolor=SURF, markeredgewidth=2)
    ax3.set_title('Hıza göre dikey sarsıntı (siyah: medyan)')
    ax3.set_xlabel('Hız (km/h)')
    ax3.set_ylabel('Dikey_RMS (m/s²)')
    ax3.set_xlim(left=0)
    ax3.set_ylim(bottom=0)
    noktalar = [s for s in satirlar if s['d_enlem'] is not None]
    if noktalar:
        e0, b0 = min(s['d_enlem'] for s in noktalar), min(s['d_boylam'] for s in noktalar)
        kx = DEG_M * math.cos(math.radians(e0))
        X = lambda b: (b - b0) * kx
        Y = lambda e: (e - e0) * DEG_M
        ax4.plot([X(s['d_boylam']) for s in noktalar], [Y(s['d_enlem']) for s in noktalar], color=AXIS, lw=0.8, zorder=0)
        hn = [s for s in noktalar if s['durum'] == 'hareket']
        cmap = LinearSegmentedColormap.from_list('mavi', RENKLER)
        sc = ax4.scatter([X(s['d_boylam']) for s in hn], [Y(s['d_enlem']) for s in hn], c=[s['rms'] for s in hn], cmap=cmap,
                         vmin=0, s=30, edgecolors=SURF, linewidths=0.8)
        for i, k in enumerate(kumeler, 1):
            ax4.add_patch(plt.Circle((X(k['boylam']), Y(k['enlem'])), k['belirsizlik_m'], fill=False, color=TURUNCU, lw=1.5))
            ax4.annotate(str(i), (X(k['boylam']), Y(k['enlem'])), ha='center', va='center', fontsize=9, fontweight='bold', color=INK)
        ax4.set_aspect('equal', adjustable='datalim')
        cb = fig.colorbar(sc, ax=ax4, shrink=0.8)
        cb.set_label('Dikey_RMS (m/s²)', color=INK2)
        cb.outline.set_visible(False)
    ax4.set_title('Güzergâh – turuncu daire: darbe noktası ± belirsizlik')
    ax4.set_xlabel('Doğu (m)')
    ax4.set_ylabel('Kuzey (m)')
    fig.suptitle(f'Sürüş analizi – {ad}', x=0.06, ha='left', fontsize=13, fontweight='bold', color=INK)
    fig.savefig(yol, dpi=130, bbox_inches='tight')
    plt.close(fig)


# ---------------------------------------------------------------- ana akış

def main():
    p = argparse.ArgumentParser(description='Mikromobilite sarsıntı kaydı analizi (uygulamanın CSV dosyaları).')
    p.add_argument('csv', nargs='+', help='Analiz edilecek CSV dosya(lar)ı')
    p.add_argument('--cikti', help='Çıktı klasörü (varsayılan: CSV\'nin yanında <ad>_analiz)')
    p.add_argument('--gecikme', type=float, default=1.0, help='GPS gecikmesi, sn (varsayılan 1,0)')
    p.add_argument('--min-hiz', type=float, default=3.0, help='Bunun altı duruş sayılır, km/h (varsayılan 3)')
    p.add_argument('--darbe-orani', type=float, default=4.0, help='Darbe: tepe ≥ oran × çevre RMS (varsayılan 4)')
    p.add_argument('--darbe-esik', type=float, default=20.0, help='Darbe: tepe ≥ bu değer, m/s² (varsayılan 20)')
    p.add_argument('--kume-yaricap', type=float, default=10.0, help='Grup merkezine bu mesafedeki darbeler aynı nokta sayılır, m (varsayılan 10)')
    p.add_argument('--hiz-araligi', type=float, default=3.0, help='Hız tablosu aralığı, km/h (varsayılan 3)')
    ayar = p.parse_args()

    for yol in ayar.csv:
        ad = os.path.splitext(os.path.basename(yol))[0]
        klasor = ayar.cikti or os.path.join(os.path.dirname(os.path.abspath(yol)), f'{ad}_analiz')
        os.makedirs(klasor, exist_ok=True)
        cikti = lambda son: os.path.join(klasor, f'{ad}_{son}')
        print(f'{yol} -> {klasor}')

        satirlar = oku(yol)
        olcumler, hareket, olaylar, kumeler = analiz_et(satirlar, ayar)
        tablo = hiz_tablosu(hareket, ayar.hiz_araligi)

        ozet_yaz(cikti('ozet.txt'), ad, satirlar, olcumler, hareket, olaylar, kumeler, tablo, ayar)
        satirlar_yaz(cikti('satirlar.csv'), satirlar)
        olaylar_yaz(cikti('olaylar.csv'), kumeler)
        geojson_yaz(cikti('harita.geojson'), satirlar, kumeler)
        harita_yaz(cikti('harita.html'), ad, satirlar, kumeler, ayar)
        grafik_yaz(cikti('grafik.png'), ad, satirlar, hareket, tablo, kumeler)
        print(f'  {len(hareket)} hareket satırı, {len(olaylar)} darbe, {len(kumeler)} darbe noktası')


if __name__ == '__main__':
    main()
