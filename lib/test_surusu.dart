import 'dart:math';
import 'package:latlong2/latlong.dart';

// TEST SÜRÜŞÜ (Ayarlar): gerçek GPS yerine sanal konum. Güzergâh YTÜ Davutpaşa Yerleşkesi'nin iç yollarında, orta bloğun
// çevresinde kapalı bir turdur (OpenStreetMap, "YTU Davutpasa Yerleşkesi" yolları; 1 m toleransla sadeleştirildi).
// Sanal sürücü turun kuzey köşesinden başlar, yolları izleyerek dolanır ve başladığı yere döner; orada 6 sn durup
// yeni tura başlar. Hız 4-20 km/h arasında değişir. Sarsıntı her zaman gerçek ivmeölçerden ölçülür.
class SanalTur {
  SanalTur() {
    var top = 0.0;
    _kumulatif.add(0);
    for (var i = 0; i < _yol.length; i++) {
      top += _mesafe.as(LengthUnit.Meter, _yol[i], _yol[(i + 1) % _yol.length]);
      _kumulatif.add(top);
    }
  }

  static const Distance _mesafe = Distance(roundResult: false);
  static const double durusSn = 6; // her tur sonunda başlangıçta bekleme
  final List<double> _kumulatif = [];
  double get uzunluk => _kumulatif.last;

  double _gidilen = 0; // bu turda gidilen yol, m
  double _bekleme = durusSn; // kayıt başı da duruşla başlar (GPS "ilk konum" gibi)
  double _sure = 0; // sn
  double hizKmh = 0;
  LatLng konum = _yol.first;

  // dt saniye ilerlet
  void ilerle(double dt) {
    _sure += dt;
    if (_bekleme > 0) {
      _bekleme -= dt;
      hizKmh = 0;
      konum = _yol.first;
      return;
    }
    hizKmh = 12.0 + 8.0 * sin(_sure / 60 * 2 * pi); // 4-20 km/h, dakikalık dalga
    _gidilen += hizKmh / 3.6 * dt;
    if (_gidilen >= uzunluk) {
      // Başlangıca dönüldü: dur, sonra yeni tur
      _gidilen = 0;
      _bekleme = durusSn;
      hizKmh = 0;
      konum = _yol.first;
      return;
    }
    var i = 0;
    while (_kumulatif[i + 1] < _gidilen) {
      i++;
    }
    final a = _yol[i], b = _yol[(i + 1) % _yol.length];
    final k = (_gidilen - _kumulatif[i]) / (_kumulatif[i + 1] - _kumulatif[i]);
    konum = LatLng(a.latitude + k * (b.latitude - a.latitude), a.longitude + k * (b.longitude - a.longitude));
  }

  // Tur: 34 nokta, 1850 m, saat yönünün tersi
  static const List<LatLng> _yol = [
    LatLng(41.027878, 28.889648),
    LatLng(41.027248, 28.889079),
    LatLng(41.026890, 28.888808),
    LatLng(41.026509, 28.888473),
    LatLng(41.026281, 28.888188),
    LatLng(41.025124, 28.886972),
    LatLng(41.025025, 28.886894),
    LatLng(41.024961, 28.886894),
    LatLng(41.024931, 28.886935),
    LatLng(41.024910, 28.887032),
    LatLng(41.024844, 28.887174),
    LatLng(41.024468, 28.887703),
    LatLng(41.022462, 28.891055),
    LatLng(41.022316, 28.891373),
    LatLng(41.022288, 28.891791),
    LatLng(41.022294, 28.891899),
    LatLng(41.022317, 28.891978),
    LatLng(41.023058, 28.893564),
    LatLng(41.023402, 28.893673),
    LatLng(41.024208, 28.893578),
    LatLng(41.024384, 28.893583),
    LatLng(41.024557, 28.893640),
    LatLng(41.025127, 28.893933),
    LatLng(41.025274, 28.893988),
    LatLng(41.025341, 28.893945),
    LatLng(41.025428, 28.893956),
    LatLng(41.025503, 28.894021),
    LatLng(41.025526, 28.894095),
    LatLng(41.025690, 28.894123),
    LatLng(41.026235, 28.892357),
    LatLng(41.026310, 28.892172),
    LatLng(41.026420, 28.892019),
    LatLng(41.026668, 28.891779),
    LatLng(41.027857, 28.889791),
  ];
}
