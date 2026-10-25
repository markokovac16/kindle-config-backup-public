#!/usr/bin/env python3
"""What's on the connected Kindle, compared with what this repo was tested on. Changes nothing.

    USB (stock or jailbroken, mounted on a Mac):  python3 tools/check-device.py
      (if it can't read the model: KINDLE_MODEL=PW5 python3 tools/check-device.py)
    SSH (once KOReader's SSH server runs):        KINDLE_IP=192.168.1.50 python3 tools/check-device.py

Jailbreaks differ by model and firmware, so it also lists the ones kindlemodding.org currently
says fit this Kindle. Only the model code of the serial number is printed, never the serial.
"""
import json, os, re, subprocess, sys, urllib.request

TESTED_MODEL = "PW5"
TESTED_FIRMWARE = "5.18.6"
TESTED_KOREADER = "v2026.07.1"
JAILBREAKS_URL = "https://kindlemodding.org/jailbreaks.json"
MOUNT = os.environ.get("KINDLE_MOUNT", "/Volumes/Kindle")
IP = os.environ.get("KINDLE_IP")

# Serial number -> model, from KOReader's frontend/device/kindle/device.lua. Serials starting with
# B or 9 keep the code in characters 3-4, newer ones in characters 4-6. The short names are
# kindlemodding.org's (None: not listed there).
OLD = {
    ("Kindle 2", "K2"): "02 03", ("Kindle DX", "DX"): "04 05", ("Kindle DX Graphite", "DX"): "09",
    ("Kindle Keyboard", "K3"): "08 06 0A", ("Kindle 4", "K4"): "0E 23", ("Kindle Touch", "KT"): "0F 11 10 12",
    ("Kindle Paperwhite 1", "PW"): "24 1B 1D 1F 1C 20",
    ("Kindle Paperwhite 2", "PW2"): "D4 5A D5 D6 D7 D8 F2 17 60 F4 F9 62 61 5F",
    ("Kindle Basic 2 (7th gen)", "KT2"): "C6 DD", ("Kindle Voyage", "KV"): "13 54 2A 4F 52 53",
}
NEW = {
    ("Kindle Paperwhite 3", "PW3"): "0G1 0G2 0G4 0G5 0G6 0G7 0KB 0KC 0KD 0KE 0KF 0KG 0LK 0LL",
    ("Kindle Oasis", "KOA"): "0GC 0GD 0GR 0GS 0GT 0GU",
    ("Kindle Oasis 2", "KOA2"): "0LM 0LN 0LP 0LQ 0P1 0P2 0P6 0P7 0P8 0S1 0S2 0S3 0S4 0S7 0SA",
    ("Kindle Basic 3 (8th gen)", "KT3"): "0DU 0K9 0KA",
    ("Kindle Paperwhite 4", "PW4"): "0PP 0T1 0T2 0T3 0T4 0T5 0T6 0T7 0TJ 0TK 0TL 0TM 0TN 102 103 16Q 16R 16S 16T 16U 16V",
    ("Kindle Basic 4 (10th gen)", "KT4"): "10L 0WF 0WG 0WH 0WJ 0VB",
    ("Kindle Oasis 3", "KOA3"): "11L 0WQ 0WP 0WN 0WM 0WL",
    ("Kindle Paperwhite 5 (11th gen)", "PW5"): "1Q0 1PX 1VD 21A 2BJ 2DK",
    ("Kindle Paperwhite 5 Signature Edition", "PW5"): "1LG 219 2BH",
    ("Kindle Basic 5 (11th gen)", "KT5"): "22D 25T 23A 2AQ 2AP 1XH 22C",
    ("Kindle Scribe", "KS"): "27J 2BL 263 227 2BM 23L 23M 270",
    ("Kindle Colorsoft", "CS"): "3H2 3H4 3H6 3H7 3H9 3JT 3J6 455 456 4EP 34X 3HB",
    ("Kindle Basic 6 (12th gen)", "KT6"): "A89 3L2 3L3 3L4 3L5 3L6 3KM",
    ("Kindle Paperwhite 6 (12th gen)", "PW6"): "33W 33X 346 349 3H3 3H5 3H8 3HA 3J5 3JS",
    ("Kindle Scribe 2", "KS2"): "3V0 3V1 3X5 3UV 3X4 3X3 41E 410",
    ("Kindle Scribe 3", None): "4PG 4PE 4PL 4F8 4FA 454",
    ("Kindle Scribe Colorsoft", None): "4VX 4PF 4PH 4F9 4FB 46P",
}


