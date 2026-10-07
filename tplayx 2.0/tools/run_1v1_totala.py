"""Same-PC 1v1 test for plain Total Annihilation (C:\\CAVEDOG\\TOTALA\\TotalA.exe + tplayx.dll).
  python run_1v1_totala.py [options]          (or RUN_1V1_TOTALA.bat [options])
Options:
  --seconds N   how long the battle runs before the logs are checked (default 120)
  --norecord    do not type .record in the chat
  --nodeploy    do not copy the freshly built tplayx.dll into TOTALA
  --keep        leave both games running at the end
  --cmds LIST   after the start the host types these .commands (comma list, e.g. fixall,about,time);
                the self-only ones must NOT reach the joiner (checked in the joiner's recorder log)
  --battle      battle test: builds + deploys the TEST build (tplayx_test.dll, has +midbattle),
                host spawns units east of the map centre, joiner west, both patrol to the
                centre; topped up every 10 s, re-sent to the centre every 30 s.
                The release tplayx.dll is put back afterwards. Default battle 240 s.
  --wave N        units per spawn wave per side           (default 30)
  --live N        keep this many units alive per side    (default 120)
  --spread PX     each side's distance from the centre   (default 1200)
  --cx P --cz P   battle centre in % of the map  (default 25 75 = middle of the bottom-left quarter)
  --host-units L  host unit types   (default ARMSTUMP,ARMFLASH)
  --join-units L  joiner unit types (default CORRAID,CORAK)
kill old games -> deploy DLL -> host (Next) -> joiner (Join) -> Go both -> Start
-> .record on both -> battle runs -> check recorder logs, ErrorLog.txt, Windows crash events.
Progress: totala_1v1_status.txt   Result: totala_1v1_result_<time>.txt (PASS / FAIL)"""
import os, sys, time, struct, shutil, subprocess, glob, ctypes, ctypes.wintypes as wt

HERE = os.path.dirname(os.path.abspath(__file__))
TA = r"C:\CAVEDOG\TOTALA"
EXE = os.path.join(TA, "TotalA.exe")
BUILT_DLL = r"C:\tpLAYX1\TPLAYX_upload\tplayx 2.0\src\Recorder\tplayx.dll"
BUILT_MAP = r"C:\tpLAYX1\TPLAYX_upload\tplayx 2.0\src\Recorder\tplayx.map"
HOST_ARGS = ["-p30", "-d", "-N1:127.0.0.1", "-HMy_Game"]
JOIN_ARGS = ["-p30", "-d", "-N1:127.0.0.1", "-jMy_Game"]
ARGS = sys.argv[1:]
def opt(name, default):
    return ARGS[ARGS.index(name) + 1] if name in ARGS and ARGS.index(name) + 1 < len(ARGS) else default
BATTLE = "--battle" in ARGS
SECONDS = int(opt("--seconds", 240 if BATTLE else 120))
CX, CZ = int(opt("--cx", 25)), int(opt("--cz", 75))
WAVE, LIVE, SPREAD = int(opt("--wave", 30)), int(opt("--live", 120)), int(opt("--spread", 1200))
HOST_UNITS, JOIN_UNITS = opt("--host-units", "ARMSTUMP,ARMFLASH").upper(), opt("--join-units", "CORRAID,CORAK").upper()
LAZBUILD = r"C:\lazarus\lazbuild.exe"
LPI = r"C:\tpLAYX1\TPLAYX_upload\tplayx 2.0\src\Recorder\tplayx.lpi"
TEST_DLL = r"C:\tpLAYX1\TPLAYX_upload\tplayx 2.0\src\Recorder\tplayx_test.dll"
STAMP = time.strftime("%H%M%S")
ST = os.path.join(HERE, "totala_1v1_status.txt")
RESULT = os.path.join(HERE, "totala_1v1_result_%s.txt" % STAMP)
CMDS = [c.strip().lstrip(".") for c in ARGS[ARGS.index("--cmds") + 1].split(",")] if "--cmds" in ARGS else []
LOCAL_CMDS = {"help", "status", "crash", "panic", "about", "fixfacexps", "protectdt", "fixall", "time",
              "sharemappos", "record", "recordstatus", "3dta", "stoplog", "createtxt", "lockon", "randmap",
              "rm", "fakewatch", "forcecd", "yankspank"}
