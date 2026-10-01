{$MODE DELPHI}
unit CloakOnly;

// =============================================================================
// CloakOnly - ARMRAD area-cloak plugin
//
// AUDIT 28 Sep 2026
//  * NETWORK SILENT: the plugin runs the same cloak calculation for EVERY unit
//    on EVERY machine, so the network broadcast of cloak state (Rec2Rec
//    ExtraUnitState, FieldType 2) was redundant and fought the local result.
//    It is now compiled out (CLOAK_NET_SEND = False) and incoming cloak
//    packets are ignored by idplay (CLOAK_NET_RECV = False).
//    TAUnit.SetCloak only flips a bit in the local unit struct - it sends
//    nothing by itself.
//  * LOGGING: tplayx_cloak.log, the on-screen [Cloak+]/[Cloak-] lines, the
//    "Active" banner and the 5-second [Ping] chat readout only exist in a
//    build with -dTPLAYX_DEBUG. Hotkey replies (radius +/-, info) stay: the
//    user asked for them.
//  * THREAD SAFETY: WriteLog is called from this plugin's thread AND from
//    TDPlay.Receive. All access to the shared TextFile now goes through a
//    critical section (two threads writing one TextFile buffer = heap damage).
//  * OpenLog checks IOResult and never marks a failed open as open.
// =============================================================================

interface

uses
  Windows, PluginEngine, SysUtils, Math,
  TA_MemoryStructures, TA_MemUnits,
  TA_MemoryLocations, TA_MemoryConstants, TA_FunctionsU,
  UnitInfoExpand, idplay;

function  GetPlugin: TPluginData;
procedure OnInstallCloak;
procedure OnUninstallCloak;
procedure CloakOnly_RadiusDecrease;
procedure CloakOnly_RadiusIncrease;
procedure CloakOnly_PrintInfo;
procedure CloakOnly_CycleDebugMode;
procedure WriteLog(const Msg: string); // idplay also logs into tplayx_cloak.log (debug builds only)

const
  DEFAULT_CLOAK_RADIUS = 500;
  MAX_ARMRAD_UNITS     = 16;
  DAMAGE_DECLOAK_TICKS = 60;
  UNIT_STRUCT_STRIDE   = $118;

  // Network switches - forced OFF (see header). Every machine computes the
  // same cloak state locally, so nothing needs to go over the wire.
  CLOAK_NET_SEND = False;   // never call Broadcast_ExtraUnitState(.., 2, ..)
  CLOAK_NET_RECV = False;   // idplay ignores incoming FieldType 2 packets

var
  CloakFieldRadius : Integer = DEFAULT_CLOAK_RADIUS;
  DebugMode        : Integer = 0;   // on-screen [Cloak+/-] lines, debug builds only

implementation

uses
  IniOptions;

var
  // ',armrad,corrad,' - lower case, from CLOAKER= in the ini (default ARMRAD)
  CloakerList       : AnsiString = ',armrad,';
  CloakThreadHandle : THandle  = 0;
  ExitThreadSignal  : Boolean  = False;
  WasPlaying        : Boolean  = False;
  {$IFDEF TPLAYX_DEBUG}
  Timer5Sec         : Integer  = 0; // 5-second [Ping] readout pacing
  {$ENDIF}
  ArmradDamageTimer : array[0..MAX_ARMRAD_UNITS-1] of Integer;
  ArmradLastHealth  : array[0..MAX_ARMRAD_UNITS-1] of Word;
  PrevArmrads       : array[0..MAX_ARMRAD_UNITS-1] of PUnitStruct;
  PrevSuppressed    : array[0..MAX_ARMRAD_UNITS-1] of Boolean;
  PrevArmradCount   : Integer = 0;

  // Cloak transition counters (were "broadcast" counters - nothing is sent now)
  SessionTransitions : Integer = 0;
  TotalTransitions   : Integer = 0;
  CloakOnCount       : Integer = 0;
  CloakOffCount      : Integer = 0;
  EnemyEventCount    : Integer = 0;

  // Log file - only touched while holding LogLock
  LogLock      : TRTLCriticalSection;
  CloakLog     : TextFile;
  CloakLogOpen : Boolean = False;

