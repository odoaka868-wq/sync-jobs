# build_dataset.py (pc1): fetch reference images via FxTwitter (curl.exe) and prep training data
import json, os, re, subprocess, sys, time, hashlib
from PIL import Image

BASE = os.path.join(os.path.expanduser('~'), 'pc1-train')
RAW = os.path.join(BASE, 'raw')
DATA = os.path.join(BASE, 'data', '5_tegakisk')
os.makedirs(RAW, exist_ok=True)
os.makedirs(DATA, exist_ok=True)

LINKS = [
    "https://x.com/6Yaoyue/status/2086440872078635366",
    "https://x.com/6Yaoyue/status/2092990794265473063",
    "https://x.com/6Yaoyue/status/2093715692520677385",
    "https://x.com/6Yaoyue/status/2093975003134087502",
    "https://x.com/6Yaoyue/status/2094964190377304213",
    "https://x.com/6Yaoyue/status/2096029800628629742",
    "https://x.com/6Yaoyue/status/2096754025047961850",
    "https://x.com/6Yaoyue/status/2097539738362396945",
    "https://x.com/6Yaoyue/status/2098405240408334472",
    "https://x.com/6Yaoyue/status/2099294419300319500",
    "https://x.com/6Yaoyue/status/2100026148617060496",
    "https://x.com/6Yaoyue/status/2100890929678930140",
    "https://x.com/6Yaoyue/status/2109064678731301082",
    "https://x.com/6Yaoyue/status/2113064488476065831",
    "https://x.com/6Yaoyue/status/2113107581359313145",
    "https://x.com/6Yaoyue/status/2114177983569359095",
    "https://x.com/6Yaoyue/status/2120052933111029920",
    "https://x.com/6Yaoyue/status/2120367075164402144",
    "https://x.com/Torso__/status/2032572584802529301",
    "https://x.com/Torso__/status/2033064546991222830",
    "https://x.com/Torso__/status/2033488246446104842",
    "https://x.com/Torso__/status/2034086232926642308",
    "https://x.com/Torso__/status/2035534235101250017",
    "https://x.com/Torso__/status/2036082921254359317",
    "https://x.com/Torso__/status/2036292886531355127",
    "https://x.com/Torso__/status/2036977270964052155",
    "https://x.com/Torso__/status/2051041442328666246",
    "https://x.com/Torso__/status/2079356323536441690",
    "https://x.com/Torso__/status/2080081927332327517",
    "https://x.com/Torso__/status/2081573057274286591",
    "https://x.com/Torso__/status/2081819060162240622",
    "https://x.com/Torso__/status/2081891589799231751",
    "https://x.com/Torso__/status/2082304920787751265",
    "https://x.com/Torso__/status/2082710100566008207",
    "https://x.com/Torso__/status/2083801876009812222",
    "https://x.com/Torso__/status/2084211695136981395",
    "https://x.com/Torso__/status/2085288617908613304",
    "https://x.com/Torso__/status/2085917288491003921",
    "https://x.com/Torso__/status/2086392307553845558",
    "https://x.com/Torso__/status/2086742851514433679",
    "https://x.com/Torso__/status/2087114126476939472",
    "https://x.com/Torso__/status/2087530233243283824",
    "https://x.com/Torso__/status/2087971123694842268",
    "https://x.com/Torso__/status/2088473233259639156",
    "https://x.com/Torso__/status/2088570379275259916",
    "https://x.com/Torso__/status/2088974525585313855",
    "https://x.com/Torso__/status/2089230905269428714",
    "https://x.com/Torso__/status/2089664823588159639",
    "https://x.com/Torso__/status/2089928297010655597",
    "https://x.com/Torso__/status/2090425371191910853",
    "https://x.com/Torso__/status/2117268004509757656",
    "https://x.com/Torso__/status/2118110704561783253",
    "https://x.com/Torso__/status/2118654304173318351",
    "https://x.com/Torso__/status/2119195760445304858",
    "https://x.com/Torso__/status/2119554263630405923",
    "https://x.com/betanonbeet/status/2094386046020862114",
    "https://x.com/betanonbeet/status/2104529051063062738",
    "https://x.com/betanonbeet/status/2105455633336311960",
    "https://x.com/betanonbeet/status/2106705471856095533",
    "https://x.com/betanonbeet/status/2118289431438430530",
    "https://x.com/betanonbeet/status/2119739599300018510",
    "https://x.com/betanonbeet/status/2120119670271508910",
    "https://x.com/jipa42760710/status/2100887558133571644",
    "https://x.com/jipa42760710/status/2102013006989394110",
    "https://x.com/jipa42760710/status/2102670572761354633",
    "https://x.com/jipa42760710/status/2103062122234335264",
    "https://x.com/jipa42760710/status/2104873716962537916",
    "https://x.com/jipa42760710/status/2105311717299241391",
    "https://x.com/jipa42760710/status/2105576265109696943",
    "https://x.com/jipa42760710/status/2106328577755201783",
    "https://x.com/jipa42760710/status/2107410541174206601",
    "https://x.com/jipa42760710/status/2108150511598026852",
    "https://x.com/jipa42760710/status/2108525773300887600",
    "https://x.com/jipa42760710/status/2109584873673338905",
    "https://x.com/jipa42760710/status/2109585136971084250",
    "https://x.com/jipa42760710/status/2110672028449849393",
    "https://x.com/jipa42760710/status/2111485601174450552",
    "https://x.com/jipa42760710/status/2111759204201439433",
    "https://x.com/jipa42760710/status/2111759468384170339",
    "https://x.com/jipa42760710/status/2112846355076968787",
    "https://x.com/jipa42760710/status/2113164142228230191",
    "https://x.com/jipa42760710/status/2113958307752997255",
    "https://x.com/jipa42760710/status/2116545736242520205",
    "https://x.com/jipa42760710/status/2117557404837835218",
    "https://x.com/jipa42760710/status/2118644573815951670",
    "https://x.com/jipa42760710/status/2119731726100422905",
    "https://x.com/roror0_/status/2103880378268438712",
    "https://x.com/roror0_/status/2105327159091102177",
    "https://x.com/roror0_/status/2113287928361455898",
    "https://x.com/roror0_/status/2113674933528391857",
    "https://x.com/roror0_/status/2114756785177551016",
    "https://x.com/roror0_/status/2115474832137879892",
    "https://x.com/roror0_/status/2115851214541975713",
    "https://x.com/roror0_/status/2118011765233766553",
    "https://x.com/roror0_/status/2118736346756026472",
    "https://x.com/roror0_/status/2119460027148980674",
    "https://x.com/roror0_/status/2120229146878205968",
]

