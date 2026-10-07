unit OnOffPortal;

interface

uses
  PluginEngine;

const
  State_OnOffPortal : Boolean = True;

function GetPlugin : TPluginData;

function OnOffPortal_TestCommand(const Args: String): String;

procedure OnOffPortal_CheckStateTransitions;

procedure OnOffPortal_StopButtonPressed; stdcall;

implementation

uses
  Windows, SysUtils, Classes,
  TA_MemoryStructures,
  TA_MemoryLocations,
  TA_FunctionsU,
  TA_MemUnits,
  UnitInfoExpand,
  CloakOnly,
  UnitPortal;

const

  ADDR_SPECIALORDER_SOUND  = $0041A896;
  ADDR_MAPCLICK            = $00498F70;
  ADDR_DRAW_OVERLAY        = $00469F9A;
  ADDR_STOP_BUTTON         = $00419CB6;

  OFS_CLICK_POS            = $2CAA;
  OFS_CURSOR_INDEX         = $2CBE;

  PREPARE_DEFAULT          = 1;
  PREPARE_UNLOAD           = 5;
  CURSOR_ORDER_LIMIT       = $11;

  OVERLAY_BEACON_ALWAYS    = True;
  OVERLAY_COLOR_PICKUP     = 10;
  OVERLAY_COLOR_DROP       = 14;
  SIDEBAR_W                = 128;
  TOPBAR_H                 = 32;

  UNITSTATE_SELECTED       = $10;
  UNITINFO2_ONOFFABLE      = 4;
  UNITBAS_ACTIVATED        = 1;

  CLOAK_LABEL_COLOR        = 83;

  TRANSPORT_LABEL_COLOR    = 254;

var
  LayoutOK     : Boolean = False;
  Armed        : Boolean = False;
  ArmedUnitId  : Word = 0;
  LogPath      : String = 'C:\tpLAYX1\LOG\OnOffPortal.log';

  PendingDeactivateId   : Word = 0;
  PendingDeactivateTime : Integer = 0;

function DynByte(Ofs: Cardinal): PByte; inline;
begin
  Result := PByte(Cardinal(TAData.MainStruct) + Ofs);
end;

function IsOnOffTransport(p_Unit: PUnitStruct): Boolean;
begin
  Result := (p_Unit <> nil) and (p_Unit.p_UNITINFO <> nil) and
            ((p_Unit.p_UNITINFO.UnitTypeMask2 and UNITINFO2_ONOFFABLE) <> 0) and
            (p_Unit.p_UNITINFO.cTransportCap > 0);
end;

function UnitTag(p_Unit: PUnitStruct): String;
begin
  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
    Result := '<none>'
  else
    Result := String(p_Unit.p_UNITINFO.szName) + '#' + IntToStr(TAUnit.GetId(p_Unit));
end;

function FindSelectedOnOffTransport: PUnitStruct;
var
  i: Cardinal;
  p: PUnitStruct;
begin
  Result := nil;
  for i := 1 to TAData.MaxUnitsID do
  begin
    p := TAUnit.Id2Ptr(i);
    if (p = nil) or (p.p_UNITINFO = nil) or (p.nHealth = 0) then Continue;
    if (p.lUnitStateMask and UNITSTATE_SELECTED) = 0 then Continue;
    if not IsOnOffTransport(p) then Continue;
    if not TAUnit.IsOnThisComp(p, False) then Continue;
    Result := p;
    Exit;
  end;
end;

function FirstLocalOnOffTransport: PUnitStruct;
var
  i: Cardinal;
  p: PUnitStruct;
begin
  Result := nil;
  for i := 1 to TAData.MaxUnitsID do
  begin
    p := TAUnit.Id2Ptr(i);
    if (p = nil) or (p.p_UNITINFO = nil) or (p.nHealth = 0) then Continue;
    if IsOnOffTransport(p) and TAUnit.IsOnThisComp(p, False) then
    begin
      Result := p;
      Exit;
    end;
  end;
end;

function StateLine: String;
begin
  if TAData.MainStruct = nil then
  begin
    Result := 'no game';
    Exit;
  end;
  Result := Format('armed=%s unit=%d prepare=%d cursor=$%.2x onoffUI=%d mouse=(%d,%d) | %s',
    [BoolToStr(Armed, True), ArmedUnitId, TAData.MainStruct.ucPrepareOrderType,
     DynByte(OFS_CURSOR_INDEX)^, (TAData.MainStruct.field_37EC0 shr 5) and 3,
     TAData.MainStruct.nMouseMapPosX, TAData.MainStruct.nMouseMapPosY,
     PortalOnOff_StatusLine]);
