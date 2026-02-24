from PIL import Image
import shutil, os

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

# Full-body master (square-padded to 1024)
side = max(w, h)
full_padded = Image.new("RGBA", (side, side), (0, 0, 0, 0))
full_padded.paste(img, ((side - w) // 2, (side - h) // 2))
full_1024 = full_padded.resize((1024, 1024), Image.LANCZOS)
full_1024.save("zebra_full_1024.png")
print("Saved zebra_full_1024.png")

# Head crop: top ~42% (hat + face), then square-padded
crop_bottom = int(h * 0.42)
head = img.crop((0, 0, w, crop_bottom))
head_side = w   # head crop is already full width
head_sq = Image.new("RGBA", (head_side, head_side), (0, 0, 0, 0))
paste_y = (head_side - crop_bottom) // 2
head_sq.paste(head, (0, paste_y))
head_1024 = head_sq.resize((1024, 1024), Image.LANCZOS)
head_1024.save("zebra_head_1024.png")
print("Saved zebra_head_1024.png")

# App icon sizes (from head crop)
SIZES = [16, 32, 64, 128, 256, 512, 1024]
for s in SIZES:
    head_1024.resize((s, s), Image.LANCZOS).save(f"icon_{s}.png")
    print(f"Saved icon_{s}.png")

print("\nAll done!")
