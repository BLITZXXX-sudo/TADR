unit TDrawUnhook;

{
  TDrawUnhook - removes TDRAW's code hooks from TA's network/lobby code
                ($00450000-$00457000) while the game runs.

  WHY
  ---
  TDRAW (ddraw wrapper) still uses the stock 10-player layout, and its hook
  engine is not safe when a hook fires again inside its own handler. With
  12+ players this crashes the host at $450D20 / $45490C when someone joins.
  Removing TDRAW's hooks in this range lets a full 16-player game load.
  This replaces the test script tdraw_unhook.py.

  HOW
  ---
  - Reads the original bytes of $450000-$457000 from the exe on disk
    (file offset = VA - $400C00).
  - A background thread compares memory against them every second
    (TDRAW installs some hooks late).
  - A changed range whose jmp/call goes into TPLAYX is KEPT (our own hooks).
    Any other changed range is put back to the original bytes.

  SWITCHES
  --------
  State_TDrawUnhook = False and rebuild   -> plugin off.
  Or, without rebuilding: create an empty file  tdrawunhook.off  in the game
  folder -> the plugin does nothing that run.

  OUTPUT: <TA folder>\tdrawunhook.log
}

interface

uses
  PluginEngine;

Procedure OnInstall;
Procedure OnUninstall;

const
  State_TDrawUnhook : boolean = true;

function GetPlugin : TPluginData;

implementation

uses
  Windows,
  SysUtils,
  Classes;

const
  RANGE_LO    = $00450000;
  RANGE_HI    = $00457000;
  RANGE_LEN   = RANGE_HI - RANGE_LO;
  TEXT_DELTA  = $00400C00;        // .text: file offset = VA - $400C00
  CHECK_MS    = 1000;
  START_MS    = 2000;
  MAX_SANE_DIFF = 4096;           // more than this on the first pass = wrong exe

  // TPLAYX's own hooks in this range - never touched, even if the
  // ownership check below should fail for some reason.
  // The last three are JoinGuard's redirected calls: only the 4-byte rel32
  // after the unchanged E8 differs, so the changed range starts one byte in.
  KEEP_ADDRS : array[0..9] of Cardinal = ( $0045130F, $00452B54,
                                           $00452B5E, $00452E67,
                                           $00450CBC, $00450CF7, $00450D0C,
                                           $00450B70, $00450C2A, $00450C3D );

var
  Orig       : array of Byte;
  LogPath    : string = '';
  LogLock    : TRTLCriticalSection;
  LogReady   : boolean = false;
  StopFlag   : boolean = false;
  ThreadH    : THandle = 0;
  SelfLo     : Cardinal = 0;
  SelfHi     : Cardinal = 0;
  Unhooked   : Integer = 0;
  Kept       : array of Cardinal;

  // v2: filter in front of TDRAW's code writer
  WriterAddr    : Cardinal = 0;     // TDRAW base + TDRAW_WRITER_RVA
  WriterCont    : Cardinal = 0;     // WriterAddr + 5 (after the 5 bytes we replace)
  WriterChecked : boolean = false;  // tried once (patched or not recognised)
  WriterPatched : boolean = false;
  WritesBlocked : LongInt = 0;

  // v3: TDRAW guard-order crash fix (null options object)
  GuardAddr     : Cardinal = 0;
  GuardCont     : Cardinal = 0;
  GuardChecked  : boolean = false;
  GuardPatched  : boolean = false;

const
  TDRAW_WRITER_RVA = $43850;        // TDRAW.dll 2025.8.29.0
  WRITER_HEAD : array[0..4] of Byte = ($55,$8B,$EC,$6A,$FE);   // push ebp/mov ebp,esp/push -2
  // -1 = relocated address byte (skip)
  WRITER_SIG : array[0..29] of SmallInt = (
    $55,$8B,$EC,$6A,$FE,$68,-1,-1,-1,-1,$68,-1,-1,-1,-1,
    $64,$A1,$00,$00,$00,$00,$50,$83,$EC,$10,$53,$56,$57,$A1,-1);
  WRITER_SIG2_OFS = $48;            // mov ebx,[ebp+0C] / push ebx / mov esi,[ebp+10] / push esi
  WRITER_SIG2 : array[0..7] of Byte = ($8B,$5D,$0C,$53,$8B,$75,$10,$56);

  // TDRAW RVA $30040: guard-order option lookup, thiscall(options, stance).
  // Unlike the patrol version at $300E0 it does not check for a nil options
  // object, so clicking Guard crashes (read of [0+$84]) whenever TDRAW's
  // construction-unit options object does not exist.
  TDRAW_GUARD_RVA = $30040;
  GUARD_HEAD : array[0..10] of Byte = ($55,$8B,$EC,$8B,$45,$08,$83,$E8,$00,$74,$25);

