# Mikromobilite Veri Aracı (Kaan Usta – YTÜ Harita Mühendisliği Tezi)

Telefonun GPS'i ve ivmeölçeri ile mikromobilite (e-scooter, bisiklet vb.) sürüşünde
**hıza göre dikey sarsıntıyı** ölçüp CSV olarak dışa aktaran Android uygulaması.

## APK'yı indirme

1. GitHub'da depo → **Actions** sekmesi → en son başarılı **"APK Derle"** çalıştırması.
2. Sayfanın altındaki **Artifacts** bölümünden `mikromobilite-apk` dosyasını indirin (zip içinde `app-release.apk`).
3. APK'yı telefona atıp açın ("Bilinmeyen kaynaklardan yükleme" izni istenir).

## CSV sütunları (her 0,5 sn'de bir satır)

Dosya Türkçe Excel biçimindedir: sütun ayırıcı **noktalı virgül (;)**, ondalık ayırıcı **virgül (,)**.
Excel'de çift tıklayınca sütunlar doğrudan ayrılır. Python ile okumak için:
`pd.read_csv("dosya.csv", sep=";", decimal=",")`.

| Sütun | Açıklama |
|---|---|
| `Tarih_Saat` | Kayıt zamanı (telefon saati) |
| `Enlem`, `Boylam` | Son geçerli GPS konumu, doğrudan GPS donanımından (WGS84, derece) |
| `GPS_Doppler_Hiz_kmh` | Doğrudan GPS donanımının hızı: uydu sinyalinin Doppler kaymasından, yumuşatma yok |
| `Duzeltilmis_GPS_Hiz_kmh` | Fused (birleşik) konum servisinin hızı; uygulamada "Düzeltilmiş GPS" |
| `Dikey_RMS` | Penceredeki dikey sarsıntının RMS'i (m/s²) → **ana sarsıntı şiddeti ölçüsü**. Dikey sarsıntı = titreşimin gerçek düşey yöndeki bileşeni, telefonun montaj açısından bağımsız |
| `Dikey_Min`, `Dikey_Max` | Penceredeki en düşük / en yüksek dikey sarsıntı (m/s², darbe tepe değerleri) |
| `Ivme_Ornek_Sayisi` | Penceredeki ivmeölçer örneği sayısı (~200 Hz istenir → ~100 beklenir; telefon daha yavaş veriyorsa daha az) |
| `GPS_Dogruluk_m` | GPS yatay konum doğruluğu (m, %68 güven yarıçapı) |
| `Cukur` | Anlık çukur uyarısı: o 0,5 sn içinde en büyük dikey ivme ≥ 35 m/s² ve GPS hızı ≥ 3 km/h ise `1` (ekrandaki sarsıntı kartı kırmızı yanar) |
| `Isaret` | Sürücünün çukur işaretine o 0,5 sn içinde kaç kez bastığı (boş = basılmadı) |
| `Isaret_Kaynak` | İşaretin nereden geldiği: `ekran` (ÇUKUR butonu), `tus` (telefonun ses tuşu), `kumanda` (Bluetooth kumanda), `kulaklik` (kulaklık / medya tuşu) |

**GPS kesintisi:** Son GPS konumu 3 saniyeden eskiyse (tünel, yüksek bina arası vb.) `Enlem`, `Boylam`,
`GPS_Doppler_Hiz_kmh` ve `GPS_Dogruluk_m` hücreleri boş bırakılır; düzeltilmiş GPS 3 saniyeden eskiyse
`Duzeltilmis_GPS_Hiz_kmh` boş kalır. Böylece eski konum/hız tekrar yazılmaz; sarsıntı sütunları yine doldurulur.

**Yerçekimi giderme ve dikey sarsıntı:** İvmenin üç ekseni de 0,4 Hz kesim frekanslı birinci
dereceden yüksek geçiren filtreden (bilineer/Tustin dönüşümü) geçirilir; 0,4 Hz, ISO 2631-1'in alt
bant sınırıdır. Filtre çıkışı titreşim, ham ivme − titreşim ise yerçekimi vektörüdür (telefonun o anki
"aşağı" yönü). Dikey sarsıntı, titreşim vektörünün yerçekimi yönüne izdüşümüdür; bu sayede telefon
hangi açıda takılırsa takılsın aynı sarsıntı aynı değeri verir. Filtre ilk ~2 saniyede oturur.

