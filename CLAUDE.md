# KAAN USTA – Mikromobilite Veri Aracı (YTÜ Harita Mühendisliği tezi)

Scooter / bisiklet sürüşünde telefonun GPS'i ve ivmeölçeriyle hıza göre dikey sarsıntıyı ölçen sistem.
Kullanıcıyla Türkçe konuşulur; kod, yorumlar, commit mesajları ve belgeler Türkçedir.

## Bölümler

- `lib/`, `android/`, `assets/`: Flutter Android uygulaması (kayıt, anlık çukur uyarısı, CSV dışa aktarma).
- `analiz/`: Python analiz betikleri. `surus_analizi.py` (tek sürüş), `birlestir.py` (sürüşleri birleştirme),
  `haritaya_oturtma.py` (OSM yollarına oturtma), `simulasyon.py` (gerçeği bilinen yapay sürüşlerle doğrulama).
  Yalnızca standart kütüphane ve matplotlib kullanılır (masaüstü uygulaması bu ikisini gömülü getirir).
  Yöntem ve parametreler: `analiz/README.md`.
- `masaustu/analiz_araci.py`: betikleri Python kurmadan çalıştıran Windows uygulaması (tkinter + PyInstaller).
  "GitHub'dan güncelle" düğmesi betikleri deponun varsayılan dalından (`main`) çeker.

## Kayıt CSV biçimi

Türkçe Excel biçimi: sütun ayırıcı `;`, ondalık ayırıcı `,`. Her kaydın yanında `_bilgi.txt` (cihaz, scooter, hava durumu).

## Doğrulama

- Analiz betiği değişince: `python analiz/simulasyon.py` (10 senaryo, rapor `analiz/ornek/simulasyon_raporu.md`).
  Varsayılan değişirse raporu ve `analiz/ornek*` örnek çıktılarını yeniden üret.
- Uygulama değişince: `flutter analyze`.

## Derleme (GitHub Actions)

- `build-apk.yml`: yalnızca `lib/`, `android/`, `assets/`, `pubspec.*`, `analysis_options.yaml` değişince APK derler.
- `build-windows.yml`: `analiz/` veya `masaustu/` değişince `KaanUstaAnaliz.exe` derler.

## Git

- Değişiklikleri doğrudan `main` dalına gönder. Oturum ayrı bir dal açtıysa işi bitirince `main` ile birleştir
  (ileri alarak) ve `main`'e gönder. Bu, kullanıcının kalıcı iznidir.
