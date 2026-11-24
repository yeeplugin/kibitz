# Xuất icon mẫu 1 (icon-1.svg) ra icon iOS và Android. Chạy: python3 install.py
import json, os, re, subprocess
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
body = re.search(r'<svg[^>]*>(.*)</svg>', open(f'{HERE}/icon-1.svg').read(), re.S).group(1)
art = body[body.index('</defs>') + 7:]
art = art[art.index('/>') + 2:]  # bỏ nền, chỉ giữ khung ngắm + quân mã
head = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">'
variants = {
    'full': head + body + '</svg>',
    'round': head + '<clipPath id="r"><rect x="40" y="40" width="944" height="944" rx="200"/></clipPath><g clip-path="url(#r)">' + body + '</g></svg>',
    'fg': head + '<g transform="translate(512 512) scale(.6) translate(-512 -512)">' + art + '</g></svg>',
}
os.makedirs(f'{HERE}/out', exist_ok=True)
for k, v in variants.items():
    svg = f'{HERE}/out/{k}.svg'
    open(svg, 'w').write(v)
    subprocess.run([CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
                    '--default-background-color=00000000', '--window-size=1024,1024',
                    f'--screenshot={HERE}/out/{k}.png', f'file://{svg}'], check=True, capture_output=True)

def resize(src, px, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    subprocess.run(['sips', '-z', str(px), str(px), f'{HERE}/out/{src}.png', '--out', dst], check=True, capture_output=True)

ios = f'{ROOT}/ios/Runner/Assets.xcassets/AppIcon.appiconset'
for im in json.load(open(f'{ios}/Contents.json'))['images']:
    px = round(float(im['size'].split('x')[0]) * int(im['scale'][0]))
    resize('full', px, f"{ios}/{im['filename']}")

res = f'{ROOT}/android/app/src/main/res'
for d, legacy, fg in [('mdpi', 48, 108), ('hdpi', 72, 162), ('xhdpi', 96, 216), ('xxhdpi', 144, 324), ('xxxhdpi', 192, 432)]:
    resize('round', legacy, f'{res}/mipmap-{d}/ic_launcher.png')
    resize('fg', fg, f'{res}/mipmap-{d}/ic_launcher_foreground.png')
os.makedirs(f'{res}/mipmap-anydpi-v26', exist_ok=True)
open(f'{res}/drawable/ic_launcher_background.xml', 'w').write(
    '<?xml version="1.0" encoding="utf-8"?>\n<shape xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <gradient android:startColor="#2B90FF" android:endColor="#0062D6" android:angle="315" />\n</shape>\n')
open(f'{res}/mipmap-anydpi-v26/ic_launcher.xml', 'w').write(
    '<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <background android:drawable="@drawable/ic_launcher_background" />\n'
    '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n</adaptive-icon>\n')
print('ok')