## Analiz

Kayıtların analizi için `analiz/surus_analizi.py` betiği kullanılır: GPS gecikmesini düzeltir, duruşları
ayıklar, hıza göre sarsıntı tablosu çıkarır, darbeleri bulur ve sarsıntıya göre renklendirilmiş bir harita üretir.
Sokaklara göre sarsıntı sıralaması da çıkarır. Birden fazla sürüş `analiz/birlestir.py` ile birleştirilerek
yol kalitesi haritası ve tekrar eden darbe noktaları elde edilir. Ayrıntılar: [analiz/README.md](analiz/README.md).

Python kurmadan kullanmak için **Windows uygulaması** (`KaanUstaAnaliz.exe`, Actions → "Windows Uygulaması Derle" → Artifacts):
CSV, `_bilgi.txt` ve `_puan.csv` dosyaları pencereye sürüklenir, tek düğmeyle analiz / birleştirme yapılır. Betikler uygulamanın içinde gelir;
değiştiklerinde uygulama yeniden indirilmeden **GitHub'dan güncelle** veya **Betik dosyası yükle** ile yenilenir.

## Kayıt sırasında çukur: üç mod (Ayarlar)

| Mod | Sürücü ne görür / yapar | Ne zaman |
|---|---|---|
| **Çukurları ben işaretlerim** (varsayılan) | ÇUKUR butonu, ses tuşu, kumanda veya kulaklıkla işaretler; otomatik uyarı **gösterilmez** | Doğrulama sürüşleri |
| **Otomatik çukur uyarısı** | Sert darbede ekran kırmızı yanar, sesli uyarı; işaret butonu yok | Gösterim, uyarının denenmesi |
| **Yalnızca ölçüm** | Hiçbiri | Ekrana dokunmadan ölçüm |

- **Neden işaret modunda uyarı yok:** Uyarıyı gören sürücü uyarı geldiği için basar; işaretler ölçümden bağımsız olmaz ve
  doğrulama değerini yitirir. Uyarıyı görmeyen sürücünün işaretleri bağımsız bir referanstır.
- Her modda uygulamanın otomatik tespiti CSV'nin `Cukur` sütununa **sessizce** yazılır; analiz betiği sürücünün işaretleriyle karşılaştırır.
  Seçilen mod `_bilgi.txt`'ye yazılır.

## Anlık çukur uyarısı

Yalnızca **Otomatik çukur uyarısı** modunda: kayıt sırasında 0,5 saniyelik penceredeki en büyük dikey ivme (|Dikey_Min| veya Dikey_Max) **35 m/s²**'yi aşarsa
ve GPS hızı 3 km/h'in üstündeyse ekrandaki sarsıntı kartı 1,5 saniye **kırmızı yanar** ve **sesli uyarı** verilir, CSV'de o satırın `Cukur`
sütununa `1` yazılır. Kartın altında bu kayıttaki uyarı sayısı (UYARI) görünür.

- **Neden sabit eşik:** Kayıt sırasında yalnızca geçmiş bilinir. İki gerçek sürüşte, geçmişe göre ayarlanan (göreli)
  eşikler sabit eşikten daha iyi sonuç vermedi; 35 m/s² en sert darbeleri az yanlış alarmla yakaladı.
- **Hız şartı:** Duruşta scooter'ı elle çevirmek / itmek uyarı vermez. GPS hızı yoksa uyarı verilmez.
- **Uyarı ile betiğin ilişkisi:** Uyarı yalnızca en sert darbeleri gösterir. Ayrıntılı tespiti analiz betiği yapar: her darbeyi
  çevresindeki sarsıntıyla karşılaştırır ve GPS gecikmesini düzeltir. Betik, uygulamanın uyarılarını kendi bulduklarıyla karşılaştırıp
  haritada ayrıca gösterir.

