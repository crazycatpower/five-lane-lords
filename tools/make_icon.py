"""Builds the game's icon from the lion crest (assets/manuscript-v1/crown.png).

    python tools/make_icon.py

Output: icon.png (the window / taskbar icon, project setting application/config/icon) and
icon.ico (16-256 px, embedded in the Windows executable by the export preset).
"""
import pathlib
from PIL import Image, ImageDraw

root = pathlib.Path(__file__).resolve().parent.parent
SIZE = 1024
canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(canvas)
# An indigo field inside a gold rim and an ink edge: the lion's ivory and vermilion stay readable at 16 px.
draw.rounded_rectangle((16, 16, SIZE - 16, SIZE - 16), radius=210, fill=(70, 53, 41, 255))
draw.rounded_rectangle((40, 40, SIZE - 40, SIZE - 40), radius=190, fill=(207, 170, 96, 255))
draw.rounded_rectangle((84, 84, SIZE - 84, SIZE - 84), radius=150, fill=(47, 63, 92, 255))
lion = Image.open(root / "assets" / "manuscript-v1" / "crown.png").convert("RGBA")
box = lion.getbbox()
lion = lion.crop(box)
scale = min((SIZE - 250) / lion.width, (SIZE - 250) / lion.height)
lion = lion.resize((round(lion.width * scale), round(lion.height * scale)), Image.LANCZOS)
canvas.alpha_composite(lion, ((SIZE - lion.width) // 2, (SIZE - lion.height) // 2 + 6))
canvas.resize((256, 256), Image.LANCZOS).save(root / "icon.png")
canvas.save(root / "icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print("icon.png, icon.ico")
