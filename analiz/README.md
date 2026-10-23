# Sürüş analizi betiği

`surus_analizi.py`, uygulamanın kaydettiği CSV dosyalarını analiz eder:

- GPS gecikmesini düzeltir ve konumu OpenStreetMap yollarına oturtur.
- Duruşları ayıklar ve hıza göre sarsıntı tablosu çıkarır.
- Darbeleri (çukur vb.) otomatik tespit eder ve uygulamanın sürüş sırasındaki anlık çukur uyarılarıyla karşılaştırır.
- Sonuçları uydu görüntüsü üzerinde bir haritada gösterir.

## Adım adım kullanım (Windows)

**Bir kez yapılacaklar**

1. **Python'u kurun:** <https://www.python.org/downloads/> adresinden indirin. Kurulumun ilk ekranında
   **"Add python.exe to PATH"** kutusunu işaretleyin.
2. **Betiği indirin:** GitHub'da depo sayfasında **Code → Download ZIP**'e tıklayın, ZIP'i açın.
   İçindeki `analiz` klasörünü kolay bulacağınız bir yere kopyalayın, örneğin `Belgeler\analiz`.
3. **Grafik kütüphanesini kurun (isteğe bağlı):** Başlat menüsünde **cmd** yazıp **Komut İstemi**'ni açın ve şunu yazın:
   ```
   pip install matplotlib
   ```
   Kurmazsanız grafik dışındaki her şey yine üretilir.

**Her sürüşten sonra**

4. **Dosyaları bilgisayara alın:** Telefonda uygulamanın **Kayıtlar** sayfasından CSV'yi paylaşın (e-posta, Drive vb.) ya da
   telefonu USB ile bağlayıp `Android/data/tr.edu.yildiz.kaan_usta/files/kayitlar` klasöründen kopyalayın.
   CSV'yi `analiz` klasörüne koyun.
5. **Betiği çalıştırın:** `analiz` klasöründe adres çubuğuna tıklayın, **cmd** yazıp Enter'a basın. Açılan pencerede
   (dosya adını kendi dosyanızınkiyle değiştirin):
   ```
   python surus_analizi.py mikromobilite_20261023_234304.csv
   ```
   İpucu: `python surus_analizi.py ` yazdıktan sonra CSV dosyasını pencereye sürükleyip bırakırsanız adı kendiliğinden yazılır.
6. **Sonuçlara bakın:** CSV'nin yanında `mikromobilite_..._analiz` klasörü oluşur.
   - **`..._harita.html`** dosyasına çift tıklayın. Tarayıcıda uydu görüntüsü üzerinde güzergâh, otomatik bulunan
     darbeler (turuncu numaralı) ve uygulamanın anlık uyarıları (kırmızı nokta) açılır. İşaretlere dokununca ayrıntılar
     ve Google Haritalar bağlantısı çıkar.
   - **`..._ozet.txt`** sürüşün özeti: hız-sarsıntı tablosu ve çukur listesi.
   - **`..._grafik.png`** grafikler.
   - **`..._satirlar.csv`** ve **`..._olaylar.csv`** Excel ile açılır.

İnternet gerekir: yollar ilk çalıştırmada OpenStreetMap'ten indirilir ve `..._osm.json` olarak saklanır.
Harita da uydu görüntüsünü internetten yükler. İnternet yoksa betik haritaya oturtmayı atlar, geri kalan her şeyi yapar.

Birden fazla dosya aynı anda verilebilir: `python surus_analizi.py *.csv`. Tüm ayarları görmek için: `python surus_analizi.py -h`.

## Çıktılar

| Çıktı | İçerik |
|---|---|
| `_ozet.txt` | Veri kalitesi, haritaya oturtma, hıza göre sarsıntı tablosu, uygulamanın anlık uyarıları, otomatik darbeler |
| `_harita.html` | Uydu görüntüsü üzerinde güzergâh (renk = Dikey_RMS). İşaretli çukurlar, basış yerleri, darbe noktaları ve konum belirsizliği daireleri. Katman menüsünden oturtma öncesi ham GPS de gösterilebilir. |
| `_harita.geojson` | Aynı veri, QGIS / ArcGIS için (WGS84) |
| `_satirlar.csv` | Tüm satırlar: oturtulmuş ve ham konum, düzeltilmiş hız, durum (hareket / durus / gps_yok), uygulama uyarısı ve darbe işaretleri |
| `_isaretler.csv` | Yalnızca eski sürümün çukur butonuyla yapılmış kayıtlar için: basışlar ve eşleşen çukurlar |
| `_olaylar.csv` | Otomatik bulunan darbeler ve gruplandıkları noktalar |
| `_grafik.png` | Hız, sarsıntı (otomatik darbeler işaretli), hız-sarsıntı ilişkisi, güzergâh |
| `_osm.json` | İndirilen yol verisi (önbellek) |

## Yöntem

**GPS gecikmesi (`--gecikme`, varsayılan 1 sn):**
- **Sorun:** Telefonun GPS yongası hız ve konumu yaklaşık 1 sn geç bildirir. İlk deneme sürüşünde sarsıntı-hız uyumu
  1 sn kaydırınca en yüksek çıktı; durunca sarsıntı sıfıra inerken GPS hızı 2-3 sn daha düşmeye devam etti.