BAD = ("exception", "access violation", "error", "not large enough")

u32 = ctypes.windll.user32
k32 = ctypes.windll.kernel32
u32.SetProcessDPIAware()
EnumProc = ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
k32.ReadProcessMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t,
                                  ctypes.POINTER(ctypes.c_size_t)]


def note(m):
    line = time.strftime("%H:%M:%S ") + m
    print(line, flush=True)
    with open(ST, "a") as f:
        f.write(line + "\n")


# ---------------------------------------------------------------- windows / input
def hwnd_of(pid):
    found = []

    def cb(h, _):
        p = wt.DWORD()
        u32.GetWindowThreadProcessId(h, ctypes.byref(p))
        if p.value == pid and u32.IsWindowVisible(h):
            found.append(h)
        return True
    u32.EnumWindows(EnumProc(cb), 0)
    return found[0] if found else None


def alive(pid):
    h = k32.OpenProcess(0x1000, False, pid)
    if not h:
        return False
    code = wt.DWORD()
    k32.GetExitCodeProcess(h, ctypes.byref(code))
    k32.CloseHandle(h)
    return code.value == 259


def focus(pid):
    h = hwnd_of(pid)
    if not h:
        return False
    if u32.GetForegroundWindow() == h:
        return True
    if u32.IsIconic(h):
        u32.ShowWindow(h, 9)
    u32.keybd_event(0x12, 0, 0, 0); u32.keybd_event(0x12, 0, 2, 0)
    u32.SetForegroundWindow(h)
    time.sleep(0.3)
    return u32.GetForegroundWindow() == h


def key(scan):
    u32.keybd_event(0, scan, 0x8, 0); time.sleep(0.05)
    u32.keybd_event(0, scan, 0x8 | 0x2, 0); time.sleep(0.05)


SC = dict(zip("qwertyuiop", range(0x10, 0x1A)))
SC.update(zip("asdfghjkl", range(0x1E, 0x27)))
SC.update(zip("zxcvbnm", range(0x2C, 0x33)))
SC.update(zip("1234567890", range(0x02, 0x0C)))
SC.update({" ": 0x39, ".": 0x34, "-": 0x0C})
SC_ENTER = 0x1C


def tap(pid, ch):
    focus(pid); time.sleep(0.3)
    key(SC[ch] if isinstance(ch, str) else ch)
    time.sleep(0.8)


def chat(pid, text):
    focus(pid); time.sleep(0.4)
    key(SC_ENTER); time.sleep(0.4)
    for c in text:
        key(SC[c.lower()])
    time.sleep(0.3); key(SC_ENTER); time.sleep(0.5)


class _MI(ctypes.Structure):
    _fields_ = [("dx", ctypes.c_long), ("dy", ctypes.c_long), ("data", ctypes.c_ulong),
                ("flags", ctypes.c_ulong), ("time", ctypes.c_ulong), ("extra", ctypes.c_size_t)]


class _IN(ctypes.Structure):
    _fields_ = [("type", ctypes.c_ulong), ("mi", _MI)]


def _mouse(flags):
    i = _IN(0, _MI(0, 0, 0, flags, 0, 0))
    u32.SendInput(1, ctypes.byref(i), ctypes.sizeof(i))


def click(pid, gx, gy):
    """click a point given in 640x480 GUI coordinates, scaled to the client area"""
    focus(pid); time.sleep(0.4)
    h = hwnd_of(pid); rc = wt.RECT(); pt = wt.POINT(0, 0)
    u32.GetClientRect(h, ctypes.byref(rc)); u32.ClientToScreen(h, ctypes.byref(pt))
    x, y = pt.x + gx * rc.right // 640, pt.y + gy * rc.bottom // 480
    for dx in (-6, 0):
        u32.SetCursorPos(x + dx, y); time.sleep(0.15)
    _mouse(0x0002); time.sleep(0.08); _mouse(0x0004); time.sleep(0.8)


