# Mikromobilite Veri Aracı (Kaan Usta – YTÜ Harita Mühendisliği Tezi)

E-scooter / bisiklet sürüşünde telefonun **ham sensör ve GPS verisini** toplayan Android uygulaması (sürüm 2).
Sürücü sürüş sırasında çukurları işaretler, her kesitin sonunda konfor puanı verir. Veriler QGIS'te katman katman
incelenmek üzere **GeoPackage** (`.gpkg`) dosyalarına yazılır.

Tez düzeni: Claude yalnızca ham veriden kendi algoritmasıyla çukur noktaları ve konfor puanları üretir; sürücünün
işaret ve puanlarıyla QGIS'te karşılaştırılır. Dosya biçimi ve QGIS kullanımı: [qgis/README.md](qgis/README.md).

## APK'yı indirme

1. GitHub'da depo → **Actions** sekmesi → en son başarılı **"APK Derle"** çalıştırması.
2. Sayfanın altındaki **Artifacts** bölümünden `mikromobilite-apk` dosyasını indirin (zip içinde `app-release.apk`).
3. APK'yı telefona atıp açın ("Bilinmeyen kaynaklardan yükleme" izni istenir).

Bütün derlemeler depodaki sabit anahtarla (`android/app/kaan_usta.jks`) imzalanır: yeni sürüm eskisinin üstüne kurulur,
kayıtlar silinmez. Bu anahtardan önceki bir derleme (35 ve öncesi) kuruluysa bir kez kaldırıp kurmak gerekir; kaldırmak
uygulamanın kendi klasöründeki kayıtları siler (Belgeler/Mikromobilite kopyaları kalır).

## Sürüş: bir kayıt = bir kesit = bir puan

1. Kesitin başında durun, **BAŞLAT**'a basın, ~5 sn bekleyip sürün.
2. Ani sarsıntı veren her şeyde (çukur, kasis, ray, rögar, kot farkı) **kulaklık veya Bluetooth kumanda tuşuna** basın
   (kısa çift bip). Arnavut kaldırımı gibi sürekli pürüzlü zeminde yalnızca zeminden belirgin ayrılan sarsıntılara basın.
   Ekrandaki ÇUKUR butonu ve telefonun ses tuşu yedektir: telefonu sarsarlar. 1 sn içindeki ikinci basış sayılmaz.
3. Kesitin sonunda durun, ~5 sn bekleyip **DURDUR**'a basılı tutun.
4. Açılan ekranda kesitin konforunu puanlayın: **1 çok sarsıntılı – 5 çok rahat** veya "Hatırlamıyorum" (geçilemez;
   sonradan Kayıtlar'dan değiştirilebilir). Ölçülen sarsıntı gösterilmez.

- Kesit boyunca zemin tek tip olmalı; değişiyorsa orada durup yeni kayıt başlatın. Her geçişte aynı noktalarda başlayıp bitirin.
- **Kesit kodu** (K01, K02, ...) otomatik verilir: başlangıç ve bitiş noktası önceki bir kayıtla ~30 m içinde örtüşen kayıt
  aynı kesittir (ters yönde örtüşürse "dönüş"). Kesite **Kayıtlar** sayfasında ad verilebilir; ad o kesitin bütün
  kayıtlarına ve sonraki geçişlerine uygulanır.
- Kayıt sırasında ekranda dikey sarsıntı, hız ve harita görünür (yalnızca gösterim). Ekran kapanırsa veya başka uygulamaya
  geçilirse kayıt arka planda sürer. Kayıt sırasında geri tuşu uygulamayı kapatmaz.

## Kaydedilen ham veri

Bütün sensörler ve basışlar Android tarafında aynı saatle (`elapsedRealtimeNanos`) zaman damgalanır; telefonda süzgeç uygulanmaz.

| Kaynak | Ne kaydedilir |
|---|---|
| İvmeölçer | Üç eksen, m/s², yerçekimi dahil; 200 Hz istenir, telefon desteklediği hızı verir (Samsung M21: 125 Hz) |
| Jiroskop | Üç eksen, rad/s, ivmeölçerle aynı hızda |
| GNSS (GPS_PROVIDER) | Her konum: enlem, boylam, yükseklik, Doppler hızı, yön, doğruluk, hız / yükseklik doğruluğu, kullanılan uydu sayısı |
| Çukur basışları | An ve kaynak (`kulaklik` / `kumanda` / `ekran` / `tus`) |
| Kayıt bilgisi | Telefon ve sensör adları, gerçek örnekleme hızı, scooter (Ayarlar), hava durumu (Open-Meteo), uygulama sürümü |

Kayıt sırasında veri saniyede bir diske yazılır (uygulama çökerse en fazla son ~1 sn kaybolur; yarım kalan kayıt bir sonraki
açılışta kurtarılır). DURDUR'dan sonra o günün GeoPackage dosyalarına eklenir.

## Dosyalar

Her sürüş günü iki dosya (uygulamanın klasöründe ve telefonun **Belgeler/Mikromobilite** klasöründe):

| Dosya | İçerik | Kime |
|---|---|---|
| `mikromobilite_<gün>_ham.gpkg` | `kayitlar` (güzergâh çizgisi), `gps_noktalari` (+ dikey sarsıntı özeti), `ivme`, `jiroskop` | Claude'a gönderilir |
| `mikromobilite_<gün>_insan.gpkg` | `insan_cukurlar` (basışlar), `insan_puanlar` (kesit puanları) | Sürücüde kalır |

QGIS'e sürüklenince katmanlar hazır görünümle açılır; her dosyada alanları açıklayan `aciklamalar` tablosu vardır.
Ayrıntı: [qgis/README.md](qgis/README.md).

**Kayıtlar** sayfası (başlıktaki klasör simgesi): günlere göre kayıtlar; "Ham dosyayı gönder", "İşaret/puan dosyası",
kayda dokununca harita (güzergâh ve işaretler), üç nokta menüsünden kesit adı, puan, silme.

## Ayarlar

- **Scooter**: bir kez yazılır, her kayda eklenir.
- **Test sürüşü (sanal GPS)**: konum YTÜ Davutpaşa Yerleşkesi iç yollarında ~1,85 km'lik bir turda üretilir (başa dönünce
  6 sn durup yeni tura başlar, hız 4-20 km/h); sarsıntı gerçek ivmeölçerden. Kayıt akışını evde prova etmek içindir.
  Test kayıtları ayrı dosyalara (`test_mikromobilite_<gün>_...`) yazılır ve Kayıtlar'da TEST diye ayrı görünür.
  Tez verisi için kapalı tutun.

## Montaj

Telefon araca sıkıca sabitlenmelidir; açısı önemli değildir. Gevşek tutucu veya cep / çanta ölçümü bozar.
Samsung telefonlarda uygulamanın pil ayarı "Kısıtlanmamış" olmalıdır.

## Eski (v1) kayıtlar ve analiz betikleri

Sürüm 1.x, 0,5 sn'lik özet satırlar içeren CSV dosyaları (`mikromobilite_<tarih_saat>.csv`, `_bilgi.txt`, `_puan.csv`)
üretiyordu. Bu kayıtlar telefonda olduğu gibi durur: Kayıtlar sayfasında sağ üstteki saat simgesi (**Eski kayıtlar**)
ile açılır, paylaşılır, önizlenir. `analiz/` klasöründeki betikler bu v1 biçimini okur
([analiz/README.md](analiz/README.md)); yeni ham biçim için karşılaştırma aşamasında yeniden ele alınacak.
