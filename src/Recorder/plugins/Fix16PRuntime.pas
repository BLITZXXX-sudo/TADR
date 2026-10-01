unit Fix16PRuntime;

{
  Fix16PRuntime - 16-player game fixes applied by TPLAYX at RUNTIME, so the
                  exe on disk stays the plain S7 build (24 Sep 2026).

  WHY AT RUNTIME
  --------------
  The same unit-count fix baked into the exe (S8) stopped the host's game
  from showing in the lobby list. Doing it from TPLAYX once loading has
  started keeps the lobby seeing an unchanged exe.

  WHAT IT FIXES
  -------------
  1. LOADING HANG "Waiting for other players"
     The load barrier (exe $4568C0, loop at $456B85) waits while any remote
     player's ready flag [TAMain+$3D900+slot*4] is 0. The 0x15 "ready"
     message for the host's last AI got lost twice in a row, although that
     player's load progress (+$20) was 100. Before the check runs we now set
     the ready flag of every remote player (type 3) that is at 100%.
       $456B85  lea eax,[edx+$3D900]  ->  call ReadyStub / nop

  2. FALSE "X has gone to a better place / shown the door" MESSAGES
     (v2: also no "destroyed" at all during the first 20 s of game time -
      at the start a player can briefly have 0 units on the other machine)

  3. UNITS STUCK AT THE TOP-LEFT (0,0) FOR ~50 s  (v3)
     Position packets (0x2C, $48B710) only carry units that are moving, so a
     commander whose start position was lost stays at 0,0 on the other
     machine until it first moves. For the first 20 s of game time every
     unit is included.
       $48B78E  call [edx+1C] / test eax,eax  ->  call PosStub
     Each player's unit counter (PlayerStruct+$144) gets credited to the
     wrong player on the remote machine (seen: -4, 0 while alive, 7 for 2).
     A counter reaching 0 = "player destroyed". When a unit dies we now
     recount the owner's live units (UnitInfoID <> 0) and use that.
       $486E03  mov eax,[esi+96]/cmp word [eax+144],bx/jne 486E59
            ->  call CountStub / jne 486E59 / nops

  WHEN
  ----
  A thread polls every 100 ms. As soon as TAMain exists and the "loading"
  bit ([TAMain+$38D75] and 4) is set, both patches are written once.
  Original bytes are checked first; anything unexpected is left alone and
  logged. S9's own ready fix (call $52EE80 at $456B85) is detected and left.

  TDrawUnhook: $456B85 is inside its watched range; our call goes into
  TPLAYX, so TDrawUnhook keeps it (OwnedBySelf).

  SWITCHES
  --------
  State_Fix16PRuntime = False and rebuild   -> plugin off.
  Or create an empty file  fix16p.off  in the game folder.

  OUTPUT: <TA folder>\fix16p.log
}

{$ASMMODE INTEL}

interface

uses
  PluginEngine;

Procedure OnInstall;
Procedure OnUninstall;

const
  State_Fix16PRuntime : boolean = true;

function GetPlugin : TPluginData;

implementation

uses
  Windows,
  SysUtils;

const
  TAMAIN_PTR      = $00511DE8;
  OFS_PLAYERS     = $3A000;
  PLAYER_SIZE     = $14B;
  OFS_READY       = $3D900;
  OFS_LOADFLAGS   = $38D75;
  UNIT_SIZE       = $118;
  OFS_GAMETIME    = $38A47;         // TAMain.lGameTime, 30 ticks per second
  DEATH_GRACE     = 30 * 20;        // no "player destroyed" in the first 20 s
  POS_GRACE       = 30 * 20;        // send every unit's position in the first 20 s
  SITE_POS        = $0048B78E;
  POS_OLD : array[0..4] of Byte = ($FF,$52,$1C,$85,$C0);
  DMG_GRACE       = 30 * 20;        // no damage in the first 20 s (v4)
  DMG_KILL        = 30000;          // kill orders / self-destruct / received deaths
  SITE_DMG        = $00489BB0;      // UNITS_MakeDamage (stdcall, 5 args)
  DMG_OLD : array[0..7] of Byte = ($83,$EC,$0C,$53,$8B,$5C,$24,$20);

  SITE_READY      = $00456B85;
  SITE_COUNT      = $00486E03;
  COUNT_JNE_TGT   = $00486E59;

  READY_OLD : array[0..5] of Byte = ($8D,$82,$00,$D9,$03,$00);
  COUNT_OLD : array[0..14] of Byte = ($8B,$86,$96,$00,$00,$00,
                                      $66,$39,$98,$44,$01,$00,$00,$75,$47);

