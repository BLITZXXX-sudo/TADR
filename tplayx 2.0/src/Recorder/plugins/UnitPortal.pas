unit UnitPortal;

interface

uses
  TA_MemoryStructures;

function GetNativeSelectedUnit: PUnitStruct;

procedure PortalOnOff_BeginForUnit(p_Unit: PUnitStruct);
function PortalOnOff_DispatchToTarget(p_Unit: PUnitStruct; const Target: TPosition): Boolean;
procedure PortalOnOff_StopForUnit(p_Unit: PUnitStruct);
function PortalOnOff_StatusLine: String;
function PortalOnOff_TransportAlive(p_Unit: PUnitStruct): Boolean;
procedure PortalOnOff_Tick;

type

  TPortalOverlayInfo = record
    LoopRunning  : Boolean;
    TransportId  : Word;
    SrcOn, DstOn : Boolean;
    SrcX, SrcY, SrcZ : Integer;
    DstX, DstY, DstZ : Integer;
    PickupRadius : Integer;
    DropRadius   : Integer;
    Aboard, Capacity : Integer;
    WaitingFull  : Boolean;
    BeaconAnim   : Integer;
  end;

procedure PortalOnOff_GetOverlay(out Info: TPortalOverlayInfo);

implementation

uses
  Windows, SysUtils, Classes, Math,
  TA_MemUnits,
  TA_MemoryLocations,
  TA_FunctionsU,
  idplay;

type
  TPortalPos = record
    X: Word;
    Z: Word;
    Y: Word;
    Name: String;
    Active: Boolean;
  end;

var
  SelectedUnitId: Word = 0;

  SourcePos: TPortalPos;
  DestPos: TPortalPos;

  AutoLoopEnabled: Boolean = False;
  AutoLoopUnitId: Word = 0;
  AutoLoopPhase: Integer = 0;

  AutoLoopThreadHandle: THandle = 0;
  AutoLoopThreadActive: Boolean = False;
  StragglerCheckPending: Boolean = False;

  FullWaitStartTick: Cardinal = 0;

  Cfg_PickupScanRadius: Integer = 300;

  Cfg_UnloadSearchMaxRadius: Integer = 300;

  Cfg_UnloadSearchRadiusStep: Integer = 30;

  Cfg_UnloadSearchAnglesPerRing: Integer = 12;

  Cfg_UnloadMinSeparation: Integer = 80;

  Cfg_AutoLoopPollMs: Integer = 3000;

  Cfg_WaitForFullLoad: Integer = 1;

  Cfg_FullLoadTimeoutSec: Integer = 0;

  Cfg_FullWeightPercent: Integer = 90;

  Cfg_OnOffHoverLiftOff: Integer = 1;

  Cfg_OnOffHoverOffset: Integer = 48;

  Cfg_OnOffHoverOrder: Integer = 1;

  Cfg_DropBeaconAnim: Integer = 5;

  Cfg_OnOffHoverDelayTicks: Integer = 4;

  HoverPending: Boolean = False;
  HoverUnitId: Word = 0;
  HoverDueTime: Integer = 0;

  Map_ScreenToWorldClick: procedure(pData: Pointer); stdcall;

procedure ChatMsg(const Msg: String);
begin
  SendTextLocal(Msg);
end;

function FerryFields(p_Unit: PUnitStruct): PUnitInfoCustomFieldsRec;
begin
  Result := nil;
  if (p_Unit <> nil) and (p_Unit.p_UNITINFO <> nil) and
     (p_Unit.p_UNITINFO.nCategory <= High(UnitInfoCustomFields)) then
    Result := @UnitInfoCustomFields[p_Unit.p_UNITINFO.nCategory];
end;

function FerryPick(FbiValue, Default: Integer): Integer; inline;
begin
  if FbiValue >= 0 then Result := FbiValue else Result := Default;
end;

function FerryPickupRadius(p_Unit: PUnitStruct): Integer;
var F: PUnitInfoCustomFieldsRec;
begin
  F := FerryFields(p_Unit);
  if F = nil then Result := Cfg_PickupScanRadius else Result := FerryPick(F.FerryPickupRadius, Cfg_PickupScanRadius);
end;

function FerryDropRadius(p_Unit: PUnitStruct): Integer;
var F: PUnitInfoCustomFieldsRec;
begin
  F := FerryFields(p_Unit);
  if F = nil then Result := Cfg_UnloadSearchMaxRadius else Result := FerryPick(F.FerryDropRadius, Cfg_UnloadSearchMaxRadius);
end;

function FerryUnloadSpacing(p_Unit: PUnitStruct): Integer;
var F: PUnitInfoCustomFieldsRec;
begin
  F := FerryFields(p_Unit);
  if F = nil then Result := Cfg_UnloadMinSeparation else Result := FerryPick(F.FerryUnloadSpacing, Cfg_UnloadMinSeparation);
end;

function FerryWaitFull(p_Unit: PUnitStruct): Integer;
var F: PUnitInfoCustomFieldsRec;
begin
  F := FerryFields(p_Unit);
  if F = nil then Result := Cfg_WaitForFullLoad else Result := FerryPick(F.FerryWaitFull, Cfg_WaitForFullLoad);
end;

function FerryFullTimeout(p_Unit: PUnitStruct): Integer;
var F: PUnitInfoCustomFieldsRec;
begin
  F := FerryFields(p_Unit);
  if F = nil then Result := Cfg_FullLoadTimeoutSec else Result := FerryPick(F.FerryFullTimeout, Cfg_FullLoadTimeoutSec);
end;

function FerryFullWeightPct(p_Unit: PUnitStruct): Integer;
var F: PUnitInfoCustomFieldsRec;
begin
  F := FerryFields(p_Unit);
  if F = nil then Result := Cfg_FullWeightPercent else Result := FerryPick(F.FerryFullWeightPct, Cfg_FullWeightPercent);
end;

function FerryHoverOffset(p_Unit: PUnitStruct): Integer;
var F: PUnitInfoCustomFieldsRec;
begin
  F := FerryFields(p_Unit);
  if F = nil then Result := Cfg_OnOffHoverOffset else Result := FerryPick(F.FerryHoverOffset, Cfg_OnOffHoverOffset);
end;

function FerryBeaconAnim(p_Unit: PUnitStruct): Integer;
var F: PUnitInfoCustomFieldsRec;
begin
  F := FerryFields(p_Unit);
  if F = nil then Result := Cfg_DropBeaconAnim else Result := FerryPick(F.FerryBeaconAnim, Cfg_DropBeaconAnim);
end;

function FerryHoverOrder(p_Unit: PUnitStruct): Integer;
var F: PUnitInfoCustomFieldsRec;
begin
  F := FerryFields(p_Unit);
  if F = nil then Result := Cfg_OnOffHoverOrder else Result := FerryPick(F.FerryHoverOrder, Cfg_OnOffHoverOrder);
end;

