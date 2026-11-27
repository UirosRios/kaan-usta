# KAAN USTA – Mikromobilite Veri Aracı (YTÜ Harita Mühendisliği tezi)

Scooter / bisiklet sürüşünde telefonun GPS'i ve ivmeölçeriyle hıza göre dikey sarsıntıyı ölçen sistem.
Tezin sahibi kullanıcının arkadaşı (YTÜ Harita Mühendisliği); kullanıcı geliştirmeye yardım ediyor ve sürüşleri kendisi yapıyor.
Bu dosya oturumlar arası kalıcı hafızadır: bulut oturumu her seferinde sıfırdan kurulur, `~/.claude` altındaki notlar kaybolur.
Önemli bir karar veya durum değişince burayı güncelle.

## Kullanıcı ve çalışma tercihleri

- Kullanıcıyla **Türkçe** konuşulur, uzun raporlar dahil her mesaj (iki kez unutuldu, kullanıcı uyardı); kod, yorumlar, commit mesajları ve belgeler Türkçedir.
- Kullanıcı hekimdir (yazılımcı değil): açıklamalar sade, teknik ayrıntı gerektiği kadar.
- **"Bir sorun varsa önce sor, sonra yap."** Belirsiz / riskli / kapsam dışı değişikliklerde önce sor; açık istekleri doğrudan yap.
  Büyük işlerde önce plan sunulur, kullanıcı onaylayınca ("başla") uygulanır.
- Sonuçları dürüst raporla: telefonda denenmemiş özellikleri "denenmedi" diye belirt.
- Hocaya gösterilecek açıklamalar istendiğinde Artifact sayfası olarak hazırlandı (uygulama mantığı, oturtma, çıktılar).
  25 Kasım 2026 (2.0 için): "Kaan Usta Sistem Özeti" https://claude.ai/artifact/HR6424k6VUmaTi8ud21ghG ve "Kaan Usta Veri
  Sözlüğü" https://claude.ai/artifact/RCaCWqkL2HCKi2QdT3CK5r (QGIS sütunları, deneme sürüşünden örnekler). Kaynak HTML'ler
  oturumun geçici klasöründeydi; güncellemek için sayfayı `Artifact read` ile okuyup aynı URL'ye yayımla.
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
  **Hocanın kararı (27 Kasım 2026, arkadaş aracılığıyla):** "5-6 farklı sokaktaki sürüşü ve o güzergâhlarda elle belirlenen
  rahatsızlık uyandıran sarsıntı noktalarını Claude'a birlikte ver (geliştirme). Sonra başka yollarda yine noktaları belirle
  ama Claude'a yalnızca sürüş verisini yükle; sorunlu noktaların konumlarını tahmin etsin. Tahmin ile elle belirlenen ne kadar
  yakın, ölç; GPS'in konum hatasından küçükse doğru kabul et." → İnsan işaretleri geliştirme setinde ayar için kullanılabilir;
  test sokakları farklı ve işaretleri tahminler GitHub'a konmadan görülmez. Hoca konfor puanından (1-5) söz etmedi.
  **Kullanıcının cevapları (27 Kasım):** (1) konfor puanı (1-5) tezde **kalıyor**; (2) "doğru" eşiğini kullanıcı ve arkadaş
  geliştirme sürüşlerinden sonra, o sürüşlerin `dogruluk_m` değerlerine bakarak **kendileri belirler** (test öncesi sabitlenir);
  (3) doğru eşleşenin yanında kaçırılan ve fazladan bulunan da sayılır (duyarlılık + kesinlik; ek tablo 5 / 10 / 15 m).
  Not: işaret ve tahmin aynı GPS izinden geldiği için GPS'in mutlak hatası büyük ölçüde sadeleşir; ölçüt pratikte zaman
  uyumunu (basış gecikmesi × hız) sınar (kullanıcıya açıklandı).
  Algoritmaya geliştirme sürüşleri gelince ve kullanıcı "başla" deyince başlanır.
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
  ekran butonu yedek, kaynağı kaydedilir). Kumandanın "iOS" (ses açma) tuşu kullanılır.
- **Kayıt sırasında ekran açık kalır, kilitlenmez** (karar 25 Kasım 2026): ekran kapalıyken kumanda çalışmıyor; uygulama
  kayıtta ekranı açık tutar. Ekran kapalı yöntemi (ses düzeyini izleme) denenmedi, kullanıcı istemedi.
