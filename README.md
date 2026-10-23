# Mikromobilite Sarsıntı Ölçer (Kaan Usta – YTÜ Harita Mühendisliği Tezi)

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

**Yerçekimi giderme ve dikey sarsıntı:** İvmenin üç ekseni de 0,4 Hz kesim frekanslı birinci
dereceden yüksek geçiren filtreden (bilineer/Tustin dönüşümü) geçirilir; 0,4 Hz, ISO 2631-1'in alt
bant sınırıdır. Filtre çıkışı titreşim, ham ivme − titreşim ise yerçekimi vektörüdür (telefonun o anki
"aşağı" yönü). Dikey sarsıntı, titreşim vektörünün yerçekimi yönüne izdüşümüdür; bu sayede telefon
hangi açıda takılırsa takılsın aynı sarsıntı aynı değeri verir. Filtre ilk ~2 saniyede oturur.

## Kayıt dosyaları

- Veriler kayıt sırasında **5 saniyede bir** dosyaya yazılır; uygulama kapanırsa en fazla son 5 saniye kaybolur.
- Her kayıt iki dosyadır: `mikromobilite_<tarih_saat>.csv` (veri) ve `..._bilgi.txt`
  (telefon modeli, Android ve uygulama sürümü, sensör adları/çözünürlük/ölçüm aralığı, ölçüm ayarları).
- Uygulamada başlıktaki **klasör** simgesinden eski kayıtlar tekrar paylaşılabilir veya silinebilir.
- Klasör: `Android/data/tr.edu.yildiz.kaan_usta/files/kayitlar` (USB ile bilgisayardan da erişilebilir).

## Kullanılan sensörler

Uygulamada sağ üstteki **ⓘ** simgesine dokununca açılan *Hakkında / Teknik Bilgi* sayfasında da listelenir.

1. **İvmeölçer** – üç eksen ivme (m/s²), ~200 Hz; yerçekimi filtreyle çıkarılır, dikey sarsıntı hesaplanır
2. **Jiroskop** – X/Y/Z açısal hız (rad/s), ~200 Hz; yalnızca ekranda gösterilir, CSV'ye yazılmaz
3. **GNSS alıcısı** – doğrudan GPS_PROVIDER; konum, GPS Doppler hızı, doğruluk
4. **Fused konum servisi (düzeltilmiş GPS)** – Google'ın birleşik konum servisi
5. **Telefon saati** – zaman damgası

## Ölçüm notları

- Telefon araca **sıkıca** sabitlenmelidir; **açısı önemli değildir** (dikey sarsıntı açıdan bağımsız hesaplanır).
  Gevşek tutucu veya cep/çanta ölçümü bozar. Montaj açısı ana ekranda (EĞİM) görülebilir.
- Yaklaşık 1 sn'den uzun süren hızlanma, fren veya virajlarda yerçekimi yönü tahmini, yatay ivmenin
  yerçekimine oranı kadar kayar (ör. 1 m/s² fren ≈ 6°, 3 m/s² sert fren ≈ 17°). Bu sürede dikey sarsıntı
  %0,5–4 eksik ölçülür ve yatay titreşimin bir kısmı (açının sinüsü kadar, ≈ %10–30) dikeye karışır.
- Kayıt süresince uygulama **açık ve ön planda** kalmalıdır (ekran otomatik kapanmaz).