// ---------------------------------------------------------------------------
// Logging (compiled to no-ops unless TPLAYX_DEBUG is defined)
// ---------------------------------------------------------------------------

procedure OpenLog;
{$IFDEF TPLAYX_DEBUG}
var
  Path: string;
{$ENDIF}
begin
  {$IFDEF TPLAYX_DEBUG}
  EnterCriticalSection(LogLock);
  try
    if CloakLogOpen then Exit;                  // already open - no second handle
    Path := ExtractFilePath(ParamStr(0)) + 'tplayx_cloak.log';
    AssignFile(CloakLog, Path);
    {$I-}
    if FileExists(Path) then Append(CloakLog) else Rewrite(CloakLog);
    {$I+}
    if IOResult <> 0 then Exit;                 // failed open is NOT marked open
    CloakLogOpen := True;
    Writeln(CloakLog, '');
    Writeln(CloakLog, '=== CloakOnly Session ' +
      FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' ===');
    Writeln(CloakLog, 'Radius=' + IntToStr(CloakFieldRadius) + '  TA=' + ParamStr(0));
    Flush(CloakLog);
  finally
    LeaveCriticalSection(LogLock);
  end;
  {$ENDIF}
end;

procedure CloseLog;
begin
  {$IFDEF TPLAYX_DEBUG}
  EnterCriticalSection(LogLock);
  try
    if not CloakLogOpen then Exit;
    try
      Writeln(CloakLog, Format('--- Session end | Transitions=%d ON=%d OFF=%d Enemy=%d ---',
        [SessionTransitions, CloakOnCount, CloakOffCount, EnemyEventCount]));
      CloseFile(CloakLog);
    except end;
    CloakLogOpen := False;
  finally
    LeaveCriticalSection(LogLock);
  end;
  {$ENDIF}
end;

procedure WriteLog(const Msg: string);
begin
  {$IFDEF TPLAYX_DEBUG}
  EnterCriticalSection(LogLock);
  try
    if not CloakLogOpen then Exit;
    try
      Writeln(CloakLog, FormatDateTime('hh:nn:ss.zzz', Now) + '  ' + Msg);
      Flush(CloakLog);
    except end;
  finally
    LeaveCriticalSection(LogLock);
  end;
  {$ENDIF}
end;

// On-screen debug line - debug builds + DebugMode=1 only
procedure DebugChat(const Msg: string);
begin
  {$IFDEF TPLAYX_DEBUG}
  if DebugMode = 1 then
    SendTextLocal(Msg);
  {$ENDIF}
end;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function IsGamePlaying: Boolean;
begin
  Result := False;
  if PCardinal(TAdynmemStructPtr)^ = 0 then Exit;
  if TAData.GUICallbackState <> gsPlaying then Exit;
  Result := TAData.GameingType in [gtSkirmish, gtMultiplayer];
end;

function IsUnitAlive(pUnit: PUnitStruct): Boolean;
begin
  Result := (pUnit <> nil)
    and (DWORD(pUnit) > $10000)
    and (DWORD(pUnit) < $70000000)
    and (pUnit^.lUnitInGameIndex <> 0)
    and (pUnit^.nHealth > 0)
    and (pUnit^.fBuildTimeLeft <= 0.0);
end;

function IsWithinDistance(pA, pB: PUnitStruct; MaxDist: Integer): Boolean;
var dx, dz, m: Int64;
begin
  dx := pA^.Position.X - pB^.Position.X;
  dz := pA^.Position.Z - pB^.Position.Z;
  m  := Int64(MaxDist) * 65536;
  Result := (dx*dx + dz*dz) <= (m * m);
end;

