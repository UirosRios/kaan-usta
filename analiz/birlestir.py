#!/usr/bin/env python3
"""Birden fazla sürüşü birleştirerek yol kalitesi analizi.

Tüm sürüşler surus_analizi.py ile aynı yöntemle analiz edilir (GPS gecikmesi, haritaya oturtma, duruş
ayıklama, darbe tespiti), sonra birleştirilir:

  birlesik_ozet.txt        Sürüşler, en bozuk sokaklar, tekrar eden darbe noktaları
  birlesik_harita.html     Yol kalitesi haritası: 25 m'lik hücreler, renk = hız düzeltmeli sarsıntı indeksi
  birlesik_sokaklar.csv    Sokak sıralaması (tüm sürüşler)
  birlesik_suruslar.csv    Sürüş listesi (scooter, hava durumu, medyan hız / sarsıntı, darbe)
  birlesik_darbeler.csv    Darbe noktaları ve kaç farklı sürüşte görüldükleri
  birlesik_hucreler.geojson  Hücreler (QGIS / ArcGIS)

Hız düzeltmeli indeks: aynı 25 m'lik hücre içindeki hız farklarından sarsıntının hıza bağlılığı
(RMS ∝ hız^b) tahmin edilir ve her ölçüm 15 km/h'e çevrilir. Böylece bir sokakta hızlı, ötekinde yavaş
gidilmiş olması yüzey karşılaştırmasını bozmaz.

Kullanım:
  python birlestir.py kayitlar_klasoru
  python birlestir.py mikromobilite_20261023_234304.csv mikromobilite_20261024_011543.csv
  python birlestir.py klasor --tek-tek      (her sürüşün ayrı analizini de yaz)
"""

import csv
import html
import json
import os
import statistics as st
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import surus_analizi as sa  # noqa: E402

EN_AZ_SATIR = 4  # haritada gösterilecek hücre için en az satır (2 sn)


def hucre_tablosu(hareket, olaylar, b):
    gruplar = defaultdict(list)
    for s in hareket:
        gruplar[sa.hucre(s)].append(s)
    darbe = defaultdict(int)
    for o in olaylar:
        darbe[sa.hucre(o)] += 1
    tablo = []
    for h, g in gruplar.items():
        if len(g) < EN_AZ_SATIR:
            continue
        tablo.append(dict(
            hucre=h, sinir=sa.hucre_sinirlari(h, g[0]['d_enlem']), n=len(g), suruslar=sorted({s['surus'] for s in g}),
            rms=st.median(s['rms'] for s in g), hiz=st.median(s['d_hiz'] for s in g),
            indeks=st.median(sa.duzeltilmis_rms(s, b) for s in g) if b is not None else None,
            sokak=st.mode(sa.sokak_adi(s) for s in g), darbe=darbe[h]))
    return tablo


def ozet_yaz(yol, suruslar, sokaklar, hucreler, noktalar, b, osm_kaynak):
    satir = []
    y = satir.append
    y(f'BİRLEŞİK ANALİZ - {len(suruslar)} sürüş')
    y('')
    y('SÜRÜŞLER')
    y(f'  {"Kayıt":<34}{"Süre":>7}{"Yol":>8}{"Hız":>7}{"RMS":>7}{"Darbe":>7}  Scooter / Hava durumu')
    for k in suruslar:
        y(f'  {k["ad"][:33]:<34}{k["sure"]:>6.0f}s{k["yol_m"]:>7.0f}m{sa.tr(k["hiz"], 1):>7}{sa.tr(k["rms"]):>7}{k["darbe"]:>7}  '
          f'{k["etiket"].get("scooter", "-")} / {k["etiket"].get("hava", "-")}')
    scooterlar = {k['etiket']['scooter'] for k in suruslar if k['etiket'].get('scooter') and not k['etiket']['scooter'].startswith('belirtilmedi')}
    if len(scooterlar) > 1:
        y('  DİKKAT: sürüşlerde farklı scooterlar var; sarsıntı değerleri araca da bağlıdır.')
    y('')
    y(f'Haritaya oturtma: {osm_kaynak}')
    if b is not None:
        y(f'Hız düzeltmesi: RMS ∝ hız^{sa.tr(b)} (aynı 25 m\'lik hücredeki hız farklarından); İndeks = {sa.HIZ_REF:.0f} km/h\'te beklenen Dikey_RMS.')
    else:
        y('Hız düzeltmesi için veri yetersiz; sıralama medyan Dikey_RMS\'ye göre.')
    y('')
    y('SOKAKLAR (en bozuktan en düzgüne)')
    y(f'  {"Sokak":<34}{"Sürüş":>6}{"Yol (m)":>9}{"Hız":>7}{"RMS":>7}{"İndeks":>8}{"Darbe/100m":>12}')
    kisa = [t for t in sokaklar if t['yol_m'] < 30]
    for t in sokaklar:
        if t['yol_m'] < 30:
            continue
        y(f'  {t["ad"][:33]:<34}{len(t["suruslar"]):>6}{t["yol_m"]:>9.0f}{sa.tr(t["hiz"], 1):>7}{sa.tr(t["rms"]):>7}'
          f'{sa.tr(t["indeks"]) or "-":>8}{sa.tr(t["darbe_100m"], 1):>12}')
    if kisa:
        y(f'  (30 m\'den kısa geçilen {len(kisa)} yol özette gösterilmedi; birlesik_sokaklar.csv\'de var.)')
    y('')
    tekrar = [k for k in noktalar if k['surus_sayisi'] >= 2]
    y(f'TEKRAR EDEN DARBE NOKTALARI ({len(tekrar)} nokta en az 2 farklı sürüşte; toplam {len(noktalar)} nokta)')
    for n, k in enumerate(noktalar, 1):
        if k['surus_sayisi'] < 2:
            continue
        y(f'  Nokta {n}: {k["enlem"]:.6f}, {k["boylam"]:.6f} ±{k["belirsizlik_m"]:.0f} m  {k["surus_sayisi"]} sürüş, '
          f'{len(k["olaylar"])} geçiş, en büyük tepe {sa.tr(k["en_buyuk"], 1)} m/s²  {sa.maps_link(k["enlem"], k["boylam"])}')
    y('')
    y(f'Haritada {len(hucreler)} hücre (25 m, en az {EN_AZ_SATIR} satır). Tek sürüşte geçilen hücreler daha soluk gösterilir.')
    with open(yol, 'w', encoding='utf-8') as f:
        f.write('\n'.join(satir) + '\n')