function FerrySettingsStr(p_Unit: PUnitStruct): String;
begin
  Result := 'PickupRadius=' + IntToStr(FerryPickupRadius(p_Unit)) +
    ' DropRadius=' + IntToStr(FerryDropRadius(p_Unit)) +
    ' UnloadSpacing=' + IntToStr(FerryUnloadSpacing(p_Unit)) +
    ' WaitFull=' + IntToStr(FerryWaitFull(p_Unit)) +
    ' FullTimeout=' + IntToStr(FerryFullTimeout(p_Unit)) +
    ' FullWeightPct=' + IntToStr(FerryFullWeightPct(p_Unit)) +
    ' HoverOffset=' + IntToStr(FerryHoverOffset(p_Unit)) +
    ' BeaconAnim=' + IntToStr(FerryBeaconAnim(p_Unit)) +
    ' HoverOrder=' + IntToStr(FerryHoverOrder(p_Unit));
end;

function TryCaptureGroundClick(out GameX, GameZ: Word): Boolean;
var
  ResolvedX, ResolvedZ: Word;
  MapWidth, MapHeight: Integer;
begin
  Result := False;
  GameX := 0;
  GameZ := 0;

  if (TAData.MainStruct = nil) or (not Assigned(Map_ScreenToWorldClick)) then
    Exit;

  Map_ScreenToWorldClick(Pointer(Cardinal(TAData.MainStruct) + $2C76));

  ResolvedX := TAData.MainStruct.nMouseMapPosX;
  ResolvedZ := TAData.MainStruct.nMouseMapPosY;

  MapWidth := TAData.MainStruct.TNTMemStruct.lMapWidth;
  MapHeight := TAData.MainStruct.TNTMemStruct.lMapHeight;

  if (MapWidth <= 0) or (MapHeight <= 0) then
    Exit;
  if (ResolvedX = 0) and (ResolvedZ = 0) then
    Exit;
  if (Integer(ResolvedX) > MapWidth) or (Integer(ResolvedZ) > MapHeight) then
    Exit;

  GameX := ResolvedX;
  GameZ := ResolvedZ;
  Result := True;
end;

function CapturePositionFromMouse(out X, Z, Y: Word): Boolean;
var
  MouseUnit, p_Unit: PUnitStruct;
begin
  Result := False;
  X := 0;
  Z := 0;
  Y := 0;

  if TryCaptureGroundClick(X, Z) then
  begin
    Y := 0;
    Result := True;
    Exit;
  end;

  MouseUnit := TAUnit.AtMouse;
  if MouseUnit <> nil then
  begin
    X := TAUnit.GetUnitX(MouseUnit);
    Z := TAUnit.GetUnitZ(MouseUnit);
    Y := TAUnit.GetUnitY(MouseUnit);
    Result := True;
    Exit;
  end;

  if SelectedUnitId <> 0 then
  begin
    p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
    if (p_Unit <> nil) and (p_Unit.p_UNITINFO <> nil) then
    begin
      X := TAUnit.GetUnitX(p_Unit);
      Z := TAUnit.GetUnitZ(p_Unit);
      Y := TAUnit.GetUnitY(p_Unit);
      Result := True;
    end;
  end;
end;

function IsFlyingUnit(p_Unit: PUnitStruct): Boolean;
begin
  Result := False;
  if (p_Unit <> nil) and (p_Unit.p_UNITINFO <> nil) then
    Result := TAUnit.GetUnitInfoField(p_Unit, uiCanFly) = 1;
end;

function UnitDisplayName(p_Unit: PUnitStruct): String;
begin
  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
    Result := '<invalid unit>'
  else
    Result := String(p_Unit.p_UNITINFO.szUnitName) + ' (#' + IntToStr(TAUnit.GetId(p_Unit)) + ')';
end;

function GetNativeSelectedUnit: PUnitStruct;
var
  i: Word;
  Candidate: PUnitStruct;
begin
  Result := nil;
  for i := 1 to TAData.MaxUnitsID do
  begin
    Candidate := TAUnit.Id2Ptr(i);
    if (Candidate = nil) or (Candidate.p_UNITINFO = nil) then
      Continue;
    if (Candidate.lUnitStateMask and UnitSelectState[UnitSelected_State]) = UnitSelectState[UnitSelected_State] then
    begin
      Result := Candidate;
      Exit;
    end;
  end;
end;

function IssueScriptOrder(p_Unit, TargetUnit: PUnitStruct;
  const ScriptActionName: String; Position: PPosition; ShiftKey: Byte): LongInt;
var
  ScriptIndex: Byte;
begin
  ScriptIndex := TAMem.ScriptActionName2Index(ScriptActionName);
  Result := Order2Unit(ScriptIndex, ShiftKey, p_Unit, TargetUnit, Position, 0, 0);
end;

function FindNearestValidUnloadSpot(p_Unit: PUnitStruct; const CenterPos: TPosition;
  out ResultPos: TPosition): Boolean;

var
  Radius, AngleVal, i: Integer;
  CandX, CandZ: Integer;
  CandPos: TPosition;
  Height: Integer;
begin
  Result := False;
  FillChar(ResultPos, SizeOf(ResultPos), 0);

  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
    Exit;

  if TAUnit.TestUnloadPosition(p_Unit.p_UNITINFO, CenterPos) then
  begin
    ResultPos := CenterPos;
    Result := True;
    Exit;
  end;

  Radius := Cfg_UnloadSearchRadiusStep;
  while Radius <= FerryDropRadius(p_Unit) do
  begin
    for i := 0 to Cfg_UnloadSearchAnglesPerRing - 1 do
    begin
      AngleVal := Round((360 / Cfg_UnloadSearchAnglesPerRing) * i);
      if TAUnits.CircleCoords(CenterPos, Radius, AngleVal, CandX, CandZ) then
      begin
        if Assigned(GetTPosition) and (GetTPosition(CandX, CandZ, CandPos) <> nil) then
        begin
          if Assigned(GetPosHeight) then
          begin
            Height := GetPosHeight(@CandPos);
            if Height <> -1 then
              CandPos.Y := Height * 65536
            else
              CandPos.Y := CenterPos.Y;
          end else
            CandPos.Y := CenterPos.Y;

          if TAUnit.TestUnloadPosition(p_Unit.p_UNITINFO, CandPos) then
          begin
            ResultPos := CandPos;
            Result := True;
            Exit;
          end;
        end;
      end;
    end;
    Inc(Radius, Cfg_UnloadSearchRadiusStep);
  end;

end;

type
  TPositionArray = array of TPosition;

function FindMultipleValidUnloadSpots(p_Unit: PUnitStruct; const CenterPos: TPosition;
  Count: Integer): TPositionArray;

