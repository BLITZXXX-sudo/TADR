unit UnitActions;

interface
uses
  PluginEngine;

const
  State_UnitActions: Boolean = True;

function GetPlugin: TPluginData;

Procedure OnInstallUnitActions;
Procedure OnUninstallUnitActions;

procedure RemoveBuildQueuesFromSelected;

implementation
uses
  SysUtils,
  IniOptions,
  idplay,
  UnitInfoExpand,
  UnitSearchHandlers,
  TA_MemoryConstants,
  TA_MemoryStructures,
  TA_MemoryLocations,
  TA_MemPlayers,
  TA_MemUnits,
  TA_MemPlotData,
  TA_FunctionsU,
  GUIEnhancements,
  OnOffPortal;

var
  DiagLoggedShieldRangeSeen: Boolean = False;
  DiagLoggedShieldArmoredState: Boolean = False;
  DiagLoggedShieldUnitInfoFields: Boolean = False;

const
  MAX_PORTAL_SCAN_ATTEMPTS = 8;

var
  DiagPortalScanCallCount: Integer = 0;

procedure UnitActions_ExtraVTOLOrders;
label
  AirUnitChase,
  GroundMovementChase;
asm
  test    dh, 8
  jnz     AirUnitChase
  jmp GroundMovementChase
AirUnitChase :
  pushAD
  push    2
  push    eax
  call    GetUnitInfoProperty
  test    eax, eax
  popAD
  jnz     GroundMovementChase
  push $00438B60;
  call PatchNJump;
GroundMovementChase :
  push $00438AE8;
  call PatchNJump;
end;

function SetCursorNewOrders(ActionType: Integer;
  OrderUnit: PUnitStruct; TargetUnit: PUnitStruct; TargetPosition: PPosition): Integer; stdcall;
var
  ReturnVal : Integer;
  Distance : Integer;
  InDistance : Boolean;
  CanTeleport : Boolean;
begin
  ReturnVal := 0;
  case ActionType of
    BUTTON_ORDER_TELEPORTNEW-1 :
      begin
        ReturnVal := 14;
        if TAUnit.AtMouse = nil then
        begin
          Distance := TAMem.DistanceBetweenPos(@OrderUnit.Position, TargetPosition);
          InDistance := (Distance <= UnitInfoCustomFields[OrderUnit.p_UnitInfo.nCategory].TeleportMaxDistance) and
            (Distance >= UnitInfoCustomFields[OrderUnit.p_UnitInfo.nCategory].TeleportMinDistance);
          CanTeleport := InDistance;
          if UnitInfoCustomFields[OrderUnit.p_UnitInfo.nCategory].TeleportToLoSOnly then
            CanTeleport := CanTeleport and TAMap.PositionInLOS(OrderUnit.p_Owner, TargetPosition);
          if CanTeleport then
            ReturnVal := 9;
        end;
      end;
  end;
  Result := ReturnVal;
end;

procedure UnitActions_AllowOrderType;
label
  custom_or_default_order,
  default_order;
asm
  cmp     eax, 0Dh
  ja      custom_or_default_order
  push $0043E4FE;
  call PatchNJump;
custom_or_default_order:

  push    ecx
  push    edx
  push    ebx
  push    esi
  push    edi

  mov     ebx, [esp+38h]
  push    ebx
  push    edi
  push    edx
  push    eax
  call    SetCursorNewOrders

  pop     edi
  pop     esi
  pop     ebx
  pop     edx
  pop     ecx

  test    eax, eax
  jz      default_order
  push $0043EA5A;
  call PatchNJump;
default_order:
  push $0043F098;
  call PatchNJump;
end;

function UnitActions_AllowOrderType_Action2Index(ActionType: Byte;
  OrderUnit, TargetUnit: PUnitStruct; TargetPosition: PPosition): Byte; stdcall;
var
  Distance: Integer;
