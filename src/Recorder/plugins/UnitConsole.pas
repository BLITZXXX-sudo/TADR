unit UnitConsole;
{
  Unit Selection Console with Submenu System
  Hotkey: Alt+Shift+L to open/close

  Main Menu (0): Shows categories
  Then select 1-6 for each submenu
  Press 0 anytime to return to main menu
}

interface

procedure ToggleUnitConsole;

implementation

uses
  Windows, SysUtils, Classes, Math,
  TA_MemUnits,
  TA_MemoryLocations,
  TA_MemoryStructures,
  TA_FunctionsU,
  idplay;

var
  ConsoleHandle: THandle = 0;
  ConsoleThread: THandle = 0;
  ConsoleActive: Boolean = False;
  SelectedUnitId: Word = 0;
  CurrMousePosition: TPoint = (X: 0; Y: 0);
  CurrentMenu: Integer = 0;  { 0=Main, 1=Selection, 2=Status, 3=Control, 4=Orders, 5=Advanced, 6=Mouse }

  { Captured world position (set by Mouse Tools > Capture mouse pos).
    Distinct from CurrMousePosition, which is only the screen coordinate
    shown for reference - CreateMainOrder needs game world X/Z/Y. }
  CapturedGameX: Word = 0;
  CapturedGameZ: Word = 0;
  CapturedGameY: Word = 0;
  CapturedValid: Boolean = False;

  { Game's own screen-click -> world-ground resolver (handles terrain
    height, minimap vs main view). Found via Ghidra + cross-checked
    against leaked SDK source (commanderwarp.cpp, which reads the
    neighboring lEyeBallMapX/Y fields the same way). Not previously
    used anywhere in this project, so results are sanity-checked
    against map bounds before being trusted - see TryCaptureGroundClick. }
  Map_ScreenToWorldClick: procedure(pData: Pointer); stdcall;

{ ============================================================================= }
{ Helper: Display message to console                                          }
{ ============================================================================= }

procedure WriteLn(const Msg: String);
var
  Written: Cardinal;