## Çukur işaretleme (doğrulama için)

**Çukurları ben işaretlerim** modunda kayıt sırasında ekranda büyük turuncu **ÇUKUR** butonu çıkar. Sürücü çukurdan geçince işaretler; kısa bir çift bip duyulur
ve o an CSV'deki `Isaret` ve `Isaret_Kaynak` sütunlarına yazılır. Analiz betiği basıştan önceki 5 saniyedeki sarsıntı tepesini
bularak çukurun anını ve konumunu çıkarır ve otomatik darbe tespitinin bu işaretlerin kaçını bulduğunu raporlar.
İşaretler sistemin bağımsız bir referansla karşılaştırılması (doğrulama) içindir.

- **İşaretleme yolları:** ekrandaki buton, telefonun ses tuşları, **Bluetooth kumanda** (selfie / deklanşör kumandası; çoğu
  ses açma veya Enter tuşu gönderir) ve **kulaklık tuşu** (kablolu veya Bluetooth kulaklığın oynat/duraklat, ileri, geri tuşları).
- **Ekran kapalıyken:** kumanda, kulaklık ve ses tuşları kayıt hizmetinin medya oturumuyla yine çalışır. Bunun için kayıt boyunca
  sessiz bir ses çalınır. O sırada başka bir uygulama müzik çalıyorsa medya tuşları o uygulamaya gidebilir.
- **Kayıt sırasında** ses tuşları ses düzeyini değiştirmez, kulaklık tuşu müziği durdurmaz; kayıt bitince normale döner.
- **Buton etkisi:** Ekrana veya telefonun tuşuna basmak telefonu kısa bir an sarsar. Betik o satırı ve sonraki 0,5 sn'yi analize katmaz.
  Kumanda ve kulaklık telefonu sarsmadığı için bu basışlarda dışlama yapılmaz; doğrulama için en temiz yöntemdir.
- **Titreşim yok:** Geri bildirim yalnızca sesle verilir; titreşim motoru ivmeölçere karışırdı.
- **Çift basma:** 1 saniye içindeki ikinci basış sayılmaz.
- **Durdurma:** Kayıt sırasında **DURDUR** butonu, ÇUKUR butonuna basarken yanlışlıkla kaydı bitirmesin diye basılı tutularak çalışır.
- Diğer modlarda buton çıkmaz, tuşlar normal çalışır.

## Sürüş sonrası konfor puanlaması (doğrulama için)

DURDUR'dan sonra **Sürüşü puanla** ekranı açılır. Güzergâh dönüş noktalarından parçalara bölünür (kabaca her sokak bir parça;
uzun düz yollar en fazla ~200 m, en kısa parça 50 m). Haritada sırayla her parça mavi gösterilir (yeşil nokta başı, kırmızı sonu);
sürücü o parçadan geçişin ne kadar rahat olduğunu puanlar:

| 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|
| Çok sarsıntılı | Sarsıntılı | Orta | Rahat | Çok rahat |

- **Kör puanlama:** Haritada ölçülen sarsıntı gösterilmez; puan ölçümden bağımsız olmalıdır.
- **Hatırlamıyorum** seçilebilir, **Geri** ile önceki parça düzeltilebilir. **Sonra** ile geçilirse Kayıtlar sayfasındaki
  **yıldız** simgesinden sonradan puanlanır (puanlar değiştirilebilir). Sürüş akılda tazeyken puanlamak önerilir.
- Puanlar `mikromobilite_<tarih_saat>_puan.csv` dosyasına yazılır: parça no, başlangıç / bitiş zamanı ve konumu, uzunluk, puan,
  durum (`puanlandi` / `hatirlamiyorum` / `puanlanmadi`), puanlama zamanı.
- Analiz betiği her parçanın hız düzeltmeli sarsıntı indeksini puanla karşılaştırır (Spearman sıra korelasyonu); birleştirme bütün
  sürüşlerin parçalarını birlikte değerlendirir. Ayrıntı: [analiz/README.md](analiz/README.md).

## Ayarlar ve kayıt etiketleri

