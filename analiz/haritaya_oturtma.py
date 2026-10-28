"""GPS güzergâhını OpenStreetMap yol ağına oturtma (map matching).

Yöntem: gizli Markov modeli + Viterbi (Newson ve Krumm, 2009). Her GPS ölçümü için yakındaki yol
parçaları aday konum olur. En olası aday dizisi iki ölçüte göre seçilir:

  * Ölçüm olasılığı: GPS noktasının adaya uzaklığı (GPS hatası Gauss dağılımlı varsayılır;
    sigma = GPS_Dogruluk_m / 1,5 çünkü Android doğruluğu %68 yarıçapıdır; en az sigma_min = 4 m,
    Newson ve Krumm'un ölçtüğü değer: bina arasında telefon doğruluğu olduğundan iyi bildirir).
  * Geçiş olasılığı: iki aday arasındaki YOL mesafesi, iki GPS noktası arasındaki düz mesafeye
    yakın olmalıdır (|yol - düz| büyüdükçe olasılık üstel düşer, ölçek beta). Ayrıca oturtulmuş konumun
    yer değiştirmesi ham GPS'inkine (yön ve uzunluk) benzemelidir (ağırlık yon_agirlik): GPS hatası kısa
    sürede sabit bir sapmadır, sapmalı iz bir yan sokağın üstünden geçince oraya sapıp geri dönülmez.
  * Tek yönlü yollar (OSM oneway): ters yönde gitmek yasak değildir ama yol (1 + ters_yon) kat uzun sayılır.
    Bölünmüş caddede karşı şeride oturtmayı önler; ters yöne giren scooter yine o yola oturtulur.

Scooter her zaman haritadaki bir yolda gitmez (meydan, park, haritada olmayan geçit). Bu yüzden her
ölçüme ayrıca "yol dışı" adayı eklenir: konumu GPS noktasının kendisidir, sabit bir ceza alır. Yol,
GPS noktasına ceza eşiğinden (2,5 sigma, en az yol_disi_min = 25 m) daha uzaksa nokta olduğu yerde bırakılır.
Metre cinsinden alt sınırın nedeni: bina arasında GPS 15-20 m sabit sapabilir ve telefon doğruluğu yine 3 m
bildirir (Kadıköy'de gerçek kayıt). Bedeli: haritada yolu olmayan meydanda yola 25 m'den yakın noktalar yola çekilir.

Yalnızca yana doğru (yola dik) hata düzelir. Yol boyunca ileri-geri hata kalır.
"""

import heapq
import json
import math
import urllib.parse
import urllib.request

DEG_M = 111320.0
OVERPASS = ['https://overpass-api.de/api/interpreter', 'https://overpass.kumi.systems/api/interpreter']
# Scooter'ın giremeyeceği veya yol olmayan OSM yol türleri
HARIC = {'motorway', 'motorway_link', 'trunk', 'trunk_link', 'steps', 'construction', 'proposed', 'raceway',
         'bus_guideway', 'escape', 'elevator', 'corridor', 'platform', 'rest_area', 'services'}


def osm_indir(guney, bati, kuzey, dogu, zaman_asimi=90):
    """Kutudaki tüm highway yollarını Overpass API'den indir (OSM JSON)."""
    sorgu = (f'[out:json][timeout:{zaman_asimi}];way["highway"]({guney:.6f},{bati:.6f},{kuzey:.6f},{dogu:.6f});'
             '(._;>;);out body;')
    son_hata = None
    for adres in OVERPASS:
        try:
            istek = urllib.request.Request(adres, data=urllib.parse.urlencode({'data': sorgu}).encode(),
                                           headers={'User-Agent': 'kaan-usta-surus-analizi/1.0'})
            with urllib.request.urlopen(istek, timeout=zaman_asimi + 10) as yanit:
                return json.load(yanit)
        except Exception as e:  # sıradaki sunucuyu dene
            son_hata = e
    raise RuntimeError(f'OpenStreetMap verisi indirilemedi: {son_hata}')


