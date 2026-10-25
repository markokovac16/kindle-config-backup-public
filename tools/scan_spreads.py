# Finds landscape pages in the CBZs on the Kindle by reading only each page's first 2 KB over SSH.
import os, subprocess, struct, sys, json
K = ["ssh", "-n", "-p", "2222", "root@" + os.environ["KINDLE_IP"]]
def run(cmd):
    return subprocess.run(K + [cmd], capture_output=True, check=True).stdout
def run_script(script):
    r = subprocess.run(K[:1] + K[2:] + ["sh"], input=script.encode(), capture_output=True)
    if r.returncode: raise SystemExit("remote script failed: %d %s" % (r.returncode, r.stderr[:300]))
    return r.stdout
def q(s): return "'" + s.replace("'", "'\\''") + "'"
files = run("ls /mnt/us/documents/Manga/*/*.cbz").decode().splitlines()
result = {}
for f in files:
    size = int(run("wc -c < " + q(f)).strip())
    tail = run("tail -c 65536 " + q(f))
    e = tail.rfind(b"PK\x05\x06")
    n, cd_size, cd_off = struct.unpack("<HII", tail[e + 10:e + 20])
    cd = tail[len(tail) - (size - cd_off):][:cd_size] if size - cd_off <= len(tail) else None
    if cd is None:
        cd = run("tail -c %d %s | head -c %d" % (size - cd_off, q(f), cd_size))
    entries, i = [], 0
    while i < len(cd) and cd[i:i + 4] == b"PK\x01\x02":
        nl, el, cl = struct.unpack("<HHH", cd[i + 28:i + 34])
        off = struct.unpack("<I", cd[i + 42:i + 46])[0]
        entries.append((cd[i + 46:i + 46 + nl].decode(), off))
        i += 46 + nl + el + cl
    script = "F=%s\n" % q(f) + "".join('dd if="$F" bs=512 skip=%d count=5 2>/dev/null\n' % (off // 512) for _, off in entries)
    blob = run_script(script)
    spreads = []
    for k, (name, off) in enumerate(entries):
        chunk = blob[k * 2560:(k + 1) * 2560]
        p = off % 512
        nl, el = struct.unpack("<HH", chunk[p + 26:p + 30])
        b = chunk[p + 30 + nl + el:]
        j = 2
        while j < len(b) - 9:
            if b[j] != 0xFF: j += 1; continue
            m = b[j + 1]
            if m in (0xC0, 0xC1, 0xC2):
                h, w = struct.unpack(">HH", b[j + 5:j + 9])
                if w > h: spreads.append(name)
                break
            j += 2 + struct.unpack(">H", b[j + 2:j + 4])[0]
    result[f] = spreads
    print(f.rsplit("/", 1)[1][:40], len(entries), "pages,", len(spreads), "spreads", flush=True)
json.dump(result, open(sys.argv[1], "w"), indent=1)
