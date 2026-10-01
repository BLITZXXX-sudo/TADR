unit KeyboardHook;
{

}
interface
uses
  PluginEngine, Windows, Messages, SysUtils;

// -----------------------------------------------------------------------------

const
  State_KeyboardHook: Boolean = True;

function GetPlugin : TPluginData;

// -----------------------------------------------------------------------------

procedure OnInstallKeyboardHook;
procedure OnUninstallKeyboardHook;

var
  hKeyboardHook: HHook;
  keyboardHookLevel: byte;

function KeyboardHookFunction(nCode: Integer; wParam: Word; lParam: LongInt): LRESULT; stdcall;
procedure SetInGameHotkeysLevel;

// -----------------------------------------------------------------------------
// actions for keys

procedure SwitchSetShareEnergy;
procedure UpdateSelectUnitEffect;
procedure ApplySelectUnitMenu_Wrapper;
function FindIdleFactory : Boolean;
procedure SquadGroup_Select(GroupNum: Integer);
procedure Squad_ApplyFormation(FormationType: Integer);

var
  // Alt+Shift+1..9 squad groups: each holds the short unit IDs assigned to
  // it. Short IDs can be recycled onto an unrelated unit after death (see
  // the TADR docs' own CONFIRM_LONG_ID note) - SquadGroup_Select guards
  // against the common case (member died) via a liveness check on recall,
  // but this is not a full long-ID confirmation.
  SquadGroups: array[1..9] of array of Word;

  // Alt+Shift+N cycles 1->2->3->4->5->6->7->1->... through the formations
  // (Line, Wall, Triangle, Square, Circle, Blitz, Spell).
  CurrentFormationCycle: Integer;

// -----------------------------------------------------------------------------

implementation
uses
  idplay,
  Math,
  TA_MemoryLocations,
  TA_MemPlayers,
  TA_MemUnits,
  TA_MemoryStructures,
  TA_MemoryConstants,
  TA_FunctionsU,
  GUIEnhancements,
  //BattleRoomScroll,
  SaveUnitsWeaponsList,
  UnitActions,
  UnitInfoExpand,
  CloakOnly,
  UnitConsole,
  UnitPortal;

const
  LastNum : Cardinal = 0;

var
  lastShareEnergyVal: single;
  Semaphore_IdleFactory : THandle;
  COBConsoleInitialized: Boolean = False;  { Track if console was already initialized }

Procedure OnInstallKeyboardHook;
begin
  keyboardHookLevel := 2;
  lastShareEnergyVal := 0;
  hKeyboardHook:= SetWindowsHookEx(WH_KEYBOARD, @KeyboardHookFunction, 0, GetCurrentThreadId);
  Semaphore_IdleFactory := CreateSemaphore(nil, 1, 1, '');
  { Do NOT initialize COB Console at startup - defer until first hotkey press }
end;

Procedure OnUninstallKeyboardHook;
begin
  { UnitConsole and UnitPortal each clean themselves up via their own
    finalization sections, so no explicit console teardown is needed here. }
  CloseHandle(Semaphore_IdleFactory);
  if (hKeyboardHook <> 0) then
    UnhookWindowsHookEx(hKeyboardHook);
end;

function GetPlugin : TPluginData;
begin
  if IsTAVersion31 and State_KeyboardHook then
  begin
    Result := TPluginData.create( true,
                                'Keyboard Hook',
                                State_KeyboardHook,
                                @OnInstallKeyboardHook, @OnUnInstallKeyboardHook );

    Result.MakeRelativeJmp( State_KeyboardHook,
                            'set ingame hotkeys level',
                            @SetInGameHotkeysLevel,
                            $00498362, 1);
  end else
    result := nil;
end;

procedure SetInGameHotkeysLevel;
asm
  mov     keyboardHookLevel, 2
  mov     ecx, [TADynMemStructPtr]
  push $0049836D;
  call PatchNJump;
end;

function KeyboardHookFunction(nCode: Integer; wParam: Word; lParam: LongInt): LRESULT; stdcall;
var
  UnitAtMouse: PUnitStruct;