def model_of(serial):
    if not serial:
        return None, None, None
    old = serial[0] in "B9"
    code = serial[2:4] if old else serial[3:6]
    for (name, short), codes in (OLD if old else NEW).items():
        if code in codes.split():
            return code, name, short
    return code, "unknown model", None


def vtuple(v):
    return tuple(int(x) for x in re.findall(r"\d+", v))


def read_ssh():
    script = r'''
echo "fw=$(sed -n "s/^Kindle \([0-9.]*\).*/\1/p" /etc/prettyversion.txt | head -1)"
echo "sn=$(cat /proc/usid)"
echo "jb=$([ -f /mnt/us/documents/JAILBROKEN.txt ] || [ -f /mnt/us/privesc_marker.txt ] && echo yes || echo no)"
echo "ota=$([ -e /usr/bin/otaupd ] || [ -e /usr/bin/otav3 ] && echo ACTIVE || { [ -e /usr/bin/otaupd.bck ] && echo blocked || echo unknown; })"
echo "ko=$(cat /mnt/us/koreader/git-rev 2>/dev/null)"
echo "kpm=$(ls /mnt/us/kmc/kpm/packages 2>/dev/null | tr "\n" " ")"
echo "plugins=$(ls /mnt/us/koreader/plugins 2>/dev/null | tr "\n" " ")"
echo "patches=$(ls /mnt/us/koreader/patches 2>/dev/null | tr "\n" " ")"
echo "free=$(df -m /mnt/us | awk "NR==2 {print \$4}")"
'''
    r = subprocess.run(["ssh", "-p", "2222", "-o", "ConnectTimeout=10", "root@" + IP, "sh"],
                       input=script, capture_output=True, text=True)
    if r.returncode:
        sys.exit("Can't reach root@%s:2222 (Wi-Fi on? KOReader running with SSH started?)" % IP)
    return dict(l.split("=", 1) for l in r.stdout.splitlines() if "=" in l)


def ls(path):
    try:
        return " ".join(sorted(os.listdir(path)))
    except OSError:
        return ""