Başlıktaki **dişli** simgesinden açılan Ayarlar sayfasında kullanılan scooter (marka / model) bir kez yazılır; her kaydın
`_bilgi.txt` dosyasına otomatik eklenir. Şartlar değişince buradan güncellenir. Kayıt sırasında çukur modu da buradan seçilir (yukarıda).

Kayıt başında internet ve GPS konumu varsa **hava durumu** (durum, sıcaklık, yağış, rüzgâr, nem) [Open-Meteo](https://open-meteo.com)
servisinden alınır ve `_bilgi.txt`'ye yazılır. Konum ~1 km'ye yuvarlanarak gönderilir. Alınamazsa hava durumu satırı yazılmaz.

## Kayıt dosyaları

- Veriler kayıt sırasında **5 saniyede bir** dosyaya yazılır; uygulama kapanırsa en fazla son 5 saniye kaybolur.
- Her kayıt `mikromobilite_<tarih_saat>.csv` (veri), `..._bilgi.txt` (telefon modeli, Android ve uygulama sürümü,
  sensör adları/çözünürlük/ölçüm aralığı, ölçüm ayarları, çukur modu) ve puanlandıysa `..._puan.csv` dosyalarıdır.
- **Telefonda erişilebilir kopya:** Kayıt bitince (ve puanlama sonrası) dosyalar telefonun **Belgeler/Mikromobilite**
  (`Documents/Mikromobilite`) klasörüne kopyalanır: dosya yöneticisinden açılır, USB ile bilgisayara alınır. Android 10 ve sonrasında
  izin gerekmez; Android 9 ve öncesinde ilk açılışta dosya izni istenir. Daha önceki kayıtlar da uygulama açılınca kopyalanır.
  Kayıtlar sayfasının üstündeki klasör-ok simgesi hepsini yeniden kopyalar.
- Uygulamada başlıktaki **klasör** simgesinden eski kayıtlar tekrar paylaşılabilir, puanlanabilir veya silinebilir
  (uygulamadan silmek Belgeler'deki kopyayı silmez).
- Uygulamanın kendi klasörü: `Android/data/tr.edu.yildiz.kaan_usta/files/kayitlar` (Android 11 ve sonrasında dosya yöneticileri göstermez).

## Kullanılan sensörler

Uygulamada sağ üstteki **ⓘ** simgesine dokununca açılan *Hakkında / Teknik Bilgi* sayfasında da listelenir.

1. **İvmeölçer** – üç eksen ivme (m/s²), ~200 Hz; yerçekimi filtreyle çıkarılır, dikey sarsıntı hesaplanır
2. **GNSS alıcısı** – doğrudan GPS_PROVIDER; konum, GPS Doppler hızı, doğruluk
3. **Fused konum servisi (düzeltilmiş GPS)** – Google'ın birleşik konum servisi
4. **Telefon saati** – zaman damgası

## Ölçüm notları

- Telefon araca **sıkıca** sabitlenmelidir; **açısı önemli değildir** (dikey sarsıntı açıdan bağımsız hesaplanır).
  Gevşek tutucu veya cep/çanta ölçümü bozar. Montaj açısı ana ekranda (EĞİM) görülebilir.
- Yaklaşık 1 sn'den uzun süren hızlanma, fren veya virajlarda yerçekimi yönü tahmini, yatay ivmenin
  yerçekimine oranı kadar kayar (ör. 1 m/s² fren ≈ 6°, 3 m/s² sert fren ≈ 17°). Bu sürede dikey sarsıntı
  %0,5–4 eksik ölçülür ve yatay titreşimin bir kısmı (açının sinüsü kadar, ≈ %10–30) dikeye karışır.
- Kayıt sırasında ekran açık kalır; ekran kilitlenir veya başka uygulamaya geçilirse kayıt **arka planda sürer** (bildirim
  çubuğunda "Sürüş kaydı sürüyor" görünür). Bazı telefonlar (özellikle Samsung) pil tasarrufu için arka plandaki uygulamaları
  kapatabilir: Ayarlar → Uygulamalar → Mikromobilite Veri Aracı → Pil → **Kısıtlanmamış** seçilmesi önerilir.