def suruslar_yaz(yol, suruslar):
    with open(yol, 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.writer(f, delimiter=';')
        w.writerow(['Kayit', 'Baslangic', 'Sure_s', 'Yol_m', 'Medyan_Hiz_kmh', 'Medyan_Dikey_RMS', 'Darbe', 'Uygulama_Uyarisi',
                    'Scooter', 'Hava_Durumu'])
        for k in suruslar:
            w.writerow([k['ad'], k['baslangic'], f'{k["sure"]:.0f}', f'{k["yol_m"]:.0f}', sa.tr(k['hiz'], 1), sa.tr(k['rms'], 3),
                        k['darbe'], k['uyari'], k['etiket'].get('scooter', ''), k['etiket'].get('hava', '')])


def darbeler_yaz(yol, noktalar):
    with open(yol, 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.writer(f, delimiter=';')
        w.writerow(['Nokta', 'Enlem', 'Boylam', 'Belirsizlik_m', 'Surus_Sayisi', 'Gecis', 'En_Buyuk_Tepe', 'Suruslar', 'Google_Maps'])
        for n, k in enumerate(noktalar, 1):
            w.writerow([n, sa.tr(k['enlem'], 6), sa.tr(k['boylam'], 6), sa.tr(k['belirsizlik_m'], 1), k['surus_sayisi'],
                        len(k['olaylar']), sa.tr(k['en_buyuk'], 1), ', '.join(sorted({o['surus'] for o in k['olaylar']})),
                        sa.maps_link(k['enlem'], k['boylam'])])


def hucre_degeri(h):
    return h['indeks'] if h['indeks'] is not None else h['rms']


def geojson_yaz(yol, hucreler):
    ozellikler = []
    for h in hucreler:
        (g, b), (k, d) = h['sinir']
        ozellikler.append({'type': 'Feature',
                           'geometry': {'type': 'Polygon', 'coordinates': [[[b, g], [d, g], [d, k], [b, k], [b, g]]]},
                           'properties': {'satir': h['n'], 'surus_sayisi': len(h['suruslar']), 'sokak': h['sokak'],
                                          'medyan_hiz_kmh': round(h['hiz'], 2), 'medyan_dikey_rms': round(h['rms'], 3),
                                          'indeks': round(h['indeks'], 3) if h['indeks'] is not None else None,
                                          'darbe': h['darbe']}})
    with open(yol, 'w', encoding='utf-8') as f:
        json.dump({'type': 'FeatureCollection', 'features': ozellikler}, f, ensure_ascii=False)


def harita_yaz(yol, hucreler, noktalar, b):
    deger_adi = f'İndeks ({sa.HIZ_REF:.0f} km/h\'te beklenen Dikey_RMS)' if b is not None else 'Medyan Dikey_RMS'
    kutular = [dict(s=h['sinir'], r=sa.renk(hucre_degeri(h)), o=.8 if len(h['suruslar']) >= 2 else .5,
                    i=(f"{html.escape(h['sokak'])}<br>{len(h['suruslar'])} sürüş, {h['n']} satır<br>"
                       f"hız {sa.tr(h['hiz'], 1)} km/h · RMS {sa.tr(h['rms'])} m/s²"
                       + (f" · indeks {sa.tr(h['indeks'])}" if h['indeks'] is not None else '')
                       + (f"<br>{h['darbe']} darbe" if h['darbe'] else ''))) for h in hucreler]
    darbeler = [dict(e=k['enlem'], b=k['boylam'], no=str(n), s=k['surus_sayisi'],
                     h=(f"<b>Darbe noktası {n}</b><br>{k['surus_sayisi']} sürüş, {len(k['olaylar'])} geçiş<br>"
                        f"en büyük tepe {sa.tr(k['en_buyuk'], 0)} m/s²<br>{k['enlem']:.6f}, {k['boylam']:.6f} ±{k['belirsizlik_m']:.0f} m<br>"
                        f"<a href='{sa.maps_link(k['enlem'], k['boylam'])}' target='_blank'>Google Haritalar'da aç</a>"))
                for n, k in enumerate(noktalar, 1)]
    veri = json.dumps(dict(kutular=kutular, darbeler=darbeler), ensure_ascii=False)
    sayfa = f"""<!doctype html>
<html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Yol kalitesi haritası</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>
  html, body {{ margin: 0; height: 100%; font-family: system-ui, sans-serif; background: #fcfcfb; }}
  #harita {{ position: absolute; inset: 0; }}
  .kutu {{ background: rgba(252,252,251,.94); padding: 8px 10px; border-radius: 6px; font-size: 12px; color: #0b0b0b; line-height: 1.5; max-width: 280px; }}
  .kutu b {{ font-size: 13px; }}
  .serit {{ display: flex; height: 14px; margin: 4px 0 2px; }} .serit span {{ flex: 1; }}
  .uclar {{ display: flex; justify-content: space-between; color: #52514e; }}
  .no {{ background: {sa.MOR}; color: #fff; border: 2px solid #fff; border-radius: 50%; font: bold 11px/18px system-ui, sans-serif;
         text-align: center; box-shadow: 0 1px 3px rgba(0,0,0,.45); }}
  .no.tek {{ opacity: .55; }}
</style></head><body><div id="harita"></div>
<script>
const V = {veri};
const harita = L.map('harita', {{ maxZoom: 21 }});
const sade = L.tileLayer('https://{{s}}.basemaps.cartocdn.com/light_all/{{z}}/{{x}}/{{y}}{{r}}.png',
  {{ subdomains: 'abcd', maxNativeZoom: 20, maxZoom: 21, attribution: '&copy; OpenStreetMap katkıcıları &copy; CARTO' }}).addTo(harita);
const renkli = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{{z}}/{{y}}/{{x}}',
  {{ maxNativeZoom: 19, maxZoom: 21, attribution: 'Esri, HERE, Garmin, &copy; OpenStreetMap katkıcıları' }});
const uydu = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{{z}}/{{y}}/{{x}}',
  {{ maxNativeZoom: 19, maxZoom: 21, attribution: 'Uydu: Esri, Maxar, Earthstar Geographics' }});
const hucre = L.layerGroup().addTo(harita), darbe = L.layerGroup().addTo(harita), sinir = [];
for (const k of V.kutular) {{
  L.rectangle(k.s, {{ color: '#0b0b0b', weight: .5, opacity: .3, fillColor: k.r, fillOpacity: k.o }}).bindTooltip(k.i).addTo(hucre);
  sinir.push(...k.s);
}}
for (const d of V.darbeler)
  L.marker([d.e, d.b], {{ icon: L.divIcon({{ className: d.s >= 2 ? 'no' : 'no tek', html: d.no, iconSize: [22, 22] }}) }}).bindPopup(d.h).addTo(darbe);
harita.fitBounds(sinir.length ? sinir : [[0, 0]], {{ padding: [30, 30] }});
L.control.layers({{ 'Sokak haritası (sade)': sade, 'Sokak haritası (renkli)': renkli, 'Uydu görüntüsü': uydu }},
  {{ 'Yol kalitesi (25 m hücre)': hucre, 'Darbe noktaları': darbe }}).addTo(harita);
L.control.scale({{ imperial: false }}).addTo(harita);
const aciklama = L.control({{ position: 'bottomleft' }});
aciklama.onAdd = () => {{
  const k = L.DomUtil.create('div', 'kutu');
  k.innerHTML = `<b>Yol kalitesi</b><br>{html.escape(deger_adi)} (m/s²)
    <div class="serit">{''.join(f'<span style="background:{c}"></span>' for c in sa.RENKLER)}</div>
    <div class="uclar"><span>0</span>{''.join(f'<span>{s}</span>' for s in sa.SINIRLAR)}<span>+</span></div>
    yeşil: düzgün, sarı: orta, kırmızı: bozuk<br>Soluk hücre / işaret: yalnızca tek sürüşte geçildi<br>
    Mor: darbe noktası (dokunun: kaç sürüşte görüldüğü)`;
  return k;
}};
aciklama.addTo(harita);
</script></body></html>
"""
    with open(yol, 'w', encoding='utf-8') as f:
        f.write(sayfa)


def main():
    p = sa.ayristirici()
    p.description = 'Birden fazla sürüşü birleştirerek yol kalitesi analizi.'
    p.add_argument('--tek-tek', action='store_true', help='Her sürüşün ayrı analiz klasörünü de yaz')
    ayar = p.parse_args()
    dosyalar = sa.dosyalari_bul(ayar.csv)
    if not dosyalar:
        p.error('CSV dosyası bulunamadı (dosya adları veya kayıtların bulunduğu klasör verin)')
    cikti = ayar.cikti or os.path.join(os.getcwd(), 'birlesik_analiz')
    os.makedirs(cikti, exist_ok=True)

    # Yol verisi bir kez, tüm sürüşleri kapsayacak şekilde indirilir
    tum_olcumler = []
    for yol in dosyalar:
        tum_olcumler += sa.gps_olcumleri(sa.oku(yol))
    osm, osm_kaynak = sa.osm_yukle(tum_olcumler, ayar, os.path.join(cikti, 'birlesik_osm.json'))
    if osm is not None and not ayar.osm:
        ayar.osm = os.path.join(cikti, 'birlesik_osm.json')
    elif osm is None:
        ayar.oturtma = 'kapali'  # indirilemediyse her sürüşte yeniden denenmesin

    suruslar, hareket, olaylar = [], [], []
    for yol in dosyalar:
        ad = os.path.splitext(os.path.basename(yol))[0]
        print(yol)
        ayar.cikti = None
        r = sa.dosya_analiz(yol, ayar, klasor=os.path.join(cikti, ad) if ayar.tek_tek else None, yaz=ayar.tek_tek)
        for s in r['satirlar']:
            s['surus'] = ad
        hareket += r['hareket']
        olaylar += r['olaylar']
        st_ = r['satirlar']
        suruslar.append(dict(
            ad=ad, baslangic=st_[0]['zaman_metin'][:19], sure=st_[-1]['t'] - st_[0]['t'] + 0.5,
            yol_m=sum(s['d_hiz'] / 3.6 * 0.5 for s in r['hareket']),
            hiz=st.median(s['d_hiz'] for s in r['hareket']) if r['hareket'] else 0.0,
            rms=st.median(s['rms'] for s in r['hareket']) if r['hareket'] else 0.0,
            darbe=len(r['olaylar']), uyari=sum(1 for s in st_ if s['uyg_cukur']), etiket=r['etiket']))
        print(f'  {len(r["hareket"])} hareket satırı, {len(r["olaylar"])} darbe')

    b = sa.hiz_ussu(hareket)
    sokaklar = sa.sokak_tablosu(hareket, olaylar, b)
    hucreler = hucre_tablosu(hareket, olaylar, b)
    noktalar = sa.kumele(olaylar, ayar.kume_yaricap)
    for k in noktalar:
        k['surus_sayisi'] = len({o['surus'] for o in k['olaylar']})
    noktalar.sort(key=lambda k: (-k['surus_sayisi'], -len(k['olaylar']), -k['en_buyuk']))

    def yol_(son):
        return os.path.join(cikti, f'birlesik_{son}')
    ozet_yaz(yol_('ozet.txt'), suruslar, sokaklar, hucreler, noktalar, b, osm_kaynak)
    sa.sokaklar_yaz(yol_('sokaklar.csv'), sokaklar, surus_sayisi=True)
    suruslar_yaz(yol_('suruslar.csv'), suruslar)
    darbeler_yaz(yol_('darbeler.csv'), noktalar)
    geojson_yaz(yol_('hucreler.geojson'), hucreler)
    harita_yaz(yol_('harita.html'), hucreler, noktalar, b)
    print(f'{len(dosyalar)} sürüş birleştirildi -> {cikti}')
    print(f'  {len(sokaklar)} sokak, {len(hucreler)} hücre, {sum(1 for k in noktalar if k["surus_sayisi"] >= 2)} tekrar eden darbe noktası')


if __name__ == '__main__':
    main()