{$IFDEF TPLAYX_DEBUG}
function GetUnitName(pUnit: PUnitStruct): AnsiString;
var Info: PUnitInfo;
begin
  Result := '?';
  if (pUnit = nil) or (pUnit^.nUnitInfoID = 0) then Exit;
  Info := TAMem.UnitInfoId2Ptr(pUnit^.nUnitInfoID);
  if (Info <> nil) and (DWORD(Info) > $10000) then
    Result := AnsiString(Info^.szUnitName);
end;
{$ENDIF}

// Network send of a cloak transition. Compiled out: CLOAK_NET_SEND = False.
// Kept as one function so the silent state is enforced in exactly one place.
procedure NetSendCloakState(UnitId: Word; Value: Integer);
begin
  if not CLOAK_NET_SEND then Exit;              // forced silent - no packet
  if TAData.NetworkLayerEnabled and Assigned(GlobalDPlay) then
   // GlobalDPlay.Broadcast_ExtraUnitState(UnitId, 2, Value);
end;

// ---------------------------------------------------------------------------
// Cloak state changes (tracked in UnitsCustomFields[].CloakFieldArmrad)
// ---------------------------------------------------------------------------

procedure SetCloakOn(pUnit: PUnitStruct; pArmrad: PUnitStruct);
var
  UnitId : Word;
  InRange: Boolean;
begin
  UnitId  := TAUnit.GetId(pUnit);
  InRange := UnitId < Cardinal(Length(UnitsCustomFields));

  // Already cloaked by us - just keep tracking which ARMRAD covers it
  if InRange and (UnitsCustomFields[UnitId].CloakFieldArmrad <> nil) then
  begin
    UnitsCustomFields[UnitId].CloakFieldArmrad := pArmrad;
    Exit;
  end;

  // Native cloak (COB-driven): don't take ownership, leave it alone
  if TAUnit.GetCloak(pUnit) <> 0 then Exit;

  // Uncloaked and not tracked - cloak it locally and take ownership
  TAUnit.SetCloak(pUnit, 1);
  if InRange then
    UnitsCustomFields[UnitId].CloakFieldArmrad := pArmrad;

  NetSendCloakState(UnitId, 1);                 // no-op (silent)
  Inc(TotalTransitions); Inc(SessionTransitions); Inc(CloakOnCount);

  {$IFDEF TPLAYX_DEBUG}
  DebugChat('[Cloak+] ' + string(GetUnitName(pUnit)) +
    ' P' + IntToStr(TAUnit.GetOwnerIndex(pUnit)) +
    ' (ARMRAD owner P' + IntToStr(TAUnit.GetOwnerIndex(pArmrad)) + ') entered the cloak');
  WriteLog(Format('CLOAK_ON   UnitID=%-4d  Unit=%-12s  P=%d  ArmradP=%d  Transitions=%d',
    [UnitId, string(GetUnitName(pUnit)), TAUnit.GetOwnerIndex(pUnit),
     TAUnit.GetOwnerIndex(pArmrad), TotalTransitions]));
  {$ENDIF}
end;

procedure SetCloakOff(pUnit: PUnitStruct; const Reason: string);
var
  UnitId : Word;
begin
  UnitId := TAUnit.GetId(pUnit);
  if UnitId >= Cardinal(Length(UnitsCustomFields)) then Exit;
  if UnitsCustomFields[UnitId].CloakFieldArmrad = nil then Exit; // not ours

  UnitsCustomFields[UnitId].CloakFieldArmrad := nil;
  if TAUnit.GetCloak(pUnit) = 0 then Exit;      // already uncloaked

  TAUnit.SetCloak(pUnit, 0);
  NetSendCloakState(UnitId, 0);                 // no-op (silent)
  Inc(TotalTransitions); Inc(SessionTransitions); Inc(CloakOffCount);

  {$IFDEF TPLAYX_DEBUG}
  DebugChat('[Cloak-] ' + string(GetUnitName(pUnit)) + ' - ' + Reason);
  WriteLog(Format('CLOAK_OFF  UnitID=%-4d  Unit=%-12s  P=%d  Reason=%-14s  Transitions=%d',
    [UnitId, string(GetUnitName(pUnit)), TAUnit.GetOwnerIndex(pUnit), Reason, TotalTransitions]));
  {$ENDIF}