def curl(url, out=None):
    cmd = ['curl.exe', '-sL', '--retry', '2', '-A', 'Mozilla/5.0', url]
    if out:
        cmd += ['-o', out]
        return subprocess.run(cmd).returncode == 0 and os.path.exists(out)
    r = subprocess.run(cmd, capture_output=True)
    return r.stdout

count = 0
for link in LINKS:
    m = re.search(r'x\.com/([^/]+)/status/(\d+)', link)
    if not m: continue
    user, tid = m.groups()
    data = curl(f'https://api.fxtwitter.com/{user}/status/{tid}')
    if not data: print('API fail', tid); continue
    try: tw = json.loads(data)
    except Exception: print('JSON fail', tid); continue
    tweet = tw.get('tweet') or {}
    media = (tweet.get('media') or {}).get('all') or []
    for i, md in enumerate(media):
        if md.get('type') != 'photo': continue
        url = md.get('url', '')
        if not url: continue
        orig = re.sub(r'\?.*$', '', url) + '?format=jpg&name=orig'
        name = f'{user}_{tid}_{i}.jpg'
        dst = os.path.join(RAW, name)
        if os.path.exists(dst) and os.path.getsize(dst) > 10000: count += 1; continue
        if curl(orig, dst): count += 1; print('got', name)
        time.sleep(0.3)
    time.sleep(0.5)
print('raw images on disk:', len(os.listdir(RAW)))

seen = {}
idx = 0
for f in sorted(os.listdir(RAW)):
    p = os.path.join(RAW, f)
    try:
        h = hashlib.md5(open(p, 'rb').read()).hexdigest()
        if h in seen: continue
        seen[h] = f
        im = Image.open(p); w, hh = im.size
        if max(w, hh) < 1024: continue
        idx += 1
        name = f'img_{idx:03d}'
        im.convert('RGB').save(os.path.join(DATA, name + '.jpg'), quality=92)
        open(os.path.join(DATA, name + '.txt'), 'w').write('tegakisk')
    except Exception as e:
        print('skip', f, e)
print('prepped:', idx, '->', DATA)
