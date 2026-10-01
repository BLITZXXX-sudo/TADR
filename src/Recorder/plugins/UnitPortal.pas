unit UnitPortal;
{
  Portal System for Total Annihilation
  Hotkey: Alt+Shift+K to open/close

  - Select a unit
  - Set Source and Destination positions from the unit under the mouse
  - Move/Teleport the selected unit to those positions
}

interface

uses
  TA_MemoryStructures;  { PUnitStruct - needed here now that GetNativeSelectedUnit
                          and the PortalHotkey_* procedures are exported below
                          (2026-08-18, fixes "Identifier not found PUnitStruct") }

procedure TogglePortalConsole;

{ 2026-08-18 - "I WILL WANT TO JUST HOT KEY IT SOON SO THE MAIN UNIT GETS
  SETS SROUCE AT ITS CURRENT LOCTION AND THEN THE HOT KEY TRIGGERS THE DES
  AND THEN SELECTED THE TRANSPORT UNIT THEN STARTS THE LOOP" - exported so a
  future global hotkey (wired up wherever KeyboardHook.pas's other hotkeys
  live) can drive the whole Source -> Destination -> arm transport ->
  Continuous Auto-Cycle flow directly, without opening the portal console at
  all. Two calls, one per hotkey:
    1) PortalHotkey_SetSourceFromSelection      - press with the pickup-point
       unit selected in-game.
    2) PortalHotkey_SetDestArmTransportAndStartLoop - press with the
       transport itself selected, standing at the drop-off point; sets
       Destination there, locks that unit in as the loop's transport, and
       starts the Continuous Auto-Cycle immediately.
  See GetNativeSelectedUnit's comment for how "currently selected" is read -
  the game's own in-game selection highlight, not this console's separate
  SelectedUnitId (which only ever changes via the console's own menu). }
function GetNativeSelectedUnit: PUnitStruct;
procedure PortalHotkey_SetSourceFromSelection;
procedure PortalHotkey_SetDestArmTransportAndStartLoop;

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
  ConsoleHandle: THandle = 0;
  ConsoleThread: THandle = 0;
  ConsoleActive: Boolean = False;
  SelectedUnitId: Word = 0;

  { Portal positions }
  SourcePos: TPortalPos;
  DestPos: TPortalPos;

  { UI State }
  CurrentMenu: Integer = 0;  { 0=Main }

  { Continuous Auto-Cycle (2026-08-17) - "is there a option 11 to turn on
    contuioesly": see the AutoLoop section below (near PortalFullCycleAuto)
    for the full writeup. AutoLoopUnitId is the transport locked in when
    the loop was switched on - Option 11 re-captures it each time it's
    toggled on, it does NOT follow later unit-selection changes.

    UPDATE (2026-08-18): "AFTER ONE DROP IT RETURN BACK THE SROUCE LOCTION
    DOESNT PICK UP ANY MORE UNITS UNLESS I ACTIAVTE 10" plus a diagnostic
    log with ZERO "AutoLoop: tick fired" lines despite the timer being
    enabled for 30-70+ second stretches - the TConsoleTimer-based background
    thread was never actually calling its own tick handler at all (its
    Execute loop must be exiting immediately after start, before the first
    wait even completes - see the AutoLoopThread section below for the
    replacement). Switched to a plain CreateThread + Sleep loop instead,
    the exact same mechanism OpenPortalConsole already uses successfully
    for ConsoleThread itself - fewer moving parts than TThread/TSimpleEvent,
    and proven to actually run in this exact file. }
  AutoLoopEnabled: Boolean = False;
  AutoLoopUnitId: Word = 0;
  AutoLoopThreadHandle: THandle = 0;
  AutoLoopThreadActive: Boolean = False;

  { ============================================================================= }
  { Tunable settings (2026-08-18)                                                }
  { "CAN U SET SOME VARRIBIES AT TOP SO I CAN ADJUST THE SPACING AND SEARCH      }
  { RADUIS ETC" - everything below used to be a `const` buried inside whichever  }
  { function happened to use it. Now it's all in one place, and since these are  }
  { plain `var`s (not `const`s) menu option 12 - Settings can also change them   }
  { at runtime from the console without a recompile - see ShowTunableSettings /  }
  { ApplyTunableSetting further down. }
  { ============================================================================= }
  Cfg_PickupScanRadius: Integer = 300;
    { world units around Source to scan for loadable cargo - PortalFullCycleAuto
      and the AutoLoop background thread's own pre-check both use this. }
  Cfg_UnloadSearchMaxRadius: Integer = 300;
    { world units - how far out around a drop-off point FindNearestValidUnloadSpot /
      FindMultipleValidUnloadSpots are willing to search for a free spot. }
  Cfg_UnloadSearchRadiusStep: Integer = 30;
    { ring spacing for that outward unload-spot search, world units. }
  Cfg_UnloadSearchAnglesPerRing: Integer = 12;
    { candidate points tested per ring during that search. }
  Cfg_UnloadMinSeparation: Integer = 80;
    { world units - minimum gap FindMultipleValidUnloadSpots keeps between two
      drop-off spots so two landed units don't physically overlap. Was 40,
      bumped to 80 (2026-08-18) - see FindMultipleValidUnloadSpots' comment. }
  Cfg_AutoLoopPollMs: Integer = 3000;
    { how often (ms) the Continuous Auto-Cycle background thread checks in. }
  Cfg_ShowConsoleOnHotkey: Integer = 0;
    { "SET INTHE PAS A OPTION TO DISPLAY THE CONSOLE AS A DEGUB ON OFF"
      (2026-08-18): 0/1 flag (Integer, not Boolean, so ApplyTunableSetting's
      shared "<number> <new value>" console input keeps working the same
      way as every other Cfg_* setting here). 0 (default) = the hotkey's
      automated Source/Dest/Start-Loop flow runs completely silently, no
      console window pops up - true one-click. 1 = console window shows as
      it always did, for when actually debugging the transport. LogUnload
      keeps writing to UnloadDiag.log either way, so nothing is lost by
      hiding the window - see OpenPortalConsole/ClosePortalConsole. }

  { Game's own screen-click -> world-ground resolver (handles terrain
    height, minimap vs main view). Found via Ghidra + cross-checked
    against leaked SDK source (commanderwarp.cpp, which reads the
    neighboring lEyeBallMapX/Y fields the same way). Not previously
    used anywhere in this project, so results are sanity-checked
    against map bounds before being trusted - see TryCaptureGroundClick. }
  Map_ScreenToWorldClick: procedure(pData: Pointer); stdcall;

{ ============================================================================= }
{ Console Output                                                              }
{ ============================================================================= }

procedure WriteLn(const Msg: String);
var
  Written: Cardinal;
begin
  if ConsoleHandle <> 0 then
    WriteFile(ConsoleHandle, PChar(Msg + #13#10)^, Length(Msg) + 2, Written, nil);
end;

procedure Write(const Msg: String);
var
  Written: Cardinal;
begin
  if ConsoleHandle <> 0 then
    WriteFile(ConsoleHandle, PChar(Msg)^, Length(Msg), Written, nil);
end;

{ ============================================================================= }
{ Diagnostic log - Unload investigation (2026-08-17)                          }
{ Same shared log file as UnitConsole.pas's LogUnload (C:\tpLAYX1\LOG\), just  }
{ tagged [UnitPortal] instead, so a single file shows both systems in order.  }
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
      otherwise shadow the 2-arg file-writing Writeln from here on. }
    System.Writeln(LogFile, FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + '  [UnitPortal] ' + Msg);
    CloseFile(LogFile);
  except end;
end;

{ Prints to the console window AND flashes the same line in the in-game
  chat/reminder overlay via SendTextLocal. Use for actionable events;
  plain WriteLn for menu text so chat doesn't get spammed. }
procedure Notify(const Msg: String);
begin
  WriteLn('  ' + Msg);
  SendTextLocal(Msg);
end;

{ ============================================================================= }
{ Position Capture - anywhere on the map, ground or unit                      }
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

function CapturePositionFromMouse(out X, Z, Y: Word): Boolean;
var
  MouseUnit, p_Unit: PUnitStruct;
begin
  Result := False;
  X := 0;
  Z := 0;
  Y := 0;

  { First choice: resolve wherever the mouse is on the map right now,
    even bare ground - same resolution the game itself uses for clicks. }
  if TryCaptureGroundClick(X, Z) then
  begin
    Y := 0;
    Result := True;
    Exit;
  end;

  { Second choice: whatever unit is directly under the mouse cursor. }
  MouseUnit := TAUnit.AtMouse;
  if MouseUnit <> nil then
  begin
    X := TAUnit.GetUnitX(MouseUnit);
    Z := TAUnit.GetUnitZ(MouseUnit);
    Y := TAUnit.GetUnitY(MouseUnit);
    Result := True;
    Exit;
  end;

  { Last resort: the ground-click resolver above returned nothing usable
    (e.g. game not fully in a state it recognizes) and there's no unit
    under the mouse either. Fall back to the selected unit's own current
    position. }
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

{ ============================================================================= }
{ Unit Information Display                                                    }
{ ============================================================================= }

procedure ShowUnitInfo(UnitId: Word);
var
  p_Unit: PUnitStruct;
  X, Z, Y: Word;
  Health: Word;
  Speed: Integer;
begin
  p_Unit := TAUnit.Id2Ptr(UnitId);

  if p_Unit = nil then
  begin
    WriteLn('  [ERROR] Unit not found');
    Exit;
  end;

  if p_Unit.p_UNITINFO = nil then
  begin
    WriteLn('  [ERROR] Unit is not active');
    Exit;
  end;

  X := TAUnit.GetUnitX(p_Unit);
  Z := TAUnit.GetUnitZ(p_Unit);
  Y := TAUnit.GetUnitY(p_Unit);
  Health := TAUnit.GetHealth(p_Unit);
  Speed := TAUnit.GetCurrentSpeedVal(p_Unit);

  WriteLn('');
  WriteLn('  ================================');
  WriteLn('   UNIT INFORMATION');
  WriteLn('  ================================');
  WriteLn('  ID:     ' + IntToStr(UnitId));
  WriteLn('  Name:   ' + String(p_Unit.p_UNITINFO.szUnitName));
  WriteLn('  Health: ' + IntToStr(Health));
  WriteLn('  Speed:  ' + IntToStr(Speed));
  WriteLn('  Position:');
  WriteLn('    X: ' + IntToStr(X));
  WriteLn('    Z: ' + IntToStr(Z));
  WriteLn('    Y: ' + IntToStr(Y));
  WriteLn('');
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
  WriteLn('   ID    | Health | Speed  | Unit Name');
  WriteLn('  ' + StringOfChar('-', 60));

  Count := 0;
  for i := 0 to 4999 do
  begin
    p_Unit := TAUnit.Id2Ptr(i);
    if (p_Unit <> nil) and (p_Unit.p_UNITINFO <> nil) then
    begin
      WriteLn(Format('  %4d   | %6d | %5d  | %s',
        [i, TAUnit.GetHealth(p_Unit), TAUnit.GetCurrentSpeedVal(p_Unit),
         String(p_Unit.p_UNITINFO.szUnitName)]));
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
{ Portal Position Display                                                     }
{ ============================================================================= }

procedure ShowPortalPositions;
begin
  WriteLn('');
  WriteLn('  ================================');
  WriteLn('   PORTAL POSITIONS');
  WriteLn('  ================================');
  WriteLn('');

  WriteLn('  SOURCE POSITION:');
  if SourcePos.Active then
    WriteLn('    X=' + IntToStr(SourcePos.X) + ' Z=' + IntToStr(SourcePos.Z) + ' Y=' + IntToStr(SourcePos.Y) + ' [SET]')
  else
    WriteLn('    [NOT SET]');

  WriteLn('');
  WriteLn('  DESTINATION POSITION:');
  if DestPos.Active then
    WriteLn('    X=' + IntToStr(DestPos.X) + ' Z=' + IntToStr(DestPos.Z) + ' Y=' + IntToStr(DestPos.Y) + ' [SET]')
  else
    WriteLn('    [NOT SET]');

  WriteLn('');
end;

{ ============================================================================= }
{ Menu Display                                                                }
{ ============================================================================= }

procedure ShowMainMenu;
begin
  WriteLn('');
  WriteLn('  ================================');
  WriteLn('   PORTAL SYSTEM - Main Menu');
  WriteLn('  ================================');
  WriteLn('');
  WriteLn('   1 - Select Unit');
  WriteLn('   2 - Set Source Position');
  WriteLn('   3 - Set Destination Position');
  WriteLn('   4 - Teleport Unit');
  WriteLn('   5 - View Positions');
  WriteLn('   6 - List Units');
  WriteLn('   7 - Send to Source (auto-unload, then return to Source)');
  WriteLn('   8 - Send to Destination (auto-unload, then return to Source)');
  WriteLn('   9 - Full Cycle: load cargo at Source, deliver to Destination, return to Source');
  WriteLn('   10 - Full Cycle (Auto-load): scan near Source, load up to capacity, deliver, return');
  if AutoLoopEnabled then
    WriteLn('   11 - Toggle Continuous Auto-Cycle (currently: ON)')
  else
    WriteLn('   11 - Toggle Continuous Auto-Cycle (currently: OFF)');
  WriteLn('   12 - Settings (spacing / search radius / poll interval)');
  WriteLn('');
  WriteLn('   20 - Exit');
  WriteLn('');
end;

procedure ShowMenu;
begin
  if CurrentMenu = 0 then
    ShowMainMenu;
end;

{ ============================================================================= }
{ Tunable settings menu (2026-08-18)                                          }
{ "CAN U SET SOME VARRIBIES AT TOP SO I CAN ADJUST THE SPACING AND SEARCH     }
{ RADUIS ETC" - the Cfg_* globals up top hold the actual values; this just    }
{ lists them with a number and lets option 12 change one at a time from the   }
{ console, no recompile needed. }
{ ============================================================================= }
procedure ShowTunableSettings;
begin
  WriteLn('');
  WriteLn('  ================================');
  WriteLn('   PORTAL SYSTEM - Settings');
  WriteLn('  ================================');
  WriteLn('');
  WriteLn('   1 - Pickup scan radius (world units): ' + IntToStr(Cfg_PickupScanRadius));
  WriteLn('   2 - Unload-spot search max radius (world units): ' + IntToStr(Cfg_UnloadSearchMaxRadius));
  WriteLn('   3 - Unload-spot search ring step (world units): ' + IntToStr(Cfg_UnloadSearchRadiusStep));
  WriteLn('   4 - Unload-spot search angles per ring: ' + IntToStr(Cfg_UnloadSearchAnglesPerRing));
  WriteLn('   5 - Unload-spot minimum separation (world units): ' + IntToStr(Cfg_UnloadMinSeparation));
  WriteLn('   6 - Continuous Auto-Cycle poll interval (ms): ' + IntToStr(Cfg_AutoLoopPollMs));
  WriteLn('   7 - Show console window on hotkey (0=hidden/silent, 1=visible): ' + IntToStr(Cfg_ShowConsoleOnHotkey));
  WriteLn('');
  WriteLn('   Enter as "<number> <new value>" (e.g. "5 100"), or blank to cancel.');
  WriteLn('');
end;

{ Returns True and applies the change if SettingNum/NewValue were valid.
  Rejects anything <= 0 - every one of these is a radius/step/count/interval
  where zero or negative would either divide-by-zero (angles-per-ring) or
  spin the search loop forever (radius/step both zero). }
function ApplyTunableSetting(SettingNum, NewValue: Integer): Boolean;
begin
  Result := True;

  { Setting 7 (Cfg_ShowConsoleOnHotkey) is a 0/1 toggle - 0 is a perfectly
    valid value there, unlike every other setting here where 0 or negative
    would break a radius/step/count/interval. Only reject <= 0 for the rest. }
  if (NewValue <= 0) and (SettingNum <> 7) then
  begin
    WriteLn('  [ERROR] Value must be greater than 0');
    Result := False;
    Exit;
  end;
  if (SettingNum = 7) and (NewValue <> 0) and (NewValue <> 1) then
  begin
    WriteLn('  [ERROR] Setting 7 must be 0 (hidden) or 1 (visible)');
    Result := False;
    Exit;
  end;

  case SettingNum of
    1: Cfg_PickupScanRadius := NewValue;
    2: Cfg_UnloadSearchMaxRadius := NewValue;
    3: Cfg_UnloadSearchRadiusStep := NewValue;
    4: Cfg_UnloadSearchAnglesPerRing := NewValue;
    5: Cfg_UnloadMinSeparation := NewValue;
    6: Cfg_AutoLoopPollMs := NewValue;
    7: Cfg_ShowConsoleOnHotkey := NewValue;
  else
    begin
      WriteLn('  [ERROR] Unknown setting number');
      Result := False;
    end;
  end;

  if Result then
  begin
    LogUnload('  ApplyTunableSetting: setting ' + IntToStr(SettingNum) + ' -> ' + IntToStr(NewValue));
    Notify('[OK] Setting updated');
  end;
end;

{ ============================================================================= }
{ Portal Operations                                                           }
{ ============================================================================= }

{ Ground vs air transports use different unload order constants - same
  detection UnitConsole.pas's GiveOrderUnloadAt uses. }
function IsFlyingUnit(p_Unit: PUnitStruct): Boolean;
begin
  Result := False;
  if (p_Unit <> nil) and (p_Unit.p_UNITINFO <> nil) then
    Result := TAUnit.GetUnitInfoField(p_Unit, uiCanFly) = 1;
end;

{ "the unit names long ones i guess" (2026-08-17): szUnitName is the
  human-readable display name field on TUnitInfo (distinct from szName,
  a shorter internal type-id-style field) - same field KeyboardHook.pas's
  SpawnUnitsNearSelection already reads via implicit AnsiChar-array-to-
  String conversion. Used everywhere a unit shows up in a list or log line
  from here on, instead of a bare numeric ID. }
function UnitDisplayName(p_Unit: PUnitStruct): String;
begin
  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
    Result := '<invalid unit>'
  else
    Result := String(p_Unit.p_UNITINFO.szUnitName) + ' (#' + IntToStr(TAUnit.GetId(p_Unit)) + ')';
end;

{ "DID U SEE ANYWHERE THE CURRECT SLECTED UNIT IS" (2026-08-18) - yes: the
  game keeps its own native selection state as a bit on each unit's own
  lUnitStateMask (UnitSelectState[UnitSelected_State], declared in
  TA_MemoryStructures.pas) - completely separate from this file's own
  SelectedUnitId var, which only ever gets set by typing an ID into the
  portal console (option 1) or its "0 for mouse" shortcut. KeyboardHook.pas's
  Squad_ApplyFormation / SquadGroup_Select already walk the local player's
  whole unit array checking this exact bit to gather what's currently
  box-selected/clicked in-game.

  This does the same check but loops via TAUnit.Id2Ptr/TAData.MaxUnitsID
  (same pattern FindLoadableUnitsNearSource already uses in this file)
  instead of Player.p_UnitsArray, so it doesn't need TA_MemPlayers added to
  this file's uses clause just for one lookup. Returns the FIRST natively-
  selected unit found - good enough for "the one unit I've got selected
  right now", which is the hotkey use case this exists for (see the two
  PortalHotkey_* procedures near ToggleAutoLoop). Returns nil if nothing is
  currently selected in-game. }
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

{ Diagnostic (2026-08-17): ground transports unload fine via
  CreateMainOrder(..., Action_Ground_Unload, ...) - the raw TTAActionType
  ordinal - but VTOL transports sit still on the same code path with
  Action_VTOL_Unload. Working theory: base native order types are a fixed
  C++ enum matching our Pascal ordinals, but VTOL_* variants are COB
  script actions resolved at runtime (same category as
  TELEPORT/RECLAIM/RESURRECT/REPAIRPATROL in OrdersOverride.pas, which
  always go through TAMem.ScriptActionName2Index rather than a hardcoded
  ordinal) - so Action_VTOL_Unload's ordinal may not be the real runtime
  index. This calls Order2Unit directly with the runtime-resolved index
  instead of routing through CreateMainOrder's Ord(ActionType). Mirrors
  UnitConsole.pas's IssueScriptOrder exactly (separate copy, same reason
  the rest of this file duplicates rather than shares with UnitConsole). }
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

{ ============================================================================= }
{ Unload-spot nudge/retry (2026-08-17)                                        }
{ "when it trys to unloaded more than one unit it says its unnable to is way  }
{ of nugding the transport to unload ? maybe use same kind techice the search }
{ raduis does ?" / "bascily i t cant leave the unload aerea in till its       }
{ unload all units try agin try again around the primter of the drop off"    }
{ ============================================================================= }

{ Same retry-loop shape as TAUnits.CreateMinions (TA_MemUnits.pas) and
  KeyboardHook.pas's SpawnUnitsNearSelection: walk outward in expanding
  rings around CenterPos, testing candidate spots with
  TAUnit.TestUnloadPosition - already proven safe to call repeatedly from
  this console-command context throughout this whole project (unlike
  TestBuildSpot, which crashes when called outside COB script context, see
  SpawnUnitsNearSelection's own comment for that history).

  Honest limitation: this mod has no live "did the unload actually finish"
  event hook - all orders here are queued once, synchronously, ahead of
  real play time (see IssueScriptOrder's comment). So this can't literally
  watch the transport sit in the drop-off zone and keep nudging in
  real-time if the FIRST attempt silently fails once play resumes. What it
  CAN do, and does: use TestUnloadPosition as a stand-in for "is there
  actually room here" (the same signal the game's own unload rejection is
  presumably keying off) and search outward from the requested spot until
  it finds one that passes, rather than only ever trying the single exact
  point and giving up. Any caller queuing an Unload order should route the
  final Move+Unload position through this instead of the raw captured
  Destination point. }
function FindNearestValidUnloadSpot(p_Unit: PUnitStruct; const CenterPos: TPosition;
  out ResultPos: TPosition): Boolean;
{ MaxRadius/RadiusStep/AnglesPerRing moved to the Cfg_UnloadSearch* globals up
  top (2026-08-18) - see the "Tunable settings" block. }
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

  { Try the exact requested spot first - most of the time this just works. }
  if TAUnit.TestUnloadPosition(p_Unit.p_UNITINFO, CenterPos) then
  begin
    ResultPos := CenterPos;
    Result := True;
    Exit;
  end;

  LogUnload('  FindNearestValidUnloadSpot: exact drop-off spot rejected, searching perimeter (up to radius=' +
    IntToStr(Cfg_UnloadSearchMaxRadius) + ')...');

  Radius := Cfg_UnloadSearchRadiusStep;
  while Radius <= Cfg_UnloadSearchMaxRadius do
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
            LogUnload('  FindNearestValidUnloadSpot: found valid spot at radius=' + IntToStr(Radius) +
              ' angle=' + IntToStr(AngleVal) + ' -> X=' + IntToStr(CandPos.X) + ' Z=' + IntToStr(CandPos.Z));
            ResultPos := CandPos;
            Result := True;
            Exit;
          end;
        end;
      end;
    end;
    Inc(Radius, Cfg_UnloadSearchRadiusStep);
  end;

  LogUnload('  FindNearestValidUnloadSpot: exhausted search up to radius=' + IntToStr(Cfg_UnloadSearchMaxRadius) +
    ' - no valid drop-off spot found');
end;

type
  TPositionArray = array of TPosition;

{ "OK IT AUTO SEARCHED PICKED UP ID... BUT UNLOAD ONLY WORKED FOR ON UNIT
  MAYBE IT SHOULD KEEP TRYING IN THE AREA NEAR THE DEST INTILL THE LOAD
  LIST IS EMTPY" (2026-08-17). Log evidence: PortalFullCycleAuto loaded 4
  units near Source, but only ever issued ONE queued Unload order - and
  that one order only ever drops a single carried unit, same as the native
  vanilla "Unload" command behaves with multiple passengers (it's a
  per-order action, not "empty the whole hold"). Reissuing the same single
  Unload spot repeatedly wouldn't help either - all 6+ steps here fire
  synchronously ahead of real play time (see IssueScriptOrder's comment),
  so there's no way to check "did that one actually land" before queuing
  the next.

  Fix: give every loaded unit its OWN distinct drop-off spot around
  Destination up front (same outward ring search as
  FindNearestValidUnloadSpot, but keeps collecting instead of stopping at
  the first hit, and rejects candidates too close to ones already picked -
  MinSeparation - so the queued spots don't overlap each other), then queue
  one Move+Unload leg-pair per loaded unit instead of a single shared
  Move+Unload for all of them. That's the version of "keep trying near the
  dest until the load list is empty" that's actually achievable with this
  project's synchronous, no-live-feedback order-issuing model - see
  ClearLoadedCargoList's comment for the same limitation spelled out for
  the tracking list. }
function FindMultipleValidUnloadSpots(p_Unit: PUnitStruct; const CenterPos: TPosition;
  Count: Integer): TPositionArray;
{ MaxRadius/RadiusStep/AnglesPerRing/MinSeparation moved to the
  Cfg_UnloadSearch*/Cfg_UnloadMinSeparation globals up top (2026-08-18) - see
  the "Tunable settings" block. MinSeparation was 40; bumped to 80 after a log
  showed one loaded unit consistently failing to actually disembark even
  though its Unload order queued fine - working theory is a real in-game
  footprint collision between two drop spots that were "far enough apart" by
  this flat check but still close enough for two landing units to physically
  overlap once the game actually places them (see AutoLoopThreadProc's
  straggler-recovery comment below for the other half of this fix). }
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
      if Round(Hypot(dx, dz)) < Cfg_UnloadMinSeparation then
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

  { Exact requested spot counts as the first slot if it's valid. }
  if TAUnit.TestUnloadPosition(p_Unit.p_UNITINFO, CenterPos) then
  begin
    SetLength(Results, 1);
    Results[0] := CenterPos;
  end;

  Radius := Cfg_UnloadSearchRadiusStep;
  while (Length(Results) < Count) and (Radius <= Cfg_UnloadSearchMaxRadius) do
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
            LogUnload('  FindMultipleValidUnloadSpots: spot ' + IntToStr(Length(Results)) + '/' + IntToStr(Count) +
              ' at radius=' + IntToStr(Radius) + ' angle=' + IntToStr(AngleVal));
          end;
        end;
      end;
    end;
    Inc(Radius, Cfg_UnloadSearchRadiusStep);
  end;

  LogUnload('  FindMultipleValidUnloadSpots: found ' + IntToStr(Length(Results)) + '/' + IntToStr(Count) + ' spot(s)');
  Result := Results;
end;

{ ============================================================================= }
{ Loaded-cargo tracking (2026-08-17)                                          }
{ "also a good idea is to make a list of what units are loaded then removed   }
{ on unload"                                                                  }
{                                                                              }
{ Honest limitation (same root cause as FindNearestValidUnloadSpot's above):  }
{ there's no live "this specific unit just disembarked" event hook available  }
{ from here, so this can't be cleared one-unit-at-a-time as each one actually }
{ lands in real time. What it does instead: track IDs as they're queued for   }
{ pickup, and clear the whole list once the matching Unload order for that    }
{ run has been queued (see PortalFullCycleAuto) - good enough to know "what   }
{ is this transport currently carrying" between a Load and its matching      }
{ Unload, which is the actual use case that was asked for.                    }
{ ============================================================================= }
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

{ ============================================================================= }
{ Capacity-aware radius scan for cargo near Source (2026-08-17)               }
{ "check transport pas there is a way it check the limits of how much it can  }
{ load... till its full then we can drop of at b... the selected unit as the  }
{ transport should scanround the destion loction intill its full then go to   }
{ drop off ponit" / "you should ignore hes unit2ptr but look up the other     }
{ units in raduis"                                                            }
{                                                                              }
{ Capacity math mirrored from Transporters.pas's own native-patch hooks       }
{ (OverloadBugFix / CompareVTOLUnitWeight / Transporters_VTOLTransportSize) - }
{ same three checks the game itself uses when a load order actually runs:     }
{ unit COUNT vs p_UNITINFO.cTransportCap, WEIGHT vs                           }
{ UnitInfoCustomFields[nCategory].TransportWeightCapacity, and FOOTPRINT vs   }
{ p_UNITINFO.cTransportSize. Scans outward from Source (not the transport's   }
{ own live position - by the time this runs the transport likely hasn't       }
{ actually arrived at Source yet, all orders here fire synchronously ahead    }
{ of real play time) via a manual loop over every unit ID, same structure     }
{ TAUnits.SearchUnits itself uses internally, just centered on the captured   }
{ Source position instead of a reference unit's live Position field.         }
{ ============================================================================= }
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

  LogUnload('  FindLoadableUnitsNearSource: start CurLoadAmount=' + IntToStr(CurLoadAmount) +
    ' TransportCap=' + IntToStr(TransportCap) + ' CurLoadWeight=' + IntToStr(CurLoadWeight) +
    ' WeightCap=' + IntToStr(WeightCap) + ' TransportSize=' + IntToStr(TransportSize) +
    ' SearchRadius=' + IntToStr(SearchRadius));

  for i := 1 to TAData.MaxUnitsID do
  begin
    if CurLoadAmount >= TransportCap then
    begin
      LogUnload('  FindLoadableUnitsNearSource: count capacity reached, stopping scan early');
      Break;
    end;

    { "TO IMPROVE PERFROMCE CAN WE ONCE FOUND MAX CAPCITY STOP SEARCHING"
      (2026-08-18): same early-exit idea as the count check above, but for
      weight. Only safe to Break (not just skip) once CurLoadWeight has
      actually reached WeightCap with zero room left - a lighter unit later
      in the scan could still fit right up until then, so this can't fire
      the moment one candidate is merely too heavy (that's still just a
      per-candidate Continue below). }
    if (WeightCap > 0) and (CurLoadWeight >= WeightCap) then
    begin
      LogUnload('  FindLoadableUnitsNearSource: weight capacity reached, stopping scan early');
      Break;
    end;

    Candidate := TAUnit.Id2Ptr(i);
    if (Candidate = nil) or (Candidate.p_UNITINFO = nil) then
      Continue;

    { "I BELEVAE I KILLED SOME UNITS BUT ITS STILL REG THAT THESE UNITS R
      THERE...ONCE A UNIT IS DEAD WHEN THE NEXT BUILT UNIT REPLACE THAT
      SOLT" (2026-08-18): TA recycles unit-ID slots - a dead unit's slot
      isn't cleared, it just sits there (p_UNITINFO non-nil but stale/blank,
      hence "None" for the name and weight=0) until the game reuses that
      exact ID for the next unit built. p_UNITINFO<>nil alone isn't enough
      to prove a slot holds a genuinely live unit right now - same
      UnitValid2_State bit + p_Owner check KeyboardHook.pas's own unit-array
      walk already uses for the same reason. }
    if (Candidate.lUnitStateMask and UnitSelectState[UnitValid2_State]) <> UnitSelectState[UnitValid2_State] then
      Continue;
    if Candidate.p_Owner = nil then
      Continue;

    if TAUnit.GetId(Candidate) = TAUnit.GetId(p_Transport) then
      Continue;                              { skip the transport itself }
    if Candidate.p_TransporterUnit <> nil then
      Continue;                              { already loaded on something else }
    if Candidate.p_UNITINFO.cTransportCap > 0 then
      Continue;                              { skip other transports as cargo candidates }

    if not TAMem.DistanceBetweenPosCompare(@SrcPos, @Candidate.Position, SearchRadius) then
      Continue;

    { footprint check, mirrors Transporters_VTOLTransportSize's
      [eax+TUnitStruct.nFootPrintX] vs cTransportSize compare }
    if Candidate.nFootPrintX > TransportSize then
      Continue;

    { weight check, mirrors CompareVTOLUnitWeight }
    CandWeight := Round(Candidate.p_UNITINFO.lBuildCostMetal);
    if (WeightCap > 0) and ((CurLoadWeight + CandWeight) > WeightCap) then
      Continue;

    { count check, mirrors OverloadBugFix }
    if (CurLoadAmount + 1) > TransportCap then
      Continue;

    SetLength(Results, CandCount + 1);
    Results[CandCount] := Candidate;
    Inc(CandCount);
    Inc(CurLoadAmount);
    CurLoadWeight := CurLoadWeight + CandWeight;

    LogUnload('  FindLoadableUnitsNearSource: selected ' + UnitDisplayName(Candidate) +
      ' (running total count=' + IntToStr(CurLoadAmount) + ' weight=' + IntToStr(CurLoadWeight) + ')');
  end;

  LogUnload('  FindLoadableUnitsNearSource: found ' + IntToStr(CandCount) + ' candidate(s)');
  Result := Results;
end;

{ ============================================================================= }
{ Carried-unit linked list (2026-08-18)                                       }
{ "EXPLOR THE CARRIER N WHAT IT IS" / "OK LETS TRY IT" - confirmed live       }
{ against the actual binary (Ghidra, Parse_AttachUnitPacket @ 0048ab70) that  }
{ this struct's EXISTING p_TransporterUnit/p_TransportedUnit/p_PriorUnit      }
{ fields are a real linked list, not just three loosely-related pointers:     }
{                                                                              }
{   - On the CARRIER: p_TransportedUnit is the HEAD of the list of units it's }
{     currently carrying (byte offset 0x8A - confirmed exact match against    }
{     Parse_AttachUnitPacket's own raw pointer math).                         }
{   - On each CARRIED unit: p_PriorUnit is - despite the name - the pointer   }
{     to the NEXT sibling passenger in that same carrier's list, not a        }
{     "previous unit" in some other sense (byte offset 0x8E, confirmed the    }
{     same way - Parse_AttachUnitPacket walks exactly this chain to splice a  }
{     unit in or out when it's attached/detached).                            }
{   - p_TransporterUnit (0x86) on a carried unit points back to its carrier.  }
{                                                                              }
{ This gives an EXACT list of what's aboard a transport right now, instead of }
{ just a headcount from TAUnit.GetLoadCurAmount - lets the straggler-recovery }
{ in AutoLoopThreadProc name the stuck unit specifically and target it        }
{ directly for unload (VTOL_UNLOAD/Action_Ground_Unload's TargetUnit param -  }
{ already used the same way for VTOL_PICKUP's Candidates[i] elsewhere in this }
{ file) instead of only ever issuing a positional "eject whatever's next"     }
{ order. Honest caveat: whether the native Unload order actually HONORS a     }
{ specific TargetUnit (vs. always ejecting the head of the list regardless)   }
{ hasn't been confirmed by a real playtest yet - this is worth trying because }
{ it's a small, low-risk change (same fallback behavior either way if it      }
{ turns out to be ignored), not because it's proven. }
{ ============================================================================= }
function GetCarriedUnits(p_Transport: PUnitStruct): TUnitPtrArray;
const
  MaxCarried = 64;  { defensive cap - a corrupt/unexpectedly-circular list
                      should never spin forever just because we're reading it }
  { CRASH FIX (2026-08-18): "IS THIS TIO DO WITH OUR DLL?" - yes, almost
    certainly. Parse_AttachUnitPacket (the native code this whole list walk
    was reverse-engineered from) never trusts p_TransporterUnit/
    p_TransportedUnit/p_PriorUnit as real list links without first checking
    these two bits in the CANDIDATE NODE'S OWN lUnitStateMask - "valid" and
    "currently carried". This function originally skipped that check
    entirely and just followed p_PriorUnit blindly until nil. The crash
    dialog's faulting address (0x7C - a tiny near-null offset, not a random
    corrupt address) is exactly the signature of eventually following a
    pointer field that wasn't cleanly zeroed once a unit left the carried
    state (very plausible for an old C-style struct that likely reuses the
    same bytes for something else once a unit isn't actively linked into a
    carrier's list). Gate every step of the walk on these bits, same as the
    native code does, and stop cold the moment a node doesn't look like a
    genuinely valid, currently-carried unit rather than trusting it. }
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
      LogUnload('  GetCarriedUnits: stopping walk early - node does not look like a valid ' +
        'currently-carried unit (safety check, see crash-fix comment above)');
      Break;
    end;

    SetLength(Results, Length(Results) + 1);
    Results[High(Results)] := p_Cargo;
    p_Cargo := p_Cargo.p_PriorUnit;
    Inc(SafetyCount);
  end;

  if SafetyCount >= MaxCarried then
    LogUnload('  GetCarriedUnits: hit safety cap of ' + IntToStr(MaxCarried) +
      ' - list may be circular/corrupt, stopped early');

  Result := Results;
end;

{ Display helper for the straggler-recovery logging in AutoLoopThreadProc -
  same shape as LoadedCargoListStr above. }
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

{ OrderVTOLTransport_CheckSize @ $00489A90 - same native pickup-compatibility
  check UnitConsole.pas's GiveOrderLoadUnit used to use (see that file's
  comment for the full explanation of what it checks and why it needs a
  thiscall wrapper instead of a plain function-pointer var). Duplicated
  here rather than shared, same reasoning as IssueScriptOrder above.

  UPDATE (2026-08-17): this was the project's first use of a thiscall
  wrapper, and it crashed on first real-world use - PortalFullCycle called
  this immediately after resolving the cargo unit, and the diagnostic log
  showed nothing past PortalFullCycle's own entry line (no ABORT message,
  no exception caught by ConsoleThreadProc's own try/except), consistent
  with a hard crash rather than a clean Pascal error. No longer called
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

type
  { UPDATE (2026-08-17): no longer used anywhere - see PortalSendWithAutoUnload's
    comment for the full story. Short version: this was meant to snapshot
    whatever order the unit was running before a detour (up to 2 legs, to
    try to cover a 2-point A<->B patrol) so it could be reissued afterward
    to "resume" it. That crashed in real testing. Left defined here in
    case a safer way to resume a multi-leg order gets sorted out later
    (ORDERS_BackupMainOrder/ORDERS_PushOrder/ORDERS_RecoverMainOrder,
    already used successfully elsewhere in OrdersOverride.pas from inside
    a hooked order handler, are one candidate - but calling them from
    outside that context, like this project's console commands do, is
    untested and would need its own careful verification pass first). }
  TSavedOrder = record
    Valid: Boolean;
    ActionType: Byte;
    TargetUnit: PUnitStruct;
    Position: TPosition;
    { A 2-point Patrol (the normal in-game A<->B patrol command) is stored
      as TWO chained orders off p_MainOrder/p_NextOrder - one leg is "the
      order currently running", the other is queued right behind it. The
      original single-leg snapshot only ever captured the first of those,
      so resuming it after a detour replaced the *other* waypoint with
      wherever the detour went (patrol looked like it turned into
      X<->A instead of staying A<->B). These three fields capture that
      second leg too, one level via p_NextOrder only - not walking any
      further, since a real patrol's chain loops back on itself and
      walking it blindly risks an infinite loop / crash. That covers the
      common 2-point patrol case; a patrol with 3+ waypoints would still
      only get its first two legs preserved. }
    HasNextLeg: Boolean;
    NextActionType: Byte;
    NextTargetUnit: PUnitStruct;
    NextPosition: TPosition;
  end;

{ Reads whatever order the unit is currently running (if any) so we can
  hand it back after the portal trip - this is what makes "send through
  the portal" resumable instead of just leaving the unit idle afterward.
  cOrderType/p_UnitTarget/Position are plain fields on TUnitOrder
  (TA_MemoryStructures.pas), no native call needed to read them. Also
  peeks one order ahead via p_NextOrder to capture a 2-point patrol's
  other leg - see TSavedOrder's comment above for why.

  UPDATE (2026-08-17): no longer called anywhere - see TSavedOrder's
  comment above and PortalSendWithAutoUnload's comment below. Left
  defined, not deleted, in case it's useful again later. }
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

{ Sends a transport to a portal point, auto-unloads once there, then
  returns to Source afterward. No teleport involved anywhere in this - the
  unit physically drives/flies over there like any other Move order, same
  as Transporters.pas was NOT doing (that one moved the unit's position
  directly, which is why it looked like a teleport).

  Uses the game's own shift-queue mechanism (the same thing a player gets
  from shift-right-click to queue several orders) rather than any new
  native hook: Move replaces the current order (ShiftKey=0), then Unload
  and the return-to-Source leg are appended behind it (ShiftKey=1 each),
  so they run in sequence once the unit arrives and finishes unloading.

  UPDATE (2026-08-17): this used to snapshot whatever order the unit was
  running before (up to 2 legs, to try to cover a 2-point A<->B patrol)
  and reissue it here to "resume" it. That crashed in real testing -
  reverted to the same simpler fix already applied to PortalFullCycle:
  don't try to resume anything, just queue a Move back to Source once the
  unload is done. See SnapshotCurrentOrder/TSavedOrder's comments above
  (now unused) for the full story on why the resume attempt existed and
  what went wrong with it. }
procedure PortalSendWithAutoUnload(p_Unit: PUnitStruct; TargetPos: TPosition;
  const PointLabel: String);
var
  SourceMovePos, ReturnPos, ActualUnloadPos: TPosition;
  TestResult: Boolean;
  MoveResult, UnloadResult, ReturnResult: LongInt;
  CurX, CurY, CurZ: Word;
begin
  LogUnload('==== PortalSendWithAutoUnload called: PointLabel=' + PointLabel + ' ====');

  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
  begin
    LogUnload('  ABORT: p_Unit or p_UNITINFO nil');
    WriteLn('  [ERROR] Unit no longer valid');
    Exit;
  end;

  CurX := TAUnit.GetUnitX(p_Unit);
  CurY := TAUnit.GetUnitY(p_Unit);
  CurZ := TAUnit.GetUnitZ(p_Unit);
  LogUnload('  UnitID=' + IntToStr(SelectedUnitId) + ' current pos: X=' + IntToStr(CurX) +
    ' Y=' + IntToStr(CurY) + ' Z=' + IntToStr(CurZ));
  LogUnload('  TargetPos (16.16 fixed-point): X=' + IntToStr(TargetPos.X) +
    ' Z=' + IntToStr(TargetPos.Z) + ' Y=' + IntToStr(TargetPos.Y));

  if p_Unit.p_MovementClass = nil then
    LogUnload('  WARNING: p_MovementClass = nil - unit cannot move regardless of order given')
  else
    LogUnload('  p_MovementClass <> nil (unit can move)');

  if p_Unit.p_TransportedUnit = nil then
    LogUnload('  WARNING: p_Unit.p_TransportedUnit = nil - this transport has NOTHING loaded to unload')
  else
    LogUnload('  p_Unit.p_TransportedUnit <> nil (transport is carrying something)');

  LogUnload('  Order state BEFORE anything: ' + DumpOrderState(p_Unit));

  { Nudge/retry (2026-08-17): search around TargetPos for a spot that
    actually accepts an unload instead of just aborting on the first
    rejection - see FindNearestValidUnloadSpot's comment above. }
  TestResult := FindNearestValidUnloadSpot(p_Unit, TargetPos, ActualUnloadPos);
  LogUnload('  FindNearestValidUnloadSpot result: ' + BoolToStr(TestResult, True));
  if not TestResult then
  begin
    LogUnload('  ABORT: no valid unload spot found near ' + PointLabel);
    WriteLn('  [ERROR] Cannot unload at ' + PointLabel + ' - no free spot found nearby');
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
    { Nudged 40 world units off the exact Source spot - see Step 3/4's
      comment below for why the return leg can't just reuse SourceMovePos
      as-is when PointLabel=SOURCE (Step 1 already targets that exact
      point in that case). }
    ReturnPos.X := SourceMovePos.X + (40 * 65536);
    ReturnPos.Z := SourceMovePos.Z + (40 * 65536);
    ReturnPos.Y := SourceMovePos.Y;
  end;

  { Move: Action_Move_Ground is a ground-pathfinding order and does not
    make a VTOL unit fly anywhere - OrdersOverride.pas's own Teleport code
    confirms the project already treats 'VTOL_MOVE' as a distinct action
    from ground Move (see its tmVTOLOthers branch). This alone likely
    explains "air transport just sits still": step 1 never got the
    aircraft moving in the first place, so steps 2/3 never had anything
    to build on. }
  { Uses ActualUnloadPos (may be nudged off TargetPos - see
    FindNearestValidUnloadSpot above), NOT the raw captured TargetPos. }
  if IsFlyingUnit(p_Unit) then
  begin
    LogUnload('  IsFlyingUnit=True -> Step 1/4 Move via ScriptActionName2Index(''VTOL_MOVE'')');
    MoveResult := IssueScriptOrder(p_Unit, nil, 'VTOL_MOVE', @ActualUnloadPos, 0);
  end else
  begin
    LogUnload('  IsFlyingUnit=False -> Step 1/4 Move via Action_Move_Ground');
    MoveResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Move_Ground, @ActualUnloadPos, 0, 0, 0);
  end;
  LogUnload('  Step 1/4 Move returned=' + IntToStr(MoveResult) +
    ' -> order state now: ' + DumpOrderState(p_Unit));

  { Unload: same VTOL_UNLOAD-vs-enum-ordinal issue diagnosed in
    UnitConsole.pas (see IssueScriptOrder's comment above) - ground works
    on the raw enum, VTOL needs the runtime-resolved script index. }
  if IsFlyingUnit(p_Unit) then
  begin
    LogUnload('  IsFlyingUnit=True -> Step 2/4 Unload via ScriptActionName2Index(''VTOL_UNLOAD'')');
    UnloadResult := IssueScriptOrder(p_Unit, nil, 'VTOL_UNLOAD', @ActualUnloadPos, 1);
  end else
  begin
    LogUnload('  IsFlyingUnit=False -> Step 2/4 Unload via Action_Ground_Unload');
    UnloadResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Ground_Unload, @ActualUnloadPos, 1, 0, 0);
  end;
  LogUnload('  Step 2/4 Unload (ShiftKey=1/queued) returned=' + IntToStr(UnloadResult) +
    ' -> order state now: ' + DumpOrderState(p_Unit));

  { UPDATE (2026-08-17): this used to snapshot the prior order (up to 2
    legs, to cover a 2-point A<->B patrol) and reissue it here to "resume"
    whatever the unit was doing before. That crashed in real testing - see
    SnapshotCurrentOrder/TSavedOrder's comments above, now unused. Same
    fix as PortalFullCycle: skip trying to resume anything, and instead
    queue a plain Move back to Source once the unload is done, so the
    transport ends up parked there afterward rather than wherever the
    detour left it.

    Uses ReturnPos (Source nudged 40 world units), NOT SourceMovePos as-is.
    Decompiled Order2Unit ($0043AFC0) in Ghidra to chase down a separate
    report of the transport unloading and then just sitting at the
    destination instead of coming home: when ShiftKey<>0, it scans the
    unit's existing order chain for one already matching the same
    action+target+position (within ~16 world units), and if found,
    CANCELS that matching order instead of queuing a new one - the native
    "shift-click the same waypoint again to remove it" toggle. When
    PointLabel=SOURCE, Step 1 above already queued a VTOL_MOVE to
    SourceMovePos; reusing that exact position here would match it and
    cancel it instead of adding a return leg. ReturnPos sidesteps that by
    landing close to Source without exactly matching the earlier order. }
  if SourcePos.Active then
  begin
    if IsFlyingUnit(p_Unit) then
      ReturnResult := IssueScriptOrder(p_Unit, nil, 'VTOL_MOVE', @ReturnPos, 1)
    else
      ReturnResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Move_Ground, @ReturnPos, 1, 0, 0);
    LogUnload('  Step 3/4 Return to Source (ShiftKey=1/queued) returned=' + IntToStr(ReturnResult) +
      ' -> order state now: ' + DumpOrderState(p_Unit));

    { Step 4/4: Patrol at the exact Source spot (queued), chained right
      behind Step 3's Move - holds the transport there instead of it
      drifting once idle. Safe to use the exact (non-nudged) SourceMovePos
      here: Patrol is a different action index from Move, so it can't
      match-and-cancel Step 1's Move even landing on the same coordinates
      (only same-action + same-position collides) - see the block comment
      above and PortalFullCycle's matching Step 6 for the full reasoning. }
    if IsFlyingUnit(p_Unit) then
      ReturnResult := IssueScriptOrder(p_Unit, nil, 'VTOL_PATROL', @SourceMovePos, 1)
    else
      ReturnResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Patrol, @SourceMovePos, 1, 0, 0);
    LogUnload('  Step 4/4 Patrol/hold at Source returned=' + IntToStr(ReturnResult) +
      ' -> order state now: ' + DumpOrderState(p_Unit));
  end else
    LogUnload('  Step 3/4 and 4/4 skipped - Source position not set');

  Notify('[OK] Moving to ' + PointLabel + ', will auto-unload then return and hold at Source');
end;

procedure MoveUnitToSourceAutoUnload(p_Unit: PUnitStruct);
var
  MovePos: TPosition;
begin
  if not SourcePos.Active then
  begin
    WriteLn('  [ERROR] Source position not set');
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
    WriteLn('  [ERROR] Destination position not set');
    Exit;
  end;
  MovePos.X := Integer(DestPos.X) * 65536;
  MovePos.Z := Integer(DestPos.Z) * 65536;
  MovePos.Y := Integer(DestPos.Y) * 65536;
  PortalSendWithAutoUnload(p_Unit, MovePos, 'DESTINATION');
end;

{ Full round trip in one command: fly/drive to Source, pick up the given
  cargo unit there, continue on to Destination, drop it off, then head
  back to Source ready for the next pickup. Same shift-queue technique as
  PortalSendWithAutoUnload - all 6 legs (Move, Load, Move, Unload, Move, Patrol)
  are queued in one shot with ShiftKey, so the game runs them one after
  another on its own. Left the existing "Send to Source"/"Send to
  Destination" (auto-unload) commands as they were rather than
  repurposing them - this is an additive third option (menu 9) so the
  already-working single-point behavior stays exactly as tested.

  UPDATE (2026-08-17): Step 5 used to try to "resume whatever order the
  transport was running before" by snapshotting p_MainOrder and replaying
  it (see SnapshotCurrentOrder/TSavedOrder above, still used by options
  7/8). That only captures ONE order, not a whole chain - so if the prior
  order was itself a multi-leg route (e.g. the transport was already
  patrolling as part of a portal shuttle), only the first leg survived,
  which is why the transport ended up parked at/near Destination instead
  of continuing its loop. Replaced with a plain queued Move back to
  Source instead: simpler, and it's what you actually want out of a
  portal shuttle - drop off, then be ready to pick up the next load from
  Source. If you need it to resume something else entirely afterward,
  just re-run this command or issue a fresh order once it's back at
  Source.

  p_Cargo is passed in explicitly by the caller (see ConsoleThreadProc
  InputMode=9) rather than resolved internally via TAUnit.AtMouse - this
  lets the menu handler offer either "enter a Unit ID" or "0 for mouse",
  matching the existing Select-Unit pattern, instead of forcing mouse-hover
  only. }
procedure PortalFullCycle(p_Unit: PUnitStruct; p_Cargo: PUnitStruct);
var
  SourceMovePos, DestMovePos, ReturnPos, ActualUnloadPos: TPosition;
  TestResult: Boolean;
  StepResult: LongInt;
begin
  LogUnload('==== PortalFullCycle called ====');

  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
  begin
    LogUnload('  ABORT: p_Unit or p_UNITINFO nil');
    WriteLn('  [ERROR] Unit no longer valid');
    Exit;
  end;

  if not SourcePos.Active then
  begin
    LogUnload('  ABORT: Source position not set');
    WriteLn('  [ERROR] Source position not set');
    Exit;
  end;
  if not DestPos.Active then
  begin
    LogUnload('  ABORT: Destination position not set');
    WriteLn('  [ERROR] Destination position not set');
    Exit;
  end;

  if (p_Cargo = nil) or (p_Cargo.p_UNITINFO = nil) then
  begin
    LogUnload('  ABORT: no cargo unit given');
    WriteLn('  [ERROR] No cargo unit to load');
    Exit;
  end;
  if TAUnit.GetId(p_Cargo) = SelectedUnitId then
  begin
    LogUnload('  ABORT: cargo unit is the transport itself');
    WriteLn('  [ERROR] Cannot load a transport into itself');
    Exit;
  end;

  { NativeCheckTransportFit pre-check removed (2026-08-17): this call
    crashed the game on its first real use, with the diagnostic log
    showing nothing past this function's own entry line - see the
    updated comment on NativeCheckTransportFit's definition above for the
    full writeup. Dropping the pre-check entirely rather than risk-wrapping
    it: the native Pickup order handler already validates compatibility
    itself when the order actually executes (that's the whole reason
    OrderVTOLTransport_CheckSize exists as a pure UI/cursor helper in the
    first place), so an incompatible pairing just won't attach instead of
    crashing the mod. }

  SourceMovePos.X := Integer(SourcePos.X) * 65536;
  SourceMovePos.Z := Integer(SourcePos.Z) * 65536;
  SourceMovePos.Y := Integer(SourcePos.Y) * 65536;
  DestMovePos.X := Integer(DestPos.X) * 65536;
  DestMovePos.Z := Integer(DestPos.Z) * 65536;
  DestMovePos.Y := Integer(DestPos.Y) * 65536;

  { ReturnPos is Source nudged by 40 world units on both axes - see Step
    5/6's comment below for why this can't just reuse SourceMovePos as-is. }
  ReturnPos.X := SourceMovePos.X + (40 * 65536);
  ReturnPos.Z := SourceMovePos.Z + (40 * 65536);
  ReturnPos.Y := SourceMovePos.Y;

  { Nudge/retry (2026-08-17): search around DestMovePos for a spot that
    actually accepts an unload instead of aborting on the first rejection -
    see FindNearestValidUnloadSpot's comment above. Steps 3/4 below use
    ActualUnloadPos (may be nudged), not the raw captured DestMovePos. }
  TestResult := FindNearestValidUnloadSpot(p_Unit, DestMovePos, ActualUnloadPos);
  LogUnload('  FindNearestValidUnloadSpot (Destination) result: ' + BoolToStr(TestResult, True));
  if not TestResult then
  begin
    LogUnload('  ABORT: no valid unload spot found around Destination');
    WriteLn('  [ERROR] Cannot unload at Destination - no free spot found nearby');
    Exit;
  end;

  { Step 1/6: Move to Source }
  if IsFlyingUnit(p_Unit) then
    StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_MOVE', @SourceMovePos, 0)
  else
    StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Move_Ground, @SourceMovePos, 0, 0, 0);
  LogUnload('  Step 1/6 Move to Source returned=' + IntToStr(StepResult) +
    ' -> ' + DumpOrderState(p_Unit));

  { Step 2/6: Load cargo (queued) }
  if IsFlyingUnit(p_Unit) then
    StepResult := IssueScriptOrder(p_Unit, p_Cargo, 'VTOL_PICKUP', nil, 1)
  else
    StepResult := TAUnit.CreateMainOrder(p_Unit, p_Cargo, Action_Ground_Pickup, nil, 1, 0, 0);
  LogUnload('  Step 2/6 Load cargo returned=' + IntToStr(StepResult) +
    ' -> ' + DumpOrderState(p_Unit));

  { Step 3/6: Move to Destination (queued) - ActualUnloadPos, may be
    nudged off DestMovePos (see the FindNearestValidUnloadSpot call above) }
  if IsFlyingUnit(p_Unit) then
    StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_MOVE', @ActualUnloadPos, 1)
  else
    StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Move_Ground, @ActualUnloadPos, 1, 0, 0);
  LogUnload('  Step 3/6 Move to Destination returned=' + IntToStr(StepResult) +
    ' -> ' + DumpOrderState(p_Unit));

  { Step 4/6: Unload at Destination (queued) - same ActualUnloadPos as Step 3 }
  if IsFlyingUnit(p_Unit) then
    StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_UNLOAD', @ActualUnloadPos, 1)
  else
    StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Ground_Unload, @ActualUnloadPos, 1, 0, 0);
  LogUnload('  Step 4/6 Unload at Destination returned=' + IntToStr(StepResult) +
    ' -> ' + DumpOrderState(p_Unit));

  { Step 5/6: head back to Source (queued) - ready for the next pickup
    instead of trying to resume whatever multi-leg order was running
    before (see the updated function comment above for why).

    UPDATE (2026-08-17): must NOT reuse SourceMovePos here. Decompiled
    Order2Unit ($0043AFC0) in Ghidra to understand a crash/misbehavior
    report: when ShiftKey<>0, it first scans the unit's existing order
    chain for one already matching the same action+target+position
    (within ~16 world units) - and if it finds one, it does NOT queue a
    new order, it CANCELS the matching one instead (this is the native
    "shift-click the same waypoint again to remove it" toggle). Step 1
    above queues VTOL_MOVE to SourceMovePos; since all 6 steps here fire
    within the same instant, Step 1's move is still sitting unexecuted in
    the chain by the time this runs. Reissuing the exact same
    action+position for "return to Source" doesn't append anything - it
    matches Step 1 and CANCELS it, promoting Load to the front of the
    queue instead. That's exactly why the transport used to unload and
    then just sit at Destination: the "go home" leg never actually got
    added, and Step 1's original move got wiped out by this call.
    ReturnPos (Source nudged by 40 world units, computed above) is far
    enough outside that ~16-unit match window to be treated as a
    genuinely new order and queued normally, while still landing close
    enough to Source to serve the same purpose. }
  if IsFlyingUnit(p_Unit) then
    StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_MOVE', @ReturnPos, 1)
  else
    StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Move_Ground, @ReturnPos, 1, 0, 0);
  LogUnload('  Step 5/6 Return to Source returned=' + IntToStr(StepResult) +
    ' -> ' + DumpOrderState(p_Unit));

  { Step 6/6: Patrol at the exact Source spot (queued), chained right
    behind Step 5's Move. This is what actually holds the transport there
    afterward instead of it drifting off on its own once idle - a Patrol
    order whose only point is Source functions as "stay put and stand
    ready" rather than a real back-and-forth patrol.

    Safe to use the EXACT SourceMovePos here (no nudge needed, unlike
    Step 5): Order2Unit's match-and-cancel check (see Step 5's comment
    above) requires the SAME action type as well as the same position.
    Patrol (Action_VTOL_Patrol=56 / Action_Patrol=29) is a different
    action index from Move (55 / Action_Move_Ground), so even landing on
    the identical Source coordinates as Step 1's Move order, it can't
    match and cancel it - different action type is enough to make this a
    genuinely new order. }
  if IsFlyingUnit(p_Unit) then
    StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_PATROL', @SourceMovePos, 1)
  else
    StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Patrol, @SourceMovePos, 1, 0, 0);
  LogUnload('  Step 6/6 Patrol/hold at Source returned=' + IntToStr(StepResult) +
    ' -> ' + DumpOrderState(p_Unit));

  Notify('[OK] Full cycle queued: Source -> load ' + UnitDisplayName(p_Cargo) +
    ' -> Destination -> unload -> return and hold at Source');
end;

{ Same 6-leg shuttle as PortalFullCycle, but instead of a single caller-given
  cargo unit, scans a radius around Source for every loadable unit that fits
  within the transport's real capacity (count/weight/footprint - see
  FindLoadableUnitsNearSource above) and queues a Pickup for each one before
  heading to Destination. Menu option 10 - "you should ignore hes unit2ptr
  but look up the other units in raduis... scanround the destion loction
  intill its full then go to drop off ponit" (Source, not Destination, per
  context - see FindLoadableUnitsNearSource's own comment). }
procedure PortalFullCycleAuto(p_Unit: PUnitStruct);
{ ScanRadius moved to the Cfg_PickupScanRadius global up top (2026-08-18). }
var
  SourceMovePos, DestMovePos, ReturnPos: TPosition;
  Candidates: TUnitPtrArray;
  UnloadSpots: TPositionArray;
  ThisSpot: TPosition;
  i, SpotIdx, RepeatPass: Integer;
  StepResult: LongInt;
begin
  LogUnload('==== PortalFullCycleAuto called ====');

  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
  begin
    LogUnload('  ABORT: p_Unit or p_UNITINFO nil');
    WriteLn('  [ERROR] Unit no longer valid');
    Exit;
  end;
  if not SourcePos.Active then
  begin
    LogUnload('  ABORT: Source position not set');
    WriteLn('  [ERROR] Source position not set');
    Exit;
  end;
  if not DestPos.Active then
  begin
    LogUnload('  ABORT: Destination position not set');
    WriteLn('  [ERROR] Destination position not set');
    Exit;
  end;

  Candidates := FindLoadableUnitsNearSource(p_Unit, Cfg_PickupScanRadius);
  if Length(Candidates) = 0 then
  begin
    LogUnload('  ABORT: no loadable units found near Source within radius=' + IntToStr(Cfg_PickupScanRadius));
    WriteLn('  [ERROR] No loadable units found near Source (radius=' + IntToStr(Cfg_PickupScanRadius) + ')');
    Exit;
  end;

  WriteLn('  Found ' + IntToStr(Length(Candidates)) + ' loadable unit(s) near Source:');
  for i := 0 to High(Candidates) do
    WriteLn('    - ' + UnitDisplayName(Candidates[i]));

  SourceMovePos.X := Integer(SourcePos.X) * 65536;
  SourceMovePos.Z := Integer(SourcePos.Z) * 65536;
  SourceMovePos.Y := Integer(SourcePos.Y) * 65536;
  DestMovePos.X := Integer(DestPos.X) * 65536;
  DestMovePos.Z := Integer(DestPos.Z) * 65536;
  DestMovePos.Y := Integer(DestPos.Y) * 65536;
  ReturnPos.X := SourceMovePos.X + (40 * 65536);
  ReturnPos.Z := SourceMovePos.Z + (40 * 65536);
  ReturnPos.Y := SourceMovePos.Y;

  { "unload only worked for on unit maybe it should keep trying in the area
    near the dest intill the load list is emtpy" (2026-08-17): a single
    shared Unload order only ever drops one carried unit (see
    FindMultipleValidUnloadSpots' comment above for the full story) - find
    one distinct spot per loaded unit up front instead of one shared spot. }
  UnloadSpots := FindMultipleValidUnloadSpots(p_Unit, DestMovePos, Length(Candidates));
  if Length(UnloadSpots) = 0 then
  begin
    LogUnload('  ABORT: no valid unload spot(s) found around Destination');
    WriteLn('  [ERROR] Cannot unload at Destination - no free spot found nearby');
    Exit;
  end;
  if Length(UnloadSpots) < Length(Candidates) then
    WriteLn('  [WARNING] Only found ' + IntToStr(Length(UnloadSpots)) + ' distinct drop-off spot(s) for ' +
      IntToStr(Length(Candidates)) + ' loaded unit(s) - some will share a spot');

  ClearLoadedCargoList;

  { Step 1: Move to Source }
  if IsFlyingUnit(p_Unit) then
    StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_MOVE', @SourceMovePos, 0)
  else
    StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Move_Ground, @SourceMovePos, 0, 0, 0);
  LogUnload('  Step Move to Source returned=' + IntToStr(StepResult) + ' -> ' + DumpOrderState(p_Unit));

  { Step 2: queue a Pickup (ShiftKey=1, chained) for every candidate found
    near Source - up to however many fit within capacity. }
  for i := 0 to High(Candidates) do
  begin
    if IsFlyingUnit(p_Unit) then
      StepResult := IssueScriptOrder(p_Unit, Candidates[i], 'VTOL_PICKUP', nil, 1)
    else
      StepResult := TAUnit.CreateMainOrder(p_Unit, Candidates[i], Action_Ground_Pickup, nil, 1, 0, 0);
    LogUnload('  Step Load cargo ' + UnitDisplayName(Candidates[i]) + ' returned=' + IntToStr(StepResult));
    AddLoadedCargo(TAUnit.GetId(Candidates[i]));
  end;

  { Step 3+: one Move+Unload leg-pair PER loaded unit, each targeting its
    own distinct spot from UnloadSpots (round-robin if there were fewer
    valid spots found than units loaded) - instead of one shared
    Move+Unload for the whole hold. See FindMultipleValidUnloadSpots'
    comment above for why: a single Unload order only ever dropped one
    passenger in testing. }
  for i := 0 to High(Candidates) do
  begin
    SpotIdx := i mod Length(UnloadSpots);
    ThisSpot := UnloadSpots[SpotIdx];

    { If there were fewer distinct spots than loaded units, a later unit
      round-robins back onto an earlier unit's exact spot - reissuing the
      identical action+position while the earlier order is still pending
      would hit Order2Unit's dedup/cancel toggle (see PortalFullCycle's
      Step 5 comment for the full Ghidra writeup) and wipe out the earlier
      unit's leg instead of adding a new one. Nudge each repeat pass a
      little further out to dodge that ~16-unit match window. }
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
    LogUnload('  Step Move to drop-off spot ' + IntToStr(SpotIdx) + ' (for ' + UnitDisplayName(Candidates[i]) +
      ') returned=' + IntToStr(StepResult) + ' -> ' + DumpOrderState(p_Unit));

    if IsFlyingUnit(p_Unit) then
      StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_UNLOAD', @ThisSpot, 1)
    else
      StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Ground_Unload, @ThisSpot, 1, 0, 0);
    LogUnload('  Step Unload at drop-off spot ' + IntToStr(SpotIdx) + ' (for ' + UnitDisplayName(Candidates[i]) +
      ') returned=' + IntToStr(StepResult) + ' -> ' + DumpOrderState(p_Unit));
  end;
  { Best-effort clear - see ClearLoadedCargoList's comment on why this
    can't be done per-unit as each one actually lands. }
  ClearLoadedCargoList;

  { Step 5: head back to Source - nudged off SourceMovePos, same
    Order2Unit dedup/cancel reasoning as PortalFullCycle's Step 5. }
  if IsFlyingUnit(p_Unit) then
    StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_MOVE', @ReturnPos, 1)
  else
    StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Move_Ground, @ReturnPos, 1, 0, 0);
  LogUnload('  Step Return to Source returned=' + IntToStr(StepResult) + ' -> ' + DumpOrderState(p_Unit));

  { Step 6: Patrol/hold at the exact Source spot }
  if IsFlyingUnit(p_Unit) then
    StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_PATROL', @SourceMovePos, 1)
  else
    StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Patrol, @SourceMovePos, 1, 0, 0);
  LogUnload('  Step Patrol/hold at Source returned=' + IntToStr(StepResult) + ' -> ' + DumpOrderState(p_Unit));

  Notify('[OK] Full Cycle (Auto-load): loaded ' + IntToStr(Length(Candidates)) +
    ' unit(s) near Source, delivering to Destination, then returning to hold at Source');
end;

{ ============================================================================= }
{ Continuous Auto-Cycle (2026-08-17, reworked 2026-08-18)                     }
{ "the method u just gave is working is there a option 11 to turn on         }
{ contuioesly"                                                                }
{                                                                              }
{ First attempt used ConsoleTimer.pas's TConsoleTimer (TThread-based, the     }
{ same class idplay.pas uses for its own periodic cheat/process checks).      }
{ "AFTER ONE DROP IT RETURN BACK THE SROUCE LOCTION DOESNT PICK UP ANY MORE   }
{ UNITS UNLESS I ACTIAVTE 10" plus a diagnostic log with ZERO "tick fired"    }
{ lines despite the timer being left enabled for 30-70+ second stretches     }
{ showed its background thread was never actually reaching the tick handler  }
{ at all - not an exception (that would have logged), just silence, which    }
{ points at TConsoleTimer.Execute's own wait loop exiting immediately after  }
{ starting rather than anything in our code.                                 }
{                                                                              }
{ Replaced with a plain CreateThread + Sleep loop instead - the exact same   }
{ primitive OpenPortalConsole already uses successfully for ConsoleThread    }
{ itself (this file's own console-reading thread), just running a periodic   }
{ check instead of a blocking read. Fewer moving parts than TThread's own    }
{ event-object machinery, and proven to actually start and run in this      }
{ exact file already.                                                        }
{                                                                              }
{ Readiness check: PortalFullCycleAuto's own final step always ends by       }
{ issuing a Patrol/hold order at the exact Source position once a cycle's    }
{ whole order chain has actually finished executing (every Move/Pickup/      }
{ Unload leg ahead of it in the queue has to drain first, in-order, before   }
{ the game ever gets to that last step) - so "the transport's current order  }
{ is Patrol" is a cheap, already-available signal for "this cycle is done,   }
{ safe to queue the next one" without needing any new tracking state.        }
{ ============================================================================= }

{ Runs on its own thread (created by ToggleAutoLoop below), completely       }
{ separate from both the game's main thread and the portal console's own    }
{ input-reading thread - same separation ConsoleThread itself already has   }
{ from the main game thread. Sleeps AutoLoopPollMs between checks rather     }
{ than blocking on any Windows sync object, so there's nothing here that     }
{ can silently fail to wake up the way TConsoleTimer's event-based wait      }
{ apparently did. }
function AutoLoopThreadProc(Param: Pointer): Integer; stdcall;
{ AutoLoopPollMs moved to the Cfg_AutoLoopPollMs global up top (2026-08-18) -
  can now be adjusted live via menu option 12 without a recompile. }
var
  p_Unit: PUnitStruct;
  IsReady: Boolean;
  Candidates: TUnitPtrArray;
  StragglerCount: Integer;
  StragglerSpot, SourceHoldPos: TPosition;
  StepResult: LongInt;
begin
  Result := 0;
  LogUnload('  AutoLoopThread: thread started');

  while AutoLoopThreadActive do
  begin
    Sleep(Cfg_AutoLoopPollMs);
    if not AutoLoopThreadActive then
      Break;

    try
      LogUnload('  AutoLoop: tick fired (AutoLoopEnabled=' + BoolToStr(AutoLoopEnabled, True) +
        ' AutoLoopUnitId=' + IntToStr(AutoLoopUnitId) + ')');

      if not AutoLoopEnabled then
        Continue;

      p_Unit := TAUnit.Id2Ptr(AutoLoopUnitId);
      if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
      begin
        LogUnload('  AutoLoop: tracked unit #' + IntToStr(AutoLoopUnitId) + ' no longer valid - stopping loop');
        AutoLoopEnabled := False;
        Notify('[INFO] Continuous Auto-Cycle stopped - tracked unit no longer valid');
        Continue;
      end;

      if p_Unit.p_MainOrder = nil then
        LogUnload('  AutoLoop: current order = nil (idle)')
      else
        LogUnload('  AutoLoop: current order cOrderType=' + IntToStr(p_Unit.p_MainOrder.cOrderType) +
          ' (ready values: Action_Patrol=' + IntToStr(Ord(Action_Patrol)) +
          ' Action_VTOL_Patrol=' + IntToStr(Ord(Action_VTOL_Patrol)) + ')');

      { Idle (never given an order yet) or holding Patrol at Source (the last
        leg of a finished cycle) both mean "ready for the next cycle".
        Anything else (Move/Pickup/Unload mid-chain) means a cycle is still
        in flight - do nothing this tick. }
      IsReady := (p_Unit.p_MainOrder = nil) or
                 (p_Unit.p_MainOrder.cOrderType = Ord(Action_Patrol)) or
                 (p_Unit.p_MainOrder.cOrderType = Ord(Action_VTOL_Patrol));
      if not IsReady then
      begin
        LogUnload('  AutoLoop: not ready yet (cycle still in flight) - waiting');
        Continue;
      end;

      { "MAYBE SMALL BUF BU T ONE UNIT DIDNT GET UNLOADED WITCH MENT IT ONLY
        PCIKED 3 UP" (2026-08-18): a log showed every Move+Unload leg-pair
        in PortalFullCycleAuto queuing fine (all nonzero Order2Unit returns)
        yet TAUnit.GetLoadCurAmount(p_Unit) stayed stuck at 1 forever after,
        across every following cycle - a single passenger that queued an
        Unload order but never actually disembarked once play resumed. Since
        FindLoadableUnitsNearSource reads that same live GetLoadCurAmount
        value as "already-used capacity" (see its own comment), a stuck
        straggler silently eats one slot's worth of capacity/weight on every
        future cycle forever, which is exactly the "only picked 3 up instead
        of 4" symptom reported.

        Ready (Patrol/idle) means every leg ahead of it in the queue -
        including all per-unit Unload orders - has actually finished
        draining in real game time, so this is the right moment to check:
        if cargo is still aboard here, it's a genuine straggler, not just a
        cycle still in flight.

        REVERTED (2026-08-18) - "OK I WANT TO REVERT TO THE PREVIOUS CODE ONE
        BEFOR DISSBLING OPTION 11": back to the simple generic positional
        Move+Unload at the transport's own current position. The targeted,
        GetCarriedUnits-based per-straggler version (walking the carried-unit
        list and issuing a Move+Unload per named unit via TargetUnit) is
        still defined further up in this file (GetCarriedUnits/
        StragglerListStr) and untouched, just no longer called from here. }
      StragglerCount := TAUnit.GetLoadCurAmount(p_Unit);
      if StragglerCount > 0 then
      begin
        LogUnload('  AutoLoop: ready, but transport still shows CurLoadAmount=' + IntToStr(StragglerCount) +
          ' - straggler(s) never disembarked last cycle, forcing unload before doing anything else');

        if FindNearestValidUnloadSpot(p_Unit, p_Unit.Position, StragglerSpot) then
        begin
          if IsFlyingUnit(p_Unit) then
          begin
            StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_MOVE', @StragglerSpot, 0);
            LogUnload('  AutoLoop: straggler Move returned=' + IntToStr(StepResult));
            StepResult := IssueScriptOrder(p_Unit, nil, 'VTOL_UNLOAD', @StragglerSpot, 1);
            LogUnload('  AutoLoop: straggler Unload returned=' + IntToStr(StepResult));
          end else
          begin
            StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Move_Ground, @StragglerSpot, 0, 0, 0);
            LogUnload('  AutoLoop: straggler Move returned=' + IntToStr(StepResult));
            StepResult := TAUnit.CreateMainOrder(p_Unit, nil, Action_Ground_Unload, @StragglerSpot, 1, 0, 0);
            LogUnload('  AutoLoop: straggler Unload returned=' + IntToStr(StepResult));
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
          LogUnload('  AutoLoop: could not find a valid spot to force-unload straggler(s) near current position');

        Continue;  { re-check next tick once GetLoadCurAmount actually reads back 0 }
      end;

      { Quiet pre-check so an empty Source doesn't spam the in-game chat
        with "[ERROR] No loadable units found" every tick while waiting for
        more cargo to show up - PortalFullCycleAuto's own abort path is
        meant for a single manual run, not a polling loop. }
      Candidates := FindLoadableUnitsNearSource(p_Unit, Cfg_PickupScanRadius);
      if Length(Candidates) = 0 then
      begin
        LogUnload('  AutoLoop: ready, but no loadable units near Source yet - waiting');
        Continue;
      end;

      LogUnload('  AutoLoop: ready and ' + IntToStr(Length(Candidates)) + ' unit(s) waiting - starting next cycle');
      PortalFullCycleAuto(p_Unit);
    except
      on E: Exception do
        LogUnload('  AutoLoop: EXCEPTION in AutoLoopThreadProc tick: ' + E.Message);
    end;
  end;

  LogUnload('  AutoLoopThread: thread exiting');
end;

{ Menu option 11 - starts/stops the background poll thread above. Same guard
  checks as option 10 (unit selected, Source+Destination set) since turning
  it on immediately tries to run a cycle on the next tick. The thread itself
  is only ever created once (first activation) and then just parked via
  AutoLoopEnabled=False when "stopped" - matches ConsoleThread's own
  create-once lifecycle in this file. }
{ Shared "turn the loop on for this unit" logic - factored out of
  ToggleAutoLoop (2026-08-18) so PortalHotkey_SetDestArmTransportAndStartLoop
  below can start the loop directly from a unit pointer it already has (from
  native selection) without needing SelectedUnitId set via the console
  first. Guard checks (Source/Dest active) are unchanged from the original
  ToggleAutoLoop. }
function StartAutoLoopForUnit(p_Unit: PUnitStruct): Boolean;
var
  ThreadId: Cardinal;
begin
  Result := False;

  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
  begin
    WriteLn('  [INFO] No unit to start the loop on');
    Exit;
  end;
  if not SourcePos.Active then
  begin
    WriteLn('  [ERROR] Source position not set');
    Exit;
  end;
  if not DestPos.Active then
  begin
    WriteLn('  [ERROR] Destination position not set');
    Exit;
  end;

  AutoLoopUnitId := TAUnit.GetId(p_Unit);
  AutoLoopEnabled := True;
  LogUnload('  StartAutoLoopForUnit: turning ON for unit #' + IntToStr(AutoLoopUnitId));

  if AutoLoopThreadHandle = 0 then
  begin
    AutoLoopThreadActive := True;
    AutoLoopThreadHandle := CreateThread(nil, 0, @AutoLoopThreadProc, nil, 0, ThreadId);
    if AutoLoopThreadHandle = 0 then
    begin
      AutoLoopThreadActive := False;
      AutoLoopEnabled := False;
      LogUnload('  StartAutoLoopForUnit: CreateThread FAILED');
      WriteLn('  [ERROR] Could not start Continuous Auto-Cycle - CreateThread failed');
      Exit;
    end;
    LogUnload('  StartAutoLoopForUnit: AutoLoopThread created, handle=' + IntToStr(Cardinal(AutoLoopThreadHandle)));
  end;

  Notify('[OK] Continuous Auto-Cycle started on ' + UnitDisplayName(p_Unit) +
    ' - will keep shuttling Source -> Destination automatically until stopped');
  Result := True;
end;

{ RE-ENABLED (2026-08-18) - "CAN WE ENABLE SETTING 11 AGAIN" - back to
  starting a new loop from the menu using whatever's currently selected. }
procedure ToggleAutoLoop;
begin
  if AutoLoopEnabled then
  begin
    AutoLoopEnabled := False;
    LogUnload('  ToggleAutoLoop: turned OFF');
    Notify('[OK] Continuous Auto-Cycle stopped');
    Exit;
  end;

  if SelectedUnitId = 0 then
  begin
    WriteLn('  [INFO] No unit selected');
    Exit;
  end;

  StartAutoLoopForUnit(TAUnit.Id2Ptr(SelectedUnitId));
end;

{ ============================================================================= }
{ Hotkey-driven Source/Dest/transport-arming (2026-08-18)                     }
{ "I WILL WANT TO JUST HOT KEY IT SOON SO THE MAIN UNIT GETS SETS SROUCE AT   }
{ ITS CURRENT LOCTION AND THEN THE HOT KEY TRIGGERS THE DES AND THEN         }
{ SELECTED THE TRANSPORT UNIT THEN STARTS THE LOOP" - these two exported     }
{ procedures are the building blocks for that: wire each one up to its own   }
{ global hotkey (wherever KeyboardHook.pas's other Alt+Shift+* hotkeys are   }
{ registered) and the whole flow runs without ever opening the portal        }
{ console. Both read position via TAUnit.GetUnitX/Z/Y - the same plain       }
{ world-unit scale TPortalPos already stores (see CapturePositionFromMouse), }
{ not the 16.16 fixed-point TPosition a unit's own .Position field uses.     }
{ ============================================================================= }

{ Hotkey 1: press with the pickup-point unit selected in-game (e.g. a con
  unit or factory sitting where cargo will spawn/gather) - sets Source to
  wherever that unit currently is. }
procedure PortalHotkey_SetSourceFromSelection;
var
  p_Unit: PUnitStruct;
begin
  p_Unit := GetNativeSelectedUnit;
  if p_Unit = nil then
  begin
    Notify('[ERROR] Portal hotkey: no unit selected - cannot set Source');
    Exit;
  end;

  SourcePos.X := TAUnit.GetUnitX(p_Unit);
  SourcePos.Z := TAUnit.GetUnitZ(p_Unit);
  SourcePos.Y := TAUnit.GetUnitY(p_Unit);
  SourcePos.Active := True;
  LogUnload('  PortalHotkey_SetSourceFromSelection: Source set from ' + UnitDisplayName(p_Unit) +
    ' X=' + IntToStr(SourcePos.X) + ' Z=' + IntToStr(SourcePos.Z));
  Notify('[OK] Portal Source set to ' + UnitDisplayName(p_Unit) + ' position: X=' +
    IntToStr(SourcePos.X) + ' Z=' + IntToStr(SourcePos.Z));
end;

{ Hotkey 2: press with the TRANSPORT selected in-game, standing at the
  drop-off point - sets Destination there, arms that same unit as the
  Continuous Auto-Cycle's transport, and starts the loop immediately.
  Source must already be set (via the hotkey above, or the console) or this
  just reports the error and does nothing else. }
procedure PortalHotkey_SetDestArmTransportAndStartLoop;
var
  p_Unit: PUnitStruct;
begin
  p_Unit := GetNativeSelectedUnit;
  if p_Unit = nil then
  begin
    Notify('[ERROR] Portal hotkey: no unit selected - cannot set Destination / arm transport');
    Exit;
  end;
  if not SourcePos.Active then
  begin
    Notify('[ERROR] Portal hotkey: Source not set yet - use the Source hotkey first');
    Exit;
  end;

  DestPos.X := TAUnit.GetUnitX(p_Unit);
  DestPos.Z := TAUnit.GetUnitZ(p_Unit);
  DestPos.Y := TAUnit.GetUnitY(p_Unit);
  DestPos.Active := True;
  LogUnload('  PortalHotkey_SetDestArmTransportAndStartLoop: Dest set from ' + UnitDisplayName(p_Unit) +
    ' X=' + IntToStr(DestPos.X) + ' Z=' + IntToStr(DestPos.Z));
  Notify('[OK] Portal Destination set to ' + UnitDisplayName(p_Unit) + ' position: X=' +
    IntToStr(DestPos.X) + ' Z=' + IntToStr(DestPos.Z));

  SelectedUnitId := TAUnit.GetId(p_Unit);
  StartAutoLoopForUnit(p_Unit);
end;

procedure MoveUnitToSource(p_Unit: PUnitStruct);
var
  MovePos: TPosition;
begin
  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
  begin
    WriteLn('  [ERROR] Unit no longer valid');
    Exit;
  end;

  if not SourcePos.Active then
  begin
    WriteLn('  [ERROR] Source position not set');
    Exit;
  end;

  { Convert to 16.16 fixed-point format }
  MovePos.X := Integer(SourcePos.X) * 65536;
  MovePos.Z := Integer(SourcePos.Z) * 65536;
  MovePos.Y := Integer(SourcePos.Y) * 65536;

  TAUnit.CreateMainOrder(p_Unit, nil, Action_Move_Ground, @MovePos, 0, 0, 0);
  Notify('[OK] Unit moving to SOURCE position: X=' + IntToStr(SourcePos.X) + ' Z=' + IntToStr(SourcePos.Z));
end;

procedure MoveUnitToDest(p_Unit: PUnitStruct);
var
  MovePos: TPosition;
begin
  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
  begin
    WriteLn('  [ERROR] Unit no longer valid');
    Exit;
  end;

  if not DestPos.Active then
  begin
    WriteLn('  [ERROR] Destination position not set');
    Exit;
  end;

  { Convert to 16.16 fixed-point format }
  MovePos.X := Integer(DestPos.X) * 65536;
  MovePos.Z := Integer(DestPos.Z) * 65536;
  MovePos.Y := Integer(DestPos.Y) * 65536;

  TAUnit.CreateMainOrder(p_Unit, nil, Action_Move_Ground, @MovePos, 0, 0, 0);
  Notify('[OK] Unit moving to DESTINATION position: X=' + IntToStr(DestPos.X) + ' Z=' + IntToStr(DestPos.Z));
end;

procedure TeleportUnit(p_Unit: PUnitStruct);
var
  CurrentX, CurrentZ: Word;
begin
  if (p_Unit = nil) or (p_Unit.p_UNITINFO = nil) then
  begin
    WriteLn('  [ERROR] Unit no longer valid');
    Exit;
  end;

  if not DestPos.Active then
  begin
    WriteLn('  [ERROR] Destination position not set');
    Exit;
  end;

  CurrentX := TAUnit.GetUnitX(p_Unit);
  CurrentZ := TAUnit.GetUnitZ(p_Unit);

  WriteLn('  Unit teleporting from X=' + IntToStr(CurrentX) + ' Z=' + IntToStr(CurrentZ) +
          ' to X=' + IntToStr(DestPos.X) + ' Z=' + IntToStr(DestPos.Z));

  MoveUnitToDest(p_Unit);
  Notify('[OK] Teleport complete');
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

  case MenuOption of
    1: begin
      { Select Unit }
      WriteLn('');
      Write('  Enter Unit ID (or 0 for mouse): ');
      WaitingForInput := True;
      InputMode := 1;
    end;

    2: begin
      { Set Source Position }
      WriteLn('');
      WriteLn('  Place mouse over source location and press ENTER');
      Write('  Ready (press ENTER): ');
      WaitingForInput := True;
      InputMode := 2;
    end;

    3: begin
      { Set Destination Position }
      WriteLn('');
      WriteLn('  Place mouse over destination location and press ENTER');
      Write('  Ready (press ENTER): ');
      WaitingForInput := True;
      InputMode := 3;
    end;

    4: begin
      { Teleport Unit }
      if SelectedUnitId = 0 then
        WriteLn('  [INFO] No unit selected')
      else
      begin
        p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
        TeleportUnit(p_Unit);
      end;
    end;

    5: begin
      { View Positions }
      ShowPortalPositions;
    end;

    6: begin
      { List Units }
      ListAllUnits;
    end;

    7: begin
      { Send to Source, auto-unload, then return to Source }
      if SelectedUnitId = 0 then
        WriteLn('  [INFO] No unit selected')
      else
      begin
        p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
        MoveUnitToSourceAutoUnload(p_Unit);
      end;
    end;

    8: begin
      { Send to Destination, auto-unload, then return to Source }
      if SelectedUnitId = 0 then
        WriteLn('  [INFO] No unit selected')
      else
      begin
        p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
        MoveUnitToDestAutoUnload(p_Unit);
      end;
    end;

    9: begin
      { Full Cycle: load at Source, deliver to Destination - prompt for
        which unit to load as cargo (ID, or 0 for mouse) before running,
        same pattern as option 1's unit selection. }
      if SelectedUnitId = 0 then
        WriteLn('  [INFO] No unit selected')
      else
      begin
        WriteLn('');
        Write('  Enter Cargo Unit ID (or 0 for mouse): ');
        WaitingForInput := True;
        InputMode := 9;
      end;
    end;

    10: begin
      { Full Cycle (Auto-load): scans a radius around Source itself, no
        cargo-ID prompt needed. }
      if SelectedUnitId = 0 then
        WriteLn('  [INFO] No unit selected')
      else
      begin
        p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
        PortalFullCycleAuto(p_Unit);
      end;
    end;

    11: begin
      { Toggle Continuous Auto-Cycle - background timer repeats
        PortalFullCycleAuto on its own, see ToggleAutoLoop's comment. }
      ToggleAutoLoop;
    end;

    12: begin
      { Settings - list current Cfg_* values, then prompt for "<num> <value>". }
      ShowTunableSettings;
      Write('  > Setting to change (blank to cancel): ');
      WaitingForInput := True;
      InputMode := 12;
    end;

    20: begin
      WriteLn('  Closing portal console...');
      ConsoleActive := False;
    end;

    else
      WriteLn('  [ERROR] Invalid option');
  end;
end;

{ ============================================================================= }
{ Input Processing in Thread                                                  }
{ ============================================================================= }

{ Forward decl - full implementation lives down near OpenPortalConsole, but
  ConsoleThreadProc (right below) needs to call it before the menu's first
  ShowMenu, and Free Pascal implementation-section code must be declared
  before use. }
function AutoDetectSelectedUnitOnOpen: Boolean; forward;

function ConsoleThreadProc(Param: Pointer): Integer; stdcall;
var
  InputHandle: THandle;
  Buffer: array[0..255] of Char;
  CharsRead: Cardinal;
  Input: String;
  WaitingForInput: Boolean;
  InputMode: Integer;
  UnitId: Word;
  PosX, PosZ, PosY: Word;
  p_Unit: PUnitStruct;
  p_Cargo: PUnitStruct;
  SpacePos: Integer;
  SettingNumStr, SettingValStr: String;
  SettingNum, SettingVal: Integer;
begin
  Result := 0;

  try
    InputHandle := GetStdHandle(STD_INPUT_HANDLE);
    WaitingForInput := False;
    InputMode := 0;
    CurrentMenu := 0;

    if AutoDetectSelectedUnitOnOpen then
    begin
      { "I WASNT TO SET DES POS ON THE HOTKEY PRESS...I WANT TO SET DES ON
        PRESS WHERE I AM AT" (2026-08-18): no more waiting for a separate
        ENTER - capture wherever the mouse is RIGHT NOW, at the moment the
        console opens, same resolver CapturePositionFromMouse always used
        (ground under mouse -> unit under mouse -> selected unit fallback),
        just called immediately instead of arming InputMode=3 and waiting
        on a keypress. }
      if CapturePositionFromMouse(PosX, PosZ, PosY) then
      begin
        DestPos.X := PosX;
        DestPos.Z := PosZ;
        DestPos.Y := PosY;
        DestPos.Active := True;
        Notify('[OK] Destination position set: X=' + IntToStr(PosX) + ' Z=' + IntToStr(PosZ) + ' Y=' + IntToStr(PosY));

        { "WHEN I PRESS THE HOT KEY I WANT IT TO START THE LOADING AND
          UNLOADING PROCCESES" (2026-08-18) - no more separate "press 11"
          step: Source + Dest are both set now, so immediately start the
          Continuous Auto-Cycle on the same unit AutoDetectSelectedUnitOnOpen
          just picked up, same as option 11 does manually. }
        p_Unit := GetNativeSelectedUnit;

        { "IF I HAVE 4 TRANSPORTERS...IT SHOULD CANCLE THE AUTOMATION FOR
          THE OTHER TRANSPORTS" (2026-08-18) - only ONE transport auto-cycles
          at a time. Pressing the hotkey on a DIFFERENT transport than the
          one currently running hands the loop over to it, explicitly
          stopping the previous one first rather than just letting it get
          silently abandoned mid-cycle (AutoLoopThreadProc would already
          stop tracking the old unit either way, since it re-reads
          AutoLoopUnitId fresh every tick - this just makes the handoff
          clean and logged instead of implicit). Skip the stop+restart
          dance entirely if the hotkey was pressed again on the SAME
          transport that's already running - nothing to cancel there. }
        if AutoLoopEnabled and (p_Unit <> nil) and (AutoLoopUnitId <> TAUnit.GetId(p_Unit)) then
        begin
          LogUnload('  Hotkey: switching Continuous Auto-Cycle from unit #' + IntToStr(AutoLoopUnitId) +
            ' to unit #' + IntToStr(TAUnit.GetId(p_Unit)));
          Notify('[OK] Stopping Continuous Auto-Cycle on the previous transport - handing off to ' + UnitDisplayName(p_Unit));
          AutoLoopEnabled := False;
        end;

        StartAutoLoopForUnit(p_Unit);
      end else
        WriteLn('  [ERROR] Could not resolve a destination position - point at the map, hover a unit, or select one first');
      ShowMenu;
    end else
      ShowMenu;

    while ConsoleActive do
    begin
      if WaitingForInput then
      begin
        case InputMode of
          1: Write('  > Unit ID: ');
          2: Write('  > Ready to capture source: ');
          3: Write('  > Ready to capture dest: ');
          9: Write('  > Cargo Unit ID: ');
          12: Write('  > Setting to change: ');
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
          begin
            { For position capture, empty input means proceed with capture }
            if (InputMode = 2) or (InputMode = 3) then
            begin
              if CapturePositionFromMouse(PosX, PosZ, PosY) then
              begin
                if InputMode = 2 then
                begin
                  SourcePos.X := PosX;
                  SourcePos.Z := PosZ;
                  SourcePos.Y := PosY;
                  SourcePos.Active := True;
                  Notify('[OK] Source position set: X=' + IntToStr(PosX) + ' Z=' + IntToStr(PosZ) + ' Y=' + IntToStr(PosY));
                end else
                begin
                  DestPos.X := PosX;
                  DestPos.Z := PosZ;
                  DestPos.Y := PosY;
                  DestPos.Active := True;
                  Notify('[OK] Destination position set: X=' + IntToStr(PosX) + ' Z=' + IntToStr(PosZ) + ' Y=' + IntToStr(PosY));
                end;
                WaitingForInput := False;
                ShowMenu;
              end else
                WriteLn('  [ERROR] Could not resolve a position - point at the map, hover a unit, or select one first');
            end;

            { Blank input on the Settings prompt just cancels back to the menu. }
            if InputMode = 12 then
            begin
              WaitingForInput := False;
              ShowMenu;
            end;

            Continue;
          end;

          if WaitingForInput then
          begin
            case InputMode of
              1: begin
                try
                  UnitId := StrToInt(Input);

                  { If 0, select unit under mouse }
                  if UnitId = 0 then
                  begin
                    p_Unit := TAUnit.AtMouse;
                    if p_Unit <> nil then
                    begin
                      SelectedUnitId := TAUnit.GetId(p_Unit);
                      Notify('[OK] Selected unit under mouse: ' + IntToStr(SelectedUnitId));
                      ShowUnitInfo(SelectedUnitId);
                    end else
                      WriteLn('  [ERROR] No unit under mouse');
                  end else
                  begin
                    { Select by ID }
                    p_Unit := TAUnit.Id2Ptr(UnitId);
                    if (p_Unit <> nil) and (p_Unit.p_UNITINFO <> nil) then
                    begin
                      SelectedUnitId := UnitId;
                      Notify('[OK] Selected Unit: ' + IntToStr(UnitId));
                      ShowUnitInfo(UnitId);
                    end else
                      WriteLn('  [ERROR] Unit does not exist');
                  end;

                  WaitingForInput := False;
                  ShowMenu;
                except
                  WriteLn('  [ERROR] Invalid ID');
                end;
              end;

              2: begin
                { Capture source position }
                if CapturePositionFromMouse(PosX, PosZ, PosY) then
                begin
                  SourcePos.X := PosX;
                  SourcePos.Z := PosZ;
                  SourcePos.Y := PosY;
                  SourcePos.Active := True;
                  Notify('[OK] Source position set: X=' + IntToStr(PosX) + ' Z=' + IntToStr(PosZ) + ' Y=' + IntToStr(PosY));
                  WaitingForInput := False;
                  ShowMenu;
                end else
                  WriteLn('  [ERROR] Could not resolve a position - point at the map, hover a unit, or select one first');
              end;

              3: begin
                { Capture destination position }
                if CapturePositionFromMouse(PosX, PosZ, PosY) then
                begin
                  DestPos.X := PosX;
                  DestPos.Z := PosZ;
                  DestPos.Y := PosY;
                  DestPos.Active := True;
                  Notify('[OK] Destination position set: X=' + IntToStr(PosX) + ' Z=' + IntToStr(PosZ) + ' Y=' + IntToStr(PosY));
                  WaitingForInput := False;
                  ShowMenu;
                end else
                  WriteLn('  [ERROR] Could not resolve a position - point at the map, hover a unit, or select one first');
              end;

              9: begin
                { Resolve cargo unit for Full Cycle (option 9), then run it.
                  Same ID-or-0-for-mouse pattern as InputMode=1. }
                try
                  UnitId := StrToInt(Input);

                  if UnitId = 0 then
                    p_Cargo := TAUnit.AtMouse
                  else
                    p_Cargo := TAUnit.Id2Ptr(UnitId);

                  if (p_Cargo = nil) or (p_Cargo.p_UNITINFO = nil) then
                    WriteLn('  [ERROR] Cargo unit not found')
                  else
                  begin
                    p_Unit := TAUnit.Id2Ptr(SelectedUnitId);
                    PortalFullCycle(p_Unit, p_Cargo);
                  end;

                  WaitingForInput := False;
                  ShowMenu;
                except
                  WriteLn('  [ERROR] Invalid ID');
                end;
              end;

              12: begin
                { "<setting number> <new value>", e.g. "5 100" - split on the
                  first space, StrToInt both halves. }
                try
                  SpacePos := Pos(' ', Input);
                  if SpacePos = 0 then
                  begin
                    WriteLn('  [ERROR] Expected "<setting number> <new value>", e.g. "5 100"');
                  end else
                  begin
                    SettingNumStr := Trim(Copy(Input, 1, SpacePos - 1));
                    SettingValStr := Trim(Copy(Input, SpacePos + 1, Length(Input)));
                    SettingNum := StrToInt(SettingNumStr);
                    SettingVal := StrToInt(SettingValStr);
                    if ApplyTunableSetting(SettingNum, SettingVal) then
                      ShowTunableSettings;
                  end;

                  WaitingForInput := False;
                  ShowMenu;
                except
                  WriteLn('  [ERROR] Invalid input - expected "<setting number> <new value>", e.g. "5 100"');
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
    WriteLn('  Portal console closed.');

  except
    on E: Exception do
      WriteLn('  [EXCEPTION] ' + E.Message);
  end;
end;

{ ============================================================================= }
{ Console Lifecycle                                                           }
{ ============================================================================= }

{ "A FIND TO AUTO DECTED WITCH UNIT IS SELECTED WHEN WE PRESS THE HOTKEY
  BEFOR THE MENU OPENS" (2026-08-18): reuses GetNativeSelectedUnit (see its
  own comment above) to grab whatever unit is natively selected in-game at
  the moment Alt+Shift+K opens the console, so SelectedUnitId is already
  populated - option 1 becomes optional instead of mandatory. Also flags
  whether it looks like an air transport (flying + has cargo capacity) since
  that's the unit type this whole console is built around; not a hard
  block, just a heads-up, in case the user opened the console with something
  else selected (or nothing at all).

  UPDATE (2026-08-18) - "IT SAYS SELECTED NOW WHEN HOT KEY IS PRESSED IT
  WILL USE THAT LCOTION THE UNIT IS AT AND THEN ASK ME TO SET DEST": now
  also sets Source straight from that unit's live position (same
  TAUnit.GetUnitX/Z/Y read PortalHotkey_SetSourceFromSelection already uses)
  and returns True when it did, so ConsoleThreadProc can skip straight to
  the "place mouse over destination and press ENTER" prompt instead of
  showing the plain main menu.

  Called from ConsoleThreadProc, AFTER AllocConsole has already happened (so
  the console window actually exists to print to) - NOT from OpenPortalConsole
  itself, which runs before the console/stdout is ready. }
function AutoDetectSelectedUnitOnOpen: Boolean;
var
  p_Unit: PUnitStruct;
begin
  Result := False;

  p_Unit := GetNativeSelectedUnit;
  if p_Unit = nil then
  begin
    WriteLn('  [INFO] No unit currently selected in-game - use option 1 to select one');
    Exit;
  end;

  SelectedUnitId := TAUnit.GetId(p_Unit);

  if IsFlyingUnit(p_Unit) and (p_Unit.p_UNITINFO.cTransportCap > 0) then
    WriteLn('  [OK] Auto-selected currently-selected unit: ' + UnitDisplayName(p_Unit) + ' (air transport)')
  else
    WriteLn('  [OK] Auto-selected currently-selected unit: ' + UnitDisplayName(p_Unit) +
      ' (NOTE: does not look like an air transport)');

  SourcePos.X := TAUnit.GetUnitX(p_Unit);
  SourcePos.Z := TAUnit.GetUnitZ(p_Unit);
  SourcePos.Y := TAUnit.GetUnitY(p_Unit);
  SourcePos.Active := True;
  WriteLn('  [OK] Source position set from ' + UnitDisplayName(p_Unit) + ': X=' +
    IntToStr(SourcePos.X) + ' Z=' + IntToStr(SourcePos.Z));

  Result := True;
end;

procedure OpenPortalConsole;
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

    { "DISPLAY THE CONSOLE AS A DEGUB ON OFF...SO ITS ONE CLICK AUTOMATED"
      (2026-08-18): AllocConsole above always has to run - WriteLn/LogUnload
      and the whole ConsoleThreadProc input loop need a real console handle
      to exist, hotkey-driven or not. What Cfg_ShowConsoleOnHotkey controls
      is just whether that window is actually VISIBLE - hide it right after
      creation when off, same handle and thread underneath either way, so
      the hotkey's automated flow runs with nothing popping up on screen. }
    if Cfg_ShowConsoleOnHotkey = 0 then
      ShowWindow(GetConsoleWindow, SW_HIDE);

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

procedure ClosePortalConsole;
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

{ "SO ITS ONE CLICK AUTOMATED" (2026-08-18): with Cfg_ShowConsoleOnHotkey=0
  the window never shows itself, which raises an obvious problem - if it's
  invisible, how do you ever reach option 12 to turn it back on? Solving
  that with a second hotkey felt heavier than necessary, so instead the
  SAME Alt+Shift+K toggle does double duty: if the console is already
  running but hidden, this press reveals it (so you can check on it /
  reach Settings) instead of closing it outright - only a press while it's
  already VISIBLE actually closes it. Fully visible-by-default behavior
  (Cfg_ShowConsoleOnHotkey=1) is unaffected - IsWindowVisible is already
  True there, so it just closes on the very next press exactly like before. }
procedure TogglePortalConsole;
begin
  if ConsoleActive then
  begin
    if not IsWindowVisible(GetConsoleWindow) then
      ShowWindow(GetConsoleWindow, SW_SHOW)
    else
      ClosePortalConsole;
  end else
    OpenPortalConsole;
end;

initialization
  ConsoleActive := False;
  ConsoleHandle := 0;
  ConsoleThread := 0;
  SelectedUnitId := 0;
  CurrentMenu := 0;

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

  { Game's own screen-click -> world-ground resolver, found via Ghidra
    (see TryCaptureGroundClick). }
  Pointer(@Map_ScreenToWorldClick) := Pointer($00498DA0);

finalization
  if ConsoleActive then
    ClosePortalConsole;

  { Continuous Auto-Cycle cleanup - same pattern ClosePortalConsole itself
    uses for ConsoleThread (signal, wait briefly, close handle). The loop is
    deliberately NOT stopped by closing the portal console window (see
    ToggleAutoLoop's comment) - it keeps shuttling in the background - so it
    has to be torn down here instead. }
  AutoLoopEnabled := False;
  AutoLoopThreadActive := False;
  if AutoLoopThreadHandle <> 0 then
  begin
    { AutoLoopThreadProc sleeps in AutoLoopPollMs (3000ms) chunks, so give it
      a bit more than that to wake up, notice AutoLoopThreadActive=False, and
      exit cleanly before falling back to just closing the handle. }
    WaitForSingleObject(AutoLoopThreadHandle, 4000);
    CloseHandle(AutoLoopThreadHandle);
    AutoLoopThreadHandle := 0;
  end;

end.
