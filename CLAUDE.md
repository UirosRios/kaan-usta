# KAAN USTA – Mikromobilite Veri Aracı (YTÜ Harita Mühendisliği tezi)

Scooter / bisiklet sürüşünde telefonun GPS'i ve ivmeölçeriyle hıza göre dikey sarsıntıyı ölçen sistem.
Tezin sahibi kullanıcının arkadaşı (YTÜ Harita Mühendisliği); kullanıcı geliştirmeye yardım ediyor ve sürüşleri kendisi yapıyor.
Bu dosya oturumlar arası kalıcı hafızadır: bulut oturumu her seferinde sıfırdan kurulur, `~/.claude` altındaki notlar kaybolur.
Önemli bir karar veya durum değişince burayı güncelle.

## Kullanıcı ve çalışma tercihleri

- Kullanıcıyla **Türkçe** konuşulur (unutulunca kullanıcı uyardı); kod, yorumlar, commit mesajları ve belgeler Türkçedir.
- Kullanıcı hekimdir (yazılımcı değil): açıklamalar sade, teknik ayrıntı gerektiği kadar.
- **"Bir sorun varsa önce sor, sonra yap."** Belirsiz / riskli / kapsam dışı değişikliklerde önce sor; açık istekleri doğrudan yap.
  Büyük işlerde önce plan sunulur, kullanıcı onaylayınca ("başla") uygulanır.
- Sonuçları dürüst raporla: telefonda denenmemiş özellikleri "denenmedi" diye belirt.
- Hocaya gösterilecek açıklamalar istendiğinde Artifact sayfası olarak hazırlandı (uygulama mantığı, oturtma, çıktılar).
- Örnek dosyaları / biçimleri **kullanıcı ve arkadaşı** onaylar (hoca değil).

## Tez tasarımı (24 Kasım 2026'da değişti)

Arkadaş ve danışman hocası tezi değiştirdi. Yeni düzen:
- **Uygulama ham veri toplayıcıdır.** Sürüş sırasında sürücü çukurları işaretler, her kaydın sonunda kesite 1-5 konfor puanı verir.
- **Claude**, yalnızca ham sensör + GPS verisinden kendi algoritmasıyla çukur noktaları ve kesit puanları üretir.
  **Arkadaş ve kullanıcı** kendi işaret ve puanlarını verir. İkisi **QGIS**'te katman katman (öznitelik tablolarıyla)
  karşılaştırılır (hocanın önerisi). Biçim GeoPackage; ayrıntı aşağıda.
- Amaç: algoritma çukurları ne kadar doğru / duyarlı / özgül buluyor, puanları insan puanına ne kadar yakın.
- **Bağımsızlık kuralı:** Claude bir sürüş gününün insan dosyasını (`*_insan.gpkg`: işaretler, puanlar) o günün Claude
  katmanları (`*_claude.gpkg`) GitHub'a gönderilmeden **açmaz, okumaz, analiz etmez**. Yanlışlıkla gelirse açmadan kenara
  koy ve kullanıcıya söyle. Algoritma bir test gününe bakılarak sonradan değiştirilmez (değişirse yeni sürüm, yeni test verisi).
  İstisna: **geliştirme seti** (kullanıcı izin verdi): ilk sürüşlerde her şey görülür, algoritma ve 1-5 çevirisi bunlarla kurulur.
  3 Kasım Kadıköy sürüşü geliştirme verisidir (eşikler onunla ayarlandı). **Test kesitleri geliştirme kesitlerinden ayrı sokaklar.**
