# KAAN USTA – Mikromobilite Veri Aracı (YTÜ Harita Mühendisliği tezi)

Scooter / bisiklet sürüşünde telefonun GPS'i ve ivmeölçeriyle hıza göre dikey sarsıntıyı ölçen sistem.
Tezin sahibi kullanıcının arkadaşı (YTÜ Harita Mühendisliği); kullanıcı geliştirmeye yardım ediyor ve sürüşleri kendisi yapıyor.
Bu dosya oturumlar arası kalıcı hafızadır: bulut oturumu her seferinde sıfırdan kurulur, `~/.claude` altındaki notlar kaybolur.
Önemli bir karar veya durum değişince burayı güncelle.

## Kullanıcı ve çalışma tercihleri

- Kullanıcıyla **Türkçe** konuşulur (unutulunca kullanıcı uyardı); kod, yorumlar, commit mesajları ve belgeler Türkçedir.
- Kullanıcı hekimdir (yazılımcı değil): açıklamalar sade, teknik ayrıntı gerektiği kadar.
- **"Bir sorun varsa önce sor, sonra yap."** Belirsiz / riskli / kapsam dışı değişikliklerde önce sor; açık istekleri doğrudan yap.
- Sonuçları dürüst raporla: telefonda denenmemiş özellikleri "denenmedi" diye belirt.
- Hocaya gösterilecek açıklamalar istendiğinde Artifact sayfası olarak hazırlandı (uygulama mantığı, oturtma, çıktılar).

## Bölümler

- `lib/`, `android/`, `assets/`: Flutter Android uygulaması (kayıt, çukur işareti / uyarısı, puanlama, önizleme, CSV dışa aktarma).
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
- `analiz/`: Python analiz betikleri. `surus_analizi.py` (tek sürüş), `birlestir.py` (sürüşleri birleştirme),
  `haritaya_oturtma.py` (OSM yollarına oturtma), `simulasyon.py` (gerçeği bilinen yapay sürüşlerle doğrulama).
  Yalnızca standart kütüphane ve matplotlib kullanılır (masaüstü uygulaması bu ikisini gömülü getirir).
  Yöntem ve parametreler: `analiz/README.md`.
- `masaustu/analiz_araci.py`: betikleri Python kurmadan çalıştıran Windows uygulaması (tkinter + PyInstaller).
  Sürükle-bırak; `_bilgi.txt` / `_puan.csv` başka klasördeyse CSV'nin yanına kopyalar. "GitHub'dan güncelle" düğmesi betikleri
  deponun varsayılan dalından (`main`) çeker.
- Belgeler: `README.md` (uygulama), `analiz/README.md` (yöntem, çıktılar, sütunlar).

## Kayıt CSV biçimi

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

## Uygulamanın özellikleri (v1.4.0+5)

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

## Analiz yöntemi (özet; ayrıntı `analiz/README.md`)

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

## Doğrulama durumu ve sonuçlar

- Hocanın itirazı: "validasyon yok". Çözüm: (1) sürücünün çukur işaretleri (manuel referans) ↔ otomatik darbe,
  (2) sürüş sonrası kör konfor puanı ↔ hız düzeltmeli sarsıntı indeksi.
- 3 Kasım 2026 Kadıköy sürüşü (`mikromobilite_20261103_155653`, Samsung SM-M215F, kulaklık tuşuyla 11 işaret):
  8 işaret net eşleşti ve 8/8'ini otomatik darbe tespiti de buldu; tepki süresi ~1,3 sn; 3 belirsiz (ikisi bir darbe noktasıyla
  aynı yerde). En sert 10 darbenin 9'u işaretli. Puan: 7 parça, Spearman r = −0,75, p = 0,069 (n küçük; birleştirmeyle
  güçlenecek). Mühürdar Karakolu (parke / Arnavut kaldırımı) puan 1, indeks ~12; diğerleri 3,7-5,3 (insan ince farkı ayırmıyor).
  Sabit 35 m/s² anlık uyarı Arnavut kaldırımında 36 kez tetiklendi → uyarının doğrulama sürüşlerinde kapalı olması gerekçesi.
- Kullanıcının doğruladıkları: kulaklık tuşu **ekran açıkken** çalışıyor; Belgeler klasörü çalışıyor.
- **Henüz telefonda denenmedi:** kulaklık / kumanda tuşu **ekran kapalıyken**; v1.4.0'daki test sürüşü kampüs turu,
  sade önizleme ve gri altlık (APK derlemesi 32 başarılı).

## Doğrulama komutları

- Analiz betiği değişince: `python analiz/simulasyon.py` (10 senaryo, rapor `analiz/ornek/simulasyon_raporu.md`).
  Varsayılan değişirse raporu ve `analiz/ornek*` örnek çıktılarını yeniden üret.
- Uygulama değişince: `flutter analyze` (info dahil temiz olmalı; CI'da uyarılar hata sayılır).
- Bulut oturumunda Flutter kurulu değildir: CI ile aynı sürümü (stable **3.47.7**) oturumun geçici klasörüne indir,
  `git config --global --add safe.directory '*'` çalıştır, sonra `flutter analyze`. Ekranı görmek için geçici bir widget testi
  (`test/` altında, commit edilmez) `matchesGoldenFile` + `--update-goldens` ile PNG üretir; Roboto ve MaterialIcons yazı tipleri
  SDK'nın `bin/cache/artifacts/material_fonts` klasöründen FontLoader ile yüklenir, `path_provider` kanalı taklit edilir.
  Testte harita karoları yüklenmez (boş gri altlık normaldir).
- Gerçek sürüş analizi için kullanıcının gönderdiği dosyaları oturumun geçici klasörüne kopyalayıp
  `python analiz/surus_analizi.py <csv>` çalıştır; `_bilgi.txt` ve `_puan.csv` CSV'nin yanında olmalı.

## Derleme (GitHub Actions)

- `build-apk.yml`: yalnızca `lib/`, `android/`, `assets/`, `pubspec.*`, `analysis_options.yaml` değişince APK derler
  (Flutter 3.47.7 stable; önce `flutter analyze`). APK: Actions → "APK Derle" → Artifacts.
- `build-windows.yml`: `analiz/` veya `masaustu/` değişince `KaanUstaAnaliz.exe` derler.
- Bulut oturumunda `gh` yok; GitHub işlemleri MCP araçlarıyla. Depo herkese açık olduğundan derleme durumu
  `https://api.github.com/repos/UirosRios/kaan-usta/actions/runs` adresinden curl ile de okunabilir.
- Sürüm `pubspec.yaml`'da (`1.4.0+5`); kullanıcıya görünür özellik eklenince küçük sürümü artır.

## Git

- Değişiklikleri doğrudan `main` dalına gönder. Oturum ayrı bir dal açtıysa işi bitirince `main` ile birleştir
  (ileri alarak) ve `main`'e gönder. Bu, kullanıcının kalıcı iznidir.

## Açık işler / sıradaki adımlar

- Telefonda dene: ekran kapalıyken kulaklık / kumanda işareti; test sürüşü turu; sade önizleme ve gri altlık.
- Daha fazla doğrulama sürüşü (işaret modu + puanlama) toplayıp `birlestir.py` ile havuzlanmış Spearman ve işaret duyarlılığı.
- İstenirse: arkadaşın GPS'siz cihazlarda ağ konumuna düşme değişikliği.