var
  Radius, AngleVal, i: Integer;
  CandX, CandZ: Integer;
  CandPos: TPosition;
  Height: Integer;
  Results: TPositionArray;

  function FarEnoughFromExisting(const P: TPosition): Boolean;
  var
    k: Integer;
    dx, dz: Int64;
  begin
    Result := True;
    for k := 0 to High(Results) do
    begin
      dx := (P.X - Results[k].X) div 65536;
      dz := (P.Z - Results[k].Z) div 65536;
      if Round(Hypot(dx, dz)) < FerryUnloadSpacing(p_Unit) then
      begin
        Result := False;
        Exit;
      end;
    end;
  end;

begin
  SetLength(Results, 0);

  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) or (Count <= 0) then
  begin
    Result := Results;
    Exit;
  end;

  if TAUnit.TestUnloadPosition(p_Unit.p_UNITINFO, CenterPos) then
  begin
    SetLength(Results, 1);
    Results[0] := CenterPos;
  end;

  Radius := Cfg_UnloadSearchRadiusStep;
  while (Length(Results) < Count) and (Radius <= FerryDropRadius(p_Unit)) do
  begin
    for i := 0 to Cfg_UnloadSearchAnglesPerRing - 1 do
    begin
      if Length(Results) >= Count then
        Break;

      AngleVal := Round((360 / Cfg_UnloadSearchAnglesPerRing) * i);
      if TAUnits.CircleCoords(CenterPos, Radius, AngleVal, CandX, CandZ) then
      begin
        if Assigned(GetTPosition) and (GetTPosition(CandX, CandZ, CandPos) <> nil) then
        begin
          if Assigned(GetPosHeight) then
          begin
            Height := GetPosHeight(@CandPos);
            if Height <> -1 then
              CandPos.Y := Height * 65536
            else
              CandPos.Y := CenterPos.Y;
          end else
            CandPos.Y := CenterPos.Y;

          if TAUnit.TestUnloadPosition(p_Unit.p_UNITINFO, CandPos) and FarEnoughFromExisting(CandPos) then
          begin
            SetLength(Results, Length(Results) + 1);
            Results[High(Results)] := CandPos;
          end;
        end;
      end;
    end;
    Inc(Radius, Cfg_UnloadSearchRadiusStep);
  end;

  Result := Results;
end;

var
  LoadedCargoIds: array of Word;

procedure ClearLoadedCargoList;
begin
  SetLength(LoadedCargoIds, 0);
end;

procedure AddLoadedCargo(UnitId: Word);
begin
  SetLength(LoadedCargoIds, Length(LoadedCargoIds) + 1);
  LoadedCargoIds[High(LoadedCargoIds)] := UnitId;
end;

function LoadedCargoListStr: String;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(LoadedCargoIds) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + '#' + IntToStr(LoadedCargoIds[i]);
  end;
  if Result = '' then
    Result := '(none)';
end;

type
  TUnitPtrArray = array of PUnitStruct;

function FindLoadableUnitsNearSource(p_Transport: PUnitStruct; SearchRadius: Integer): TUnitPtrArray;
var
  i: Word;
  Candidate: PUnitStruct;
  SrcPos: TPosition;
  CandCount: Integer;
  CurLoadAmount, TransportCap: Integer;
  CurLoadWeight, CandWeight, WeightCap: Integer;
  TransportSize: Byte;
  Results: TUnitPtrArray;
begin
  SetLength(Results, 0);
  CandCount := 0;

  if (p_Transport = nil) or (p_Transport.p_UNITINFO = nil) or (not SourcePos.Active) then
  begin
    Result := Results;
    Exit;
  end;

  SrcPos.X := Integer(SourcePos.X) * 65536;
  SrcPos.Z := Integer(SourcePos.Z) * 65536;
  SrcPos.Y := Integer(SourcePos.Y) * 65536;

  CurLoadAmount := TAUnit.GetLoadCurAmount(p_Transport);
  TransportCap := p_Transport.p_UNITINFO.cTransportCap;
  CurLoadWeight := TAUnit.GetLoadWeight(p_Transport);
  WeightCap := 0;
  if p_Transport.p_UNITINFO.nCategory <= High(UnitInfoCustomFields) then
    WeightCap := UnitInfoCustomFields[p_Transport.p_UNITINFO.nCategory].TransportWeightCapacity;
  TransportSize := p_Transport.p_UNITINFO.cTransportSize;

  for i := 1 to TAData.MaxUnitsID do
  begin
    if CurLoadAmount >= TransportCap then
    begin
      Break;
    end;

    if (WeightCap > 0) and (CurLoadWeight >= WeightCap) then
    begin
      Break;
    end;

    Candidate := TAUnit.Id2Ptr(i);
    if (Candidate = nil) or (Candidate.p_UNITINFO = nil) then
      Continue;

    if (Candidate.lUnitStateMask and UnitSelectState[UnitValid2_State]) <> UnitSelectState[UnitValid2_State] then
      Continue;
    if Candidate.p_Owner = nil then
      Continue;

    if TAUnit.GetId(Candidate) = TAUnit.GetId(p_Transport) then
      Continue;
    if Candidate.p_TransporterUnit <> nil then
      Continue;
    if Candidate.p_UNITINFO.cTransportCap > 0 then
      Continue;

    if Candidate.p_Owner <> p_Transport.p_Owner then
      Continue;
    if (Candidate.p_UNITINFO.UnitTypeMask2 and $40000) <> 0 then
      Continue;
    if (Candidate.p_UNITINFO.UnitTypeMask2 and $80000) <> 0 then
      Continue;
    if (Candidate.p_UNITINFO.UnitTypeMask and (1 shl 11)) <> 0 then
      Continue;

    if (Candidate.p_UNITINFO.cBMCode = 0) or (Candidate.p_UNITINFO.lMaxSpeedRaw = 0) then
      Continue;
    if Candidate.fBuildTimeLeft <> 0.0 then
      Continue;

    if not TAMem.DistanceBetweenPosCompare(@SrcPos, @Candidate.Position, SearchRadius) then
      Continue;

    if Candidate.nFootPrintX > TransportSize then
      Continue;

    CandWeight := Round(Candidate.p_UNITINFO.lBuildCostMetal);
    if (WeightCap > 0) and ((CurLoadWeight + CandWeight) > WeightCap) then
      Continue;

    if (CurLoadAmount + 1) > TransportCap then
      Continue;

    SetLength(Results, CandCount + 1);
    Results[CandCount] := Candidate;
    Inc(CandCount);
    Inc(CurLoadAmount);
    CurLoadWeight := CurLoadWeight + CandWeight;

  end;

  Result := Results;
end;

function GetCarriedUnits(p_Transport: PUnitStruct): TUnitPtrArray;
const
  MaxCarried = 64;

  UnitState_Valid   = $10000000;
  UnitState_Carried = $20000000;
var
  Results: TUnitPtrArray;
  p_Cargo: PUnitStruct;
  SafetyCount: Integer;