- Algoritma sohbette verilen yorum değil, depodaki koddur: aynı girdiden hep aynı sonucu üretir.
- Gerçek sürüş güzergâhları ve verileri depoya konabilir (kullanıcı izni; depo herkese açık).
- Daha önce önerilen resmî "dondur + mühürle" protokolü (git etiketi, tahminler referanstan önce GitHub'da) ve istatistik
  planı şimdilik **park edildi**; resmî karşılaştırmaya geçilirse aşağıdaki "İleriki aşama" notundan yeniden kurulur.

### Sürüş protokolü (karar verildi)

- **Bir kayıt = bir kesit = bir puan.** Kesit boyunca zemin tek tip olmalı; zemin değişirse (asfalt → parke) orada durup yeni kayıt.
- Başta: kesit başında dur, BAŞLAT, ~5 sn bekle, sür. Sonda: kesit sonunda dur, ~5 sn bekle, DURDUR (son çukurun işareti
  ~1,3 sn sonra geldiği için; başlat/durdur dokunuşu duruşa denk gelsin). Her geçiş **aynı noktalarda** başlar ve biter.
- Puan DURDUR'dan hemen sonra verilir (1-5 veya "Hatırlamıyorum"; "Sonra" kalkacak).
- **Çukur tanımı:** ani sarsıntı hissi veren her şey (çukur, kasis, ray, rögar, kot farkı vb.). Arnavut kaldırımı gibi sürekli
  pürüzlü zeminde her taşa değil, yalnızca zeminden belirgin ayrılan sarsıntılara basılır.
- İşaret doğrulama sürüşlerinde **kulaklık / Bluetooth kumanda** ile verilir (ekran ve telefon tuşu telefonu sarsar;
  ekran butonu yedek, kaynağı kaydedilir).
- Kesitler önceden, **gözle** seçilir (ölçülen sarsıntıya bakmadan) ve tüm zemin türlerini kapsar (çok iyi asfalt … Arnavut
  kaldırımı, ray, kasis); tercihen > 150 m. Her kesit ≥ 3 geçiş (farklı gün / hız / iki yönlüyse iki yön). Hedef 20-25+ kesit.
- **Kesit kimliği otomatik:** başlangıç ve bitiş noktaları ~30 m içinde (ters yön dahil) ve güzergâhı büyük ölçüde (%80+)
  çakışan kayıtlar aynı kesit. Kodu (K01, K02 …) telefon verir (önerilen; örnek dosyada öyle), QGIS'te düzeltilebilir;
  sokak adı OSM'den analizde verilir (telefon çevrimdışı ad alamaz). Eşikler kesinleşmedi.

### Uygulama 2.0 planı (henüz yapılmadı; örnek GeoPackage onaylandı, uygulama planı kullanıcı onayı bekliyor)

- **Ham kayıt:** ivmeölçer 3 eksen ve **jiroskop** (kullanıcı istedi) ~200 Hz, her GPS_PROVIDER konumu (hız, yön, doğruluk,
  yükseklik, uydu sayısı), her basış; hepsi **aynı saatle** (sensör zaman damgası). Telefonda filtre yok (yalnızca nokta
  katmanındaki sarsıntı özeti; kullanıcı onayladı). Kayıt büyük olasılıkla Kotlin `KayitServisi`'ne taşınır
  (`sensors_plus` `event.timestamp`'ın donanım saati mi geliş saati mi olduğu kontrol edilmeli).
- **Çıktı:** her sürüş günü için GeoPackage, **yazarına göre ayrı dosyalar**: `*_ham.gpkg` (Claude'a gider) ve `*_insan.gpkg`
  (işaret + puan; sürücüde kalır). Claude `*_claude.gpkg` üretir. Ayrıntı: `qgis/README.md`.
- Kalkacaklar: otomatik çukur uyarısı modu ve `Cukur` sütunu, 0,5 sn özet CSV, her DURDUR'dan sonra açılan paylaşım ekranı,
  dönüşlere göre otomatik parçalama (`Parcalama`), puanlamadaki "Sonra", önizlemedeki sarsıntı renkleri. Yerine: gün sonunda
  tek "Günün kayıtlarını gönder".
- **Kayıt sırasında sarsıntı ve harita görünmeye devam eder** (kullanıcı istedi, 25 Kasım).
- **Kesit adı:** Kayıtlar sayfasında kesite ad verilebilir (`kesit_adi`; aynı kesitin bütün kayıtlarına uygulanır, sonraki
  kayıtlar da alır). Alan `kayitlar`, `insan_puanlar`, `claude_puanlar` katmanlarında (kullanıcı istedi, 25 Kasım).
- Kalacaklar: işaret yolları (kulaklık / kumanda / ses tuşu / ekran), test sürüşü (sanal GPS), Belgeler/Mikromobilite kopyası.
- **Uygulama 2.0 mühendislik kuralları** (kodlamadan önce karar verildi):
  - Test edilebilirlik mimariyi belirler: CI yalnızca Kotlin'in derlendiğini kanıtlar. GeoPackage yazımı, sarsıntı özeti ve kesit
    atama bu bulut oturumunda çalıştırılabilecek yerde (Dart, host'ta `flutter test`) olmalı; Kotlin yalnızca yakalama yapar
    (sensör, GPS, basış; hepsi `elapsedRealtimeNanos` saatiyle).
  - Altın kontrol: uygulamanın ürettiği dosya pyogrio ile okunur; katmanlar, alan adları ve türleri `qgis/ornek/` ile aynı olmalı.
  - Bağımlılıklar (SQLite paketi, `sensors_plus` zaman damgası) ezberden değil, güncel kaynak koduna bakılarak seçilir.
  - Çökme güvenliği: ham veri geldikçe diske yazılır; bir kaydın eklenmesi sırasında çökme, günün önceki kayıtlarını bozmamalı.
  - Test sürüşü yeni yoldan geçer, ayrı `test_` dosyalarına yazılır (kullanıcı evde prova edebilsin).
  - Gönder düğmesi varsayılan olarak yalnızca ham dosyayı paylaşır. v1 kayıtlarına dokunulmaz.
  - `lib/` veya `android/` içeren her `main` gönderimi yüklenebilir APK üretir: yalnızca `flutter analyze` temiz durumlar
    gönderilir, kullanıcıya hangi derleme numarasını kuracağı söylenir.
  - QML stilleri uygulamanın ürettiği dosyalara da gömülür (kullanıcı QGIS 4.2.3'te kendiliğinden uygulandığını doğruladı,
    25 Kasım; altlık ve birleştirme projede kalır, bu normal).
- Sıra: örnek GeoPackage onayı → uygulama 2.0 (`flutter analyze`, telefonda denenmedi) → deneme çıkışı (gerçek örnekleme hızı,
  ekran kapalıyken kulaklık, dosya boyutu, QGIS'te açılış) → geliştirme sürüşleri → algoritma → test sürüşleri.

### İleriki aşama: resmî karşılaştırma planı (park edildi)

- Konfor, birincil kesit düzeyi: insan puan ortalaması ↔ Claude kesit puanı (geçiş puanlarının ortalaması); ICC(A,1)
  (iki yönlü, mutlak uyum), Bland–Altman (kabul: uyum sınırları ±1 puan), Spearman + permütasyon. İkincil geçiş düzeyi:
  kuadratik ağırlıklı kappa, tam / ±1 uyum, 5×5 tablo; güven aralığı kesite göre bootstrap (10000, sabit tohum).
  Tutarlılık: sürücü ve algoritma için tekrarlar arası ICC(1,1); "algoritma–sürücü uyumu, sürücü–sürücü uyumu kadar mı?".
  Dahil etme: kesitte ≥ 2 geçerli insan ve algoritma puanı. 1-5 çevirisi geliştirme setinde kurulur.
- Çukur: geçiş başına zamanla olay eşleştirme (tahmin, basıştan önceki ~5 sn içinde), duyarlılık, PPV, F1, km başına yanlış
  alarm; özgüllük için 20 m hücreler (2×2, NPV, kappa); güven puanıyla ROC/AUC; referans konumu yalnızca basış zamanından.
- Örneklem birimi kesittir (geçişler bağımsız değil). Hız üssü tek kısa geçişten kestirilemez; geliştirme setinde kestirilip dondurulur.

## Bölümler

- `lib/`, `android/`, `assets/`: Flutter Android uygulaması (şu an v1.4: kayıt, çukur işareti / uyarısı, puanlama, önizleme, CSV).
  - `main.dart`: ana ekran, kayıt motoru (0,5 sn pencere, ~200 Hz ivme, yerçekimi giderme 0,4 Hz yüksek geçiren), GPS, test sürüşü.
  - `ayarlar.dart`: scooter adı, çukur modu (`CukurModu`), test sürüşü anahtarı.
  - `puanlama.dart`: sürüş sonrası konfor puanlaması (`Parcalama`, `PuanlamaSayfasi`), `sadeAltlik()` gri harita altlığı.
  - `onizleme.dart`: Kayıtlar'da kayda dokununca açılan sade önizleme (harita / grafikler / puanlar / özet).
  - `recordings_page.dart`: Kayıtlar listesi, paylaşma, Belgeler'e kopyalama, `kaydiAc` (CSV'yi Excel vb. ile açma).
  - `test_surusu.dart`: `SanalTur` (test sürüşünün kampüs turu).
  - `hava_durumu.dart` (Open-Meteo), `device_info.dart`, `about_page.dart` (Hakkında / Teknik Bilgi kartları).
  - Kotlin: `MainActivity.kt` (ham GPS_PROVIDER kanalı, tuş yakalama `dispatchKeyEvent`, `kaan_usta/dosya` MediaStore dışa aktarma),
    `KayitServisi.kt` (ön plan kayıt hizmeti; işaret modunda MediaSession + VolumeProvider + sessiz AudioTrack ile ekran kapalıyken
    kulaklık / Bluetooth kumanda / ses tuşu yakalama).
- `analiz/`: v1 Python analiz betikleri (0,5 sn CSV biçimini okur; yeni ham biçim için karşılaştırma aşamasında yeniden ele alınacak).
  `surus_analizi.py` (tek sürüş), `birlestir.py` (sürüşleri birleştirme), `haritaya_oturtma.py` (OSM yollarına oturtma),
  `simulasyon.py` (gerçeği bilinen yapay sürüşlerle doğrulama). Yalnızca standart kütüphane ve matplotlib.
  Yöntem ve parametreler: `analiz/README.md`.
- `qgis/`: QGIS için GeoPackage biçimi (`README.md`), yazıcı ve örnek dosyalar.
- Masaüstü Windows uygulaması (`masaustu/`, `build-windows.yml`) kullanıcı isteğiyle **kaldırıldı** (24 Kasım 2026).
- Belgeler: `README.md` (uygulama), `analiz/README.md` (yöntem, çıktılar, sütunlar).

## v1.4 kayıt CSV biçimi (mevcut uygulama; 2.0'da GeoPackage'a geçecek)

Türkçe Excel biçimi: sütun ayırıcı `;`, ondalık ayırıcı `,`. Başlık:
`Tarih_Saat;Enlem;Boylam;GPS_Doppler_Hiz_kmh;Duzeltilmis_GPS_Hiz_kmh;Dikey_RMS;Dikey_Min;Dikey_Max;Ivme_Ornek_Sayisi;GPS_Dogruluk_m;Cukur;Isaret;Isaret_Kaynak`
- `Cukur`: uygulamanın anlık uyarısı (|Dikey_Min| veya Dikey_Max ≥ 35 m/s² ve hız ≥ 3 km/h); her modda sessizce yazılır.
- `Isaret` / `Isaret_Kaynak`: sürücünün çukur basışı; kaynak `ekran` / `tus` / `kumanda` / `kulaklik` (1 sn içindeki ikinci basış sayılmaz).
- Her kaydın yanında `_bilgi.txt` (cihaz, sensör, scooter, hava durumu, çukur modu, işaret sayısı) ve puanlandıysa `_puan.csv`
  (`Parca;Baslangic;Bitis;Uzunluk_m;Baslangic_Enlem;Baslangic_Boylam;Bitis_Enlem;Bitis_Boylam;Puan;Durum;Puanlama_Zamani`).
- Ayarlar'daki test sürüşü kayıtları `test_mikromobilite_...` adını alır, `_bilgi.txt`'ye `TEST SÜRÜŞÜ:` satırı yazılır;
  analiz klasör taramasında atlanır (dosya adıyla verilirse analiz eder, özete uyarı yazar).
- Kayıt bitince dosyalar telefonun **Belgeler/Mikromobilite** klasörüne kopyalanır (Android 10+ izin yok; 9 ve öncesi
  WRITE_EXTERNAL_STORAGE). Uygulama açılışında eski kayıtlar da kopyalanır. Kullanıcı bunun çalıştığını doğruladı.

## Uygulamanın özellikleri (v1.4.0+5, mevcut)

- **Çukur modu (Ayarlar, 3 seçenek):** "Çukurları ben işaretlerim" (varsayılan; ÇUKUR butonu + ses tuşu + Bluetooth kumanda +
  kulaklık tuşu, çift bip `assets/sesler/isaret.mp3`; otomatik uyarı gösterilmez ki işaretler ölçümden bağımsız olsun),
  "Otomatik çukur uyarısı" (kırmızı ışık + ses, işaret butonu yok), "Yalnızca ölçüm". İşaret modunda DURDUR basılı tutularak çalışır.
- **Konfor puanlaması:** DURDUR'dan sonra açılır ("Sonra" ile geçilir, Kayıtlar'daki yıldızdan sonradan yapılır). Güzergâh
  dönüşlerden (45°) parçalanır; gerçek sürüşte 10 m örnekleme, en kısa 50 m, uzun düzler en fazla ~200 m; test kayıtlarında
  1 m / en kısa 5 m (dosya adı `test_` ile seçilir). 1-5 kör puan (sarsıntı gösterilmez), "Hatırlamıyorum", "Geri".
- **Test sürüşü (Ayarlar, sanal GPS):** arkadaşın test modundan uyarlandı. Konum YTÜ Davutpaşa Yerleşkesi iç yollarında
  (OSM "YTU Davutpasa Yerleşkesi" yolları, orta bloğun çevresi) ~1,85 km kapalı tur; kuzey köşeden başlar, başa dönünce 6 sn
  durup yeni tura başlar; hız 4-20 km/h (dakikalık sinüs). Sarsıntı gerçek ivmeölçerden. Hava durumu alınmaz.
  Arkadaşın koddaki GPS'siz cihazlar için NETWORK_PROVIDER'a düşme değişikliği **alınmadı** (gerçek GPS yolunu etkilediği için);
  kullanıcıya önerildi, istenirse eklenebilir.
- **Kayıt önizlemesi (Kayıtlar'da kayda dokununca; gösterim için, asıl analiz bilgisayarda):** kullanıcı isteğiyle sadeleştirildi.
  Harita: 25 m'lik parçalar, medyan Dikey_RMS'e göre 3 sınıf (yeşil düzgün < 5, turuncu orta 5-8, kırmızı sarsıntılı ≥ 8 m/s²;
  sınırlar Kadıköy sürüşlerindeki 25 m parça dağılımından), çukur işaretleri lacivert kare (basıştan önceki 5 sn'deki en büyük tepe),
  konum 1 sn GPS gecikme düzeltmeli. Uygulamanın anlık uyarıları ve tek tek tepeler **gösterilmez** (elle sallamada ekranı
  dolduruyordu). Grafikler: 5 sn ortalama sarsıntı (sınıf bantlı) ve hız. Puanlar: puan ve ölçülen sınıf yan yana. Özet: yolun
  sınıf payları, süre, yol, hız, sayılar. Grafikler ek paket olmadan CustomPainter ile çizilir.
- **Harita altlıkları:** ana ekran Esri Light Gray Canvas (+ Reference etiketleri). Puanlama ve önizleme `sadeAltlik()`: Esri
  World_Street_Map'in ColorFilter ile griye çevrilmişi (kullanıcı sarı yolların göz yorduğunu söyledi; gri Canvas 16. seviyeden
  sonra bulanık). Analiz HTML haritaları da "sade" (gri filtreli Esri) altlık kullanır; CARTO API anahtarı istediği için bırakıldı.

## v1 analiz yöntemi (özet; ayrıntı `analiz/README.md`)

- GPS gecikme düzeltmesi 1,0 sn; duruş eşiği 3 km/h.
- Haritaya oturtma: HMM/Viterbi (Newson & Krumm). σ = max(doğruluk/1,5; 4 m), yol dışı eşiği max(2,5σ; 25 m), β = 5,
  yol dışı cezası 2,5, tek yön tersine ×2 (`--ters-yon-ceza`), hareket yönü ağırlığı 4 (`--oturtma-yon`).
  Kadıköy'de Mühürdar/Damga'da yanlış şerit ve Rıza Paşa'ya sahte sapma bu iki ayarla düzeltildi.
- Overpass sunucuları: `overpass-api.de`, yedek `maps.mail.ru/osm/tools/overpass`, `overpass.kumi.systems`.
  **Bulut oturumundan overpass-api.de bağlantıyı keser; maps.mail.ru çalışır** (betik sırayla dener).
- Sarsıntı ∝ hız^k (aynı 25 m parçadaki hız farklarından; ~0,6-0,73); sokak indeksi = 15 km/h'te beklenen Dikey_RMS.
- Darbe: tepe ≥ 4 × çevre RMS (iki yan) ve ≥ 10 m/s²; gruplama 10 m.
- Çukur işareti: basıştan önceki 5 sn'de tepe ≥ 3 × çevre RMS; ekran / telefon tuşu basışından sonraki 0,5 sn analiz dışı.
- Konfor puanı doğrulaması: parçaya satır atama `bas ≤ satır zamanı + gecikme ≤ bit`; en az 4 hareket satırı (2 sn);
  Spearman (ortalama sıralar) + iki yönlü permütasyon testi (10000, tohum 1). `birlestir.py` tüm sürüşleri havuzlar ve
  işaret duyarlılığını (işaretli çukurların kaçını otomatik darbe buldu) raporlar.

## v1 doğrulama sonuçları (eski tasarım; geliştirme verisi sayılır)

- Hocanın itirazı: "validasyon yok". O zamanki çözüm: (1) sürücünün çukur işaretleri ↔ otomatik darbe,
  (2) sürüş sonrası kör konfor puanı ↔ hız düzeltmeli sarsıntı indeksi.
- 3 Kasım 2026 Kadıköy sürüşü (`mikromobilite_20261103_155653`, Samsung SM-M215F, kulaklık tuşuyla 11 işaret):
  8 işaret net eşleşti ve 8/8'ini otomatik darbe tespiti de buldu; tepki süresi ~1,3 sn; 3 belirsiz (ikisi bir darbe noktasıyla
  aynı yerde). En sert 10 darbenin 9'u işaretli. Puan: 7 parça, Spearman r = −0,75, p = 0,069 (n küçük).
  Mühürdar Karakolu (parke / Arnavut kaldırımı) puan 1, indeks ~12; diğerleri 3,7-5,3 (insan ince farkı ayırmıyor).
  Sabit 35 m/s² anlık uyarı Arnavut kaldırımında 36 kez tetiklendi → uyarının doğrulama sürüşlerinde kapalı olması gerekçesi.
- Kullanıcının doğruladıkları: kulaklık tuşu **ekran açıkken** çalışıyor; Belgeler klasörü çalışıyor.
- **Henüz telefonda denenmedi:** kulaklık / kumanda tuşu **ekran kapalıyken**; v1.4.0'daki test sürüşü kampüs turu,
  sade önizleme ve gri altlık (APK derlemesi 32 başarılı).

## Doğrulama komutları

- v1 analiz betiği değişince: `python analiz/simulasyon.py` (10 senaryo, rapor `analiz/ornek/simulasyon_raporu.md`).
  Varsayılan değişirse raporu ve `analiz/ornek*` örnek çıktılarını yeniden üret.
- GeoPackage dosyaları: QGIS bulut oturumunda yok. GDAL ile okunarak denetlenir: oturumun geçici klasöründe
  `python3 -m venv gdalenv && gdalenv/bin/pip install pyogrio numpy` (GDAL gömülü gelir), sonra `pyogrio.list_layers`,
  `read_info` (CRS, alan türleri), `pyogrio.raw.read`. Rapor: "GDAL ile doğrulandı, QGIS'te denenmedi".
- Uygulama değişince: `flutter analyze` (info dahil temiz olmalı; CI'da uyarılar hata sayılır).
- Bulut oturumunda Flutter kurulu değildir: CI ile aynı sürümü (stable **3.47.7**) oturumun geçici klasörüne indir,
  `git config --global --add safe.directory '*'` çalıştır, sonra `flutter analyze`. Ekranı görmek için geçici bir widget testi
  (`test/` altında, commit edilmez) `matchesGoldenFile` + `--update-goldens` ile PNG üretir; Roboto ve MaterialIcons yazı tipleri
  SDK'nın `bin/cache/artifacts/material_fonts` klasöründen FontLoader ile yüklenir, `path_provider` kanalı taklit edilir.
  Testte harita karoları yüklenmez (boş gri altlık normaldir).
- Gerçek sürüş verisini oturumun geçici klasörüne kopyalayıp çalış. **Bağımsızlık kuralına uy** (insan dosyasını açma).

## Derleme (GitHub Actions)

- `build-apk.yml`: yalnızca `lib/`, `android/`, `assets/`, `pubspec.*`, `analysis_options.yaml` değişince APK derler
  (Flutter 3.47.7 stable; önce `flutter analyze`). APK: Actions → "APK Derle" → Artifacts.
- Bulut oturumunda `gh` yok; GitHub işlemleri MCP araçlarıyla. Depo herkese açık olduğundan derleme durumu
  `https://api.github.com/repos/UirosRios/kaan-usta/actions/runs` adresinden curl ile de okunabilir.
- Sürüm `pubspec.yaml`'da (`1.4.0+5`); kullanıcıya görünür özellik eklenince küçük sürümü artır (ham veri sürümü 2.0.0 olacak).

## Git

- Doğrudan `main` dalında çalış, commit et ve `main`'e gönder; ayrı dal açma (kullanıcının kalıcı isteği ve izni).
  Oturum `claude/...` gibi ayrı bir dalla başladıysa, değişiklik yapmadan önce `main`'e geç
  (`git checkout main && git pull --ff-only`); o dalda iş yapıldıysa önce `main` ile ileri alarak birleştir.

## Açık işler / sıradaki adımlar

- **Örnek GeoPackage biçimi ONAYLANDI** (25 Kasım 2026; `qgis/ornek/`, `qgis/ornek_uret.py`; GDAL ile okundu, kullanıcı
  QGIS'te (Windows, Türkçe arayüz) açtı; resmî `validate_gpkg.py` çalıştırılamadı). Sıradaki iş: uygulama 2.0.
- Veri aktarımı: `_ham.gpkg` (dakikada ~1,5 MB, günde ~60 MB) sohbete yüklenir; sığmazsa Google Drive (oturumda Drive
  bağlantısı var).
  Kullanıcının QGIS stil tercihi (katmanlar renkle değil biçimle ayrılsın): `gps_noktalari` Blues
  (ters çevirmeden; koyu = sarsıntılı), `insan_cukurlar` kırmızı üçgen, `claude_cukurlar` gölge efektli (drop shadow) daire.
  QGIS seçim rengi sarı; anlatımda renk yerine "seçili satırlara yakınlaştır" kullan. Kullanıcı QGIS **4.2.3** kullanıyor.
  25 Kasım: kullanıcının `deneme.qgz` projesinden stiller `qgis/stil_cikar.py` ile `qgis/stiller/*.qml`'e çıkarıldı ve
  GeoPackage'ların `layer_styles` tablosuna gömüldü (QGIS katmanı eklerken uygular; GDAL ile okundu, QGIS'te otomatik
  uygulanması denenmedi). Son hâli: Blues (`dikey_rms`, 5 sınıf, alt 0, üst açık), insan = kırmızı üçgen, Claude =
  gölgeli koyu kırmızı yıldız, proje KRS EPSG:5254, altlık Esri Light Gray Base. Proje dosyasında kullanıcının adı ve
  Windows yolu var: .qgz/.qgs **depoya konmaz**, yalnızca görünüm alınır. Uygulama 2.0 da aynı QML'leri gömmeli.
- Telefonda dene (2.0 ile): ekran kapalıyken kulaklık / kumanda işareti, gerçek örnekleme hızı, dosya boyutu.
- Kesit listesi (arkadaş + hoca, gözle, tüm zemin türleri) hazırlanacak; geliştirme ve test kesitleri ayrı sokaklar.
- İstenirse: arkadaşın GPS'siz cihazlarda ağ konumuna düşme değişikliği.
