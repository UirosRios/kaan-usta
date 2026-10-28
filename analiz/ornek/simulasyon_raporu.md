# Simülasyon sonuçları

Her senaryo 12 kez (farklı rastgele GPS hatası, sürücü tepkisi, zemin) çalıştırıldı.
Güzergâh: 300 m cadde, 2 tur ileri-geri (her çukurdan 4 geçiş, iki yönde), ~15 km/h.
Konum hataları metre; "ham": gecikme düzeltmeli ham GPS, "oturtulmuş": haritaya oturtma sonrası.

- **Satır konum hatası:** sarsıntının ölçüldüğü andaki gerçek konuma uzaklık (medyan / %95).
- **İşaretli çukur: doğru an:** basışların yüzde kaçı doğru çukurun 0,5 sn'lik penceresiyle eşleşti. "yanlış an": başka bir tepe seçildi; "belirsiz": betik emin olmadığını söyledi ve yaklaşık konum verdi; "eşleşmedi": belirgin tepe yok / GPS yok.
- **Çukur yer hatası:** doğru eşleşen tek basışların gerçek çukura uzaklığı.
- **Çok geçişli çukur noktası hatası:** en az 2 geçişte işaretlenip gruplanan çukur noktalarının gerçek çukura uzaklığı.
- **Otomatik tespit duyarlılığı:** çukur geçişlerinin yüzde kaçında otomatik darbe bulundu. **Yanlış alarm:** hiçbir kusura (çukur / rögar) denk gelmeyen darbe sayısı.
- **Yanlış basışın eşleşmesi:** çukur yokken basılan butonun bir tepeyle eşleştirildiği durum / yanlış basış sayısı.

| Senaryo | Satır konum hatası, medyan / %95 (ham → oturtulmuş) | İşaretli çukur: doğru an | Çukur yer hatası, medyan (ham → oturtulmuş) | Çok geçişli çukur noktası hatası | Otomatik tespit duyarlılığı | Yanlış alarm (sürüş başına) | Yanlış basışın eşleşmesi |
|---|---|---|---|---|---|---|---|
| 1. Asfalt, açık alan, iyi GPS | 3.6 / 7.4 → 2.0 / 5.9 | %100 (144/144; yanlış an 0, belirsiz 0, eşleşmedi 0) | 3.3 → 1.7 | 0.8 (n=36) | %100 | 0.2 | 0/0 |
| 2. Parke, bina arası: kötü GPS + yansıma sapması | 8.9 / 18.2 → 4.6 / 14.3 | %78 (112/144; yanlış an 0, belirsiz 26, eşleşmedi 6) | 8.5 → 4.6 | 2.8 (n=34) | %69 | 2.2 | 0/0 |
| 3. 15 m arayla paralel iki sokak | 7.2 / 14.6 → 4.5 / 15.1 | %82 (118/144; yanlış an 1, belirsiz 22, eşleşmedi 3) | 7.2 → 4.7 | 3.7 (n=32) | %73 | 2.8 | 0/0 |
| 4. Haritada yolu olmayan meydan | 6.0 / 12.1 → 3.8 / 14.9 | %76 (145/192; yanlış an 1, belirsiz 45, eşleşmedi 1) | 6.6 → 9.7 | 15.1 (n=38) | %69 | 2.7 | 0/0 |
| 5. Arnavut kaldırımı, küçük çukurlar | 5.7 / 11.9 → 3.3 / 9.2 | %10 (15/144; yanlış an 23, belirsiz 82, eşleşmedi 24) | 7.6 → 5.2 | 3.9 (n=10) | %2 | 3.6 | 0/0 |
| 6. Zor sürücü: geç basma, unutma, yanlış basış, 3 m arayla iki çukur | 5.7 / 11.7 → 3.2 / 9.8 | %59 (78/133; yanlış an 3, belirsiz 40, eşleşmedi 12) | 6.2 → 3.1 | 1.6 (n=24) | %66 | 1.8 | 7/21 |
| 7. GPS kesintisi (40 m alt geçit, çukur içinde) | 4.9 / 10.5 → 2.8 / 8.5 | %67 (96/144; yanlış an 0, belirsiz 0, eşleşmedi 48) | 4.8 → 2.7 | 0.7 (n=25) | %67 | 0.1 | 0/0 |
| 8. Gerçek GPS gecikmesi 2 sn (betik 1 sn varsayar) | 7.7 / 15.3 → 5.2 / 13.3 | %72 (103/144; yanlış an 1, belirsiz 38, eşleşmedi 2) | 7.7 → 6.1 | 5.4 (n=33) | %65 | 2.2 | 0/0 |
| 9. Duraklama + kalkış (U dönüşlerinde ve ortada durma) | 5.8 / 12.0 → 3.3 / 9.4 | %73 (105/144; yanlış an 3, belirsiz 32, eşleşmedi 4) | 5.3 → 3.3 | 2.7 (n=31) | %69 | 2.6 | 0/0 |
| 10. Bina arası: 15 m yansıma sapması, telefon doğruluğu ~3 m bildirir | 12.0 / 21.7 → 4.2 / 20.8 | %76 (110/144; yanlış an 3, belirsiz 30, eşleşmedi 1) | 15.4 → 3.7 | 2.8 (n=30) | %73 | 3.4 | 0/0 |