begin
  SetLength(Results, 0);

  if (p_Transport = nil) or (p_Transport.p_UNITINFO = nil) then
  begin
    Result := Results;
    Exit;
  end;

  p_Cargo := p_Transport.p_TransportedUnit;
  SafetyCount := 0;
  while (p_Cargo <> nil) and (SafetyCount < MaxCarried) do
  begin
    if (p_Cargo.p_UNITINFO = nil) or
       ((p_Cargo.lUnitStateMask and UnitState_Valid) = 0) or
       ((p_Cargo.lUnitStateMask and UnitState_Carried) = 0) then
    begin
      Break;
    end;

    SetLength(Results, Length(Results) + 1);
    Results[High(Results)] := p_Cargo;
    p_Cargo := p_Cargo.p_PriorUnit;
    Inc(SafetyCount);
  end;

  if SafetyCount >= MaxCarried then
    ;

  Result := Results;
end;

function StragglerListStr(const Units: TUnitPtrArray): String;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(Units) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + UnitDisplayName(Units[i]);
  end;
  if Result = '' then
    Result := '(none)';
end;

function NativeCheckTransportFit(p_Transport, p_Candidate: Pointer): LongBool;
const
  FuncAddr = $00489A90;
begin
  Result := False;
  if (p_Transport = nil) or (p_Candidate = nil) then
    Exit;
  asm
    mov  eax, p_Transport
    mov  ecx, eax
    mov  edx, p_Candidate
    push edx
    call FuncAddr
    mov  Result, eax
  end;
end;

type

  TSavedOrder = record
    Valid: Boolean;
    ActionType: Byte;
    TargetUnit: PUnitStruct;
    Position: TPosition;

    HasNextLeg: Boolean;
    NextActionType: Byte;
    NextTargetUnit: PUnitStruct;
    NextPosition: TPosition;
  end;

function SnapshotCurrentOrder(p_Unit: PUnitStruct): TSavedOrder;
var
  p_Next: PUnitOrder;
begin
  Result.Valid := False;
  Result.TargetUnit := nil;
  FillChar(Result.Position, SizeOf(Result.Position), 0);
  Result.HasNextLeg := False;
  Result.NextTargetUnit := nil;
  FillChar(Result.NextPosition, SizeOf(Result.NextPosition), 0);
  if (p_Unit <> nil) and (p_Unit.p_MainOrder <> nil) then
  begin
    Result.Valid := True;
    Result.ActionType := p_Unit.p_MainOrder.cOrderType;
    Result.TargetUnit := p_Unit.p_MainOrder.p_UnitTarget;
    Result.Position := p_Unit.p_MainOrder.Position;

    if p_Unit.p_MainOrder.p_NextOrder <> nil then
    begin
      p_Next := PUnitOrder(p_Unit.p_MainOrder.p_NextOrder);
      Result.HasNextLeg := True;
      Result.NextActionType := p_Next.cOrderType;
      Result.NextTargetUnit := p_Next.p_UnitTarget;
      Result.NextPosition := p_Next.Position;
    end;
  end;
end;

function DumpOrderState(p_Unit: PUnitStruct): String;
begin
  if (p_Unit = nil) or (p_Unit.p_MainOrder = nil) then
    Result := 'p_MainOrder=nil'
  else
    Result := 'cOrderType=' + IntToStr(p_Unit.p_MainOrder.cOrderType) +
      ' ucState=' + IntToStr(p_Unit.p_MainOrder.ucState) +
      ' Position=(' + IntToStr(p_Unit.p_MainOrder.Position.X) + ',' +
      IntToStr(p_Unit.p_MainOrder.Position.Z) + ',' +
      IntToStr(p_Unit.p_MainOrder.Position.Y) + ')' +
      ' HasNextOrder=' + BoolToStr(p_Unit.p_MainOrder.p_NextOrder <> nil, True);
end;

procedure PortalSendWithAutoUnload(p_Unit: PUnitStruct; TargetPos: TPosition;
  const PointLabel: String);
var
  SourceMovePos, ReturnPos, ActualUnloadPos: TPosition;
  TestResult: Boolean;
  MoveResult, UnloadResult, ReturnResult: LongInt;
  CurX, CurY, CurZ: Word;
begin

  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
  begin
    Exit;
  end;

  CurX := TAUnit.GetUnitX(p_Unit);
  CurY := TAUnit.GetUnitY(p_Unit);
  CurZ := TAUnit.GetUnitZ(p_Unit);

  if p_Unit.p_MovementClass = nil then

  else
    ;

  if p_Unit.p_TransportedUnit = nil then

  else
    ;

  TestResult := FindNearestValidUnloadSpot(p_Unit, TargetPos, ActualUnloadPos);
  if not TestResult then
  begin
    Exit;
  end;

  SourceMovePos.X := 0;
  SourceMovePos.Z := 0;
  SourceMovePos.Y := 0;
  ReturnPos.X := 0;
  ReturnPos.Z := 0;
  ReturnPos.Y := 0;
  if SourcePos.Active then
  begin
    SourceMovePos.X := Integer(SourcePos.X) * 65536;
    SourceMovePos.Z := Integer(SourcePos.Z) * 65536;
    SourceMovePos.Y := Integer(SourcePos.Y) * 65536;

    ReturnPos.X := SourceMovePos.X + (40 * 65536);
    ReturnPos.Z := SourceMovePos.Z + (40 * 65536);
    ReturnPos.Y := SourceMovePos.Y;
  end;

  if IsFlyingUnit(p_Unit) then
  begin
    MoveResult := IssueScriptOrder(p_Unit, nil, 'VTOL_MOVE', @ActualUnloadPos, 0);
  end else
  begin
    MoveResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Move_Ground, @ActualUnloadPos, 0, 0, 0);
  end;

  if IsFlyingUnit(p_Unit) then
  begin
    UnloadResult := IssueScriptOrder(p_Unit, nil, 'VTOL_UNLOAD', @ActualUnloadPos, 1);
  end else
  begin
    UnloadResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Ground_Unload, @ActualUnloadPos, 1, 0, 0);
  end;

  if SourcePos.Active then
  begin
    if IsFlyingUnit(p_Unit) then
      ReturnResult := IssueScriptOrder(p_Unit, nil, 'VTOL_MOVE', @ReturnPos, 1)
    else
      ReturnResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Move_Ground, @ReturnPos, 1, 0, 0);

    if IsFlyingUnit(p_Unit) then
      ReturnResult := IssueScriptOrder(p_Unit, nil, 'VTOL_PATROL', @SourceMovePos, 1)
    else
      ReturnResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Patrol, @SourceMovePos, 1, 0, 0);
  end else
    ;

end;

procedure MoveUnitToSourceAutoUnload(p_Unit: PUnitStruct);
var
  MovePos: TPosition;
begin
  if not SourcePos.Active then
  begin
    Exit;
  end;
  MovePos.X := Integer(SourcePos.X) * 65536;
  MovePos.Z := Integer(SourcePos.Z) * 65536;
  MovePos.Y := Integer(SourcePos.Y) * 65536;
  PortalSendWithAutoUnload(p_Unit, MovePos, 'SOURCE');
