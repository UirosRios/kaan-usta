import 'gpkg.dart';

// GeoPackage katmanları ve veri sözlüğü. Biçim kullanıcı ve arkadaşı tarafından onaylandı (25 Kasım 2026):
// alan adları, türleri ve sırası qgis/ornek/ dosyalarıyla ve qgis/ornek_uret.py ile aynı kalmalı
// (denetim: python3 qgis/sema_karsilastir.py). Açıklamalar qgis/README.md'dekiyle uyumlu.

const List<(String, String)> _sensorAlanlari = [('kayit_no', 'TEXT'), ('t_s', 'REAL'), ('x', 'REAL'), ('y', 'REAL'), ('z', 'REAL')];

const Katman kayitlarKatmani = Katman('kayitlar', 'LINESTRING', [
  ('kayit_no', 'TEXT'), ('kesit', 'TEXT'), ('kesit_adi', 'TEXT'), ('yon', 'TEXT'), ('baslangic', 'DATETIME'),
  ('bitis', 'DATETIME'), ('baslangic_yerel', 'TEXT'), ('sure_s', 'REAL'), ('uzunluk_m', 'REAL'), ('ort_hiz_kmh', 'REAL'),
  ('gps_nokta', 'INTEGER'), ('ivme_hz', 'REAL'), ('jiro_hz', 'REAL'), ('cihaz', 'TEXT'), ('ivme_sensoru', 'TEXT'),
  ('jiro_sensoru', 'TEXT'), ('scooter', 'TEXT'), ('hava', 'TEXT'), ('sicaklik_c', 'REAL'), ('yagis_mm', 'REAL'),
  ('ruzgar_kmh', 'REAL'), ('veri_kaynagi', 'TEXT'), ('uygulama_surumu', 'TEXT'),
], 'Her kayıt (bir kesitin bir geçişi) bir çizgi: ham GPS noktalarının birleşimi.');

const Katman gpsKatmani = Katman('gps_noktalari', 'POINT', [
  ('kayit_no', 'TEXT'), ('kesit', 'TEXT'), ('t_s', 'REAL'), ('zaman', 'DATETIME'), ('yerel_saat', 'TEXT'),
  ('hiz_kmh', 'REAL'), ('yon_derece', 'REAL'), ('dogruluk_m', 'REAL'), ('hiz_dogrulugu_kmh', 'REAL'),
  ('yukseklik_m', 'REAL'), ('dikey_dogruluk_m', 'REAL'), ('uydu', 'INTEGER'),
  ('dikey_rms', 'REAL'), ('dikey_tepe', 'REAL'), ('ivme_ornek', 'INTEGER'),
], 'Telefonun GPS alıcısından gelen her konum (ham, düzeltilmemiş) ve iki konum arasındaki sarsıntı özeti.');

const Katman ivmeKatmani = Katman('ivme', null, _sensorAlanlari, 'Ham ivmeölçer (m/s², yerçekimi dahil, telefon eksenleri), ~200 Hz.');
const Katman jiroKatmani = Katman('jiroskop', null, _sensorAlanlari, 'Ham jiroskop (rad/s, telefon eksenleri), ~200 Hz.');

const Katman insanCukurKatmani = Katman('insan_cukurlar', 'POINT', [
  ('kayit_no', 'TEXT'), ('kesit', 'TEXT'), ('t_s', 'REAL'), ('zaman', 'DATETIME'), ('yerel_saat', 'TEXT'),
  ('hiz_kmh', 'REAL'), ('kaynak', 'TEXT'),
], 'Sürücünün çukur basışları; konum basış anındaki ham GPS konumu (çukurun birkaç metre ilerisi).');

const Katman insanPuanKatmani = Katman('insan_puanlar', 'LINESTRING', [
  ('kayit_no', 'TEXT'), ('kesit', 'TEXT'), ('kesit_adi', 'TEXT'), ('puan', 'INTEGER'), ('durum', 'TEXT'),
  ('puanlama_zamani', 'DATETIME'), ('isaret_sayisi', 'INTEGER'),
], 'Sürücünün kesite verdiği konfor puanı (1 çok kötü - 5 çok iyi); çizgi kaydın güzergâhı.');

const Katman aciklamaKatmani = Katman('aciklamalar', null, [
  ('katman', 'TEXT'), ('alan', 'TEXT'), ('tur', 'TEXT'), ('birim', 'TEXT'), ('aciklama', 'TEXT'),
], 'Bu dosyadaki katman ve alanların açıklaması (veri sözlüğü).');

