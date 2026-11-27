# Sürüş verileri

Gerçek sürüşlerin GeoPackage dosyaları. Depo herkese açıktır; kullanıcı gerçek güzergâhların ve verilerin depoya
konmasına izin verdi.

- `gelistirme/<YYYYMMDD>/`: **geliştirme seti.** Ham + insan dosyaları birlikte. Algoritma bunlarla kurulur ve ayarlanır.
  - `20261125`: Söğütlüçeşme deneme sürüşü (4 kısa kayıt, 9 işaret, uygulama sürüm 2.0, derleme 34).
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