begin
  Result := 0;
  case ActionType of
    BUTTON_ORDER_TELEPORTNEW-1 :
      begin
        if OrderUnit.p_UnitInfo.cBMCode = 1 then
          if (OrderUnit.p_UnitInfo.UnitTypeMask and (1 shl 11)) <> 0 then
            Result := TAMem.ScriptActionName2Index('VTOL_MOVE')
          else
            Result := TAMem.ScriptActionName2Index('MOVE_GROUND');
        if (UnitInfoCustomFields[OrderUnit.p_UnitInfo.nCategory].TeleportMethod <> tmNone) and
           (UnitsCustomFields[TAUnit.GetId(OrderUnit)].TeleportReloadCur = 0) then
        begin
          Distance := TAMem.DistanceBetweenPos(@OrderUnit.Position, TargetPosition);
          if (Distance <= UnitInfoCustomFields[OrderUnit.p_UnitInfo.nCategory].TeleportMaxDistance) and
             (Distance >= UnitInfoCustomFields[OrderUnit.p_UnitInfo.nCategory].TeleportMinDistance) then
          begin
            if UnitInfoCustomFields[OrderUnit.p_UnitInfo.nCategory].TeleportToLoSOnly then
              if not TAMap.PositionInLOS(OrderUnit.p_Owner, TargetPosition) then Exit;
            case UnitInfoCustomFields[OrderUnit.p_UnitInfo.nCategory].TeleportMethod of
              tmSelf :
                if TAUnit.TestUnloadPosition(OrderUnit.p_UnitInfo, TargetPosition^) then
                  Result := TAMem.ScriptActionName2Index('TELEPORT');
              else
                Result := TAMem.ScriptActionName2Index('TELEPORT');
            end;
          end;
        end;
      end;
  end;
end;

procedure UnitActions_AllowOrderType_Action2IndexWrapper;
label
  custom_or_default_order,
  default_order;
asm
  cmp     ecx, 0Dh
  ja      custom_or_default_order
  push $0043F14D;
  call PatchNJump;
custom_or_default_order:

  push    ecx
  push    edx
  push    ebx
  push    esi
  push    edi

  mov     ebx, [esp+38h]
  push    ebx
  push    edi
  push    ebp
  push    ecx
  call    UnitActions_AllowOrderType_Action2Index

  pop     edi
  pop     esi
  pop     ebx
  pop     edx
  pop     ecx

  test    al, al
  jz      default_order
  mov     esi, [esp+14h]
  mov     [esi], al
  push $00440194;
  call PatchNJump;
default_order:
  push $004401DC;
  call PatchNJump;
end;

procedure RemoveBuildQueuesFromSelected;
var
  Player: PPlayerStruct;
  PlayerMaxUnitID: Cardinal;
  CurrentUnit: PUnitStruct;
  i: Cardinal;
begin
  Player := TAPlayer.GetPlayerByIndex(TAData.LocalPlayerID);
  PlayerMaxUnitID := Player.nNumUnits;
  for i := 0 to PlayerMaxUnitID do
  begin
    CurrentUnit := Pointer(Cardinal(Player.p_UnitsArray) + i * SizeOf(TUnitStruct));
    if ((CurrentUnit.lUnitStateMask and UnitSelectState[UnitSelected_State]) = UnitSelectState[UnitSelected_State]) then
    begin
      if (CurrentUnit.fBuildTimeLeft <> 0.0) or
         (CurrentUnit.p_Owner = nil) or
         (CurrentUnit.p_UnitInfo = nil) then
        Continue;

      if (CurrentUnit.p_UnitInfo.cBMCode <> 0) then
        Continue;

      if (TAUnit.GetUnitInfoField(CurrentUnit, uiBUILDER) = 0) then
         Continue
      else begin
        ORDERS_RemoveAllBuildQueues(CurrentUnit, True);
        UpdateIngameGUI(0);
      end;
    end;
  end;
end;

