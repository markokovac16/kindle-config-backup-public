# CBZ (or a folder of page images) -> greyscale + fit to the PW5 screen (1236x1648), pages renumbered in reading order.
import os, sys, re, io, zipfile
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
W, H = 1236, 1648
IMG = (".jpg", ".jpeg", ".png", ".webp")
if os.path.isdir(src):  # a folder of page images, e.g. from `pdfimages -j book.pdf dir/p`
    class _Dir:
        def read(self, info): return open(os.path.join(src, info.filename), "rb").read()
    zin = _Dir()
    pages = [zipfile.ZipInfo(f) for f in os.listdir(src) if f.lower().endswith(IMG)]
else:
    zin = zipfile.ZipFile(src)
    pages = [i for i in zin.infolist() if not i.is_dir() and i.filename.lower().endswith(IMG)]
def key(i):
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", i.filename)]
pages.sort(key=key)
with zipfile.ZipFile(dst, "w", zipfile.ZIP_STORED) as zout:
    for n, info in enumerate(pages, 1):
        im = Image.open(io.BytesIO(zin.read(info))).convert("L")
        if im.width > im.height:  # two-page spread: rotate so it fills the screen with the Kindle turned clockwise
            im = im.rotate(90, expand=True)
        scale = min(W / im.width, H / im.height, 1.0)
        if scale < 1.0:
            im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=88, optimize=True)
        zout.writestr("%04d.jpg" % n, buf.getvalue())
print("pages", len(pages), "first", pages[0].filename, "last", pages[-1].filename)
