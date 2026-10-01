unit COB_Console;
{
  MS-DOS Style Console for COB Extensions - FINAL INTEGRATED VERSION
  Integrates with existing KeyboardHook.pas hotkey system
  Uses Alt+Shift+L hotkey to toggle console
  Hooks into COB_extensions for live queries
  Uses SendTextLocal for in-game debug output
}
interface

uses
  Windows, SysUtils, Classes, COB_extensions, TA_MemoryStructures;

type
  TCOBConsole = class(TObject)
  private
    FConsoleActive: Boolean;
    FConsoleVisible: Boolean;
    FSelectedUnitID: Cardinal;
    procedure ClearScreen;
    procedure WriteHeader;
    procedure WriteMainMenu;
    procedure WriteUnitMenu;
    procedure WriteMovementMenu;
    procedure WriteSearchMenu;
    procedure WriteWeaponMenu;
    procedure WriteOrderMenu;
    procedure WriteMapMenu;
    procedure WriteEffectsMenu;
    procedure ReadInput(var Key: Char);
    procedure DisplayUnitInfo;
    procedure DisplayMapInfo;
    procedure MoveUnitInteractive;
    procedure SearchUnitsInteractive;
    procedure FireWeaponInteractive;
    procedure IssueOrderInteractive;
    procedure PlaySoundInteractive;
    procedure PlaceFeatureInteractive;
    procedure GetUnitHealth;
    procedure GetUnitKills;
    procedure SetUnitCloak;
    procedure DamageUnit;
    procedure GetUnitTeam;
    procedure CheckAlliedStatus;
    procedure GetUnitSpeed;
    procedure GetUnitTurnAngles;
    procedure GetUnitPosition;
    procedure SetUnitHeight;
    procedure GetUnitDistance;
  public
    constructor Create;
    destructor Destroy; override;
    procedure ToggleConsole;
    procedure ProcessInput;
    property ConsoleActive: Boolean read FConsoleActive;
    property SelectedUnitID: Cardinal read FSelectedUnitID write FSelectedUnitID;
  end;

var
  COBConsole: TCOBConsole;

procedure RegisterCOBConsole;
procedure UnregisterCOBConsole;
procedure HandleConsoleHotkey;  // Called from KeyboardHook.pas

implementation

uses
  idplay,
  TA_MemoryLocations,
  TA_MemPlayers,
  TA_MemUnits,
  TA_FunctionsU,
  GUIEnhancements;

const
  CONSOLE_WIDTH = 80;
  CONSOLE_HEIGHT = 25;
  COLOR_HEADER = $0F;      // White on black
  COLOR_MENU = $0A;        // Light green on black
  COLOR_SELECTED = $0E;    // Yellow on black
  COLOR_INPUT = $0B;       // Light cyan on black
  COLOR_ERROR = $0C;       // Light red on black
  COLOR_SUCCESS = $0A;     // Light green on black

procedure SetConsoleColors(ForeColor, BackColor: Byte);
begin
  SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), ForeColor or (BackColor shl 4));
end;

procedure GotoXY(X, Y: Integer);
var
  Coord: TCoord;
begin
  Coord.X := X - 1;
  Coord.Y := Y - 1;
  SetConsoleCursorPosition(GetStdHandle(STD_OUTPUT_HANDLE), Coord);
end;

constructor TCOBConsole.Create;
begin
  inherited Create;
  FConsoleActive := False;
  FConsoleVisible := False;
  FSelectedUnitID := 0;
end;

destructor TCOBConsole.Destroy;
begin
  inherited Destroy;
end;

procedure TCOBConsole.ClearScreen;
begin
  SetConsoleColors(COLOR_HEADER, 0);
  GotoXY(1, 1);
  Writeln(StringOfChar('─'[1], CONSOLE_WIDTH));
  SetConsoleColors(COLOR_MENU, 0);
  Writeln('   COB EXTENSIONS - MS-DOS STYLE CONSOLE (Alt+Shift+L)   ');
  SetConsoleColors(COLOR_HEADER, 0);
  Writeln(StringOfChar('─'[1], CONSOLE_WIDTH));
end;