// -----------------------------------------------------------------------------
// Logging
// -----------------------------------------------------------------------------

procedure ULog(const s : string);
var
  f : TextFile;
begin
  if not LogReady then Exit;
  EnterCriticalSection(LogLock);
  try
    try
      AssignFile(f, LogPath);
      if FileExists(LogPath) then Append(f) else Rewrite(f);
      WriteLn(f, FormatDateTime('hh:nn:ss ', Now) + s);
      CloseFile(f);
    except
    end;
  finally
    LeaveCriticalSection(LogLock);
  end;
end;

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

// Address range of this DLL (TPLAYX), found from the address of our own code.
procedure FindSelfRange;
var
  mbi   : TMemoryBasicInformation;
  base  : Cardinal;
  lfa   : LongInt;
begin
  FillChar(mbi, SizeOf(mbi), 0);
  VirtualQuery(@FindSelfRange, mbi, SizeOf(mbi));
  base   := Cardinal(mbi.AllocationBase);
  lfa    := PLongInt(base + $3C)^;
  SelfLo := base;
  SelfHi := base + PCardinal(base + Cardinal(lfa) + $50)^;   // SizeOfImage
end;

function InSelf(a : Cardinal) : boolean;
begin
  result := (a >= SelfLo) and (a < SelfHi);
end;

function IsKeepAddr(a : Cardinal) : boolean;
var
  i : Integer;
begin
  result := true;
  for i := Low(KEEP_ADDRS) to High(KEEP_ADDRS) do
    if (a <= KEEP_ADDRS[i]) and (KEEP_ADDRS[i] < a + 5) then Exit;
  for i := 0 to High(Kept) do
    if Kept[i] = a then Exit;
  result := false;
end;

// Does a changed range starting at a hold a jmp/call into TPLAYX?
// Looks at every byte of the range (a hook may start a byte or two in).
function OwnedBySelf(a, len : Cardinal) : boolean;
var
  p   : Cardinal;
  op  : Byte;
  tgt : Cardinal;
begin
  result := true;
  p := a - 4;                         // an E8/E9 whose opcode byte is unchanged
  while p < a + len do
  begin
    op := PByte(p)^;
    if (op = $E9) or (op = $E8) then
    begin
      tgt := Cardinal(LongInt(p + 5) + PLongInt(p + 1)^);
      if InSelf(tgt) then Exit;
    end;
    Inc(p);
  end;
  result := false;
end;

function LoadOriginal : boolean;
var
  fs : TFileStream;
begin
  result := false;
  SetLength(Orig, RANGE_LEN);
  try
    fs := TFileStream.Create(ParamStr(0), fmOpenRead or fmShareDenyNone);
    try
      fs.Position := RANGE_LO - TEXT_DELTA;
      result := fs.Read(Orig[0], RANGE_LEN) = RANGE_LEN;
    finally
      fs.Free;
    end;
  except
    on e : Exception do ULog('cannot read exe: ' + e.Message);
  end;
end;

procedure RestoreBytes(a, len : Cardinal);
var
  old : DWORD;
begin
  if VirtualProtect(Pointer(a), len, PAGE_EXECUTE_READWRITE, old) then
  begin
    Move(Orig[a - RANGE_LO], Pointer(a)^, len);
    VirtualProtect(Pointer(a), len, old, old);
    FlushInstructionCache(GetCurrentProcess, Pointer(a), len);
  end;
end;

function Differs(i : Cardinal) : boolean; inline;
begin
  result := PByte(RANGE_LO + i)^ <> Orig[i];
end;

