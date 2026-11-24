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
              'Mikromobilite Veri Aracı: e-scooter / bisiklet sürüşünde ham sensör ve GPS verisi, sürücünün çukur işaretleri ve konfor puanları (QGIS için GeoPackage).',
              'YTÜ Harita Mühendisliği tez çalışması - Kaan Usta.',
            ],
          ),
          const _SectionTitle('BU CİHAZ'),
          // Telefonun modeli ve sensörlerinin özellikleri (her kaydın kayitlar katmanına da yazılır)
          FutureBuilder<Map<String, dynamic>>(
            future: DeviceInfo.load(),
            builder: (context, snapshot) => _InfoCard(
              title: 'Cihaz ve sensör özellikleri',
              lines: snapshot.hasData ? DeviceInfo.describe(snapshot.data!) : const ['Yükleniyor...'],
            ),
          ),
          const _SectionTitle('KAYDEDİLEN HAM VERİ'),
          const _InfoCard(
            title: '1. İvmeölçer',
            lines: [
              'Üç eksendeki ivme (X, Y, Z), m/s², yerçekimi dahil; ~200 Hz. Telefonda süzgeç uygulanmadan, her örnek kaydedilir.',
              'Ekrandaki DİKEY SARSINTI yalnızca gösterim içindir: ivmenin üç eksenine 0,4 Hz yüksek geçiren süzgeç, titreşimin yerçekimi yönüne izdüşümü (telefonun açısından bağımsız). TOPLAM: titreşimin büyüklüğü; EĞİM: telefonun yataydan eğimi.',
              'GeoPackage: ivme tablosu (ham), gps_noktalari katmanında iki GPS konumu arasındaki dikey sarsıntı özeti (dikey_rms, dikey_tepe).',
            ],
          ),
          const _InfoCard(
            title: '2. Jiroskop',
            lines: [
              'Üç eksendeki açısal hız (rad/s), ~200 Hz, ham. Telefonun dönmesini (viraj, darbede gidonun öne-arkaya oynaması) ölçer.',
              'GeoPackage: jiroskop tablosu.',
            ],
          ),
          const _InfoCard(
            title: '3. GNSS alıcısı (GPS)',
            lines: [
              'Doğrudan GPS donanımı okunur (Android GPS_PROVIDER); yumuşatma yapılmaz. Her konum kaydedilir: enlem, boylam, yükseklik, Doppler hızı, yön, doğruluk, hız ve yükseklik doğruluğu, kullanılan uydu sayısı.',
              'GPS konumu gerçek konumun yaklaşık 1 sn gerisindedir; düzeltme yapılmaz (analizde yapılır).',
              'Ekrandaki DÜZELTİLMİŞ GPS (Google birleşik konum servisi) yalnızca gösterim içindir, kaydedilmez.',
            ],
          ),
          const _InfoCard(
            title: 'Ortak saat',
            lines: [
              'İvmeölçer, jiroskop, GPS ve çukur basışları aynı saatle (Android elapsedRealtimeNanos) zaman damgalanır. GeoPackage\'ta t_s = kayıt başından (BAŞLAT) itibaren saniye; zaman alanları UTC.',
            ],
          ),
          const _InfoCard(
            title: 'Harita',
            lines: [
              'Esri Light Gray Canvas altlık haritası. Mavi nokta o anki GPS konumu, açık mavi daire GPS doğruluğu. Harita karoları internetten yüklenir; kaydı etkilemez.',
            ],
          ),
          const _SectionTitle('SÜRÜŞ'),
          const _InfoCard(
            title: 'Kesit: bir kayıt = bir kesit = bir puan',
            lines: [
              'Kesit başında durun, BAŞLAT\'a basın, ~5 sn bekleyip sürün. Kesit sonunda durun, ~5 sn bekleyip DURDUR\'a basılı tutun. Her geçişte aynı noktalarda başlayıp bitirin.',
              'Zemin kesit boyunca tek tip olmalı; değişiyorsa (asfalt → parke) orada durup yeni kayıt başlatın.',
              'Kesit kodu (K01, K02...) otomatik verilir: başlangıç ve bitiş noktası önceki bir kayıtla ~30 m içinde örtüşen kayıt aynı kesittir (ters yönde örtüşürse dönüş). Kesite Kayıtlar sayfasında ad verilebilir.',
            ],
          ),
          const _InfoCard(
            title: 'Çukur işareti',
            lines: [
              'Ani sarsıntı veren her şeyde (çukur, kasis, ray, rögar, kot farkı) kulaklık veya Bluetooth kumanda tuşuna basın; kısa bir çift bip duyulur. Ekran kapalıyken de çalışır (o sırada müzik çalan başka uygulama varsa medya tuşları ona gidebilir).',
              'Arnavut kaldırımı gibi sürekli pürüzlü zeminde her taşa değil, yalnızca zeminden belirgin ayrılan sarsıntılara basın.',
              'Ekrandaki ÇUKUR butonu ve telefonun ses tuşu yedektir: telefonu sarstıkları için kaynakları ayrı kaydedilir. 1 sn içindeki ikinci basış sayılmaz.',
            ],
          ),
          const _InfoCard(
            title: 'Konfor puanı',
            lines: [
              'DURDUR\'dan hemen sonra açılır ve geçilemez: 1 (çok sarsıntılı) - 5 (çok rahat) veya "Hatırlamıyorum". Ölçülen sarsıntı gösterilmez.',
              'Puan sonradan Kayıtlar sayfasından değiştirilebilir.',
            ],
          ),
          const _InfoCard(
            title: 'Kayıt etiketleri',
            lines: [
              'Scooter: Ayarlar\'da bir kez yazılır, her kayda eklenir. Hava durumu: kayıt başında internet ve GPS varsa Open-Meteo\'dan alınır (konum ~1 km\'ye yuvarlanır).',
            ],
          ),
          const _InfoCard(
            title: 'Test sürüşü (sanal GPS)',
            lines: [
              'Ayarlar\'dan açılır. Konum YTÜ Davutpaşa Yerleşkesi\'nin iç yollarında ~1,85 km\'lik bir turda üretilir, sarsıntı gerçek ivmeölçerden. Kayıt akışını evde prova etmek içindir; test kayıtları ayrı dosyalara yazılır. Tez verisi için kapalı tutun.',
            ],
          ),
          const _SectionTitle('DOSYALAR'),
          const _InfoCard(
            title: 'GeoPackage (QGIS)',
            lines: [
              'Her sürüş günü iki dosyadır: mikromobilite_<gün>_ham.gpkg (güzergâh, GPS noktaları, ivme, jiroskop; Claude\'a gönderilir) ve mikromobilite_<gün>_insan.gpkg (çukur işaretleri ve konfor puanları; sürücüde kalır).',
              'Dosyalar QGIS\'e sürüklenince katmanlar hazır görünümle (renk ve simgeler) açılır. Her dosyada alanları açıklayan aciklamalar tablosu vardır.',
              'Ham veri kayıt sırasında saniyede bir diske yazılır; uygulama çökerse en fazla son ~1 sn kaybolur, yarım kalan kayıt bir sonraki açılışta kurtarılır.',
              'Dosyalar telefonun Belgeler/Mikromobilite klasörüne de kopyalanır (dosya yöneticisi veya USB). Kayıtlar sayfasından gönderilir; kesit adı ve puan değiştirilebilir, kayıt silinebilir. Eski (v1) CSV kayıtları Kayıtlar sayfasındaki saat simgesindedir.',
            ],
          ),
          const _InfoCard(
            title: 'Montaj',
            lines: [
              'Telefon araca sıkıca sabitlenmelidir; açısı önemli değildir (dikey sarsıntı açıdan bağımsız hesaplanır). Gevşek tutucu veya cep/çanta ölçümü bozar.',
              'Montaj açısı ana ekranda EĞİM olarak görülebilir. Kayıt sırasında geri tuşu uygulamayı kapatmaz.',
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