def read_usb():
    vf = os.path.join(MOUNT, "system", "version.txt")
    if not os.path.isfile(vf):
        sys.exit("No Kindle at %s (plug it in, or set KINDLE_MOUNT / KINDLE_IP)" % MOUNT)
    m = re.match(r"Kindle ([0-9.]+)", open(vf, errors="replace").read())
    # A Kindle reports its serial number over USB; macOS shows it in ioreg.
    sn = ""
    try:
        out = subprocess.run(["ioreg", "-p", "IOUSB", "-l", "-w0"], capture_output=True, text=True).stdout
        for block in out.split("+-o ")[1:]:
            if re.search(r'"USB Product Name" = "Kindle', block):
                s = re.search(r'"USB Serial Number" = "([^"]+)"', block)
                sn = s.group(1).replace(" ", "") if s else ""
                break
    except OSError:
        pass
    j = lambda *p: os.path.isfile(os.path.join(MOUNT, *p))
    st = os.statvfs(MOUNT)
    ko = os.path.join(MOUNT, "koreader", "git-rev")
    return {
        "fw": m.group(1) if m else "", "sn": sn,
        "jb": "yes" if j("documents", "JAILBROKEN.txt") or j("privesc_marker.txt") else "no",
        "ota": "unknown over USB (check over SSH)",
        "ko": open(ko).read().strip() if os.path.isfile(ko) else "",
        "kpm": ls(os.path.join(MOUNT, "kmc", "kpm", "packages")),
        "plugins": ls(os.path.join(MOUNT, "koreader", "plugins")),
        "patches": ls(os.path.join(MOUNT, "koreader", "patches")),
        "free": str(st.f_bavail * st.f_frsize // (1 << 20)),
    }


def jailbreaks_for(short, fw):
    """Jailbreaks kindlemodding.org lists for this model and firmware, or None if unreachable."""
    try:
        with urllib.request.urlopen(JAILBREAKS_URL, timeout=10) as r:
            data = json.load(r)
    except Exception:
        return None
    v, found = vtuple(fw), []
    for jb in data:
        if short not in jb.get("models", []):
            continue
        for f in jb.get("firmwares", []):
            if "all" not in f["models"] and short not in f["models"]:
                continue
            out = f.get("outliers", {})
            if fw in out.get("denied", []):
                continue
            if vtuple(f["min"]) <= v <= vtuple(f["max"]) or fw in out.get("accepted", []):
                found.append("%s (%s-%s%s): https://kindlemodding.org%s" % (
                    jb["name"], f["min"], f["max"],
                    ", needs a registered Kindle" if jb.get("registration") else "", jb.get("url", "")))
                break
    return found


def main():
    d = read_ssh() if IP else read_usb()
    warnings = []
    warn = warnings.append
    code, name, short = model_of(d.get("sn", ""))
    if not code and os.environ.get("KINDLE_MODEL"):
        # Serial unreadable (e.g. over USB on Linux): take the model from Device Info.
        short = os.environ["KINDLE_MODEL"].upper()
        code, name = "from KINDLE_MODEL", next((n for n, s in list(OLD) + list(NEW) if s == short), short)
    fw, jb, ko = d.get("fw", ""), d.get("jb", "no"), d.get("ko", "")
    plugins, patches = d.get("plugins", "").split(), d.get("patches", "").split()

    print("Model:          %s" % ("%s [code %s]" % (name, code) if code else "unknown (read Settings > Device Options > Device Info)"))
    if not code:
        warn("Couldn't read the model. Look it up under Settings > Device Options > Device Info and re-run "
             "with KINDLE_MODEL set to its short name (PW5, KT5, PW6, KS, ...).")
    elif short != TESTED_MODEL:
        warn("This setup was made on a Paperwhite 5. On a %s the jailbreak and install steps differ, "
             "and the home screen's layout may need changes (screen size, buttons, light)." % name)
    elif "Signature" in name:
        warn("Signature Edition: very close to the PW5 (adds a light sensor), but not tested.")

    print("Firmware:       %s" % (fw or "unknown"))
    print("Jailbroken:     %s" % jb)
    if not fw:
        warn("Couldn't read the firmware version.")
    elif jb == "no" and short:
        found = jailbreaks_for(short, fw)
        if found is None:
            warn("Couldn't load %s; check kindlemodding.org by hand for %s on %s." % (JAILBREAKS_URL, short, fw))
        elif found:
            print("Jailbreaks for %s on %s (from kindlemodding.org; read the page before using one):" % (short, fw))
            for f in found:
                print("    " + f)
            if not any(f.startswith("SpiderCat ") for f in found):
                warn("INSTALL.md uses SpiderCat, which doesn't fit this Kindle: follow the jailbreak page above instead.")
        else:
            warn("No known jailbreak for %s on %s. Keep the Kindle offline (airplane mode) and watch kindlemodding.org." % (short, fw))
    if fw and fw != TESTED_FIRMWARE:
        print("  (this repo was tested on firmware %s)" % TESTED_FIRMWARE)

    ota = d.get("ota", "")
    print("Amazon updates: %s" % ota)
    if ota == "ACTIVE":
        warn("Amazon's updater is active: an update can remove the jailbreak. Block it (see the jailbreak's page).")

    print("KOReader:       %s" % (ko or "not installed"))
    if ko and ko != TESTED_KOREADER:
        warn("Tested on KOReader %s. Follow 'Updating KOReader' in AGENTS.md before deploying." % TESTED_KOREADER)
    print("KPM packages:   %s" % (d.get("kpm") or "none"))
    print("Project: Title: %s" % ("yes" if "projecttitle.koplugin" in plugins else "no"))
    print("Home plugin:    %s" % ("yes" if "kindlehome.koplugin" in plugins else "no"))
    print("Patches:        %s" % (" ".join(patches) or "none"))
    free = d.get("free", "")
    print("Free space:     %s MB" % (free or "?"))
    if free.isdigit() and int(free) < 500:
        warn("Low free space: the firmware deletes books on its own when storage runs out. Back up first.")

    print()
    for w in warnings:
        print("!! " + w)
    print("OK: matches what this repo was tested on." if not warnings else "Sort out the !! lines before going on.")
    return 1 if warnings else 0


if __name__ == "__main__":
    sys.exit(main())