def tek_yon(etiket):
    """OSM etiketlerinden yön: 1 = yol çizim yönünde tek yön, -1 = tersinde, 0 = çift yön.
    Bisiklete iki yönlü açık tek yönlü yollar (oneway:bicycle=no) çift yön sayılır."""
    if etiket.get('oneway:bicycle') == 'no' or etiket.get('cycleway') in ('opposite', 'opposite_lane', 'opposite_track'):
        return 0
    deger = etiket.get('oneway')
    if deger in ('yes', 'true', '1'):
        return 1
    if deger in ('-1', 'reverse'):
        return -1
    if deger is None and etiket.get('junction') in ('roundabout', 'circular'):
        return 1
    return 0


class YolAgi:
    """OSM yolları, yerel metrik koordinatlarda (x doğu, y kuzey; enlem0/boylam0 merkezli)."""

    HUCRE = 25.0  # mekânsal indeks hücresi (m)
    SINIR = 400.0  # yol mesafesi hesabında en fazla bakılan mesafe (m)

    def __init__(self, osm, enlem0, boylam0, ters_yon=2.0):
        self.enlem0, self.boylam0 = enlem0, boylam0
        self.ters_yon = ters_yon
        self.kx = DEG_M * math.cos(math.radians(enlem0))
        dugum = {e['id']: (e['lat'], e['lon']) for e in osm.get('elements', []) if e.get('type') == 'node'}
        self.xy = {i: self.yerel(*p) for i, p in dugum.items()}
        self.parcalar = []  # (u, v, uzunluk, yol no)
        self.yon = []  # parça başına tek yön: 1 = yalnızca u->v, -1 = yalnızca v->u, 0 = çift yön
        self.yollar = []  # yol no -> dict(id, ad, tur)
        self.komsu = {}
        for e in osm.get('elements', []):
            if e.get('type') != 'way':
                continue
            etiket = e.get('tags', {})
            if etiket.get('highway') in HARIC or etiket.get('area') == 'yes':
                continue  # alan (meydan) kenarları yol sayılmaz; içi "yol dışı" adayıyla karşılanır
            n = [i for i in e.get('nodes', []) if i in self.xy]
            yol_no = len(self.yollar)
            tek = tek_yon(etiket)
            self.yollar.append(dict(id=e.get('id'), ad=etiket.get('name') or etiket.get('ref'), tur=etiket.get('highway')))
            for u, v in zip(n, n[1:]):
                if u == v:
                    continue
                (ax, ay), (bx, by) = self.xy[u], self.xy[v]
                L = math.hypot(bx - ax, by - ay)
                if L < 0.01:
                    continue
                self.parcalar.append((u, v, L, yol_no))
                self.yon.append(tek)
                self.komsu.setdefault(u, []).append((v, self.maliyet(L, tek, 1)))
                self.komsu.setdefault(v, []).append((u, self.maliyet(L, tek, -1)))
        self.izgara = {}
        for i, (u, v, _, _) in enumerate(self.parcalar):
            (ax, ay), (bx, by) = self.xy[u], self.xy[v]
            for gx in range(int(math.floor(min(ax, bx) / self.HUCRE)), int(math.floor(max(ax, bx) / self.HUCRE)) + 1):
                for gy in range(int(math.floor(min(ay, by) / self.HUCRE)), int(math.floor(max(ay, by) / self.HUCRE)) + 1):
                    self.izgara.setdefault((gx, gy), []).append(i)
        self._dijkstra = {}

    def maliyet(self, L, tek, yon):
        """Parça boyunca L metre gitmenin maliyeti; yon 1: u->v, -1: v->u. Tek yönlü yolda ters gitmek yasak
        değildir (scooter ters yöne girebilir) ama (1 + ters_yon) kat uzun sayılır."""
        return L * (1.0 + self.ters_yon) if tek == -yon else L

    def yerel(self, enlem, boylam):
        return (boylam - self.boylam0) * self.kx, (enlem - self.enlem0) * DEG_M

    def cografi(self, x, y):
        return self.enlem0 + y / DEG_M, self.boylam0 + x / self.kx

    def adaylar(self, x, y, yaricap, en_fazla=8):
        """(x, y)'ye yaricap içindeki yol parçalarına dik izdüşümler: (parça, px, py, u'dan uzaklık, mesafe)"""
        sonuc = []
        r = int(math.ceil(yaricap / self.HUCRE))
        gx0, gy0 = int(math.floor(x / self.HUCRE)), int(math.floor(y / self.HUCRE))
        gorulen = set()
        for gx in range(gx0 - r, gx0 + r + 1):
            for gy in range(gy0 - r, gy0 + r + 1):
                for i in self.izgara.get((gx, gy), ()):
                    if i in gorulen:
                        continue
                    gorulen.add(i)
                    u, v, L, _ = self.parcalar[i]
                    (ax, ay), (bx, by) = self.xy[u], self.xy[v]
                    k = max(0.0, min(1.0, ((x - ax) * (bx - ax) + (y - ay) * (by - ay)) / (L * L)))
                    px, py = ax + k * (bx - ax), ay + k * (by - ay)
                    d = math.hypot(x - px, y - py)
                    if d <= yaricap:
                        sonuc.append((i, px, py, k * L, d))
        sonuc.sort(key=lambda a: a[4])
        # Aynı noktaya düşen (kavşak düğümü) adayların tekrarı ayıklanır
        tekil = []
        for a in sonuc:
            if all(math.hypot(a[1] - b[1], a[2] - b[2]) > 0.5 for b in tekil):
                tekil.append(a)
            if len(tekil) >= en_fazla:
                break
        return tekil

    def _uzakliklar(self, kaynak):
        if kaynak not in self._dijkstra:
            uzak = {kaynak: 0.0}
            kuyruk = [(0.0, kaynak)]
            while kuyruk:
                d, n = heapq.heappop(kuyruk)
                if d > uzak.get(n, math.inf) or d > self.SINIR:
                    continue
                for m, L in self.komsu.get(n, ()):
                    nd = d + L
                    if nd < uzak.get(m, math.inf) and nd <= self.SINIR:
                        uzak[m] = nd
                        heapq.heappush(kuyruk, (nd, m))
            self._dijkstra[kaynak] = uzak
        return self._dijkstra[kaynak]

    def yol_mesafesi(self, a, b):
        """İki aday arasındaki en kısa yol mesafesi (ulaşılamıyorsa inf)"""
        ia, _, _, oa, _ = a
        ib, _, _, ob, _ = b
        ta, tb = self.yon[ia], self.yon[ib]
        if ia == ib:
            return self.maliyet(abs(ob - oa), ta, 1 if ob >= oa else -1)
        ua, va, La, _ = self.parcalar[ia]
        ub, vb, Lb, _ = self.parcalar[ib]
        en_iyi = math.inf
        for na, da in ((ua, self.maliyet(oa, ta, -1)), (va, self.maliyet(La - oa, ta, 1))):
            uzak = self._uzakliklar(na)
            for nb, db in ((ub, self.maliyet(ob, tb, 1)), (vb, self.maliyet(Lb - ob, tb, -1))):
                if nb in uzak:
                    en_iyi = min(en_iyi, da + uzak[nb] + db)
        return en_iyi


