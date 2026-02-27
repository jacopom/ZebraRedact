from PIL import Image, ImageDraw
import os

SRC = "zebra_source.png"
THRESHOLD = 240

img = Image.open(SRC).convert("RGBA")
w, h = img.size
px = img.load()

# Remove white background
for y in range(h):
    for x in range(w):
        r, g, b, a = px[x, y]
        if r > THRESHOLD and g > THRESHOLD and b > THRESHOLD:
            px[x, y] = (r, g, b, 0)

# Full-body master
side = max(w, h)
full_padded = Image.new("RGBA", (side, side), (0, 0, 0, 0))
full_padded.paste(img, ((side - w) // 2, (side - h) // 2))
full_1024 = full_padded.resize((1024, 1024), Image.LANCZOS)
full_1024.save("zebra_full_1024.png")
print("Saved zebra_full_1024.png")

# Head crop: top 42% of source, then tight-crop to actual content bounding box
# (removes transparent margins so the wide/flat crop scales up properly)
crop_bottom = int(h * 0.42)
head_raw = img.crop((0, 0, w, crop_bottom))
bbox = head_raw.getbbox()   # tight bounds around non-transparent pixels
head = head_raw.crop(bbox) if bbox else head_raw

# ── ICON GEOMETRY (Apple HIG) ─────────────────────────────────────────────
# Total canvas : 1024 × 1024  (transparent)
# Squircle tile:  824 × 824  centred → 100 px transparent border each side
# Squircle radius: 22.5 % of tile = 185 px
# Zebra padding inside tile: 8 % each side → artwork ~84 % of tile

CANVAS   = 1024
TILE     = 824          # Apple HIG artwork area
BORDER   = (CANVAS - TILE) // 2   # 100 px transparent bleed each side

INNER_PAD = 0.04        # 4 % padding inside the squircle tile
art_size  = int(TILE * (1 - 2 * INNER_PAD))   # ≈ 692 px

# Scale so the zebra HEIGHT fills art_size; the wide hat brim will overflow
# horizontally and get clipped naturally by the squircle mask — giving a bold,
# full-height icon rather than a tiny wide-and-short fit-in-box result.
scale = art_size / head.size[1]
z_w = int(head.size[0] * scale)
z_h = art_size
zebra = head.resize((z_w, z_h), Image.LANCZOS)

# Build squircle tile (white background)
tile = Image.new("RGBA", (TILE, TILE), (255, 255, 255, 255))
paste_x = (TILE - z_w) // 2
paste_y = TILE - z_h          # anchor to bottom edge
tile.paste(zebra, (paste_x, paste_y), zebra)

# Squircle mask baked in (macOS debug builds don't auto-apply it)
def squircle_mask(size):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        [0, 0, size - 1, size - 1],
        radius=int(size * 0.225),
        fill=255
    )
    return m

tile.putalpha(squircle_mask(TILE))

# Compose: place tile on transparent 1024 × 1024 canvas
canvas_img = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
canvas_img.paste(tile, (BORDER, BORDER), tile)
canvas_img.save("zebra_head_1024.png")
print("Saved zebra_head_1024.png")

# Export all icon sizes (no extra per-size squircle; already baked)
for s in [16, 32, 64, 128, 256, 512, 1024]:
    canvas_img.resize((s, s), Image.LANCZOS).save(f"icon_{s}.png")
    print(f"Saved icon_{s}.png")

print("\nAll done!")
