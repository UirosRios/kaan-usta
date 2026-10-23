# Sürüş analizi betiği

`surus_analizi.py`, uygulamanın kaydettiği CSV dosyalarını analiz eder:

- GPS gecikmesini düzeltir ve konumu OpenStreetMap yollarına oturtur.
- Duruşları ayıklar ve hıza göre sarsıntı tablosu çıkarır.
- Darbeleri (çukur vb.) otomatik tespit eder ve uygulamanın sürüş sırasındaki anlık çukur uyarılarıyla karşılaştırır.
- Sonuçları sokak haritası üzerinde, sarsıntıya göre renklendirilmiş bir haritada gösterir.

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
   - **`..._harita.html`** dosyasına çift tıklayın. Tarayıcıda sokak haritası üzerinde güzergâh (yeşil: az, sarı: orta, kırmızı: çok sarsıntı), otomatik bulunan
     darbeler (mor numaralı) ve uygulamanın anlık uyarıları (siyah nokta) açılır. Sağ üstten renkli sokak haritasına veya uydu görüntüsüne geçilebilir. İşaretlere dokununca ayrıntılar
     ve Google Haritalar bağlantısı çıkar.
   - **`..._ozet.txt`** sürüşün özeti: hız-sarsıntı tablosu ve çukur listesi.
   - **`..._grafik.png`** grafikler.
   - **`..._satirlar.csv`** ve **`..._olaylar.csv`** Excel ile açılır.

İnternet gerekir: yollar ilk çalıştırmada OpenStreetMap'ten indirilir ve `..._osm.json` olarak saklanır.
Harita da altlığı internetten yükler. İnternet yoksa betik haritaya oturtmayı atlar, geri kalan her şeyi yapar.

Birden fazla dosya veya kayıtların bulunduğu klasör verilebilir: `python surus_analizi.py *.csv` ya da
`python surus_analizi.py kayitlar`. Tüm ayarları görmek için: `python surus_analizi.py -h`.

Kaydın `_bilgi.txt` dosyası CSV'nin yanındaysa (uygulamanın paylaştığı gibi) scooter ve hava durumu özete eklenir.

## Birden fazla sürüşü birleştirme (yol kalitesi haritası)

Bütün sürüşlerin CSV'lerini (ve `_bilgi.txt` dosyalarını) bir klasöre, örneğin `kayitlar`, koyun ve:
```
python birlestir.py kayitlar
```
`birlesik_analiz` klasöründe:

| Çıktı | İçerik |
|---|---|
| `birlesik_harita.html` | **Yol kalitesi haritası:** 25 m'lik hücreler, renk = hız düzeltmeli sarsıntı indeksi (yeşil düzgün, kırmızı bozuk); yalnızca tek sürüşte geçilen hücreler soluk. Mor işaretler darbe noktaları (dokununca kaç farklı sürüşte görüldüğü). |
| `birlesik_ozet.txt` | Sürüşler (scooter, hava durumu), en bozuktan en düzgüne sokaklar, en az 2 sürüşte tekrar eden darbe noktaları |
| `birlesik_sokaklar.csv` | Sokak sıralaması: sürüş sayısı, yol, medyan hız ve sarsıntı, indeks, 100 m başına darbe |
| `birlesik_suruslar.csv` | Sürüş listesi |
| `birlesik_darbeler.csv` | Darbe noktaları, kaç sürüşte ve hangi sürüşlerde görüldükleri |
| `birlesik_hucreler.geojson` | Hücreler, QGIS / ArcGIS için |

`--tek-tek` eklenirse her sürüşün ayrı analizi de bu klasöre yazılır.

## Çıktılar

