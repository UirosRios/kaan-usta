# Mikromobilite Sarsıntı Ölçer (Kaan Usta – YTÜ Harita Mühendisliği Tezi)

Telefonun GPS'i ve ivmeölçeri ile mikromobilite (e-scooter, bisiklet vb.) sürüşünde
**hıza göre Z-ekseni sarsıntısını** ölçüp CSV olarak dışa aktaran Android uygulaması.

## APK'yı indirme

1. GitHub'da depo → **Actions** sekmesi → en son başarılı **"APK Derle"** çalıştırması.
2. Sayfanın altındaki **Artifacts** bölümünden `mikromobilite-apk` dosyasını indirin (zip içinde `app-release.apk`).
3. APK'yı telefona atıp açın ("Bilinmeyen kaynaklardan yükleme" izni istenir).

## CSV sütunları (her 0,5 sn'de bir satır)

| Sütun | Açıklama |
|---|---|
| `Tarih_Saat` | Kayıt zamanı |
| `Enlem`, `Boylam` | Son geçerli ham GPS konumu (WGS84, derece) |
| `Mantiksal_Hiz_kmh` | Ham hızın 2 km/h altı sıfırlanmış hali |
| `Ham_Hiz_kmh` | Doğrudan GPS donanımından ham hız (Doppler, yumuşatma yok) |
| `Duzeltilmis_GPS_Hiz_kmh` | Fused (birleşik) konum servisinin hızı; uygulamada "Düzeltilmiş GPS" |
| `Z_Ekseni` | O andaki tek Z ivme değeri (m/s², yerçekimi dahil) |
| `Z_Ort` | 0,5 sn penceredeki Z ortalaması (≈ yerçekimi bileşeni) |
| `Z_RMS_Dinamik` | Ortalama çıkarıldıktan sonra RMS → **sarsıntı şiddeti** |
| `Z_Min`, `Z_Max` | Penceredeki en düşük / en yüksek Z |
| `Z_Ornek_Sayisi` | Penceredeki ivmeölçer örneği sayısı (~25 beklenir) |
| `GPS_Dogruluk_m` | Ham GPS yatay doğruluğu (m, %68 güven yarıçapı) |
| `GPS_Yasi_s` | Son ham GPS konumundan bu yana geçen süre (GPS kesintilerini ayıklamak için) |
| `Duzeltilmis_GPS_Yasi_s` | Son düzeltilmiş (Fused) konumdan bu yana geçen süre |

## Ölçüm notları

- Telefon gidonda **sabit bir tutucuya, ekranı yukarı bakacak şekilde** yatay monte edilmelidir;
  Z ekseni ekrana diktir, telefon eğik durursa düşey sarsıntı tam ölçülmez.
- Kayıt süresince uygulama **açık ve ön planda** kalmalıdır (ekran otomatik kapanmaz).