- Kesitler önceden, **gözle** seçilir (ölçülen sarsıntıya bakmadan) ve tüm zemin türlerini kapsar (çok iyi asfalt … Arnavut
  kaldırımı, ray, kasis); tercihen > 150 m. Her kesit ≥ 3 geçiş (farklı gün / hız / iki yönlüyse iki yön). Hedef 20-25+ kesit.
- **Kesit kimliği otomatik:** başlangıç ve bitiş noktaları ~30 m içinde (ters yön dahil) ve güzergâhı büyük ölçüde (%80+)
  çakışan kayıtlar aynı kesit. Kodu (K01, K02 …) telefon verir (önerilen; örnek dosyada öyle), QGIS'te düzeltilebilir;
  sokak adı OSM'den analizde verilir (telefon çevrimdışı ad alamaz). Eşikler kesinleşmedi.
  **Kesit referansı (25 Kasım, derleme 40):** kesitin uçları, kayıtlarının uçlarının ortancası (`kesitler.json`'da kayıt
  başına `uclar`, kesitin yönüne çevrilmiş; dönüşte baş/bit yer değiştirir). Silinen kayıt referanstan çıkar: yanlış
  noktadan başlayan geçiş silinip yeniden sürülünce kesit kalan geçişlere göre eşleşir; 3+ geçişte tek sapan geçiş
  referansı kaydırmaz. 2.1 öncesi defterde uçlar gün dosyasından (`gps_noktalari`, aynı `uclar` kuralı, salt okunur)
  tamamlanır; dosya yoksa / bozuksa kayıt bilinmeyen kalır (referansa katılmaz, çeviriyi ve silmeyi engellemez).
  **Boşalan kesit saklanır** (kullanıcı onayladı, 25 Kasım): bütün kayıtları silinen kesit (adlı / adsız) defterde son
  referansıyla kalır; aynı yer yeniden sürülünce kodu ve adı geri gelir, başka sokak yeni kod alır (kod hiç yeniden
  verilmez; önceden gönderilmiş dosyalarla karışmasın).
  Sınırlar: (1) bölünmüş kodlar birleştirilmez (ilk geçiş >30 m saptıysa yeni kod açılmış olabilir; QGIS'te düzeltilir);
  (2) boşalan kesitin referansı son silinen kaydınkidir (silme sırasına bağlı; tek kötü geçiş silindiyse onun uçları);
  (3) iki geçişte referans ortadır (her biri ±15 m sapmış olabilir).

### Uygulama 2.0 (yazıldı 25 Kasım 2026, sürüm 2.0.0+6; telefonda DENENMEDİ)

- **Ham kayıt:** ivmeölçer 3 eksen ve **jiroskop** (kullanıcı istedi) ~200 Hz, her GPS_PROVIDER konumu (hız, yön, doğruluk,
  yükseklik, uydu sayısı), her basış; hepsi **aynı saatle** (sensör zaman damgası). Telefonda filtre yok (yalnızca nokta
  katmanındaki sarsıntı özeti; kullanıcı onayladı). Kayıt Kotlin `KayitMotoru`'nda (sensör olayının kendi zaman damgası;
  başka saat tabanındaysa 'T' saat eşi kayıtlarından düzeltilir, `HamKayit.sensorSaatDuzeltmesi`).