var
  LogPath   : string = '';
  LogReady  : boolean = false;
  StopFlag  : boolean = false;
  ThreadH   : THandle = 0;
  Applied   : boolean = false;
  ReadyFixes: Integer = 0;
  CountFixes: Integer = 0;
  SkipDeath : Byte = 0;
  DeathsSuppressed : Integer = 0;
  DamageBlocked : Integer = 0;

procedure FLog(const s : string);
var
  f : TextFile;
begin
  if not LogReady then Exit;
  try
    AssignFile(f, LogPath);
    if FileExists(LogPath) then Append(f) else Rewrite(f);
    WriteLn(f, FormatDateTime('hh:nn:ss ', Now) + s);
    CloseFile(f);
  except
  end;
end;

// -----------------------------------------------------------------------------
// Fix 1: ready repair (called from the load barrier)
// -----------------------------------------------------------------------------

procedure ReadyRepair; stdcall;
var
  ta, p : Cardinal;
  i     : Integer;
  flag  : PCardinal;
begin
  ta := PCardinal(TAMAIN_PTR)^;
  if ta = 0 then Exit;
  for i := 0 to 15 do
  begin
    p := ta + OFS_PLAYERS + Cardinal(i) * PLAYER_SIZE;
    if (PCardinal(p)^ <> 0) and (PByte(p + $73)^ = 3) and (PByte(p + $20)^ = 100) then
    begin
      flag := PCardinal(ta + OFS_READY + Cardinal(i) * 4);
      if flag^ = 0 then
      begin
        flag^ := 1;
        Inc(ReadyFixes);
      end;
    end;
  end;
end;

procedure ReadyStub; assembler; nostackframe;
asm
  pushad
  call ReadyRepair
  popad
  lea  eax, [edx + $3D900]
end;

// -----------------------------------------------------------------------------
// Fix 2: recount the dying unit's owner
// -----------------------------------------------------------------------------

procedure RecountOwner(unitp : Cardinal); stdcall;
var
  owner, arr, n, i, live, ta : Cardinal;
  cnt : PWord;
begin
  SkipDeath := 0;
  owner := PCardinal(unitp + $96)^;
  if owner = 0 then Exit;
  arr := PCardinal(owner + $67)^;
  if arr = 0 then Exit;
  n := Cardinal(PWord(owner + $71)^) - Cardinal(PWord(owner + $6F)^) + 1;
  if (n = 0) or (n > 5000) then Exit;
  live := 0;
  for i := 0 to n - 1 do
    if PWord(arr + i * UNIT_SIZE + $A6)^ <> 0 then Inc(live);
  cnt := PWord(owner + $144);
  if cnt^ <> live then
  begin
    cnt^ := live;
    Inc(CountFixes);
  end;
  // At the very start of a game remote units are still being set up and a
  // player can briefly have 0 live units on this machine. Do not declare
  // anyone destroyed during the first DEATH_GRACE ticks.
  if live = 0 then
  begin
    ta := PCardinal(TAMAIN_PTR)^;
    if (ta <> 0) and (PInteger(ta + OFS_GAMETIME)^ < DEATH_GRACE) then
    begin
      SkipDeath := 1;
      Inc(DeathsSuppressed);
    end;
  end;
end;

procedure CountStub; assembler; nostackframe;
asm
  pushad
  push esi
  call RecountOwner
  popad
  mov  eax, [esi + $96]
  cmp  byte ptr [SkipDeath], 0      // 1 -> ZF=0 -> caller's jne skips the death
  jne  @done
  cmp  word ptr [eax + $144], 0
@done:
end;

// -----------------------------------------------------------------------------
// Fix 3: position sync at the start of the game
// The owner's position packet (0x2C, built in $48B710) only includes units
// whose movement object says "changed" (vfunc +$1C). A commander standing
// still is never sent, so a machine that missed its start position keeps it
// at 0,0 until it first moves (~50 s). During the first POS_GRACE ticks we
// include every unit, so the other machines get the real positions at once.
// -----------------------------------------------------------------------------