const String stilNotu = "Kullanıcının QGIS projesinden alınan görünüm (qgis/stil_cikar.py).";

const List<List<String>> _ortak = [
  ['(tümü)', 'kayit_no', 'metin', '', 'Kaydın kimliği: başlangıcın yerel tarih ve saati (YYYYMMDD_SSddss). Bütün dosyalarda aynı; katmanları bununla birleştirin.'],
  ['(tümü)', 'kesit', 'metin', '', "Kesit kodu (K01, K02...). Telefon otomatik verir: başlangıç ve bitiş noktası önceki bir kayıtla ~30 m içinde örtüşen (ters yön dahil) kayıt aynı kesittir. Yanlışsa QGIS'te düzeltilebilir."],
  ['(tümü)', 'kesit_adi', 'metin', '', "Kesitin adı: kullanıcı Kayıtlar sayfasında verir (ör. sokak adı); aynı kesitin bütün kayıtlarına uygulanır. Verilmediyse boş."],
  ['(tümü)', 't_s', 'ondalık', 's', "Kayıt başından (BAŞLAT) bu yana geçen süre. Bütün sensörler ve basışlar aynı saatle ölçülür; katmanları zamanla eşleştirmek için bu alan kullanılır."],
  ['(tümü)', 'zaman', 'tarih-saat', 'UTC', 'Mutlak zaman (GeoPackage kuralı gereği UTC; İstanbul = UTC+3).'],
  ['(tümü)', 'yerel_saat', 'metin', 'UTC+3', 'Aynı an, İstanbul saatiyle okunabilir yazım.'],
];

List<List<String>> hamAciklamalari({required bool test}) => [
      if (test) ['(dosya)', '', '', '', 'TEST SÜRÜŞÜ: konum ve GPS hızı sanaldır (üretilmiş), sarsıntı gerçek ivmeölçerden. Tez verisi değildir.'],
      ['(dosya)', '', '', '', "Telefonun ürettiği ham veri dosyası (*_ham.gpkg). Claude'a bu dosya verilir; sürücünün işaret ve puanları bu dosyada YOKTUR."],
      ['(dosya)', '', '', '', "Koordinat sistemi WGS84 (EPSG:4326). Konumlar ham GPS'tir: düzeltme yapılmamıştır; GPS konumu gerçek konumun yaklaşık 1 sn gerisindedir."],
      ..._ortak,
      ['kayitlar', '(geometri)', 'çizgi', '', 'Kaydın güzergâhı: ham GPS noktalarının birleşimi. Bir kayıt = bir kesitin bir geçişi.'],
      ['kayitlar', 'yon', 'metin', '', 'gidis / donus: kesitin ilk kaydedildiği yöne göre.'],
      ['kayitlar', 'baslangic, bitis', 'tarih-saat', 'UTC', 'BAŞLAT ve DURDUR anları.'],
      ['kayitlar', 'sure_s', 'ondalık', 's', 'Kayıt süresi (baştaki ve sondaki ~5 sn duruş dahil).'],
      ['kayitlar', 'uzunluk_m', 'ondalık', 'm', 'GPS noktaları arasındaki mesafelerin toplamı (yalnızca hız >= 3 km/h olan kısımlar).'],
      ['kayitlar', 'ort_hiz_kmh', 'ondalık', 'km/h', 'Hareket halindeki (>= 3 km/h) GPS hızlarının ortalaması.'],
      ['kayitlar', 'gps_nokta', 'tam sayı', '', 'Kayıttaki GPS konumu sayısı.'],
      ['kayitlar', 'ivme_hz, jiro_hz', 'ondalık', 'Hz', 'Telefonun gerçekte verdiği örnekleme hızı (istenen ~200 Hz).'],
      ['kayitlar', 'cihaz, ivme_sensoru, jiro_sensoru', 'metin', '', 'Telefon modeli, Android sürümü, sensör adları.'],
      ['kayitlar', 'scooter', 'metin', '', "Ayarlar'daki scooter adı."],
      ['kayitlar', 'hava, sicaklik_c, yagis_mm, ruzgar_kmh', 'metin / ondalık', '°C, mm, km/h', 'Kayıt başındaki hava durumu (Open-Meteo).'],
      ['kayitlar', 'veri_kaynagi', 'metin', '', 'telefon / test_surusu (sanal GPS) / yapay_ornek.'],
      ['kayitlar', 'uygulama_surumu', 'metin', '', 'Kaydı yapan uygulama sürümü.'],
      ['gps_noktalari', '(geometri)', 'nokta', '', 'Telefonun GPS alıcısından gelen her konum (yaklaşık saniyede bir), ham.'],
      ['gps_noktalari', 'hiz_kmh', 'ondalık', 'km/h', 'GPS Doppler hızı.'],
      ['gps_noktalari', 'yon_derece', 'ondalık', '°', 'Hareket yönü (kuzeyden saat yönünde). Dururken boş.'],
      ['gps_noktalari', 'dogruluk_m', 'ondalık', 'm', 'Yatay doğruluk (%68 güven yarıçapı).'],
      ['gps_noktalari', 'hiz_dogrulugu_kmh', 'ondalık', 'km/h', 'Hız doğruluğu.'],
      ['gps_noktalari', 'yukseklik_m, dikey_dogruluk_m', 'ondalık', 'm', 'GPS yüksekliği (elipsoit) ve doğruluğu.'],
      ['gps_noktalari', 'uydu', 'tam sayı', '', 'Konumda kullanılan uydu sayısı.'],
      ['gps_noktalari', 'dikey_rms', 'ondalık', 'm/s²', "Önceki GPS konumundan bu konuma kadarki dikey sarsıntının RMS'i. Yöntem: ivmenin üç eksenine 0,4 Hz yüksek geçiren süzgeç, yerçekimi yönüne izdüşüm (telefonun açısından bağımsız). Renklendirme için."],
      ['gps_noktalari', 'dikey_tepe', 'ondalık', 'm/s²', 'Aynı aralıktaki en büyük mutlak dikey sarsıntı (darbe tepesi).'],
      ['gps_noktalari', 'ivme_ornek', 'tam sayı', '', 'Aynı aralıktaki ivme örneği sayısı (~200 beklenir).'],
      ['ivme', 'x, y, z', 'ondalık', 'm/s²', 'Ham ivmeölçer, yerçekimi dahil, telefonun kendi eksenleri (x sağa, y ekranın üstüne, z ekrandan dışarı). Geometrisi yoktur; kayit_no ve t_s ile eşleştirilir.'],
      ['jiroskop', 'x, y, z', 'ondalık', 'rad/s', 'Ham jiroskop (açısal hız), telefonun kendi eksenleri. Geometrisi yoktur.'],
    ];