end;

procedure MoveUnitToDestAutoUnload(p_Unit: PUnitStruct);
var
  MovePos: TPosition;
begin
  if not DestPos.Active then
  begin
    Exit;
  end;
  MovePos.X := Integer(DestPos.X) * 65536;
  MovePos.Z := Integer(DestPos.Z) * 65536;
  MovePos.Y := Integer(DestPos.Y) * 65536;
  PortalSendWithAutoUnload(p_Unit, MovePos, 'DESTINATION');
end;

procedure PortalFullCycle(p_Unit: PUnitStruct; p_Cargo: PUnitStruct);
var
  SourceMovePos, DestMovePos, ReturnPos, ActualUnloadPos: TPosition;
  TestResult: Boolean;
  StepResult: LongInt;
begin

  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
  begin
    Exit;
  end;

  if not SourcePos.Active then
  begin
    Exit;
  end;
  if not DestPos.Active then
  begin
    Exit;
  end;

  if (p_Cargo = nil) or (p_Cargo.p_UNITINFO = nil) then
  begin
    Exit;
  end;
  if TAUnit.GetId(p_Cargo) = SelectedUnitId then
  begin
    Exit;
  end;

  SourceMovePos.X := Integer(SourcePos.X) * 65536;
  SourceMovePos.Z := Integer(SourcePos.Z) * 65536;
  SourceMovePos.Y := Integer(SourcePos.Y) * 65536;
  DestMovePos.X := Integer(DestPos.X) * 65536;
  DestMovePos.Z := Integer(DestPos.Z) * 65536;
  DestMovePos.Y := Integer(DestPos.Y) * 65536;

  ReturnPos.X := SourceMovePos.X + (40 * 65536);
  ReturnPos.Z := SourceMovePos.Z + (40 * 65536);
  ReturnPos.Y := SourceMovePos.Y;

  TestResult := FindNearestValidUnloadSpot(p_Unit, DestMovePos, ActualUnloadPos);
  if not TestResult then
  begin
    Exit;
  end;

  if IsFlyingUnit(p_Unit) then
    StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_MOVE', @SourceMovePos, 0)
  else
    StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Move_Ground, @SourceMovePos, 0, 0, 0);

  if IsFlyingUnit(p_Unit) then
    StepResult := IssueScriptOrder(p_Unit, p_Cargo, 'VTOL_PICKUP', nil, 1)
  else
    StepResult := TAUnit.CreateMainOrder(p_Unit, p_Cargo, Action_Ground_Pickup, nil, 1, 0, 0);

  if IsFlyingUnit(p_Unit) then
    StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_MOVE', @ActualUnloadPos, 1)
  else
    StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Move_Ground, @ActualUnloadPos, 1, 0, 0);

  if IsFlyingUnit(p_Unit) then
    StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_UNLOAD', @ActualUnloadPos, 1)
  else
    StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Ground_Unload, @ActualUnloadPos, 1, 0, 0);

  if IsFlyingUnit(p_Unit) then
    StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_MOVE', @ReturnPos, 1)
  else
    StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Move_Ground, @ReturnPos, 1, 0, 0);

  if IsFlyingUnit(p_Unit) then
    StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_PATROL', @SourceMovePos, 1)
  else
    StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Patrol, @SourceMovePos, 1, 0, 0);

end;

procedure PortalFullCycleAuto(p_Unit: PUnitStruct);

var
  SourceMovePos, DestMovePos, ReturnPos: TPosition;
  Candidates: TUnitPtrArray;
  UnloadSpots: TPositionArray;
  ThisSpot: TPosition;
  i, SpotIdx, RepeatPass: Integer;
  StepResult: LongInt;
begin

  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
  begin
    Exit;
  end;
  if not SourcePos.Active then
  begin
    Exit;
  end;
  if not DestPos.Active then
  begin
    Exit;
  end;

  Candidates := FindLoadableUnitsNearSource(p_Unit, FerryPickupRadius(p_Unit));
  if Length(Candidates) = 0 then
  begin
    Exit;
  end;

  for i := 0 to High(Candidates) do
    ;

  SourceMovePos.X := Integer(SourcePos.X) * 65536;
  SourceMovePos.Z := Integer(SourcePos.Z) * 65536;
  SourceMovePos.Y := Integer(SourcePos.Y) * 65536;
  DestMovePos.X := Integer(DestPos.X) * 65536;
  DestMovePos.Z := Integer(DestPos.Z) * 65536;
  DestMovePos.Y := Integer(DestPos.Y) * 65536;
  ReturnPos.X := SourceMovePos.X + (40 * 65536);
  ReturnPos.Z := SourceMovePos.Z + (40 * 65536);
  ReturnPos.Y := SourceMovePos.Y;

  UnloadSpots := FindMultipleValidUnloadSpots(p_Unit, DestMovePos, Length(Candidates));
  if Length(UnloadSpots) = 0 then
  begin
    Exit;
  end;
  if Length(UnloadSpots) < Length(Candidates) then
    ;

  ClearLoadedCargoList;

  if IsFlyingUnit(p_Unit) then
    StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_MOVE', @SourceMovePos, 0)
  else
    StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Move_Ground, @SourceMovePos, 0, 0, 0);

  for i := 0 to High(Candidates) do
  begin
    if IsFlyingUnit(p_Unit) then
      StepResult := IssueScriptOrder(p_Unit, Candidates[i], 'VTOL_PICKUP', nil, 1)
    else
      StepResult := TAUnit.CreateMainOrder(p_Unit, Candidates[i], Action_Ground_Pickup, nil, 1, 0, 0);
    AddLoadedCargo(TAUnit.GetId(Candidates[i]));
  end;

  for i := 0 to High(Candidates) do
  begin
    SpotIdx := i mod Length(UnloadSpots);
    ThisSpot := UnloadSpots[SpotIdx];

    RepeatPass := i div Length(UnloadSpots);
    if RepeatPass > 0 then
    begin
      ThisSpot.X := ThisSpot.X + (RepeatPass * 20 * 65536);
      ThisSpot.Z := ThisSpot.Z + (RepeatPass * 20 * 65536);
    end;

    if IsFlyingUnit(p_Unit) then
      StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_MOVE', @ThisSpot, 1)
    else
      StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Move_Ground, @ThisSpot, 1, 0, 0);

    if IsFlyingUnit(p_Unit) then
      StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_UNLOAD', @ThisSpot, 1)
    else
      StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Ground_Unload, @ThisSpot, 1, 0, 0);
  end;

  ClearLoadedCargoList;

  if IsFlyingUnit(p_Unit) then
    StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_MOVE', @ReturnPos, 1)
  else
    StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Move_Ground, @ReturnPos, 1, 0, 0);

  if IsFlyingUnit(p_Unit) then
    StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_PATROL', @SourceMovePos, 1)
  else
    StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Patrol, @SourceMovePos, 1, 0, 0);

