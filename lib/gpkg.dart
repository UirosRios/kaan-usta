import 'dart:math';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

// GeoPackage (.gpkg) yazıcısı: QGIS'in kendi önerdiği biçim (tek SQLite dosyasında birden çok katman).
// OGC GeoPackage 1.3'ün gerekli en küçük kısmı yazılır (koordinat sistemi, içerik ve geometri sütunları tabloları).
// Koordinatlar WGS84 (EPSG:4326), x = boylam, y = enlem. Python karşılığı ve örnek dosyalar: qgis/gpkg.py, qgis/ornek/.
// Bir sürüş gününün dosyasına kayıtlar eklenir; her ekleme tek bir işlemdir (yarıda kalırsa önceki kayıtlar bozulmaz).

const int wgs84 = 4326;
const String _wgs84Wkt = 'GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563,AUTHORITY["EPSG","7030"]],'
    'AUTHORITY["EPSG","6326"]],PRIMEM["Greenwich",0,AUTHORITY["EPSG","8901"]],'
    'UNIT["degree",0.0174532925199433,AUTHORITY["EPSG","9122"]],'
    'AXIS["Latitude",NORTH],AXIS["Longitude",EAST],AUTHORITY["EPSG","4326"]]';

class Geometri {
  Geometri(this.blob, this.minX, this.minY, this.maxX, this.maxY);
  final Uint8List blob;
  final double minX, minY, maxX, maxY;
}

Uint8List _baslik(ByteData b, bool zarf) {
  // 'GP', sürüm 0, bayraklar: bit0 küçük sonlu, bit1-3 zarf türü (1: xy)
  b.setUint8(0, 0x47);
  b.setUint8(1, 0x50);
  b.setUint8(2, 0);
  b.setUint8(3, 1 | (zarf ? 2 : 0));
  b.setInt32(4, wgs84, Endian.little);
  return b.buffer.asUint8List();
}

Geometri nokta(double boylam, double enlem) {
  final b = ByteData(8 + 21);
  _baslik(b, false);
  b.setUint8(8, 1);
  b.setUint32(9, 1, Endian.little);
  b.setFloat64(13, boylam, Endian.little);
  b.setFloat64(21, enlem, Endian.little);
  return Geometri(b.buffer.asUint8List(), boylam, enlem, boylam, enlem);
}

// koordinatlar: [(boylam, enlem)], en az 2 nokta
Geometri cizgi(List<(double, double)> k) {
  var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
  for (final (x, y) in k) {
    minX = min(minX, x);
    minY = min(minY, y);
    maxX = max(maxX, x);
    maxY = max(maxY, y);
  }
  final b = ByteData(8 + 32 + 9 + 16 * k.length);
  _baslik(b, true);
  b.setFloat64(8, minX, Endian.little);
  b.setFloat64(16, maxX, Endian.little);
  b.setFloat64(24, minY, Endian.little);
  b.setFloat64(32, maxY, Endian.little);
  b.setUint8(40, 1);
  b.setUint32(41, 2, Endian.little);
  b.setUint32(45, k.length, Endian.little);
  var o = 49;
  for (final (x, y) in k) {
    b.setFloat64(o, x, Endian.little);
    b.setFloat64(o + 8, y, Endian.little);
    o += 16;
  }
  return Geometri(b.buffer.asUint8List(), minX, minY, maxX, maxY);
}

// Katman tanımı: geometri türü 'POINT', 'LINESTRING' veya null (geometrisiz tablo); alanlar (ad, tür).
// Tür: TEXT, INTEGER, REAL, DATETIME (UTC, 'YYYY-MM-DDTHH:MM:SS.SSSZ').
class Katman {
  const Katman(this.ad, this.geometri, this.alanlar, this.aciklama);
  final String ad;
  final String? geometri;
  final List<(String, String)> alanlar;
  final String aciklama;
}

String gpkgZamani(DateTime t) {
  final u = t.toUtc();
  String iki(int v) => v.toString().padLeft(2, '0');
  return '${u.year}-${iki(u.month)}-${iki(u.day)}T${iki(u.hour)}:${iki(u.minute)}:${iki(u.second)}.'
      '${u.millisecond.toString().padLeft(3, '0')}Z';
}

class GeoPackage {
  GeoPackage._(this.db, this.yol);
  final Database db;
  final String yol;