procedure CallActionScriptForSelected;
var
  Player: PPlayerStruct;
  PlayerMaxUnitID: Cardinal;
  CurrentUnit: PUnitStruct;
  i: Cardinal;
begin
  Player := TAPlayer.GetPlayerByIndex(TAData.LocalPlayerID);
  PlayerMaxUnitID := Player.nNumUnits;
  for i := 0 to PlayerMaxUnitID do
  begin
    CurrentUnit := Pointer(Cardinal(Player.p_UnitsArray) + i * SizeOf(TUnitStruct));
    if ((CurrentUnit.lUnitStateMask and UnitSelectState[UnitSelected_State]) = UnitSelectState[UnitSelected_State]) then
    begin
      if (CurrentUnit.fBuildTimeLeft <> 0.0) or
         (CurrentUnit.p_Owner = nil) or
         (CurrentUnit.p_UnitInfo = nil) then Continue;
      TAUnit.CobStartScript(CurrentUnit, 'ActionButtonPressed', nil, nil, nil, nil, True);
    end;
  end;
end;

function UnitActions_NewOrdersButtons(a2, v3, v4: Cardinal) : Integer; stdcall;
var
  DestStr: array[0..15] of AnsiChar;
  OrderName: String;
  ActionIndex: Byte;
label
  buildspot_state,
  play_immediateorders_return,
  play_specialorders_return;
begin
  OrderName := GetPrepareOrderName(a2, @DestStr, v3);

  if ( Pos('MOVE', OrderName) <> 0 ) then
  begin
    if ( PWord(v4 + $138)^ <> 0) then
    begin
      TAData.MainStruct.ucPrepareOrderType := BUTTON_ORDER_MOVE;
      TAData.MainStruct.cBuildSpotState :=
        TAData.MainStruct.cBuildSpotState and $F7;
      PlaySound_2D_Name(PAnsiChar(IMMEDIATEORDERS), 0);
      Result := 1;
      Exit;
    end;
    TAData.MainStruct.ucPrepareOrderType := BUTTON_ORDER_STOP;
    goto buildspot_state;
  end;

  if ( Pos('STOP', OrderName) <> 0 ) then
  begin

    OnOffPortal_StopButtonPressed;
    TAData.MainStruct.ucPrepareOrderType := BUTTON_ORDER_STOP;
    TAData.MainStruct.cBuildSpotState :=
        TAData.MainStruct.cBuildSpotState and $F7;

    if IniSettings.StopButton then
      RemoveBuildQueuesFromSelected;

    ActionIndex := TAMem.ScriptActionName2Index(PAnsiChar('STOP'));
    MOUSE_EVENT_2UnitOrder(@TAData.MainStruct.CurtMousePosition, 0, ActionIndex, 0, 0, 0);