end;

function CheckLayout: Boolean;
const
  N: PTAdynmemStruct = nil;
var
  oPrep, oSpot, oUI, oMX, oMZ: Cardinal;
begin
  oPrep := Cardinal(@N^.ucPrepareOrderType);
  oSpot := Cardinal(@N^.cBuildSpotState);
  oUI   := Cardinal(@N^.field_37EC0);
  oMX   := Cardinal(@N^.nMouseMapPosX);
  oMZ   := Cardinal(@N^.nMouseMapPosY);
  Result := (oPrep = $2CC3) and (oSpot = $2CC6) and (oUI = $37EC0) and
            (oMX = OFS_CLICK_POS + 2) and (oMZ = OFS_CLICK_POS + 10);
end;

procedure SetUnloadCursor;
begin

  TAData.MainStruct.ucPrepareOrderType := PREPARE_UNLOAD;
  TAData.MainStruct.cBuildSpotState := TAData.MainStruct.cBuildSpotState and $F7;
end;

procedure ResetPrepareOrder;
begin

  TAData.MainStruct.ucPrepareOrderType := PREPARE_DEFAULT;
  TAData.MainStruct.cBuildSpotState := TAData.MainStruct.cBuildSpotState and $DF;
end;

procedure ArmUnit(p_Unit: PUnitStruct; const Why: String);
begin
  PortalOnOff_BeginForUnit(p_Unit);
  SetUnloadCursor;
  Armed := True;
  ArmedUnitId := TAUnit.GetId(p_Unit);
end;

procedure Disarm(const Why: String; ResetCursor: Boolean);
begin
  if Armed and ResetCursor and (TAData.MainStruct <> nil) and
     (TAData.MainStruct.ucPrepareOrderType = PREPARE_UNLOAD) then
    ResetPrepareOrder;
  if Armed then
    ;
  Armed := False;
  ArmedUnitId := 0;
end;

function DispatchArmed(const Target: TPosition; const Why: String): Boolean;
var
  p: PUnitStruct;
begin
  Result := False;
  p := TAUnit.Id2Ptr(ArmedUnitId);
  if (p = nil) or (p.p_UNITINFO = nil) or (p.nHealth = 0) then
  begin
    Disarm('armed transport gone', True);
    Exit;
  end;
  ResetPrepareOrder;
  Armed := False;
  Result := PortalOnOff_DispatchToTarget(p, Target);
  ArmedUnitId := 0;
end;

procedure FerryOff(p: PUnitStruct; const Why: String; Deactivate: Boolean);
var
  Id: Word;
begin
  if p = nil then Exit;
  Id := TAUnit.GetId(p);
  if Armed and (ArmedUnitId = Id) then
    Disarm(Why, True);
  PortalOnOff_StopForUnit(p);
  if Deactivate and ((p.nUnitStateMaskBas and UNITBAS_ACTIVATED) <> 0) then
  begin
    PendingDeactivateId := Id;
    PendingDeactivateTime := TAData.GameTime;
  end;
end;

procedure FirePendingDeactivate;
var
  p: PUnitStruct;
  Idx: Byte;
begin
  if PendingDeactivateId = 0 then Exit;
  if TAData.GameTime = PendingDeactivateTime then Exit;
  p := TAUnit.Id2Ptr(PendingDeactivateId);
  PendingDeactivateId := 0;
  if not PortalOnOff_TransportAlive(p) then Exit;
  if (p.nUnitStateMaskBas and UNITBAS_ACTIVATED) = 0 then Exit;
  Idx := TAMem.ScriptActionName2Index('DEACTIVATE');
  Order2Unit(Idx, 0, p, nil, nil, 0, 0);
end;

procedure OnOffPortal_StopButtonPressed; stdcall;
var
  OI: TPortalOverlayInfo;
  i: Cardinal;
  p: PUnitStruct;
  Id: Word;