| Çıktı | İçerik |
|---|---|
| `_ozet.txt` | Veri kalitesi, haritaya oturtma, hıza göre sarsıntı tablosu, uygulamanın anlık uyarıları, otomatik darbeler |
| `_harita.html` | Sokak haritası üzerinde güzergâh. Renk Dikey_RMS'ye göre sabit sınıflardır (0-2-4-6-8-10 m/s²: koyu yeşilden koyu kırmızıya); böylece farklı sürüşler karşılaştırılabilir. Renk, tek tük tepeler sokağı alacalı göstermesin diye ±1 sn'lik kayan medyanla hesaplanır. Darbe noktaları, uygulama uyarıları ve konum belirsizliği daireleri. Katman menüsünden renkli sokak haritası, uydu görüntüsü ve oturtma öncesi ham GPS seçilebilir. |
| `_harita.geojson` | Aynı veri, QGIS / ArcGIS için (WGS84) |
| `_satirlar.csv` | Tüm satırlar: oturtulmuş ve ham konum, düzeltilmiş hız, durum (hareket / durus / gps_yok), uygulama uyarısı ve darbe işaretleri |
| `_isaretler.csv` | Yalnızca eski sürümün çukur butonuyla yapılmış kayıtlar için: basışlar ve eşleşen çukurlar |
| `_olaylar.csv` | Otomatik bulunan darbeler ve gruplandıkları noktalar |
| `_sokaklar.csv` | Sokaklara göre sarsıntı: yol, medyan hız ve Dikey_RMS, hız düzeltmeli indeks, darbe sayısı (en bozuktan en düzgüne) |
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
- **Ölçüt:** Tepe değer = max(|Dikey_Min|, Dikey_Max). Yolun "normal" sarsıntısı (taban): önceki 10 sn ve sonraki 10 sn'lik hareket
  satırlarının Dikey_RMS medyanlarından büyük olanı. Tepe bunun 4 katını (`--darbe-orani`) ve 10 m/s²'yi (`--darbe-esik`)
  aşıyorsa satır darbe sayılır. İki yana ayrı bakmak, düzgünden bozuk zemine geçerken bozuk kısmın sıradan tepelerinin
  "darbe" sayılmasını önler. Bir ödünleşimdir; simülasyonda ±10 sn tek medyana göre:

  | | Tek medyan (`--darbe-taban ortak`) | İki yan (varsayılan) |
  |---|---|---|
  | Yanlış alarm, sürüş başına | 4,0–7,2 | 1,8–3,6 |
  | Çukur bulma oranı (asfalt dışı senaryolar) | %67–85 | %65–73 (5–12 puan düşük) |
  | Asfalt, iyi GPS | %100, 0,2 yanlış | aynı |

  Bütün çukurları yakalamak, yanlış alarmdan önemliyse `--darbe-taban ortak` kullanın.
- **Gruplama:** Farklı geçişlerde, merkezine 10 m'den (`--kume-yaricap`) yakın darbeler / çukurlar aynı nokta olarak gruplanır.
  Aynı yerden ne kadar çok, özellikle iki yönde geçilirse konum o kadar iyileşir.

**Sokaklara göre özet ve hız düzeltmeli indeks:**
- **Sokak:** Satırlar haritaya oturtulduğu OpenStreetMap yoluna göre gruplanır (oturtma yoksa tek grup "yol dışı").
- **Neden düzeltme:** Sarsıntı hem yüzeye hem hıza bağlıdır. Bozuk sokakta yavaş, düzgün sokakta hızlı gidildiyse ham
  ortalamalar yüzey farkını gizler.
- **Hıza bağlılığın tahmini:** Aynı 25 m'lik hücreden farklı hızlarla geçişlerden tahmin edilir (RMS ∝ hız^b; hücre
  içinde yüzey sabit kabul edilir).
- **İndeks:** Her ölçüm 15 km/h'e çevrilir; sokağın ya da hücrenin medyanıdır.
- **Sınır:** GPS hız gürültüsü b'yi biraz düşük tahmin ettirir; simülasyonda gerçek 0,8 iken 0,5 bulundu. İndeks hız
  farkını eksik düzeltir, ama sokak sıralaması doğru çıktı. Veri yetersizse (aynı yerden yeterince farklı hızda
  geçilmemişse) düzeltme yapılmaz, medyan RMS kullanılır.

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
python simulasyon.py --birlesik ornek_birlesik   # yüzeyi bilinen sokaklarda 3 sürüş üret ve birleştir
```

Birleştirme doğrulamasında (Ana Cadde'nin yarısı parke, yarısı asfalt; 3. Sokak arnavut kaldırımı) sokak sıralaması ve
indeksler gerçekle uyuştu (3. Sokak 8,8 / gerçek 9,0 m/s²); tekrar eden 3 darbe noktasının üçü de gerçek kusurdu (2-3 m içinde).
Arnavut kaldırımındaki çukur zeminden ayırt edilemedi (bilinen fiziksel sınır).

Son sonuçlar ve örnek çıktı: [ornek/simulasyon_raporu.md](ornek/simulasyon_raporu.md), `ornek/` klasörü.
Örnek sürüş yapaydır. Yolları gerçek bir yere ait değildir; harita altlığı yalnızca arka plandır.
