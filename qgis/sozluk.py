"""QGIS dosyalarının veri sözlüğü ve Claude katmanlarının alanları (tek kaynak).

`ornek_uret.py` (yapay örnek) ve `algoritma/uret.py` (gerçek Claude dosyası) buradan alır. Uygulamanın yazdığı ham ve
insan dosyalarının sözlüğü `lib/katmanlar.dart`'tadır; ikisi aynı tutulmalı.
"""

CLAUDE_CUKUR_ALANLARI = [
    ("kayit_no", "TEXT"), ("kesit", "TEXT"), ("t_s", "REAL"), ("yerel_saat", "TEXT"),
    ("hiz_kmh", "REAL"), ("guven", "REAL"), ("tepe_ms2", "REAL"), ("algoritma", "TEXT"),
]
CLAUDE_CUKUR_ACIKLAMA = "Claude'un bulduğu çukur / ani sarsıntı noktaları (darbe anındaki ham GPS konumu)."
CLAUDE_PUAN_ALANLARI = [
    ("kayit_no", "TEXT"), ("kesit", "TEXT"), ("kesit_adi", "TEXT"), ("puan", "INTEGER"), ("puan_ondalik", "REAL"),
    ("indeks_ms2", "REAL"), ("algoritma", "TEXT"),
]
CLAUDE_PUAN_ACIKLAMA = "Claude'un kesite verdiği konfor puanı (1-5); çizgi kaydın güzergâhı."

ORTAK = [
    ("(tümü)", "kayit_no", "metin", "", "Kaydın kimliği: başlangıcın yerel tarih ve saati (YYYYMMDD_SSddss). Bütün dosyalarda aynı; katmanları bununla birleştirin."),
    ("(tümü)", "kesit", "metin", "", "Kesit kodu (K01, K02...). Telefon otomatik verir: başlangıç ve bitiş noktası önceki bir kayıtla ~30 m içinde örtüşen (ters yön dahil) kayıt aynı kesittir. Yanlışsa QGIS'te düzeltilebilir."),
    ("(tümü)", "kesit_adi", "metin", "", "Kesitin adı: kullanıcı Kayıtlar sayfasında verir (ör. sokak adı); aynı kesitin bütün kayıtlarına uygulanır. Verilmediyse boş."),
    ("(tümü)", "t_s", "ondalık", "s", "Kayıt başından (BAŞLAT) bu yana geçen süre. Bütün sensörler ve basışlar aynı saatle ölçülür. Çukur noktalarının konumu bu andaki ham GPS konumudur (iki GPS noktası arasında doğrusal ara değer)."),
    ("(tümü)", "yerel_saat", "metin", "UTC+3", "Aynı an, İstanbul saatiyle (milisaniyeli)."),
]

ACIKLAMA_HAM = [
    ("(dosya)", "", "", "", "Telefonun ürettiği ham veri dosyası (*_ham.gpkg). Claude'a bu dosya verilir; sürücünün işaret ve puanları bu dosyada YOKTUR."),
    ("(dosya)", "", "", "", "Koordinat sistemi WGS84 (EPSG:4326). Konumlar ham GPS'tir: düzeltme yapılmamıştır (GPS konumu gerçek konumun biraz gerisinde olabilir; eski sürümde ~1 sn ölçülmüştü)."),
] + ORTAK + [
    ("kayitlar", "(geometri)", "çizgi", "", "Kaydın güzergâhı: ham GPS noktalarının birleşimi. Bir kayıt = bir kesitin bir geçişi."),
    ("kayitlar", "yon", "metin", "", "gidis / donus: kesitin ilk kaydedildiği yöne göre."),
    ("kayitlar", "baslangic_yerel", "metin", "UTC+3", "BAŞLAT anı, İstanbul saatiyle."),
    ("kayitlar", "sure_s", "ondalık", "s", "Kayıt süresi (baştaki ve sondaki ~5 sn duruş dahil)."),
    ("kayitlar", "uzunluk_m", "ondalık", "m", "GPS noktaları arasındaki mesafelerin toplamı (yalnızca hız >= 3 km/h olan kısımlar)."),
    ("kayitlar", "ort_hiz_kmh", "ondalık", "km/h", "Hareket halindeki (>= 3 km/h) GPS hızlarının ortalaması."),
    ("kayitlar", "gps_nokta", "tam sayı", "", "Kayıttaki GPS konumu sayısı."),
    ("kayitlar", "ivme_hz, jiro_hz", "ondalık", "Hz", "Telefonun gerçekte verdiği örnekleme hızı (200 Hz istenir; Samsung M21 125 Hz verir)."),
    ("kayitlar", "cihaz, ivme_sensoru, jiro_sensoru", "metin", "", "Telefon modeli, Android sürümü, sensör adları."),
    ("kayitlar", "scooter", "metin", "", "Ayarlar'daki scooter adı."),
    ("kayitlar", "hava, sicaklik_c, yagis_mm", "metin / ondalık", "°C, mm", "Kayıt başındaki hava durumu (Open-Meteo)."),
    ("kayitlar", "veri_kaynagi", "metin", "", "telefon / test_surusu (sanal GPS) / yapay_ornek."),
    ("kayitlar", "uygulama_surumu", "metin", "", "Kaydı yapan uygulama sürümü."),
    ("gps_noktalari", "(geometri)", "nokta", "", "Telefonun GPS alıcısından gelen her konum (yaklaşık saniyede bir), ham."),
    ("gps_noktalari", "hiz_kmh", "ondalık", "km/h", "GPS Doppler hızı."),
    ("gps_noktalari", "yon_derece", "ondalık", "°", "Hareket yönü (kuzeyden saat yönünde). Dururken boş."),
    ("gps_noktalari", "dogruluk_m", "ondalık", "m", "Yatay doğruluk (%68 güven yarıçapı)."),
    ("gps_noktalari", "uydu", "tam sayı", "", "Konumda kullanılan uydu sayısı."),
    ("gps_noktalari", "dikey_rms", "ondalık", "m/s²", "Önceki GPS konumundan bu konuma kadarki dikey sarsıntının RMS'i. Yöntem: ivmenin üç eksenine 0,4 Hz yüksek geçiren süzgeç, yerçekimi yönüne izdüşüm (telefonun açısından bağımsız). Renklendirme için."),
    ("gps_noktalari", "dikey_tepe", "ondalık", "m/s²", "Aynı aralıktaki en büyük mutlak dikey sarsıntı (darbe tepesi)."),
    ("gps_noktalari", "ivme_ornek", "tam sayı", "", "Aynı aralıktaki ivme örneği sayısı (telefonun hızı kadar; Samsung M21 ~125)."),
    ("ivme", "x, y, z", "ondalık", "m/s²", "Ham ivmeölçer, yerçekimi dahil, telefonun kendi eksenleri (x sağa, y ekranın üstüne, z ekrandan dışarı). Geometrisi yoktur; kayit_no ve t_s ile eşleştirilir."),
    ("jiroskop", "x, y, z", "ondalık", "rad/s", "Ham jiroskop (açısal hız), telefonun kendi eksenleri. Geometrisi yoktur."),
]