NEXT_BTN, GO_BTN, START_BTN = (515, 325), (487, 79), (570, 452)


# ---------------------------------------------------------------- game memory (TA 3.1c)
def rd(pid, a, n):
    h = k32.OpenProcess(0x0010 | 0x0400, False, pid)
    if not h:
        return None
    b = ctypes.create_string_buffer(n); g = ctypes.c_size_t()
    ok = k32.ReadProcessMemory(h, ctypes.c_void_p(a), b, n, ctypes.byref(g))
    k32.CloseHandle(h)
    return b.raw[:g.value] if ok else None


def main_ptr(pid):
    r = rd(pid, 0x511DE8, 4)
    return struct.unpack("<I", r)[0] if r and len(r) == 4 else 0


def slot_ctrl(pid, slot):
    m = main_ptr(pid)
    r = rd(pid, m + 0x3A000 + slot * 0x14B + 0x73, 1) if m else None
    return r[0] if r else -1


def tick(pid):
    m = main_ptr(pid)
    r = rd(pid, m + 0x38A47, 4) if m else None
    return struct.unpack("<I", r)[0] if r and len(r) == 4 else 0


def map_loaded(pid):
    m = main_ptr(pid)
    r = rd(pid, m + 0x14223, 4) if m else None
    return bool(r) and struct.unpack("<i", r)[0] > 0


def running(hp, jp):
    a, b = tick(hp), tick(jp); time.sleep(3)
    return tick(hp) > a and tick(jp) > b and map_loaded(hp) and map_loaded(jp)


def newest_log(after):
    fs = [f for f in glob.glob(os.path.join(TA, "log", "*.txt")) if os.path.getctime(f) >= after - 1]
    return max(fs, key=os.path.getctime) if fs else None


def log_has(path, text):
    try:
        return path is not None and text in open(path, errors="replace").read()
    except OSError:
        return False


def in_room(pid, lg):
    return log_has(lg, "TDPlay.Open, dwFlags = $00000002") or slot_ctrl(pid, 0) == 1


def has_joined(pid, lg):
    return log_has(lg, "Player #2:") or slot_ctrl(pid, 1) == 3


def launch(args):
    p = subprocess.Popen([EXE] + args, cwd=TA)
    t = time.time()
    while time.time() - t < 60:
        if hwnd_of(p.pid):
            return p.pid
        if p.poll() is not None:
            break
        time.sleep(1)
    raise SystemExit(note("FAILED: TotalA.exe %s opened no window" % " ".join(args)) or 1)


# ---------------------------------------------------------------- checks
def crash_events(since):
    ps = ("Get-WinEvent -FilterHashtable @{LogName='Application';Id=1000,1001;StartTime=[datetime]'%s'} "
          "-ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'TotalA' -and $_.Message -notmatch 'AppHang' } | "
          "ForEach-Object { $_.TimeCreated.ToString('HH:mm:ss') + ' ' + (($_.Message -split \"`n\")[0..6] -join ' | ') }"
          % time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(since)))
    r = subprocess.run(["powershell", "-NoProfile", "-Command", ps], capture_output=True, text=True)
    return [l for l in r.stdout.splitlines() if l.strip()]


def new_logs(since):
    return sorted(f for f in glob.glob(os.path.join(TA, "log", "*.txt")) if os.path.getmtime(f) >= since - 1)


def bad_lines(path):
    out = []
    for l in open(path, errors="replace"):
        low = l.lower()
        if any(b in low for b in BAD) and "unknown packet" not in low and "subpacket longer" not in low:
            out.append(l.rstrip())
    return out


