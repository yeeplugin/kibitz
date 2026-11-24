# Sinh các mẫu icon Kibitz (SVG 1024) và bảng so sánh sheet.svg.
G1, G2, CREAM, AMBER, NAVY, WHITE = '#2A8A5C', '#0F4A33', '#F6EDD6', '#F5B63A', '#14202B', '#FFFFFF'

def piece(kind, x, y, s, fill, eye=None):
    p = {
        'pawn': '<circle cx="50" cy="26" r="15"/><rect x="33" y="40" width="34" height="8" rx="4"/>'
                '<path d="M40 47 C40 62 32 70 27 81 L73 81 C68 70 60 62 60 47 Z"/><rect x="20" y="80" width="60" height="13" rx="5"/>',
        'rook': '<path d="M26 12 h12 v9 h8 v-9 h8 v9 h8 v-9 h12 v24 h-48 Z"/><path d="M32 34 L68 34 L73 81 L27 81 Z"/>'
                '<rect x="18" y="80" width="64" height="13" rx="5"/>',
        'king': '<rect x="46" y="2" width="8" height="26" rx="2"/><rect x="38" y="9" width="24" height="8" rx="2"/>'
                '<path d="M30 32 C20 32 17 46 27 57 L33 81 L67 81 L73 57 C83 46 80 32 70 32 C60 32 54 38 50 45 C46 38 40 32 30 32 Z"/>'
                '<rect x="20" y="80" width="60" height="13" rx="5"/>',
        'knight': '<path d="M29 81 C29 64 43 57 47 46 C41 51 35 55 29 55 L20 45 L39 26 L41 9 L53 19 C72 23 82 45 77 81 Z"/>'
                  '<rect x="18" y="80" width="64" height="13" rx="5"/>'
                  + (f'<circle cx="45" cy="31" r="3.4" fill="{eye}"/>' if eye else ''),
    }[kind]
    return f'<g transform="translate({x},{y}) scale({s/100})" fill="{fill}">{p}</g>'

def grad(i, a, b):
    return f'<defs><linearGradient id="g{i}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{a}"/><stop offset="1" stop-color="{b}"/></linearGradient></defs><rect width="1024" height="1024" fill="url(#g{i})"/>'

def brackets(inset, L, w, col):
    a, b = inset, 1024 - inset
    d = f'M{a} {a+L} V{a} H{a+L} M{b-L} {a} H{b} V{a+L} M{b} {b-L} V{b} H{b-L} M{a+L} {b} H{a} V{b-L}'
    return f'<path d="{d}" fill="none" stroke="{col}" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round"/>'

def checker(x, y, n, c, dark, light, rx=0):
    out = [f'<rect x="{x}" y="{y}" width="{n*c}" height="{n*c}" fill="{light}" rx="{rx}"/>']
    for r in range(n):
        for k in range(n):
            if (r + k) % 2: out.append(f'<rect x="{x+k*c}" y="{y+r*c}" width="{c}" height="{c}" fill="{dark}"/>')
    return ''.join(out)

icons = []

# 1 Khung ngắm + mã
icons.append(('Khung ngắm', grad(1, '#2B90FF', '#0062D6') + brackets(170, 150, 46, CREAM) + piece('knight', 262, 250, 500, CREAM, '#004FAD')
              + f'<circle cx="790" cy="234" r="34" fill="{AMBER}"/>'))

# 2 Máy ảnh hình xe
icons.append(('Xe máy ảnh', grad(2, '#1D2D3B', NAVY)
              + f'<g fill="{CREAM}"><rect x="212" y="250" width="130" height="150" rx="18"/><rect x="447" y="250" width="130" height="150" rx="18"/><rect x="682" y="250" width="130" height="150" rx="18"/>'
              + f'<rect x="172" y="350" width="680" height="440" rx="70"/></g>'
              + f'<circle cx="512" cy="570" r="170" fill="{NAVY}"/><circle cx="512" cy="570" r="120" fill="{G1}"/><circle cx="512" cy="570" r="62" fill="{NAVY}"/>'
              + f'<circle cx="478" cy="536" r="22" fill="{WHITE}" opacity=".85"/><circle cx="762" cy="430" r="26" fill="{AMBER}"/>'))

# 3 Bong bóng mách nước
icons.append(('Mách nước', grad(3, G1, G2)
              + f'<path d="M250 190 H774 Q864 190 864 280 V620 Q864 710 774 710 H470 L300 860 L330 710 H250 Q160 710 160 620 V280 Q160 190 250 190 Z" fill="{CREAM}"/>'
              + piece('pawn', 322, 240, 380, G2)
              + f'<path d="M700 560 V370 M640 430 L700 365 L760 430" fill="none" stroke="{AMBER}" stroke-width="44" stroke-linecap="round" stroke-linejoin="round"/>'))

# 4 Con mắt bàn cờ
icons.append(('Mắt cờ', grad(4, '#FBE08A', AMBER)
              + f'<path d="M92 512 Q512 130 932 512 Q512 894 92 512 Z" fill="{CREAM}" stroke="{NAVY}" stroke-width="44" stroke-linejoin="round"/>'
              + f'<clipPath id="c4"><circle cx="512" cy="512" r="200"/></clipPath><g clip-path="url(#c4)">{checker(312, 312, 4, 100, G2, CREAM)}</g>'
              + f'<circle cx="512" cy="512" r="200" fill="none" stroke="{NAVY}" stroke-width="36"/><circle cx="512" cy="512" r="70" fill="{NAVY}"/><circle cx="486" cy="486" r="22" fill="{WHITE}"/>'))

