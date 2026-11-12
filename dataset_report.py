# dataset_report.py (pc1): データセットの作風傾向を可視化する (モザイクグリッド + 簡易統計)
import os, random, math
from PIL import Image, ImageFilter

BASE = os.path.join(os.path.expanduser('~'), 'pc1-train')
DATA = None
for name in ('1_tegakisk', '5_tegakisk'):
    p = os.path.join(BASE, 'data', name)
    if os.path.isdir(p):
        DATA = p; break
print('data dir:', DATA)

# ComfyUI output の特定 (config経由)
import json
models_dir = None
cfg = os.path.join(os.path.expanduser('~'), 'pc1-agent', 'config.json')
if os.path.exists(cfg):
    try: models_dir = json.load(open(cfg))['modelsDir']
    except Exception: pass
OUT = os.path.join(os.path.dirname(models_dir), 'output') if models_dir else BASE
os.makedirs(OUT, exist_ok=True)
print('out dir:', OUT)

files = sorted(f for f in os.listdir(DATA) if f.lower().endswith('.jpg'))
print('total images:', len(files))

# --- 統計 (全数, 256pxに縮小して計測) ---
sats, bris, edges, aspects = [], [], [], []
for f in files:
    try:
        im = Image.open(os.path.join(DATA, f)).convert('RGB')
        w, h = im.size
        aspects.append(w / h)
        small = im.copy(); small.thumbnail((256, 256))
        hsv = small.convert('HSV')
        px = list(hsv.getdata())
        n = len(px)
        sats.append(sum(p[1] for p in px) / n / 255)
        bris.append(sum(p[2] for p in px) / n / 255)
        g = small.convert('L').filter(ImageFilter.FIND_EDGES)
        gp = list(g.getdata())
        edges.append(sum(gp) / len(gp) / 255)
    except Exception as e:
        print('stat skip', f, e)

def quart(v):
    v = sorted(v); n = len(v)
    return f"min={v[0]:.2f} q1={v[n//4]:.2f} med={v[n//2]:.2f} q3={v[3*n//4]:.2f} max={v[-1]:.2f} mean={sum(v)/n:.2f}"
print('saturation:', quart(sats))
print('brightness:', quart(bris))
print('edge_density:', quart(edges))
print('aspect(w/h):', quart(aspects))

# --- モザイクグリッド (ランダム128枚 -> 8x8 x2) ---
random.seed(42)
sample = random.sample(files, min(128, len(files)))
CELL = 256
for gi in range(2):
    grid = Image.new('RGB', (CELL * 8, CELL * 8), (24, 24, 24))
    for i, f in enumerate(sample[gi * 64:(gi + 1) * 64]):
        try:
            im = Image.open(os.path.join(DATA, f)).convert('RGB')
            im.thumbnail((CELL, CELL))
            x = (i % 8) * CELL + (CELL - im.width) // 2
            y = (i // 8) * CELL + (CELL - im.height) // 2
            grid.paste(im, (x, y))
        except Exception as e:
            print('grid skip', f, e)
    outp = os.path.join(OUT, f'dataset_grid_{gi}.png')
    grid.save(outp)
    print('grid saved:', outp)
print('DATASET_REPORT_DONE')
