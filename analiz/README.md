# Sürüş analizi betiği

`surus_analizi.py`, uygulamanın kaydettiği CSV dosyalarını analiz eder: GPS gecikmesini düzeltir,
duruşları ayıklar, hıza göre sarsıntı tablosu çıkarır, darbeleri bulur ve uydu görüntüsü üzerinde
gösteren bir harita üretir.

## Kurulum

Python 3.10 veya üstü gerekir. Grafik için matplotlib (isteğe bağlı; yoksa grafik dışındaki her şey yine üretilir):

```
pip install matplotlib
```

## Kullanım

```
python surus_analizi.py mikromobilite_20261023_234304.csv
```

Birden fazla dosya aynı anda verilebilir (`python surus_analizi.py *.csv`). Çıktılar CSV'nin yanındaki
`<ad>_analiz` klasörüne yazılır (`--cikti klasor` ile değiştirilebilir).

| Çıktı | İçerik |
|---|---|
| `<ad>_ozet.txt` | Veri kalitesi, hız aralıklarına göre sarsıntı tablosu, korelasyon, darbe listesi ve Google Haritalar bağlantıları |
| `<ad>_harita.html` | Tarayıcıda açılır: uydu görüntüsü üzerinde güzergâh (renk = Dikey_RMS), darbe noktaları ve konum belirsizlik daireleri. Sağ üstten sokak haritasına geçilebilir. İnternet gerekir. |
| `<ad>_harita.geojson` | Aynı veri, QGIS / ArcGIS için (WGS84) |
| `<ad>_satirlar.csv` | Tüm satırlar: düzeltilmiş konum ve hız, durum (hareket / durus / gps_yok), darbe işareti. Excel ile açılır. |
| `<ad>_olaylar.csv` | Darbeler: konum, belirsizlik, hız, tepe değerler, ait olduğu darbe noktası |
| `<ad>_grafik.png` | Hız, sarsıntı, hız-sarsıntı ilişkisi ve güzergâh |

## Yapılan düzeltmeler

- **GPS gecikmesi (`--gecikme`, varsayılan 1 sn):** Telefonun GPS yongası hız ve konumu yaklaşık 1 sn geç
  bildirir (ilk deneme sürüşünde sarsıntı-hız uyumu 1 sn kaydırınca en yüksek çıktı; durunca sarsıntı
  sıfıra inerken GPS hızı 2-3 sn daha düşmeye devam etti). Her satırın sarsıntısı, bu kadar sonra gelen
  GPS değeriyle eşleştirilir.
- **Konum enterpolasyonu:** GPS saniyede 1 kez güncellenir; 0,5 sn'lik satırların konumu ve hızı iki GPS
  ölçümü arasında doğrusal enterpolasyonla bulunur. Satırın zamanı, özetlediği 0,5 sn'lik pencerenin
  ortası alınır.
- **Duruş ayıklama (`--min-hiz`, varsayılan 3 km/h):** Düzeltilmiş hız bunun altındaysa satır analize
  girmez. Scooter'ı elle çevirme / itme sarsıntıları ve hareketsizken GPS'in gösterdiği sahte 1-2 km/h hız
  bu yolla ayıklanır.

## Darbe tespiti

Bir satırın **tepe değeri** = max(|Dikey_Min|, Dikey_Max). Çevresindeki ±10 sn'lik hareket satırlarının
Dikey_RMS medyanı o yolun "normal" sarsıntısıdır. Tepe değer bunun **4 katını** (`--darbe-orani`) ve
**20 m/s²**'yi (`--darbe-esik`) aşıyorsa satır darbe sayılır (ISO 2631-1'deki tepe faktörü fikri). Art arda
işaretlenen satırlar tek darbe sayılır.

Farklı geçişlerde, merkezine **10 m**'den (`--kume-yaricap`) yakın darbeler aynı **darbe noktası** olarak
gruplanır. Grubun konumu, ölçümlerin GPS doğruluğuyla ağırlıklı ortalamasıdır; aynı noktadan ne kadar çok
geçilirse (özellikle iki yönde) konum o kadar iyileşir.

**Belirsizlik yarıçapı** = GPS doğruluğu, darbenin 0,5 sn'lik pencere içindeki yerinin bilinmemesi ve gecikme
belirsizliğinin (±0,5 sn) birleşimi. Darbenin gerçek yeri büyük olasılıkla bu daire içinde, güzergâh
üzerindedir.

Eşikler ilk denemelere göre seçilmiştir; bilinen çukur / kasis noktalarından geçilen kalibrasyon
sürüşleriyle ayarlanmaları önerilir.