# 5 Ống kính trên bàn cờ
icons.append(('Ống kính', f'<rect width="1024" height="1024" fill="{CREAM}"/><rect x="512" width="512" height="512" fill="{G1}"/><rect y="512" width="512" height="512" fill="{G1}"/>'
              + f'<circle cx="512" cy="512" r="300" fill="{NAVY}"/><circle cx="512" cy="512" r="236" fill="none" stroke="{CREAM}" stroke-width="16" opacity=".5"/>'
              + f'<circle cx="512" cy="512" r="190" fill="{G2}"/>' + piece('king', 392, 384, 240, CREAM)
              + f'<circle cx="716" cy="308" r="30" fill="{AMBER}"/>'))

# 6 Chữ K
icons.append(('Chữ K', grad(6, '#1D2D3B', NAVY) + brackets(130, 120, 36, G1)
              + f'<g fill="{CREAM}"><rect x="290" y="230" width="140" height="564" rx="24"/>'
              + f'<path d="M430 520 L640 230 H800 L560 548 Z"/><path d="M500 500 L600 440 L812 794 H650 Z"/></g>'
              + f'<circle cx="500" cy="512" r="74" fill="{NAVY}"/><circle cx="500" cy="512" r="46" fill="{AMBER}"/>'))

# 7 Bàn cờ phối cảnh + mũi tên
def quad(u0, v0, u1, v1):
    TL, TR, BR, BL = (300, 300), (724, 300), (880, 790), (144, 790)
    def at(u, v):
        t = v ** 0.8
        ax, ay = TL[0] + (TR[0]-TL[0])*u, TL[1] + (BL[1]-TL[1])*t
        bx = BL[0] + (BR[0]-BL[0])*u
        return (ax + (bx-ax)*t, ay)
    ps = [at(u0, v0), at(u1, v0), at(u1, v1), at(u0, v1)]
    return ' '.join(f'{x:.1f},{y:.1f}' for x, y in ps)
b = f'<polygon points="{quad(0,0,1,1)}" fill="{CREAM}" stroke="{CREAM}" stroke-width="30" stroke-linejoin="round"/>'
for r in range(4):
    for k in range(4):
        if (r + k) % 2 == 0: b += f'<polygon points="{quad(k/4, r/4, (k+1)/4, (r+1)/4)}" fill="{G2}"/>'
icons.append(('Bàn cờ', grad(7, G1, G2) + brackets(110, 120, 36, CREAM) + b
              + f'<path d="M330 720 C380 560 520 470 650 430 M560 400 L662 426 L600 512" fill="none" stroke="{AMBER}" stroke-width="46" stroke-linecap="round" stroke-linejoin="round"/>'
              + f'<circle cx="330" cy="720" r="40" fill="{AMBER}"/>'))

# 8 Vua trong vòng ống kính
icons.append(('Vòng kính', grad(8, '#1D2D3B', NAVY)
              + f'<circle cx="512" cy="512" r="350" fill="none" stroke="{AMBER}" stroke-width="64"/><circle cx="512" cy="512" r="270" fill="{G2}"/>'
              + piece('king', 337, 322, 350, CREAM)
              + f'<path d="M512 60 V120 M512 904 V964 M60 512 H120 M904 512 H964" stroke="{CREAM}" stroke-width="30" stroke-linecap="round"/>'))

# 9 Bàn cờ biết nói
icons.append(('Bàn cờ nói', grad(9, '#FBE08A', AMBER)
              + f'<path d="M300 760 L230 930 L470 780 Z" fill="{NAVY}"/><rect x="142" y="130" width="740" height="680" rx="120" fill="{NAVY}"/>'
              + f'<clipPath id="c9"><rect x="192" y="180" width="640" height="580" rx="80"/></clipPath><g clip-path="url(#c9)">{checker(192, 150, 4, 160, G1, CREAM)}</g>'
              + piece('knight', 372, 300, 300, NAVY, CREAM)))

for i, (name, body) in enumerate(icons, 1):
    open(f'icon-{i}.svg', 'w').write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">{body}</svg>')

S, GAP, LAB = 340, 44, 64
W = 3 * S + 4 * GAP
rows = (len(icons) + 2) // 3
H = rows * (S + LAB) + (rows + 1) * GAP
sheet = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}"><rect width="{W}" height="{H}" fill="#E9E9EC"/>']
for i, (name, body) in enumerate(icons):
    x, y = GAP + (i % 3) * (S + GAP), GAP + (i // 3) * (S + LAB + GAP)
    sheet.append(f'<clipPath id="m{i}"><rect x="{x}" y="{y}" width="{S}" height="{S}" rx="{S*0.225}"/></clipPath>'
                 f'<g clip-path="url(#m{i})"><svg x="{x}" y="{y}" width="{S}" height="{S}" viewBox="0 0 1024 1024">{body}</svg></g>'
                 f'<svg x="{x+S-70}" y="{y+S+8}" width="56" height="56" viewBox="0 0 1024 1024"><clipPath id="s{i}"><rect width="1024" height="1024" rx="230"/></clipPath><g clip-path="url(#s{i})">{body}</g></svg>'
                 f'<text x="{x+6}" y="{y+S+46}" font-family="Helvetica, Arial, sans-serif" font-size="30" font-weight="bold" fill="#222">{i+1}. {name}</text>')
sheet.append('</svg>')
open('sheet.svg', 'w').write(''.join(sheet))
