"""mockup.png 에서 화면 1 일러스트, 아이콘 2개, 화면 3 기본 아바타를 잘라 Assets.xcassets 에 넣는다."""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "SignTrans/Resources/Assets.xcassets"
CROPS = {
    "StartIllustration": (0, 40, 362, 240),
    "DeafIcon": (28, 440, 140, 530),
    "HearingIcon": (22, 605, 142, 710),
    "DefaultAvatar": (870, 100, 1026, 258),
}

im = Image.open(ROOT / "mockup.png").convert("RGBA")
ASSETS.mkdir(parents=True, exist_ok=True)
(ASSETS / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}))
for name, box in CROPS.items():
    d = ASSETS / f"{name}.imageset"
    d.mkdir(exist_ok=True)
    im.crop(box).save(d / f"{name}.png")
    (d / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name}.png", "idiom": "universal", "scale": "1x"}],
        "info": {"author": "xcode", "version": 1}}))
    print("wrote", name, box)

# 앱 아이콘: 화면 1의 '농인으로 시작' 아이콘(파란 바탕 흰 그림)을 1024×1024 로 키운다.
icon = Image.new("RGB", (1024, 1024), (0x28, 0x5E, 0xE0))
glyph = im.crop(CROPS["DeafIcon"]).convert("RGB").resize((760, 610), Image.LANCZOS)
icon.paste(glyph, (132, 207))
d = ASSETS / "AppIcon.appiconset"
d.mkdir(exist_ok=True)
icon.save(d / "AppIcon.png")
(d / "Contents.json").write_text(json.dumps({
    "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
    "info": {"author": "xcode", "version": 1}}))
print("wrote AppIcon")
