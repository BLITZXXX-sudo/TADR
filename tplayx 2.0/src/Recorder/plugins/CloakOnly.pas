{$MODE DELPHI}
unit CloakOnly;

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

function CloakOnly_FieldRadius(pUnit: PUnitStruct): Integer;
function CloakOnly_FieldAnim(pUnit: PUnitStruct): Integer;
function CloakOnly_FieldRingColor(pUnit: PUnitStruct): Integer;

function CloakOnly_FieldState(UnitId: Word): Integer;

const
  DEFAULT_CLOAK_RADIUS = 500;
  MAX_ARMRAD_UNITS     = 64;
  DAMAGE_DECLOAK_TICKS = 60;
  DEFAULT_RING_COLOR   = 254;
  UNIT_STRUCT_STRIDE   = $118;

var
  CloakFieldRadius : Integer = DEFAULT_CLOAK_RADIUS;
  DebugMode        : Integer = 1;

implementation

var
  DebugThreadHandle : THandle  = 0;
  ExitThreadSignal  : Boolean  = False;
  WasPlaying        : Boolean  = False;
  ArmradDamageTimer : array[0..MAX_ARMRAD_UNITS-1] of Integer;
  ArmradLastHealth  : array[0..MAX_ARMRAD_UNITS-1] of Word;
  PrevArmrads       : array[0..MAX_ARMRAD_UNITS-1] of PUnitStruct;
  PrevSuppressed    : array[0..MAX_ARMRAD_UNITS-1] of Boolean;
  PrevArmradCount   : Integer = 0;

  PubGenId          : array[0..MAX_ARMRAD_UNITS-1] of Word;
  PubGenUp          : array[0..MAX_ARMRAD_UNITS-1] of Boolean;
  PubGenCount       : Integer = 0;

  SessionBroadcasts : Integer = 0;
  TotalBroadcasts   : Integer = 0;
  CloakOnCount      : Integer = 0;
  CloakOffCount     : Integer = 0;
  EnemyEventCount   : Integer = 0;

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

function GetUnitName(pUnit: PUnitStruct): AnsiString;
var Info: PUnitInfo;
begin
  Result := '?';
  if (pUnit = nil) or (pUnit^.nUnitInfoID = 0) then Exit;
  Info := TAMem.UnitInfoId2Ptr(pUnit^.nUnitInfoID);
  if (Info <> nil) and (DWORD(Info) > $10000) then
    Result := AnsiString(Info^.szUnitName);
end;

function FieldRec(pUnit: PUnitStruct): PUnitInfoCustomFieldsRec;
begin
  Result := nil;
  if (pUnit <> nil) and (pUnit^.p_UNITINFO <> nil) and
     (pUnit^.p_UNITINFO^.nCategory <= High(UnitInfoCustomFields)) then
    Result := @UnitInfoCustomFields[pUnit^.p_UNITINFO^.nCategory];
end;

function CloakOnly_FieldRadius(pUnit: PUnitStruct): Integer;
var F: PUnitInfoCustomFieldsRec;
begin
  Result := 0;
  F := FieldRec(pUnit);
  if F = nil then Exit;
  if F^.CloakFieldRadius > 0 then
    Result := F^.CloakFieldRadius;
end;

function CloakOnly_FieldAnim(pUnit: PUnitStruct): Integer;
var F: PUnitInfoCustomFieldsRec;
begin
  Result := 0;
  F := FieldRec(pUnit);
  if (F <> nil) and (F^.CloakFieldAnim > 0) then Result := F^.CloakFieldAnim;
end;

function CloakOnly_FieldRingColor(pUnit: PUnitStruct): Integer;
var F: PUnitInfoCustomFieldsRec;
begin
  Result := DEFAULT_RING_COLOR;
  F := FieldRec(pUnit);
  if (F <> nil) and (F^.CloakFieldRingColor >= 0) then Result := F^.CloakFieldRingColor and $FF;
end;

function FieldDamageDelay(pUnit: PUnitStruct): Integer;
var F: PUnitInfoCustomFieldsRec;
begin
  Result := DAMAGE_DECLOAK_TICKS;
  F := FieldRec(pUnit);
  if (F <> nil) and (F^.CloakFieldDamageDelay >= 0) then Result := F^.CloakFieldDamageDelay;
end;

function FieldEnemyCancel(pUnit: PUnitStruct): Boolean;
var F: PUnitInfoCustomFieldsRec;
begin
  Result := True;
  F := FieldRec(pUnit);
  if (F <> nil) and (F^.CloakFieldEnemyCancel >= 0) then Result := F^.CloakFieldEnemyCancel <> 0;
end;

function CloakOnly_FieldState(UnitId: Word): Integer;
var J, N: Integer;
begin
  Result := -1;
  N := PubGenCount;
  if N > MAX_ARMRAD_UNITS then N := MAX_ARMRAD_UNITS;
  for J := 0 to N - 1 do
    if PubGenId[J] = UnitId then
    begin
      if PubGenUp[J] then Result := 1 else Result := 0;
      Exit;
    end;
end;