begin
  if nCode < 1 then
    CallNextHookEx(hKeyboardHook, nCode, wParam, lParam)
  else
  begin
    if ((lParam and $80000000) = 0) then
    begin
      if keyboardHookLevel > 1 then
      begin
        case wParam of
        $5A : begin     // left alt + shift + z
                if ( ((GetAsyncKeyState(VK_MENU) and $8000) > 0) and
                     ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) ) then
                begin
                  SwitchSetShareEnergy;
                  Result := 1;
                  Exit;
                end;
              end;
        $58 : begin     // left alt + shift + x
                if ( ((GetAsyncKeyState(VK_MENU) and $8000) > 0) and
                     ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) ) then
                begin
                  InterpretInternalCommand(PChar('shareenergy'));
                  Result := 1;
                  Exit;
                end;
              end;
        $43 : begin     // left alt + shift + c
                if ( ((GetAsyncKeyState(VK_MENU) and $8000) > 0) and
                     ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) ) then
                begin
                  InterpretInternalCommand(PChar('sharemetal'));
                  Result := 1;
                  Exit;
                end;
              end;
        $41 : begin     // left alt + shift + a
                if ( ((GetAsyncKeyState(VK_MENU) and $8000) > 0) and
                     ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) ) then
                begin
                  TAData.ShootAll := not TAData.ShootAll;
                  if TAData.ShootAll then
                    SendTextLocal('Toggled ShootAll to: ON')
                  else
                    SendTextLocal('Toggled ShootAll to: OFF');
                  Result := 1;
                  Exit;
                end;
              end;
        // (Alt+Shift+B / Alt+Shift+V unit-spawn cheat hotkeys removed - BLITZ CLAN build)
        $53 : begin     // left alt + shift + s
                if ( ((GetAsyncKeyState(VK_MENU) and $8000) > 0) and
                     ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) ) then
                begin
                  UnitAtMouse := TAUnit.AtMouse;
                  if (UnitAtMouse <> nil) then
                    if TAUnit.IsOnThisComp(UnitAtMouse, False) then
                    begin
                     // UnitAtMouse.p_MainOrder.p_NextOrder := nil;
                   //   UnitAtMouse.p_SubOrder := nil;
                    //  Result := 1;
                     // Exit;
                    end;
                end;
                // ctrl + shift + s
                if ( ((GetAsyncKeyState(VK_CONTROL) and $8000) > 0) and
                     ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) ) then
                begin
                  RemoveBuildQueuesFromSelected;
                  //DeselectAllUnits;
                  Result := 1;
                  Exit;
                end;
              end;
        {$IFDEF Debug}
        $51 : begin     // left alt + shift + q
                if ( ((GetAsyncKeyState(VK_MENU) and $8000) > 0) and
                     ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) ) then
                begin
                  UnitAtMouse := TAUnit.AtMouse;
                  if (UnitAtMouse <> nil) then
                  begin
                  end;
                end;
              end;
        $72 : begin     // shift + F3
                if ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) then
                begin
                end;
              end;
        {$ENDIF}
        $57 : begin     // left alt + shift + w
                if ( ((GetAsyncKeyState(VK_MENU) and $8000) > 0) and
                     ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) ) then
                begin
                  if TAData.DevMode then
                  begin
                    SaveUnitsWeaponsListToScriptorFile;
                    SendTextLocal('Saved current list of units and weapons to file');
                  end;
                end;
              end;
        $13 : begin     // pause button
                if TAData.NetworkLayerEnabled and Assigned(GlobalDPlay) then
                  if GlobalDPlay.AutopauseAtStart and not GlobalDPlay.Players[TAData.LocalPlayerID+1].IsServer then
                  begin
                    Msg_Reminder(PAnsiChar('Only the host can unpause.' +#13#10+ 'You can also vote to go with .ready command'), 1);
                    Result := 1;
                    Exit;
                  end;
              end;
        $5D : begin     // MENU KEY
                InterpretCommand('showranges', 1);
              end;
        $4C : begin     // Alt + Shift + L  →  Toggle Unit Console
                if ( ((GetAsyncKeyState(VK_MENU) and $8000) > 0) and
                     ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) ) then
                begin
                  UnitConsole.ToggleUnitConsole;
                  Result := 1;
                  Exit;
                end;
              end;
        $4B : begin     // Alt + Shift + K  →  Toggle Portal Console
                if ( ((GetAsyncKeyState(VK_MENU) and $8000) > 0) and
                     ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) ) then
                begin
                  UnitPortal.TogglePortalConsole;
                  Result := 1;
                  Exit;
                end;
              end;
        $46 : begin     // ctrl + f
                if ( ((GetAsyncKeyState(VK_CONTROL) and $8000) > 0) and
                     ((GetAsyncKeyState(VK_SHIFT) and $8000) = 0) ) then
                begin
                  if FindIdleFactory then
                  begin
                    UpdateSelectUnitEffect;
                    ApplySelectUnitMenu_Wrapper;
                  end;
                  Result := 1;
                  Exit;
                end;
              end; {
        $47 : begin     // left alt + shift + g
                if ( ((GetAsyncKeyState(VK_MENU) and $8000) > 0) and
                     ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) ) then
                begin
                end;
              end;   }
     //   $52 : begin     // Alt + Shift + R  →  decrease cloak radius
           //         if ( ((GetAsyncKeyState(VK_MENU) and $8000) > 0) and
          //               ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) ) then
          //          begin
        //              CloakOnly_RadiusDecrease;
           //           Result := 1;
         //             Exit;
         //           end;
         //         end;
        //    $54 : begin     // Alt + Shift + T  →  increase cloak radius
           //         if ( ((GetAsyncKeyState(VK_MENU) and $8000) > 0) and
                 //        ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) ) then
           //         begin
                    //  CloakOnly_RadiusIncrease;
           //           Result := 1;
                 //     Exit;
              //      end;
               //   end;
      //      $50 : begin     // Alt + Shift + P  →  print cloak settings
            //        if ( ((GetAsyncKeyState(VK_MENU) and $8000) > 0) and
                  //       ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) ) then
                 //   begin
                     // CloakOnly_PrintInfo;
                //      Result := 1;
                  //    Exit;
         //       end;
           //   end;
       // $4F : begin     // Alt + Shift + O  →  (drawing removed, reserved)
                end;
        //    $49 : begin     // Alt + Shift + I  →  cycle debug array mode
              //      if ( ((GetAsyncKeyState(VK_MENU) and $8000) > 0) and
                    //     ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) ) then
             //       begin
                   //   CloakOnly_CycleDebugMode;
                  //    Result := 1;
                   //   Exit;
              //  end;
             // end;

     end else
     begin
       if keyboardHookLevel > 0 then
       begin
         //case wParam of
         //  VK_PRIOR: ScrollBattleRoomTextWindowUp;
         //  VK_NEXT : ScrollBattleRoomTextWindowDown;
         //end;
       end; { hooklevel }
     end;
     end;
  end; { ncode }
  // don't block key
  Result:= 0;
