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
              'Ölçtüğü: Üç eksendeki ivme (X, Y, Z), m/s². Ham değere yerçekimi dahildir; telefon düz dururken Z ≈ 9,81.',
              'Yerçekimi giderme: her eksen 0,4 Hz kesim frekanslı birinci dereceden yüksek geçiren filtreden (bilineer dönüşüm) geçirilir (0,4 Hz = ISO 2631-1 alt bant sınırı). Filtre çıkışı titreşimdir; ham ivme − titreşim = yerçekimi, yani telefonun o anki "aşağı" yönü. Filtre ilk ~2 saniyede oturur.',
              'DİKEY SARSINTI: titreşimin gerçek düşey yöndeki bileşeni. Telefon hangi açıda takılırsa takılsın aynı sarsıntı aynı değeri verir.',
              'TOPLAM: üç eksendeki titreşimin büyüklüğü (dikey + yatay), yönden bağımsız.',
              'Z-EKSENİ: yalnızca telefonun kendi Z ekseni (ekrana dik). Telefon yatay değilse düşey sarsıntının bir kısmını ölçer.',
              'EĞİM: telefonun yataydan eğimi (ekran yukarı ve yatayken 0°).',
              'Örnekleme: ~50 Hz istenir (gerçek sayı CSV\'de Ivme_Ornek_Sayisi).',
              'CSV: Dikey_Net, Dikey_RMS, Dikey_Min, Dikey_Max, Toplam_RMS, Egim_derece, Z_Net, Z_Ham, Z_Ham_Ort, Z_Net_RMS, Z_Net_Min, Z_Net_Max, Ivme_Ornek_Sayisi',
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
              'Ekranda: HAM GPS HIZI, KOORDİNATLAR, Doğruluk, HARİTA',
              'CSV: Enlem, Boylam, Ham_Hiz_kmh, GPS_Dogruluk_m, GPS_Yasi_s',
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
          const _InfoCard(
            title: 'Harita',
            lines: [
              'OpenStreetMap haritası (flutter_map). Mavi nokta o anki ham GPS konumu, açık mavi daire GPS doğruluğu (yarıçap = doğruluk, m).',
              'Harita konumu kendisi takip eder; iki parmakla veya çift dokunarak yakınlaştırılabilir.',
              'Harita karoları internetten yüklenir; ölçümü ve kaydı etkilemez.',
            ],
          ),
          const _SectionTitle('KAYIT YÖNTEMİ'),
          const _InfoCard(
            title: 'Örnekleme ve filtreler',
            lines: [
              'Her 0,5 saniyede bir CSV satırı yazılır (saniyede 2 satır).',
              'İvmeölçer ve jiroskop için o 0,5 sn içindeki tüm örneklerin istatistiği alınır.',
              'Dikey_RMS: dikey sarsıntının pencere içindeki RMS\'i = ana sarsıntı şiddeti ölçüsü.',
              'Toplam_RMS: üç eksen titreşiminin RMS\'i. Egim_derece: pencere içindeki ortalama eğim.',
              'Z_Net_RMS: yalnızca telefonun Z ekseni için aynı ölçü (telefon yatayken Dikey_RMS ile aynıdır).',
              'Doğruluğu 50 m\'den kötü GPS konumları atılır.',
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
              'Telefon araca sıkıca sabitlenmelidir; açısı önemli değildir (dikey sarsıntı açıdan bağımsız hesaplanır). Gevşek tutucu veya cep/çanta ölçümü bozar.',
              'Montaj açısı her kayıtta Egim_derece sütununa yazılır.',
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