begin
  try
    if (not LayoutOK) or (TAData.MainStruct = nil) then Exit;
    PortalOnOff_GetOverlay(OI);
    if not (Armed or OI.LoopRunning or OI.SrcOn or OI.DstOn) then Exit;
    for i := 1 to TAData.MaxUnitsID do
    begin
      p := TAUnit.Id2Ptr(i);
      if (p = nil) or (p.p_UNITINFO = nil) or (p.nHealth = 0) then Continue;
      if (p.lUnitStateMask and UNITSTATE_SELECTED) = 0 then Continue;
      if not IsOnOffTransport(p) then Continue;
      if not TAUnit.IsOnThisComp(p, False) then Continue;
      Id := TAUnit.GetId(p);
      if (Armed and (ArmedUnitId = Id)) or (OI.TransportId = Id) or
         ((not OI.LoopRunning) and (OI.SrcOn or OI.DstOn)) then
        FerryOff(p, 'STOP button', True);
    end;
  except
    on E: Exception do ;
  end;
end;

procedure HandleSwitch(NewState: Integer; const Why: String);
var
  p: PUnitStruct;
begin
  p := FindSelectedOnOffTransport;
  if p = nil then Exit;

  case NewState of
    1: ArmUnit(p, Why);
    0: FerryOff(p, 'switched OFF', False);
  end;
end;

procedure OnOffPortal_OnSwitchClicked; stdcall;
begin
  try
    if (not LayoutOK) or (TAData.MainStruct = nil) then Exit;
    HandleSwitch((TAData.MainStruct.field_37EC0 shr 5) and 3, 'ONOFF button');
  except
    on E: Exception do ;
  end;
end;

function OnOffPortal_OnMapClick(pMouseEvent: Pointer): LongBool; stdcall;
var
  Cursor: Byte;
  Target: TPosition;
begin
  Result := False;
  if (not Armed) or (not LayoutOK) then Exit;
  try
    if TAData.MainStruct = nil then Exit;

    if TAData.MainStruct.ucPrepareOrderType <> PREPARE_UNLOAD then
    begin

      Disarm('cancelled - prepare order is now ' +
        IntToStr(TAData.MainStruct.ucPrepareOrderType), False);
      Exit;
    end;

    Cursor := DynByte(OFS_CURSOR_INDEX)^;
    if Cursor >= CURSOR_ORDER_LIMIT then
    begin

      ;
      Exit;
    end;

    Target := PPosition(Cardinal(TAData.MainStruct) + OFS_CLICK_POS)^;
    DispatchArmed(Target, 'map click');
    Result := True;
  except
    on E: Exception do
    begin
      Result := False;
    end;
  end;
end;

function PalColor(Idx: Integer): Byte;
begin
  Result := PByte(Cardinal(TAData.ColorsPalette) + Cardinal(Idx))^;
end;

procedure WorldToScreen(X, Y, Z: Integer; out SX, SY: Integer);
begin
  SX := X - TAData.MainStruct.lEyeBallMapX + SIDEBAR_W;
  SY := Z - TAData.MainStruct.lEyeBallMapY - (Y div 2) + TOPBAR_H;
end;

function OnScreen(SX, SY, R: Integer): Boolean;
begin
  Result := (SX + R >= SIDEBAR_W) and (SY + R >= TOPBAR_H) and
            (SX - R <= TAData.MainStruct.ScreenWidth) and
            (SY - R <= TAData.MainStruct.ScreenHeight);
end;

procedure DrawRing(p_Offscreen: Pointer; SX, SY, R: Integer; Color: Byte);
begin
  if R <= 2 then Exit;
  DrawCircle(p_Offscreen, SX, SY, R, Color);
  DrawCircle(p_Offscreen, SX, SY, R - 1, Color);
end;

procedure DrawLabel(p_Offscreen: Pointer; const Txt: AnsiString; SX, SY: Integer;
  Color: Byte = CLOAK_LABEL_COLOR);
begin
  SetFontColor(Color, GetFontBackgroundColor);
  DrawTextCustomFont(p_Offscreen, PAnsiChar(Txt), SX, SY, -1);
end;

procedure DrawBeacon(p_Offscreen: Pointer; SX, SY, Anim: Integer);
var
  Seq: PGAFSequence;
  Frame: Pointer;
begin
  if Anim <= 0 then Exit;
  if Length(ExtraGAFAnimations.CustAnim) < Anim then Exit;
  Seq := PGAFSequence(ExtraGAFAnimations.CustAnim[Anim - 1]);
  if (Seq = nil) or (Seq.Frames <= 0) then Exit;
  Frame := GAF_SequenceIndex2Frame(Seq, (TAData.GameTime div 2) mod Seq.Frames);
  if Frame <> nil then
    CopyGafToContext(p_Offscreen, Frame, SX, SY);