procedure SetCloakOn(pUnit: PUnitStruct; pArmrad: PUnitStruct);
var
  UnitId : Word;
  WasOurs: Boolean;
begin
  UnitId  := TAUnit.GetId(pUnit);
  WasOurs := (UnitId < Cardinal(Length(UnitsCustomFields))) and
             (UnitsCustomFields[UnitId].CloakFieldArmrad <> nil);

  if WasOurs then
  begin
    UnitsCustomFields[UnitId].CloakFieldArmrad := pArmrad;
    Exit;
  end;

  if TAUnit.GetCloak(pUnit) <> 0 then Exit;

  TAUnit.SetCloak(pUnit, 1);
  if UnitId < Cardinal(Length(UnitsCustomFields)) then
    UnitsCustomFields[UnitId].CloakFieldArmrad := pArmrad;

  Inc(TotalBroadcasts); Inc(SessionBroadcasts); Inc(CloakOnCount);

end;

procedure SetCloakOff(pUnit: PUnitStruct; const Reason: string);
var
  UnitId : Word;
  WasOurs: Boolean;
begin
  UnitId  := TAUnit.GetId(pUnit);
  WasOurs := (UnitId < Cardinal(Length(UnitsCustomFields))) and
             (UnitsCustomFields[UnitId].CloakFieldArmrad <> nil);

  if not WasOurs then Exit;

  if UnitId < Cardinal(Length(UnitsCustomFields)) then
    UnitsCustomFields[UnitId].CloakFieldArmrad := nil;

  if TAUnit.GetCloak(pUnit) = 0 then Exit;

  TAUnit.SetCloak(pUnit, 0);

  Inc(TotalBroadcasts); Inc(SessionBroadcasts); Inc(CloakOffCount);

end;

procedure GetPlayerBounds(pUnit: PUnitStruct;
  out pBase: PUnitStruct; out pEnd: PUnitStruct);
var
  PI: Integer;
  pb, pe: PUnitStruct;
begin
  pBase := nil; pEnd := nil;
  for PI := 0 to MAXPLAYERCOUNT - 1 do
  begin
    pb := PUnitStruct(TAData.MainStruct.Players[PI].p_UnitsArray);
    pe := PUnitStruct(TAData.MainStruct.Players[PI].p_LastUnit);
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
  Armrads        : array[0..MAX_ARMRAD_UNITS-1] of PUnitStruct;
  ArmradOwner    : array[0..MAX_ARMRAD_UNITS-1] of Byte;
  ArmradUnitId   : array[0..MAX_ARMRAD_UNITS-1] of Word;
  ArmradBase     : array[0..MAX_ARMRAD_UNITS-1] of PUnitStruct;
  ArmradEnd      : array[0..MAX_ARMRAD_UNITS-1] of PUnitStruct;
  Suppressed     : array[0..MAX_ARMRAD_UNITS-1] of Boolean;
  ArmradRadius   : array[0..MAX_ARMRAD_UNITS-1] of Integer;
  ArmradEnemyCxl : array[0..MAX_ARMRAD_UNITS-1] of Boolean;
  Count, J, PJ   : Integer;
  FieldR         : Integer;
  Health         : Word;
  CoveringArmrad : PUnitStruct;
  PrevWasSuppr   : Boolean;
