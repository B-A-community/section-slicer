# Copyright 2026 B&A community. Licensed under Apache License 2.0.
# Иконки панели: SVG (Windows) и PNG 16/24 (macOS) из одного описания.
# Запуск: python tools/generate_icons.py
from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / 'src' / 'section_slicer' / 'icons'
DARK, BLUE, ORANGE, WHITE = '#3B3B38', '#2B6CB0', '#DD8A20', '#FFFFFF'

# Плоскость — параллелограмм в изометрии: (y центра, цвет).
def plane(y):
    return [(2, y + 2.5), (12, y - 2), (22, y + 2.5), (12, y + 7)]

SLICER = {
    'block': [(7, 4), (17, 4), (17, 20), (7, 20)],
    'planes': [(plane(13.5), BLUE), (plane(8.0), ORANGE), (plane(2.5), BLUE)],
}


def slicer_svg():
    parts = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">']
    parts.append('<rect x="7" y="3" width="10" height="18" rx="1" fill="#ECECEA" stroke="%s" stroke-width="1.6"/>' % DARK)
    for pts, color in SLICER['planes']:
        d = ' '.join('%g,%g' % p for p in pts)
        parts.append('<polygon points="%s" fill="%s" fill-opacity="0.85" stroke="%s" stroke-width="1" stroke-linejoin="round"/>' % (d, color, color))
    parts.append('</svg>')
    return '\n'.join(parts) + '\n'


def table_svg():
    return '\n'.join([
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">',
        '<rect x="3" y="3" width="18" height="18" rx="2" fill="%s" stroke="%s" stroke-width="1.6"/>' % (WHITE, DARK),
        '<rect x="3.8" y="3.8" width="16.4" height="4" fill="%s"/>' % BLUE,
        '<path d="M3 12h18M3 16.5h18M10 8v13" stroke="%s" stroke-width="1.2"/>' % DARK,
        '<rect x="11.5" y="13.2" width="7.5" height="2.2" rx="0.85" fill="%s"/>' % ORANGE,
        '</svg>',
    ]) + '\n'


def render_png(kind, size):
    scale = 8
    big = size * scale
    k = big / 24.0
    img = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    pt = lambda p: (p[0] * k, p[1] * k)
    if kind == 'slicer':
        dr.rounded_rectangle([7 * k, 3 * k, 17 * k, 21 * k], radius=k, fill='#ECECEA', outline=DARK, width=int(1.6 * k))
        for pts, color in SLICER['planes']:
            dr.polygon([pt(p) for p in pts], fill=color, outline=color)
    else:
        dr.rounded_rectangle([3 * k, 3 * k, 21 * k, 21 * k], radius=2 * k, fill=WHITE, outline=DARK, width=int(1.6 * k))
        dr.rectangle([3.8 * k, 3.8 * k, 20.2 * k, 7.8 * k], fill=BLUE)
        for y in (12, 16.5):
            dr.line([3 * k, y * k, 21 * k, y * k], fill=DARK, width=int(1.2 * k))
        dr.line([10 * k, 8 * k, 10 * k, 21 * k], fill=DARK, width=int(1.2 * k))
        dr.rounded_rectangle([11.5 * k, 13.2 * k, 19 * k, 15.4 * k], radius=0.85 * k, fill=ORANGE)
    return img.resize((size, size), Image.LANCZOS)


if __name__ == '__main__':
    OUT.mkdir(parents=True, exist_ok=True)
    for kind, svg in (('slicer', slicer_svg()), ('table', table_svg())):
        for size in (16, 24):
            (OUT / ('%s_%d.svg' % (kind, size))).write_text(svg, encoding='utf-8', newline='\n')
            render_png(kind, size).save(OUT / ('%s_%d.png' % (kind, size)))
    print('icons ->', OUT)
