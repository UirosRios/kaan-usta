#!/usr/bin/env python3
"""KAAN USTA sürüş analizi: analiz betiklerini Python kurmadan çalıştıran masaüstü uygulaması (Windows).

CSV ve _bilgi.txt dosyaları pencereye sürüklenir, tek düğmeyle surus_analizi.py veya birlestir.py çalışır.
Sonuçlar CSV'nin yanına yazılır, bitince harita açılır.

Betikler uygulamanın içinde gömülü gelir. Betikler değişince uygulamayı yeniden indirmek gerekmez:
  * "GitHub'dan güncelle": deponun varsayılan dalındaki analiz/*.py dosyaları indirilir.
  * "Betik dosyası yükle": seçilen .py dosyaları kopyalanır (diğerleri olduğu gibi kalır).
Güncellenen betikler kullanıcı klasörüne yazılır (%APPDATA%/KaanUstaAnaliz/betikler) ve gömülülerin yerine
kullanılır. "Varsayılana dön" bu klasörü siler.

Sınır: Uygulamanın içinde yalnızca Python'un standart kütüphanesi ve matplotlib vardır. Yeni betikler başka bir
kütüphane (pandas vb.) kullanırsa uygulamanın yeniden derlenmesi gerekir (_paketlenecek_moduller).

Geliştirme sırasında doğrudan da çalışır: python masaustu/analiz_araci.py (betikler ../analiz klasöründen).
"""

import contextlib
import json
import os
import queue
import runpy
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading
import traceback
import urllib.request
from datetime import datetime

import tkinter as tk
from tkinter import filedialog, messagebox, ttk
from tkinter.scrolledtext import ScrolledText

try:
    from tkinterdnd2 import DND_FILES, TkinterDnD
except ImportError:  # sürükle-bırak yoksa dosyalar düğmeyle seçilir
    TkinterDnD = None

UYGULAMA = 'KAAN USTA – Sürüş Analizi'
DEPO = 'UirosRios/kaan-usta'
DEPO_KLASORU = 'analiz'
ANALIZ = 'surus_analizi.py'
BIRLESTIR = 'birlestir.py'
GEREKLI = (ANALIZ, BIRLESTIR, 'haritaya_oturtma.py')

os.environ.setdefault('MPLBACKEND', 'Agg')  # grafik iş parçacığında çizilir, pencere açılmaz
sys.dont_write_bytecode = True  # betik klasörlerine __pycache__ yazılmasın


def _paketlenecek_moduller():
    """Hiç çağrılmaz. PyInstaller yalnızca kodda içe aktarılan modülleri pakete koyar; betikler dışarıdan
    yüklendiği için kullandıkları (ve yeni sürümlerinin kullanabileceği) modüller burada listelenir."""
    import argparse, bisect, csv, glob, heapq, html, io, itertools, functools, math, random, statistics  # noqa
    import collections, dataclasses, datetime, decimal, fractions, gzip, hashlib, pathlib, pprint  # noqa
    import string, textwrap, time, unicodedata, urllib.parse, urllib.request, urllib.error, zipfile  # noqa
    import matplotlib, matplotlib.pyplot, matplotlib.colors, matplotlib.backends.backend_agg, numpy  # noqa


# ---------------------------------------------------------------- betik klasörleri

def gomulu_klasor():
    if getattr(sys, 'frozen', False):
        return os.path.join(sys._MEIPASS, 'betikler')
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', DEPO_KLASORU)


def kullanici_kok():
    taban = os.environ.get('APPDATA') or os.path.join(os.path.expanduser('~'), '.config')
    return os.path.join(taban, 'KaanUstaAnaliz')


def kullanici_klasor():
    return os.path.join(kullanici_kok(), 'betikler')


def etkin_klasor():
    k = kullanici_klasor()
    return k if all(os.path.isfile(os.path.join(k, d)) for d in GEREKLI) else gomulu_klasor()


def surum_oku(klasor):
    try:
        with open(os.path.join(klasor, 'surum.json'), encoding='utf-8') as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def surum_metni():
    klasor = etkin_klasor()
    s = surum_oku(klasor)
    kaynak = 'gömülü' if klasor == gomulu_klasor() else s.get('kaynak', 'elle yüklendi')
    ayrinti = ', '.join(x for x in (s.get('tarih'), s.get('commit')) if x)
    return f'Betikler: {kaynak}' + (f' ({ayrinti})' if ayrinti else '')


