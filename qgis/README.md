# QGIS için veri dosyaları (GeoPackage)

Uygulama 2.0 her sürüş günü için **GeoPackage** (`.gpkg`) dosyaları üretecek. GeoPackage QGIS'in kendi önerdiği
biçimdir: tek dosyanın içinde birden çok katman ve her katmanın öznitelik tablosu bulunur. Ek program gerekmez.

`ornek/` klasöründeki dosyalar **yapay örnektir** (gerçek sürüş değildir). Biçimi onaylamak için üretildiler.
Uygulama henüz bu biçimi yazmıyor; biçim onaylanınca uygulamaya eklenecek.

## Üç dosya: kim üretir, kime gider

| Dosya | Üreten | İçerik | Kime |
|---|---|---|---|
| `<gün>_ham.gpkg` | Telefon | Güzergâh, GPS noktaları + sarsıntı özeti, ham ivme ve jiroskop | Claude'a verilir |
| `<gün>_insan.gpkg` | Telefon | Sürücünün çukur işaretleri ve kesit puanları | Sürücüde kalır |
| `<gün>_claude.gpkg` | Claude | Claude'un çukur noktaları ve kesit puanları | Herkese |

İşaret ve puanlar ayrı dosyada durur. Böylece Claude'un sonuçları yalnızca sensör verisinden üretilir.
**Kural:** Claude bir günün `_insan.gpkg` dosyasını, o günün `_claude.gpkg` dosyası GitHub'a gönderilmeden açmaz.

Katman adları dosyalar arasında çakışmaz (`insan_...`, `claude_...`). Üç dosya aynı anda QGIS'e eklenebilir.

## Katmanlar

Her dosyanın içinde bir de **`aciklamalar`** tablosu (ve QGIS'in stil tablosu `layer_styles`) bulunur. Bu tablo veri sözlüğüdür ve her alanın anlamını ve
birimini verir.

**`_ham.gpkg`**

| Katman | Geometri | Öznitelikler |
|---|---|---|
| `kayitlar` | Çizgi (her kayıt = bir kesitin bir geçişi) | kayit_no, kesit, yon, baslangic, bitis, sure_s, uzunluk_m, ort_hiz_kmh, gps_nokta, ivme_hz, jiro_hz, cihaz, sensörler, scooter, hava, veri_kaynagi, uygulama_surumu |
| `gps_noktalari` | Nokta (her GPS konumu, ~1 sn) | kayit_no, kesit, t_s, zaman, hiz_kmh, yon_derece, dogruluk_m, yukseklik_m, uydu, **dikey_rms**, **dikey_tepe**, ivme_ornek |
| `ivme` | Yok (tablo, ~200 Hz) | kayit_no, t_s, x, y, z (m/s², yerçekimi dahil) |
| `jiroskop` | Yok (tablo, ~200 Hz) | kayit_no, t_s, x, y, z (rad/s) |

**`_insan.gpkg`**: `insan_cukurlar` (nokta: kayit_no, kesit, t_s, zaman, hiz_kmh, kaynak) ve `insan_puanlar`
(çizgi: kayit_no, kesit, puan, durum, puanlama_zamani, isaret_sayisi).

**`_claude.gpkg`**: `claude_cukurlar` (nokta: kayit_no, kesit, t_s, zaman, hiz_kmh, guven, tepe_ms2, algoritma) ve
`claude_puanlar` (çizgi: kayit_no, kesit, puan, puan_ondalik, indeks_ms2, algoritma).

İnsan ve Claude katmanları aynı alan adlarını ve anahtarları kullanır, böylece yan yana konabilir.

## Hazır görünüm (stiller)

Dosyalar, kullanıcının QGIS'te hazırladığı görünümü içinde taşır (`layer_styles` tablosu; QGIS'in kendi varsayılan stil
yeri). Katman QGIS'e eklenince bu görünüm kendiliğinden gelir:
- `gps_noktalari`: Blues, `dikey_rms`'e göre 5 sınıf; koyu = sarsıntılı.
- `insan_cukurlar`: kırmızı üçgen.
- `claude_cukurlar`: gölgeli koyu kırmızı yıldız.

Renk yerine biçim farkı kullanıldığı için renk ayırt etmede zorlananlar için de okunur.

Stiller `stiller/*.qml` dosyalarındadır. QGIS'te görünüm değiştirilince proje (.qgz) kaydedilip
`python qgis/stil_cikar.py proje.qgz` ile yeniden çıkarılır. Projeden yalnızca görünüm alınır; yazar adı, dosya
yolları ve birleştirmeler alınmaz. Dereceli sınıflarda en alt sınıf 0'dan başlatılır, en üst sınıf "ve üstü" olarak
açık bırakılır; böylece örnek verideki aralığın dışında kalan gerçek değerler haritadan kaybolmaz.

## Ortak anahtarlar ve bilinmesi gerekenler

- **`kayit_no`**: Kaydın kimliğidir (başlangıcın yerel tarih-saati). Bütün katmanlarda aynıdır ve birleştirme bununla yapılır.
- **`kesit`**: Telefon otomatik olarak verir. Başlangıç ve bitiş noktası daha önceki bir kayıtla ~30 m içinde örtüşen
  kayıtlar aynı kesit sayılır; ters yön de dahildir. Yanlış atanırsa QGIS'te düzeltilebilir. Sokak adı telefonda
  çevrimdışı bulunamadığı için analizde eklenecek.