procedure PosStub; assembler; nostackframe;
asm
  call dword ptr [edx + $1C]        // original: movement->NeedsSync (ecx = obj)
  test eax, eax
  jnz  @yes
  mov  eax, dword ptr [$00511DE8]
  test eax, eax
  jz   @no
  cmp  dword ptr [eax + $38A47], POS_GRACE
  jge  @no
  mov  eax, 1
@yes:
  test eax, eax
  ret
@no:
  xor  eax, eax
end;

// -----------------------------------------------------------------------------
// Fix 4: no damage during the first DMG_GRACE ticks (v4)
// While remote units are still being placed they can sit at 0,0 on one
// machine and get shot there (seen: AI d-gunned a commander). Game time is
// the same on every machine, so all of them skip the same hits.
// Args: [esp+4] attacker, [esp+8] target, [esp+$C] amount, [esp+$10] type, [esp+$14] angle
// -----------------------------------------------------------------------------

procedure DmgStub; assembler; nostackframe;
asm
  mov  eax, dword ptr [$00511DE8]
  test eax, eax
  jz   @orig
  cmp  dword ptr [eax + $38A47], DMG_GRACE
  jge  @orig
  cmp  dword ptr [esp + $0C], DMG_KILL
  jge  @orig
  inc  dword ptr [DamageBlocked]
  ret  $14
@orig:
  sub  esp, $0C                     // original first 8 bytes
  push ebx
  mov  ebx, dword ptr [esp + $20]
  push $00489BB8
  ret
end;

// -----------------------------------------------------------------------------
// Patching
// -----------------------------------------------------------------------------

function SameBytes(a : Cardinal; const b : array of Byte) : boolean;
var
  i : Integer;
begin
  result := false;
  for i := 0 to High(b) do
    if PByte(a + Cardinal(i))^ <> b[i] then Exit;
  result := true;
end;

procedure WriteCode(a : Cardinal; const b : array of Byte);
var
  old : DWORD;
  i   : Integer;
begin
  if VirtualProtect(Pointer(a), Length(b), PAGE_EXECUTE_READWRITE, old) then
  begin
    for i := 0 to High(b) do
      PByte(a + Cardinal(i))^ := b[i];
    VirtualProtect(Pointer(a), Length(b), old, old);
    FlushInstructionCache(GetCurrentProcess, Pointer(a), Length(b));
  end;
end;

procedure PutRel(var b : array of Byte; idx : Integer; opcode : Byte; from, target : Cardinal);
var
  rel : LongInt;
begin
  rel := LongInt(target) - LongInt(from + 5);
  b[idx]     := opcode;
  b[idx + 1] := Byte(rel);
  b[idx + 2] := Byte(rel shr 8);
  b[idx + 3] := Byte(rel shr 16);
  b[idx + 4] := Byte(rel shr 24);
end;

function HexAt(a, len : Cardinal) : string;
var
  i : Cardinal;
begin
  result := '';
  for i := 0 to len - 1 do
    result := result + IntToHex(PByte(a + i)^, 2);
end;

procedure ApplyPatches;
var
  r : array[0..5] of Byte;
  c : array[0..14] of Byte;
  p : array[0..4] of Byte;
  d : array[0..7] of Byte;
  i : Integer;