end;

function PortalAutoLoadPhase(p_Unit: PUnitStruct; const Candidates: TUnitPtrArray): Boolean;
var
  SourceMovePos: TPosition;
  i: Integer;
  StepResult: LongInt;
begin
  Result := False;
  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) or (not SourcePos.Active) or
     (Length(Candidates) = 0) then
    Exit;

  SourceMovePos.X := Integer(SourcePos.X) * 65536;
  SourceMovePos.Z := Integer(SourcePos.Z) * 65536;
  SourceMovePos.Y := Integer(SourcePos.Y) * 65536;

  ClearLoadedCargoList;

  if IsFlyingUnit(p_Unit) then
    StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_MOVE', @SourceMovePos, 0)
  else
    StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Move_Ground, @SourceMovePos, 0, 0, 0);

  for i := 0 to High(Candidates) do
  begin
    if IsFlyingUnit(p_Unit) then
      StepResult := IssueScriptOrder(p_Unit, Candidates[i], 'VTOL_PICKUP', nil, 1)
    else
      StepResult := TAUnit.CreateMainOrder(p_Unit, Candidates[i], Action_Ground_Pickup, nil, 1, 0, 0);
    AddLoadedCargo(TAUnit.GetId(Candidates[i]));
  end;

  if IsFlyingUnit(p_Unit) then
    StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_PATROL', @SourceMovePos, 1)
  else
    StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Patrol, @SourceMovePos, 1, 0, 0);

  Result := True;
end;

function PortalAutoDeliverPhase(p_Unit: PUnitStruct; LoadedCount: Integer;
  QueueFirst: Boolean = False): Boolean;
var
  SourceMovePos, DestMovePos, ReturnPos, ThisSpot: TPosition;
  UnloadSpots: TPositionArray;
  i, SpotIdx, RepeatPass: Integer;
  StepResult: LongInt;
begin
  Result := False;
  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) or (not SourcePos.Active) or
     (not DestPos.Active) or (LoadedCount <= 0) then
    Exit;

  SourceMovePos.X := Integer(SourcePos.X) * 65536;
  SourceMovePos.Z := Integer(SourcePos.Z) * 65536;
  SourceMovePos.Y := Integer(SourcePos.Y) * 65536;
  DestMovePos.X := Integer(DestPos.X) * 65536;
  DestMovePos.Z := Integer(DestPos.Z) * 65536;
  DestMovePos.Y := Integer(DestPos.Y) * 65536;
  ReturnPos.X := SourceMovePos.X + (40 * 65536);
  ReturnPos.Z := SourceMovePos.Z + (40 * 65536);
  ReturnPos.Y := SourceMovePos.Y;

  UnloadSpots := FindMultipleValidUnloadSpots(p_Unit, DestMovePos, LoadedCount);
  if Length(UnloadSpots) = 0 then
  begin
    Exit;
  end;

  for i := 0 to LoadedCount - 1 do
  begin
    SpotIdx := i mod Length(UnloadSpots);
    ThisSpot := UnloadSpots[SpotIdx];
    RepeatPass := i div Length(UnloadSpots);
    if RepeatPass > 0 then
    begin
      ThisSpot.X := ThisSpot.X + (RepeatPass * 20 * 65536);
      ThisSpot.Z := ThisSpot.Z + (RepeatPass * 20 * 65536);
    end;

    if IsFlyingUnit(p_Unit) then
      StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_MOVE', @ThisSpot, Ord((i > 0) or QueueFirst))
    else
      StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Move_Ground, @ThisSpot, Ord((i > 0) or QueueFirst), 0, 0);

    if IsFlyingUnit(p_Unit) then
      StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_UNLOAD', @ThisSpot, 1)
    else
      StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Ground_Unload, @ThisSpot, 1, 0, 0);
  end;

  if IsFlyingUnit(p_Unit) then
    StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_MOVE', @ReturnPos, 1)
  else
    StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Move_Ground, @ReturnPos, 1, 0, 0);
  if IsFlyingUnit(p_Unit) then
    StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_PATROL', @SourceMovePos, 1)
  else
    StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Patrol, @SourceMovePos, 1, 0, 0);

  Result := True;
end;

function TransportAlive(p_Unit: PUnitStruct): Boolean;
begin
  Result := (p_Unit <> nil) and (p_Unit.p_UNITINFO <> nil) and (p_Unit.p_Owner <> nil) and
            (p_Unit.nHealth > 0) and
            ((p_Unit.lUnitStateMask and UnitSelectState[UnitValid2_State]) = UnitSelectState[UnitValid2_State]);
end;

procedure FerryShutdown(const Why: String);
begin
  if AutoLoopEnabled or SourcePos.Active or DestPos.Active then
    ;
  AutoLoopEnabled := False;
  AutoLoopPhase := 0;
  StragglerCheckPending := False;
  FullWaitStartTick := 0;
  HoverPending := False;
  SourcePos.Active := False;
  DestPos.Active := False;
end;

function TransportCapacityStr(p_Unit: PUnitStruct): String;
begin
  Result := IntToStr(TAUnit.GetLoadCurAmount(p_Unit)) + '/' + IntToStr(p_Unit.p_UNITINFO.cTransportCap);
end;

function TransportWouldBeFull(p_Unit: PUnitStruct; ExtraCount, ExtraWeight: Integer): Boolean;
var
  Cap, WeightCap: Integer;
begin
  Cap := p_Unit.p_UNITINFO.cTransportCap;
  Result := (Cap > 0) and ((TAUnit.GetLoadCurAmount(p_Unit) + ExtraCount) >= Cap);
  if Result then Exit;
  WeightCap := 0;
  if p_Unit.p_UNITINFO.nCategory <= High(UnitInfoCustomFields) then
    WeightCap := UnitInfoCustomFields[p_Unit.p_UNITINFO.nCategory].TransportWeightCapacity;
  if WeightCap > 0 then
    Result := (TAUnit.GetLoadWeight(p_Unit) + ExtraWeight) * 100 >= WeightCap * FerryFullWeightPct(p_Unit);
end;

function FullLoadWaitTimedOut(p_Unit: PUnitStruct): Boolean;
begin
  Result := (FerryFullTimeout(p_Unit) > 0) and (FullWaitStartTick <> 0) and
            ((GetTickCount - FullWaitStartTick) >= Cardinal(Min(FerryFullTimeout(p_Unit), 3600)) * 1000);
end;

function ReadyToDispatch(p_Unit: PUnitStruct): Boolean;
begin
  Result := (FerryWaitFull(p_Unit) = 0) or TransportWouldBeFull(p_Unit, 0, 0) or FullLoadWaitTimedOut(p_Unit);
end;

function AutoLoopThreadProc(Param: Pointer): Integer; stdcall;