def deploy_test():
    r = subprocess.run([LAZBUILD, "--build-all", "--build-mode=Test", LPI], capture_output=True, text=True)
    lps = LPI[:-4] + ".lps"                     # lazbuild remembers the last mode: back to Default
    try:
        t = open(lps, encoding="latin-1").read()
        open(lps, "w", encoding="latin-1").write(t.replace('<BuildModes Active="Test"/>', '<BuildModes Active="Default"/>'))
    except OSError:
        pass
    tail = [l for l in r.stdout.splitlines() if "Error" in l or "Fatal" in l or "lines compiled" in l]
    if r.returncode != 0 or not os.path.exists(TEST_DLL):
        raise SystemExit(note("FAILED to build the test DLL: " + " | ".join(tail[-5:])) or 1)
    dst = os.path.join(TA, "tplayx.dll")
    if os.path.exists(dst):
        shutil.copy2(dst, dst + ".pre_battle_%s" % STAMP)
    shutil.copy2(TEST_DLL, dst)
    return "TEST build deployed (%s)" % (tail[-1] if tail else "built")


def restore_release():
    dst = os.path.join(TA, "tplayx.dll")
    src = BUILT_DLL if os.path.exists(BUILT_DLL) else dst + ".pre_battle_%s" % STAMP
    for _ in range(10):
        try:
            shutil.copy2(src, dst)
            return "release tplayx.dll put back"
        except OSError:
            time.sleep(1)
    return "could NOT put the release tplayx.dll back - copy it by hand"


def send_cmd(pid, line):
    with open(os.path.join(TA, "aio_%d.cmd" % pid), "a") as f:
        f.write(line + "\n")


def battle(hp, jp, seconds, fail):
    sides = ((hp, 1, HOST_UNITS, "host"), (jp, -1, JOIN_UNITS, "joiner"))
    t0 = time.time(); last_wave = last_charge = 0
    note("battle: centre at %d%%/%d%% of the map, host %s east, joiner %s west, %d px out, waves of %d, kept at %d live"
         % (CX, CZ, HOST_UNITS, JOIN_UNITS, SPREAD, WAVE, LIVE))
    shot = False
    while time.time() - t0 < seconds:
        now = time.time()
        if now - last_wave >= 10:
            for pid, side, units, _ in sides:
                send_cmd(pid, "midbattle count=%d cap=%d side=%d spread=%d cx=%d cz=%d units=%s"
                         % (WAVE, LIVE, side, SPREAD, CX, CZ, units))
            last_wave = now
        if now - last_charge >= 30:
            for pid, _, _, _ in sides:
                send_cmd(pid, "midcharge cx=%d cz=%d" % (CX, CZ))
            last_charge = now
        if not shot and now - t0 > 60:
            screenshot("totala_battle_%s.png" % STAMP); shot = True
        for pid, _, _, name in sides:
            if not alive(pid):
                fail.append("%s game closed after %d s of battle" % (name, now - t0))
        if fail:
            return
        time.sleep(2)


def screenshot(name):
    ps = ("Add-Type -AssemblyName System.Windows.Forms,System.Drawing; $b=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds;"
          "$bm=New-Object System.Drawing.Bitmap $b.Width,$b.Height; $g=[System.Drawing.Graphics]::FromImage($bm);"
          "$g.CopyFromScreen($b.Location,[System.Drawing.Point]::Empty,$b.Size); $bm.Save('%s')" % os.path.join(HERE, name))
    subprocess.run(["powershell", "-NoProfile", "-Command", ps], capture_output=True)


def deploy():
    if BATTLE:
        return deploy_test()
    if "--nodeploy" in ARGS or not os.path.exists(BUILT_DLL):
        return "not deployed (using the DLL already in TOTALA)"
    dst = os.path.join(TA, "tplayx.dll")
    if os.path.exists(dst) and open(dst, "rb").read() == open(BUILT_DLL, "rb").read():
        return "tplayx.dll in TOTALA is already the latest build"
    if os.path.exists(dst):
        shutil.copy2(dst, dst + ".pre_1v1_%s" % STAMP)
    shutil.copy2(BUILT_DLL, dst)
    if os.path.exists(BUILT_MAP):
        shutil.copy2(BUILT_MAP, os.path.join(TA, "tplayx.map"))
    return "deployed %s (%d bytes, built %s)" % (os.path.basename(BUILT_DLL), os.path.getsize(BUILT_DLL),
                                                time.strftime("%H:%M", time.localtime(os.path.getmtime(BUILT_DLL))))