play_immediateorders_return:
    PlaySound_2D_Name(PAnsiChar(IMMEDIATEORDERS), 0);
    Result := 1;
    Exit;
  end;

  if ( Pos('ATTACK', OrderName) <> 0 ) then
  begin
    if ( PWord(v4 + $138)^ <> 0) then
    begin
      TAData.MainStruct.ucPrepareOrderType := BUTTON_ORDER_ATTACK;
      TAData.MainStruct.cBuildSpotState :=
        TAData.MainStruct.cBuildSpotState and $F7;
      PlaySound_2D_Name(PAnsiChar(IMMEDIATEORDERS), 0);
      Result := 1;
      Exit;
    end;
    TAData.MainStruct.ucPrepareOrderType := BUTTON_ORDER_STOP;
    goto buildspot_state;
  end;

  if ( Pos('BLAST', OrderName) <> 0 ) then
  begin
    if ( PWord(v4 + $138)^ <> 0) then
    begin
      TAData.MainStruct.ucPrepareOrderType := BUTTON_ORDER_BLAST;
      TAData.MainStruct.cBuildSpotState :=
        TAData.MainStruct.cBuildSpotState and $F7;
      PlaySound_2D_Name(PAnsiChar(IMMEDIATEORDERS), 0);
      Result := 1;
      Exit;
    end;
    TAData.MainStruct.ucPrepareOrderType := BUTTON_ORDER_STOP;
    goto play_specialorders_return;
  end;

  if ( Pos('DEFEND', OrderName) <> 0 ) then
  begin
    if ( PWord(v4 + $138)^ <> 0) then
    begin
      TAData.MainStruct.ucPrepareOrderType := BUTTON_ORDER_DEFEND;
      TAData.MainStruct.cBuildSpotState :=
        TAData.MainStruct.cBuildSpotState and $F7;
      PlaySound_2D_Name(PAnsiChar(IMMEDIATEORDERS), 0);
      Result := 1;
      Exit;
    end;
    TAData.MainStruct.ucPrepareOrderType := BUTTON_ORDER_STOP;
    goto buildspot_state;
  end;

  if ( Pos('REPAIR', OrderName) <> 0 ) then
  begin
    if ( PWord(v4 + $138)^ <> 0) then
    begin
      TAData.MainStruct.ucPrepareOrderType := BUTTON_ORDER_REPAIR;
      TAData.MainStruct.cBuildSpotState :=
        TAData.MainStruct.cBuildSpotState and $F7;
      PlaySound_2D_Name(PAnsiChar(SPECIALORDERS), 0);
      Result := 1;
      Exit;
    end;
    TAData.MainStruct.ucPrepareOrderType := BUTTON_ORDER_STOP;
    goto play_specialorders_return;
  end;

  if ( Pos('PATROL', OrderName) <> 0 ) then
  begin
    if ( PWord(v4 + $138)^ <> 0) then
    begin
      TAData.MainStruct.ucPrepareOrderType := BUTTON_ORDER_PATROL;
      TAData.MainStruct.cBuildSpotState :=
        TAData.MainStruct.cBuildSpotState and $F7;
      PlaySound_2D_Name(PAnsiChar(IMMEDIATEORDERS), 0);
      Result := 1;
      Exit;
    end;
    TAData.MainStruct.ucPrepareOrderType := BUTTON_ORDER_STOP;
    goto buildspot_state;
  end;

  if ( Pos('RECLAIM', OrderName) <> 0 ) then
  begin
    if ( PWord(v4 + $138)^ <> 0) then
    begin
      TAData.MainStruct.ucPrepareOrderType := BUTTON_ORDER_RECLAIM;
      TAData.MainStruct.cBuildSpotState :=
        TAData.MainStruct.cBuildSpotState and $F7;
      PlaySound_2D_Name(PAnsiChar(SPECIALORDERS), 0);
      Result := 1;
      Exit;
    end;
    TAData.MainStruct.ucPrepareOrderType := BUTTON_ORDER_STOP;
    goto play_specialorders_return;
  end;

  if ( Pos('CAPTURE', OrderName) <> 0 ) then
  begin
    if ( PWord(v4 + $138)^ <> 0) then
    begin
      TAData.MainStruct.ucPrepareOrderType := BUTTON_ORDER_CAPTURE;
      TAData.MainStruct.cBuildSpotState :=
        TAData.MainStruct.cBuildSpotState and $F7;
      PlaySound_2D_Name(PAnsiChar(SPECIALORDERS), 0);
      Result := 1;
      Exit;
    end;
    TAData.MainStruct.ucPrepareOrderType := BUTTON_ORDER_STOP;
    goto play_specialorders_return;
  end;

  if ( Pos('TELEPORT', OrderName) <> 0 ) then
  begin
    if ( PWord(v4 + $138)^ <> 0) then
    begin
      TAData.MainStruct.ucPrepareOrderType := BUTTON_ORDER_TELEPORTNEW;
      TAData.MainStruct.cBuildSpotState :=
        TAData.MainStruct.cBuildSpotState and $F7;
      PlaySound_2D_Name(PAnsiChar(IMMEDIATEORDERS), 0);
      Result := 1;
      Exit;
    end;
    TAData.MainStruct.ucPrepareOrderType := BUTTON_ORDER_STOP;
    goto buildspot_state;
  end;

  if ( Pos('UNLOAD', OrderName) <> 0 ) then
  begin
    if ( PWord(v4 + $138)^ <> 0) then
      TAData.MainStruct.ucPrepareOrderType := BUTTON_ORDER_UNLOAD
    else
      TAData.MainStruct.ucPrepareOrderType := BUTTON_ORDER_STOP;
