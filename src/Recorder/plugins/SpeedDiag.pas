unit SpeedDiag;

{
  SpeedDiag - logs the game-speed / tick-clock state so we can see, from
  inside the DLL, whether two machines are actually running the same speed.
  ... [Original Comments Preserved] ...
}

interface

uses
  Windows, SysUtils,
  TA_MemoryLocations, TA_MemoryStructures, TA_MemoryConstants;

type
  // Define the plugin callback signature
  TSpeedDiagPlugin = procedure(M: PTADynMemStruct);

// Call once per frame (or per tick). Cheap: only writes on change or on
// the periodic heartbeat.
procedure SpeedDiag_Poll;

// Force a line out now, with a caller-supplied tag (e.g. 'GAMESTART').
procedure SpeedDiag_Mark(const Tag: string);

// Register a custom external diagnostic plugin
procedure SpeedDiag_RegisterPlugin(Plugin: TSpeedDiagPlugin);

implementation

const
  LOGNAME        = 'speeddiag.log';
  HEARTBEAT_MS   = 3000;   // periodic line even when nothing changes
  EARLY_UNTIL    = 200;    // dump every tick while lGameTime < this
  EARLY_MAX      = 250;    // hard cap on early lines, so the log stays sane

var
  gInited        : Boolean = False;
  gLastSpeed     : Integer = -1;
  gLastInit      : Integer = -1;
  gLastPaused    : Integer = -1;
  gLastBeatMS    : Cardinal = 0;
  gLastBeatTime  : Integer = 0;   // lGameTime at last heartbeat
  gStartMS       : Cardinal = 0;
  gSeqCount      : Integer = 0;   // nth speed transition this run
  gLastChangeMS  : Cardinal = 0;  // for inter-change timing
  gLastSynch     : Integer = -1;  // nPlayersSynchMask, to catch barrier release
  gBarrierLogged : Boolean = False;
  gEarlyLines    : Integer = 0;   // high-res logging budget for the first ticks
  gLastEarlyTime : Integer = -1;

  // Plugin System Storage
  gPlugins       : array of TSpeedDiagPlugin;

procedure SpeedDiag_RegisterPlugin(Plugin: TSpeedDiagPlugin);
var
  Len: Integer;
begin
  if not Assigned(Plugin) then Exit;

  Len := Length(gPlugins);
  SetLength(gPlugins, Len + 1);
  gPlugins[Len] := Plugin;
end;

procedure WriteLine(const S: string);
var
  F: TextFile;
begin
  try
    AssignFile(F, LOGNAME);
    if FileExists(LOGNAME) then
      Append(F)
    else
      Rewrite(F);
    try
      WriteLn(F, S);
    finally
      CloseFile(F);
    end;
  except
    // never let diagnostics take the game down
  end;
end;

function SafeMain: PTADynMemStruct;
begin
  // TAData is a global INSTANCE of TAMem, constructed in
  // TA_MemoryLocations' initialization section. Unit init order is not
  // guaranteed relative to ours, and FPC dereferences the instance to find
  // the VMT, so a nil TAData would fault on every call - check it first.
  Result := nil;
  if TAData = nil then
    Exit;
  try
    Result := TAData.MainStruct;
    // TADynmemStructPtr is null until the game allocates its main struct,
    // which is well after DLL load. Nil here just means "not in a game yet".
  except
    Result := nil;
  end;
end;

procedure Emit(const Tag: string; M: PTADynMemStruct);
var
  nowMS   : Cardinal;
  dMS     : Cardinal;
  dTicks  : Integer;
  rate    : Double;
  rateStr : string;
  speed   : Integer;
  spInit  : Integer;
  paused  : Integer;
  gtime   : Integer;
begin
  if M = nil then
    Exit;

  speed  := M^.nTAGameSpeed;
  spInit := M^.nTAGameSpeed_Init;
  paused := M^.cIsGamePaused;
  gtime  := M^.lGameTime;

  nowMS := GetTickCount;
  dMS   := nowMS - gLastBeatMS;
  dTicks := gtime - gLastBeatTime;

  if (gLastBeatMS <> 0) and (dMS > 0) then
  begin
    rate := (dTicks * 1000.0) / dMS;
    rateStr := Format('%.2f', [rate]);
  end
  else
    rateStr := 'n/a';

  WriteLine(Format(
    '%s [%s] Speed=%d Init=%d Paused=%d(bit0=%d) GameTime=%d Tick/s=%s',
    [FormatDateTime('hh:nn:ss.zzz', Now),
     Tag, speed, spInit, paused, paused and 1, gtime, rateStr]));

  // Loud about the illegal value - this is the bug signature.
  if speed = 0 then
    WriteLine('    *** Speed=0 is ILLEGAL (ChangeGameSpeed clamps to 1..20). '
            + 'Unclamped options-screen write at 0x0045EBE4, or '
            + 'InitBasicGameData skipped its type-3 seed. ***');

  if speed <> spInit then
    WriteLine(Format('    note: nTAGameSpeed(%d) <> nTAGameSpeed_Init(%d) '
            + '- hysteresis has drifted them apart.', [speed, spInit]));

  gLastBeatMS   := nowMS;
  gLastBeatTime := gtime;
end;

procedure EmitEarly(M: PTADynMemStruct);
var
  i    : Integer;
  ctrl : Byte;
