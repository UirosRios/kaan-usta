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
| `Enlem`, `Boylam` | Son geçerli GPS konumu (WGS84, derece) |
| `Mantiksal_Hiz_kmh` | 2 km/h altı sıfırlanmış hız |
| `Ham_Hiz_kmh` | GPS'in verdiği ham hız |
| `Z_Ekseni` | O andaki tek Z ivme değeri (m/s², yerçekimi dahil) |
| `Z_Ort` | 0,5 sn penceredeki Z ortalaması (≈ yerçekimi bileşeni) |
| `Z_RMS_Dinamik` | Ortalama çıkarıldıktan sonra RMS → **sarsıntı şiddeti** |
| `Z_Min`, `Z_Max` | Penceredeki en düşük / en yüksek Z |
| `Z_Ornek_Sayisi` | Penceredeki ivmeölçer örneği sayısı (~25 beklenir) |
| `GPS_Dogruluk_m` | GPS yatay doğruluğu (m) |
| `GPS_Yasi_s` | Son GPS konumundan bu yana geçen süre (GPS kesintilerini ayıklamak için) |

## Ölçüm notları

- Telefon gidonda **sabit bir tutucuya, ekranı yukarı bakacak şekilde** yatay monte edilmelidir;
  Z ekseni ekrana diktir, telefon eğik durursa düşey sarsıntı tam ölçülmez.
- Kayıt süresince uygulama **açık ve ön planda** kalmalıdır (ekran otomatik kapanmaz).
