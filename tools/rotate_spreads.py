# Rotates the landscape pages (spreads) of CBZs on the Kindle in place: fetch only those pages,
# rotate 90° counter-clockwise (turn the Kindle clockwise to read them full screen), append them
# plus a new central directory to the archive, swap the file in atomically.
import os, subprocess, struct, sys, json, io, zlib
from PIL import Image
K = ["ssh", "-p", "2222", "root@" + os.environ["KINDLE_IP"]]
W, H = 1236, 1648
def q(s): return "'" + s.replace("'", "'\\''") + "'"
def run(cmd, data=None):
    r = subprocess.run(K + [cmd], input=data, capture_output=True, stdin=None if data is not None else subprocess.DEVNULL)
    if r.returncode: raise SystemExit("remote failed: %s %s" % (cmd[:120], r.stderr[:300]))
    return r.stdout
spreads = json.load(open(sys.argv[1]))
for f, names in sorted(spreads.items()):
    if not names: continue
    size = int(run("wc -c < " + q(f)).strip())
    tail = run("tail -c 65536 " + q(f))
    e = tail.rfind(b"PK\x05\x06")
    n_entries, cd_size, cd_off = struct.unpack("<HII", tail[e + 10:e + 20])
    assert cd_off + cd_size + 22 == size, "unexpected zip layout"
    cd = tail[len(tail) - (size - cd_off):][:cd_size]
    records, i = [], 0
    while i < len(cd):
        nl, el, cl = struct.unpack("<HHH", cd[i + 28:i + 34])
        rec = bytearray(cd[i:i + 46 + nl + el + cl])
        records.append((cd[i + 46:i + 46 + nl].decode(), rec))
        i += 46 + nl + el + cl
    append = bytearray()
    for name, rec in records:
        if name not in names: continue
        csize, = struct.unpack("<I", rec[20:24]); off, = struct.unpack("<I", rec[42:46])
        raw = run("tail -c +%d %s | head -c %d" % (off + 1, q(f), csize + 1024))
        nl, el = struct.unpack("<HH", raw[26:30])
        data = raw[30 + nl + el:30 + nl + el + csize]
        assert zlib.crc32(data) == struct.unpack("<I", rec[16:20])[0], "crc mismatch fetching " + name
        im = Image.open(io.BytesIO(data)).convert("L").rotate(90, expand=True)
        scale = min(W / im.width, H / im.height, 1.0)
        if scale < 1.0: im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
        buf = io.BytesIO(); im.save(buf, "JPEG", quality=88, optimize=True); new = buf.getvalue()
        crc = zlib.crc32(new)
        nb = name.encode()
        local = struct.pack("<IHHHHHIIIHH", 0x04034b50, 20, 0, 0, rec[12] | rec[13] << 8, rec[14] | rec[15] << 8,
                            crc, len(new), len(new), len(nb), 0) + nb
        struct.pack_into("<III", rec, 16, crc, len(new), len(new))
        struct.pack_into("<I", rec, 42, cd_off + len(append))
        append += local + new
    new_cd = b"".join(bytes(r) for _, r in records)
    append += new_cd + struct.pack("<IHHHHIIH", 0x06054b50, 0, 0, n_entries, n_entries, len(new_cd), cd_off + len(append), 0)
    d, base = f.rsplit("/", 1)
    tmp = d + "/." + base + ".tmp"
    run("cat > /tmp/spread-append", bytes(append))
    out = run("head -c %d %s > %s && cat /tmp/spread-append >> %s && [ $(wc -c < %s) -eq %d ] && mv %s %s && rm /tmp/spread-append && echo ok"
              % (cd_off, q(f), q(tmp), q(tmp), q(tmp), cd_off + len(append), q(tmp), q(f)))
    print(base[:42], len(names), "rotated", out.decode().strip(), flush=True)