begin
  if M = nil then Exit;
  // Only start once the barrier has released, otherwise the whole line budget
  // is spent on lobby traffic while lGameTime sits at 0.
  if not gBarrierLogged then Exit;
  if M^.lGameTime >= EARLY_UNTIL then Exit;
  if gEarlyLines >= EARLY_MAX then Exit;

  gLastEarlyTime := M^.lGameTime;
  Inc(gEarlyLines);

  WriteLine(Format('%s [EARLY] GameTime=%-4d budget=%-3d Speed=%d/%d hyst=%-4d paused=%d',
    [FormatDateTime('hh:nn:ss.zzz', Now),
     M^.lGameTime,
     M^.field_38A3B,
     M^.nTAGameSpeed, M^.nTAGameSpeed_Init,
     M^.field_38A4F,
     M^.cIsGamePaused]));

  for i := 0 to 15 do
  begin
    ctrl := Byte(M^.PlayersExt[i].cPlayerController);
    if (M^.PlayersExt[i].lPlayerActive = 0) and (ctrl = 0) then
      Continue;                                 // skip never-used slots
    WriteLine(Format('        slot%-2d act=%d ctrl=%-3d ack(+18)=%-6d load(+20)=%-3d ping=%d',
      [i,
       Ord(M^.PlayersExt[i].lPlayerActive <> 0),
       ctrl,
       M^.PlayersExt[i].field_18,
       M^.PlayersExt[i].cMultiLoadProgress,
       M^.PlayersExt[i].nPing]));
  end;
end;

procedure SpeedDiag_Mark(const Tag: string);
var
  M: PTADynMemStruct;
begin
  M := SafeMain;
  if M = nil then Exit;
  Emit(Tag, M);
end;

procedure SpeedDiag_Poll;
var
  M      : PTADynMemStruct;
  speed  : Integer;
  spInit : Integer;
  paused : Integer;
  nowMS  : Cardinal;
  changed: Boolean;
  i      : Integer;
begin
  M := SafeMain;
  if M = nil then
    Exit;

  // --- EXECUTE PLUGINS ---
  for i := 0 to High(gPlugins) do
  begin
    try
      gPlugins[i](M);
    except
      // Trap plugin errors so they do not interrupt core diagnostics
    end;
  end;

  if not gInited then
  begin
    gInited  := True;
    gStartMS := GetTickCount;
    try
      if FileExists(LOGNAME) then
        DeleteFile(LOGNAME);
    except
    end;
    WriteLine('=== SpeedDiag start ' + DateTimeToStr(Now) + ' ===');
    WriteLine('=== compare Speed= and Tick/s between HOST and CLIENT ===');
    WriteLine('=== 10 = Normal. 0 = illegal (unclamped write). ===');
    gLastBeatMS   := GetTickCount;
    gLastChangeMS := gLastBeatMS;
    gLastBeatTime := M^.lGameTime;
    Emit('INIT', M);
    Exit;
  end;

  speed  := M^.nTAGameSpeed;
  spInit := M^.nTAGameSpeed_Init;
  paused := M^.cIsGamePaused;

  if M^.nPlayersSynchMask <> gLastSynch then
  begin
    WriteLine(Format('%s [SYNCMASK] 0x%.4x -> 0x%.4x  bit3=%d  GameTime=%d',
      [FormatDateTime('hh:nn:ss.zzz', Now),
       gLastSynch and $FFFF, M^.nPlayersSynchMask,
       (M^.nPlayersSynchMask shr 3) and 1, M^.lGameTime]));
    gLastSynch := M^.nPlayersSynchMask;
  end;

  if (not gBarrierLogged) and (((M^.nPlayersSynchMask shr 3) and 1) <> 0) then
  begin
    gBarrierLogged := True;
    WriteLine('');
    WriteLine('*** BARRIER RELEASED - "Synchronization complete" ***');
    WriteLine(Format('    %s  lGameTime=%d  Speed=%d/%d  MaxPlayers=%d',
      [FormatDateTime('hh:nn:ss.zzz', Now), M^.lGameTime,
       M^.nTAGameSpeed, M^.nTAGameSpeed_Init, M^.lMaxPlayers]));
    WriteLine('    >>> COMPARE lGameTime ACROSS MACHINES. Equal = barrier');
    WriteLine('    >>> held. Different = the clocks start apart and stay');
    WriteLine('    >>> apart (offset < 900 is never corrected).');
    WriteLine('');
  end;

  EmitEarly(M);

  changed := (speed  <> gLastSpeed)
          or (spInit <> gLastInit)
          or (paused <> gLastPaused);

  nowMS := GetTickCount;

  if changed then
  begin
    if speed <> gLastSpeed then
    begin
      Inc(gSeqCount);
      WriteLine(Format('%s [SEQ %d] %d -> %d  (dt=%dms, GameTime=%d)',
        [FormatDateTime('hh:nn:ss.zzz', Now),
         gSeqCount, gLastSpeed, speed,
         nowMS - gLastChangeMS, M^.lGameTime]));
      gLastChangeMS := nowMS;
    end;

    Emit('CHANGE', M);
    gLastSpeed  := speed;
    gLastInit   := spInit;
    gLastPaused := paused;
  end
  else if (nowMS - gLastBeatMS) >= HEARTBEAT_MS then
    Emit('BEAT', M);
end;

end.
