unit KeyboardHook;

interface
uses
  PluginEngine, Windows, Messages, SysUtils;

const
  State_KeyboardHook: Boolean = True;

function GetPlugin : TPluginData;

procedure OnInstallKeyboardHook;
procedure OnUninstallKeyboardHook;

var
  hKeyboardHook: HHook;
  keyboardHookLevel: byte;

function KeyboardHookFunction(nCode: Integer; wParam: Word; lParam: LongInt): LRESULT; stdcall;
procedure SetInGameHotkeysLevel;

procedure SwitchSetShareEnergy;
procedure UpdateSelectUnitEffect;
procedure ApplySelectUnitMenu_Wrapper;
function FindIdleFactory : Boolean;
procedure SquadGroup_Select(GroupNum: Integer);
procedure Squad_ApplyFormation(FormationType: Integer);
procedure SpawnUnitsNearSelection(const UnitName: String; Amount: Byte);

var

  SquadGroups: array[1..9] of array of Word;

  CurrentFormationCycle: Integer;

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

  SaveUnitsWeaponsList,
  UnitActions,
  UnitInfoExpand,
  CloakOnly;

const
  LastNum : Cardinal = 0;

var
  lastShareEnergyVal: single;
  Semaphore_IdleFactory : THandle;
  COBConsoleInitialized: Boolean = False;

Procedure OnInstallKeyboardHook;
begin
  keyboardHookLevel := 2;
  lastShareEnergyVal := 0;
  hKeyboardHook:= SetWindowsHookEx(WH_KEYBOARD, @KeyboardHookFunction, 0, GetCurrentThreadId);
  Semaphore_IdleFactory := CreateSemaphore(nil, 1, 1, '');

end;