- **Düzeltme:** Her satırın sarsıntısı bu kadar sonra gelen GPS değeriyle eşleştirilir. Satırın zamanı, özetlediği 0,5 sn'lik
  pencerenin ortası alınır. GPS saniyede 1 kez geldiği için aradaki konumlar doğrusal enterpolasyonla bulunur.

**Haritaya oturtma (`haritaya_oturtma.py`):**
- **Yöntem:** Gizli Markov modeli ve Viterbi algoritması (Newson ve Krumm, 2009). Her GPS noktasının yakınındaki yollar aday konumdur.
  En olası aday dizisi iki ölçüte göre seçilir:
  - noktanın yola uzaklığı (GPS doğruluğuna göre),
  - iki nokta arasındaki yol mesafesinin düz mesafeye yakınlığı.
- **Yol dışı:** Scooter her zaman haritadaki bir yolda gitmediği için (meydan, park, haritada olmayan geçit) her noktaya bir de
  "yol dışı" adayı eklenir. En yakın yol 2,5 sigma'dan uzaksa (`--yol-disi-ceza`) nokta olduğu yerde kalır.
- **Sınır:** Yalnızca yana doğru hata düzelir; yol boyunca ileri-geri hata kalır.

**Duruş:**
- Düzeltilmiş hız 3 km/h'in altındaysa (`--min-hiz`) satır analize girmez. Scooter'ı elle çevirme / itme sarsıntıları ve
  hareketsizken GPS'in gösterdiği sahte 1-2 km/h hız bu yolla ayıklanır.

**Uygulamanın anlık uyarıları (`Cukur` sütunu):** Uygulama sürüş sırasında yalnızca geçmişi bildiği için basit bir sabit eşik
kullanır (tepe ≥ 35 m/s², GPS hızı ≥ 3 km/h). Betik bu uyarıları kendi tespitiyle karşılaştırır (özet ve haritada ayrı katman).

**Eski çukur butonu (`Isaret` sütunu, yalnızca eski kayıtlar):** Uygulamanın önceki sürümünde sürücü çukurdan sonra butona basıyordu;
bu kayıtlar hâlâ analiz edilebilir. Basılan satır ve sonraki 0,5 sn (`--isaret-dislama`) analize girmez. Her basışta, basıştan önceki 5 sn'deki (`--isaret-arama`) hareket satırları içinden tepe
değeri çevresindeki sarsıntıya göre en büyük olan aranır. Bir önceki basıştan öncesine bakılmaz. Sonuç şunlardan biridir:
- **eşleşti:** Tepe, çevre RMS'nin en az 3 katı (`--isaret-min-oran`) ve başka bir anda buna yakın (en az %80'i,
  `--isaret-belirsiz`) bir tepe yok. Çukurun anı ±0,25 sn hassasiyetle bilinir.
- **belirsiz:** Zemin de çukur kadar sarsıyor (örneğin arnavut kaldırımı). Konum, bu sürüşteki tipik tepki süresi
  kadar önceye göre **yaklaşık** verilir (haritada kesikli "Ç?").
- **belirgin tepe yok**, **GPS kesintisi**, **hareket yok:** Yaklaşık konum yine verilir (GPS varsa).

**Otomatik darbe tespiti:**
- **Ölçüt:** Tepe değer = max(|Dikey_Min|, Dikey_Max). Çevresindeki ±10 sn'lik hareket satırlarının Dikey_RMS medyanı o yolun
  "normal" sarsıntısıdır. Tepe bunun 4 katını (`--darbe-orani`) ve 10 m/s²'yi (`--darbe-esik`) aşıyorsa satır darbe sayılır.
- **Gruplama:** Farklı geçişlerde, merkezine 10 m'den (`--kume-yaricap`) yakın darbeler / çukurlar aynı nokta olarak gruplanır.
  Aynı yerden ne kadar çok, özellikle iki yönde geçilirse konum o kadar iyileşir.

**Belirsizlik:** GPS doğruluğu, darbenin 0,5 sn'lik pencere içindeki yeri (±0,25 sn) ve gecikme belirsizliğinin (±0,5 sn)
birleşimidir (~%68). Yola oturtulmuş noktalarda yalnızca yol boyunca bileşen verilir.

## Simülasyonla doğrulama

`simulasyon.py`, gerçeği bilinen yapay sürüşler üretir ve analiz betiğinin sonuçlarını bu gerçekle karşılaştırır.
Simülasyon eski çukur butonunu da içerir. Haritaya oturtma ve otomatik darbe tespiti sonuçları butondan bağımsızdır.
Ürettikleri:
- yapay yol ağı,
- 125 Hz ivme sinyali (zemin, çukur, rögar, dokunma etkisi, uygulamadaki filtre),
- zamanla ilişkili hatası, yansıma sapması, gecikmesi ve kesintisi olan GPS,
- gecikmeli basan, bazen unutan, bazen yanlış basan bir sürücü.

```
python simulasyon.py                       # 9 senaryo x 12 tekrar, sonuç tablosu
python simulasyon.py --ornek ornek         # ayrıca örnek sürüş ve tüm analiz çıktıları
```

Son sonuçlar ve örnek çıktı: [ornek/simulasyon_raporu.md](ornek/simulasyon_raporu.md), `ornek/` klasörü.
Örnek sürüş yapaydır. Yolları gerçek bir yere ait değildir; uydu görüntüsü yalnızca altlıktır.