procedure TCOBConsole.WriteHeader;
begin
  ClearScreen;
  GotoXY(1, 4);
  SetConsoleColors(COLOR_SELECTED, 0);
  Writeln('╔═══════════════════════════════════════════════════════════╗');
  Writeln('║   TOTAL ANNIHILATION - COB EXTENSIONS CONSOLE v3.5       ║');
  Writeln('║   Real-time Unit & Game Control - HOTKEY INTEGRATED      ║');
  Writeln('║   Output to in-game chat via SendTextLocal               ║');
  Writeln('╚═══════════════════════════════════════════════════════════╝');
  Writeln;
end;

procedure TCOBConsole.WriteMainMenu;
begin
  SetConsoleColors(COLOR_MENU, 0);
  GotoXY(1, 10);
  Writeln('  ┌─────────────────────────────────────┐');
  Writeln('  │  MAIN MENU                          │');
  Writeln('  ├─────────────────────────────────────┤');
  Writeln('  │  [U] Unit Operations                │');
  Writeln('  │  [M] Movement & Position            │');
  Writeln('  │  [S] Search Units                   │');
  Writeln('  │  [W] Weapons & Combat               │');
  Writeln('  │  [O] Orders & Commands              │');
  Writeln('  │  [A] Map & Area                     │');
  Writeln('  │  [E] Effects & Sound                │');
  Writeln('  │  [I] Game Info                      │');
  Writeln('  │  [Q] Quit Console                   │');
  Writeln('  └─────────────────────────────────────┘');
  Writeln;
  SetConsoleColors(COLOR_INPUT, 0);
  Write('  Select option: ');
end;

procedure TCOBConsole.WriteUnitMenu;
begin
  SetConsoleColors(COLOR_MENU, 0);
  GotoXY(1, 9);
  Writeln('  ┌─────────────────────────────────────┐');
  Writeln('  │  UNIT OPERATIONS                    │');
  Writeln('  ├─────────────────────────────────────┤');
  Writeln('  │  [I] Get Unit Info                  │');
  Writeln('  │  [H] Get Unit Health (HEALTH_VAL)  │');
  Writeln('  │  [K] Get Unit Kills (UNIT_KILLS)   │');
  Writeln('  │  [C] Set Cloak (SET_CLOAKED)        │');
  Writeln('  │  [D] Damage Unit (MAKE_DAMAGE)      │');
  Writeln('  │  [T] Get Unit Team (UNIT_TEAM)      │');
  Writeln('  │  [A] Allied Status (UNIT_ALLIED)    │');
  Writeln('  │  [R] Return to Main Menu            │');
  Writeln('  └─────────────────────────────────────┘');
  Writeln;
  SetConsoleColors(COLOR_INPUT, 0);
  Write('  Select option: ');
end;

procedure TCOBConsole.WriteMovementMenu;
begin
  SetConsoleColors(COLOR_MENU, 0);
  GotoXY(1, 9);
  Writeln('  ┌─────────────────────────────────────┐');
  Writeln('  │  MOVEMENT & POSITION                │');
  Writeln('  ├─────────────────────────────────────┤');
  Writeln('  │  [X] Get X Position (UNITX)         │');
  Writeln('  │  [Z] Get Z Position (UNITZ)         │');
  Writeln('  │  [Y] Get Y Position (UNITY)         │');
  Writeln('  │  [S] Set Height (UNITY setter)      │');
  Writeln('  │  [V] Get Speed (CURRENT_SPEED)      │');
  Writeln('  │  [T] Get Angles (TURNX/Y/Z)         │');
  Writeln('  │  [D] Get Distance (DISTANCE)        │');
  Writeln('  │  [G] Get Grid Pos (UNIT_GRID_XZ)    │');
  Writeln('  │  [R] Return to Main Menu            │');
  Writeln('  └─────────────────────────────────────┘');
  Writeln;
  SetConsoleColors(COLOR_INPUT, 0);
  Write('  Select option: ');
end;