end;

procedure DrawCloakFields(p_Offscreen: Pointer; Shift: Boolean);
var
  i, R, Anim, State: Integer;
  p: PUnitStruct;
  SX, SY: Integer;
  Txt: AnsiString;
begin
  for i := 1 to Integer(TAData.MaxUnitsID) do
  begin
    p := TAUnit.Id2Ptr(i);
    if (p = nil) or (p.p_UNITINFO = nil) or (p.nHealth = 0) then Continue;
    R := CloakOnly_FieldRadius(p);
    if R <= 0 then Continue;
    if not TAUnit.IsOnThisComp(p, False) then Continue;
    State := CloakOnly_FieldState(TAUnit.GetId(p));
    WorldToScreen(p.Position.X div 65536, p.Position.Y div 65536, p.Position.Z div 65536, SX, SY);
    if not OnScreen(SX, SY, R) then Continue;

    Anim := CloakOnly_FieldAnim(p);
    if (Anim > 0) and (State = 1) then
      DrawBeacon(p_Offscreen, SX, SY, Anim);

    if Shift and ((p.lUnitStateMask and UNITSTATE_SELECTED) <> 0) then
    begin
      DrawRing(p_Offscreen, SX, SY, R, Byte(CloakOnly_FieldRingColor(p)));
      if State = 0 then Txt := 'CLOAK FIELD - OFF (enemy near / hit)'
      else Txt := AnsiString(Format('CLOAK FIELD %d', [R]));
      DrawLabel(p_Offscreen, Txt, SX - 30, SY + R - 14);
    end;
  end;
end;

var
  OverlayErrLogged: Boolean = False;

procedure OnOffPortal_DrawOverlay(p_Offscreen: Pointer); stdcall;
var
  O: TPortalOverlayInfo;
  DeadId: Word;
  Shift: Boolean;
  SX, SY: Integer;
  Txt: AnsiString;
begin
  try
    if (not LayoutOK) or (p_Offscreen = nil) or (TAData.MainStruct = nil) then Exit;
    PortalOnOff_Tick;
    FirePendingDeactivate;
    DrawCloakFields(p_Offscreen, (GetAsyncKeyState(VK_SHIFT) and $8000) <> 0);

    if Armed and not PortalOnOff_TransportAlive(TAUnit.Id2Ptr(ArmedUnitId)) then
    begin
      DeadId := ArmedUnitId;
      Disarm('armed transport died', True);
      PortalOnOff_StopForUnit(TAUnit.Id2Ptr(DeadId));
    end;
    PortalOnOff_GetOverlay(O);
    if not (O.LoopRunning or Armed) then Exit;
    Shift := (GetAsyncKeyState(VK_SHIFT) and $8000) <> 0;

    if O.LoopRunning and O.DstOn and (OVERLAY_BEACON_ALWAYS or Shift) then
    begin
      WorldToScreen(O.DstX, O.DstY, O.DstZ, SX, SY);
      if OnScreen(SX, SY, 128) then
        DrawBeacon(p_Offscreen, SX, SY, O.BeaconAnim);
    end;

    if not Shift then Exit;

    if O.SrcOn then
    begin
      WorldToScreen(O.SrcX, O.SrcY, O.SrcZ, SX, SY);
      if OnScreen(SX, SY, O.PickupRadius) then
      begin
        DrawRing(p_Offscreen, SX, SY, O.PickupRadius, PalColor(OVERLAY_COLOR_PICKUP));
        if O.LoopRunning then
        begin
          Txt := AnsiString(Format('PICKUP %d/%d', [O.Aboard, O.Capacity]));
          if O.WaitingFull then Txt := Txt + ' - waiting for full load';
        end else
          Txt := 'PICKUP - click a drop zone';
        DrawLabel(p_Offscreen, Txt, SX - 30, SY - 6, TRANSPORT_LABEL_COLOR);
      end;
    end;

    if O.LoopRunning and O.DstOn then
    begin
      WorldToScreen(O.DstX, O.DstY, O.DstZ, SX, SY);
      if OnScreen(SX, SY, O.DropRadius) then
      begin
        DrawRing(p_Offscreen, SX, SY, O.DropRadius, PalColor(OVERLAY_COLOR_DROP));
        DrawLabel(p_Offscreen, 'DROP ZONE', SX - 26, SY + 12, TRANSPORT_LABEL_COLOR);
      end;
    end;
  except
    on E: Exception do
      if not OverlayErrLogged then
      begin
        OverlayErrLogged := True;
      end;
  end;