end;

// ---------------------------------------------------------------------------
// Ally detection using PlayerStruct.Units / UnitsAry_End bounds
// ---------------------------------------------------------------------------

procedure GetPlayerBounds(pUnit: PUnitStruct;
  out pBase: PUnitStruct; out pEnd: PUnitStruct);
var
  PI: Integer;
  pb, pe: PUnitStruct;
begin
  pBase := nil; pEnd := nil;
  for PI := 0 to MAXPLAYERCOUNT - 1 do
  begin
    pb := PUnitStruct(TAData.MainStruct.PlayersExt[PI].p_UnitsArray);
    pe := PUnitStruct(TAData.MainStruct.PlayersExt[PI].p_LastUnit);
    if (pb = nil) or (pe = nil) or (Cardinal(pb) >= Cardinal(pe)) then Continue;
    if (Cardinal(pUnit) >= Cardinal(pb)) and (Cardinal(pUnit) < Cardinal(pe)) then
    begin
      pBase := pb; pEnd := pe; Exit;
    end;
  end;
end;

function IsSamePlayerArray(pUnit: PUnitStruct;
  ArmradBase, ArmradEnd: PUnitStruct): Boolean;
begin
  Result := (ArmradBase <> nil) and (ArmradEnd <> nil) and
            (Cardinal(pUnit) >= Cardinal(ArmradBase)) and
            (Cardinal(pUnit) < Cardinal(ArmradEnd));
end;

procedure ApplyArmradCloak;
var
  pBase, pEnd    : PUnitStruct;
  pUnit, pArmrad : PUnitStruct;
  UnitInfo       : PUnitInfo;
  UnitName       : AnsiString;
  Armrads        : array[0..MAX_ARMRAD_UNITS-1] of PUnitStruct;
  ArmradUnitId   : array[0..MAX_ARMRAD_UNITS-1] of Word;
  ArmradBase     : array[0..MAX_ARMRAD_UNITS-1] of PUnitStruct;
  ArmradEnd      : array[0..MAX_ARMRAD_UNITS-1] of PUnitStruct;
  Suppressed     : array[0..MAX_ARMRAD_UNITS-1] of Boolean;
  Count, J, PJ   : Integer;
  Health         : Word;
  CoveringArmrad : PUnitStruct;
  PrevWasSuppr   : Boolean;