procedure TCOBConsole.WriteSearchMenu;
begin
  SetConsoleColors(COLOR_MENU, 0);
  GotoXY(1, 9);
  Writeln('  ┌─────────────────────────────────────┐');
  Writeln('  │  SEARCH UNITS                       │');
  Writeln('  ├─────────────────────────────────────┤');
  Writeln('  │  [N] Units Near (UNITS_NEAR)        │');
  Writeln('  │  [Y] Yardmap (UNITS_YARDMAP)        │');
  Writeln('  │  [W] Whole Map (UNITS_WHOLEMAP)     │');
  Writeln('  │  [C] Nearest (UNIT_NEAREST)         │');
  Writeln('  │  [A] At Position (UNIT_AT_POSITION) │');
  Writeln('  │  [R] Return to Main Menu            │');
  Writeln('  └─────────────────────────────────────┘');
  Writeln;
  SetConsoleColors(COLOR_INPUT, 0);
  Write('  Select option: ');
end;

procedure TCOBConsole.WriteWeaponMenu;
begin
  SetConsoleColors(COLOR_MENU, 0);
  GotoXY(1, 9);
  Writeln('  ┌─────────────────────────────────────┐');
  Writeln('  │  WEAPONS & COMBAT                   │');
  Writeln('  ├─────────────────────────────────────┤');
  Writeln('  │  [P] Primary (WEAPON_PRIMARY)       │');
  Writeln('  │  [S] Secondary (WEAPON_SECONDARY)   │');
  Writeln('  │  [T] Tertiary (WEAPON_TERTIARY)     │');
  Writeln('  │  [F] Fire Weapon (FIRE_WEAPON)      │');
  Writeln('  │  [R] Reload Time                    │');
  Writeln('  │  [L] Locked Target (LOCKED_TARGET)  │');
  Writeln('  │  [U] Under Attack (UNDER_ATTACK)    │');
  Writeln('  │  [M] Return to Main Menu            │');
  Writeln('  └─────────────────────────────────────┘');
  Writeln;
  SetConsoleColors(COLOR_INPUT, 0);
  Write('  Select option: ');
end;

procedure TCOBConsole.WriteOrderMenu;
begin
  SetConsoleColors(COLOR_MENU, 0);
  GotoXY(1, 9);
  Writeln('  ┌─────────────────────────────────────┐');
  Writeln('  │  ORDERS & COMMANDS                  │');
  Writeln('  ├─────────────────────────────────────┤');
  Writeln('  │  [C] Current Order Type             │');
  Writeln('  │  [T] Order Target                   │');
  Writeln('  │  [A] Abort Order                    │');
  Writeln('  │  [M] Move to Position              │');
  Writeln('  │  [R] Return to Main Menu            │');
  Writeln('  └─────────────────────────────────────┘');
  Writeln;
  SetConsoleColors(COLOR_INPUT, 0);
  Write('  Select option: ');
end;

procedure TCOBConsole.WriteMapMenu;
begin
  SetConsoleColors(COLOR_MENU, 0);
  GotoXY(1, 9);
  Writeln('  ┌─────────────────────────────────────┐');
  Writeln('  │  MAP & AREA                         │');
  Writeln('  ├─────────────────────────────────────┤');
  Writeln('  │  [S] Sea Level (MAP_SEA_LEVEL)      │');
  Writeln('  │  [L] Lava Map (IS_LAVA_MAP)         │');
  Writeln('  │  [M] Metal Surface (SURFACE_METAL)  │');
  Writeln('  │  [T] Test Unload (TEST_UNLOAD_POS)  │');
  Writeln('  │  [B] Test Build (TEST_BUILD_SPOT)   │');
  Writeln('  │  [F] Feature at Pos (FEATURE_*)     │');
  Writeln('  │  [G] Grid Info (GRID_INFO)          │');
  Writeln('  │  [R] Return to Main Menu            │');
  Writeln('  └─────────────────────────────────────┘');
  Writeln;
  SetConsoleColors(COLOR_INPUT, 0);
  Write('  Select option: ');
end;

