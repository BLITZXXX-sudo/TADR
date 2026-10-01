unit UnitActions;

interface
uses
  PluginEngine;

// -----------------------------------------------------------------------------

const
  State_UnitActions: Boolean = True;

function GetPlugin: TPluginData;

// -----------------------------------------------------------------------------

Procedure OnInstallUnitActions;
Procedure OnUninstallUnitActions;

// -----------------------------------------------------------------------------

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
  GUIEnhancements;

// Diagnostic (2026-07-22): tracing the ARMARAD shield-radius chain - does
// ExtraDataReload ever see ShieldRange>0 for a unit, and does
// TAUnit.IsArmored return true at that point (the shield only registers
// nearby allies via CallbackForUnitsInDistance when armored). One-shot
// flags, own diag log entries, do not affect behaviour.
var
  DiagLoggedShieldRangeSeen: Boolean = False;
  DiagLoggedShieldArmoredState: Boolean = False;
  DiagLoggedShieldUnitInfoFields: Boolean = False;

// SearchForReclamateFeatures only ever returns the SINGLE nearest
// metal-reclaimable feature within the search radius. If that nearest
// feature happens to be plain reclaim debris rather than a resurrectable
// unit corpse, Portal_AutoResurrectScan used to give up for that whole tick
// even when an actual wreck was sitting right there, slightly further away -
// this is why most resurrects were still being done manually. The retry
// loop below re-searches with a shrinking radius (just inside the distance
// of each rejected feature) so it walks outward from nearest to furthest
// until it finds an actual wreck or runs out of candidates. Capped so a
// pile of non-wreck debris can't turn this into an unbounded loop.
const
  MAX_PORTAL_SCAN_ATTEMPTS = 8;

// Diagnostic (2026-07-23 round 2): Portal_AutoResurrectScan never once logged
// a successful find across a 55-minute test session that included multiple
// manually-issued RESURRECT orders on stationary canresurrect units with
// wrecks well within BuildDistance - i.e. it's exiting early on literally
// every tick, for every such unit, the whole time. These per-branch logs
// pin down exactly which check is doing that. Capped like the existing
// RESURRECT/REPAIR diag counters so it doesn't spam forever.
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
  // edx order unit ptr
  // edi target unit ptr
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
  push $0043EA5A;      // return eax
  call PatchNJump;
default_order:
  push $0043F098;      // return 19
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
  // ebp order unit
  // edi target unit
  // esp+24h target position
  push    ecx
  push    edx
  push    ebx
  push    esi
  push    edi

  mov     ebx, [esp+38h]
  push    ebx              // position
  push    edi              // target unit
  push    ebp              // order unit
  push    ecx              // action type
  call    UnitActions_AllowOrderType_Action2Index

  pop     edi
  pop     esi
  pop     ebx
  pop     edx
  pop     ecx

  test    al, al
  jz      default_order
  mov     esi, [esp+14h] // retn action index via reference
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