begin
  pBase := TAData.UnitsArray_p;
  pEnd  := TAData.EndOfUnitsArray_p;
  if (pBase = nil) or (pEnd = nil) or (Cardinal(pBase) >= Cardinal(pEnd)) then Exit;

  // ---- Pass 1: find ARMRADs, check damage ----
  Count := 0;
  pUnit := pBase;
  while Cardinal(pUnit) < Cardinal(pEnd) do
  begin
    if IsUnitAlive(pUnit) then
    begin
      UnitInfo := nil;
      if pUnit^.nUnitInfoID <> 0 then
        UnitInfo := TAMem.UnitInfoId2Ptr(pUnit^.nUnitInfoID);
      if (UnitInfo <> nil) and (DWORD(UnitInfo) > $10000) then
      begin
        UnitName := AnsiLowerCase(AnsiString(UnitInfo^.szUnitName));
        if (Pos(',' + UnitName + ',', CloakerList) > 0) and (Count < MAX_ARMRAD_UNITS) then
        begin
          Armrads[Count]      := pUnit;
          ArmradUnitId[Count] := TAUnit.GetId(pUnit);
          GetPlayerBounds(pUnit, ArmradBase[Count], ArmradEnd[Count]);
          Suppressed[Count]   := False;

          Health := pUnit^.nHealth;
          if (ArmradLastHealth[Count] > 0) and (Health < ArmradLastHealth[Count]) then
            ArmradDamageTimer[Count] := DAMAGE_DECLOAK_TICKS;
          ArmradLastHealth[Count] := Health;
          if ArmradDamageTimer[Count] > 0 then
          begin
            Dec(ArmradDamageTimer[Count]);
            Suppressed[Count] := True;
          end;
          Inc(Count);
        end;
      end;
    end;
    pUnit := PUnitStruct(Cardinal(pUnit) + UNIT_STRUCT_STRIDE);
  end;

  if Count = 0 then
  begin
    pUnit := pBase;
    while Cardinal(pUnit) < Cardinal(pEnd) do
    begin
      if IsUnitAlive(pUnit) then SetCloakOff(pUnit, 'ArmradDied');
      pUnit := PUnitStruct(Cardinal(pUnit) + UNIT_STRUCT_STRIDE);
    end;
    PrevArmradCount := 0;
    Exit;
  end;

  // ---- Pass 2: enemy-in-radius suppression ----
  // (Prev* arrays still hold LAST tick's ARMRADs here - PrevArmradCount is
  //  only updated after this pass; it used to be overwritten first, which
  //  made the "was already suppressed" lookup compare against the wrong count.)
  pUnit := pBase;
  while Cardinal(pUnit) < Cardinal(pEnd) do
  begin
    if IsUnitAlive(pUnit) then
      for J := 0 to Count - 1 do
      begin
        if Suppressed[J] then Continue;
        if pUnit = Armrads[J] then Continue;
        if IsSamePlayerArray(pUnit, ArmradBase[J], ArmradEnd[J]) then Continue;
        if TAUnit.IsAllied(pUnit, ArmradUnitId[J]) <> 0 then Continue;
        if IsWithinDistance(pUnit, Armrads[J], CloakFieldRadius) then
        begin
          PrevWasSuppr := False;
          for PJ := 0 to PrevArmradCount - 1 do
            if PrevArmrads[PJ] = Armrads[J] then
            begin PrevWasSuppr := PrevSuppressed[PJ]; Break; end;
          if not PrevWasSuppr then
          begin
            Inc(EnemyEventCount);
            {$IFDEF TPLAYX_DEBUG}
            UnitInfo := nil;
            if pUnit^.nUnitInfoID <> 0 then
              UnitInfo := TAMem.UnitInfoId2Ptr(pUnit^.nUnitInfoID);
            if (UnitInfo <> nil) and (DWORD(UnitInfo) > $10000) then
            begin
              DebugChat('[CloakOFF] Enemy ' + string(AnsiString(UnitInfo^.szUnitName)) +
                ' in range - ARMRAD decloaking');
              WriteLog(Format('ENEMY_IN   UnitID=%-4d  Unit=%-12s  PlayerID=%d  ARMRAD[%d] suppressed',
                [TAUnit.GetId(pUnit), string(AnsiString(UnitInfo^.szUnitName)),
                 TAUnit.GetOwnerIndex(pUnit), J]));
            end;
            {$ENDIF}
          end;
          Suppressed[J] := True;
        end;
      end;
    pUnit := PUnitStruct(Cardinal(pUnit) + UNIT_STRUCT_STRIDE);
  end;

  for J := 0 to Count - 1 do
  begin
    PrevArmrads[J]    := Armrads[J];
    PrevSuppressed[J] := Suppressed[J];
  end;
  for J := Count to MAX_ARMRAD_UNITS - 1 do
  begin
    PrevArmrads[J]    := nil;
    PrevSuppressed[J] := False;
  end;
  PrevArmradCount := Count;

  // ---- Pass 3: apply cloak (local only) ----
  pUnit := pBase;
  while Cardinal(pUnit) < Cardinal(pEnd) do
  begin
    if IsUnitAlive(pUnit) then
    begin
      CoveringArmrad := nil;
      for J := 0 to Count - 1 do
      begin
        if Suppressed[J] then Continue;
        pArmrad := Armrads[J];
        if pUnit = pArmrad then
        begin CoveringArmrad := pArmrad; Break; end;
        if IsSamePlayerArray(pUnit, ArmradBase[J], ArmradEnd[J]) and
           IsWithinDistance(pUnit, pArmrad, CloakFieldRadius) then
        begin CoveringArmrad := pArmrad; Break; end;
      end;

      if CoveringArmrad <> nil then
        SetCloakOn(pUnit, CoveringArmrad)
      else
      begin
        for J := 0 to Count - 1 do
          if Suppressed[J] and IsSamePlayerArray(pUnit, ArmradBase[J], ArmradEnd[J]) then
          begin
            CoveringArmrad := Armrads[J];
            Break;
          end;
        if CoveringArmrad <> nil then
          SetCloakOff(pUnit, 'EnemyNearby')
        else
          SetCloakOff(pUnit, 'LeaveRange');
      end;
    end;
    pUnit := PUnitStruct(Cardinal(pUnit) + UNIT_STRUCT_STRIDE);
  end;