List<List<String>> insanAciklamalari({required bool test}) => [
      if (test) ['(dosya)', '', '', '', 'TEST SÜRÜŞÜ: konum sanaldır (üretilmiş). Tez verisi değildir.'],
      ['(dosya)', '', '', '', "Sürücünün işaret ve puanları (*_insan.gpkg). Claude bu dosyayı o günün Claude katmanları GitHub'a gönderilmeden açmaz."],
      ..._ortak,
      ['insan_cukurlar', '(geometri)', 'nokta', '', "Basış anındaki ham GPS konumu. Sürücü çukurdan ~1,3 sn sonra bastığı ve GPS ~1 sn geride olduğu için nokta çukurdan birkaç metre sapabilir; Claude ile eşleştirmede t_s kullanın."],
      ['insan_cukurlar', 'hiz_kmh', 'ondalık', 'km/h', 'Basış anındaki GPS hızı.'],
      ['insan_cukurlar', 'kaynak', 'metin', '', 'kulaklik / kumanda / ekran / tus. Ekran ve telefon tuşu telefonu sarsar.'],
      ['insan_puanlar', '(geometri)', 'çizgi', '', 'Kaydın güzergâhı (kayitlar katmanıyla aynı).'],
      ['insan_puanlar', 'puan', 'tam sayı', '1-5', 'Konfor puanı: 1 çok kötü ... 5 çok iyi. Hatırlamıyorum ise boş.'],
      ['insan_puanlar', 'durum', 'metin', '', 'puanlandi / hatirlamiyorum / puanlanmadi (henüz puan verilmedi).'],
      ['insan_puanlar', 'puanlama_zamani', 'tarih-saat', 'UTC', "Puanın verildiği an (DURDUR'dan hemen sonra olmalı)."],
      ['insan_puanlar', 'isaret_sayisi', 'tam sayı', '', 'Bu kayıttaki çukur işareti sayısı.'],
    ];
