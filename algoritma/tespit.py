"""Claude'un çukur ve konfor puanı algoritması.

SÜRÜM "0-altyapi": YER TUTUCU. Kural, onaylı örnek dosyadaki yer tutucu hesabın ve v1 darbe kuralının aynısıdır; hiçbir
değer gerçek geliştirme verisiyle ayarlanmadı. Altyapının (okuma, yazma, karşılaştırma) uçtan uca çalıştığını göstermek
içindir. Gerçek algoritma geliştirme sürüşleriyle kurulur ve yeni sürüm adı alır; "0-" ile başlayan sürüm test
sürüşlerinde kullanılamaz (uret.py ve karsilastir.py reddeder).

Yalnızca ham veri kullanılır (ivme + GPS). Claude noktasının konumu darbe anındaki ham GPS konumudur (`konum_at`,
insan işaretleriyle aynı kural; GPS gecikmesi düzeltilmez).
"""

import math

from ortak import dikey_sarsinti, konum_at

SURUM = "0-altyapi (yer tutucu, ayarlanmadı)"

PARAMETRELER = {
    "pencere_s": 0.5,  # sarsıntı özeti penceresi
    "taban_pencere": 20,  # çevre (taban) RMS için önceki / sonraki pencere sayısı (10 sn)
    "oran": 4.0,  # darbe: pencere tepesi >= oran x taban RMS
    "en_az_ms2": 10.0,  # ve tepe >= bu değer
    "birlestirme_s": 1.0,  # bu süreden yakın iki darbe tek sayılır (büyüğü kalır)
    "hareket_kmh": 3.0,  # yalnızca GPS hızı bu değer ve üstündeyken (başta / sondaki duruş ve dokunuşlar dışarıda)
    "hiz_ussu": 0.65,  # konfor indeksi: RMS x (ref_hiz / ort_hiz)^hiz_ussu
    "ref_hiz_kmh": 15.0,
    "puan_a": 5.6,  # puan = a − b x indeks, 1-5 arasına sıkıştırılır
    "puan_b": 0.42,
}


def _pencereler(t, dikey, p):
    """Pencere numarası -> [kare toplamı, örnek sayısı, |tepe|, tepe anı]."""
    pen = {}
    for ti, d in zip(t, dikey):
        w = int(ti // p["pencere_s"])
        q = pen.setdefault(w, [0.0, 0, 0.0, ti])
        q[0] += d * d
        q[1] += 1
        if abs(d) > q[2]:
            q[2], q[3] = abs(d), ti
    return pen


def hesapla(kayit, ivme, p=PARAMETRELER):
    """Döner: (darbeler [(t_s, tepe_ms2, oran)], puan bilgisi {'puan_ondalik', 'indeks_ms2'} veya None)."""
    t, x, y, z = ivme
    if not t or not kayit.gps:
        return [], None
    dikey = dikey_sarsinti(t, x, y, z)
    pen = _pencereler(t, dikey, p)
    hareket = {}
    for w, (kare, n, tepe, tt) in pen.items():
        hiz = konum_at(kayit.gps, (w + 0.5) * p["pencere_s"])[2]
        if hiz is not None and hiz >= p["hareket_kmh"]:
            hareket[w] = (math.sqrt(kare / n), tepe, tt)
    darbeler = []
    for w, (rms, tepe, tt) in sorted(hareket.items()):
        n = p["taban_pencere"]
        once = sorted(hareket[i][0] for i in range(w - n, w) if i in hareket)
        sonra = sorted(hareket[i][0] for i in range(w + 1, w + n + 1) if i in hareket)
        taban = max([d[len(d) // 2] for d in (once, sonra) if d] or [0.0])
        if taban > 0 and tepe >= p["oran"] * taban and tepe >= p["en_az_ms2"]:
            if darbeler and tt - darbeler[-1][0] < p["birlestirme_s"]:
                if tepe > darbeler[-1][1]:
                    darbeler[-1] = (tt, tepe, tepe / taban)
            else:
                darbeler.append((tt, tepe, tepe / taban))
    puan = None
    hizlar = [g["hiz_kmh"] for g in kayit.gps if g["hiz_kmh"] is not None and g["hiz_kmh"] >= p["hareket_kmh"]]
    if hareket and hizlar:
        rms = math.sqrt(sum(v[0] ** 2 for v in hareket.values()) / len(hareket))
        indeks = rms * (p["ref_hiz_kmh"] / (sum(hizlar) / len(hizlar))) ** p["hiz_ussu"]
        puan = {"indeks_ms2": indeks, "puan_ondalik": min(5.0, max(1.0, p["puan_a"] - p["puan_b"] * indeks))}
    return darbeler, puan


def guven(oran, p=PARAMETRELER):
    return min(1.0, 0.5 + (oran - p["oran"]) / 8)