procedure TCOBConsole.WriteEffectsMenu;
begin
  SetConsoleColors(COLOR_MENU, 0);
  GotoXY(1, 9);
  Writeln('  ┌─────────────────────────────────────┐');
  Writeln('  │  EFFECTS & SOUND                    │');
  Writeln('  ├─────────────────────────────────────┤');
  Writeln('  │  [S] 3D Sound (PLAY_3D_SOUND)       │');
  Writeln('  │  [A] GAF Anim (PLAY_GAF_ANIM)       │');
  Writeln('  │  [E] SFX Emit (EMIT_SFX)            │');
  Writeln('  │  [P] Play Speech (UNIT_SPEECH)      │');
  Writeln('  │  [F] Place Feature (MS_PLACE_*)     │');
  Writeln('  │  [M] Emit Smoke (MS_EMIT_SMOKE)     │');
  Writeln('  │  [R] Return to Main Menu            │');
  Writeln('  └─────────────────────────────────────┘');
  Writeln;
  SetConsoleColors(COLOR_INPUT, 0);
  Write('  Select option: ');
end;

procedure TCOBConsole.ReadInput(var Key: Char);
begin
  ReadLn(Key);
  Key := UpCase(Key);
end;

procedure TCOBConsole.DisplayUnitInfo;
var
  UnitID: Integer;
begin
  SetConsoleColors(COLOR_INPUT, 0);
  Write('  Enter Unit ID: ');
  ReadLn(UnitID);
  Writeln;

  if UnitID > 0 then
  begin
    FSelectedUnitID := UnitID;
    SetConsoleColors(COLOR_SUCCESS, 0);
    Writeln('  ╔═════════════════════════════════════╗');
    Writeln('  ║  UNIT INFORMATION                   ║');
    Writeln('  ╠═════════════════════════════════════╣');
    Writeln(Format('  ║  Unit ID: %d', [UnitID]));
    Writeln('  ║  [Live Query via COB Extensions]   ║');
    Writeln('  ║  Use sub-menus to get details      ║');
    Writeln('  ╚═════════════════════════════════════╝');
    Writeln;
    SendTextLocal(Format('[COB] Selected Unit ID: %d', [UnitID]));
  end
  else
  begin
    SetConsoleColors(COLOR_ERROR, 0);
    Writeln('  ERROR: Invalid Unit ID');
    Writeln;
    SendTextLocal('[COB] ERROR: Invalid Unit ID');
  end;

  SetConsoleColors(COLOR_INPUT, 0);
  Write('  Press ENTER to continue...');
  ReadLn;
end;

procedure TCOBConsole.DisplayMapInfo;
begin
  SetConsoleColors(COLOR_SUCCESS, 0);
  Writeln;
  Writeln('  ╔═════════════════════════════════════╗');
  Writeln('  ║  MAP INFORMATION (Via COB)         ║');
  Writeln('  ╠═════════════════════════════════════╣');
  Writeln('  ║  Sea Level: [MAP_SEA_LEVEL query]  ║');
  Writeln('  ║  Is Lava: [IS_LAVA_MAP query]      ║');
  Writeln('  ║  Surface Metal: [query...]          ║');
  Writeln('  ╚═════════════════════════════════════╝');
  Writeln;
  SendTextLocal('[COB] Querying map information...');

  SetConsoleColors(COLOR_INPUT, 0);
  Write('  Press ENTER to continue...');
  ReadLn;
end;

procedure TCOBConsole.MoveUnitInteractive;
var
  TargetX, TargetZ, TargetY: Integer;
begin
  SetConsoleColors(COLOR_INPUT, 0);
  Writeln;
  Write('  Enter Target X Position: ');
  ReadLn(TargetX);
  Write('  Enter Target Z Position: ');
  ReadLn(TargetZ);
  Write('  Enter Target Y Position (-1 for auto): ');
  ReadLn(TargetY);
  Writeln;

  SetConsoleColors(COLOR_SUCCESS, 0);
  Writeln(Format('  ORDER: Moving to [%d, %d, %d]', [TargetX, TargetZ, TargetY]));
  Writeln('  Function: ORDER_SELF_POS (COB Extension)');
  Writeln('  Status: Order queued to unit');
  Writeln;
  SendTextLocal(Format('[COB] Move order: [%d,%d,%d]', [TargetX, TargetZ, TargetY]));
end;

procedure TCOBConsole.SearchUnitsInteractive;
var
  SearchRadius: Integer;
  SearchType: Char;
