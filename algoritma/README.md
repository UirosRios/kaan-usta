# Claude'un algoritması ve karşılaştırma

Bu klasör, telefonun ham dosyasından (`*_ham.gpkg`) Claude'un çukur noktalarını ve kesit puanlarını üretir
(`*_claude.gpkg`) ve bunları sürücünün işaret ve puanlarıyla (`*_insan.gpkg`) karşılaştırır. Yalnızca Python'un standart
kütüphanesi kullanılır (Python 3.9+; Windows'ta düz Python ile de çalışır).

**Durum (27 Kasım 2026):** altyapı hazır, algoritma **yer tutucu** (sürüm `0-altyapi`). Çukur kuralı ve puan formülü
eski sürümden ve örnek dosyadan alındı; hiçbir değer gerçek geliştirme verisiyle ayarlanmadı. Gerçek algoritma
geliştirme sürüşleri gelince kurulur ve yeni sürüm adı alır.

## Hocanın düzeni

1. **Geliştirme:** 5-6 sokak sürülür; ham ve insan dosyaları birlikte `veri/gelistirme/<gün>/` klasörüne konur.
   Algoritma bunlarla kurulup ayarlanır, sonra sürüm adıyla dondurulur.
2. **Test:** başka sokaklar. `veri/test/<gün>/` klasörüne önce **yalnızca ham dosya** konur. Claude dosyası üretilip
   GitHub'a gönderilir (mühür). İnsan dosyası ancak bundan sonra eklenir.
3. **Karşılaştırma:** Claude noktası ile sürücünün işareti arasındaki mesafe eşiğin altındaysa "doğru" sayılır. Eşiği
   kullanıcı ve arkadaşı geliştirme sürüşlerinden sonra, GPS doğruluğuna bakarak belirler ve `veri/test/esik.json`'a
   yazar (testten önce GitHub'a).

## Komutlar

```bash
python3 algoritma/uret.py veri/gelistirme            # klasördeki her *_ham.gpkg için *_claude.gpkg
python3 algoritma/karsilastir.py veri/gelistirme     # rapor + her gün için *_karsilastirma.gpkg
python3 algoritma/karsilastir.py veri/gelistirme --esik 6
python3 -m unittest discover -s algoritma/testler    # sınamalar
```

`uret.py` her dosya için bir içerik özeti (SHA-256) yazdırır: aynı ham dosya her zaman aynı özeti verir.

## Kurallar

- **Bağımsızlık:** `uret.py` yalnızca ham dosyayı okur. Adında `_insan` geçen ya da içinde `insan_` katmanı bulunan
  dosyayı reddeder. İnsan dosyasını yalnızca `karsilastir.py` okur.
- **Konum:** İki nokta da aynı ham GPS izine aynı kuralla konur: t_s anına iki GPS noktası arasında doğrusal ara değer
  (`ortak.konum_at`, uygulamadaki `konumAt` ile aynı).
  - Claude noktası darbe anında, sürücünün noktası basış anındadır.
  - GPS gecikmesi hiçbir tarafa uygulanmaz. Aynı izde iki tarafa aynı kaydırma uygulamak mesafeyi değiştirmez; yalnızca
    insan noktasını telefonun yazdığı yerden uzaklaştırırdı.
  - `karsilastir.py`, dosyalardaki konumların bu kurala 1 cm içinde uyduğunu denetler, uymazsa durur. Böylece QGIS'te
    elle ölçülen mesafe rapordakiyle aynı olur.
- **Haritaya oturtma kullanılmaz** (karar 27 Kasım): bir tarafı sokağa çekmek mesafeye GPS'in yan sapmasını (1-6 m) ekler.
- **Eşleştirme:** aynı kayıt içinde, bire bir, en yakın çift önce, mesafe ≤ eşik.
  - Doğru: eşleşen işaret. Kaçırılan: eşleşmeyen işaret. Fazladan: eşleşmeyen Claude noktası.
  - Duyarlılık = doğru / işaret. Kesinlik = doğru / Claude noktası.
  - Ek tablo 5, 10 ve 15 m eşikleri için verilir.
- **Dışlananlar:** ekran ve telefon tuşu işaretleri basışta telefonu sarsar; algoritma basışın kendisini "çukur" diye
  bulabilir. Bu yüzden bu işaretler ve onlara 1 sn'den yakın Claude noktaları sayılmaz; sayıları raporlanır.
  Kumanda ve kulaklık işaretleri sayılır.
- **Eksik kayıt hatadır:** ham ve insan dosyalarındaki kayıtlar aynı olmalı; eksik kayıt sıfır sayılmaz.
- **Ne ölçülüyor:** işaret ve Claude noktası aynı GPS izinden konum aldığı için GPS'in kendi hatası büyük ölçüde sadeleşir.
  Mesafeyi çoğunlukla basış gecikmesi × hız belirler (ör. 0,5 sn × 15 km/h ≈ 2 m). Rapordaki "Eşik kararı için" bölümü
  GPS doğruluğunu, işaretlerin en yakın Claude noktasına uzaklığını ve zaman farklarını yan yana verir.

## Test verisi bekçileri (`veri/test/`)

- `uret.py` "0-" (yer tutucu) sürümle yazmaz ve var olan bir Claude dosyasının üstüne yazmaz.
- `karsilastir.py`:
  - Claude dosyası `origin/main`'dekiyle birebir aynı değilse durur (önce commit + push).
  - Eşiği komut satırından almaz; `veri/test/esik.json` dosyasından alır (`{"esik_m": 6}`). Bu dosya da
    `origin/main`'de olmalı.
  - "0-" sürümü kabul etmez.
  - Test ve geliştirme günlerini aynı raporda karıştırmaz.
- Onaylı örnek klasörüne (`qgis/`) yazılmaz; örnekler `qgis/ornek_uret.py` ile üretilir.

## Karşılaştırma dosyası (`*_karsilastirma.gpkg`; biçim onaylandı, 27 Kasım)

Örnek: `qgis/ornek/ornek_20261120_karsilastirma.gpkg`.

| Katman | Geometri | İçerik |
|---|---|---|
| `eslesmeler` | çizgi (işaret → Claude noktası) | esik_m, kayit_no, kesit, kesit_adi, insan_t_s, claude_t_s, fark_s, mesafe_m, kaynak |
| `eslesmeyenler` | nokta | esik_m, kayit_no, kesit, kesit_adi, taraf (insan / claude), sonuc (kacirilan / fazladan), t_s, en_yakin_m, kaynak |
| `dislananlar` | nokta | kayit_no, taraf, t_s, kaynak, neden |
| `ozet` | tablo | esik_m, isaret, claude, dogru, kacirilan, fazladan, duyarlilik, kesinlik |
| `aciklamalar` | tablo | veri sözlüğü |

Her eşik için ayrı satırlar vardır. QGIS'te katmana sağ tık → Süz (Filter) → `"esik_m" = 10`. Henüz QGIS stili yok
(varsayılan görünüm).

## Dosyalar

- `ortak.py`: GeoPackage okuma, `konum_at`, `dikey_sarsinti` (uygulamadakiyle aynı), mesafe, saat, yüzdelik.
- `okuma.py`: ham, insan ve Claude dosyalarını okur (alanlar adıyla; 2.0 dosyalarındaki fazla alanlar yok sayılır).
- `tespit.py`: algoritma (sürüm adı, parametreler, `hesapla`).
- `uret.py`, `karsilastir.py`: komutlar.
- `testler/`: sınamalar. `testler/veri/dart21_*` uygulamanın (Dart, 2.1) yazdığı yapay bir gün (`test/donusturucu_test.dart`,
  "çeviri" testi; boyut için jiroskop satırları silindi): konum kuralının Dart ile Python'da aynı olduğunu sınar.
- Katman alanları ve veri sözlüğü: `qgis/sozluk.py` (örnek üreticiyle ortak).
