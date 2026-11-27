# Chỉnh thư mục macos/ vừa tạo bằng `flutter create --platforms=macos .`: tên app, mã app, quyền sandbox, cỡ cửa sổ, icon.
# Chạy: python3 tool/mac_setup.py "<Tên app>" <bundle id>
import json, os, re, subprocess, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME, BUNDLE = sys.argv[1], sys.argv[2]
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'

def edit(path, fn):
    p = f'{ROOT}/{path}'
    s = open(p).read()
    t = fn(s)
    if t != s:
        open(p, 'w').write(t)

edit('macos/Runner/Configs/AppInfo.xcconfig', lambda s: re.sub(r'PRODUCT_BUNDLE_IDENTIFIER = .*', f'PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE}', re.sub(r'PRODUCT_NAME = .*', f'PRODUCT_NAME = {NAME}', s)))

# Sandbox: đọc tệp ảnh người dùng chọn, và ra mạng để hỏi cửa hàng (mua trong app).
EXTRA = ('\t<key>com.apple.security.files.user-selected.read-only</key>\n\t<true/>\n'
         '\t<key>com.apple.security.network.client</key>\n\t<true/>\n')
for f in ('DebugProfile', 'Release'):
    edit(f'macos/Runner/{f}.entitlements', lambda s: s if 'user-selected' in s else s.replace('</dict>', EXTRA + '</dict>'))

# Cửa sổ mở ra đủ rộng cho bố cục hai cột, không co nhỏ hơn cỡ điện thoại.
WINDOW = '''    self.contentViewController = flutterViewController
    self.setFrame(NSRect(x: windowFrame.origin.x, y: windowFrame.origin.y, width: 1120, height: 800), display: true)
    self.minSize = NSSize(width: 380, height: 640)
    self.center()
'''
edit('macos/Runner/MainFlutterWindow.swift', lambda s: s if 'minSize' in s else s.replace(
    '    self.contentViewController = flutterViewController\n    self.setFrame(windowFrame, display: true)\n', WINDOW))

# Icon macOS: hình bo góc nằm trong ô 824/1024, chừa lề trong suốt như icon Mac chuẩn.
icons = f'{ROOT}/design/icons'
body = re.search(r'<svg[^>]*>(.*)</svg>', open(f'{icons}/icon-1.svg').read(), re.S).group(1)
svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">'
       '<clipPath id="m"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>'
       '<g clip-path="url(#m)"><g transform="translate(100 100) scale(0.8046875)">' + body + '</g></g></svg>')
os.makedirs(f'{icons}/out', exist_ok=True)
open(f'{icons}/out/mac.svg', 'w').write(svg)
subprocess.run([CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
                '--default-background-color=00000000', '--window-size=1024,1024',
                f'--screenshot={icons}/out/mac.png', f'file://{icons}/out/mac.svg'], check=True, capture_output=True)
dst = f'{ROOT}/macos/Runner/Assets.xcassets/AppIcon.appiconset'
for im in json.load(open(f'{dst}/Contents.json'))['images']:
    px = round(float(im['size'].split('x')[0]) * int(im['scale'][0]))
    subprocess.run(['sips', '-z', str(px), str(px), f'{icons}/out/mac.png', '--out', f"{dst}/{im['filename']}"], check=True, capture_output=True)
print('ok')