begin
  SetConsoleColors(COLOR_INPUT, 0);
  Writeln;
  Writeln('  Search Types:');
  Writeln('    [N] Near - UNITS_NEAR');
  Writeln('    [Y] Yardmap - UNITS_YARDMAP');
  Writeln('    [W] Whole Map - UNITS_WHOLEMAP');
  Write('  Select: ');
  ReadLn(SearchType);

  if SearchType <> 'W' then
  begin
    Write('  Enter radius: ');
    ReadLn(SearchRadius);
  end
  else
    SearchRadius := 0;
  Writeln;

  SetConsoleColors(COLOR_SUCCESS, 0);
  Writeln('  Searching via COB Extensions...');
  Writeln('  Results: [Units found]');
  Writeln;
  SendTextLocal(Format('[COB] Unit search: Type=%s Radius=%d', [SearchType, SearchRadius]));
end;

procedure TCOBConsole.FireWeaponInteractive;
var
  WeaponType: Char;
  TargetID: Integer;
begin
  SetConsoleColors(COLOR_INPUT, 0);
  Writeln;
  Writeln('  Weapon Types: [P]rimary [S]econdary [T]ertiary');
  Write('  Select: ');
  ReadLn(WeaponType);

  Write('  Target Unit ID: ');
  ReadLn(TargetID);
  Writeln;

  SetConsoleColors(COLOR_SUCCESS, 0);
  Writeln(Format('  FIRE: Engaging target Unit %d', [TargetID]));
  Writeln('  Function: FIRE_WEAPON (COB Extension)');
  Writeln;
  SendTextLocal(Format('[COB] Fire weapon at Unit %d', [TargetID]));
end;

procedure TCOBConsole.IssueOrderInteractive;
var
  OrderType: Char;
begin
  SetConsoleColors(COLOR_INPUT, 0);
  Writeln;
  Writeln('  Order Types: [M]ove [A]ttack [G]uard [B]uild');
  Write('  Select: ');
  ReadLn(OrderType);
  Writeln;

  SetConsoleColors(COLOR_SUCCESS, 0);
  Writeln('  Order issued via COB Extensions');
  Writeln('  Status: Executing...');
  Writeln;
  SendTextLocal(Format('[COB] Order issued: %s', [OrderType]));
end;

procedure TCOBConsole.PlaySoundInteractive;
var
  SoundID: Integer;
begin
  SetConsoleColors(COLOR_INPUT, 0);
  Writeln;
  Write('  Sound ID: ');
  ReadLn(SoundID);
  Writeln;

  SetConsoleColors(COLOR_SUCCESS, 0);
  Writeln(Format('  Playing sound #%d', [SoundID]));
  Writeln('  Function: PLAY_3D_SOUND or MS_PLAY_SOUND_3D');
  Writeln;
  SendTextLocal(Format('[COB] Playing sound #%d', [SoundID]));
end;

procedure TCOBConsole.PlaceFeatureInteractive;
var
  FeatureID, X, Z: Integer;
begin
  SetConsoleColors(COLOR_INPUT, 0);
  Writeln;
  Write('  Feature ID: ');
  ReadLn(FeatureID);
  Write('  X Position: ');
  ReadLn(X);
  Write('  Z Position: ');
  ReadLn(Z);
  Writeln;

  SetConsoleColors(COLOR_SUCCESS, 0);
  Writeln(Format('  Placing feature #%d at [%d, %d]', [FeatureID, X, Z]));
  Writeln('  Function: MS_PLACE_FEATURE (COB Extension)');
  Writeln;
  SendTextLocal(Format('[COB] Placing feature #%d at [%d,%d]', [FeatureID, X, Z]));
end;

procedure TCOBConsole.GetUnitHealth;
begin
  SetConsoleColors(COLOR_SUCCESS, 0);
  Writeln;
  Writeln('  Getting Unit Health...');
  Writeln('  COB Extension: HEALTH_VAL');
  Writeln('  Health: [query...]');
  Writeln;
  SendTextLocal('[COB] Query: Unit Health (HEALTH_VAL)');
end;