Procedure OnUninstallKeyboardHook;
begin
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
        $5A : begin
                if ( ((GetAsyncKeyState(VK_MENU) and $8000) > 0) and
                     ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) ) then
                begin
                  SwitchSetShareEnergy;
                  Result := 1;
                  Exit;
                end;
              end;
        $58 : begin
                if ( ((GetAsyncKeyState(VK_MENU) and $8000) > 0) and
                     ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) ) then
                begin
                  InterpretInternalCommand(PChar('shareenergy'));
                  Result := 1;
                  Exit;
                end;
              end;
        $43 : begin
                if ( ((GetAsyncKeyState(VK_MENU) and $8000) > 0) and
                     ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) ) then
                begin
                  InterpretInternalCommand(PChar('sharemetal'));
                  Result := 1;
                  Exit;
                end;
              end;
        $41 : begin
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
        $42 : begin
                if ( ((GetAsyncKeyState(VK_MENU) and $8000) > 0) and
                     ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) ) then
                begin
                  SpawnUnitsNearSelection('armatlas', 1);
                          SpawnUnitsNearSelection('ARMFLASH', 10);

                  Result := 1;
                  Exit;
                end;
              end;
        $56 : begin
                if ( ((GetAsyncKeyState(VK_MENU) and $8000) > 0) and
                     ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) ) then
                begin
                  SpawnUnitsNearSelection('ARMARAD', 1);
                  Result := 1;
                  Exit;
                end;
              end;
        $53 : begin
                if ( ((GetAsyncKeyState(VK_MENU) and $8000) > 0) and
                     ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) ) then
                begin
                  UnitAtMouse := TAUnit.AtMouse;
                  if (UnitAtMouse <> nil) then
                    if TAUnit.IsOnThisComp(UnitAtMouse, False) then
                    begin
                      UnitAtMouse.p_MainOrder.p_NextOrder := nil;
                      UnitAtMouse.p_SubOrder := nil;
                      Result := 1;
                      Exit;
                    end;
                end;

                if ( ((GetAsyncKeyState(VK_CONTROL) and $8000) > 0) and
                     ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) ) then
                begin
                  RemoveBuildQueuesFromSelected;

                  Result := 1;
                  Exit;
                end;
              end;
        {$IFDEF Debug}
        $51 : begin
                if ( ((GetAsyncKeyState(VK_MENU) and $8000) > 0) and
                     ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) ) then
                begin
                  UnitAtMouse := TAUnit.AtMouse;
                  if (UnitAtMouse <> nil) then
                  begin
                  end;
                end;
              end;
        $72 : begin
                if ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) then
                begin
                end;
              end;
        {$ENDIF}
        $57 : begin
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
        $13 : begin
                if TAData.NetworkLayerEnabled and Assigned(GlobalDPlay) then
                  if GlobalDPlay.AutopauseAtStart and not GlobalDPlay.Players[TAData.LocalPlayerID+1].IsServer then
                  begin
                    Msg_Reminder(PAnsiChar('Only the host can unpause.' +#13#10+ 'You can also vote to go with .ready command'), 1);
                    Result := 1;
                    Exit;
                  end;
              end;
        $5D : begin
                InterpretCommand('showranges', 1);
              end;
        $46 : begin
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
              end;

        $31..$39 : begin
                if ( ((GetAsyncKeyState(VK_MENU) and $8000) > 0) and
                     ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) ) then
                begin
                  SquadGroup_Select(wParam - $30);
                  Result := 1;
                  Exit;
                end;
              end;
        $4E : begin
                if ( ((GetAsyncKeyState(VK_MENU) and $8000) > 0) and
                     ((GetAsyncKeyState(VK_SHIFT) and $8000) > 0) ) then
                begin
                  CurrentFormationCycle := (CurrentFormationCycle mod 7) + 1;
                  Squad_ApplyFormation(CurrentFormationCycle);
                  Result := 1;
                  Exit;
                end;
              end;
        end;
     end else
     begin
       if keyboardHookLevel > 0 then
       begin

       end;
     end;
     end;
  end;

  Result:= 0;
end;

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

procedure SpawnUnitsNearSelection(const UnitName: String; Amount: Byte);
var
  Player          : PPlayerStruct;
  PlayerMaxUnitID : Cardinal;
  CurrentUnit     : PUnitStruct;
  RefUnit         : PUnitStruct;
  UnitInfo        : PUnitInfo;
  CheckUnitInfo   : PUnitInfo;
  UnitsMax        : Integer;
  Spawned         : Integer;
  i               : Integer;
  PlayerIndex     : Integer;
  NewX, NewZ      : Integer;
  SpawnPos        : TPosition;
  Radius, Jiggle, Angle : Integer;
  Height          : Integer;
  ResultUnit      : Pointer;
begin
  Player := TAPlayer.GetPlayerByIndex(TAData.LocalPlayerID);
  PlayerMaxUnitID := Player.nNumUnits;

  RefUnit := nil;
  for i := 0 to PlayerMaxUnitID do
  begin
    CurrentUnit := Pointer(Cardinal(Player.p_UnitsArray) + Cardinal(i) * SizeOf(TUnitStruct));
    if ((CurrentUnit.lUnitStateMask and UnitSelectState[UnitSelected_State]) = UnitSelectState[UnitSelected_State]) then
    begin
      RefUnit := CurrentUnit;
      Break;
    end;
  end;

  if RefUnit = nil then
  begin
    SendTextLocal('Select a unit first (used as the spawn point)');
    Exit;
  end;

  UnitInfo := nil;
  UnitsMax := TAData.UnitInfosCount;
  for i := 0 to UnitsMax - 1 do
  begin
    CheckUnitInfo := TAMem.UnitInfoId2Ptr(i);
    if (CheckUnitInfo <> nil) and (UpperCase(CheckUnitInfo.szUnitName) = UpperCase(UnitName)) then
    begin
      UnitInfo := CheckUnitInfo;
      Break;
    end;
  end;

  if UnitInfo = nil then
  begin
    SendTextLocal('Unit type not found or not loaded: ' + UnitName);
    Exit;
  end;

  PlayerIndex := TAUnit.GetOwnerIndex(RefUnit);
  Radius := 60;
  Spawned := 0;
  Randomize;
  for i := 1 to Amount do
  begin
    Jiggle := Random(200);
    Angle := Random(360) + 1;
    if TAUnits.CircleCoords(RefUnit.Position, Radius + Jiggle, Angle, NewX, NewZ) then
    begin
      if GetTPosition(NewX, NewZ, SpawnPos) <> nil then
      begin
        Height := GetPosHeight(@SpawnPos);
        if Height <> -1 then
          SpawnPos.Y := Height * 65536
        else
          SpawnPos.Y := RefUnit.Position.Y;

        ResultUnit := TAUnit.CreateUnit(PlayerIndex, UnitInfo, SpawnPos, nil, False, False, 1);
        if ResultUnit <> nil then
          Inc(Spawned);
      end;
    end;
  end;

  SendTextLocal('Spawned ' + IntToStr(Spawned) + ' x ' + UnitName);
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

const
  FormationSpacing = 64;

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

    SpellWord := 'BLITZ';

    SetLength(AllPoints, 0);
    for LetterIdx := 1 to Length(SpellWord) do
    begin
      LetterPoints := GetGlyphPoints(SpellWord[LetterIdx]);
      for p := 0 to High(LetterPoints) do
      begin
        n := Length(AllPoints);
        SetLength(AllPoints, n + 1);
        AllPoints[n].Col := LetterPoints[p].Col + (LetterIdx - 1) * 4;
        AllPoints[n].Row := LetterPoints[p].Row;
      end;
    end;

    TotalWidth := (Length(SpellWord) - 1) * 4 + 3;

    AssignCount := Count;
    if Length(AllPoints) < AssignCount then
      AssignCount := Length(AllPoints);

    for i := 0 to AssignCount - 1 do
    begin
      LocalX := (AllPoints[i].Col - (TotalWidth - 1) / 2) * FormationSpacing;
      LocalZ := (AllPoints[i].Row - 2) * FormationSpacing;

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
      1 : begin
            LocalX := 0;
            LocalZ := i * FormationSpacing;
          end;
      2 : begin
            LocalX := (i - (Count - 1) / 2) * FormationSpacing;
            LocalZ := 0;
          end;
      3 : begin
            k := (i + 1) div 2;
            if i = 0 then Side := 0
            else if Odd(i) then Side := 1
            else Side := -1;
            LocalX := Side * k * FormationSpacing;
            LocalZ := k * FormationSpacing;
          end;
      4 : begin
            GridSize := Ceil(Sqrt(Count));
            Row := i div GridSize;
            Col := i mod GridSize;
            LocalX := (Col - (GridSize - 1) / 2) * FormationSpacing;
            LocalZ := (Row - (GridSize - 1) / 2) * FormationSpacing;
          end;
      5 : begin

            Angle  := i * (2 * Pi / Count);
            Radius := (Count * FormationSpacing) / (2 * Pi);
            LocalX := Sin(Angle) * Radius;
            LocalZ := Cos(Angle) * Radius;
          end;
      6 : begin
            k := (i + 1) div 2;
            if i = 0 then Side := 0
            else if Odd(i) then Side := 1
            else Side := -1;
            LocalX := Side * k * (FormationSpacing * 0.5);
            LocalZ := k * (FormationSpacing * 1.5);
          end;
    else
      Exit;
    end;

    WorldOffX := LocalX * Cos(FacingRad) - LocalZ * Sin(FacingRad);
    WorldOffZ := LocalX * Sin(FacingRad) + LocalZ * Cos(FacingRad);

    TargetPos.X := Integer(CenterX) + Round(WorldOffX * 65536);
    TargetPos.Z := Integer(CenterZ) + Round(WorldOffZ * 65536);
    TargetPos.Y := 0;

    TAUnit.CreateMainOrder(SelectedUnits[i], nil, Action_Move_Ground, @TargetPos, 0, 0, 0);
  end;

  SendTextLocal('Formation applied to ' + IntToStr(Count) + ' units');
end;

end.