end;

procedure OnOffPortal_SpecialOrderHook; assembler; nostackframe;
asm
  pushad
  pushfd
  call  OnOffPortal_OnSwitchClicked
  popfd
  popad
  push  dword 0
  push  dword $005026E4
  push  dword $0041A89D
  ret
end;

procedure OnOffPortal_MapClickHook; assembler; nostackframe;
label
  Consumed;
asm
  pushad
  pushfd
  mov   eax, [esp + 40]
  push  eax
  call  OnOffPortal_OnMapClick
  test  eax, eax
  jnz   Consumed
  popfd
  popad
  push  ecx
  mov   eax, dword ptr [$00511DE8]
  push  esi
  push  dword $00498F77
  ret
Consumed:
  popfd
  popad
  ret   4
end;

procedure OnOffPortal_DrawHook; assembler; nostackframe;
asm
  pushad
  pushfd
  lea   eax, [esp + $58]
  push  eax
  call  OnOffPortal_DrawOverlay
  popfd
  popad
  lea   eax, [esp + $34]
  push  eax
  push  dword $00469F9F
  ret
end;

procedure OnOffPortal_StopHook; assembler; nostackframe;
asm
  pushad
  pushfd
  call  OnOffPortal_StopButtonPressed
  popfd
  popad
  mov   ecx, dword ptr [$00511DE8]
  push  dword $00419CBC
  ret
end;

procedure OnOffPortal_CheckStateTransitions;
begin
  if Armed and (TAData.MainStruct <> nil) and
     (TAData.MainStruct.ucPrepareOrderType <> PREPARE_UNLOAD) then
    Disarm('cancelled (poll)', False);
end;

function OnOffPortal_TestCommand(const Args: String): String;
var
  Parts: TStringList;
  Verb: String;
  p: PUnitStruct;
  T: TPosition;
  OI: TPortalOverlayInfo;
begin
  Result := '';
  Parts := TStringList.Create;
  try
    Parts.Delimiter := ' ';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := Trim(Args);
    if Parts.Count = 0 then Verb := 'status' else Verb := LowerCase(Parts[0]);

    if not LayoutOK then
      Result := 'FAIL struct layout mismatch (see log)'
    else if TAData.MainStruct = nil then
    begin
      Result := 'no game';
    end
    else if Verb = 'on' then
    begin

      p := FindSelectedOnOffTransport;
      if p = nil then
      begin
        p := FirstLocalOnOffTransport;
        if p <> nil then
        begin
          DeselectAllUnits;
          p.lUnitStateMask := p.lUnitStateMask or UNITSTATE_SELECTED;
        end;
      end;
      if p = nil then
        Result := 'FAIL no local onoffable transport (spawn ARMATLAS with onoffable=1)'
      else
      begin
        TAData.MainStruct.field_37EC0 := (TAData.MainStruct.field_37EC0 and $FF9F) or $20;
        HandleSwitch(1, 'aio.cmd');
        if Armed and (TAData.MainStruct.ucPrepareOrderType = PREPARE_UNLOAD) then
          Result := 'OK armed ' + UnitTag(p)
        else
          Result := 'FAIL not armed';
      end;
    end
    else if Verb = 'off' then
    begin

      if FindSelectedOnOffTransport = nil then
      begin
        PortalOnOff_GetOverlay(OI);
        p := nil;
        if OI.TransportId <> 0 then p := TAUnit.Id2Ptr(OI.TransportId);
        if (p <> nil) and IsOnOffTransport(p) then
        begin
          DeselectAllUnits;
          p.lUnitStateMask := p.lUnitStateMask or UNITSTATE_SELECTED;
        end;
      end;
      TAData.MainStruct.field_37EC0 := TAData.MainStruct.field_37EC0 and $FF9F;
      HandleSwitch(0, 'aio.cmd');
      PortalOnOff_GetOverlay(OI);
      if Armed or OI.LoopRunning then Result := 'FAIL still armed/running' else Result := 'OK off';
    end
    else if Verb = 'stop' then
    begin

      OnOffPortal_StopButtonPressed;
      PortalOnOff_GetOverlay(OI);
      if Armed or OI.LoopRunning or OI.SrcOn or OI.DstOn then Result := 'FAIL zones still up'
      else Result := 'OK stopped';
    end
    else if Verb = 'select' then
    begin

      p := FirstLocalOnOffTransport;
      if p = nil then
        Result := 'FAIL no local onoffable transport'
      else
      begin
        DeselectAllUnits;
        p.lUnitStateMask := p.lUnitStateMask or UNITSTATE_SELECTED;
        TAData.MainStruct.DesktopGUIState := TAData.MainStruct.DesktopGUIState or $10;
        TAData.MainStruct.ShowRangeUnitIndex := 0;
        Result := 'OK selected ' + UnitTag(p);
      end;
    end
    else if Verb = 'kill' then
    begin

      PortalOnOff_GetOverlay(OI);
      p := nil;
      if OI.TransportId <> 0 then p := TAUnit.Id2Ptr(OI.TransportId);
      if (p = nil) and Armed then p := TAUnit.Id2Ptr(ArmedUnitId);
      if p = nil then
        Result := 'FAIL no ferry transport'
      else
      begin
        TAUnit.Kill(p, 0);
        Result := 'OK killed ' + UnitTag(p);
      end;
    end
    else if Verb = 'click' then
    begin
      if not Armed then
        Result := 'FAIL not armed'
      else
      begin
        if Parts.Count >= 3 then
        begin
          T.X := StrToIntDef(Parts[1], 0) * 65536;
          T.Z := StrToIntDef(Parts[2], 0) * 65536;
          T.Y := 0;
        end
        else
          T := PPosition(Cardinal(TAData.MainStruct) + OFS_CLICK_POS)^;
        if DispatchArmed(T, 'aio.cmd click') then
          Result := Format('OK dispatched (%d,%d)', [T.X div 65536, T.Z div 65536])
        else
          Result := 'FAIL dispatch rejected';
      end;
    end
    else
      Result := 'OK status';
  finally
    Parts.Free;
  end;
  if TAData.MainStruct <> nil then
    Result := Result + ' | ' + StateLine;