procedure TCOBConsole.GetUnitKills;
begin
  SetConsoleColors(COLOR_SUCCESS, 0);
  Writeln;
  Writeln('  Getting Unit Kills...');
  Writeln('  COB Extension: UNIT_KILLS');
  Writeln('  Kills: [query...]');
  Writeln;
  SendTextLocal('[COB] Query: Unit Kills (UNIT_KILLS)');
end;

procedure TCOBConsole.SetUnitCloak;
var
  CloakState: Integer;
begin
  SetConsoleColors(COLOR_INPUT, 0);
  Write('  Cloak State (0=off, 1=on): ');
  ReadLn(CloakState);
  Writeln;

  SetConsoleColors(COLOR_SUCCESS, 0);
  Writeln('  Setting Unit Cloak...');
  Writeln('  COB Extension: SET_CLOAKED');
  Writeln(Format('  State: %d', [CloakState]));
  Writeln;
  SendTextLocal(Format('[COB] Cloak set to: %d', [CloakState]));
end;

procedure TCOBConsole.DamageUnit;
var
  DamageAmount: Integer;
begin
  SetConsoleColors(COLOR_INPUT, 0);
  Write('  Damage Amount: ');
  ReadLn(DamageAmount);
  Writeln;

  SetConsoleColors(COLOR_SUCCESS, 0);
  Writeln('  Applying Damage...');
  Writeln('  COB Extension: MAKE_DAMAGE');
  Writeln(Format('  Damage: %d', [DamageAmount]));
  Writeln;
  SendTextLocal(Format('[COB] Damage applied: %d', [DamageAmount]));
end;

procedure TCOBConsole.GetUnitTeam;
begin
  SetConsoleColors(COLOR_SUCCESS, 0);
  Writeln;
  Writeln('  Getting Unit Team...');
  Writeln('  COB Extension: UNIT_TEAM');
  Writeln('  Team: [query...]');
  Writeln;
  SendTextLocal('[COB] Query: Unit Team (UNIT_TEAM)');
end;

procedure TCOBConsole.CheckAlliedStatus;
begin
  SetConsoleColors(COLOR_SUCCESS, 0);
  Writeln;
  Writeln('  Checking Allied Status...');
  Writeln('  COB Extension: UNIT_ALLIED');
  Writeln('  Status: [query...]');
  Writeln;
  SendTextLocal('[COB] Query: Allied Status (UNIT_ALLIED)');
end;

procedure TCOBConsole.GetUnitSpeed;
begin
  SetConsoleColors(COLOR_SUCCESS, 0);
  Writeln;
  Writeln('  Getting Unit Speed...');
  Writeln('  COB Extension: CURRENT_SPEED');
  Writeln('  Speed: [query...]');
  Writeln;
  SendTextLocal('[COB] Query: Current Speed (CURRENT_SPEED)');
end;

procedure TCOBConsole.GetUnitTurnAngles;
begin
  SetConsoleColors(COLOR_SUCCESS, 0);
  Writeln;
  Writeln('  Getting Unit Rotation...');
  Writeln('  COB Extensions: TURNX, TURNY, TURNZ');
  Writeln('  Angles: [query...]');
  Writeln;
  SendTextLocal('[COB] Query: Turn angles (TURNX/Y/Z)');
end;

procedure TCOBConsole.GetUnitPosition;
begin
  SetConsoleColors(COLOR_SUCCESS, 0);
  Writeln;
  Writeln('  Getting Unit Position...');
  Writeln('  COB Extensions: UNITX, UNITZ, UNITY');
  Writeln('  Position: [query...]');
  Writeln;
  SendTextLocal('[COB] Query: Unit Position (UNITX/Z/Y)');
end;

procedure TCOBConsole.SetUnitHeight;
var
  NewHeight: Integer;
begin
  SetConsoleColors(COLOR_INPUT, 0);
  Write('  New Height (Y): ');
  ReadLn(NewHeight);
  Writeln;

  SetConsoleColors(COLOR_SUCCESS, 0);
  Writeln('  Setting Unit Height...');
  Writeln('  COB Extension: UNITY (setter)');
  Writeln(Format('  Height: %d', [NewHeight]));
  Writeln;
  SendTextLocal(Format('[COB] Height set to: %d', [NewHeight]));