end;

// ---------------------------------------------------------------------------
// Hotkeys (user-requested replies stay in release builds)
// ---------------------------------------------------------------------------

procedure CloakOnly_RadiusDecrease;
begin
  CloakFieldRadius := CloakFieldRadius - 50;
  if CloakFieldRadius < 50 then CloakFieldRadius := 50;
  if IsGamePlaying then
    SendTextLocal('[CloakOnly] Radius: ' + IntToStr(CloakFieldRadius));
end;

procedure CloakOnly_RadiusIncrease;
begin
  CloakFieldRadius := CloakFieldRadius + 50;
  if CloakFieldRadius > 5000 then CloakFieldRadius := 5000;
  if IsGamePlaying then
    SendTextLocal('[CloakOnly] Radius: ' + IntToStr(CloakFieldRadius));
end;

procedure CloakOnly_PrintInfo;
begin
  if not IsGamePlaying then begin SendTextLocal('[CloakOnly] Not in game'); Exit; end;
  SendTextLocal('[CloakOnly] Cloaker=' + IniSettings.Cloaker +
    ' Radius=' + IntToStr(CloakFieldRadius) +
    ' Net=off' +
    ' Transitions(session)=' + IntToStr(SessionTransitions) +
    ' ON=' + IntToStr(CloakOnCount) +
    ' OFF=' + IntToStr(CloakOffCount) +
    ' Enemy=' + IntToStr(EnemyEventCount));
end;

procedure CloakOnly_CycleDebugMode;
begin
  {$IFDEF TPLAYX_DEBUG}
  DebugMode := (DebugMode + 1) mod 2;
  if IsGamePlaying then
    SendTextLocal('[CloakOnly] Debug=' + IntToStr(DebugMode));
  {$ELSE}
  DebugMode := 0;                               // forced silent in release
  if IsGamePlaying then
   // SendTextLocal('[CloakOnly] debug output is not compiled in (build with -dTPLAYX_DEBUG)');
  {$ENDIF}
end;

// ---------------------------------------------------------------------------
// Thread
// ---------------------------------------------------------------------------

procedure ResetTracking;
begin
  FillChar(ArmradLastHealth,  SizeOf(ArmradLastHealth),  0);
  FillChar(ArmradDamageTimer, SizeOf(ArmradDamageTimer), 0);
  FillChar(PrevArmrads,       SizeOf(PrevArmrads),       0);
  FillChar(PrevSuppressed,    SizeOf(PrevSuppressed),    0);
  PrevArmradCount := 0;
end;

{$IFDEF TPLAYX_DEBUG}
// 5-second [Ping] chat readout - debug builds only (it filled the chat area)
procedure PingReadout;
var
  PI      : Integer;
  PingMsg : string;
  PName   : string;
  pPlayer : PPlayerStruct;
  IsFirst : Boolean;
begin
  Inc(Timer5Sec);
  if Timer5Sec < 166 then Exit;                 // 166 * 30 ms = ~5 s
  Timer5Sec := 0;
  PingMsg   := '[Ping] ';
  IsFirst   := True;
  for PI := 0 to MAXPLAYERCOUNT - 1 do
  begin
    pPlayer := @TAData.MainStruct.PlayersExt[PI];
    if pPlayer^.lPlayerActive <> 0 then
    begin
      PName := Trim(string(AnsiString(pPlayer^.szName)));
      if PName = '' then PName := 'P' + IntToStr(PI);
      if not IsFirst then PingMsg := PingMsg + ' | ';
      PingMsg := PingMsg + PName + ': ' + IntToStr(pPlayer^.nPing) + 'ms';
      IsFirst := False;
    end;
  end;
  if not IsFirst then
    SendTextLocal(PingMsg);