// Count differing bytes (used once, as a sanity check on the exe layout).
function CountDiff : Cardinal;
var
  i : Cardinal;
begin
  result := 0;
  for i := 0 to RANGE_LEN - 1 do
    if Differs(i) then Inc(result);
end;

// One pass over the range. Returns the number of ranges restored.
function ScanOnce : Integer;
var
  i, j, a : Cardinal;
  function Near(k : Cardinal) : boolean;
  var
    m : Cardinal;
  begin
    // a range continues while this byte or one of the next two differs
    result := true;
    for m := k to k + 2 do
      if (m < RANGE_LEN) and Differs(m) then Exit;
    result := false;
  end;
begin
  result := 0;
  i := 0;
  while i < RANGE_LEN do
  begin
    if not Differs(i) then
    begin
      Inc(i);
      Continue;
    end;
    j := i;
    while (j < RANGE_LEN) and Near(j) do Inc(j);
    a := RANGE_LO + i;
    if IsKeepAddr(a) then
      // known TPLAYX hook or already logged as kept
    else if OwnedBySelf(a, j - i) then
    begin
      SetLength(Kept, Length(Kept) + 1);
      Kept[High(Kept)] := a;
      ULog(Format('keep   %.8x len %d (TPLAYX)', [a, j - i]));
    end
    else
    begin
      // re-check after a moment, in case someone is still writing a hook
      Sleep(50);
      if Differs(i) and not OwnedBySelf(a, j - i) then
      begin
        RestoreBytes(a, j - i);
        Inc(result);
        Inc(Unhooked);
        ULog(Format('UNHOOK %.8x len %d', [a, j - i]));
      end;
    end;
    i := j;
  end;
end;

// -----------------------------------------------------------------------------
// v2: block TDRAW from (re)writing hooks into $450000-$457000
// TDRAW's writer: stdcall(addr, len, savebuf, newbytes) - it copies the
// current bytes to savebuf, then writes newbytes. For our range we only do the
// copy (so TDRAW's own later restore writes back the original code).
// -----------------------------------------------------------------------------

function ShouldBlockWrite(addr, len, save, src : Cardinal) : LongBool; stdcall;
begin
  result := (addr < RANGE_HI) and (addr + len > RANGE_LO);
  if not result then Exit;
  if (save <> 0) and (len > 0) and (len <= 4096) then
    Move(Pointer(addr)^, Pointer(save)^, len);
  InterlockedIncrement(WritesBlocked);
end;

procedure WriterStub; assembler; nostackframe;
asm
  // re-push the 4 args: [esp+4]=addr [esp+8]=len [esp+C]=save [esp+10]=src
  push dword ptr [esp + $10]
  push dword ptr [esp + $10]
  push dword ptr [esp + $10]
  push dword ptr [esp + $10]
  call ShouldBlockWrite
  test eax, eax
  jz   @orig
  mov  eax, 1                       // writer returns 1 = OK
  ret  $10
@orig:
  push ebp                          // the 5 bytes we replaced
  mov  ebp, esp
  push -2
  jmp  dword ptr [WriterCont]
end;

procedure PatchTDrawWriter;
var
  h, a : Cardinal;
  i    : Integer;
  b    : array[0..4] of Byte;
  old  : DWORD;
  rel  : LongInt;
begin
  if WriterChecked then Exit;
  h := GetModuleHandle('TDRAW.dll');
  if h = 0 then Exit;                         // not loaded yet - try again later
  WriterChecked := True;
  a := h + TDRAW_WRITER_RVA;
  for i := 0 to High(WRITER_SIG) do
    if (WRITER_SIG[i] >= 0) and (PByte(a + Cardinal(i))^ <> Byte(WRITER_SIG[i])) then
    begin
      ULog(Format('TDRAW writer not recognised at %.8x (other TDRAW version?) - only the poll is active', [a]));
      Exit;
    end;
  for i := 0 to High(WRITER_SIG2) do
    if PByte(a + WRITER_SIG2_OFS + Cardinal(i))^ <> WRITER_SIG2[i] then
    begin
      ULog(Format('TDRAW writer not recognised at %.8x (part 2) - only the poll is active', [a]));
      Exit;
    end;
  WriterAddr := a;
  WriterCont := a + 5;
  rel := LongInt(Cardinal(@WriterStub)) - LongInt(a + 5);
  b[0] := $E9;
  Move(rel, b[1], 4);
  if VirtualProtect(Pointer(a), 5, PAGE_EXECUTE_READWRITE, old) then
  begin
    Move(b, Pointer(a)^, 5);
    VirtualProtect(Pointer(a), 5, old, old);
    FlushInstructionCache(GetCurrentProcess, Pointer(a), 5);
    WriterPatched := True;
    ULog(Format('TDRAW hook writer filtered at %.8x - TDRAW can no longer hook %.8x-%.8x',
                [a, RANGE_LO, RANGE_HI]));
  end
  else
    ULog('VirtualProtect failed on TDRAW writer - only the poll is active');
