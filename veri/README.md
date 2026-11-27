# Sürüş verileri

Gerçek sürüşlerin GeoPackage dosyaları. Depo herkese açıktır; kullanıcı gerçek güzergâhların ve verilerin depoya
konmasına izin verdi.

- `gelistirme/<YYYYMMDD>/`: **geliştirme seti.** Ham + insan dosyaları birlikte. Algoritma bunlarla kurulur ve ayarlanır.
  - `20261125`: Söğütlüçeşme deneme sürüşü (4 kısa kayıt, 9 işaret, uygulama sürüm 2.0, derleme 34).
  - `20261128`: ilk geliştirme günü, Moda (gece 00:45-01:51; 5 sokak × 3 geçiş = 15 kayıt, ~2,1 km; 42 işaret, hepsi
    kumanda; puanlar 1-5; derleme 43, Hop Scooter). Telefonda dosya adları `gelistirme_` ile başlıyordu (aynı gün test
    sürüşü yapıldığı için); burada önek kaldırıldı.
    Zemin (kullanıcının kontrol listesinden, gözle): K01 Hüseyinbey Sk. parke (puan 2), K02 Moda Cad. son kısım yamalı
    asfalt (4), K05 Moda Bostanı Sk. parke (1), K07 Ressam Şeref Akdik Sk. Arnavut kaldırımı (1-2), K10 Mühürdar Cad.
    Moda tarafı düz asfalt (5). Zemin bilgisi yalnız geliştirme ve yorum içindir; algoritmaya girdi olmaz (testte
    yalnız ham dosya verilir).
- `test/<YYYYMMDD>/`: **test seti** (geliştirmeden farklı sokaklar). Sıra şöyledir:
  1. Önce yalnızca `*_ham.gpkg` konur.
  2. `python3 algoritma/uret.py veri/test/<gün>` ile Claude dosyası üretilir, commit edilir ve GitHub'a gönderilir (mühür).
  3. Ancak bundan sonra `*_insan.gpkg` eklenir (ayrı, sonraki bir gönderimde) ve `python3 algoritma/karsilastir.py veri/test`
     çalıştırılır. Karşılaştırma, Claude dosyasının ve eşiğin insan dosyasından önce GitHub'a gittiğini git geçmişinden
     denetler; aynı gönderimde giderlerse o gün kalıcı olarak reddedilir (yalnızca git geçmişini yeniden yazmak düzeltir).
     Bu yüzden test günlerinde dosyalar tek tek eklenir (`git add -A` değil) ve insan dosyası Claude gönderimi bitene kadar
     depo klasörüne konmaz.
  - Eşik: `test/esik.json` (`{"esik_m": 6.5}`). Kullanıcı ve arkadaşı geliştirme sürüşlerinden sonra belirler; ilk test
    gününün insan dosyasından önce GitHub'a konur.

Claude, bir test gününün insan dosyasını o günün Claude dosyası GitHub'a gönderilmeden açmaz (bağımsızlık kuralı).
Kurallar ve komutlar: `algoritma/README.md`.
