# Karşılaştırma raporu: Claude ↔ sürücü

- Veri: veri/ dışında (bekçiler UYGULANMADI; resmî sonuç değildir); günler: ornek_20261120
- Algoritma sürümü: yer tutucu (algoritma henüz yok)
- ornek_20261120_claude.gpkg içerik özeti: `46683abe414988cc12c9f524056c77718b79c3ddbbb9a86cc9816b155e41c263`
- Seçilen eşik: henüz seçilmedi

## Kural

- Konum: iki nokta da ham GPS izinde t_s anına doğrusal ara değer. Dosyalardaki konumlar bu kurala uyuyor (en büyük fark 0,2 mm).
- Eşleştirme: aynı kayıt içinde, bire bir, en yakın çift önce, mesafe ≤ eşik.
- Doğru = eşleşen işaret; kaçırılan = eşleşmeyen işaret; fazladan = eşleşmeyen Claude noktası.
- Duyarlılık = doğru / işaret sayısı; kesinlik = doğru / Claude noktası sayısı.
- Dışlanan: ekran / telefon tuşu işaretleri (0), onlara 1 sn'den yakın Claude noktaları (0), konumu olmayan işaretler (0).

## Sonuç

İşaret: 6, Claude noktası: 7

| Eşik | Doğru | Kaçırılan | Fazladan | Duyarlılık | Kesinlik |
|---|---|---|---|---|---|
| 5,0 m | 1 | 5 | 6 | %17 | %14 |
| 10,0 m | 4 | 2 | 3 | %67 | %57 |
| 15,0 m | 4 | 2 | 3 | %67 | %57 |

## Eşik kararı için

- GPS doğruluğu (`dogruluk_m`, hareket halindeki noktalar, m): en küçük 3,8, ortanca 4,6, %68 5,0, %90 5,9, %95 6,2, en büyük 7,3 (n = 297)
- Her işaretin aynı kayıttaki en yakın Claude noktasına uzaklığı (m): en küçük 4,3, ortanca 6,5, %68 12,2, %90 51,0, %95 66,5, en büyük 82,0 (n = 6)
- Aynı çiftlerde zaman farkı, basış − darbe (s; eksi: basış darbeden önce): en küçük -23,37, ortanca 1,22, %68 1,28, %90 1,41, %95 1,43, en büyük 1,45 (n = 6)
- İşaret anındaki hız (km/h): en küçük 10,2, ortanca 15,8, %68 16,1, %90 16,7, %95 17,0, en büyük 17,2 (n = 6)
- Not: işaret ve Claude noktası aynı GPS izinden konum aldığı için GPS'in kendi hatası büyük ölçüde sadeleşir; mesafeyi çoğunlukla basış gecikmesi × hız belirler.

## Kayıt başına

Doğru sütunu 10,0 m eşikle.

| Kayıt | Kesit | Ad | İşaret | Claude | Doğru | İnsan puanı | Claude puanı |
|---|---|---|---|---|---|---|---|
| 20261120_101502 | K01 | Kuzey yolu | 2 | 2 | 2 | 4 | 4 |
| 20261120_101940 | K01 | Kuzey yolu | 1 | 1 | 1 | 4 | 4 |
| 20261120_102615 | K02 | Parke yol | 2 | 2 | 0 | 2 | 2 |
| 20261120_103405 | K03 |  | 1 | 1 | 1 | hatirlamiyorum | 3 |
| 20261120_103730 | K03 |  | 0 | 1 | 0 | 3 | 3 |

## Konfor puanı

Puanlanmış 4 kayıtta: tam uyum 4 (%100), ±1 içinde 4 (%100), ortalama mutlak fark 0,00 puan.
