"""Resize existing CGID artwork into platform icon assets (no new artwork)."""
import json
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1]
blue = Image.open(root / 'assets/branding/icon_silver_blue.png').convert('RGBA')
gold = Image.open(root / 'assets/branding/icon_gold_blue.png').convert('RGBA')

def save_icon(image, path, size):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), Image.Resampling.LANCZOS).save(path)

for density, size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    for name, image in [('ic_launcher',blue),('ic_launcher_gold',gold)]:
        save_icon(image, root / f'android/app/src/main/res/mipmap-{density}/{name}.png', size)
for name, image in [('app_icon', blue),('gold_icon',gold)]:
    image.resize((256,256)).save(root / f'windows/runner/resources/{name}.ico', sizes=[(s,s) for s in [16,32,48,64,128,256]])
save_icon(blue, root/'web/favicon.png', 64)
save_icon(gold, root/'web/favicon-gold.png', 64)
for size in [192,512]:
    save_icon(blue,root/f'web/icons/Icon-{size}.png',size)
    save_icon(blue,root/f'web/icons/Icon-maskable-{size}.png',size)
for platform in ['macos','ios']:
    folder = root / platform / 'Runner/Assets.xcassets/AppIcon.appiconset'
    data = json.loads((folder/'Contents.json').read_text())
    for entry in data['images']:
        if 'filename' in entry:
            size = round(float(entry['size'].split('x')[0]) * float(entry['scale'].replace('x','')))
            save_icon(blue.convert('RGB'), folder / entry['filename'], size)
    if platform == 'ios':
        alt = folder.parent/'GoldIcon.appiconset'
        alt.mkdir(exist_ok=True)
        (alt/'Contents.json').write_text(json.dumps(data,indent=2))
        for entry in data['images']:
            if 'filename' in entry:
                size = round(float(entry['size'].split('x')[0]) * float(entry['scale'].replace('x','')))
                save_icon(gold.convert('RGB'),alt/entry['filename'],size)