end;

// Put TDRAW's writer back (TPLAYX may be unloaded before TDRAW at exit).
procedure UnpatchTDrawWriter;
var
  old : DWORD;
begin
  if not WriterPatched then Exit;
  if VirtualProtect(Pointer(WriterAddr), 5, PAGE_EXECUTE_READWRITE, old) then
  begin
    Move(WRITER_HEAD, Pointer(WriterAddr)^, 5);
    VirtualProtect(Pointer(WriterAddr), 5, old, old);
    FlushInstructionCache(GetCurrentProcess, Pointer(WriterAddr), 5);
  end;
  WriterPatched := False;
end;

// -----------------------------------------------------------------------------
// v3: nil check in front of TDRAW's guard-order option lookup (same result as
// TDRAW's own patrol lookup gives for a missing object: 1 = default)
// -----------------------------------------------------------------------------

procedure GuardDispStub; assembler; nostackframe;
asm
  test ecx, ecx
  jz   @none
  push ebp                          // the 6 bytes we replaced
  mov  ebp, esp
  mov  eax, dword ptr [ebp + 8]
  jmp  dword ptr [GuardCont]
@none:
  mov  eax, 1
  ret  4
end;

procedure PatchTDrawGuard;
var
  h, a : Cardinal;
  i    : Integer;
  b    : array[0..5] of Byte;
  old  : DWORD;
  rel  : LongInt;
begin
  if GuardChecked then Exit;
  h := GetModuleHandle('TDRAW.dll');
  if h = 0 then Exit;
  GuardChecked := True;
  a := h + TDRAW_GUARD_RVA;
  for i := 0 to High(GUARD_HEAD) do
    if PByte(a + Cardinal(i))^ <> GUARD_HEAD[i] then
    begin
      ULog(Format('TDRAW guard lookup not recognised at %.8x - guard fix not applied', [a]));
      Exit;
    end;
  GuardAddr := a;
  GuardCont := a + 6;
  rel := LongInt(Cardinal(@GuardDispStub)) - LongInt(a + 5);
  b[0] := $E9;
  Move(rel, b[1], 4);
  b[5] := $90;
  if VirtualProtect(Pointer(a), 6, PAGE_EXECUTE_READWRITE, old) then
  begin
    Move(b, Pointer(a)^, 6);
    VirtualProtect(Pointer(a), 6, old, old);
    FlushInstructionCache(GetCurrentProcess, Pointer(a), 6);
    GuardPatched := True;
    ULog(Format('TDRAW guard-order crash fix applied at %.8x', [a]));
  end;
end;

procedure UnpatchTDrawGuard;
var
  old : DWORD;
begin
  if not GuardPatched then Exit;
  if VirtualProtect(Pointer(GuardAddr), 6, PAGE_EXECUTE_READWRITE, old) then
  begin
    Move(GUARD_HEAD, Pointer(GuardAddr)^, 6);
    VirtualProtect(Pointer(GuardAddr), 6, old, old);
    FlushInstructionCache(GetCurrentProcess, Pointer(GuardAddr), 6);
  end;
  GuardPatched := False;
end;

// A TDRAW built from the blitz-16p branch handles the 16-player layout itself
// and exports TDraw_16PlayerAware. Its hooks must then be left alone.
function TDrawIs16PAware : boolean;
var
  h : HMODULE;