var
  p_Unit: PUnitStruct;
  IsReady: Boolean;
  Candidates: TUnitPtrArray;
  StragglerCount, LoadedCount: Integer;
  CandWeight, CandIdx: Integer;
  StragglerSpot, SourceHoldPos: TPosition;
  StepResult: LongInt;
begin
  Result := 0;

  while AutoLoopThreadActive do
  begin
    Sleep(Cfg_AutoLoopPollMs);
    if not AutoLoopThreadActive then
      Break;

    try

      if not AutoLoopEnabled then
        Continue;

      p_Unit := TAUnit.Id2Ptr(AutoLoopUnitId);
      if not TransportAlive(p_Unit) then
      begin
        FerryShutdown('tracked transport #' + IntToStr(AutoLoopUnitId) + ' died / no longer valid');
        Continue;
      end;

      if p_Unit.p_MainOrder = nil then

      else
        ;

      IsReady := (p_Unit.p_MainOrder = nil) or
                 (p_Unit.p_MainOrder.cOrderType = Ord(Action_Patrol)) or
                 (p_Unit.p_MainOrder.cOrderType = Ord(Action_VTOL_Patrol)) or
                 (p_Unit.p_MainOrder.cOrderType = Ord(Action_VTOL_Standby)) or
                 (p_Unit.p_MainOrder.cOrderType = Ord(Action_Ready));
      if not IsReady then
      begin
        Continue;
      end;

      if AutoLoopPhase = 2 then
      begin
        AutoLoopPhase := 0;
        StragglerCheckPending := True;
        FullWaitStartTick := 0;
      end;

      if AutoLoopPhase = 1 then
      begin
        LoadedCount := TAUnit.GetLoadCurAmount(p_Unit);
        AutoLoopPhase := 0;
        if LoadedCount > 0 then
        begin
          if ReadyToDispatch(p_Unit) then
          begin
            if PortalAutoDeliverPhase(p_Unit, LoadedCount) then
            begin
              AutoLoopPhase := 2;
              FullWaitStartTick := 0;
            end;
          end else
          begin
            if FullWaitStartTick = 0 then FullWaitStartTick := GetTickCount;
          end;
        end;
        Continue;
      end;

      if StragglerCheckPending then
      begin
        StragglerCount := TAUnit.GetLoadCurAmount(p_Unit);
        if StragglerCount > 0 then
        begin

          if FindNearestValidUnloadSpot(p_Unit, p_Unit.Position, StragglerSpot) then
          begin
            if IsFlyingUnit(p_Unit) then
            begin
              StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_MOVE', @StragglerSpot, 0);
              StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_UNLOAD', @StragglerSpot, 1);
            end else
            begin
              StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Move_Ground, @StragglerSpot, 0, 0, 0);
              StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Ground_Unload, @StragglerSpot, 1, 0, 0);
            end;

            if SourcePos.Active then
            begin
              SourceHoldPos.X := Integer(SourcePos.X) * 65536;
              SourceHoldPos.Z := Integer(SourcePos.Z) * 65536;
              SourceHoldPos.Y := Integer(SourcePos.Y) * 65536;
              if IsFlyingUnit(p_Unit) then
                IssueScriptOrder(p_Unit, nil, 'VTOL_PATROL', @SourceHoldPos, 1)
              else
                TAUnit.CreateMainOrder(p_Unit, nil, Action_Patrol, @SourceHoldPos, 1, 0, 0);
            end;
          end else
            ;

          Continue;
        end;
        StragglerCheckPending := False;
      end;

      LoadedCount := TAUnit.GetLoadCurAmount(p_Unit);
      Candidates := FindLoadableUnitsNearSource(p_Unit, FerryPickupRadius(p_Unit));
      CandWeight := 0;
      for CandIdx := 0 to High(Candidates) do
        CandWeight := CandWeight + Round(Candidates[CandIdx].p_UNITINFO.lBuildCostMetal);

      if (FerryWaitFull(p_Unit) = 1) and (not FullLoadWaitTimedOut(p_Unit)) and
         (not TransportWouldBeFull(p_Unit, Length(Candidates), CandWeight)) then
      begin
        if FullWaitStartTick = 0 then FullWaitStartTick := GetTickCount;
        Continue;
      end;

      if Length(Candidates) = 0 then
      begin
        if LoadedCount > 0 then
        begin

          ;
          if PortalAutoDeliverPhase(p_Unit, LoadedCount) then
          begin
            AutoLoopPhase := 2;
            FullWaitStartTick := 0;
          end;
        end else
          ;
        Continue;
      end;

      if PortalAutoLoadPhase(p_Unit, Candidates) then
        AutoLoopPhase := 1;
    except
      on E: Exception do
        ;
    end;
  end;

end;

function StartAutoLoopForUnit(p_Unit: PUnitStruct): Boolean;
var
  ThreadId: Cardinal;
begin
  Result := False;

  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
  begin
    Exit;
  end;
  if not SourcePos.Active then
  begin
    Exit;
  end;
  if not DestPos.Active then
  begin
    Exit;
  end;

  AutoLoopUnitId := TAUnit.GetId(p_Unit);
  AutoLoopPhase := 0;
  StragglerCheckPending := False;
  FullWaitStartTick := 0;
  AutoLoopEnabled := True;

  if AutoLoopThreadHandle = 0 then
  begin
    AutoLoopThreadActive := True;
    AutoLoopThreadHandle := CreateThread(nil, 0, @AutoLoopThreadProc, nil, 0, ThreadId);
    if AutoLoopThreadHandle = 0 then
    begin
      AutoLoopThreadActive := False;
      AutoLoopEnabled := False;
      Exit;
    end;
  end;

  Result := True;
end;

procedure IssueHoverMove(p_Unit: PUnitStruct);
var
  OrderName: String;
  HoverPos: TPosition;
  StepResult: LongInt;
begin
  HoverPos := p_Unit.Position;
  HoverPos.X := HoverPos.X + FerryHoverOffset(p_Unit) * 65536;
  if (HoverPos.X div 65536) > (TAData.MainStruct.TNTMemStruct.lMapWidth - 32) then
    HoverPos.X := p_Unit.Position.X - FerryHoverOffset(p_Unit) * 65536;
  if FerryHoverOrder(p_Unit) = 1 then
    OrderName := 'VTOL_PATROL'
  else
    OrderName := 'VTOL_MOVE';
  StepResult := IssueScriptOrder(p_Unit, nil, OrderName, @HoverPos, 0);
end;

procedure FireHoverIfPending(Force: Boolean);
var
  p: PUnitStruct;
begin
  if not HoverPending then Exit;
  if (not Force) and (TAData.GameTime < HoverDueTime) then Exit;
  HoverPending := False;
  p := TAUnit.Id2Ptr(HoverUnitId);
  if TransportAlive(p) then
    IssueHoverMove(p);
end;

