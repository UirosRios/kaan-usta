# Mikromobilite Sarsıntı Ölçer (Kaan Usta – YTÜ Harita Mühendisliği Tezi)

Telefonun GPS'i ve ivmeölçeri ile mikromobilite (e-scooter, bisiklet vb.) sürüşünde
**hıza göre dikey sarsıntıyı** ölçüp CSV olarak dışa aktaran Android uygulaması.

## APK'yı indirme

1. GitHub'da depo → **Actions** sekmesi → en son başarılı **"APK Derle"** çalıştırması.
2. Sayfanın altındaki **Artifacts** bölümünden `mikromobilite-apk` dosyasını indirin (zip içinde `app-release.apk`).
3. APK'yı telefona atıp açın ("Bilinmeyen kaynaklardan yükleme" izni istenir).

## CSV sütunları (her 0,5 sn'de bir satır)

| Sütun | Açıklama |
|---|---|
| `Tarih_Saat` | Kayıt zamanı |
| `Enlem`, `Boylam` | Son geçerli ham GPS konumu (WGS84, derece) |
| `Ham_Hiz_kmh` | Doğrudan GPS donanımından ham hız (Doppler, yumuşatma yok) |
| `Duzeltilmis_GPS_Hiz_kmh` | Fused (birleşik) konum servisinin hızı; uygulamada "Düzeltilmiş GPS" |
| `Dikey_Net` | O andaki dikey sarsıntı (m/s²): titreşimin gerçek düşey yöndeki bileşeni, telefonun montaj açısından bağımsız |
| `Dikey_RMS` | Penceredeki dikey sarsıntının RMS'i → **ana sarsıntı şiddeti ölçüsü** |
| `Dikey_Min`, `Dikey_Max` | Penceredeki en düşük / en yüksek dikey sarsıntı (darbe tepe değerleri) |
| `Toplam_RMS` | Üç eksen titreşim vektörünün RMS büyüklüğü (dikey + yatay), yönden bağımsız |
| `Egim_derece` | Penceredeki ortalama telefon eğimi: Z ekseni ile düşey arasındaki açı (ekran yukarı ve yatayken 0°) |
| `Z_Net` | O andaki yerçekimi çıkarılmış Z ivmesi (m/s²), yalnızca telefonun kendi Z ekseni |
| `Z_Ham` | O andaki ham Z ivmesi (m/s², yerçekimi dahil) |
| `Z_Ham_Ort` | 0,5 sn penceredeki ham Z ortalaması (≈ yerçekiminin Z bileşeni; telefon eğildikçe 9,81'den küçülür) |
| `Z_Net_RMS` | Penceredeki yerçekimi çıkarılmış Z'nin RMS'i (telefon yatayken `Dikey_RMS` ile aynı) |
| `Z_Net_Min`, `Z_Net_Max` | Penceredeki en düşük / en yüksek yerçekimsiz Z (darbe tepe değerleri) |
| `Ivme_Ornek_Sayisi` | Penceredeki ivmeölçer örneği sayısı (~200 Hz istenir → ~100 beklenir; telefon daha yavaş veriyorsa daha az) |
| `Jiro_X_Ort`, `Jiro_Y_Ort`, `Jiro_Z_Ort` | Penceredeki ortalama açısal hız (rad/s); ekran yukarı, üst kenar ileri takılıysa X = öne/arkaya eğilme, Y = yana yatma, Z = sağa/sola dönüş |
| `Jiro_Max_Bileske` | Penceredeki en büyük bileşke açısal hız √(x²+y²+z²) (rad/s). Jiroskop yoksa jiroskop sütunları boş kalır |
| `GPS_Dogruluk_m` | Ham GPS yatay doğruluğu (m, %68 güven yarıçapı) |
| `GPS_Yasi_s` | Son ham GPS konumundan bu yana geçen süre (GPS kesintilerini ayıklamak için) |
| `Duzeltilmis_GPS_Yasi_s` | Son düzeltilmiş (Fused) konumdan bu yana geçen süre |

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

1. **İvmeölçer** – Z ekseni ivmesi (m/s²), ~200 Hz; yerçekimi filtreyle çıkarılır
2. **Jiroskop** – X/Y/Z açısal hız (rad/s), ~200 Hz
3. **GNSS alıcısı (ham GPS)** – doğrudan GPS_PROVIDER; konum, Doppler hızı, doğruluk
4. **Fused konum servisi (düzeltilmiş GPS)** – Google'ın birleşik konum servisi
5. **Telefon saati** – zaman damgası

## Ölçüm notları

- Telefon araca **sıkıca** sabitlenmelidir; **açısı önemli değildir** (dikey sarsıntı açıdan bağımsız hesaplanır).
  Gevşek tutucu veya cep/çanta ölçümü bozar. Montaj açısı `Egim_derece` sütununa yazılır.
- Yaklaşık 1 sn'den uzun süren hızlanma, fren veya virajlarda yerçekimi yönü tahmini, yatay ivmenin
  yerçekimine oranı kadar kayar (ör. 1 m/s² fren ≈ 6°, 3 m/s² sert fren ≈ 17°). Bu sürede dikey sarsıntı
  %0,5–4 eksik ölçülür ve yatay titreşimin bir kısmı (açının sinüsü kadar, ≈ %10–30) dikeye karışır.
- Kayıt süresince uygulama **açık ve ön planda** kalmalıdır (ekran otomatik kapanmaz).
