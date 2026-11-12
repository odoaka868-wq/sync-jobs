# ingest_drop.py (pc1): dropフォルダの画像を raw へ取り込み、学習データへ追加する (冪等・重複排除つき)
import os, re, hashlib, shutil
from PIL import Image

BASE = os.path.join(os.path.expanduser('~'), 'pc1-train')
DROP = os.path.join(BASE, 'drop')
RAW = os.path.join(BASE, 'raw')
DATA = os.path.join(BASE, 'data', '5_tegakisk')
os.makedirs(DROP, exist_ok=True)
os.makedirs(RAW, exist_ok=True)
os.makedirs(DATA, exist_ok=True)

def md5(p):
    h = hashlib.md5()
    with open(p, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()

known = {}
for f in os.listdir(RAW):
    p = os.path.join(RAW, f)
    if os.path.isfile(p):
        try: known[md5(p)] = f
        except Exception: pass
print('existing raw:', len(known))

idx = 0
for f in os.listdir(DATA):
    m = re.match(r'img_(\d+)\.jpg$', f)
    if m: idx = max(idx, int(m.group(1)))
print('current max img index:', idx)

exts = {'.jpg', '.jpeg', '.png', '.webp', '.bmp'}
added = prepped = dup = small = bad = 0
for root, dirs, files in os.walk(DROP):
    for f in sorted(files):
        if os.path.splitext(f)[1].lower() not in exts: continue
        src = os.path.join(root, f)
        try: h = md5(src)
        except Exception: bad += 1; continue
        if h in known: dup += 1; continue
        safe = re.sub(r'[^\w.\-]+', '_', f)
        dst = os.path.join(RAW, safe)
        n = 1
        while os.path.exists(dst):
            dst = os.path.join(RAW, f'{os.path.splitext(safe)[0]}_{n}{os.path.splitext(safe)[1]}')
            n += 1
        shutil.copy2(src, dst)
        known[h] = os.path.basename(dst)
        added += 1
        try:
            im = Image.open(dst); w, hh = im.size
            if max(w, hh) < 1024:
                small += 1; continue
            idx += 1
            name = f'img_{idx:03d}'
            im.convert('RGB').save(os.path.join(DATA, name + '.jpg'), quality=92)
            open(os.path.join(DATA, name + '.txt'), 'w').write('tegakisk')
            prepped += 1
        except Exception as e:
            print('prep skip', f, e); bad += 1
print(f'INGEST RESULT: added_to_raw={added} prepped={prepped} duplicates={dup} held_out_small={small} errors={bad}')
print('total prepped now:', len([f for f in os.listdir(DATA) if f.endswith(".jpg")]))