def oturt(olcumler, osm, yaricap=None, beta=5.0, yol_disi_ceza=2.5, max_bosluk=3.0, sigma_min=4.0, yol_disi_min=25.0,
           ters_yon=2.0, yon_agirlik=4.0):
    """GPS ölçümlerini (t, enlem, boylam, dogruluk) yola oturt.

    Her ölçüme 'o_enlem', 'o_boylam' (oturtulmuş konum), 'yolda' (True/False), 'kayma_m' (ham konumdan
    uzaklık) ve 'yol' (oturtulduğu OSM yolu: dict(id, ad, tur); yol dışıysa None) alanlarını ekler.
    Ağ kuruluş özetini döndürür.
    """
    if not olcumler:
        return dict(parca=0, yolda=0, toplam=0)
    enlem0 = sum(o['enlem'] for o in olcumler) / len(olcumler)
    boylam0 = sum(o['boylam'] for o in olcumler) / len(olcumler)
    ag = YolAgi(osm, enlem0, boylam0, ters_yon)

    # Ardışık ölçümler arasında GPS kesintisi varsa zincir bölünür ve ayrı ayrı çözülür
    zincirler, zincir = [], []
    for o in olcumler:
        if zincir and o['t'] - zincir[-1]['t'] > max_bosluk:
            zincirler.append(zincir)
            zincir = []
        zincir.append(o)
    if zincir:
        zincirler.append(zincir)

    for zincir in zincirler:
        _viterbi(ag, zincir, yaricap, beta, yol_disi_ceza, sigma_min, yol_disi_min, yon_agirlik)
    yolda = sum(1 for o in olcumler if o['yolda'])
    return dict(parca=len(ag.parcalar), yolda=yolda, toplam=len(olcumler),
                ort_kayma=sum(o['kayma_m'] for o in olcumler) / len(olcumler))


