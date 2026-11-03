import 'package:flutter/material.dart';
import 'device_info.dart';

// Hakkında / Teknik Bilgi sayfası: kullanılan sensörler ve ölçüm yöntemi
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9ECEF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF003366),
        foregroundColor: Colors.white,
        title: const Text('Hakkında / Teknik Bilgi'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _InfoCard(
            title: 'UYGULAMA',
            lines: [
              'Mikromobilite Veri Aracı: mikromobilitede (e-scooter, bisiklet vb.) hıza göre sarsıntı ölçümü.',
              'YTÜ Harita Mühendisliği tez çalışması - Kaan Usta.',
            ],
          ),
          const _SectionTitle('BU CİHAZ'),
          // Telefonun modeli ve sensörlerinin özellikleri (her kaydın _bilgi.txt dosyasına da yazılır)
          FutureBuilder<Map<String, dynamic>>(
            future: DeviceInfo.load(),
            builder: (context, snapshot) => _InfoCard(
              title: 'Cihaz ve sensör özellikleri',
              lines: snapshot.hasData ? DeviceInfo.describe(snapshot.data!) : const ['Yükleniyor...'],
            ),
          ),
          const _SectionTitle('KULLANILAN SENSÖRLER'),
          const _InfoCard(
            title: '1. İvmeölçer (sarsıntı)',
            lines: [
              'Ölçtüğü: Üç eksendeki ivme (X, Y, Z), m/s². Ham değere yerçekimi dahildir; telefon düz dururken Z ≈ 9,81.',
              'Yerçekimi giderme: her eksen 0,4 Hz kesim frekanslı birinci dereceden yüksek geçiren filtreden (bilineer dönüşüm) geçirilir (0,4 Hz = ISO 2631-1 alt bant sınırı). Filtre çıkışı titreşimdir; ham ivme − titreşim = yerçekimi, yani telefonun o anki "aşağı" yönü. Filtre ilk ~2 saniyede oturur.',
              'DİKEY SARSINTI: titreşimin gerçek düşey yöndeki bileşeni. Telefon hangi açıda takılırsa takılsın aynı sarsıntı aynı değeri verir.',
              'TOPLAM: üç eksendeki titreşimin büyüklüğü (dikey + yatay), yönden bağımsız.',
              'EĞİM: telefonun yataydan eğimi (ekran yukarı ve yatayken 0°).',
              'Örnekleme: ~200 Hz istenir (5 ms; kısa çukur darbelerinin tepesi kaçmasın diye). Gerçek sayı CSV\'de Ivme_Ornek_Sayisi (~100 / 0,5 sn beklenir); telefonun verebildiği en yüksek hız BU CİHAZ bölümünde.',
              'TOPLAM ve EĞİM yalnızca ekranda gösterilir, CSV\'ye yazılmaz.',
              'CSV: Dikey_RMS, Dikey_Min, Dikey_Max, Ivme_Ornek_Sayisi',
            ],
          ),
          const _InfoCard(
            title: '2. GNSS alıcısı (GPS Doppler hızı)',
            lines: [
              'Doğrudan GPS donanımı okunur (Android GPS_PROVIDER); yumuşatma yapılmaz. Yonga destekliyorsa GLONASS, Galileo ve BeiDou da kullanılır.',
              'Hız, uydu sinyalinin Doppler kaymasından ölçülür. Konum çoğu telefonda saniyede 1 kez gelir.',
              'Ekranda: GPS DOPPLER HIZI, KOORDİNATLAR, Doğruluk, HARİTA',
              'CSV: Enlem, Boylam, GPS_Doppler_Hiz_kmh, GPS_Dogruluk_m. Son konum 3 sn\'den eskiyse (GPS kesildiyse) bu hücreler boş bırakılır.',
            ],
          ),
          const _InfoCard(
            title: '3. Fused konum servisi (düzeltilmiş GPS)',
            lines: [
              'Sensör değil, Google\'ın yazılım servisi: GPS\'i Wi-Fi, baz istasyonu ve olası hareket sensörleriyle harmanlar ve yumuşatır.',
              'Ekranda: DÜZELTİLMİŞ GPS',
              'CSV: Duzeltilmis_GPS_Hiz_kmh',
            ],
          ),
          const _InfoCard(
            title: '4. Telefonun saati',
            lines: [
              'CSV\'deki Tarih_Saat telefonun sistem saatinden gelir (uydu saati değildir).',
            ],
          ),
          const _InfoCard(
            title: 'Harita',
            lines: [
              'Esri Light Gray Canvas altlık haritası (açık gri, sokak adlarıyla; flutter_map). Mavi nokta o anki GPS konumu (doğrudan GPS donanımından), açık mavi daire GPS doğruluğu (yarıçap = doğruluk, m).',
              'Harita konumu kendisi takip eder; iki parmakla veya çift dokunarak yakınlaştırılabilir.',
              'Harita karoları internetten yüklenir; ölçümü ve kaydı etkilemez.',
            ],
          ),
          const _SectionTitle('KAYIT YÖNTEMİ'),
          const _InfoCard(
            title: 'Örnekleme ve filtreler',
            lines: [
              'Her 0,5 saniyede bir CSV satırı yazılır (saniyede 2 satır).',
              'CSV Türkçe Excel biçimindedir: sütunlar noktalı virgülle (;), ondalıklar virgülle (,) ayrılır.',
              'Dikey sarsıntı için o 0,5 sn içindeki tüm örneklerin (~100) istatistiği alınır.',
              'Dikey_RMS: dikey sarsıntının pencere içindeki RMS\'i = ana sarsıntı şiddeti ölçüsü.',
              'Dikey_Min / Dikey_Max: pencere içindeki en büyük aşağı / yukarı darbe.',
              'Doğruluğu 50 m\'den kötü GPS konumları atılır.',
            ],
          ),
          const _InfoCard(
            title: 'Anlık çukur uyarısı',
            lines: [
              'Yalnızca Ayarlar\'da "Otomatik çukur uyarısı" seçiliyse: kayıt sırasında 0,5 sn içindeki en büyük dikey ivme 35 m/s²\'yi aşarsa ve GPS hızı 3 km/h\'in üstündeyse sarsıntı kartı 1,5 sn kırmızı yanar ve uygulama sesli uyarı verir.',
              'Diğer modlarda uyarı gösterilmez ama tespit yine CSV\'ye yazılır (sürücünün işaretleriyle karşılaştırma için).',
              'O satırın CSV\'deki Cukur sütununa 1 yazılır. Kartın altındaki UYARI sayısı bu kayıttaki uyarı sayısıdır.',
              'Uyarı yalnızca en sert darbeleri gösterir; ayrıntılı darbe tespiti analiz betiğiyle yapılır.',
            ],
          ),
          const _InfoCard(
            title: 'Çukur işareti (doğrulama)',
            lines: [
              'Ayarlar\'da "Çukurları ben işaretlerim" seçiliyse (varsayılan) kayıt sırasında çukurdan geçince turuncu ÇUKUR butonuna, telefonun ses tuşuna, Bluetooth kumandaya veya kulaklık tuşuna basın; kısa bir çift bip duyulur.',
              'Basış CSV\'de Isaret ve Isaret_Kaynak sütunlarına yazılır. Analiz betiği basıştan önceki 5 sn\'deki sarsıntı tepesini bularak çukurun anını ve konumunu çıkarır, otomatik darbe tespitini bu işaretlerle karşılaştırır.',
              'Ekrana veya telefonun tuşuna basmak telefonu sarsar: o an ve sonraki 0,5 sn analizde dışlanır. Kumanda ve kulaklık telefonu sarsmaz.',
              'Ekran kapalıyken de tuşlar çalışır. O sırada başka bir uygulama müzik çalıyorsa medya tuşları ona gidebilir.',
              '1 sn içindeki ikinci basış sayılmaz. Kayıt sırasında ses tuşları sesi değiştirmez; DURDUR basılı tutularak çalışır.',
            ],
          ),
          const _InfoCard(
            title: 'Konfor puanlaması (doğrulama)',
            lines: [
              'Kayıt bitince güzergâh dönüşlerden parçalara bölünür (kabaca her sokak bir parça, uzun düz yollar en fazla ~200 m).',
              'Her parça için ne kadar rahat geçildiği 1 (çok sarsıntılı) - 5 (çok rahat) arası puanlanır. Haritada ölçülen sarsıntı gösterilmez: puan ölçümden bağımsız olmalıdır.',
              '"Sonra" ile geçilebilir; Kayıtlar sayfasındaki yıldızdan sonradan puanlanabilir veya puan değiştirilebilir.',
              'Puanlar kaydın _puan.csv dosyasına yazılır. Analiz betiği her parçanın hız düzeltmeli sarsıntı indeksini puanla karşılaştırır (Spearman sıra korelasyonu).',
            ],
          ),
          const _InfoCard(
            title: 'Kayıt etiketleri',
            lines: [
              'Scooter: Ayarlar sayfasında bir kez yazılır, her kayda otomatik eklenir.',
              'Hava durumu: kayıt başında internet ve GPS konumu varsa Open-Meteo servisinden alınır (konum ~1 km\'ye yuvarlanarak gönderilir). Alınamazsa yazılmaz.',
              'İkisi de kaydın _bilgi.txt dosyasına yazılır; analiz betiği özet ve karşılaştırmalarda kullanır.',
            ],
          ),
          const _InfoCard(
            title: 'Test sürüşü (sanal GPS)',
            lines: [
              'Ayarlar\'dan açılır. Gerçek GPS yerine konum YTÜ Davutpaşa Yerleşkesi\'nde 150 m yarıçaplı bir tur üzerinde, hız 4-20 km/h arasında üretilir; sarsıntı gerçek ivmeölçerden ölçülür.',
              'GPS\'i olmayan cihazda veya kapalı alanda uygulamayı denemek içindir. Kayıtlar test_ ile başlar, Kayıtlar listesinde TEST yazar; hava durumu alınmaz.',
              'Puanlamada en kısa parça 50 m yerine 5 m\'dir. Analiz betikleri klasör taramasında test kayıtlarını atlar. Tez verisi için kapalı tutun.',
            ],
          ),
          const _InfoCard(
            title: 'Kayıt dosyaları',
            lines: [
              'Veriler kayıt sırasında 5 saniyede bir dosyaya yazılır; uygulama kapanırsa en fazla son 5 saniye kaybolur.',
              'Her kayıt için mikromobilite_<tarih_saat>.csv (veri), ..._bilgi.txt (cihaz, sensör, ayarlar) ve puanlandıysa ..._puan.csv oluşur.',
              'Kayıt bitince dosyalar telefonun Belgeler/Mikromobilite klasörüne kopyalanır: dosya yöneticisinden ve USB ile bilgisayardan erişilir (Android 9 ve öncesinde ilk açılışta dosya izni istenir).',
              'Başlıktaki klasör simgesinden eski kayıtlar tekrar paylaşılabilir, puanlanabilir veya silinebilir. Uygulamadan silmek Belgeler\'deki kopyayı silmez.',
            ],
          ),
          const _InfoCard(
            title: 'Montaj',
            lines: [
              'Telefon araca sıkıca sabitlenmelidir; açısı önemli değildir (dikey sarsıntı açıdan bağımsız hesaplanır). Gevşek tutucu veya cep/çanta ölçümü bozar.',
              'Montaj açısı ana ekranda EĞİM olarak görülebilir.',
              'Kayıt sırasında ekran açık kalır; ekran kilitlenir veya başka uygulamaya geçilirse kayıt arka planda sürer (bildirim çubuğunda görünür). Samsung telefonlarda uygulamanın pil ayarı "Kısıtlanmamış" olmalıdır.',
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6, left: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          color: Color(0xFF6C757D),
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.lines});
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF003366),
              ),
            ),
            const SizedBox(height: 8),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $line',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF212529),
                    height: 1.35,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