begin
  h := GetModuleHandle('TDRAW.dll');
  result := (h <> 0) and (GetProcAddress(h, 'TDraw_16PlayerAware') <> nil);
end;

function UnhookThread(Parameter : Pointer) : PtrInt;
var
  waited : Cardinal;
begin
  result := 0;
  waited := 0;
  while (not StopFlag) and (waited < START_MS) do
  begin
    Sleep(100);
    Inc(waited, 100);
  end;
  try
    if StopFlag then Exit;
    if CountDiff > MAX_SANE_DIFF then
    begin
      ULog(Format('more than %d bytes differ from the exe file - wrong exe layout? plugin stopped.',
                  [MAX_SANE_DIFF]));
      Exit;
    end;
    while not StopFlag do
    begin
      if TDrawIs16PAware then
      begin
        ULog('16-player-aware TDRAW detected - leaving its hooks alone.');
        Exit;
      end;
      PatchTDrawWriter;               // no-op once done
      PatchTDrawGuard;                // no-op once done
      ScanOnce;
      waited := 0;
      while (not StopFlag) and (waited < CHECK_MS) do
      begin
        Sleep(100);
        Inc(waited, 100);
      end;
    end;
  except
    on e : Exception do ULog('thread stopped: ' + e.Message);
  end;
end;

// -----------------------------------------------------------------------------
// Plugin Lifecycle
// -----------------------------------------------------------------------------

Procedure OnInstall;
var
  tid : TThreadID;
  dir : string;
begin
  if LogReady then Exit;              // v2: OnInstall ran twice -> two threads
  dir      := ExtractFilePath(ParamStr(0));
  LogPath  := dir + 'tdrawunhook.log';
  InitCriticalSection(LogLock);
  LogReady := True;
  StopFlag := False;
  Unhooked := 0;
  SetLength(Kept, 0);

  ULog('');
  ULog('==================================================================');
  ULog('TDrawUnhook installed  ' + FormatDateTime('yyyy-mm-dd', Now));
  ULog('TA: ' + ParamStr(0));

  if FileExists(dir + 'tdrawunhook.off') then
  begin
    ULog('tdrawunhook.off found - doing nothing this run.');
    Exit;
  end;

  FindSelfRange;
  ULog(Format('TPLAYX at %.8x-%.8x   TDRAW.dll loaded: %s',
              [SelfLo, SelfHi,
               BoolToStr(GetModuleHandle('TDRAW.dll') <> 0, 'yes', 'no')]));

  if TDrawIs16PAware then
  begin
    ULog('16-player-aware TDRAW detected (TDraw_16PlayerAware) - TDrawUnhook not needed, doing nothing.');
    Exit;
  end;

  if not LoadOriginal then
  begin
    ULog('could not load original bytes - plugin stopped.');
    Exit;
  end;

  PatchTDrawWriter;                   // as early as possible
  PatchTDrawGuard;
  ThreadH := THandle(BeginThread(nil, 0, @UnhookThread, nil, 0, tid));
  if ThreadH = 0 then
    ULog('could not start thread - plugin stopped.')
  else
    ULog(Format('watching %.8x-%.8x every %d ms', [RANGE_LO, RANGE_HI, CHECK_MS]));
end;

Procedure OnUninstall;
begin
  StopFlag := True;
  if ThreadH <> 0 then
  begin
    WaitForSingleObject(ThreadH, 2000);
    CloseHandle(ThreadH);
    ThreadH := 0;
  end;
  UnpatchTDrawWriter;
  UnpatchTDrawGuard;
  if LogReady then
  begin
    ULog(Format('TDrawUnhook uninstalled. ranges restored: %d, TPLAYX hooks kept: %d, TDRAW writes blocked: %d',
                [Unhooked, Length(Kept), WritesBlocked]));
    LogReady := False;
    DoneCriticalSection(LogLock);
  end;
end;

function GetPlugin : TPluginData;
begin
  if not State_TDrawUnhook then
  begin
    result := nil;
    Exit;
  end;

  result := TPluginData.create( true,
                                'TDRAW Unhook (net/lobby code)',
                                State_TDrawUnhook,
                                @OnInstall, @OnUninstall );
end;

end.