begin
  if ConsoleHandle <> 0 then
    WriteFile(ConsoleHandle, PChar(Msg + #13#10)^, Length(Msg) + 2, Written, nil);
end;

{ ============================================================================= }
{ Diagnostic log - Unload investigation (2026-08-17)                          }
{ Separate from the console's own WriteLn (which only appears while the       }
{ console window is open and scrolls away). Written to C:\tpLAYX1\LOG\ per    }
{ request, so it survives after the fact and can be read back outside the    }
{ game too. Same append-mode pattern as GUIEnhancements.LogDiag, just         }
{ pointed at a fixed path instead of exe-relative, and tagged per-unit so     }
{ UnitConsole.pas and UnitPortal.pas entries can be told apart in one file.   }
{ ============================================================================= }

procedure LogUnload(const Msg: String);
var
  LogFile: TextFile;
  LogPath: String;
begin
  try
    ForceDirectories('C:\tpLAYX1\LOG');
    LogPath := 'C:\tpLAYX1\LOG\UnloadDiag.log';
    AssignFile(LogFile, LogPath);
    {$I-}
    if FileExists(LogPath) then
      Append(LogFile)
    else
      Rewrite(LogFile);
    {$I+}
    if IOResult <> 0 then Exit;
    { Must be System.Writeln, fully qualified - this unit's own WriteLn
      above (single-String-arg, writes to the console window) would
      otherwise shadow the 2-arg file-writing Writeln from here on and
      fail to compile ("wrong number of parameters"). }
    System.Writeln(LogFile, FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + '  [UnitConsole] ' + Msg);
    CloseFile(LogFile);
  except end;
end;

procedure Write(const Msg: String);
var
  Written: Cardinal;
begin
  if ConsoleHandle <> 0 then
    WriteFile(ConsoleHandle, PChar(Msg)^, Length(Msg), Written, nil);
end;

{ Prints to the console window AND flashes the same line in the in-game
  chat/reminder overlay via SendTextLocal, so short confirmations and
  errors are visible even if the console window isn't in focus. Use this
  for actionable events (order given, unit killed, error, etc) - use plain
  WriteLn for menu text and info dumps so chat doesn't get spammed. }
procedure Notify(const Msg: String);
begin
  WriteLn('  ' + Msg);
  SendTextLocal(Msg);
end;

{ ============================================================================= }
{ Mouse Position Capture - anywhere on the map, ground or unit                }
{ ============================================================================= }

{ Re-runs the game's own click resolver on its own live-tracked mouse
  position (the same 2 DWords GetUnitAtMouse's hit-test already reads),
  then reads the resolved map X/Z back out of the already-named
  nMouseMapPosX/nMouseMapPosY fields. This is the same code path TA uses
  for real ground clicks, so it works on bare terrain - no unit needed.
  Sanity-checked against map bounds since this hook is untested live. }
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
    Exit;  { Map info not ready - reject rather than trust garbage }
  if (ResolvedX = 0) and (ResolvedZ = 0) then
    Exit;  { Almost certainly an unresolved read, not really the corner }
  if (Integer(ResolvedX) > MapWidth) or (Integer(ResolvedZ) > MapHeight) then
    Exit;  { Out of map bounds - reject }

  GameX := ResolvedX;
  GameZ := ResolvedZ;
  Result := True;
end;

procedure CaptureMousePosition;
var
  MouseUnit, p_Unit: PUnitStruct;
begin
  GetCursorPos(CurrMousePosition);

  { First choice: resolve wherever the mouse is on the map right now,
    even bare ground - same resolution the game itself uses for clicks. }
  if TryCaptureGroundClick(CapturedGameX, CapturedGameZ) then
  begin
    CapturedGameY := 0;
    CapturedValid := True;
    Notify('[OK] Position captured: X=' + IntToStr(CapturedGameX) +
           ' Z=' + IntToStr(CapturedGameZ));
    Exit;
  end;

  { Second choice: whatever unit is directly under the mouse cursor. }
  MouseUnit := TAUnit.AtMouse;
  if MouseUnit <> nil then
  begin
    CapturedGameX := TAUnit.GetUnitX(MouseUnit);
    CapturedGameZ := TAUnit.GetUnitZ(MouseUnit);
    CapturedGameY := TAUnit.GetUnitY(MouseUnit);
    CapturedValid := True;
    Notify('[OK] Position captured from unit under mouse: X=' + IntToStr(CapturedGameX) +
           ' Z=' + IntToStr(CapturedGameZ));
    Exit;
  end;

  { Last resort: ground-click resolution returned nothing usable and
    there's no unit under the mouse either. Use the selected unit's own
    current position. }
  if SelectedUnitId <> 0 then
  begin
    p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
    if (p_Unit <> nil) and (p_Unit.p_UNITINFO <> nil) then
    begin
      CapturedGameX := TAUnit.GetUnitX(p_Unit);
      CapturedGameZ := TAUnit.GetUnitZ(p_Unit);
      CapturedGameY := TAUnit.GetUnitY(p_Unit);
      CapturedValid := True;
      Notify('[OK] Position captured from selected unit: X=' + IntToStr(CapturedGameX) +
             ' Z=' + IntToStr(CapturedGameZ));
      Exit;
    end;
  end;

  CapturedValid := False;
  WriteLn('  [ERROR] Could not resolve a position - point at the map, hover a unit, or select one first');
end;

function GetGameCoordinatesFromMouse(out GameX, GameZ: Word): Boolean;
var
  MouseUnit: PUnitStruct;
begin
  Result := False;
  GameX := 0;
  GameZ := 0;

  { First choice: resolve wherever the mouse is on the map, even bare
    ground - same resolution the game itself uses for clicks. }
  if TryCaptureGroundClick(GameX, GameZ) then
  begin
    Result := True;
    Exit;
  end;

  { Fallback: whatever unit is directly under the mouse cursor. }
  MouseUnit := TAUnit.AtMouse;
  if MouseUnit <> nil then
  begin
    GameX := TAUnit.GetUnitX(MouseUnit);
    GameZ := TAUnit.GetUnitZ(MouseUnit);
    Result := True;
  end;
end;

{ ============================================================================= }
{ Unit Information Display                                                    }
{ ============================================================================= }

procedure ShowUnitInfo(UnitId: Word);
var
  p_Unit: PUnitStruct;
  X, Z, Y: Word;
  LongId: Cardinal;
  OwnerIdx: Integer;
  Health: Word;
  Speed: Integer;
begin
  p_Unit := TAUnit.Id2Ptr(UnitId);

  if p_Unit = nil then
  begin
    WriteLn('  [ERROR] Unit ' + IntToStr(UnitId) + ' not found');
    Exit;
  end;

  if p_Unit.p_UNITINFO = nil then
  begin
    WriteLn('  [ERROR] Unit ' + IntToStr(UnitId) + ' is not active');
    Exit;
  end;

  X := TAUnit.GetUnitX(p_Unit);
  Z := TAUnit.GetUnitZ(p_Unit);
  Y := TAUnit.GetUnitY(p_Unit);
  LongId := TAUnit.GetLongId(p_Unit);
  OwnerIdx := TAUnit.GetOwnerIndex(p_Unit);
  Health := TAUnit.GetHealth(p_Unit);
  Speed := TAUnit.GetCurrentSpeedVal(p_Unit);

  WriteLn('  ID:' + IntToStr(UnitId) + ' Long:' + IntToStr(LongId) + ' Pos:X' + IntToStr(X) +
           'Z' + IntToStr(Z) + 'Y' + IntToStr(Y) + ' Owner:P' + IntToStr(OwnerIdx) +
           ' HP:' + IntToStr(Health) + ' SPD:' + IntToStr(Speed));
end;

procedure ListAllUnits;
var
  i: Word;
  Count: Integer;
  p_Unit: PUnitStruct;
begin
  WriteLn('');
  WriteLn('  ACTIVE UNITS (First 20):');
  WriteLn('  ' + StringOfChar('-', 60));
  WriteLn('   ID    | Long ID    | Unit Name');
  WriteLn('  ' + StringOfChar('-', 60));

  Count := 0;
  for i := 0 to 4999 do
  begin
    p_Unit := TAUnit.Id2Ptr(i);
    if (p_Unit <> nil) and (p_Unit.p_UNITINFO <> nil) then
    begin
      { "also is there can we update the unit list nlogs with the unit names
        long ones i guess" (2026-08-17) - szUnitName is the human-readable
        display name field on TUnitInfo, same field KeyboardHook.pas's
        SpawnUnitsNearSelection already reads via implicit AnsiChar-array-
        to-String conversion. }
      WriteLn(Format('  %4d   | %10u | %s',
        [i, TAUnit.GetLongId(p_Unit), String(p_Unit.p_UNITINFO.szUnitName)]));
      Inc(Count);
      if Count >= 20 then
        Break;
    end;
  end;

  WriteLn('  ' + StringOfChar('-', 60));
  WriteLn('  Total shown: ' + IntToStr(Count) + ' units');
  WriteLn('');
end;

{ ============================================================================= }
{ Menu Display                                                                }
{ ============================================================================= }

procedure ShowMainMenu;
begin
  WriteLn('');
  WriteLn('  ================================');
  WriteLn('   UNIT CONSOLE - Main Menu');
  WriteLn('  ================================');
  WriteLn('');
  WriteLn('   1 - Selection & Info');
  WriteLn('   2 - Unit Status');
  WriteLn('   3 - Unit Control');
  WriteLn('   4 - Unit Orders');
  WriteLn('   5 - Advanced');
  WriteLn('   6 - Mouse Tools');
  WriteLn('');
  WriteLn('   20 - Exit console');
  WriteLn('');
end;

procedure ShowSelectionMenu;
begin
  WriteLn('');
  WriteLn('  === SELECTION & INFO ===');
  WriteLn('   1 - Select by ID');
  WriteLn('   2 - Select under mouse');
  WriteLn('   3 - Show selected info');
  WriteLn('   4 - List units');
  WriteLn('   5 - Show position');
  WriteLn('   0 - Back to main');
  WriteLn('');
end;

procedure ShowStatusMenu;
begin
  WriteLn('');
  WriteLn('  === UNIT STATUS ===');
  WriteLn('   1 - Health');
  WriteLn('   2 - Speed');
  WriteLn('   3 - Owner');
  WriteLn('   4 - Cloak status');
  WriteLn('   0 - Back to main');
  WriteLn('');
end;

procedure ShowControlMenu;
begin
  WriteLn('');
  WriteLn('  === UNIT CONTROL ===');
  WriteLn('   1 - Kill unit');
  WriteLn('   2 - Damage (enter amount)');
  WriteLn('   3 - Set speed (enter value)');
  WriteLn('   4 - Toggle cloak');
  WriteLn('   0 - Back to main');
  WriteLn('');
end;

procedure ShowOrdersMenu;
begin
  WriteLn('');
  WriteLn('  === UNIT ORDERS ===');
  WriteLn('   1 - Move to mouse');
  WriteLn('   2 - Patrol to mouse');
  WriteLn('   3 - Attack unit');
  WriteLn('   4 - Attack-Move');
  WriteLn('   5 - Stop');
  WriteLn('   6 - Guard unit');
  WriteLn('   7 - Reclaim');
  WriteLn('   8 - Cancel order');
  WriteLn('   9 - Load unit at mouse (pickup)');
  WriteLn('  10 - Unload at mouse');
  WriteLn('  11 - Unload at captured position');
  WriteLn('   0 - Back to main');
  WriteLn('');
end;

procedure ShowAdvancedMenu;
begin
  WriteLn('');
  WriteLn('  === ADVANCED ===');
  WriteLn('   1 - Teleport');
  WriteLn('   2 - Give to player');
  WriteLn('   3 - Update LOS');
  WriteLn('   0 - Back to main');
  WriteLn('');
end;

procedure ShowMouseMenu;
begin
  WriteLn('');
  WriteLn('  === MOUSE TOOLS ===');
  if CapturedValid then
    WriteLn('   Captured: X=' + IntToStr(CapturedGameX) + ' Z=' + IntToStr(CapturedGameZ))
  else
    WriteLn('   Captured: (none yet)');
  WriteLn('   1 - Capture mouse pos');
  WriteLn('   2 - Move to captured');
  WriteLn('   3 - Patrol to captured');
  WriteLn('   0 - Back to main');
  WriteLn('');
end;

procedure ShowMenu;
begin
  case CurrentMenu of
    0: ShowMainMenu;
    1: ShowSelectionMenu;
    2: ShowStatusMenu;
    3: ShowControlMenu;
    4: ShowOrdersMenu;
    5: ShowAdvancedMenu;
    6: ShowMouseMenu;
  end;
end;

{ ============================================================================= }
{ Unit Orders                                                                 }
{ ============================================================================= }

{ Shared order-issuing helper: takes explicit world coordinates so both the
  "to mouse" and "to captured" flows can share one code path instead of
  each re-sampling the mouse (which is what caused "to captured" to fail
  when the mouse had since moved off any unit). }
procedure GiveOrderToPosition(p_Unit: PUnitStruct; GameX, GameZ: Word;
  ActionType: TTAActionType; const ActionLabel: String);
var
  TargetPos: TPosition;
begin
  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
  begin
    WriteLn('  [ERROR] Unit no longer valid');
    Exit;
  end;

  TargetPos.X := Integer(GameX) * 65536;
  TargetPos.Z := Integer(GameZ) * 65536;
  TargetPos.Y := 0;

  TAUnit.CreateMainOrder(p_Unit, nil, ActionType, @TargetPos, 0, 0, 0);
  Notify('[OK] ' + ActionLabel + ' X=' + IntToStr(GameX) + ' Z=' + IntToStr(GameZ));
end;

procedure GiveOrderMove(p_Unit: PUnitStruct);
var
  MouseX, MouseZ: Word;
begin
  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
  begin
    WriteLn('  [ERROR] Unit no longer valid');
    Exit;
  end;

  if not GetGameCoordinatesFromMouse(MouseX, MouseZ) then
  begin
    WriteLn('  [ERROR] No unit at mouse position');
    Exit;
  end;

  GiveOrderToPosition(p_Unit, MouseX, MouseZ, Action_Move_Ground, 'Move to');
end;

procedure GiveOrderPatrol(p_Unit: PUnitStruct);
var
  MouseX, MouseZ: Word;
begin
  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
  begin
    WriteLn('  [ERROR] Unit no longer valid');
    Exit;
  end;

  if not GetGameCoordinatesFromMouse(MouseX, MouseZ) then
  begin
    WriteLn('  [ERROR] No unit at mouse position');
    Exit;
  end;

  GiveOrderToPosition(p_Unit, MouseX, MouseZ, TTAActionType(29), 'Patrol to');
end;

procedure GiveOrderMoveToCaptured(p_Unit: PUnitStruct);
begin
  if not CapturedValid then
  begin
    WriteLn('  [ERROR] No captured position yet - use option 1 first');
    Exit;
  end;
  GiveOrderToPosition(p_Unit, CapturedGameX, CapturedGameZ, Action_Move_Ground, 'Move to captured');
end;

procedure GiveOrderPatrolToCaptured(p_Unit: PUnitStruct);
begin
  if not CapturedValid then
  begin
    WriteLn('  [ERROR] No captured position yet - use option 1 first');
    Exit;
  end;
  GiveOrderToPosition(p_Unit, CapturedGameX, CapturedGameZ, TTAActionType(29), 'Patrol to captured');
end;

{ ============================================================================= }
{ Transport Load / Unload                                                    }
{ ============================================================================= }

{ Ground vs air transports use different order-type constants (confirmed via
  Ghidra decompile of Order2Unit's callers and cross-checked against the
  TTAActionType enum: Action_Ground_Pickup=20 / Action_Ground_Unload=21 for
  ships/hovers/ground transports, Action_VTOL_Pickup=57 / Action_VTOL_Unload=65
  for air transports). uiCanFly on the transport's own unit info tells us
  which family to use. }
function IsFlyingUnit(p_Unit: PUnitStruct): Boolean;
begin
  Result := False;
  if (p_Unit <> nil) and (p_Unit.p_UNITINFO <> nil) then
    Result := TAUnit.GetUnitInfoField(p_Unit, uiCanFly) = 1;
end;

{ OrderVTOLTransport_CheckSize @ $00489A90 - found via Ghidra. This is the
  exact native check the game itself runs (from UI_Get_Unit_At_Mouse_Position,
  cases 2/6) to decide the pickup cursor icon: candidate isn't flagged
  uncarryable, transport has the "CanLoad" bit set, transport isn't already
  at cTransportCap, candidate has a movement class, transport's
  cTransportSize covers the candidate's size class, candidate isn't mid
  attach/construction, and (for transports that require it) the candidate is
  at a liftable height. Despite the "VTOL" name it's the same function used
  for ground/sea transport compatibility too - only one branch inside it is
  air-specific, and it's a no-op for transports that don't need it.

  It's a real C++ __thiscall (this=transport in ECX, not on the Pascal
  parameter list), which none of this project's other native hooks use -
  they're all plain stdcall. That's why this needs an inline-asm wrapper
  instead of a simple function-pointer var.

  UPDATE (2026-08-17): this was the project's first use of a thiscall
  wrapper, and it crashed on first real-world use (right after the
  equivalent call in UnitPortal.pas's PortalFullCycle - diagnostic log
  showed nothing past that function's own entry line). No longer called
  anywhere - left defined here in case the calling convention gets sorted
  out later, but treat it as broken/unverified, not "should work". }
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

{ Diagnostic (2026-08-17): ground Load/Unload work fine issued via
  CreateMainOrder(..., Action_Ground_Pickup/Unload, ...) i.e. the raw
  TTAActionType ordinal - but VTOL transports just sit still on the same
  code path with Action_VTOL_Pickup/Unload. Working theory: the base
  native order types (Move/Patrol/Load/Unload/...) are a fixed C++ enum
  where our Pascal ordinals genuinely match, but VTOL_* variants are
  registered as COB script actions at runtime (same category as
  TELEPORT/RECLAIM/RESURRECT/REPAIRPATROL in OrdersOverride.pas, which
  ALWAYS resolve via TAMem.ScriptActionName2Index rather than a hardcoded
  ordinal) - so Action_VTOL_Unload=65's ordinal may simply not be the real
  runtime index for whatever VTOL_UNLOAD actually is. This calls
  Order2Unit directly with the runtime-resolved index instead of going
  through CreateMainOrder's Ord(ActionType), sidestepping the question of
  whether our enum's VTOL ordinals are right at all. Ground actions are
  left on the enum path since those are confirmed working - only touch
  what's actually broken. }
function IssueScriptOrder(p_Unit, TargetUnit: PUnitStruct;
  const ScriptActionName: String; Position: PPosition; ShiftKey: Byte): LongInt;
var
  ScriptIndex: Byte;
begin
  ScriptIndex := TAMem.ScriptActionName2Index(ScriptActionName);
  LogUnload('  IssueScriptOrder(''' + ScriptActionName + '''): ScriptActionName2Index resolved to ' +
    IntToStr(ScriptIndex));
  Result := Order2Unit(ScriptIndex, ShiftKey, p_Unit, TargetUnit, Position, 0, 0);
  LogUnload('  Order2Unit(ScriptIndex=' + IntToStr(ScriptIndex) + ') returned ' + IntToStr(Result));
end;

{ "when it trys to unloaded more than one unit it says its unnable to is way
  of nugding the transport to unload ? maybe use same kind techice the
  search raduis does ?" / "bascily i t cant leave the unload aerea in till
  its unload all units try agin try again around the primter of the drop
  off" (2026-08-17) - same retry-loop shape as TAUnits.CreateMinions
  (TA_MemUnits.pas) and KeyboardHook.pas's SpawnUnitsNearSelection: walk
  outward in expanding rings around CenterPos, testing candidate spots with
  TAUnit.TestUnloadPosition (proven safe to call repeatedly from this
  console-command context throughout this project - unlike TestBuildSpot,
  which crashes when called outside COB script context).

  Honest limitation: this mod has no live "did the unload actually finish"
  event hook - the order below is queued once, synchronously, ahead of real
  play time, same as everything else this project issues. So this can't
  literally watch the transport sit in the drop-off zone and keep nudging
  in real time if the first attempt silently fails once play resumes. What
  it CAN do: use TestUnloadPosition as a stand-in for "is there actually
  room here" and search outward until it finds a spot that passes, instead
  of only ever trying the one exact point and giving up. Duplicated from
  UnitPortal.pas's copy of the same function - same reasoning as
  IssueScriptOrder above for why this file has its own copy rather than
  sharing one unit. }
function FindNearestValidUnloadSpot(p_Unit: PUnitStruct; const CenterPos: TPosition;
  out ResultPos: TPosition): Boolean;
const
  MaxRadius = 300;      { world units - how far out around the drop-off we're willing to search }
  RadiusStep = 30;      { ring spacing, world units }
  AnglesPerRing = 12;   { candidate points tested per ring }
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

  LogUnload('  FindNearestValidUnloadSpot: exact drop-off spot rejected, searching perimeter (up to radius=' +
    IntToStr(MaxRadius) + ')...');

  Radius := RadiusStep;
  while Radius <= MaxRadius do
  begin
    for i := 0 to AnglesPerRing - 1 do
    begin
      AngleVal := Round((360 / AnglesPerRing) * i);
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
            LogUnload('  FindNearestValidUnloadSpot: found valid spot at radius=' + IntToStr(Radius) +
              ' angle=' + IntToStr(AngleVal) + ' -> X=' + IntToStr(CandPos.X) + ' Z=' + IntToStr(CandPos.Z));
            ResultPos := CandPos;
            Result := True;
            Exit;
          end;
        end;
      end;
    end;
    Inc(Radius, RadiusStep);
  end;

  LogUnload('  FindNearestValidUnloadSpot: exhausted search up to radius=' + IntToStr(MaxRadius) +
    ' - no valid drop-off spot found');
end;

{ Loads (picks up) the unit currently under the mouse cursor into the
  selected transport. Mirrors the vanilla "Load" button + click-a-unit UX,
  but issues the order directly instead of going through the game's
  click-to-prepare-order GUI state machine (SetPrepareOrder/MOUSE_EVENT_2UnitOrder). }
procedure GiveOrderLoadUnit(p_Unit: PUnitStruct);
var
  p_Cargo: PUnitStruct;
  CargoId: Word;
begin
  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
  begin
    WriteLn('  [ERROR] Unit no longer valid');
    Exit;
  end;

  { TAUnit.AtMouse returns a PUnitStruct directly, not a Word ID - see
    GetGameCoordinatesFromMouse above for the same pattern. }
  p_Cargo := TAUnit.AtMouse;
  if (p_Cargo = nil) or (p_Cargo.p_UNITINFO = nil) then
  begin
    WriteLn('  [ERROR] No unit under mouse to load - hover the unit you want to pick up');
    Exit;
  end;

  CargoId := TAUnit.GetId(p_Cargo);
  if CargoId = SelectedUnitId then
  begin
    WriteLn('  [ERROR] Cannot load a transport into itself');
    Exit;
  end;

  { NativeCheckTransportFit pre-check removed (2026-08-17): a crash
    reproduced right after the equivalent check in UnitPortal.pas's
    PortalFullCycle, with the log showing nothing past its own entry line
    - the signature of the inline-asm thiscall call not returning cleanly.
    That was always flagged as this project's first (and only) thiscall
    call, unverified until real use - this is that verification, and it
    failed. Dropping the pre-check entirely rather than risk-wrapping it:
    the native Pickup order handler already validates compatibility
    itself when the order actually executes (that's the whole reason
    OrderVTOLTransport_CheckSize exists as a pure UI/cursor helper in the
    first place - see its own comment below), so an incompatible pairing
    just won't attach instead of crashing the mod. }

  if IsFlyingUnit(p_Unit) then
    IssueScriptOrder(p_Unit, p_Cargo, 'VTOL_PICKUP', nil, 0)
  else
    TAUnit.CreateMainOrder(p_Unit, p_Cargo, Action_Ground_Pickup, nil, 0, 0, 0);

  Notify('[OK] Load order issued - picking up unit ' + IntToStr(CargoId));
end;

{ Shared unload helper: takes explicit world coordinates so "to mouse" and
  "to captured" share one code path, same reasoning as GiveOrderToPosition. }
procedure GiveOrderUnloadAt(p_Unit: PUnitStruct; GameX, GameZ: Word);
var
  TargetPos, ActualUnloadPos: TPosition;
  TestResult: Boolean;
  OrderResult: LongInt;
  CurX, CurY, CurZ: Word;
begin
  LogUnload('---- GiveOrderUnloadAt called ----');

  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
  begin
    LogUnload('  ABORT: p_Unit or p_Unit.p_UNITINFO is nil');
    WriteLn('  [ERROR] Unit no longer valid');
    Exit;
  end;

  LogUnload('  UnitID=' + IntToStr(SelectedUnitId) +
    ' TargetGameX=' + IntToStr(GameX) + ' TargetGameZ=' + IntToStr(GameZ));

  CurX := TAUnit.GetUnitX(p_Unit);
  CurY := TAUnit.GetUnitY(p_Unit);
  CurZ := TAUnit.GetUnitZ(p_Unit);
  LogUnload('  Unit current position: X=' + IntToStr(CurX) + ' Y=' + IntToStr(CurY) +
    ' Z=' + IntToStr(CurZ));

  if p_Unit.p_MovementClass = nil then
    LogUnload('  WARNING: p_Unit.p_MovementClass = nil - this unit has no movement class and CANNOT move at all, regardless of what order is issued')
  else
    LogUnload('  p_Unit.p_MovementClass <> nil (unit can move)');

  if p_Unit.p_MainOrder = nil then
    LogUnload('  Unit currently idle (p_MainOrder = nil) before this order')
  else
    LogUnload('  Unit currently has an active order before this one: cOrderType=' +
      IntToStr(p_Unit.p_MainOrder.cOrderType) + ' ucState=' + IntToStr(p_Unit.p_MainOrder.ucState));

  { p_TransportedUnit is a plain field on TUnitStruct (TA_MemoryStructures.pas).
    If this transport has nothing loaded, an Unload order may get accepted
    into the queue (icon shows) but never actually do anything, including
    the approach movement - which would look exactly like "icon shows up,
    unit just sits there". }
  if p_Unit.p_TransportedUnit = nil then
    LogUnload('  WARNING: p_Unit.p_TransportedUnit = nil - this transport has NOTHING loaded to unload')
  else
    LogUnload('  p_Unit.p_TransportedUnit <> nil (transport is carrying something)');

  TargetPos.X := Integer(GameX) * 65536;
  TargetPos.Z := Integer(GameZ) * 65536;
  TargetPos.Y := 0;
  LogUnload('  TargetPos (16.16 fixed-point): X=' + IntToStr(TargetPos.X) +
    ' Z=' + IntToStr(TargetPos.Z) + ' Y=' + IntToStr(TargetPos.Y));

  { Nudge/retry (2026-08-17): search around TargetPos for a spot that
    actually accepts an unload instead of aborting on the first rejection -
    see FindNearestValidUnloadSpot's comment above. This is our best
    available signal for "is there room here" (TA_MemUnits.pas's already-
    wrapped BuildPosition2Grid + CanAttachAtGridSpot combo), same as before,
    just retried outward instead of only checked once. }
  TestResult := FindNearestValidUnloadSpot(p_Unit, TargetPos, ActualUnloadPos);
  LogUnload('  FindNearestValidUnloadSpot result: ' + BoolToStr(TestResult, True));
  if not TestResult then
  begin
    LogUnload('  ABORT: no valid unload spot found nearby');
    WriteLn('  [ERROR] Cannot unload there - no free spot found nearby');
    Exit;
  end;

  if IsFlyingUnit(p_Unit) then
  begin
    LogUnload('  IsFlyingUnit=True -> issuing via ScriptActionName2Index(''VTOL_UNLOAD'') instead of the enum ordinal (see IssueScriptOrder comment)');
    OrderResult := IssueScriptOrder(p_Unit, nil, 'VTOL_UNLOAD', @ActualUnloadPos, 0);
  end else
  begin
    LogUnload('  IsFlyingUnit=False -> issuing via Action_Ground_Unload (ord=' + IntToStr(Ord(Action_Ground_Unload)) + ')');
    OrderResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Ground_Unload, @ActualUnloadPos, 0, 0, 0);
  end;
  LogUnload('  Order issue returned: ' + IntToStr(OrderResult));

  { Read back what actually landed on the unit right after issuing, so we
    can see whether the order that's actually queued matches what we just
    asked for, instead of guessing from in-game icons alone. }
  if p_Unit.p_MainOrder = nil then
    LogUnload('  POST-ORDER: p_MainOrder is nil (!) - order did not attach')
  else
    LogUnload('  POST-ORDER: cOrderType=' + IntToStr(p_Unit.p_MainOrder.cOrderType) +
      ' ucState=' + IntToStr(p_Unit.p_MainOrder.ucState) +
      ' Position=(' + IntToStr(p_Unit.p_MainOrder.Position.X) + ',' +
      IntToStr(p_Unit.p_MainOrder.Position.Z) + ',' +
      IntToStr(p_Unit.p_MainOrder.Position.Y) + ')' +
      ' p_NextOrder=' + BoolToStr(p_Unit.p_MainOrder.p_NextOrder <> nil, True));

  Notify('[OK] Unload order issued X=' + IntToStr(GameX) + ' Z=' + IntToStr(GameZ));
end;

procedure GiveOrderUnload(p_Unit: PUnitStruct);
var
  MouseX, MouseZ: Word;
begin
  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
  begin
    WriteLn('  [ERROR] Unit no longer valid');
    Exit;
  end;

  if not GetGameCoordinatesFromMouse(MouseX, MouseZ) then
  begin
    WriteLn('  [ERROR] Could not resolve a position - point at the map or hover a unit');
    Exit;
  end;

  GiveOrderUnloadAt(p_Unit, MouseX, MouseZ);
end;

procedure GiveOrderUnloadToCaptured(p_Unit: PUnitStruct);
begin
  if not CapturedValid then
  begin
    WriteLn('  [ERROR] No captured position yet - use Mouse Tools option 1 first');
    Exit;
  end;
  GiveOrderUnloadAt(p_Unit, CapturedGameX, CapturedGameZ);
end;

{ ============================================================================= }
{ Stop / Guard / Reclaim                                                     }
{ ============================================================================= }

procedure GiveOrderStop(p_Unit: PUnitStruct);
begin
  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
  begin
    WriteLn('  [ERROR] Unit no longer valid');
    Exit;
  end;

  TAUnit.CreateMainOrder(p_Unit, nil, Action_Stop, nil, 0, 0, 0);
  Notify('[OK] Stop order issued');
end;

{ Guards the unit under the mouse cursor. Same "target unit under mouse"
  pattern as GiveOrderLoadUnit above. }
procedure GiveOrderGuard(p_Unit: PUnitStruct);
var
  p_Target: PUnitStruct;
  TargetId: Word;
begin
  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
  begin
    WriteLn('  [ERROR] Unit no longer valid');
    Exit;
  end;

  { TAUnit.AtMouse returns a PUnitStruct directly, not a Word ID. }
  p_Target := TAUnit.AtMouse;
  if (p_Target = nil) or (p_Target.p_UNITINFO = nil) then
  begin
    WriteLn('  [ERROR] No unit under mouse to guard - hover the unit you want to protect');
    Exit;
  end;

  TargetId := TAUnit.GetId(p_Target);
  if TargetId = SelectedUnitId then
  begin
    WriteLn('  [ERROR] A unit cannot guard itself');
    Exit;
  end;

  TAUnit.CreateMainOrder(p_Unit, p_Target, Action_Guard_NoMove, nil, 0, 0, 0);
  Notify('[OK] Guard order issued - guarding unit ' + IntToStr(TargetId));
end;

{ Reclaims whatever reclaimable feature (wreck/tree/rock) is at the mouse's
  ground position. Confirmed against the project's own existing reclaim
  code in OrdersOverride.pas (Portal_AutoResurrectScan), which issues a
  native reclaim order the same way: ScriptActionName2Index('RECLAIM')
  targeting a feature's ground position. TTAActionType's ordinals are the
  same native script-action indices that ScriptActionName2Index resolves
  by name - Action_Reclaim = 32 there is the same numeric value
  ScriptActionName2Index('RECLAIM') would return - so this reuses the
  existing position-based GiveOrderToPosition helper rather than
  duplicating that lower-level ORDERS_CreateObject/PushOrder plumbing,
  which exists there for a different reason (auto-resuming the unit's
  prior order afterward, not needed for a one-shot manual command). }
procedure GiveOrderReclaim(p_Unit: PUnitStruct);
var
  MouseX, MouseZ: Word;
begin
  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
  begin
    WriteLn('  [ERROR] Unit no longer valid');
    Exit;
  end;

  if not GetGameCoordinatesFromMouse(MouseX, MouseZ) then
  begin
    WriteLn('  [ERROR] Could not resolve a position - point at the map or hover a unit');
    Exit;
  end;

  GiveOrderToPosition(p_Unit, MouseX, MouseZ, Action_Reclaim, 'Reclaim at');
end;

{ ============================================================================= }
{ Menu Processing                                                             }
{ ============================================================================= }

procedure ProcessMenuChoice(const Choice: String; var WaitingForInput: Boolean; var InputMode: Integer);
var
  MenuOption: Integer;
  p_Unit: PUnitStruct;
begin
  MenuOption := 0;

  try
    MenuOption := StrToInt(Trim(Choice));
  except
    WriteLn('  [ERROR] Invalid input');
    Exit;
  end;

  { Main menu selection }
  if CurrentMenu = 0 then
  begin
    case MenuOption of
      1..6: begin
        CurrentMenu := MenuOption;
        ShowMenu;
      end;

      20: begin
        WriteLn('  Closing console...');
        ConsoleActive := False;
      end;

      else
        WriteLn('  [ERROR] Invalid option');
    end;
  end else
  begin
    { Submenu processing }
    case CurrentMenu of
      1: begin  { Selection }
        case MenuOption of
          1: begin
            WriteLn('');
            Write('  Enter Unit ID: ');
            WaitingForInput := True;
            InputMode := 1;
          end;
          2: begin
            p_Unit := TAUnit.AtMouse;
            if p_Unit <> nil then
            begin
              SelectedUnitId := TAUnit.GetId(p_Unit);
              Notify('[OK] Selected unit under mouse: ' + IntToStr(SelectedUnitId));
              ShowUnitInfo(SelectedUnitId);
            end else
              WriteLn('  [INFO] No unit under mouse');
          end;
          3: begin
            if SelectedUnitId = 0 then
              WriteLn('  [INFO] No unit selected')
            else
              ShowUnitInfo(SelectedUnitId);
          end;
          4: ListAllUnits;
          5: begin
            if SelectedUnitId = 0 then
              WriteLn('  [INFO] No unit selected')
            else
            begin
              p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
              if (p_Unit <> nil) and (p_Unit.p_UNITINFO <> nil) then
                WriteLn('  Position: X=' + IntToStr(TAUnit.GetUnitX(p_Unit)) +
                         ', Z=' + IntToStr(TAUnit.GetUnitZ(p_Unit)) +
                         ', Y=' + IntToStr(TAUnit.GetUnitY(p_Unit)))
              else
                WriteLn('  [ERROR] Unit no longer valid');
            end;
          end;
          0: begin
            CurrentMenu := 0;
            ShowMenu;
          end;
          else WriteLn('  [ERROR] Invalid option');
        end;
      end;

      2: begin  { Status }
        case MenuOption of
          1: begin
            if SelectedUnitId = 0 then
              WriteLn('  [INFO] No unit selected')
            else
            begin
              p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
              if (p_Unit <> nil) and (p_Unit.p_UNITINFO <> nil) then
                WriteLn('  Health: ' + IntToStr(TAUnit.GetHealth(p_Unit)))
              else
                WriteLn('  [ERROR] Unit no longer valid');
            end;
          end;
          2: begin
            if SelectedUnitId = 0 then
              WriteLn('  [INFO] No unit selected')
            else
            begin
              p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
              if (p_Unit <> nil) and (p_Unit.p_UNITINFO <> nil) then
                WriteLn('  Speed: ' + IntToStr(TAUnit.GetCurrentSpeedVal(p_Unit)))
              else
                WriteLn('  [ERROR] Unit no longer valid');
            end;
          end;
          3: begin
            if SelectedUnitId = 0 then
              WriteLn('  [INFO] No unit selected')
            else
            begin
              p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
              if (p_Unit <> nil) and (p_Unit.p_UNITINFO <> nil) then
                WriteLn('  Owner: Player ' + IntToStr(TAUnit.GetOwnerIndex(p_Unit)))
              else
                WriteLn('  [ERROR] Unit no longer valid');
            end;
          end;
          4: begin
            if SelectedUnitId = 0 then
              WriteLn('  [INFO] No unit selected')
            else
            begin
              p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
              if (p_Unit <> nil) and (p_Unit.p_UNITINFO <> nil) then
              begin
                if TAUnit.GetCloak(p_Unit) = 1 then
                  WriteLn('  Status: CLOAKED')
                else
                  WriteLn('  Status: VISIBLE');
              end else
                WriteLn('  [ERROR] Unit no longer valid');
            end;
          end;
          0: begin
            CurrentMenu := 0;
            ShowMenu;
          end;
          else WriteLn('  [ERROR] Invalid option');
        end;
      end;

      3: begin  { Control }
        case MenuOption of
          1: begin
            if SelectedUnitId = 0 then
              WriteLn('  [INFO] No unit selected')
            else
            begin
              p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
              if (p_Unit <> nil) and (p_Unit.p_UNITINFO <> nil) then
              begin
                TAUnit.Kill(p_Unit, 3);
                Notify('[OK] Unit killed');
                SelectedUnitId := 0;
              end else
                WriteLn('  [ERROR] Unit no longer valid');
            end;
          end;
          2: begin
            if SelectedUnitId = 0 then
              WriteLn('  [INFO] No unit selected')
            else
            begin
              WriteLn('');
              Write('  Damage amount: ');
              WaitingForInput := True;
              InputMode := 11;
            end;
          end;
          3: begin
            if SelectedUnitId = 0 then
              WriteLn('  [INFO] No unit selected')
            else
            begin
              WriteLn('');
              Write('  Speed value: ');
              WaitingForInput := True;
              InputMode := 12;
            end;
          end;
          4: begin
            if SelectedUnitId = 0 then
              WriteLn('  [INFO] No unit selected')
            else
            begin
              p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
              if (p_Unit <> nil) and (p_Unit.p_UNITINFO <> nil) then
              begin
                if TAUnit.GetCloak(p_Unit) = 1 then
                begin
                  TAUnit.SetCloak(p_Unit, 0);
                  Notify('[OK] Cloak disabled');
                end else
                begin
                  TAUnit.SetCloak(p_Unit, 1);
                  Notify('[OK] Cloak enabled');
                end;
              end else
                WriteLn('  [ERROR] Unit no longer valid');
            end;
          end;
          0: begin
            CurrentMenu := 0;
            ShowMenu;
          end;
          else WriteLn('  [ERROR] Invalid option');
        end;
      end;

      4: begin  { Orders }
        case MenuOption of
          1: begin
            if SelectedUnitId = 0 then
              WriteLn('  [INFO] No unit selected')
            else
            begin
              p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
              GiveOrderMove(p_Unit);
            end;
          end;
          2: begin
            if SelectedUnitId = 0 then
              WriteLn('  [INFO] No unit selected')
            else
            begin
              p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
              GiveOrderPatrol(p_Unit);
            end;
          end;
          3, 4, 8: WriteLn('  [INFO] Command not yet implemented');
          5: begin
            if SelectedUnitId = 0 then
              WriteLn('  [INFO] No unit selected')
            else
            begin
              p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
              GiveOrderStop(p_Unit);
            end;
          end;
          6: begin
            if SelectedUnitId = 0 then
              WriteLn('  [INFO] No unit selected')
            else
            begin
              p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
              GiveOrderGuard(p_Unit);
            end;
          end;
          7: begin
            if SelectedUnitId = 0 then
              WriteLn('  [INFO] No unit selected')
            else
            begin
              p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
              GiveOrderReclaim(p_Unit);
            end;
          end;
          9: begin
            if SelectedUnitId = 0 then
              WriteLn('  [INFO] No unit selected')
            else
            begin
              p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
              GiveOrderLoadUnit(p_Unit);
            end;
          end;
          10: begin
            if SelectedUnitId = 0 then
              WriteLn('  [INFO] No unit selected')
            else
            begin
              p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
              GiveOrderUnload(p_Unit);
            end;
          end;
          11: begin
            if SelectedUnitId = 0 then
              WriteLn('  [INFO] No unit selected')
            else
            begin
              p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
              GiveOrderUnloadToCaptured(p_Unit);
            end;
          end;
          0: begin
            CurrentMenu := 0;
            ShowMenu;
          end;
          else WriteLn('  [ERROR] Invalid option');
        end;
      end;

      5: begin  { Advanced }
        case MenuOption of
          1: WriteLn('  [INFO] Teleport not yet implemented');
          2: begin
            if SelectedUnitId = 0 then
              WriteLn('  [INFO] No unit selected')
            else
            begin
              WriteLn('');
              Write('  Player index (0-10): ');
              WaitingForInput := True;
              InputMode := 15;
            end;
          end;
          3: begin
            if SelectedUnitId = 0 then
              WriteLn('  [INFO] No unit selected')
            else
            begin
              p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
              if (p_Unit <> nil) and (p_Unit.p_UNITINFO <> nil) then
              begin
                TAUnit.UpdateLos(p_Unit);
                Notify('[OK] LOS updated');
              end else
                WriteLn('  [ERROR] Unit no longer valid');
            end;
          end;
          0: begin
            CurrentMenu := 0;
            ShowMenu;
          end;
          else WriteLn('  [ERROR] Invalid option');
        end;
      end;

      6: begin  { Mouse }
        case MenuOption of
          1: CaptureMousePosition;
          2: begin
            if SelectedUnitId = 0 then
              WriteLn('  [INFO] No unit selected')
            else
            begin
              p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
              GiveOrderMoveToCaptured(p_Unit);
            end;
          end;
          3: begin
            if SelectedUnitId = 0 then
              WriteLn('  [INFO] No unit selected')
            else
            begin
              p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
              GiveOrderPatrolToCaptured(p_Unit);
            end;
          end;
          0: begin
            CurrentMenu := 0;
            ShowMenu;
          end;
          else WriteLn('  [ERROR] Invalid option');
        end;
      end;
    end;
  end;
end;

{ ============================================================================= }
{ Input Processing in Thread                                                  }
{ ============================================================================= }

function ConsoleThreadProc(Param: Pointer): Integer; stdcall;
var
  InputHandle: THandle;
  Buffer: array[0..255] of Char;
  CharsRead: Cardinal;
  Input: String;
  WaitingForInput: Boolean;
  InputMode: Integer;
  UnitId: Word;
  DamageAmount: Integer;
  NewSpeed: Cardinal;
  PlayerIdx: Byte;
  p_Unit: PUnitStruct;
begin
  Result := 0;

  try
    InputHandle := GetStdHandle(STD_INPUT_HANDLE);
    WaitingForInput := False;
    InputMode := 0;
    CurrentMenu := 0;

    ShowMenu;

    while ConsoleActive do
    begin
      if WaitingForInput then
      begin
        case InputMode of
          1:  Write('  > Unit ID: ');
          11: Write('  > Damage: ');
          12: Write('  > Speed: ');
          15: Write('  > Player: ');
        end;
      end else
        Write('  > ');

      FillChar(Buffer, SizeOf(Buffer), 0);

      if ReadFile(InputHandle, Buffer, SizeOf(Buffer), CharsRead, nil) then
      begin
        if CharsRead > 0 then
        begin
          if Buffer[CharsRead - 1] = #13 then
            Buffer[CharsRead - 1] := #0;

          Input := Trim(String(PChar(@Buffer)));

          if Input = '' then
            Continue;

          if WaitingForInput then
          begin
            case InputMode of
              1: begin
                try
                  UnitId := StrToInt(Input);
                  p_Unit := TAUnit.Id2Ptr(UnitId);
                  if (p_Unit <> nil) and (p_Unit.p_UNITINFO <> nil) then
                  begin
                    SelectedUnitId := UnitId;
                    Notify('[OK] Selected Unit: ' + IntToStr(UnitId));
                    ShowUnitInfo(UnitId);
                    WaitingForInput := False;
                    ShowMenu;
                  end else
                    WriteLn('  [ERROR] Unit does not exist');
                except
                  WriteLn('  [ERROR] Invalid ID');
                end;
              end;

              11: begin
                try
                  DamageAmount := StrToInt(Input);
                  p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
                  if (p_Unit <> nil) and (p_Unit.p_UNITINFO <> nil) then
                  begin
                    TAUnit.MakeDamage(nil, p_Unit, dtWeapon, DamageAmount);
                    Notify('[OK] Applied ' + IntToStr(DamageAmount) + ' damage');
                    WaitingForInput := False;
                    ShowMenu;
                  end else
                    WriteLn('  [ERROR] Unit no longer valid');
                except
                  WriteLn('  [ERROR] Invalid amount');
                end;
              end;

              12: begin
                try
                  NewSpeed := StrToInt(Input);
                  p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
                  if (p_Unit <> nil) and (p_Unit.p_UNITINFO <> nil) then
                  begin
                    TAUnit.SetCurrentSpeed(p_Unit, NewSpeed);
                    Notify('[OK] Speed set to ' + IntToStr(NewSpeed));
                    WaitingForInput := False;
                    ShowMenu;
                  end else
                    WriteLn('  [ERROR] Unit no longer valid');
                except
                  WriteLn('  [ERROR] Invalid speed value');
                end;
              end;

              15: begin
                try
                  PlayerIdx := StrToInt(Input);
                  p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
                  if (p_Unit <> nil) and (p_Unit.p_UNITINFO <> nil) then
                  begin
                    TAUnits.GiveUnit(p_Unit, PlayerIdx);
                    Notify('[OK] Unit given to player ' + IntToStr(PlayerIdx));
                    WaitingForInput := False;
                    ShowMenu;
                  end else
                    WriteLn('  [ERROR] Unit no longer valid');
                except
                  WriteLn('  [ERROR] Invalid player index');
                end;
              end;
            end;
          end else
          begin
            ProcessMenuChoice(Input, WaitingForInput, InputMode);
            if ConsoleActive and not WaitingForInput then
              ShowMenu;
          end;
        end;
      end else
        Break;

      if not ConsoleActive then
        Break;
    end;

    WriteLn('');
    WriteLn('  Console closed.');

  except
    on E: Exception do
      WriteLn('  [EXCEPTION] ' + E.Message);
  end;
end;

{ ============================================================================= }
{ Console Lifecycle                                                           }
{ ============================================================================= }

procedure OpenConsole;
var
  ThreadId: Cardinal;
begin
  if ConsoleActive then
    Exit;

  if AllocConsole then
  begin
    ConsoleHandle := GetStdHandle(STD_OUTPUT_HANDLE);
    ConsoleActive := True;
    SelectedUnitId := 0;
    CurrentMenu := 0;

    ConsoleThread := CreateThread(
      nil, 0, @ConsoleThreadProc, nil, 0, ThreadId
    );

    if ConsoleThread = 0 then
    begin
      FreeConsole;
      ConsoleActive := False;
      ConsoleHandle := 0;
    end;
  end;
end;

procedure CloseConsole;
begin
  if not ConsoleActive then
    Exit;

  ConsoleActive := False;

  if ConsoleThread <> 0 then
  begin
    WaitForSingleObject(ConsoleThread, 2000);
    CloseHandle(ConsoleThread);
    ConsoleThread := 0;
  end;

  if ConsoleHandle <> 0 then
  begin
    FreeConsole;
    ConsoleHandle := 0;
  end;
end;

procedure ToggleUnitConsole;
begin
  if ConsoleActive then
    CloseConsole
  else
    OpenConsole;
end;

initialization
  ConsoleActive := False;
  ConsoleHandle := 0;
  ConsoleThread := 0;
  SelectedUnitId := 0;
  CurrentMenu := 0;
  CapturedValid := False;

  { Game's own screen-click -> world-ground resolver, found via Ghidra
    (see TryCaptureGroundClick). }
  Pointer(@Map_ScreenToWorldClick) := Pointer($00498DA0);

finalization
  if ConsoleActive then
    CloseConsole;

end.