// "Portal" auto-resurrect (2026-07-23): native replacement for the fixed
// r=8 (~128 elmo) grid scan hardcoded in ARMMEX.bos's AutoResurrectScan.
// That COB scan can't be widened without editing+recompiling the .bos, and
// its hardcoded radius doesn't match BuildDistance (300 - the actual range
// our RESURRECT bypass allows an order to succeed at), which is what showed
// up as a circle/behavior mismatch. This runs from ExtraDataReload (the same
// per-unit periodic hook the ShieldRange logic above already uses) so a
// single value - nBuildDistance - drives both the search radius here and the
// circle GUIEnhancements.pas draws, with no COB recompile involved.
// Reuses the exact SearchForReclamateFeatures -> GetFeatureTypeFromOrder ->
// UNITINFO_Name2ID -> ORDERS_CreateObject/ORDERS_PushOrder pattern that
// OrdersOverride_RepairPatrol already uses successfully for mobile units
// (OrdersOverride.pas), just swapping nSightDistance for nBuildDistance and
// dropping the resource-availability gating (the native RESURRECT handler
// already handles cost/consumption once an order is issued).
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

  // Throttle to roughly every ~90 ticks (~3s at 30 ticks/sec), matching the
  // old COB scan's "sleep 3000" cadence, so this isn't doing a feature search
  // for every canresurrect unit on every single simulation tick.
  if UnitsCustomFields[UnitId].ResurrectScanCooldown > 0 then
  begin
    Dec(UnitsCustomFields[UnitId].ResurrectScanCooldown);
    Exit;
  end;
  UnitsCustomFields[UnitId].ResurrectScanCooldown := 90;

  if p_Unit.p_MovementClass <> nil then Exit;   // mobile units already get this via RepairPatrol

  // uiCanResurrect=0 units (i.e. almost every unit in the match - tanks,
  // infantry, etc.) hit this cooldown-gated check just as often as real
  // resurrectors do. Logging/counting those was burning through the 500-call
  // diag cap in a couple of minutes flat in a match with any real unit count,
  // which made logging for the units we actually care about go silent very
  // early while the game (and Portal) kept running fine - looked exactly
  // like "it stopped working" from the log alone. Skip them silently instead;
  // the counter below only tracks units that are actually flagged canresurrect.
  bCanResurrect := TAUnit.GetUnitInfoField(p_Unit, uiCanResurrect);
  if bCanResurrect = 0 then Exit;

  Inc(DiagPortalScanCallCount);

  if p_Unit.p_MainOrder <> nil then
  begin
    if DiagPortalScanCallCount <= 2000 then
      LogDiag(Format('Portal scan #%d: UnitID=%d has active p_MainOrder <> nil, skipping this tick',
        [DiagPortalScanCallCount, UnitId]));
    Exit;
  end;

  BuildDist := p_Unit.p_UnitInfo.nBuildDistance;
  if BuildDist <= 0 then
  begin
    if DiagPortalScanCallCount <= 2000 then
      LogDiag(Format('Portal scan #%d: UnitID=%d BuildDistance<=0 (%d), skipping',
        [DiagPortalScanCallCount, UnitId, BuildDist]));
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
      LogDiag(Format('Portal scan #%d: UnitID=%d attempt=%d SearchDist=%d SearchFound=%s p_MetalFeaturePosition<>nil=%s FeatureMetal=%.1f FeatureEnergy=%.1f',
        [DiagPortalScanCallCount, UnitId, ScanAttempt, SearchDist, BoolToStr(bSearchFound, True),
         BoolToStr(p_MetalFeaturePosition <> nil, True), FeatureMetal, FeatureEnergy]));

    if (not bSearchFound) or (p_MetalFeaturePosition = nil) then
      Break; // nothing (else) reclaimable within the shrinking radius

    FeatureTypeID := GetFeatureTypeFromOrder(p_MetalFeaturePosition, nil, nil);

    if FeatureTypeID <> Word(-1) then
    begin
      WreckTypeName := StringReplace(TAMem.FeatureDefId2Ptr(FeatureTypeID).Name, '_', #0, []);
      WreckUnitInfoID := UNITINFO_Name2ID(PAnsiChar(WreckTypeName));

      if DiagPortalScanCallCount <= 2000 then
        LogDiag(Format('Portal scan #%d: UnitID=%d attempt=%d FeatureTypeID=%d FeatureDef.Name=%s WreckUnitInfoID=%d',
          [DiagPortalScanCallCount, UnitId, ScanAttempt, FeatureTypeID,
           TAMem.FeatureDefId2Ptr(FeatureTypeID).Name, WreckUnitInfoID]));

      if WreckUnitInfoID <> 0 then
      begin
        bFoundValidWreck := True;
        Break;
      end;
    end else
    begin
      if DiagPortalScanCallCount <= 2000 then
        LogDiag(Format('Portal scan #%d: UnitID=%d attempt=%d FeatureTypeID=-1 (not a unit corpse)',
          [DiagPortalScanCallCount, UnitId, ScanAttempt]));
    end;

    // Not a resurrectable wreck (plain reclaim debris, or a corpse type this
    // mod doesn't recognise). SearchForReclamateFeatures always returns the
    // SINGLE nearest reclaimable feature, so calling it again with the same
    // radius would just return this same rejected feature forever. Shrink
    // the radius to just inside this rejected feature's actual distance so
    // the next attempt is forced past it and finds whatever's next-nearest.
    RejectedDist := TAMem.DistanceBetweenPos(@p_Unit.Position, PPosition(p_MetalFeaturePosition));
    if RejectedDist <= 0 then Break; // safety: avoid looping forever on a bad distance
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
  LogDiag(Format('Portal auto-scan: UnitID=%d found resurrectable wreck at (%d,%d) ' +
    '(BuildDistance=%d), queued RESURRECT',
    [UnitId, MetalFeaturePosition.X, MetalFeaturePosition.Z, BuildDist]));
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

    // shield is not activated or unit is not in range of it anymore
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
    LogDiagOnce(DiagLoggedShieldRangeSeen,
      Format('ExtraDataReload: UnitId=%d has ShieldRange=%d, IsArmored=%s',
        [UnitId, ShieldRange, BoolToStr(TAUnit.IsArmored(p_Unit), True)]));
    // Diagnostic (2026-07-22): directly checks, for THIS exact unit (known
    // to be the shield generator, e.g. ARMARAD, since it has ShieldRange>0)
    // whether its UnitInfoCustomFields (the per-unit-TYPE record, loaded
    // once from its FBI) actually picked up the customrange1dist/color and
    // customreloadbar tags, and whether its per-instance custom-bar fields
    // have ever been populated by a CUSTOM_BAR_PROGRESS extension call.
    // This sidesteps having to guess which selected unit a GUI-side
    // diagnostic corresponds to.
    if p_Unit.nUnitInfoID <= High(UnitInfoCustomFields) then
      LogDiagOnce(DiagLoggedShieldUnitInfoFields,
        Format('ExtraDataReload: UnitId=%d nUnitInfoID=%d CustomRange1Distance=%d CustomRange1Color=%d UseCustomReloadBar=%s CustomWeapReloadCur=%d CustomWeapReloadMax=%d',
          [UnitId, p_Unit.nUnitInfoID,
           UnitInfoCustomFields[p_Unit.nUnitInfoID].CustomRange1Distance,
           UnitInfoCustomFields[p_Unit.nUnitInfoID].CustomRange1Color,
           BoolToStr(UnitInfoCustomFields[p_Unit.nUnitInfoID].UseCustomReloadBar, True),
           UnitsCustomFields[UnitId].CustomWeapReloadCur,
           UnitsCustomFields[UnitId].CustomWeapReloadMax]))
    else
      LogDiagOnce(DiagLoggedShieldUnitInfoFields,
        Format('ExtraDataReload: UnitId=%d nUnitInfoID=%d OUT OF RANGE (High(UnitInfoCustomFields)=%d)',
          [UnitId, p_Unit.nUnitInfoID, High(UnitInfoCustomFields)]));
    UnitSearchCallbackRec.p_CallerUnit := nil;
    if TAUnit.IsArmored(p_Unit) then
    begin
      UnitSearchCallbackRec.p_CallerUnit := p_Unit;
      LogDiagOnce(DiagLoggedShieldArmoredState,
        Format('ExtraDataReload: UnitId=%d is ARMORED, registering as shield source (range=%d)',
          [UnitId, ShieldRange]));
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
  push    ebx // save old order
  push    edi // unit
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
  fld     [esi+TUnitStruct.fBuildTimeLeft]  // buildtimeleft
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
  // p_TargetUnit should always be a live unit taking damage. If it isn't (or
  // its UNITINFO has already been torn down mid-death), bail instead of
  // dereferencing stale memory further down.
  //
  // Also require a non-nil p_Owner: disassembling the actual crash site
  // (TotalA.exe+0x489C94) showed native UNITS_MakeDamage unconditionally
  // dereferences the target's p_Owner field (TUnitStruct offset 0x96, right
  // after p_UNITINFO at 0x92) - this fires for any owner-less/neutral unit
  // taking damage, not just ones with a stale UNITINFO. This hook intercepts
  // every damage event in the game (installed via PatchNJump), so it's the
  // most likely place this was actually being hit from.
  if (p_TargetUnit = nil) or (p_TargetUnit.p_UNITINFO = nil) or
     (p_TargetUnit.p_Owner = nil) then
    Exit;

  // Normalise an attacker whose slot has gone stale/empty down to a real
  // nil - UNITS_MakeDamage(nil, ...) is already a supported pattern
  // elsewhere, a dangling non-nil pointer to an empty slot is not.
  if (p_AttackerUnit <> nil) and (p_AttackerUnit.p_UNITINFO = nil) then
    p_AttackerUnit := nil;

  TargetUnitId := TAUnit.GetId(p_TargetUnit);

  p_Shield := UnitsCustomFields[TargetUnitId].ShieldedBy;

  // UnitsCustomFields[..].ShieldedBy is only ever cleared by the shield
  // generator's OWN periodic scan (UnitSearchHandlers.SetShield, called
  // while that unit is alive and scanning for nearby allies). If the
  // generator itself dies, that scan simply stops running - it never gets
  // a last call with p_Shield=nil to clear out units it was shielding. Any
  // unit it was shielding is then left with a dangling ShieldedBy pointer
  // into the dead generator's (possibly reused) memory slot. The next time
  // that unit takes damage, this function would dereference the stale
  // pointer's Position/UNITINFO/COB script data and crash (this matched
  // TotalA.exe+0x489C94, "Illegal read, data address 0x0", after testing
  // an ARMARAD-based shield generator). Treat a stale shield the same as no
  // shield instead of dereferencing it.
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
//        Distance := TAUnits.Distance(@p_Projectile.Position_Start,
//          @p_Projectile.Position_Curnt);

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
                             {              
    Result.MakeRelativeJmp( State_UnitActions,
                            'Default unit mission with position parameter addition',
                            @UnitActions_AdvancedDefaultMission,
                            $0043B9DE, 1 );
                             }
    {
    Result.MakeRelativeJmp( State_UnitActions,
                            'dont heal time units that are under construction',
                            @UnitActions_DontHealTimeNotBuilt,
                            $0048AF58, 1 );
    }
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
