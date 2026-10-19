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
              'Mikromobilitede (e-scooter, bisiklet vb.) hıza göre sarsıntı ölçümü.',
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
              'Ölçtüğü: Ekrana dik (Z) eksendeki ivme, m/s². Ham değere yerçekimi dahildir; telefon düz dururken ≈ 9,81.',
              'Yerçekimi giderme: ham Z, 0,4 Hz kesim frekanslı birinci dereceden yüksek geçiren filtreden (bilineer dönüşüm) geçirilir (0,4 Hz = ISO 2631-1 alt bant sınırı). Sonuç (Z_Net) hareketsizken ≈ 0 olur. Filtre ilk ~2 saniyede oturur.',
              'Örnekleme: ~50 Hz istenir (gerçek sayı CSV\'de Z_Ornek_Sayisi).',
              'Ekranda: Z-EKSENİ SARSINTI (büyük sayı Z_Net, altında ham değer)',
              'CSV: Z_Net, Z_Ham, Z_Ham_Ort, Z_Net_RMS, Z_Net_Min, Z_Net_Max, Z_Ornek_Sayisi',
            ],
          ),
          const _InfoCard(
            title: '2. Jiroskop (dönme / eğilme)',
            lines: [
              'Ölçtüğü: Üç eksendeki açısal hız, rad/s. Telefon hareketsizken üçü de ≈ 0.',
              'Telefon ekranı yukarı, üst kenarı ileri bakacak şekilde takılıysa: X = öne/arkaya eğilme, Y = yana yatma, Z = sağa/sola dönüş.',
              'Örnekleme: ~50 Hz istenir.',
              'Ekranda: JİROSKOP X / Y / Z',
              'CSV: Jiro_X_Ort, Jiro_Y_Ort, Jiro_Z_Ort, Jiro_Max_Bileske',
            ],
          ),
          const _InfoCard(
            title: '3. GNSS alıcısı (ham GPS)',
            lines: [
              'Doğrudan GPS donanımı okunur (Android GPS_PROVIDER); yumuşatma yapılmaz. Yonga destekliyorsa GLONASS, Galileo ve BeiDou da kullanılır.',
              'Hız, uydu sinyalinin Doppler kaymasından ölçülür. Konum çoğu telefonda saniyede 1 kez gelir.',
              'Ekranda: HAM GPS HIZI, MANTIKSAL HIZ, KOORDİNATLAR, Doğruluk',
              'CSV: Enlem, Boylam, Ham_Hiz_kmh, Mantiksal_Hiz_kmh, GPS_Dogruluk_m, GPS_Yasi_s',
            ],
          ),
          const _InfoCard(
            title: '4. Fused konum servisi (düzeltilmiş GPS)',
            lines: [
              'Sensör değil, Google\'ın yazılım servisi: GPS\'i Wi-Fi, baz istasyonu ve olası hareket sensörleriyle harmanlar ve yumuşatır.',
              'Ekranda: DÜZELTİLMİŞ GPS',
              'CSV: Duzeltilmis_GPS_Hiz_kmh, Duzeltilmis_GPS_Yasi_s',
            ],
          ),
          const _InfoCard(
            title: '5. Telefonun saati',
            lines: [
              'CSV\'deki Tarih_Saat ve GPS yaşı hesapları telefonun sistem saatinden gelir (uydu saati değildir).',
            ],
          ),
          const _SectionTitle('KAYIT YÖNTEMİ'),
          const _InfoCard(
            title: 'Örnekleme ve filtreler',
            lines: [
              'Her 0,5 saniyede bir CSV satırı yazılır (saniyede 2 satır).',
              'İvmeölçer ve jiroskop için o 0,5 sn içindeki tüm örneklerin istatistiği alınır.',
              'Z_Net_RMS: yerçekimi çıkarılmış Z\'nin pencere içindeki RMS\'i = sarsıntı şiddeti.',
              'Z_Ham_Ort: ham Z ortalaması ≈ yerçekiminin Z bileşeni; telefon eğildikçe 9,81\'den küçülür.',
              'Doğruluğu 50 m\'den kötü GPS konumları atılır.',
              'Mantıksal hız: ham hız 2 km/h altındaysa 0 kabul edilir.',
            ],
          ),
          const _InfoCard(
            title: 'Kayıt dosyaları',
            lines: [
              'Veriler kayıt sırasında 5 saniyede bir dosyaya yazılır; uygulama kapanırsa en fazla son 5 saniye kaybolur.',
              'Her kayıt için iki dosya oluşur: mikromobilite_<tarih_saat>.csv (veri) ve ..._bilgi.txt (cihaz, sensör ve ayarlar).',
              'Başlıktaki klasör simgesinden eski kayıtlar tekrar paylaşılabilir veya silinebilir.',
              'Klasör: Android/data/tr.edu.yildiz.kaan_usta/files/kayitlar (telefon USB ile bilgisayara bağlanınca da erişilebilir).',
            ],
          ),
          const _InfoCard(
            title: 'Montaj',
            lines: [
              'Telefon gidona sabit bir tutucuyla, ekranı yukarı bakacak şekilde yatay takılmalıdır.',
              'Kayıt boyunca uygulama açık ve ön planda kalmalıdır (ekran otomatik kapanmaz).',
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