play_specialorders_return:
    TAData.MainStruct.cBuildSpotState :=
      TAData.MainStruct.cBuildSpotState and $F7;
    PlaySound_2D_Name(PAnsiChar(SPECIALORDERS), 0);
    Result := 1;
    Exit;
  end;

  if ( Pos('LOAD', OrderName) <> 0 ) then
  begin
    if ( PWord(v4 + $138)^ <> 0) then
      TAData.MainStruct.ucPrepareOrderType := BUTTON_ORDER_LOAD
    else
      TAData.MainStruct.ucPrepareOrderType := BUTTON_ORDER_STOP;
buildspot_state:
    TAData.MainStruct.cBuildSpotState :=
      TAData.MainStruct.cBuildSpotState and $F7;
    goto play_immediateorders_return;
  end;

  if ( Pos('ACTIONBUTTON', OrderName) <> 0 ) then
  begin
    CallActionScriptForSelected;
    PlaySound_2D_Name(PAnsiChar(IMMEDIATEORDERS), 0);
  end;
  Result := 0;
end;

procedure UnitActions_NewOrdersButtonsWrapper;
label
  return;
asm
  push    edx
  push    ecx
  push    ebp
  push    eax
  push    esi
  call    UnitActions_NewOrdersButtons
return:
  pop     ecx
  pop     edx
  push $0041A0FB;
  call PatchNJump;
end;

procedure Portal_AutoResurrectScan(p_Unit: PUnitStruct);
var
  UnitId: Word;
  BuildDist: Integer;
  MetalFeaturePosition: TPosition;
  p_MetalFeaturePosition: Pointer;
  EnergyFeaturePosition: TPosition;
  p_EnergyFeaturePosition: Pointer;
  FeatureEnergy: Single;
  FeatureMetal: Single;
  FeatureTypeID: Word;
  WreckTypeName: String;
  WreckUnitInfoID: Word;
  p_PushedOrderMem: Pointer;
  p_PushedOrder: PUnitOrder;
  OrderActionIdx: Byte;
  bSearchFound: Boolean;
  bCanResurrect: LongWord;
  SearchDist: Integer;
  RejectedDist: Integer;
  ScanAttempt: Integer;
  bFoundValidWreck: Boolean;