def _viterbi(ag, zincir, yaricap, beta, yol_disi_ceza, sigma_min, yol_disi_min, yon_agirlik):
    adaylar = []
    for o in zincir:
        x, y = ag.yerel(o['enlem'], o['boylam'])
        sigma = max((o.get('dogruluk') or 10.0) / 1.5, sigma_min)
        esik = max(yol_disi_ceza, yol_disi_min / sigma)  # yol dışı eşiği, sigma biriminde
        r = yaricap or max(4 * sigma, 25.0, yol_disi_min + 10.0)
        liste = [dict(yol=a, x=a[1], y=a[2], log=-0.5 * (a[4] / sigma) ** 2) for a in ag.adaylar(x, y, r)]
        liste.append(dict(yol=None, x=x, y=y, log=-0.5 * esik ** 2))  # yol dışı adayı
        adaylar.append((x, y, liste))

    puan = [a['log'] for a in adaylar[0][2]]
    geri = []
    for k in range(1, len(zincir)):
        (x0, y0, onceki), (x1, y1, simdiki) = adaylar[k - 1], adaylar[k]
        duz = math.hypot(x1 - x0, y1 - y0)
        yeni, oklar = [], []
        for b in simdiki:
            en_iyi, en_iyi_i = -math.inf, 0
            for i, a in enumerate(onceki):
                if puan[i] == -math.inf:
                    continue
                if a['yol'] is not None and b['yol'] is not None:
                    mesafe = ag.yol_mesafesi(a['yol'], b['yol'])
                    gecis = 0.0
                else:
                    mesafe = math.hypot(b['x'] - a['x'], b['y'] - a['y'])
                    gecis = 0.0 if a['yol'] is None and b['yol'] is None else -1.0  # yol <-> yol dışı geçiş cezası
                if mesafe == math.inf:
                    continue
                # Oturtulmuş hareket, ham GPS'in hareketine (yön ve uzunluk) benzemeli: GPS hatası kısa sürede
                # sabit bir sapma gibi davranır, sapmalı iz yan sokağa değince kısa bir gidip dönme oluşmasın
                fark = math.hypot(b['x'] - a['x'] - (x1 - x0), b['y'] - a['y'] - (y1 - y0))
                p = puan[i] + gecis - (abs(mesafe - duz) + yon_agirlik * fark) / beta
                if p > en_iyi:
                    en_iyi, en_iyi_i = p, i
            yeni.append(en_iyi + b['log'] if en_iyi > -math.inf else -math.inf)
            oklar.append(en_iyi_i)
        if all(p == -math.inf for p in yeni):  # hiçbir geçiş mümkün değil: zinciri burada yeniden başlat
            yeni = [b['log'] for b in simdiki]
            oklar = [None] * len(simdiki)
        puan = yeni
        geri.append(oklar)

    # Geriye doğru en olası yolu çıkar
    i = max(range(len(puan)), key=lambda j: puan[j])
    secim = [i]
    for oklar in reversed(geri):
        i = oklar[i]
        if i is None:  # zincirin yeniden başladığı yer: önceki kısım için ayrıca en iyi aday
            break
        secim.append(i)
    secim.reverse()
    bas = len(zincir) - len(secim)
    if bas > 0:  # yeniden başlama noktasından öncesini ayrı çöz
        _viterbi(ag, zincir[:bas], yaricap, beta, yol_disi_ceza, sigma_min, yol_disi_min, yon_agirlik)
    for o, (x, y, liste), j in zip(zincir[bas:], adaylar[bas:], secim):
        a = liste[j]
        o['o_enlem'], o['o_boylam'] = ag.cografi(a['x'], a['y'])
        o['yolda'] = a['yol'] is not None
        o['yol'] = ag.yollar[ag.parcalar[a['yol'][0]][3]] if a['yol'] is not None else None
        o['kayma_m'] = math.hypot(a['x'] - x, a['y'] - y)