procedure PortalOnOff_Tick;
begin
  try
    if TAData.MainStruct <> nil then
      FireHoverIfPending(False);
  except
    on E: Exception do ;
  end;
end;

procedure PortalOnOff_BeginForUnit(p_Unit: PUnitStruct);
var
  UnitId: Word;
begin
  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
    Exit;
  UnitId := TAUnit.GetId(p_Unit);

  if AutoLoopEnabled and (AutoLoopUnitId = UnitId) then
  begin
    AutoLoopEnabled := False;
    AutoLoopPhase := 0;
  end;

  SourcePos.X := TAUnit.GetUnitX(p_Unit);
  SourcePos.Z := TAUnit.GetUnitZ(p_Unit);
  SourcePos.Y := TAUnit.GetUnitY(p_Unit);
  SourcePos.Active := True;
  SelectedUnitId := UnitId;

  if (Cfg_OnOffHoverLiftOff = 1) and IsFlyingUnit(p_Unit) then
  begin
    HoverPending := True;
    HoverUnitId := UnitId;
    HoverDueTime := TAData.GameTime + Cfg_OnOffHoverDelayTicks;
  end;

  ChatMsg('Auto transport enabled: ' + String(p_Unit.p_UNITINFO.szName));
end;

function PortalOnOff_DispatchToTarget(p_Unit: PUnitStruct; const Target: TPosition): Boolean;
var
  TX, TZ, TY, MapW, MapH, Loaded: Integer;
  Delivered: Boolean;
begin
  Result := False;
  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
  begin
    Exit;
  end;

  TX := Target.X div 65536;
  TZ := Target.Z div 65536;
  TY := Target.Y div 65536;
  if TY < 0 then TY := 0;

  MapW := TAData.MainStruct.TNTMemStruct.lMapWidth;
  MapH := TAData.MainStruct.TNTMemStruct.lMapHeight;
  if (TX <= 0) or (TZ <= 0) or ((MapW > 0) and (TX > MapW)) or ((MapH > 0) and (TZ > MapH)) then
  begin
    Exit;
  end;

  if not SourcePos.Active then
  begin
    SourcePos.X := TAUnit.GetUnitX(p_Unit);
    SourcePos.Z := TAUnit.GetUnitZ(p_Unit);
    SourcePos.Y := TAUnit.GetUnitY(p_Unit);
    SourcePos.Active := True;
  end;

  DestPos.X := Word(TX);
  DestPos.Z := Word(TZ);
  DestPos.Y := Word(TY);
  DestPos.Active := True;
  SelectedUnitId := TAUnit.GetId(p_Unit);

  Loaded := TAUnit.GetLoadCurAmount(p_Unit);

  FireHoverIfPending(True);

  Delivered := (Loaded > 0) and ReadyToDispatch(p_Unit) and
               PortalAutoDeliverPhase(p_Unit, Loaded, FerryHoverOrder(p_Unit) = 0);

  if not StartAutoLoopForUnit(p_Unit) then
  begin
    Exit;
  end;
  if Delivered then
    AutoLoopPhase := 2;

  Result := True;
end;

procedure PortalOnOff_StopForUnit(p_Unit: PUnitStruct);
begin
  if p_Unit = nil then Exit;
  if (AutoLoopEnabled and (AutoLoopUnitId = TAUnit.GetId(p_Unit))) or
     ((not AutoLoopEnabled) and (SelectedUnitId = TAUnit.GetId(p_Unit))) then
    FerryShutdown('switched OFF on ' + UnitDisplayName(p_Unit));
end;

function PortalOnOff_TransportAlive(p_Unit: PUnitStruct): Boolean;
begin
  Result := TransportAlive(p_Unit);
end;

procedure PortalOnOff_GetOverlay(out Info: TPortalOverlayInfo);
var
  p: PUnitStruct;
begin
  FillChar(Info, SizeOf(Info), 0);
  if AutoLoopEnabled and not TransportAlive(TAUnit.Id2Ptr(AutoLoopUnitId)) then
    FerryShutdown('transport #' + IntToStr(AutoLoopUnitId) + ' died (seen by overlay)');
  Info.LoopRunning := AutoLoopEnabled;
  Info.TransportId := AutoLoopUnitId;
  Info.SrcOn := SourcePos.Active;
  Info.SrcX := SourcePos.X;  Info.SrcY := SourcePos.Y;  Info.SrcZ := SourcePos.Z;
  Info.DstOn := DestPos.Active;
  Info.DstX := DestPos.X;    Info.DstY := DestPos.Y;    Info.DstZ := DestPos.Z;

  p := nil;
  if AutoLoopEnabled then p := TAUnit.Id2Ptr(AutoLoopUnitId)
  else if SelectedUnitId <> 0 then p := TAUnit.Id2Ptr(SelectedUnitId);
  Info.PickupRadius := FerryPickupRadius(p);
  Info.DropRadius := FerryDropRadius(p);
  Info.BeaconAnim := FerryBeaconAnim(p);
  if AutoLoopEnabled then
  begin
    p := TAUnit.Id2Ptr(AutoLoopUnitId);
    if (p <> nil) and (p.p_UNITINFO <> nil) then
    begin
      Info.Aboard := TAUnit.GetLoadCurAmount(p);
      Info.Capacity := p.p_UNITINFO.cTransportCap;
      Info.WaitingFull := (AutoLoopPhase <> 2) and (FerryWaitFull(p) = 1) and
                          not TransportWouldBeFull(p, 0, 0);
    end;
  end;
end;

function PortalOnOff_StatusLine: String;
begin
  Result := 'loop=' + BoolToStr(AutoLoopEnabled, True) +
    ' unit=' + IntToStr(AutoLoopUnitId) +
    ' phase=' + IntToStr(AutoLoopPhase) +
    ' src=' + BoolToStr(SourcePos.Active, True) + '(' + IntToStr(SourcePos.X) + ',' + IntToStr(SourcePos.Z) + ')' +
    ' dst=' + BoolToStr(DestPos.Active, True) + '(' + IntToStr(DestPos.X) + ',' + IntToStr(DestPos.Z) + ')';
end;

initialization
  SelectedUnitId := 0;

  SourcePos.Active := False;
  SourcePos.X := 0;
  SourcePos.Z := 0;
  SourcePos.Y := 0;
  SourcePos.Name := 'Source';

  DestPos.Active := False;
  DestPos.X := 0;
  DestPos.Z := 0;
  DestPos.Y := 0;
  DestPos.Name := 'Destination';

  Pointer(@Map_ScreenToWorldClick) := Pointer($00498DA0);

finalization

  AutoLoopEnabled := False;
  AutoLoopThreadActive := False;
  if AutoLoopThreadHandle <> 0 then
  begin

    WaitForSingleObject(AutoLoopThreadHandle, 4000);
    CloseHandle(AutoLoopThreadHandle);
    AutoLoopThreadHandle := 0;
  end;

end.