begin
  UnitId := TAUnit.GetId(p_Unit);

  if UnitsCustomFields[UnitId].ResurrectScanCooldown > 0 then
  begin
    Dec(UnitsCustomFields[UnitId].ResurrectScanCooldown);
    Exit;
  end;
  UnitsCustomFields[UnitId].ResurrectScanCooldown := 90;

  if p_Unit.p_MovementClass <> nil then Exit;

  bCanResurrect := TAUnit.GetUnitInfoField(p_Unit, uiCanResurrect);
  if bCanResurrect = 0 then Exit;

  Inc(DiagPortalScanCallCount);

  if p_Unit.p_MainOrder <> nil then
  begin
    if DiagPortalScanCallCount <= 2000 then
      ;
    Exit;
  end;

  BuildDist := p_Unit.p_UnitInfo.nBuildDistance;
  if BuildDist <= 0 then
  begin
    if DiagPortalScanCallCount <= 2000 then
      ;
    Exit;
  end;

  SearchDist := BuildDist;
  bFoundValidWreck := False;
  ScanAttempt := 0;

  while (not bFoundValidWreck) and (SearchDist > 0) and (ScanAttempt < MAX_PORTAL_SCAN_ATTEMPTS) do
  begin
    Inc(ScanAttempt);
    p_MetalFeaturePosition := @MetalFeaturePosition;
    p_EnergyFeaturePosition := @EnergyFeaturePosition;
    bSearchFound := SearchForReclamateFeatures(@p_Unit.Position, SearchDist shl 16,
        @p_EnergyFeaturePosition, @FeatureEnergy, @p_MetalFeaturePosition, @FeatureMetal);

    if DiagPortalScanCallCount <= 2000 then
      ;

    if (not bSearchFound) or (p_MetalFeaturePosition = nil) then
      Break;

    FeatureTypeID := GetFeatureTypeFromOrder(p_MetalFeaturePosition, nil, nil);

    if FeatureTypeID <> Word(-1) then
    begin
      WreckTypeName := StringReplace(TAMem.FeatureDefId2Ptr(FeatureTypeID).Name, '_', #0, []);
      WreckUnitInfoID := UNITINFO_Name2ID(PAnsiChar(WreckTypeName));

      if DiagPortalScanCallCount <= 2000 then
        ;

      if WreckUnitInfoID <> 0 then
      begin
        bFoundValidWreck := True;
        Break;
      end;
    end else
    begin
      if DiagPortalScanCallCount <= 2000 then
        ;
    end;

    RejectedDist := TAMem.DistanceBetweenPos(@p_Unit.Position, PPosition(p_MetalFeaturePosition));
    if RejectedDist <= 0 then Break;
    SearchDist := RejectedDist - 1;
  end;

  if not bFoundValidWreck then Exit;

  MetalFeaturePosition.Y := GetPosHeight(@MetalFeaturePosition) shl 16;
  p_PushedOrderMem := MEM_Alloc(SizeOf(TUnitOrder));
  if p_PushedOrderMem = nil then Exit;
  OrderActionIdx := TAMem.ScriptActionName2Index('RESURRECT');
  p_PushedOrder := ORDERS_CreateObject(0, 0, p_PushedOrderMem,
    0, 0, 0, @MetalFeaturePosition, nil, OrderActionIdx);
  ORDERS_PushOrder(p_Unit, p_PushedOrder);
end;

procedure ExtraDataReload(p_Unit: PUnitStruct); stdcall;
var
  UnitId: Cardinal;
  p_Shield: PUnitStruct;
  ShieldRange: Integer;
  TeleportReloadMax: Integer;
  UnitSearchCallbackRec: TUnitSearchCallbackRec;
begin
  UnitId := TAUnit.GetId(p_Unit);

  Portal_AutoResurrectScan(p_Unit);

  TeleportReloadMax := UnitsCustomFields[UnitId].TeleportReloadMax;
  if TeleportReloadMax <> 0 then
  begin
    if UnitsCustomFields[UnitId].TeleportReloadCur < TeleportReloadMax then
      Inc(UnitsCustomFields[UnitId].TeleportReloadCur)
    else
    begin
      UnitsCustomFields[UnitId].TeleportReloadMax := 0;
      UnitsCustomFields[UnitId].TeleportReloadCur := 0;
    end;
  end;

  p_Shield := UnitsCustomFields[UnitId].ShieldedBy;
  if p_Shield <> nil then
  begin
    ShieldRange := UnitsCustomFields[TAUnit.GetId(p_Shield)].ShieldRange;

    if (ShieldRange = 0) or
       not TAUnit.IsArmored(p_Shield) or
       (TAMem.DistanceBetweenPos(@p_Shield.Position, @p_Unit.Position) > ShieldRange) then
    begin
      UnitSearchCallbackRec.p_CallerUnit := nil;
      SetShield(nil, nil, UnitSearchCallbackRec, p_Unit);
    end;
  end;

  ShieldRange := UnitsCustomFields[UnitId].ShieldRange;
  if ShieldRange > 0 then
  begin

    if p_Unit.nUnitInfoID <= High(UnitInfoCustomFields) then

    else
      ;
    UnitSearchCallbackRec.p_CallerUnit := nil;
    if TAUnit.IsArmored(p_Unit) then
    begin
      UnitSearchCallbackRec.p_CallerUnit := p_Unit;
    end;
    UnitSearchCallbackRec.p_CallbackProc := @SetShieldHandler;
    UnitSearchCallbackRec.p_OwnerPtr := p_Unit.p_Owner;
    CallbackForUnitsInDistance(@p_Unit.Position, ShieldRange shl 16, @UnitSearchCallbackRec);
  end;
end;

procedure UnitActions_ExtraDataReload;
asm
  pushAD
  push    esi
  call    ExtraDataReload
  popAD
  mov     al, [esi+TUnitStruct.ucRecentDamage]
  push $0048ADF6;
  call PatchNJump;
end;

function AdvancedDefaultMission(p_Unit: PUnitStruct): PUnitOrder; stdcall;
var
  OrderMem: PUnitOrder;
  Position: TPosition;
  UnitInfoID: Word;
begin
  OrderMem := MEM_Alloc(SizeOf(TUnitOrder));
  if OrderMem <> nil then
  begin
    UnitInfoID := p_Unit.p_UnitInfo.nCategory;
    if UnitInfoCustomFields[UnitInfoID].DefaultMissionOrgPos then
      Position := p_Unit.Position
    else
      FillChar(Position, SizeOf(TPosition), 0);
    Result := ORDERS_CreateObject(0, 0, OrderMem, 0,
                                  0, 0, @Position, nil,
                                  p_Unit.p_UnitInfo.cDefMissionType);
  end else
    Result := nil;
end;

procedure UnitActions_AdvancedDefaultMission;
asm
  push    ebx
  push    edi
  call    AdvancedDefaultMission
  pop     ebx
  push $0043BA05;
  call PatchNJump;
end;

procedure UnitActions_DontHealTimeNotBuilt;
label
  dont_heal,
  heal;
asm
  fld     [esi+TUnitStruct.fBuildTimeLeft]
  fcomp   ds:$004FD748
  fnstsw  ax
  test    ah, 40h
  jz      dont_heal
heal :
  mov     ecx, [TaDynMemStructPtr]
  push $0048AF5E;
  call PatchNJump;
dont_heal :
  push $0048AF97;
  call PatchNJump;
end;

procedure UnitActions_AntiDamageShield(p_Projectile: PWeaponProjectile; p_AttackerUnit: PUnitStruct; p_TargetUnit: PUnitStruct;
  Amount: Integer; DamageType: Cardinal; Angle: Word); stdcall;
var
  TargetUnitId, UnitId: Word;
  p_Shield: PUnitStruct;
begin

  if (p_TargetUnit = nil) or (p_TargetUnit.p_UNITINFO = nil) or
     (p_TargetUnit.p_Owner = nil) then
    Exit;

  if (p_AttackerUnit <> nil) and (p_AttackerUnit.p_UNITINFO = nil) then
    p_AttackerUnit := nil;

  TargetUnitId := TAUnit.GetId(p_TargetUnit);

  p_Shield := UnitsCustomFields[TargetUnitId].ShieldedBy;

  if (p_Shield <> nil) and (p_Shield.p_UNITINFO = nil) then
  begin
    UnitsCustomFields[TargetUnitId].ShieldedBy := nil;
    p_Shield := nil;
  end;

  if (p_Shield <> nil) then
  begin
    if (p_AttackerUnit <> nil) then
    begin
      if TAUnit.IsAllied(p_AttackerUnit, TargetUnitId) = 1 then
        UNITS_MakeDamage(p_AttackerUnit, p_TargetUnit, Amount, DamageType, Angle)
      else
      begin

        if (TAUnit.GetUnitInfoField(p_AttackerUnit, uiCANFLY) = 0) and
           (TAMem.DistanceBetweenPosCompare(@p_AttackerUnit.Position,
             @UnitsCustomFields[TargetUnitId].ShieldedBy.Position,
             UnitsCustomFields[TAUnit.GetId(p_Shield)].ShieldRange)) then
        begin
          UNITS_MakeDamage(p_AttackerUnit, p_TargetUnit, Amount, DamageType, Angle);
          Exit;
        end;
      end;
    end;
    UnitId := TAUnit.GetId(p_AttackerUnit);
    TAUnit.CobStartScript(p_Shield, 'Shield',
                        @Amount, @UnitId, @TargetUnitId, nil,
                        False);
  end else
    UNITS_MakeDamage(p_AttackerUnit, p_TargetUnit, Amount, DamageType, Angle);
end;

procedure UnitActions_AntiDamageShieldHook;
asm
  push edx
  call UnitActions_AntiDamageShield
  push $00499E3C;
  call PatchNJump;
end;

function FixUnitYPos(p_Unit: PUnitStruct): Integer; stdcall;
begin
  Result := 0;
  if (p_Unit <> nil) and
     UnitsCustomFields[TAUnit.GetId(p_Unit)].ForcedYPos then
  begin
    p_Unit.Position.Y := UnitsCustomFields[TAUnit.GetId(p_Unit)].ForcedYPosVal shl 16;
    Result := 1;
  end;
end;

procedure UnitActions_FixUnitYPos; stdcall;
label
  dont_fix;
asm
  pushAD
  push   esi
  call   FixUnitYPos
  test   eax, eax
  jnz    dont_fix
  popAD
  mov    ecx, [esi+TUnitStruct.p_UnitInfo]
  push $0048A8BF;
  call PatchNJump;
dont_fix :
  popAD
  push $0048A96F;
  call PatchNJump;
end;

Procedure OnInstallUnitActions;
begin
end;

Procedure OnUninstallUnitActions;
begin
end;

function GetPlugin: TPluginData;
begin
  if IsTAVersion31 and State_UnitActions then
  begin
    Result := TPluginData.Create( False, 'UnitActions Plugin',
                                  State_UnitActions,
                                  @OnInstallUnitActions,
                                  @OnUninstallUnitActions );

    Result.MakeRelativeJmp( State_UnitActions,
                            'Enable resurrect and capture orders fot VTOLs',
                            @UnitActions_ExtraVTOLOrders,
                            $00438AE3, 0 );

    Result.MakeRelativeJmp( State_UnitActions,
                            'set cursor for new orders',
                            @UnitActions_AllowOrderType,
                            $0043E4F5, 4 );

    Result.MakeRelativeJmp( State_UnitActions,
                            'convert cursor type to action type',
                            @UnitActions_AllowOrderType_Action2IndexWrapper,
                            $0043F144, 4 );

    Result.MakeRelativeJmp( State_UnitActions,
                            'translate orders buttons to action type',
                            @UnitActions_NewOrdersButtonsWrapper,
                            $00419C20, 4 );

    Result.MakeRelativeJmp( State_UnitActions,
                            'extra unit state and orders reload routine',
                            @UnitActions_ExtraDataReload,
                            $0048ADF0, 1 );

    Result.MakeRelativeJmp( State_UnitActions,
                            'dont pass damage to shielded untis',
                            @UnitActions_AntiDamageShieldHook,
                            $00499E37, 0 );

    Result.MakeRelativeJmp( State_UnitActions,
                            'fix unit y pos for surfacing subs',
                            @UnitActions_FixUnitYPos,
                            $0048A8B9, 1 );
  end else
    Result := nil;
end;

end.