end;

{
Switch share energy to 0 or latest value
(also enable sharing if it's disabled)
}
procedure SwitchSetShareEnergy;
begin
  if not TAData.ShareEnergy then
    InterpretInternalCommand('shareenergy');
  if TAData.ShareEnergyVal > 0 then
  begin
    lastShareEnergyVal := TAData.ShareEnergyVal;
    InterpretInternalCommand('setshareenergy 0');
  end else
    InterpretInternalCommand('setshareenergy '+IntToStr(Round(lastShareEnergyVal)));
end;

procedure UpdateSelectUnitEffect;
begin
  TAData.MainStruct.DesktopGUIState := TAData.MainStruct.DesktopGUIState or $10;
  TAData.MainStruct.ShowRangeUnitIndex := 0;
end;

procedure ApplySelectUnitMenu_Wrapper;
var
  old: Byte;
begin
  old := TAData.MainStruct.ucPrepareOrderType;
  ApplySelectUnitMenu;
  TAData.MainStruct.ucPrepareOrderType := old;
end;

procedure ScrollCenterView(X, Z : Integer; Smooth: Boolean);
var
  MaxX, MaxZ : Integer;
begin
  X := X - (TAData.MainStruct.ScreenWidth-128) div 2;
  Z := Z - (TAData.MainStruct.ScreenHeight-64) div 2;

  if X < 0 then X := 0
  else begin
    MaxX := TAData.MainStruct.TNTMemStruct.lRadarPictureWidth - ((TAData.MainStruct.ScreenWidth-128));
    if (X > MaxX) then
      X := MaxX;
  end;

  if Z < 0 then Z := 0
  else begin
    MaxZ := TAData.MainStruct.TNTMemStruct.lRadarPictureHeight - ((TAData.MainStruct.ScreenHeight-64));
    if (Z > MaxZ) then
      Z := MaxZ;
  end;

  ScrollView(X, Z, Smooth);
end;

function FindIdleFactory : Boolean;
label
  Retry;
var
  WaitResult : Cardinal;
  j : Cardinal;
  PlayerMaxUnitID : Cardinal;
  CurrentUnit : PUnitStruct;
  Player : PPlayerStruct;
begin
  Result := False;
  WaitResult := WaitForSingleObject(Semaphore_IdleFactory, INFINITE);
  if WaitResult = WAIT_FAILED then
    Exit;
  if WaitResult = WAIT_TIMEOUT then
  begin
    ReleaseSemaphore(Semaphore_IdleFactory, 1, nil);
    Exit;
  end;

Retry:
  j := LastNum;
  Player := TAPlayer.GetPlayerByIndex(TAData.LocalPlayerID);
  PlayerMaxUnitID := Player.nNumUnits;
  CurrentUnit := TAData.UnitsArray_p;

  while (j<=PlayerMaxUnitID) do
  begin
    CurrentUnit := Pointer(Cardinal(Player.p_UnitsArray) + j * SizeOf(TUnitStruct));
    if ((CurrentUnit.lUnitStateMask and UnitSelectState[UnitValid2_State]) = UnitSelectState[UnitValid2_State]) then
    begin
      if CurrentUnit.fBuildTimeLeft = 0.0 then
        if CurrentUnit.p_Owner <> nil then
        begin
          if CurrentUnit.p_UNITINFO <> nil then
          begin
            if CurrentUnit.p_UNITINFO.cBMCode = 0 then
              if TAUnit.GetUnitInfoField(CurrentUnit, uiBUILDER) <> 0 then
              begin
                if UnitInfoCustomFields[CurrentUnit.p_UNITINFO.nCategory].NotLab then
                begin
                  Inc(j);
                  Continue;
                end else
                begin
                  if CurrentUnit.p_MainOrder <> nil then
                    if PUnitOrder(CurrentUnit.p_MainOrder).cOrderType = $C then
                    begin
                      Inc(j);
                      Continue;
                    end;
                end;
                if (LastNum<j) then
                begin
                  LastNum := j;
                  Break;
                end;
              end;
          end;
        end;
    end;
    Inc(j);
  end;
  if (j<=PlayerMaxUnitID) then
  begin
    DeselectAllUnits;
    CurrentUnit.lUnitStateMask := CurrentUnit.lUnitStateMask or UnitSelectState[UnitSelected_State];
    ScrollCenterView(CurrentUnit.Position.X, CurrentUnit.Position.Z, True);
    Result := True;
  end else
  begin
    if (LastNum<>0) then
    begin
      LastNum := 0;
      goto Retry;
    end;
  end;
  ReleaseSemaphore(Semaphore_IdleFactory, 1, nil);
end;

// -----------------------------------------------------------------------------
// SquadGroup_Select - Alt+Shift+1..9 squad group hotkey action.
//
// If the local player currently has any units selected -> ASSIGN them to
// GroupNum (replacing whatever was there before).
// If nothing is selected -> RECALL GroupNum: select every still-living
// member and center the camera on their average position.
// -----------------------------------------------------------------------------
procedure SquadGroup_Select(GroupNum: Integer);
var
  Player          : PPlayerStruct;
  PlayerMaxUnitID : Cardinal;
  CurrentUnit     : PUnitStruct;
  i, n            : Cardinal;
  AnySelected     : Boolean;
  CenterX, CenterZ: Int64;
  FoundCount      : Integer;
begin
  Player := TAPlayer.GetPlayerByIndex(TAData.LocalPlayerID);
  PlayerMaxUnitID := Player.nNumUnits;

  // Pass 1: is anything selected right now? Decides assign vs recall.
  AnySelected := False;
  for i := 0 to PlayerMaxUnitID do
  begin
    CurrentUnit := Pointer(Cardinal(Player.p_UnitsArray) + i * SizeOf(TUnitStruct));
    if ((CurrentUnit.lUnitStateMask and UnitSelectState[UnitSelected_State]) = UnitSelectState[UnitSelected_State]) then
    begin
      AnySelected := True;
      Break;
    end;
  end;

  if AnySelected then
  begin
    // ---- ASSIGN: record every selected unit's short ID into this group ----
    SetLength(SquadGroups[GroupNum], 0);
    for i := 0 to PlayerMaxUnitID do
    begin
      CurrentUnit := Pointer(Cardinal(Player.p_UnitsArray) + i * SizeOf(TUnitStruct));
      if ((CurrentUnit.lUnitStateMask and UnitSelectState[UnitSelected_State]) = UnitSelectState[UnitSelected_State]) then
      begin
        n := Length(SquadGroups[GroupNum]);
        SetLength(SquadGroups[GroupNum], n + 1);
        SquadGroups[GroupNum][n] := TAUnit.GetId(CurrentUnit);
      end;
    end;
    SendTextLocal('Squad group ' + IntToStr(GroupNum) + ' assigned (' +
      IntToStr(Length(SquadGroups[GroupNum])) + ' units)');
  end
  else
  begin
    // ---- RECALL: select every still-alive stored member ----
    if Length(SquadGroups[GroupNum]) = 0 then
    begin
      SendTextLocal('Squad group ' + IntToStr(GroupNum) + ' is empty');
      Exit;
    end;

    DeselectAllUnits;
    FoundCount := 0;
    CenterX := 0;
    CenterZ := 0;

    for i := 0 to Cardinal(Length(SquadGroups[GroupNum]) - 1) do
    begin
      CurrentUnit := TAUnit.Id2Ptr(SquadGroups[GroupNum][i]);
      // Same liveness sanity check used elsewhere (IsUnitAlive in
      // CloakOnly.pas) - catches "member died", not full long-ID recycling.
      if (CurrentUnit <> nil) and (DWORD(CurrentUnit) > $10000)
         and (CurrentUnit^.nHealth > 0) then
      begin
        CurrentUnit.lUnitStateMask := CurrentUnit.lUnitStateMask or UnitSelectState[UnitSelected_State];
        Inc(CenterX, CurrentUnit^.Position.X);
        Inc(CenterZ, CurrentUnit^.Position.Z);
        Inc(FoundCount);
      end;
    end;

    if FoundCount > 0 then
      ScrollCenterView(Integer(CenterX div FoundCount), Integer(CenterZ div FoundCount), True)
    else
      SendTextLocal('Squad group ' + IntToStr(GroupNum) + ' - all members lost');
  end;
end;

// -----------------------------------------------------------------------------
// Squad_ApplyFormation - arranges the currently selected units into a shape.
// FormationType: 1 = Line (column, single file), 2 = Wall (abreast, side by
// side), 3 = Triangle (wedge, tip forward).
//
// Centered on the selection's current average position. Oriented to the
// FIRST selected unit's current facing (Turn.Z) - a 16-bit angle where
// 65536 = 360 degrees, matching the TADR docs' own "TURNZ = ORIENTATION in
// TA:K" note. Worth confirming that scaling live if the formation comes out
// rotated wrong.
//
// Uses TAUnit.CreateMainOrder / Action_Move_Ground the same way
// OrdersOverride.pas already does elsewhere in this project.
// -----------------------------------------------------------------------------
const
  FormationSpacing = 64;  // world units between formation slots - tune to taste

// -----------------------------------------------------------------------------
// Tiny 3-wide x 5-tall dot-matrix font, used only by FormationType 7 (Spell).
// Only B, L, I, T, Z are defined - just enough for "BLITZ". Add more letters
// here the same way (Col,Row pairs, top-left origin) if you want other words.
// -----------------------------------------------------------------------------
type
  TGlyphPoint      = record
    Col, Row : Integer;
  end;
  TGlyphPointArray = array of TGlyphPoint;

function GetGlyphPoints(Letter: Char): TGlyphPointArray;

  procedure AddPt(var Arr: TGlyphPointArray; C, R: Integer);
  var n: Integer;
  begin
    n := Length(Arr);
    SetLength(Arr, n + 1);
    Arr[n].Col := C;
    Arr[n].Row := R;
  end;

begin
  SetLength(Result, 0);
  case UpCase(Letter) of
    'B' : begin
            AddPt(Result,0,0); AddPt(Result,1,0);
            AddPt(Result,0,1);                     AddPt(Result,2,1);
            AddPt(Result,0,2); AddPt(Result,1,2);
            AddPt(Result,0,3);                     AddPt(Result,2,3);
            AddPt(Result,0,4); AddPt(Result,1,4);
          end;
    'L' : begin
            AddPt(Result,0,0);
            AddPt(Result,0,1);
            AddPt(Result,0,2);
            AddPt(Result,0,3);
            AddPt(Result,0,4); AddPt(Result,1,4); AddPt(Result,2,4);
          end;
    'I' : begin
            AddPt(Result,0,0); AddPt(Result,1,0); AddPt(Result,2,0);
                                AddPt(Result,1,1);
                                AddPt(Result,1,2);
                                AddPt(Result,1,3);
            AddPt(Result,0,4); AddPt(Result,1,4); AddPt(Result,2,4);
          end;
    'T' : begin
            AddPt(Result,0,0); AddPt(Result,1,0); AddPt(Result,2,0);
                                AddPt(Result,1,1);
                                AddPt(Result,1,2);
                                AddPt(Result,1,3);
                                AddPt(Result,1,4);
          end;
    'Z' : begin
            AddPt(Result,0,0); AddPt(Result,1,0); AddPt(Result,2,0);
                                                    AddPt(Result,2,1);
                                AddPt(Result,1,2);
            AddPt(Result,0,3);
            AddPt(Result,0,4); AddPt(Result,1,4); AddPt(Result,2,4);
          end;
  end;
end;

procedure Squad_ApplyFormation(FormationType: Integer);
var
  Player          : PPlayerStruct;
  PlayerMaxUnitID : Cardinal;
  CurrentUnit     : PUnitStruct;
  SelectedUnits   : array of PUnitStruct;
  i, k            : Integer;
  Count           : Integer;
  GridSize        : Integer;
  Row, Col        : Integer;
  Angle, Radius   : Double;
  CenterX, CenterZ: Int64;
  FacingRad       : Double;
  LocalX, LocalZ  : Double;
  Side            : Integer;
  WorldOffX       : Double;
  WorldOffZ       : Double;
  TargetPos       : TPosition;
  SpellWord       : String;
  LetterIdx, p, n : Integer;
  AssignCount     : Integer;
  TotalWidth      : Integer;
  AllPoints       : TGlyphPointArray;
  LetterPoints    : TGlyphPointArray;
begin
  Player := TAPlayer.GetPlayerByIndex(TAData.LocalPlayerID);
  PlayerMaxUnitID := Player.nNumUnits;

  // Gather currently selected units (same pattern as SquadGroup_Select)
  SetLength(SelectedUnits, 0);
  for i := 0 to PlayerMaxUnitID do
  begin
    CurrentUnit := Pointer(Cardinal(Player.p_UnitsArray) + Cardinal(i) * SizeOf(TUnitStruct));
    if ((CurrentUnit.lUnitStateMask and UnitSelectState[UnitSelected_State]) = UnitSelectState[UnitSelected_State]) then
    begin
      Count := Length(SelectedUnits);
      SetLength(SelectedUnits, Count + 1);
      SelectedUnits[Count] := CurrentUnit;
    end;
  end;

  Count := Length(SelectedUnits);
  if Count = 0 then
  begin
    SendTextLocal('No units selected for formation');
    Exit;
  end;

  // Center = average current position of selected units (Int64 to avoid
  // overflow summing several already-scaled fixed-point coordinates -
  // same overflow concern flagged in SquadGroup_Select's recall path).
  CenterX := 0;
  CenterZ := 0;
  for i := 0 to Count - 1 do
  begin
    Inc(CenterX, SelectedUnits[i]^.Position.X);
    Inc(CenterZ, SelectedUnits[i]^.Position.Z);
  end;
  CenterX := CenterX div Count;
  CenterZ := CenterZ div Count;

  FacingRad := (SelectedUnits[0]^.Turn.Z / 65536) * 2 * Pi;

  if FormationType = 7 then
  begin
    // ---- SPELL: lay out selected units to spell SpellWord ----
    // Only B/L/I/T/Z are defined in GetGlyphPoints right now (just enough
    // for "BLITZ"). Undefined letters silently contribute zero points.
    SpellWord := 'BLITZ';

    SetLength(AllPoints, 0);
    for LetterIdx := 1 to Length(SpellWord) do
    begin
      LetterPoints := GetGlyphPoints(SpellWord[LetterIdx]);
      for p := 0 to High(LetterPoints) do
      begin
        n := Length(AllPoints);
        SetLength(AllPoints, n + 1);
        AllPoints[n].Col := LetterPoints[p].Col + (LetterIdx - 1) * 4;  // 3-wide glyph + 1 gap column
        AllPoints[n].Row := LetterPoints[p].Row;
      end;
    end;

    TotalWidth := (Length(SpellWord) - 1) * 4 + 3;  // last glyph has no trailing gap

    AssignCount := Count;
    if Length(AllPoints) < AssignCount then
      AssignCount := Length(AllPoints);

    for i := 0 to AssignCount - 1 do
    begin
      LocalX := (AllPoints[i].Col - (TotalWidth - 1) / 2) * FormationSpacing;
      LocalZ := (AllPoints[i].Row - 2) * FormationSpacing;  // 5 rows (0..4), centered on row 2

      WorldOffX := LocalX * Cos(FacingRad) - LocalZ * Sin(FacingRad);
      WorldOffZ := LocalX * Sin(FacingRad) + LocalZ * Cos(FacingRad);

      TargetPos.X := Integer(CenterX) + Round(WorldOffX * 65536);
      TargetPos.Z := Integer(CenterZ) + Round(WorldOffZ * 65536);
      TargetPos.Y := 0;

      TAUnit.CreateMainOrder(SelectedUnits[i], nil, Action_Move_Ground, @TargetPos, 0, 0, 0);
    end;

    if AssignCount < Length(AllPoints) then
      SendTextLocal('Spelling "' + SpellWord + '" needs ' + IntToStr(Length(AllPoints)) +
        ' units for full text - only had ' + IntToStr(Count) + ', drew it partially')
    else
      SendTextLocal('Spelled "' + SpellWord + '" with ' + IntToStr(AssignCount) + ' units');

    Exit;
  end;

  for i := 0 to Count - 1 do
  begin
    case FormationType of
      1 : begin  // LINE (column) - single file, one behind another
            LocalX := 0;
            LocalZ := i * FormationSpacing;
          end;
      2 : begin  // WALL (abreast) - side by side, centered on the group
            LocalX := (i - (Count - 1) / 2) * FormationSpacing;
            LocalZ := 0;
          end;
      3 : begin  // TRIANGLE (wedge) - tip forward, alternating left/right
            k := (i + 1) div 2;
            if i = 0 then Side := 0
            else if Odd(i) then Side := 1
            else Side := -1;
            LocalX := Side * k * FormationSpacing;
            LocalZ := k * FormationSpacing;
          end;
      4 : begin  // SQUARE (grid block) - roughly equal rows/columns
            GridSize := Ceil(Sqrt(Count));
            Row := i div GridSize;
            Col := i mod GridSize;
            LocalX := (Col - (GridSize - 1) / 2) * FormationSpacing;
            LocalZ := (Row - (GridSize - 1) / 2) * FormationSpacing;
          end;
      5 : begin  // CIRCLE - evenly spaced around a ring
            // radius scales with Count so neighbour spacing along the
            // circle stays roughly FormationSpacing regardless of squad size
            Angle  := i * (2 * Pi / Count);
            Radius := (Count * FormationSpacing) / (2 * Pi);
            LocalX := Sin(Angle) * Radius;
            LocalZ := Cos(Angle) * Radius;
          end;
      6 : begin  // BLITZ - narrow spearhead: tighter and deeper than Triangle
            k := (i + 1) div 2;
            if i = 0 then Side := 0
            else if Odd(i) then Side := 1
            else Side := -1;
            LocalX := Side * k * (FormationSpacing * 0.5);  // half-width vs Triangle
            LocalZ := k * (FormationSpacing * 1.5);         // deeper - elongated arrow
          end;
    else
      Exit;  // unknown formation type - do nothing rather than guess
    end;

    // Rotate the local formation slot by the reference facing angle
    WorldOffX := LocalX * Cos(FacingRad) - LocalZ * Sin(FacingRad);
    WorldOffZ := LocalX * Sin(FacingRad) + LocalZ * Cos(FacingRad);

    TargetPos.X := Integer(CenterX) + Round(WorldOffX * 65536);
    TargetPos.Z := Integer(CenterZ) + Round(WorldOffZ * 65536);
    TargetPos.Y := 0;  // Move_Ground orders snap to ground height regardless

    TAUnit.CreateMainOrder(SelectedUnits[i], nil, Action_Move_Ground, @TargetPos, 0, 0, 0);
  end;

  SendTextLocal('Formation applied to ' + IntToStr(Count) + ' units');
end;

end.