end;
{$ENDIF}

function CloakThread(Parameter: Pointer): PtrInt;
begin
  Result := 0;
  while not ExitThreadSignal do
  begin
    try
      if IsGamePlaying then
      begin
        if not WasPlaying then
        begin
          WasPlaying         := True;
          SessionTransitions := 0;
          CloakOnCount       := 0;
          CloakOffCount      := 0;
          EnemyEventCount    := 0;
          {$IFDEF TPLAYX_DEBUG}
          Timer5Sec          := 0;
          {$ENDIF}
          ResetTracking;
          OpenLog;
          WriteLog('Game started  Radius=' + IntToStr(CloakFieldRadius) + '  NetSend=off');
          {$IFDEF TPLAYX_DEBUG}
          SendTextLocal('[CloakOnly] Active - Radius: ' + IntToStr(CloakFieldRadius));
          {$ENDIF}
        end;

        if CloakerList <> '' then
          ApplyArmradCloak;
        {$IFDEF TPLAYX_DEBUG}
        PingReadout;
        {$ENDIF}
      end
      else if WasPlaying then
      begin
        WasPlaying := False;
        WriteLog(Format('Game ended  Transitions=%d  ON=%d  OFF=%d  Enemy=%d',
          [SessionTransitions, CloakOnCount, CloakOffCount, EnemyEventCount]));
        CloseLog;
        ResetTracking;
      end;
    except
      // An exception must never kill this thread (it used to escape from
      // OpenLog/SendTextLocal, which were outside the old try block).
    end;
    Sleep(30);
  end;
end;

// ---------------------------------------------------------------------------
// Install / Uninstall / GetPlugin
// ---------------------------------------------------------------------------

procedure OnInstallCloak;
var
  ThreadId: TThreadID;
begin
  if CloakThreadHandle <> 0 then Exit;          // never start a second thread / leak a handle
  CloakFieldRadius   := DEFAULT_CLOAK_RADIUS;
  ExitThreadSignal   := False;
  WasPlaying         := False;
  TotalTransitions   := 0;
  SessionTransitions := 0;
  CloakOnCount       := 0;
  CloakOffCount      := 0;
  EnemyEventCount    := 0;
  DebugMode          := 0;                      // explicit, not left to the default
  // which unit(s) project the cloak field: CLOAKER= in the ini
  CloakerList := ',' + AnsiLowerCase(StringReplace(StringReplace(IniSettings.Cloaker,
                 ' ', '', [rfReplaceAll]), ';', '', [rfReplaceAll])) + ',';
  if CloakerList = ',,' then
    CloakerList := ',armrad,';
  // Cloaker = NONE (or OFF) switches the area cloak off completely
  if (CloakerList = ',none,') or (CloakerList = ',off,') then
    CloakerList := '';
  ResetTracking;
  CloakThreadHandle := THandle(BeginThread(nil, 0, @CloakThread, nil, 0, ThreadId));
end;

procedure OnUninstallCloak;
begin
  ExitThreadSignal := True;
  if CloakThreadHandle <> 0 then
  begin
    // Wait for the thread to leave; only then is it safe to close the log it uses
    WaitForSingleObject(CloakThreadHandle, 2000);
    CloseHandle(CloakThreadHandle);
    CloakThreadHandle := 0;
  end;
  CloseLog;
end;

function GetPlugin: TPluginData;
begin
  Result := TPluginData.Create(True, 'Cloak Only (local, no net send)', True,
                               @OnInstallCloak, @OnUninstallCloak);
end;

initialization
  InitializeCriticalSection(LogLock);

finalization
  CloseLog;
  DeleteCriticalSection(LogLock);

end.