- **Çıktı:** her sürüş günü için GeoPackage, **yazarına göre ayrı dosyalar**: `*_ham.gpkg` (Claude'a gider) ve `*_insan.gpkg`
  (işaret + puan; sürücüde kalır). Claude `*_claude.gpkg` üretir. Ayrıntı: `qgis/README.md`.
- Kaldırıldı: çukur modları (otomatik uyarı / yalnızca ölçüm) ve `Cukur` sütunu, 0,5 sn özet CSV, her DURDUR'dan sonra açılan paylaşım ekranı,
  dönüşlere göre otomatik parçalama (`Parcalama`), puanlamadaki "Sonra", önizlemedeki sarsıntı renkleri. Yerine: gün sonunda
  Kayıtlar'da gün başına "Ham dosyayı gönder" ve "İşaret/puan dosyası".
- **Kayıt sırasında sarsıntı ve harita görünmeye devam eder** (kullanıcı istedi, 25 Kasım).
- **Kesit adı:** Kayıtlar sayfasında kesite ad verilebilir (`kesit_adi`; aynı kesitin bütün kayıtlarına uygulanır, sonraki
  kayıtlar da alır). Alan `kayitlar`, `insan_puanlar`, `claude_puanlar` katmanlarında (kullanıcı istedi, 25 Kasım).
- **Sürüm 2.1 sadeleştirme (25 Kasım 2026, kullanıcı seçti):** GeoPackage'tan kaldırıldı: UTC saat alanları (`zaman`,
  `kayitlar.baslangic/bitis`; `puanlama_zamani` yerine İstanbul saatiyle metin `puanlama_yerel`), `ruzgar_kmh`,
  `yukseklik_m`, `hiz_dogrulugu_kmh`, `dikey_dogruluk_m`. Saat yalnızca `t_s` + İstanbul saati (`yerel_saat`,
  `baslangic_yerel`). Jiroskop **kalıyor** (dosyanın %47'si; kullanıcı "kalsın"). Ekrandan "Düzeltilmiş GPS" (Fused konum
  servisi) kaldırıldı; TOPLAM ve EĞİM kaldı. `.kuham` ham biçimi değişmedi (Kotlin hâlâ yükseklik vb. yazar, çeviride atılır).
  Kod incelemesi (25 Kasım, /code-review xhigh, 11 bulgu): önemli üçü düzeltildi (derleme 38): (1) DURDUR'da kayıt bilgisi
  (`<ham>.kuham.json`) üzerine yazılmıyor, `KayitBilgisi.eksikleriDoldur` ile birleşiyor (ekran yeniden kurulursa scooter /
  hava kaybolmasın); (2) dosya işlemleri `sirayla` kuyruğunda + `busy_timeout`; (3) `KayitMotoru` ilk yazma hatasından
  sonra hiçbir şey yazmaz, dosyayı `FileOutputStream`'den doğrudan kapatır, hatayı DURDUR'da `hata` olarak döner (Dart
  "hafıza dolmuş olabilir" uyarısı gösterir; hatadan sonra basış sayılmaz, bip gelmez). Kalan 8 bulgu kullanıcıya açıklandı;
  kullanıcının seçtiği dördü düzeltildi (derleme 39-40, telefonda denenmedi): yeniden kurulan ekranda süre ve çukur sayacı
  kayıttan devam eder (`KayitMotoru.durum`: `baslangicMs`, `isaret`; denemesi: Geliştirici seçenekleri → "Etkinlikleri
  tutma"), kesit adı penceresi kendi denetleyicisini kapatır, Kayıtlar işlemlerinde hata mesajı (`_islem`), kesit
  referansı (bkz. Sürüş protokolü). Uygulanmayan dördü: test sürüşü kayıtta değiştirilince eski mod kalması, yeniden
  kurulumdan sonra Belgeler'de "(1)" kopyaları (denetlenecek), bozuk .kuham / sahipsiz .json temizlenmemesi, karışık
  2.0/2.1 dosyada eski veri sözlüğü.
  2.0 ile yazılmış gün dosyasına 2.1 kayıt eklerse `GeoPackage.katman` eksik alanları `ALTER TABLE ADD COLUMN` ile ekler
  (eski alanlar boş kalır); `puanYaz` önce `alanlariTamamla` çağırır (testi var).
- Kaldı: işaret yolları (kulaklık / kumanda / ses tuşu / ekran), test sürüşü (sanal GPS; `test_` dosyalarına), Belgeler/Mikromobilite
  kopyası (DURDUR, puan, ad, silme sonrası), v1 kayıtları ("Eski kayıtlar").
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

- `lib/`, `android/`, `assets/`: Flutter Android uygulaması, **sürüm 2.0** (ham veri toplayıcı, GeoPackage çıktısı).
  - `main.dart`: ana ekran (canlı sarsıntı / hız / harita yalnızca gösterim), BAŞLAT / DURDUR (basılı tut), ÇUKUR butonu, test
    sürüşü sanal konumu, açılışta yarım kalan ham dosyaları çevirme (`_yarimKalanlariCevir`).
  - Kayıt hattı (Flutter'sız, host'ta test edilir): `ham_kayit.dart` (.kuham okuyucu, `dikeySarsinti`), `gpkg.dart`
    (GeoPackage yazıcı, `package:sqlite3` 3.9.1 sabit), `katmanlar.dart` (katman şeması + veri sözlüğü; `qgis/ornek` ile aynı
    olmalı), `kesitler.dart` (kesit defteri `kesitler.json`, 30 m kuralı, referans = kayıt uçlarının ortancası), `donusturucu.dart` (`donustur`, `puanYaz`,
    `kesitAdiVer`, `kayitSil`, `kayitlariListele`, `haritaVerisi`), `arka_plan.dart` (isolate sarmalayıcıları: **sayfa içinden
    `Isolate.run` çağırma**, kapanış sayfayı yakalar ve "unsendable" hatası verir; ekran görüntüsü testi bunu yakaladı;
    gün dosyalarına / `kesitler.json`'a dokunan her işlem ve Belgeler kopyası **`sirayla`** ile tek sırada çalışır,
    sıradaki bir işlemin içinden `sirayla` çağrılmaz; `GeoPackage.ac` ayrıca `busy_timeout = 5000`).
  - `puan_sayfasi.dart` (DURDUR sonrası geçilemez puan ekranı), `kayitlar_sayfasi.dart` (günlere göre liste, gönder, kesit adı,
    puan, sil, harita), `ayarlar.dart` (scooter, çukur işareti açıklaması, test sürüşü; çukur modları kaldırıldı).
  - v1 için kalanlar: `recordings_page.dart` ("Eski kayıtlar (v1)" sayfası + `recordingsDirectory`, `telefonaKopyala`,
    `tumKayitlariKopyala` artık .gpkg'leri de kopyalar), `onizleme.dart`, `puanlama.dart` (`sadeAltlik()` 2.0'da da kullanılır).
  - `test_surusu.dart`, `hava_durumu.dart`, `device_info.dart` (jiroskop eklendi), `about_page.dart` (2.0 metinleri).
  - Kotlin: `KayitMotoru.kt` (ham kayıt: ivme + jiroskop 5000 µs, GPS_PROVIDER 500 ms + GnssStatus uydu, basışlar; ikili
    `.kuham`, saniyede bir flush, 'T' saat eşi kayıtları), `MainActivity.kt` (`kaan_usta/kayit_servisi`: baslat {yol, sanal},
    durdur, isaret, sanalKonum, durum; ekran GPS kanalı; tuş yakalama `KayitMotoru.kayitta` iken; `isFinishing` ise kaydı kapatır),
    `KayitServisi.kt` (ön plan hizmeti + MediaSession / VolumeProvider / sessiz AudioTrack; `isaretBildir` önce KayitMotoru'na yazar).
  - Testler: `test/donusturucu_test.dart` (yapay .kuham → gpkg; okuma, saat düzeltmesi, yarım dosya, kesit, puan, ad, silme, test
    dosyaları, 2.0 gün dosyası, eski kesit defteri ve bozuk eski gün dosyası), `test/kesitler_test.dart` (kesit referansı:
    silme, dönüş, sapan geçiş, adlı boş kesit, JSON), `test/arka_plan_test.dart` (`sirayla`, isolate, busy_timeout). `KAAN_TEST_CIKTI=<klasör> flutter test` çıktıları kopyalar; `python3 qgis/sema_karsilastir.py qgis/ornek/..._ham.gpkg
    <çıktı>_ham.gpkg` biçimi denetler (25 Kasım: gerçek ve test, ham ve insan dosyalarının dördü de örnekle aynı; testte gerçek
    `qgis/stiller` kullanılır).
- `analiz/`: v1 Python analiz betikleri (0,5 sn CSV biçimini okur; yeni ham biçim için karşılaştırma aşamasında yeniden ele alınacak).
  `surus_analizi.py` (tek sürüş), `birlestir.py` (sürüşleri birleştirme), `haritaya_oturtma.py` (OSM yollarına oturtma),
  `simulasyon.py` (gerçeği bilinen yapay sürüşlerle doğrulama). Yalnızca standart kütüphane ve matplotlib.
  Yöntem ve parametreler: `analiz/README.md`.
- `qgis/`: QGIS için GeoPackage biçimi (`README.md`), Python yazıcı (`gpkg.py`), örnek üretici (`ornek_uret.py`), stiller
  (`stiller/*.qml`, `stil_cikar.py`; uygulamaya asset olarak gömülür, CI `qgis/stiller/**` değişince de APK derler), biçim
  karşılaştırıcı (`sema_karsilastir.py`).
- Masaüstü Windows uygulaması (`masaustu/`, `build-windows.yml`) kullanıcı isteğiyle **kaldırıldı** (24 Kasım 2026).
- Belgeler: `README.md` (uygulama), `analiz/README.md` (yöntem, çıktılar, sütunlar).

## v1.4 kayıt CSV biçimi (eski; telefondaki v1 kayıtları bu biçimde kalır)

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

## v1.4 uygulamasının özellikleri (eski; 2.0'da çoğu kaldırıldı, bkz. "Uygulama 2.0")

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
- Ekran kapalıyken kumanda 25 Kasım'da 2.0'da denendi, çalışmadı (bkz. Sürüş protokolü). **Henüz telefonda denenmedi:** v1.4.0'daki test sürüşü kampüs turu,
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
- Sürüm `pubspec.yaml`'da (`2.1.0+6`); kullanıcıya görünür özellik eklenince küçük sürümü artır. APK'nın yapı numarası CI
  çalıştırma numarasıdır (`--build-number=run_number`).

## Git

- Doğrudan `main` dalında çalış, commit et ve `main`'e gönder; ayrı dal açma (kullanıcının kalıcı isteği ve izni).
  Oturum `claude/...` gibi ayrı bir dalla başladıysa, değişiklik yapmadan önce `main`'e geç
  (`git checkout main && git pull --ff-only`); o dalda iş yapıldıysa önce `main` ile ileri alarak birleştir.

## Açık işler / sıradaki adımlar

- **Örnek GeoPackage biçimi ONAYLANDI** (25 Kasım 2026; `qgis/ornek/`, `qgis/ornek_uret.py`; GDAL ile okundu, kullanıcı
  QGIS'te (Windows, Türkçe arayüz) açtı; resmî `validate_gpkg.py` çalıştırılamadı). Sıradaki iş: uygulama 2.0.
- Veri aktarımı: `_ham.gpkg` (ölçüldü: dakikada ~1 MB, günde ~40 MB) sohbete yüklenir; sığmazsa Google Drive (oturumda Drive
  bağlantısı var).
  Kullanıcının QGIS stil tercihi (katmanlar renkle değil biçimle ayrılsın): `gps_noktalari` Blues
  (ters çevirmeden; koyu = sarsıntılı), `insan_cukurlar` kırmızı üçgen, `claude_cukurlar` gölge efektli (drop shadow) daire.
  QGIS seçim rengi sarı; anlatımda renk yerine "seçili satırlara yakınlaştır" kullan. Kullanıcı QGIS **4.2.3** kullanıyor.
  25 Kasım: kullanıcının `deneme.qgz` projesinden stiller `qgis/stil_cikar.py` ile `qgis/stiller/*.qml`'e çıkarıldı ve
  GeoPackage'ların `layer_styles` tablosuna gömüldü (QGIS katmanı eklerken uygular; GDAL ile okundu, QGIS'te otomatik
  uygulanması denenmedi). Son hâli: Blues (`dikey_rms`, 5 sınıf, alt 0, üst açık), insan = kırmızı üçgen, Claude =
  gölgeli koyu kırmızı yıldız, proje KRS EPSG:5254, altlık Esri Light Gray Base. Proje dosyasında kullanıcının adı ve
  Windows yolu var: .qgz/.qgs **depoya konmaz**, yalnızca görünüm alınır. Uygulama 2.0 da aynı QML'leri gömmeli.
- **Uygulama 2.0 telefonda denenecek** (hiçbiri denenmedi): evde test sürüşü provası (BAŞLAT → işaret → DURDUR → puan →
  Kayıtlar → gönder → QGIS), sonra 2-3 kısa gerçek kesit: ekran kapalıyken kulaklık / kumanda, gerçek örnekleme hızı
  (`kayitlar.ivme_hz`), dosya boyutu, sohbete yükleme, kesit otomatik atama, yarım kalan kayıt kurtarma.
  **Telefonda görüldü (25 Kasım, kullanıcının ekran görüntüsü):** gerçek GPS'le 4 kısa kayıt (22-32 sn, 31-68 m); Kayıtlar
  listesi, puanlar, işaret sayıları, kesit ataması ve gidiş/dönüş (K01 gidiş + K01 dönüş) çalışıyor. Gönder / QGIS henüz görülmedi.
  **İlk gerçek dosyalar incelendi (25 Kasım, Söğütlüçeşme, yapı 34, SM-M215F, 4 kayıt / 108 sn, gece ~03:00):**
  biçim örnekle aynı (`sema_karsilastir.py`, ham + insan), SQLite bütünlük temiz; **QGIS'te gömülü stiller kendiliğinden uygulandı**
  (kullanıcının ekran görüntüsü). İvme ve jiroskop **125,2 Hz** (8,00 ms ± 0,1, boşluk yok, sıra bozulması yok; v1 de bu
  telefonda 125 Hz idi, `analiz/README.md` simülasyonu da 125 Hz; 5000 µs isteğine telefon 125 Hz veriyor, değiştirilmedi).
  GPS saniyede 1 konum (500 ms istendi, yonga 1 Hz veriyor), doğruluk 3,5-7 m, 15-24 uydu. Saat düzeltmesi gerekmedi.
  Boyut ~0,95 MB/dk. 9 işaretin hepsi `kumanda` (Bluetooth kumanda, ekran açık: `dispatchKeyEvent` + harici aygıt);
  her biri net bir darbeden (çevre RMS'in 7-14 katı, 33-65 m/s²) **0,1-0,9 sn** sonra; ikisinde basış darbeyle neredeyse aynı
  anda (sürücü çukuru görüp önceden basıyor) → algoritma eşleştirme penceresi basıştan biraz sonrasını da kapsamalı
  (geliştirme bulgusu). İşaretsiz büyük darbeler de var (ör. 030314'te 9,8 ve 10,7 sn).
  **Ekran kapalıyken kumanda ÇALIŞMADI** (25 Kasım, yapı 36, kullanıcı: çukur sayısı artmadı, başka uygulama açılmadı).
  Kumanda iki tuşlu selfie kumandası: "iOS" tuşu = ses açma (kullanılan, ekran açıkken çalışıyor), "Android" tuşu = Enter.
  Ekran kapalıyken basınca ekran yanmadı, telefonun ses düzeyi de değişmedi. Olası neden (doğrulanmadı): Android 12+'da
  `setPlaybackToRemote` oturumu, MediaRouter2 yönlendirme oturumu yoksa ses tuşlarını alamıyor (`canHandleVolumeKey` false);
  tuş müzik akışına düşüyor, ekran kapalıyken yalnızca müzik çalıyorsa işleniyor. Enter ekran kapalıyken hiçbir uygulamaya
  gitmez. Seçenekler kullanıcıya sunuldu: (1) ekran açık kalsın (önerilen, çalışıyor), (2) yerel oturum + sessiz ses + ses
  düzeyi değişimini izleyip geri alma (emin değil, medya sesini kayıtta ortaya çeker). **Kullanıcı (1)'i seçti.** Çözüm: kayıtta ekranı kilitlememek (uygulama kayıtta ekranı açık tutar,
  `WakelockPlus`; ekran açıkken kumanda 9/9 çalıştı). Olası ek: Ayarlar'da tuş denemesi (tuş kodu ve aygıt adını gösterir).
  Önceki not: ekran **kapalıyken** Bluetooth kumandanın ses tuşu `VolumeProvider`'dan gelir ve `tus` (telefon tuşu) diye
  kaydedilir; kaynağı yanlış olur (analiz `tus` sonrası 0,5 sn'yi dışlar). Ekran kapalı deneme dosyasında bakılacak.
  **İvmeölçer doyması:** ICM42605M ±8 g; değer 78,45 m/s²'de takılıyor (denemede 13 432 örneğin 50'si, çoğu y ekseni,
  sert darbelerde) → darbe görülür ama tepe büyüklüğü kırpılır; algoritma bunu hesaba katmalı. Bu telefonda
  `hiz_dogrulugu_kmh` hep 72 ve `dikey_dogruluk_m` hep 100 (telefon hesaplamıyor; 2.1'de bu alanlar ve yükseklik kaldırıldı);
  `yon_derece` dururken 0 (boş değil).
  **"Kaymış görünüyor" (26 Kasım, arkadaşın QGIS ekranı, aynı deneme dosyası):** ölçüldü, sistematik kayma yok. GPS
  noktalarının OSM sokak orta çizgisine uzaklığı kayıt başına ortanca 1,1 / 1,8 / 2,7 / 5,3 m (en çok 6,3 m); Esri World Street
  Map ve Esri Light Gray'de de sokakların üstünde. Sokaklar tek şeritli (~5-6 m), ekran ~250 m genişliğe yakınlaştırılmış:
  3-7 m GPS hatası (kayıttaki `dogruluk_m` de 3-7) noktaları kaldırıma / bina köşesine düşürüyor; gidiş ve dönüş iki paralel
  çizgi (sağdan sürüş + GPS). Batıdaki sokak yolda, doğudaki 2-4 m doğuda, Mahmut Baba'daki bacak ~5 m kuzeyde: düzensiz,
  yani KRS / projeksiyon sorunu değil (öyle olsa hepsi aynı yöne, çoğunlukla çok daha fazla kayardı). Çözüm analizde
  haritaya oturtma (v1 HMM yöntemi), algoritma aşamasında. Karşılaştırma betiği oturumun geçici klasöründeydi.
  Kullanıcının ekranında (Esri Light Gray Base) aynı veri yollara oturmuş görünüyor; arkadaşın altlığı başka bir şirketin
  haritası (yazılar "Mahmutbaba Sokak": OSM'de "Mahmut Baba Sokağı", Esri'de "Mahmut Baba Sokak"). Fark büyük ölçüde altlıkta.
  Öneri: ikisi aynı altlığı kullansın; yakın bakışta OSM (keskin, oturtmada kullanılacak veri).
  Günler birleştirilmez: her gün ayrı dosya çifti; birleştirme analizde (Claude) veya QGIS'te ("Vektör katmanlarını birleştir").
  Kesit defteri (`kesitler.json`) telefona özeldir: iki telefonla sürülürse kodlar eşleşmez, analizde uç noktalardan yeniden eşlenir. Şimdilik sürüşleri yalnızca kullanıcı
  yapıyor (tek telefon); değişirse haber verecek.
  Bilinen sınırlar: kesit ataması yalnızca uç noktalara bakar (%80 güzergâh çakışması denetimi yok).
  Hiç çalışmamış olanlar: `KayitMotoru.kt` hiçbir yerde çalıştırılmadı (yalnızca CI'da derlenir); Kotlin'in yazdığı .kuham baytları
  ile Dart okuyucusu yalnızca okunarak eşleştirildi (test kendi baytlarını yazar).
- **APK 34** (25 Kasım, 2.0.0+34): derlendi. İçinde `lib/<abi>/libsqlite3.so` (arm64-v8a, armeabi-v7a, x86_64) ve
  `assets/flutter_assets/qgis/stiller/*.qml` var (artifact indirilip bakıldı). Derleme 33, Gradle NDK indirirken bozuk dosya
  aldığı için düştü; iş akışına NDK 28.2.13676358'i önceden, 3 denemeyle kuran adım eklendi (SQLite yerel kitaplığı NDK ister).
  İş akışı dosyası değişince derleme kendiliğinden başlamaz: `actions_run_trigger` run_workflow ile elle başlatılır.
- **25 Kasım, APK 34 ile ilk açılış:** dışarıda ~5 dk GPS konumu gelmedi (2-3 görünen, 0 kullanılan uydu; Google Haritalar
  konum buldu), sonra kendiliğinden düzeldi. Ekran GPS kodu (`kaan_usta/ham_gps`) v1.4 ile aynı; neden bulunamadı (büyük
  olasılıkla yavaş ilk konum). Tekrarlarsa: uygulamayı kapatıp açma, yeniden başlatma, güç tasarrufu, "GPS Test" ile karşılaştırma.
  Aynı sırada bulunan ekran hatası düzeltildi (derleme 35): test sürüşü kapatılınca eski sanal koordinat ve hız ekranda kalıyordu.
- **İmza anahtarı (karar verildi, 25 Kasım 2026):** sabit anahtar `android/app/kaan_usta.jks` (PKCS12, takma ad `kaan_usta`,
  parola `kaanusta-acik`, sertifika SHA-256 `e45f6375…`) **bilerek depoda ve herkese açık** (kullanıcı onayı; uygulama Play'de
  değil). `build.gradle.kts` release imzası bununla; `android/.gitignore`'da istisna. Önceki derlemeler (≤ 35) her seferinde başka
  debug anahtarıyla imzalanıyordu (32 ve 34 ölçüldü, farklı): kullanıcı ilk sabit anahtarlı derlemeye geçerken **son kez**
  kaldırıp kurar (uygulama klasörü, gün dosyaları, `kesitler.json` silinir), sonrakiler üstüne kurulur. Anahtar değiştirilmez.
- Kesit listesi (arkadaş + hoca, gözle, tüm zemin türleri) hazırlanacak; geliştirme ve test kesitleri ayrı sokaklar.
- İstenirse: arkadaşın GPS'siz cihazlarda ağ konumuna düşme değişikliği.