  // Dosyayı açar; yoksa temel GeoPackage tablolarıyla oluşturur.
  static GeoPackage ac(String yol) {
    final db = sqlite3.open(yol);
    final gp = GeoPackage._(db, yol);
    // Temel tablolar yoksa (yeni dosya veya oluşturulurken yarıda kalmış dosya) tek işlemde oluşturulur
    if (db.select("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'gpkg_contents'").isEmpty) {
      db.execute('PRAGMA application_id = 1196444487'); // 'GPKG'
      db.execute('PRAGMA user_version = 10300'); // GeoPackage 1.3
      gp.islem(gp._temelTablolar);
    }
    return gp;
  }

  void _temelTablolar() {
    db.execute('DROP TABLE IF EXISTS gpkg_spatial_ref_sys');
    db.execute('CREATE TABLE gpkg_spatial_ref_sys (srs_name TEXT NOT NULL, srs_id INTEGER NOT NULL PRIMARY KEY, '
        'organization TEXT NOT NULL, organization_coordsys_id INTEGER NOT NULL, definition TEXT NOT NULL, description TEXT)');
    final s = db.prepare('INSERT INTO gpkg_spatial_ref_sys VALUES (?,?,?,?,?,?)');
    s.execute(['Undefined cartesian SRS', -1, 'NONE', -1, 'undefined', 'undefined cartesian coordinate reference system']);
    s.execute(['Undefined geographic SRS', 0, 'NONE', 0, 'undefined', 'undefined geographic coordinate reference system']);
    s.execute(['WGS 84 geodetic', wgs84, 'EPSG', wgs84, _wgs84Wkt,
        'longitude/latitude coordinates in decimal degrees on the WGS 84 spheroid']);
    s.close();
    db.execute('CREATE TABLE gpkg_contents (table_name TEXT NOT NULL PRIMARY KEY, data_type TEXT NOT NULL, '
        "identifier TEXT UNIQUE, description TEXT DEFAULT '', "
        "last_change DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')), "
        'min_x DOUBLE, min_y DOUBLE, max_x DOUBLE, max_y DOUBLE, srs_id INTEGER, '
        'CONSTRAINT fk_gc_r_srs_id FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys(srs_id))');
    db.execute('CREATE TABLE gpkg_geometry_columns (table_name TEXT NOT NULL, column_name TEXT NOT NULL, '
        'geometry_type_name TEXT NOT NULL, srs_id INTEGER NOT NULL, z TINYINT NOT NULL, m TINYINT NOT NULL, '
        'CONSTRAINT pk_geom_cols PRIMARY KEY (table_name, column_name), '
        'CONSTRAINT uk_gc_table_name UNIQUE (table_name), '
        'CONSTRAINT fk_gc_tn FOREIGN KEY (table_name) REFERENCES gpkg_contents(table_name), '
        'CONSTRAINT fk_gc_srs FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys (srs_id))');
  }

  bool katmanVar(String ad) => db.select('SELECT 1 FROM gpkg_contents WHERE table_name = ?', [ad]).isNotEmpty;

  // Katman yoksa oluşturur. Varsa yalnızca eksik alanları ekler (eski sürümün yazdığı gün dosyasına yeni sürüm kayıt
  // eklediğinde; eski alanlar yerinde kalır, yeni satırlarda boş olur). Yeni oluşturulduysa true.
  bool katman(Katman k, DateTime simdi) {
    if (katmanVar(k.ad)) {
      alanlariTamamla(k);
      return false;
    }
    final sutunlar = ['"fid" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL', if (k.geometri != null) '"geom" ${k.geometri}',
      for (final (a, t) in k.alanlar) '"$a" $t'];
    db.execute('CREATE TABLE "${k.ad}" (${sutunlar.join(', ')})');
    if (k.geometri != null) {
      db.execute(
          'INSERT INTO gpkg_contents (table_name, data_type, identifier, description, last_change, srs_id) '
          "VALUES (?, 'features', ?, ?, ?, ?)",
          [k.ad, k.ad, k.aciklama, gpkgZamani(simdi), wgs84]);
      db.execute("INSERT INTO gpkg_geometry_columns VALUES (?, 'geom', ?, ?, 0, 0)", [k.ad, k.geometri, wgs84]);
    } else {
      db.execute(
          'INSERT INTO gpkg_contents (table_name, data_type, identifier, description, last_change) '
          "VALUES (?, 'attributes', ?, ?, ?)",
          [k.ad, k.ad, k.aciklama, gpkgZamani(simdi)]);
    }
    return true;
  }