def kill():
    subprocess.run("taskkill /f /im TotalA.exe", shell=True, capture_output=True)


# ---------------------------------------------------------------- run
def main():
    open(ST, "w").close()
    note("== TOTALA 1v1 test (%d s battle)" % SECONDS)
    kill(); time.sleep(3)
    t0 = time.time()
    err_log = os.path.join(TA, "ErrorLog.txt")
    err_before = os.path.getmtime(err_log) if os.path.exists(err_log) else 0
    note("DLL: " + deploy())

    for attempt in range(3):
        th = time.time(); hp = launch(HOST_ARGS); time.sleep(12)
        hlog = newest_log(th)
        # Next = Enter only. A mouse click at the "Next" spot is NOT safe: once the battle
        # room is open (the recorder log can lag ~10 s behind), the same spot is the
        # "Game Status: Open/Closed" button, and clicking it closes the game to the joiner.
        for k in range(3):
            tap(hp, SC_ENTER)
            t1 = time.time()
            while time.time() - t1 < 20:
                time.sleep(2)
                hlog = hlog or newest_log(th)
                if in_room(hp, hlog):
                    break
            if in_room(hp, hlog):
                break
        if alive(hp) and in_room(hp, hlog):
            break
        note("host not in the battle room - relaunching"); kill(); time.sleep(3)
    else:
        raise SystemExit(note("FAILED: host never reached the battle room") or 1)
    note("host pid %d in battle room" % hp)

    tj = time.time(); jp = launch(JOIN_ARGS); time.sleep(12)
    jlog = newest_log(tj)
    for attempt in range(8):
        tap(jp, "u"); time.sleep(3)
        tap(jp, "j"); time.sleep(6)
        if has_joined(hp, hlog):
            break
        if not alive(hp):
            raise SystemExit(note("FAILED: host closed while joining") or 1)
        note("join attempt %d: not in the room yet" % (attempt + 1))
    if not has_joined(hp, hlog):
        raise SystemExit(note("FAILED to join") or 1)
    hj = hwnd_of(jp)
    if hj:
        u32.SetWindowPos(hj, 0, 660, 0, 0, 0, 0x0001 | 0x0004)   # side by side: joiner to the right
    note("joiner pid %d joined | host log %s" % (jp, os.path.basename(hlog or "?")))

    if "--norecord" not in ARGS:
        chat(hp, ".record autohost"); chat(jp, ".record autojoin")
        note("typed .record autohost / .record autojoin in the battle room")

    started = False
    for attempt in range(4):
        if attempt == 0:
            click(jp, *GO_BTN); time.sleep(2)
            click(hp, *GO_BTN); time.sleep(2)
        click(hp, *START_BTN)
        t = time.time()
        while time.time() - t < 40:
            jlog = jlog or newest_log(tj)
            if (log_has(hlog, "loading started") and log_has(jlog, "loading started")) or running(hp, jp):
                started = True; break
            time.sleep(1)
        if started:
            break
        note("start attempt %d: not running yet - toggling Go again" % (attempt + 1))
        click(jp, *GO_BTN); time.sleep(1); click(jp, *GO_BTN); time.sleep(2)
    if not started:
        raise SystemExit(note("FAILED to start the game") or 1)
    note("game running on both sides - battle for %d s" % SECONDS)

    fail = []
    if BATTLE:
        mlog = os.path.join(TA, "midbattle.log")
        if os.path.exists(mlog):
            os.remove(mlog)
        battle(hp, jp, SECONDS, fail)
    if CMDS:
        time.sleep(15)
        for c in CMDS:
            chat(hp, "." + c); time.sleep(2)
        note("host typed: " + ", ".join("." + c for c in CMDS))
        time.sleep(5)
        try:
            ps = ("Add-Type -AssemblyName System.Windows.Forms,System.Drawing; $b=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds;"
                  "$bm=New-Object System.Drawing.Bitmap $b.Width,$b.Height; $g=[System.Drawing.Graphics]::FromImage($bm);"
                  "$g.CopyFromScreen($b.Location,[System.Drawing.Point]::Empty,$b.Size); $bm.Save('%s')"
                  % os.path.join(HERE, "totala_1v1_cmds_%s.png" % STAMP))
            subprocess.run(["powershell", "-NoProfile", "-Command", ps], capture_output=True)
        except Exception:
            pass
    t = time.time()
    while not BATTLE and time.time() - t < SECONDS:
        time.sleep(5)
        for pid, name in ((hp, "host"), (jp, "joiner")):
            if not alive(pid):
                fail.append("%s game closed after %d s of battle" % (name, time.time() - t))
        if fail:
            break

    res = ["TOTALA 1v1 test %s  (battle %d s, DLL %s)" % (time.strftime("%Y-%m-%d %H:%M"), SECONDS,
           time.strftime("%H:%M", time.localtime(os.path.getmtime(os.path.join(TA, "tplayx.dll")))))]
    if os.path.exists(err_log) and os.path.getmtime(err_log) > err_before:
        fail.append("ErrorLog.txt written (TA crash handler)")
    for e in crash_events(t0):
        fail.append("Windows crash event: " + e)
    logs = new_logs(t0)
    keep = os.path.join(HERE, "totala_logs_%s" % STAMP)
    os.makedirs(keep, exist_ok=True)
    for lg in logs:
        shutil.copy2(lg, keep)
        bad = bad_lines(lg)
        res.append("log %s: %d lines, %d problem lines" % (os.path.basename(lg),
                   sum(1 for _ in open(lg, errors="replace")), len(bad)))
        for b in bad[:20]:
            res.append("    " + b)
        if bad:
            fail.append("%s has %d exception/error lines" % (os.path.basename(lg), len(bad)))
    if CMDS:
        jtext = open(jlog, errors="replace").read() if jlog else ""
        for c in CMDS:
            name = c.split()[0].lower()
            seen = ("Command:." + name) in jtext
            if name in LOCAL_CMDS and seen:
                fail.append(".%s is local-only but reached the joiner" % name)
            res.append(".%s typed by the host: %s the joiner (%s)" % (name, "REACHED" if seen else "did not reach",
                       "local-only" if name in LOCAL_CMDS else "shared"))
    if BATTLE:
        mlog = os.path.join(TA, "midbattle.log")
        ml = open(mlog, errors="replace").read().splitlines() if os.path.exists(mlog) else []
        sp = [l for l in ml if "spawned" in l]
        res.append("midbattle.log: %d spawn waves, %d charges, %d problems"
                   % (len(sp), sum("midcharge" in l for l in ml), sum(("exception" in l.lower() or "not found" in l) for l in ml)))
        for l in sp[:2] + sp[-2:]:
            res.append("    " + l)
        for l in ml:
            if "exception" in l.lower() or "not found" in l or "none of the units" in l:
                fail.append("midbattle: " + l)
        if not sp:
            fail.append("no units were spawned (midbattle.log)")
        if os.path.exists(mlog):
            shutil.copy2(mlog, keep)
    if len(logs) < 2:
        fail.append("expected 2 recorder logs (host + joiner), found %d" % len(logs))
    res.insert(1, "RESULT: " + ("FAIL" if fail else "PASS - both logs written, no exceptions, no crash"))
    res[2:2] = ["  " + f for f in fail]
    res.append("logs copied to " + keep)
    open(RESULT, "w").write("\n".join(res) + "\n")
    for l in res:
        note(l)
    if "--keep" not in ARGS:
        kill()
        if BATTLE:
            time.sleep(2)
            note(restore_release())
    elif BATTLE:
        note("games left running with the TEST DLL - run again without --battle (or copy tplayx.dll) to put the release DLL back")
    note("== done: " + os.path.basename(RESULT))
    return 1 if fail else 0


if __name__ == "__main__":
    try:
        rc = main()
    except SystemExit as e:
        rc = e.code
        if BATTLE and "--keep" not in ARGS:
            kill(); time.sleep(2); note(restore_release())
    sys.exit(rc)