ACIKLAMA_INSAN = [
    ("(dosya)", "", "", "", "Sürücünün işaret ve puanları (*_insan.gpkg). Claude bu dosyayı o günün Claude katmanları GitHub'a gönderilmeden açmaz."),
] + ORTAK + [
    ("insan_cukurlar", "(geometri)", "nokta", "", "Basış anındaki ham GPS konumu (t_s anına doğrusal ara değer; Claude noktalarıyla aynı kural). Sürücü çukurdan biraz sonra bastığı için nokta çukurun birkaç metre ilerisine düşebilir. Karşılaştırmada iki nokta arasındaki mesafe kullanılır."),
    ("insan_cukurlar", "hiz_kmh", "ondalık", "km/h", "Basış anındaki GPS hızı."),
    ("insan_cukurlar", "kaynak", "metin", "", "kulaklik / kumanda / ekran / tus. Ekran ve telefon tuşu telefonu sarsar."),
    ("insan_puanlar", "(geometri)", "çizgi", "", "Kaydın güzergâhı (kayitlar katmanıyla aynı)."),
    ("insan_puanlar", "puan", "tam sayı", "1-5", "Konfor puanı: 1 çok kötü ... 5 çok iyi. Hatırlamıyorum ise boş."),
    ("insan_puanlar", "durum", "metin", "", "puanlandi / hatirlamiyorum / puanlanmadi (henüz puan verilmedi)."),
    ("insan_puanlar", "puanlama_yerel", "metin", "UTC+3", "Puanın verildiği an, İstanbul saatiyle (DURDUR'dan hemen sonra olmalı)."),
    ("insan_puanlar", "isaret_sayisi", "tam sayı", "", "Bu kayıttaki çukur işareti sayısı."),
]

ACIKLAMA_CLAUDE = [
    ("(dosya)", "", "", "", "Claude'un çıktıları (*_claude.gpkg): yalnızca *_ham.gpkg'den üretilir."),
] + ORTAK + [
    ("claude_cukurlar", "(geometri)", "nokta", "", "Darbe anındaki ham GPS konumu (t_s anına doğrusal ara değer; insan noktalarıyla aynı kural, GPS gecikmesi düzeltilmez)."),
    ("claude_cukurlar", "t_s", "ondalık", "s", "Darbe anı. Sürücünün basışı genellikle bundan biraz sonradır."),
    ("claude_cukurlar", "guven", "ondalık", "0-1", "Tespitin güven puanı."),
    ("claude_cukurlar", "tepe_ms2", "ondalık", "m/s²", "Darbenin dikey sarsıntı tepesi."),
    ("claude_cukurlar", "algoritma", "metin", "", "Algoritmanın sürümü."),
    ("claude_puanlar", "puan", "tam sayı", "1-5", "Claude'un konfor puanı (insan puanıyla aynı ölçek)."),
    ("claude_puanlar", "puan_ondalik", "ondalık", "1-5", "Yuvarlanmamış puan."),
    ("claude_puanlar", "indeks_ms2", "ondalık", "m/s²", "Puanın dayandığı sarsıntı ölçüsü."),
]


def json_icerik():
    """Uygulamanın (lib/katmanlar.dart) yazdığı sözlükle karşılaştırmak için: test/sozluk_test.dart bunu okur."""
    return {"ham": [list(r) for r in ACIKLAMA_HAM], "insan": [list(r) for r in ACIKLAMA_INSAN]}


if __name__ == "__main__":
    # python3 qgis/sozluk.py: qgis/sozluk.json'u yeniden yazar (sözlük değişince; Dart ve Python testleri bunu ister)
    import json
    import os
    yol = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sozluk.json")
    with open(yol, "w", encoding="utf-8") as f:
        json.dump(json_icerik(), f, ensure_ascii=False, indent=1)
        f.write("\n")
    print(yol)