end;

procedure OnInstallOnOffPortal;
begin
  Armed := False;
  ArmedUnitId := 0;
  LayoutOK := CheckLayout;
end;

procedure OnUninstallOnOffPortal;
begin
  Armed := False;
end;

function BytesAre(Addr: Cardinal; const Expect: array of Byte): Boolean;
var
  i: Integer;
begin
  Result := False;
  try
    for i := 0 to High(Expect) do
      if PByte(Addr + Cardinal(i))^ <> Expect[i] then Exit;
    Result := True;
  except
  end;
end;

function GetPlugin : TPluginData;
var
  DrawSiteOK: Boolean;
begin
  if IsTAVersion31 and State_OnOffPortal then
  begin
    Result := TPluginData.Create(True,
                                 'OnOffPortal',
                                 State_OnOffPortal,
                                 @OnInstallOnOffPortal,
                                 @OnUninstallOnOffPortal);

    Result.MakeRelativeJmp(State_OnOffPortal,
                           'OnOff button -> portal arm (GUI_HandleSpecialOrderButton)',
                           @OnOffPortal_SpecialOrderHook,
                           ADDR_SPECIALORDER_SOUND, 2);

    Result.MakeRelativeJmp(State_OnOffPortal,
                           'Map click -> portal destination (_TAMapClick)',
                           @OnOffPortal_MapClickHook,
                           ADDR_MAPCLICK, 2);

    if BytesAre(ADDR_STOP_BUTTON, [$8B, $0D, $E8, $1D, $51, $00]) then
      Result.MakeRelativeJmp(State_OnOffPortal,
                             'STOP button -> ferry off (SetPrepareOrder STOP branch)',
                             @OnOffPortal_StopHook,
                             ADDR_STOP_BUTTON, 1)
    else
      ;

    DrawSiteOK := BytesAre(ADDR_DRAW_OVERLAY, [$8D, $44, $24, $34, $50]);
    if DrawSiteOK then
      Result.MakeRelativeJmp(State_OnOffPortal,
                             'Portal overlay: pickup radius + drop-zone beacon (Render_Draw_Game_Screen)',
                             @OnOffPortal_DrawHook,
                             ADDR_DRAW_OVERLAY, 0)
    else
      ;
  end else
    Result := nil;
end;

end.