  // Katmanda olmayan alanları ekler (ALTER TABLE ... ADD COLUMN).
  void alanlariTamamla(Katman k) {
    final mevcut = {for (final r in db.select('PRAGMA table_info("${k.ad}")')) r['name'] as String};
    for (final (a, t) in k.alanlar) {
      if (!mevcut.contains(a)) db.execute('ALTER TABLE "${k.ad}" ADD COLUMN "$a" $t');
    }
  }

  // Satır ekler. Geometrili katmanda her satırın ilk öğesi Geometri (veya null). Katmanın kapsamı genişletilir.
  void ekle(Katman k, Iterable<List<Object?>> satirlar, DateTime simdi) {
    final adlar = [if (k.geometri != null) 'geom', for (final (a, _) in k.alanlar) a];
    final s = db.prepare('INSERT INTO "${k.ad}" (${adlar.map((a) => '"$a"').join(', ')}) '
        'VALUES (${List.filled(adlar.length, '?').join(', ')})');
    double? minX, minY, maxX, maxY;
    for (final satir in satirlar) {
      final degerler = <Object?>[];
      for (var i = 0; i < satir.length; i++) {
        var v = satir[i];
        if (i == 0 && k.geometri != null && v is Geometri) {
          minX = min(minX ?? v.minX, v.minX);
          minY = min(minY ?? v.minY, v.minY);
          maxX = max(maxX ?? v.maxX, v.maxX);
          maxY = max(maxY ?? v.maxY, v.maxY);
          v = v.blob;
        }
        if (v is double && (v.isNaN || v.isInfinite)) v = null;
        degerler.add(v);
      }
      s.execute(degerler);
    }
    s.close();
    if (minX != null) {
      final r = db.select('SELECT min_x, min_y, max_x, max_y FROM gpkg_contents WHERE table_name = ?', [k.ad]).first;
      double kucuk(Object? a, double b) => a == null ? b : min((a as num).toDouble(), b);
      double buyuk(Object? a, double b) => a == null ? b : max((a as num).toDouble(), b);
      db.execute('UPDATE gpkg_contents SET min_x = ?, min_y = ?, max_x = ?, max_y = ?, last_change = ? WHERE table_name = ?', [
        kucuk(r['min_x'], minX), kucuk(r['min_y'], minY!), buyuk(r['max_x'], maxX!), buyuk(r['max_y'], maxY!),
        gpkgZamani(simdi), k.ad
      ]);
    } else {
      db.execute('UPDATE gpkg_contents SET last_change = ? WHERE table_name = ?', [gpkgZamani(simdi), k.ad]);
    }
  }

  // QGIS'in varsayılan stil tablosu (QGIS katmanı eklerken useAsDefault = 1 olan stili kendiliğinden uygular).
  // Tablo yoksa oluşturulur; dosyada var olan katmanlar için stil yoksa eklenir.
  void stiller(Map<String, String> qml, String aciklama, DateTime simdi) {
    final tablo = Katman('layer_styles', null, const [
      ('f_table_catalog', 'TEXT(256)'), ('f_table_schema', 'TEXT(256)'), ('f_table_name', 'TEXT(256)'),
      ('f_geometry_column', 'TEXT(256)'), ('styleName', 'TEXT(30)'), ('styleQML', 'TEXT'), ('styleSLD', 'TEXT'),
      ('useAsDefault', 'BOOLEAN'), ('description', 'TEXT'), ('owner', 'TEXT(30)'), ('ui', 'TEXT(30)'),
      ('update_time', 'DATETIME'),
    ], 'QGIS katman stilleri (QGIS katmanı eklerken kendiliğinden uygular).');
    final satirlar = <List<Object?>>[];
    for (final e in qml.entries) {
      if (!katmanVar(e.key)) continue;
      if (katmanVar('layer_styles') &&
          db.select('SELECT 1 FROM layer_styles WHERE f_table_name = ?', [e.key]).isNotEmpty) {
        continue;
      }
      final geo = db.select('SELECT 1 FROM gpkg_geometry_columns WHERE table_name = ?', [e.key]).isNotEmpty ? 'geom' : '';
      satirlar.add(['', '', e.key, geo, e.key, e.value, null, 1, aciklama, '', null, gpkgZamani(simdi)]);
    }
    if (satirlar.isEmpty) return;
    katman(tablo, simdi);
    ekle(tablo, satirlar, simdi);
  }

  T islem<T>(T Function() f) {
    db.execute('BEGIN IMMEDIATE');
    try {
      final r = f();
      db.execute('COMMIT');
      return r;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void kapat() => db.close();
}