def py_dogrula(yol):
    """Dosya geçerli Python mu (bozuk / yarım indirilmiş betik yüklenmesin)"""
    with open(yol, 'rb') as f:
        compile(f.read(), yol, 'exec')


def klasoru_degistir(yeni):
    """Kullanıcı betik klasörünü 'yeni' klasörle değiştir"""
    hedef = kullanici_klasor()
    if os.path.isdir(hedef):
        shutil.rmtree(hedef)
    os.replace(yeni, hedef)


def github_al(url):
    istek = urllib.request.Request(url, headers={'User-Agent': 'KaanUstaAnaliz'})
    with urllib.request.urlopen(istek, timeout=30) as yanit:
        return yanit.read()


def github_guncelle(yaz):
    """Deponun varsayılan dalındaki analiz/*.py dosyalarını indir ve kullanıcı klasörüne koy"""
    api = f'https://api.github.com/repos/{DEPO}'
    dal = json.loads(github_al(api))['default_branch']
    yaz(f'GitHub: {DEPO}, dal: {dal}\n')
    dosyalar = [d for d in json.loads(github_al(f'{api}/contents/{DEPO_KLASORU}?ref={dal}'))
                if d['type'] == 'file' and d['name'].endswith('.py')]
    eksik = set(GEREKLI) - {d['name'] for d in dosyalar}
    if eksik:
        raise RuntimeError(f'Depoda eksik betik: {", ".join(sorted(eksik))}')
    son = json.loads(github_al(f'{api}/commits?sha={dal}&path={DEPO_KLASORU}&per_page=1'))[0]
    os.makedirs(kullanici_kok(), exist_ok=True)
    gecici = tempfile.mkdtemp(dir=kullanici_kok())
    try:
        for d in dosyalar:
            yaz(f'  {d["name"]}\n')
            yol = os.path.join(gecici, d['name'])
            with open(yol, 'wb') as f:
                f.write(github_al(d['download_url']))
            py_dogrula(yol)
        with open(os.path.join(gecici, 'surum.json'), 'w', encoding='utf-8') as f:
            json.dump({'kaynak': 'GitHub', 'tarih': son['commit']['committer']['date'][:10],
                       'commit': son['sha'][:7]}, f)
        klasoru_degistir(gecici)
    except BaseException:
        shutil.rmtree(gecici, ignore_errors=True)
        raise
    yaz(f'{len(dosyalar)} betik güncellendi (son değişiklik {son["commit"]["committer"]["date"][:10]}, '
        f'{son["sha"][:7]}: {son["commit"]["message"].splitlines()[0]})\n')


def elle_yukle(yollar):
    """Seçilen .py dosyalarını etkin betiklerin üzerine kopyala"""
    for y in yollar:
        py_dogrula(y)
    os.makedirs(kullanici_kok(), exist_ok=True)
    gecici = tempfile.mkdtemp(dir=kullanici_kok())
    try:
        for d in os.listdir(etkin_klasor()):
            if d.endswith('.py'):
                shutil.copy2(os.path.join(etkin_klasor(), d), gecici)
        for y in yollar:
            shutil.copy2(y, gecici)
        with open(os.path.join(gecici, 'surum.json'), 'w', encoding='utf-8') as f:
            json.dump({'kaynak': 'elle yüklendi', 'tarih': datetime.now().strftime('%Y-%m-%d')}, f)
        klasoru_degistir(gecici)
    except BaseException:
        shutil.rmtree(gecici, ignore_errors=True)
        raise


# ---------------------------------------------------------------- betik çalıştırma

class Yazici:
    """print çıktısını pencereye aktarır (iş parçacığından kuyruk ile)"""

    def __init__(self, kuyruk):
        self.kuyruk = kuyruk

    def write(self, metin):
        if metin:
            self.kuyruk.put(('yaz', metin))
        return len(metin)

    def flush(self):
        pass


def betik_calistir(betik, argumanlar, yaz):
    """Betiği bu süreçte '__main__' olarak çalıştır. Başarılıysa True."""
    klasor = etkin_klasor()
    # Betiklerin birbirini içe aktarması (import surus_analizi) güncel dosyaları alsın
    for k in (klasor, gomulu_klasor()):
        for d in os.listdir(k):
            if d.endswith('.py'):
                sys.modules.pop(d[:-3], None)
    eski_argv, eski_yol = sys.argv, list(sys.path)
    sys.argv = [betik] + argumanlar
    sys.path.insert(0, klasor)
    try:
        with contextlib.redirect_stdout(yaz), contextlib.redirect_stderr(yaz):
            runpy.run_path(os.path.join(klasor, betik), run_name='__main__')
        return True
    except SystemExit as e:  # argparse hataları ve -h
        return e.code in (None, 0)
    except Exception:
        yaz.write(traceback.format_exc())
        return False
    finally:
        sys.argv, sys.path[:] = eski_argv, eski_yol


