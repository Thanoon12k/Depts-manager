# Draws the launcher icon (assets/icon.png, the Android mipmaps and the adaptive-icon layers).
# Run from the repo root: python3 tool/make_icon.py
from PIL import Image, ImageDraw, ImageFont, ImageFilter

S = 1024
ORANGE, ORANGE2 = (255, 107, 61), (255, 154, 60)
INK, PAPER, LINE = (31, 28, 43), (243, 239, 230), (215, 208, 196)
GREEN, GREEN_DARK = (61, 220, 151), (10, 58, 28)
FONT = 'assets/fonts/Cairo.ttf'


def gradient(size):
    g = Image.new('RGB', (size, size))
    d = ImageDraw.Draw(g)
    for y in range(size):
        t = y / (size - 1)
        d.line([(0, y), (size, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(ORANGE2, ORANGE)))
    return g


def notebook(scale=1.0):
    """The foreground: a notebook with a coin badge, centered on a transparent square."""
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    k = lambda v: round(S / 2 + (v - S / 2) * scale)
    # soft shadow
    sh = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([k(300), k(250), k(744), k(830)], radius=round(48 * scale), fill=(80, 20, 0, 120))
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(28 * scale)))
    d = ImageDraw.Draw(im)
    # cover and pages
    d.rounded_rectangle([k(280), k(220), k(724), k(800)], radius=round(48 * scale), fill=INK)
    d.rounded_rectangle([k(330), k(250), k(700), k(770)], radius=round(28 * scale), fill=PAPER)
    # ruled lines with amounts
    for i, y in enumerate(range(400, 720, 64)):
        d.rounded_rectangle([k(380), k(y), k(650), k(y + 14)], radius=round(7 * scale), fill=LINE)
        d.rounded_rectangle([k(380), k(y), k(380 + (150 if i % 2 else 210)), k(y + 14)], radius=round(7 * scale),
                            fill=(255, 107, 61) if i == 0 else (167, 161, 182))
    # title on the page
    f = ImageFont.truetype(FONT, round(78 * scale), layout_engine=ImageFont.Layout.RAQM)
    f.set_variation_by_axes([800]) if hasattr(f, 'set_variation_by_axes') else None
    d.text((k(515), k(318)), 'الدين', font=f, fill=INK, anchor='mm', direction='rtl')
    # spiral rings
    for y in range(290, 780, 80):
        d.rounded_rectangle([k(250), k(y), k(320), k(y + 24)], radius=round(12 * scale), fill=(200, 196, 210))
    # coin badge
    cx, cy, r = 690, 720, 140
    d.ellipse([k(cx - r), k(cy - r + 12), k(cx + r), k(cy + r + 12)], fill=GREEN_DARK)
    d.ellipse([k(cx - r), k(cy - r), k(cx + r), k(cy + r)], fill=GREEN)
    d.ellipse([k(cx - r + 22), k(cy - r + 22), k(cx + r - 22), k(cy + r - 22)], outline=(255, 255, 255), width=round(8 * scale))
    f2 = ImageFont.truetype(FONT, round(110 * scale), layout_engine=ImageFont.Layout.RAQM)
    d.text((k(cx), k(cy - 8)), 'د.ع', font=f2, fill=GREEN_DARK, anchor='mm', direction='rtl')
    return im


def legacy():
    """Full icon: rounded orange square with the notebook (for launchers without adaptive icons)."""
    bg = gradient(S).convert('RGBA')
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=230, fill=255)
    out = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    out.paste(bg, mask=mask)
    out.alpha_composite(notebook(0.92))
    return out


icon = legacy()
icon.save('assets/icon.png')
res = 'android/app/src/main/res'
for name, px in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    icon.resize((px, px), Image.LANCZOS).save(f'{res}/mipmap-{name}/ic_launcher.png')
    # adaptive layers are 108dp with the safe zone in the middle 72dp
    fg = notebook(0.62).resize((px * 108 // 48, px * 108 // 48), Image.LANCZOS)
    fg.save(f'{res}/mipmap-{name}/ic_launcher_foreground.png')
    gradient(px * 108 // 48).save(f'{res}/mipmap-{name}/ic_launcher_background.png')
    # splash logo, 96dp
    notebook(0.95).resize((px * 2, px * 2), Image.LANCZOS).save(f'{res}/mipmap-{name}/launch_image.png')