begin
  pBase := TAData.UnitsArray_p;
  pEnd  := TAData.EndOfUnitsArray_p;
  if (pBase = nil) or (pEnd = nil) or (Cardinal(pBase) >= Cardinal(pEnd)) then Exit;

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
        FieldR := CloakOnly_FieldRadius(pUnit);
        if (FieldR > 0) and (Count < MAX_ARMRAD_UNITS) then
        begin
          Armrads[Count]     := pUnit;
          ArmradRadius[Count]   := FieldR;
          ArmradEnemyCxl[Count] := FieldEnemyCancel(pUnit);
          ArmradOwner[Count] := TAUnit.GetOwnerIndex(pUnit);
          ArmradUnitId[Count]:= TAUnit.GetId(pUnit);

          GetPlayerBounds(pUnit, ArmradBase[Count], ArmradEnd[Count]);
          Suppressed[Count]  := False;

          Health := pUnit^.nHealth;
          if (ArmradLastHealth[Count] > 0) and (Health < ArmradLastHealth[Count]) then
            ArmradDamageTimer[Count] := FieldDamageDelay(pUnit);
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
    PubGenCount := 0;
    Exit;
  end;

  PrevArmradCount := Count;

  pUnit := pBase;
  while Cardinal(pUnit) < Cardinal(pEnd) do
  begin
    if IsUnitAlive(pUnit) then
      for J := 0 to Count - 1 do
      begin
        if Suppressed[J] then Continue;
        if not ArmradEnemyCxl[J] then Continue;
        if pUnit = Armrads[J] then Continue;

        if IsSamePlayerArray(pUnit, ArmradBase[J], ArmradEnd[J]) then Continue;

        if TAUnit.IsAllied(pUnit, ArmradUnitId[J]) <> 0 then Continue;
        if IsWithinDistance(pUnit, Armrads[J], ArmradRadius[J]) then
        begin
          PrevWasSuppr := False;
          for PJ := 0 to PrevArmradCount - 1 do
            if PrevArmrads[PJ] = Armrads[J] then
            begin PrevWasSuppr := PrevSuppressed[PJ]; Break; end;
          if not PrevWasSuppr then
          begin
            Inc(EnemyEventCount);
            UnitInfo := nil;
            if pUnit^.nUnitInfoID <> 0 then
              UnitInfo := TAMem.UnitInfoId2Ptr(pUnit^.nUnitInfoID);
            if (UnitInfo <> nil) and (DWORD(UnitInfo) > $10000) then
            begin
            end;
          end;
          Suppressed[J] := True;
        end;
      end;
    pUnit := PUnitStruct(Cardinal(pUnit) + UNIT_STRUCT_STRIDE);
  end;

  for J := 0 to Count - 1 do
  begin
    if not Suppressed[J] then Continue;
    PrevWasSuppr := False;
    for PJ := 0 to MAX_ARMRAD_UNITS - 1 do
      if PrevArmrads[PJ] = Armrads[J] then
      begin PrevWasSuppr := PrevSuppressed[PJ]; Break; end;
    if PrevWasSuppr then Continue;
    if not TAUnit.IsOnThisComp(Armrads[J], False) then Continue;
    if ArmradDamageTimer[J] > 0 then
      SendTextLocal(string(GetUnitName(Armrads[J])) + ' cloak field down - under attack')
    else
      SendTextLocal(string(GetUnitName(Armrads[J])) + ' cloak field down - enemy nearby');
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

  for J := 0 to Count - 1 do
  begin
    PubGenId[J] := ArmradUnitId[J];
    PubGenUp[J] := not Suppressed[J];
  end;
  PubGenCount := Count;

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
           IsWithinDistance(pUnit, pArmrad, ArmradRadius[J]) then
        begin CoveringArmrad := pArmrad; Break; end;
      end;

      if CoveringArmrad <> nil then
        SetCloakOn(pUnit, CoveringArmrad)
      else
      begin

        CoveringArmrad := nil;
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

procedure CloakOnly_RadiusDecrease; begin end;
procedure CloakOnly_RadiusIncrease; begin end;
procedure CloakOnly_PrintInfo;      begin end;
procedure CloakOnly_CycleDebugMode; begin end;

function CloakThread(Parameter: Pointer): PtrInt;
begin
  Result := 0;
  while not ExitThreadSignal do
  begin
    if IsGamePlaying then
    begin
      if not WasPlaying then
      begin
        WasPlaying        := True;
        SessionBroadcasts := 0;
        CloakOnCount      := 0;
        CloakOffCount     := 0;
        EnemyEventCount   := 0;
        FillChar(ArmradLastHealth,  SizeOf(ArmradLastHealth),  0);
        FillChar(ArmradDamageTimer, SizeOf(ArmradDamageTimer), 0);
        FillChar(PrevArmrads,       SizeOf(PrevArmrads),       0);
        FillChar(PrevSuppressed,    SizeOf(PrevSuppressed),    0);
        PrevArmradCount := 0;
        PubGenCount := 0;
      end;
      try ApplyArmradCloak; except end;
    end
    else
    begin
      if WasPlaying then
      begin
        WasPlaying := False;
        FillChar(ArmradLastHealth,  SizeOf(ArmradLastHealth),  0);
        FillChar(ArmradDamageTimer, SizeOf(ArmradDamageTimer), 0);
        FillChar(PrevArmrads,       SizeOf(PrevArmrads),       0);
        FillChar(PrevSuppressed,    SizeOf(PrevSuppressed),    0);
        PrevArmradCount := 0;
        PubGenCount := 0;
      end;
    end;
    Sleep(30);
  end;
end;

procedure OnInstallCloak;
var
  ThreadId: TThreadID;
begin
  CloakFieldRadius  := DEFAULT_CLOAK_RADIUS;
  ExitThreadSignal  := False;
  WasPlaying        := False;
  PrevArmradCount   := 0;
  TotalBroadcasts   := 0;
  SessionBroadcasts := 0;
  CloakOnCount      := 0;
  CloakOffCount     := 0;
  EnemyEventCount   := 0;
  FillChar(ArmradLastHealth,  SizeOf(ArmradLastHealth),  0);
  FillChar(ArmradDamageTimer, SizeOf(ArmradDamageTimer), 0);
  FillChar(PrevArmrads,       SizeOf(PrevArmrads),       0);
  FillChar(PrevSuppressed,    SizeOf(PrevSuppressed),    0);
  DebugThreadHandle := THandle(BeginThread(nil, 0, @CloakThread, nil, 0, ThreadId));
end;

procedure OnUninstallCloak;
begin
  if DebugThreadHandle <> 0 then
  begin
    ExitThreadSignal := True;
    WaitForSingleObject(DebugThreadHandle, 2000);
    CloseHandle(DebugThreadHandle);
    DebugThreadHandle := 0;
  end;
end;

function GetPlugin: TPluginData;
begin
  Result := TPluginData.Create(True, 'Cloak Only', True,
                               @OnInstallCloak, @OnUninstallCloak);
end;

end.