- **`t_s`**: Kayıt başından (BAŞLAT) itibaren geçen saniyedir. Sensörler, GPS ve basışlar aynı saatle ölçülür.
  **İnsan ve Claude çukurlarını zamanla eşleştirin, mesafeyle değil.**
  - Claude'un noktası darbe anındadır.
  - Sürücünün basışı darbeden ~1-2 sn sonradır ve konumu basış anındaki ham GPS konumudur. Bu yüzden insan noktası
    çukurun birkaç metre ilerisine düşebilir.
- **Konumlar ham GPS'tir** ve WGS84 (EPSG:4326) koordinat sistemindedir. GPS konumu gerçek konumun yaklaşık 1 sn
  gerisindedir. QGIS, katmanları proje koordinat sistemine (ör. TUREF/TM30, EPSG:5254) kendisi dönüştürür.
- **Zaman alanları** GeoPackage kuralı gereği UTC'dir. QGIS'te İstanbul saatinden 3 saat geri görünürler. Okunabilir
  yerel saat `yerel_saat` alanındadır.
- **`dikey_rms`** ve **`dikey_tepe`**, önceki GPS konumundan bu konuma kadarki ivme örneklerinden hesaplanır.
  - Yöntem: 0,4 Hz yüksek geçiren süzgeç uygulanır, sonra titreşimin yerçekimi yönündeki bileşeni alınır. Böylece değer
    telefonun takılma açısına bağlı olmaz.
  - Haritada renklendirmek için konmuştur. Ham değerler `ivme` tablosunda durur.

## QGIS'te açma

Örnek dosyalar QGIS'te (Windows) açıldı ve katmanlar doğru yerde göründü (kullanıcı, 25 Kasım 2026). Aşağıdaki
adımların hepsi henüz denenmedi.

1. `.gpkg` dosyalarını QGIS penceresine sürükleyin. QGIS hangi katmanların ekleneceğini sorar; hepsini seçin.
2. **Koordinat sistemi:** Sağ alttaki `EPSG:4326` yazısına tıklayın, `5254` arayın, **TUREF / TM30** seçin. Harita
   metre cinsinden ve gerilmeden görünür.
3. **Altlık:** Tarayıcı (Browser) panelinde XYZ Tiles → OpenStreetMap.
4. **Öznitelik tablosu:** Katmana sağ tıklayın → Öznitelik Tablosunu Aç (Open Attribute Table).
5. **Sarsıntıya göre renk:** `gps_noktalari` → Özellikler → Simgeleme (Symbology) → Dereceli (Graduated) →
   Değer: `dikey_rms`.
6. **Puanları yan yana koyma:** `claude_puanlar` → Özellikler → Birleştirmeler (Joins) → + → katman `insan_puanlar`,
   alan `kayit_no` ↔ `kayit_no`.
7. **Sürüşü zamanla oynatma:** `gps_noktalari` → Özellikler → Zamansal (Temporal) → tarih-saat içeren tek alan:
   `zaman`. Ardından Görünüm → Paneller → Zaman Denetleyicisi (Temporal Controller).
8. **Çukur eşleştirme örneği:** Katman → Katman Ekle → Sanal Katman (Virtual Layer). Aşağıdaki sorgu, Claude'un
   darbesinden sonraki 0-5 sn içinde gelen basışları eşleştirir:
   ```sql
   SELECT i.kayit_no, i.t_s AS insan_t_s, c.t_s AS claude_t_s, i.t_s - c.t_s AS fark_s, c.guven, c.geometry
   FROM insan_cukurlar i JOIN claude_cukurlar c
     ON i.kayit_no = c.kayit_no AND i.t_s - c.t_s BETWEEN 0 AND 5
   ```

## Dosya boyutu

`_ham.gpkg`, kayıt süresinin dakikası başına yaklaşık **1,5 MB** tutar; bunun neredeyse tamamı 200 Hz'lik ivme ve
jiroskop tablolarıdır. 40 dakikalık bir sürüş günü yaklaşık 60 MB eder. `_insan` ve `_claude` dosyaları birkaç on KB'dir.

## Örnek dosyalar (`ornek/`)

Yapay bir gün, YTÜ Davutpaşa Yerleşkesi iç yollarında 3 kesit ve 5 kayıttan oluşur. Karşılaşılabilecek durumlar:
- **K01**: iyi asfalt, iki yönde geçiş. Dönüşte sürücü öteki şeritte, çukura denk gelmiyor.
- **K02**: parke, kasis ve ray. Yer tutucu hesap bunları kaçırıyor ve yanlış alarm veriyor; eşleşmeyen noktalar
  böyle görünür.
- **K03**: yamalı asfalt. Gidişte puan "Hatırlamıyorum" (boş), dönüşte hiç işaret yok.
- Her kaydın başında ve sonunda ~5 sn duruş ve BAŞLAT/DURDUR dokunuşu vardır.

`claude_*` katmanları **yer tutucudur**; algoritma henüz yazılmadı ve basit bir hesapla dolduruldu. Yeniden üretmek için:
`python qgis/ornek_uret.py`. Aynı kod her seferinde aynı dosyaları verir. Yazıcı `gpkg.py`, yalnızca Python'un
standart kütüphanesini kullanır.