def ac(yol):
    """Dosya / klasörü Windows'ta varsayılan programla aç"""
    if not os.path.exists(yol):
        return
    if hasattr(os, 'startfile'):
        os.startfile(yol)
    elif sys.platform == 'darwin':
        subprocess.Popen(['open', yol])
    else:
        subprocess.Popen(['xdg-open', yol], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)



# ---------------------------------------------------------------- pencere

class Uygulama:
    def __init__(self, kok):
        self.kok = kok
        self.girdiler = []  # CSV, _bilgi.txt ve klasör yolları
        self.kuyruk = queue.Queue()
        self.calisiyor = False
        kok.title(UYGULAMA)
        kok.geometry('820x640')
        kok.minsize(640, 480)
        self.simge_yukle()

        ust = ttk.Frame(kok, padding=10)
        ust.pack(fill='both', expand=True)

        self.birakma = tk.Label(
            ust, relief='groove', bd=2, height=3, bg='#f3f6fa', fg='#33475b', font=('Segoe UI', 11),
            text=('CSV ve _bilgi.txt dosyalarını (veya kayıtların bulunduğu klasörü) buraya sürükleyip bırakın'
                  if TkinterDnD else 'Dosyaları aşağıdaki düğmelerle seçin'))
        self.birakma.pack(fill='x')

        satir = ttk.Frame(ust)
        satir.pack(fill='x', pady=(6, 0))
        ttk.Button(satir, text='Dosya seç…', command=self.dosya_sec).pack(side='left')
        ttk.Button(satir, text='Klasör seç…', command=self.klasor_sec).pack(side='left', padx=4)
        ttk.Button(satir, text='Listeyi temizle', command=self.temizle).pack(side='right')
        ttk.Button(satir, text='Seçileni çıkar', command=self.cikar).pack(side='right', padx=4)

        self.liste = tk.Listbox(ust, height=6, selectmode='extended', activestyle='none')
        self.liste.pack(fill='x', pady=6)

        islem = ttk.LabelFrame(ust, text='Çalıştır', padding=8)
        islem.pack(fill='x')
        self.dugmeler = []
        b = ttk.Button(islem, text='Analiz et (her sürüş ayrı)', command=self.analiz_et)
        b.grid(row=0, column=0, sticky='we')
        self.dugmeler.append(b)
        b = ttk.Button(islem, text='Birleştir (yol kalitesi haritası)', command=self.birlestir)
        b.grid(row=0, column=1, sticky='we', padx=6)
        self.dugmeler.append(b)
        self.tek_tek = tk.BooleanVar(value=False)
        ttk.Checkbutton(islem, text='Birleştirirken her sürüşün ayrı analizini de yaz',
                        variable=self.tek_tek).grid(row=0, column=2, sticky='w')
        ttk.Label(islem, text='Ek ayarlar:').grid(row=1, column=0, sticky='e', pady=(6, 0))
        self.ek = ttk.Entry(islem)
        self.ek.grid(row=1, column=1, sticky='we', padx=6, pady=(6, 0))
        b = ttk.Button(islem, text='Tüm ayarları göster', command=self.ayarlari_goster)
        b.grid(row=1, column=2, sticky='w', pady=(6, 0))
        self.dugmeler.append(b)
        ttk.Label(islem, text='Boş bırakılırsa varsayılanlar kullanılır. Örnek: --darbe-taban ortak --gecikme 1.5',
                  foreground='#6b7785').grid(row=2, column=1, columnspan=2, sticky='w')
        islem.columnconfigure(1, weight=1)

        self.gunluk = ScrolledText(ust, height=12, font=('Consolas', 9), state='disabled', wrap='word')
        self.gunluk.pack(fill='both', expand=True, pady=(8, 6))

        alt = ttk.LabelFrame(ust, text='Betikler', padding=8)
        alt.pack(fill='x')
        self.surum = ttk.Label(alt, text=surum_metni())
        self.surum.pack(side='left')
        ttk.Button(alt, text='Klasörü aç', command=lambda: ac(etkin_klasor())).pack(side='right')
        b = ttk.Button(alt, text='Varsayılana dön', command=self.varsayilana_don)
        b.pack(side='right', padx=4)
        self.dugmeler.append(b)
        b = ttk.Button(alt, text='Betik dosyası yükle…', command=self.betik_yukle)
        b.pack(side='right')
        self.dugmeler.append(b)
        b = ttk.Button(alt, text="GitHub'dan güncelle", command=self.guncelle)
        b.pack(side='right', padx=4)
        self.dugmeler.append(b)

        if TkinterDnD:
            for w in (self.birakma, self.liste):
                w.drop_target_register(DND_FILES)
                w.dnd_bind('<<Drop>>', self.birak)
        kok.after(100, self.kuyrugu_isle)

    def simge_yukle(self):
        kok_yol = getattr(sys, '_MEIPASS', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
        try:
            self.simge = tk.PhotoImage(file=os.path.join(kok_yol, 'tasarim', 'logo.png')).subsample(16)
            self.kok.iconphoto(True, self.simge)
        except tk.TclError:
            pass

    # ------------------------------------------------ dosya listesi

    def ekle(self, yollar):
        for y in yollar:
            y = os.path.normpath(y)
            if not (os.path.isdir(y) or y.lower().endswith(('.csv', '.txt'))):
                self.yaz(f'Atlandı (CSV / TXT değil): {y}\n')
            elif y not in self.girdiler:
                self.girdiler.append(y)
                self.liste.insert('end', y)

    def birak(self, olay):
        self.ekle(self.kok.tk.splitlist(olay.data))

    def dosya_sec(self):
        self.ekle(filedialog.askopenfilenames(
            title='Kayıt dosyalarını seçin', filetypes=[('Kayıtlar', '*.csv *.txt'), ('Tüm dosyalar', '*.*')]))

    def klasor_sec(self):
        k = filedialog.askdirectory(title='Kayıtların bulunduğu klasörü seçin')
        if k:
            self.ekle([k])

    def cikar(self):
        for i in reversed(self.liste.curselection()):
            self.liste.delete(i)
            del self.girdiler[i]

    def temizle(self):
        self.liste.delete(0, 'end')
        self.girdiler.clear()

    def hazirla(self):
        """CSV / klasör listesini döndürür. Başka klasörden bırakılan _bilgi.txt, betik CSV'nin yanında
        aradığı için CSV'nin yanına kopyalanır."""
        csvler = [g for g in self.girdiler if os.path.isdir(g) or g.lower().endswith('.csv')]
        csv_adlari = {os.path.basename(c).lower(): c for c in csvler if not os.path.isdir(c)}
        for txt in (g for g in self.girdiler if g.lower().endswith('.txt')):
            ad = os.path.basename(txt)
            if not ad.lower().endswith('_bilgi.txt'):
                self.yaz(f'Uyarı: {ad} bir _bilgi.txt dosyası değil, kullanılmadı\n')
                continue
            csv_yol = csv_adlari.get(ad[:-len('_bilgi.txt')].lower() + '.csv')
            if csv_yol is None:
                self.yaz(f'Uyarı: {ad} dosyasının CSV\'si listede yok, kullanılmadı\n')
                continue
            hedef = os.path.join(os.path.dirname(csv_yol), ad)
            if not os.path.exists(hedef):
                shutil.copy2(txt, hedef)
                self.yaz(f'{ad} CSV\'nin yanına kopyalandı\n')
        return csvler

    # ------------------------------------------------ çalıştırma

    def ek_ayarlar(self):
        try:
            return shlex.split(self.ek.get())
        except ValueError as e:
            messagebox.showerror(UYGULAMA, f'Ek ayarlar okunamadı: {e}')
            return None

    def analiz_et(self):
        csvler, ek = self.hazirla(), self.ek_ayarlar()
        if ek is None:
            return
        if not csvler:
            messagebox.showinfo(UYGULAMA, 'Önce en az bir CSV dosyası veya klasör ekleyin.')
            return
        tek = [c for c in csvler if not os.path.isdir(c)]
        if len(csvler) == 1 and tek:
            ad = os.path.splitext(os.path.basename(tek[0]))[0]
            sonuc = os.path.join(os.path.dirname(tek[0]), f'{ad}_analiz', f'{ad}_harita.html')
        else:
            sonuc = csvler[0] if os.path.isdir(csvler[0]) else os.path.dirname(csvler[0])
        self.baslat(ANALIZ, csvler + ek, [sonuc])

    def birlestir(self):
        csvler, ek = self.hazirla(), self.ek_ayarlar()
        if ek is None:
            return
        if not csvler:
            messagebox.showinfo(UYGULAMA, 'Önce birleştirilecek CSV dosyalarını veya klasörü ekleyin.')
            return
        ilk = csvler[0]
        cikti = os.path.join(ilk if os.path.isdir(ilk) else os.path.dirname(ilk), 'birlesik_analiz')
        argumanlar = csvler + ['--cikti', cikti] + (['--tek-tek'] if self.tek_tek.get() else []) + ek
        self.baslat(BIRLESTIR, argumanlar, [cikti, os.path.join(cikti, 'birlesik_harita.html')])

    def ayarlari_goster(self):
        self.baslat(ANALIZ, ['-h'], [])

    def baslat(self, betik, argumanlar, acilacak):
        self.yaz(f'\n=== {betik} {datetime.now():%H:%M:%S} ===\n')

        def is_():
            basarili = betik_calistir(betik, argumanlar, Yazici(self.kuyruk))
            self.kuyruk.put(('bitti', (basarili, acilacak)))
        self.arka_planda(is_)

    def arka_planda(self, is_):
        self.calisiyor = True
        for b in self.dugmeler:
            b.state(['disabled'])
        self.kok.config(cursor='watch')
        threading.Thread(target=is_, daemon=True).start()

    def kuyrugu_isle(self):
        try:
            while True:
                tur, veri = self.kuyruk.get_nowait()
                if tur == 'yaz':
                    self.yaz(veri)
                    continue
                self.calisiyor = False
                for b in self.dugmeler:
                    b.state(['!disabled'])
                self.kok.config(cursor='')
                self.surum.config(text=surum_metni())
                if tur == 'bitti':
                    basarili, acilacak = veri
                    if basarili:
                        self.yaz('Bitti.\n')
                        for y in acilacak:
                            ac(y)
                    else:
                        self.yaz('HATA: betik tamamlanamadı (ayrıntı yukarıda).\n')
                elif tur == 'mesaj':
                    (messagebox.showinfo if veri[0] else messagebox.showerror)(UYGULAMA, veri[1])
        except queue.Empty:
            pass
        self.kok.after(100, self.kuyrugu_isle)

    def yaz(self, metin):
        self.gunluk.config(state='normal')
        self.gunluk.insert('end', metin)
        self.gunluk.see('end')
        self.gunluk.config(state='disabled')

    # ------------------------------------------------ betik güncelleme

    def guncelle(self):
        self.yaz('\n=== Betikler GitHub\'dan güncelleniyor ===\n')
        yaz = Yazici(self.kuyruk)

        def is_():
            try:
                github_guncelle(yaz.write)
                self.kuyruk.put(('mesaj', (True, 'Betikler güncellendi.')))
            except Exception as e:
                yaz.write(f'HATA: {e}\n')
                self.kuyruk.put(('mesaj', (False, f'Güncellenemedi (internet bağlantısını kontrol edin):\n{e}')))
        self.arka_planda(is_)

    def betik_yukle(self):
        yollar = filedialog.askopenfilenames(title='Yeni betik dosyalarını seçin', filetypes=[('Python', '*.py')])
        if not yollar:
            return
        try:
            elle_yukle(yollar)
        except Exception as e:
            messagebox.showerror(UYGULAMA, f'Yüklenemedi:\n{e}')
            return
        self.yaz('Yüklendi: ' + ', '.join(os.path.basename(y) for y in yollar) + '\n')
        self.surum.config(text=surum_metni())

    def varsayilana_don(self):
        if not os.path.isdir(kullanici_klasor()):
            messagebox.showinfo(UYGULAMA, 'Zaten uygulamanın gömülü betikleri kullanılıyor.')
            return
        if messagebox.askyesno(UYGULAMA, 'Güncellenen betikler silinsin ve uygulamanın gömülü betiklerine dönülsün mü?'):
            shutil.rmtree(kullanici_klasor())
            self.yaz('Gömülü betiklere dönüldü.\n')
            self.surum.config(text=surum_metni())


def main():
    try:  # Windows'ta yüksek çözünürlüklü ekranda bulanık görünmesin
        import ctypes
        ctypes.windll.shcore.SetProcessDpiAwareness(1)
    except (ImportError, AttributeError, OSError):
        pass
    kok = TkinterDnD.Tk() if TkinterDnD else tk.Tk()
    Uygulama(kok)
    kok.mainloop()


if __name__ == '__main__':
    main()