begin
  // 1. ready repair
  if SameBytes(SITE_READY, READY_OLD) then
  begin
    PutRel(r, 0, $E8, SITE_READY, Cardinal(@ReadyStub));
    r[5] := $90;
    WriteCode(SITE_READY, r);
    FLog(Format('ready repair installed at %.8x -> %.8x', [SITE_READY, Cardinal(@ReadyStub)]));
  end
  else if (PByte(SITE_READY)^ = $E8) and
          (Cardinal(LongInt(SITE_READY + 5) + PLongInt(SITE_READY + 1)^) = $0052EE80) then
    FLog('ready repair: exe already has it (S9) - left alone')
  else
    FLog('ready repair NOT installed - unexpected bytes at 456B85: ' + HexAt(SITE_READY, 6));

  // 2. unit recount
  if SameBytes(SITE_COUNT, COUNT_OLD) then
  begin
    PutRel(c, 0, $E8, SITE_COUNT, Cardinal(@CountStub));
    c[5] := $75;                                        // jne rel8
    c[6] := Byte(COUNT_JNE_TGT - (SITE_COUNT + 7));
    for i := 7 to 14 do c[i] := $90;
    WriteCode(SITE_COUNT, c);
    FLog(Format('unit recount installed at %.8x -> %.8x', [SITE_COUNT, Cardinal(@CountStub)]));
  end
  else
    FLog('unit recount NOT installed - unexpected bytes at 486E03: ' + HexAt(SITE_COUNT, 15));

  // 3. start-of-game position sync
  if SameBytes(SITE_POS, POS_OLD) then
  begin
    PutRel(p, 0, $E8, SITE_POS, Cardinal(@PosStub));
    WriteCode(SITE_POS, p);
    FLog(Format('start position sync installed at %.8x -> %.8x (first %d s)',
                [SITE_POS, Cardinal(@PosStub), POS_GRACE div 30]));
  end
  else
    FLog('start position sync NOT installed - unexpected bytes at 48B78E: ' + HexAt(SITE_POS, 5));

  // 4. no damage at the start
  if SameBytes(SITE_DMG, DMG_OLD) then
  begin
    PutRel(d, 0, $E9, SITE_DMG, Cardinal(@DmgStub));
    d[5] := $90; d[6] := $90; d[7] := $90;
    WriteCode(SITE_DMG, d);
    FLog(Format('start-of-game damage block installed at %.8x -> %.8x (first %d s)',
                [SITE_DMG, Cardinal(@DmgStub), DMG_GRACE div 30]));
  end
  else
    FLog('damage block NOT installed - unexpected bytes at 489BB0: ' + HexAt(SITE_DMG, 8));
end;

function WatchThread(Parameter : Pointer) : PtrInt;
var
  ta : Cardinal;
  lastR, lastC, lastD, lastB : Integer;
begin
  result := 0;
  lastR := 0; lastC := 0; lastD := 0; lastB := 0;
  try
    while not StopFlag do
    begin
      if not Applied then
      begin
        ta := PCardinal(TAMAIN_PTR)^;
        if (ta <> 0) and ((PByte(ta + OFS_LOADFLAGS)^ and 4) <> 0) then
        begin
          FLog('loading detected');
          ApplyPatches;
          Applied := True;
        end;
      end
      else if (ReadyFixes <> lastR) or (CountFixes <> lastC) or (DeathsSuppressed <> lastD) or (DamageBlocked <> lastB) then
      begin
        FLog(Format('ready flags repaired: %d   unit counts corrected: %d   start-of-game "destroyed" suppressed: %d   hits blocked: %d',
                    [ReadyFixes, CountFixes, DeathsSuppressed, DamageBlocked]));
        lastR := ReadyFixes; lastC := CountFixes; lastD := DeathsSuppressed; lastB := DamageBlocked;
      end;
      Sleep(100);
    end;
  except
    on e : Exception do FLog('thread stopped: ' + e.Message);
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
  dir      := ExtractFilePath(ParamStr(0));
  LogPath  := dir + 'fix16p.log';
  LogReady := True;
  StopFlag := False;
  Applied  := False;
  FLog('');
  FLog('================ Fix16PRuntime installed ' + FormatDateTime('yyyy-mm-dd', Now));
  FLog('TA: ' + ParamStr(0));
  if FileExists(dir + 'fix16p.off') then
  begin
    FLog('fix16p.off found - doing nothing this run.');
    Exit;
  end;
  ThreadH := THandle(BeginThread(nil, 0, @WatchThread, nil, 0, tid));
  if ThreadH = 0 then FLog('could not start thread');
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
  FLog(Format('uninstalled. ready flags repaired: %d, unit counts corrected: %d',
              [ReadyFixes, CountFixes]));
  LogReady := False;
end;

function GetPlugin : TPluginData;
begin
  if not State_Fix16PRuntime then
  begin
    result := nil;
    Exit;
  end;
  result := TPluginData.create( true,
                                '16P runtime fixes (ready, unit count, start pos, start damage)',
                                State_Fix16PRuntime,
                                @OnInstall, @OnUninstall );
end;

end.