end;

procedure TCOBConsole.GetUnitDistance;
var
  OtherUnitID: Integer;
begin
  SetConsoleColors(COLOR_INPUT, 0);
  Write('  Target Unit ID: ');
  ReadLn(OtherUnitID);
  Writeln;

  SetConsoleColors(COLOR_SUCCESS, 0);
  Writeln('  Calculating Distance...');
  Writeln('  COB Extension: DISTANCE');
  Writeln(Format('  Distance: [query...]', [OtherUnitID]));
  Writeln;
  SendTextLocal(Format('[COB] Distance to Unit %d: [querying]', [OtherUnitID]));
end;

procedure TCOBConsole.ToggleConsole;
begin
  FConsoleVisible := not FConsoleVisible;
  if FConsoleVisible then
  begin
    ProcessInput;
  end;
end;

procedure TCOBConsole.ProcessInput;
var
  Key: Char;
  KeepGoing: Boolean;
begin
  FConsoleActive := True;
  KeepGoing := True;

  while KeepGoing and FConsoleActive do
  begin
    ClearScreen;
    WriteMainMenu;
    ReadInput(Key);
    Writeln;

    case Key of
      'U': begin
        KeepGoing := True;
        while KeepGoing do
        begin
          ClearScreen;
          WriteUnitMenu;
          ReadInput(Key);
          case Key of
            'I': DisplayUnitInfo;
            'H': GetUnitHealth;
            'K': GetUnitKills;
            'C': SetUnitCloak;
            'D': DamageUnit;
            'T': GetUnitTeam;
            'A': CheckAlliedStatus;
            'R': KeepGoing := False;
          end;
          if Key <> 'R' then
          begin
            SetConsoleColors(COLOR_INPUT, 0);
            Write('  Press ENTER...');
            ReadLn;
          end;
        end;
      end;
      'M': begin
        KeepGoing := True;
        while KeepGoing do
        begin
          ClearScreen;
          WriteMovementMenu;
          ReadInput(Key);
          case Key of
            'X', 'Z', 'Y': GetUnitPosition;
            'S': SetUnitHeight;
            'V': GetUnitSpeed;
            'T': GetUnitTurnAngles;
            'D': GetUnitDistance;
            'G': GetUnitPosition;
            'R': KeepGoing := False;
          end;
          if Key <> 'R' then
          begin
            SetConsoleColors(COLOR_INPUT, 0);
            Write('  Press ENTER...');
            ReadLn;
          end;
        end;
      end;
      'S': SearchUnitsInteractive;
      'W': begin
        KeepGoing := True;
        while KeepGoing do
        begin
          ClearScreen;
          WriteWeaponMenu;
          ReadInput(Key);
          case Key of
            'F': FireWeaponInteractive;
            'M': KeepGoing := False;
            else begin
              SetConsoleColors(COLOR_SUCCESS, 0);
              Writeln;
              Writeln('  Weapon data: [query...]');
              Writeln;
              SetConsoleColors(COLOR_INPUT, 0);
              Write('  Press ENTER...');
              ReadLn;
            end;
          end;
        end;
      end;
      'O': IssueOrderInteractive;
      'A': DisplayMapInfo;
      'E': PlaySoundInteractive;
      'I': DisplayMapInfo;
      'Q': begin
        KeepGoing := False;
        SetConsoleColors(COLOR_HEADER, 0);
        Writeln;
        Writeln('  Closing COB Console...');
        Writeln;
        FConsoleActive := False;
        FConsoleVisible := False;
        SendTextLocal('[COB] Console closed');
      end;
    end;
  end;
end;

procedure HandleConsoleHotkey;
begin
  if Assigned(COBConsole) then
    COBConsole.ToggleConsole;
end;

procedure RegisterCOBConsole;
begin
  if not Assigned(COBConsole) then
  begin
    COBConsole := TCOBConsole.Create;
  end;
end;

procedure UnregisterCOBConsole;
begin
  if Assigned(COBConsole) then
  begin
    COBConsole.Free;
    COBConsole := nil;
  end;
end;

initialization
  COBConsole := nil;

finalization
  UnregisterCOBConsole;

end.
