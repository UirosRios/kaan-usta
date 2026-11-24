"""Kullanıcının QGIS projesinden (.qgz / .qgs) katman stillerini çıkarıp qgis/stiller/<katman>.qml olarak yazar.

Yalnızca görünüm (Symbology) alınır: çizim kuralları, renk, simge, efekt, saydamlık. Proje dosyasındaki yazar adı,
dosya yolları, birleştirmeler ve alan ayarları alınmaz (depo herkese açık). Bu QML'ler GeoPackage dosyalarının
`layer_styles` tablosuna gömülür; QGIS katmanı eklerken bu stili kendiliğinden uygular.

Dereceli (graduated) çizimde en alt sınıf 0'dan, en üst sınıf çok büyük bir değere kadar genişletilir: örnek veriden
alınan sınıf sınırlarının dışında kalan gerçek değerler (ör. Arnavut kaldırımında daha yüksek sarsıntı) haritadan
kaybolmasın.

Kullanım:  python qgis/stil_cikar.py proje.qgz
"""

import os
import sys
import xml.etree.ElementTree as ET
import zipfile

KATMANLAR = ["kayitlar", "gps_noktalari", "insan_cukurlar", "insan_puanlar", "claude_cukurlar", "claude_puanlar"]
ALINAN = ["renderer-v2", "selection", "labeling", "blendMode", "featureBlendMode", "layerOpacity"]
GEOMETRI_KODU = {"Point": "0", "Line": "1", "Polygon": "2"}
CIKTI = os.path.join(os.path.dirname(os.path.abspath(__file__)), "stiller")


def proje_oku(yol):
    if yol.endswith(".qgz"):
        with zipfile.ZipFile(yol) as z:
            ad = next(n for n in z.namelist() if n.endswith(".qgs"))
            return ET.fromstring(z.read(ad))
    return ET.parse(yol).getroot()


def dereceli_genislet(renderer):
    araliklar = list(renderer.iter("range"))
    if not araliklar:
        return
    araliklar.sort(key=lambda r: float(r.get("lower")))
    araliklar[0].set("lower", "0")
    ilk_ust = araliklar[0].get("label", "").split(" - ")[-1]
    araliklar[0].set("label", f"0 - {ilk_ust}")
    son = araliklar[-1]
    son.set("upper", "1000000")
    alt = son.get("label", "").split(" - ")[0]
    son.set("label", f"{alt} ve üstü")


def main():
    kok = proje_oku(sys.argv[1])
    surum = kok.get("version", "")
    os.makedirs(CIKTI, exist_ok=True)
    for ml in kok.iter("maplayer"):
        ad = (ml.findtext("layername") or "").split(" — ")[-1].strip()
        if ad not in KATMANLAR:
            continue
        qgis = ET.Element("qgis", {"version": surum, "styleCategories": "Symbology|Labeling",
                                   "labelsEnabled": ml.get("labelsEnabled", "0")})
        for etiket in ALINAN:
            e = ml.find(etiket)
            if e is not None:
                qgis.append(e)
        r = qgis.find("renderer-v2")
        if r is not None and r.get("type") == "graduatedSymbol":
            dereceli_genislet(r)
        tur = ET.SubElement(qgis, "layerGeometryType")
        tur.text = GEOMETRI_KODU.get(ml.get("geometry", ""), "0")
        ET.indent(qgis)
        metin = "<!DOCTYPE qgis PUBLIC 'http://mrcc.com/qgis.dtd' 'SYSTEM'>\n" + ET.tostring(qgis, encoding="unicode") + "\n"
        with open(os.path.join(CIKTI, f"{ad}.qml"), "w", encoding="utf-8") as f:
            f.write(metin)
        print(f"{ad}.qml ({r.get('type') if r is not None else '-'})")


if __name__ == "__main__":
    main()
