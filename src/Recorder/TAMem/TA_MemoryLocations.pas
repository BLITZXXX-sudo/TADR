unit TA_MemoryLocations;

interface
uses
  Classes, TA_MemoryStructures;

type
  TAMem = class
  protected
    class function GetShareEnergyVal: single;
    class function GetShareMetalVal: single;
    class function GetShareEnergy: Boolean;
    class function GetShareMetal: Boolean;
    class function GetShootAll: Boolean;
    class function GetSwitchesMask: Word;
    class procedure SetSwitchesMask(Mask: Word);
    class procedure SetShootAll(ANewState: Boolean);

    class Function GetLocalPlayerID: Byte;
    class Function GetViewPlayerID: Byte;
    class function GetActivePlayersCount: Byte;
    class function GetGameTime: Integer;
    class Function GetGameSpeed: Byte;
    class function GetDevMode: Boolean;
    class function GetIsNetworkLayerEnabled: Boolean;

    class Function GetMaxUnitLimit: Word;
    class Function GetActualUnitLimit: Word;
    class Function GetIsAlteredUnitLimit: Boolean;
    class function GetUnitsPtr: Pointer;
    class function GetUnits_EndMarkerPtr: Pointer;
    class function GetMaxUnitId: LongWord;
    class function GetMainStructPtr: PTADynMemStruct;
    class function GetProgramStructPtr: Pointer;
    class function GetPlayersStructPtr: Pointer;
//    class function GetModelsArrayPtr: Pointer;
    //class function GetWeaponTypeDefArrayPtr: Pointer;
    class function GetFeatureTypeDefArrayPtr: Pointer;
    class function GetFeatureAnimArrayPtr: Pointer;
    class function GetUnitInfosPtr: Pointer;
    class function GetUnitInfosCount: LongWord;
    class function GetColorsPalette: Pointer;

    class function GetGameingType: TGameingType;
    class function GetGUICallbackState: TGUICallbackState;
    class function GetGameUIRect: tagRect;
    class function GetAIDifficulty: TAIDifficulty;
    class function GetControlPlayerRaceSide: Byte;

    class Function GetPausedState: Boolean;
    class Procedure SetPausedState( value: Boolean);
  public
    property ShareEnergyVal: single read GetShareEnergyVal;
    property ShareMetalVal: single read GetShareMetalVal;
    property ShareEnergy: Boolean read GetShareEnergy;
    property ShareMetal: Boolean read GetShareMetal;
    property ShootAll: Boolean read GetShootAll write SetShootAll;
    Property SwitchesMask: Word read GetSwitchesMask write SetSwitchesMask;
    Property Paused: Boolean read GetPausedState write SetPausedState;

    property LocalPlayerID: Byte read GetLocalPlayerId;
    property ViewPlayerID: Byte read GetViewPlayerID;
    property ActivePlayersCount: Byte read GetActivePlayersCount;
    property GameTime: Integer read GetGameTime;
    Property GameSpeed: Byte read GetGameSpeed;
    Property DevMode: Boolean read GetDevMode;
    Property NetworkLayerEnabled: Boolean read GetIsNetworkLayerEnabled;
    Property MaxUnitLimit: Word read GetMaxUnitLimit;
    Property ActualUnitLimit: Word read GetActualUnitLimit;
    Property IsAlteredUnitLimit: Boolean read GetIsAlteredUnitLimit;
    Property UnitsArray_p: Pointer read GetUnitsPtr;
    Property EndOfUnitsArray_p: Pointer read GetUnits_EndMarkerPtr;
    Property MaxUnitsID: Cardinal read GetMaxUnitId;
    Property MainStruct: PTADynMemStruct read GetMainStructPtr;
    Property ProgramStructPtr: Pointer read GetProgramStructPtr;
    Property PlayersStructPtr: Pointer read GetPlayersStructPtr;
  //  Property ModelsArrayPtr: Pointer read GetModelsArrayPtr;
   // Property WeaponTypeDefArrayPtr: Pointer read GetWeaponTypeDefArrayPtr;
    Property FeatureTypeDefArrayPtr: Pointer read GetFeatureTypeDefArrayPtr;
    Property FeatureAnimArrayPtr: Pointer read GetFeatureAnimArrayPtr;
    Property UnitInfosPtr: Pointer read GetUnitInfosPtr;
    Property UnitInfosCount: LongWord read GetUnitInfosCount;

    Property GameingType: TGameingType read GetGameingType;
    Property GUICallbackState: TGUICallbackState read GetGUICallbackState;
    Property GameUIRect: tagRect read GetGameUIRect;
    Property AIDifficulty: TAIDifficulty read GetAIDifficulty;
    Property RaceSide: Byte read GetControlPlayerRaceSide;
    Property ColorsPalette: Pointer read GetColorsPalette;

    class procedure ShakeCam(X, Y, Duration: Cardinal);

    class function RaceSideId2Data(Id: Byte): PRaceSideData;
    class function ScriptActionName2Index(ActionName: String): Byte;
    class function ScriptActionIndex2Handler(ActionIndex: Byte): PActionHandler;
    //class function GetModelPtr(index: Word): Pointer;
    class function UnitInfoId2Ptr(ID: Word): PUnitInfo;
    class function UnitInfoCrc2Ptr(CRC: Integer): PUnitInfo;
    class function MovementClassId2Ptr(index: Word): Pointer;
    class function FeatureDefId2Ptr(ID: Word): PFeatureDefStruct;
    class function FeatureAnimId2Ptr(ID: Word): PFeatureAnimData;
    class function GetFeatureInfo(FeatureDef: PFeatureDefStruct; FieldType: Byte): Cardinal;
    class procedure Position2Grid(Position: TPosition; out GridPosX, GridPosZ: Word);
    class function PositionInMapArea(Position: TPosition): Boolean;
    class function DistanceBetweenPos(Pos1, Pos2: PPosition): Integer;
    class function DistanceBetweenPosCompare(Pos1, Pos2: PPosition; Range: Integer): Boolean;
    class function ProtectMemoryRegion(Address: Pointer; Writable: Boolean): Integer;
    class function IsTAVersion31: Boolean;
  end;

  TASfx = class
  public
    class procedure Speech(p_Unit: Pointer; SpeechType: Cardinal; Text: PAnsiChar);
    class function Play3DSound(EffectID: Cardinal; Position: TPosition; NetBroadcast: Boolean): Integer;
    class function PlayGafAnim(BmpType: Byte; X, Z: Word; Glow, Smoke: Byte): Integer;
    class function EmitSfxFromPiece(p_Unit: PUnitStruct; Targetp_Unit: PUnitStruct;
      PieceIdx: Integer; SfxType: Byte; Broadcast: Boolean): Cardinal;
    class function NanoParticles(StartPos: TPosition; TargetPos: TNanolathePos): Cardinal;
    class function NanoReverseParticles(StartPos: TPosition; TargetPos: TNanolathePos): Cardinal;
  end;

  TAWeapon = class
  public
    class function WeaponId2Ptr(ID: Cardinal): PWeaponDef;
    class function GetWeaponID(WeaponPtr: PWeaponDef): Cardinal;
    // TODO: FireMap_Weapon is unimplemented. The real underlying function
    // (PROJECTILES_FireMapWeap, TA_FunctionsU.pas) needs full TPosition
    // start/target structs + a broadcast flag, not (TargetX, TargetZ: Cardinal).
    // Needs a real Y/height lookup and start-position decision before this
    // can safely call into game memory -- left unimplemented rather than guessed.
    class function FireMap_Weapon(WeaponPtr: PWeaponDef;
      TargetX, TargetZ: Cardinal): Boolean;
  end;

const
  BoolValues: array [Boolean] of Byte = (0,1);

var
  TAData: TAMem;

function IsTAVersion31: Boolean;

implementation
uses
  SysUtils,

  Math,
  //IniOptions,
   //idplay,
  WeaponsExpand,
  //TAMemManipulations,
  TA_MemoryConstants,
  TA_MemPlayers,
  TA_MemUnits,
  TA_FunctionsU;

// -----------------------------------------------------------------------------

var
  // Diagnostic (2026-07-22 round 5): ARMARAD shield-ring crash investigation.
  // See the bounds-check fix in TASfx.PlayGafAnim below. Self-contained
  // append-mode logger (same pattern as GUIEnhancements.LogDiag) - kept local
  // to this unit rather than importing GUIEnhancements, to avoid introducing
  // a circular unit dependency (GUIEnhancements' implementation already uses
  // TA_MemoryLocations).
  DiagLoggedExplodeGafOutOfRange: Boolean = False;
  DiagLoggedCustAnimGafOutOfRange: Boolean = False;

procedure LogDiagOnce(var AOnceFlag: Boolean; const Msg: string);
var
  DiagLogFile: TextFile;
  DiagLogPath: string;
begin
  if AOnceFlag then Exit;
  AOnceFlag := True;
  try
    DiagLogPath := ExtractFilePath(ParamStr(0)) + 'tplayx_diag.log';
    AssignFile(DiagLogFile, DiagLogPath);
    {$I-}
    if FileExists(DiagLogPath) then
      Append(DiagLogFile)
    else
      Rewrite(DiagLogFile);
    {$I+}
    if IOResult <> 0 then Exit;
    Writeln(DiagLogFile, FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + '  ' + Msg +
      ' (further occurrences this session will not be logged)');
    CloseFile(DiagLogFile);
  except end;
end;

class function TAMem.IsTAVersion31: Boolean;
begin
  Result := True;
end;


function IsTAVersion31: Boolean;
begin
result := TAMem.IsTAVersion31();
end; {IsTAVersion31}

// -----------------------------------------------------------------------------
// TAWeapon
// -----------------------------------------------------------------------------

class function TAWeapon.WeaponId2Ptr(ID: Cardinal): PWeaponDef;
begin
  Result := nil;
  if ID < MAX_WEAPONS_PATCHED then
    Result := @WeaponsExpand.WeaponsPatchMainStruct.Weapons[ID];
end;

class function TAWeapon.GetWeaponID(WeaponPtr: PWeaponDef): Cardinal;
begin
  Result := 0;
  if WeaponPtr = nil then
    Exit;
  Result := (Cardinal(WeaponPtr) - Cardinal(@WeaponsExpand.WeaponsPatchMainStruct.Weapons[0]))
    div SizeOf(TWeaponDef);
end;

class function TAWeapon.FireMap_Weapon(WeaponPtr: PWeaponDef;
  TargetX, TargetZ: Cardinal): Boolean;
begin
  // TODO: unimplemented -- see TODO note on the class declaration above.
  Result := False;
end;

var
  CacheUsed: Boolean;
  IsTAVersion31_Cache: Boolean;

// -----------------------------------------------------------------------------
// TAMem
// -----------------------------------------------------------------------------
       function TestBytes(Address, Expected: Pointer; Len: Integer; out FailIndex: Integer; out FailValue: Byte): Boolean;
var
  i: Integer;
  pAddr, pExp: PByte;
begin
  pAddr := Address;
  pExp := Expected;
  for i := 0 to Len - 1 do
  begin
    if pAddr^ <> pExp^ then
    begin
      FailIndex := i;
      FailValue := pAddr^;
      Exit(False);
    end;
    Inc(pAddr);
    Inc(pExp);
  end;
  Result := True;
end;

Class function TAMem.GetShareEnergyVal: Single;
begin
  Result := PPlayerStruct(TAData.PlayersStructPtr).fShareLimitEnergy;
end;

Class function TAMem.GetShareMetalVal: Single;
begin
  Result := PPlayerStruct(TAData.PlayersStructPtr).fShareLimitMetal;
end;

Class function TAMem.GetShareEnergy: Boolean;
begin
  Result := PlayerState_ShareEnergy in TAData.MainStruct.PlayersExt[TAData.LocalPlayerID].PlayerInfo.SharedBits;
end;

Class function TAMem.GetShareMetal: Boolean;
begin
  Result := PlayerState_ShareMetal in TAData.MainStruct.PlayersExt[TAData.LocalPlayerID].PlayerInfo.SharedBits;
end;

Class function TAMem.GetShootAll: Boolean;
begin
  Result := ((TAData.SwitchesMask and SwitchesMasks[SwitchesMask_ShootAll]) =
    SwitchesMasks[SwitchesMask_ShootAll]);
end;

Class procedure TAMem.SetShootAll(ANewState: Boolean);
begin
  if ANewState then
    TAData.SwitchesMask := TAData.SwitchesMask or SwitchesMasks[SwitchesMask_ShootAll]
  else
    TAData.SwitchesMask := TAData.SwitchesMask and not SwitchesMasks[SwitchesMask_ShootAll];
end;

class Function TAMem.GetLocalPlayerId: Byte;
begin
  Result := TAData.MainStruct.cControlPlayerID;
end;

class Function TAMem.GetViewPlayerID: Byte;
begin
  Result := TAData.MainStruct.cViewPlayerID;
end;

class Function TAMem.GetActivePlayersCount: Byte;
begin
  Result := Byte(TAData.MainStruct.nActivePlayersCount);
end;

class Function TAMem.GetGameTime: Integer;
begin
  Result := TAData.MainStruct.lGameTime;
end;

class Function TAMem.GetGameSpeed: Byte;
begin
  Result := TAData.MainStruct.nTAGameSpeed;
end;

class Function TAMem.GetDevMode: Boolean;
begin
  Result := (TAData.MainStruct.nGameState and 2) = 2;
end;

class function TAMem.GetIsNetworkLayerEnabled: Boolean;
begin
  //Result := (GlobalDPlay <> nil) and ((TAData.MainStruct.cNetworkLayerEnabled and 1) = 1);
end;

class function TAMem.GetMaxUnitLimit: Word;
begin
  Result := TAData.MainStruct.nMaxUnitLimitPerPlayer;
end;

class function TAMem.GetActualUnitLimit: Word;
begin
  Result := TAData.MainStruct.nPerMissionUnitLimit;
end;

class function TAMem.GetIsAlteredUnitLimit: Boolean;
begin
  Result := TAData.MainStruct.cAlteredUnitLimit <> 0;
end;

class function TAMem.GetUnitsPtr: Pointer;
begin
  Result := TAData.MainStruct.p_Units;
end;

class function TAMem.GetUnits_EndMarkerPtr: Pointer;
begin
  Result := TAData.MainStruct.p_LastUnitInArray;
end;

class function TAMem.GetMainStructPtr: PTADynMemStruct;
begin
  Result := Pointer(PCardinal(TADynmemStructPtr)^);
end;

class function TAMem.GetProgramStructPtr: Pointer;
begin
  Result := TAData.MainStruct.p_TAProgram;
end;

class function TAMem.GetPlayersStructPtr: Pointer;
begin
  Result := @TAData.MainStruct.PlayersExt[0];
end;

class function TAMem.GetFeatureTypeDefArrayPtr: Pointer;
begin
  Result := TAData.MainStruct.TNTMemStruct.p_FeatureDefs;
end;

class function TAMem.GetFeatureAnimArrayPtr: Pointer;
begin
  Result := TAData.MainStruct.TNTMemStruct.p_FeatureAnimData;
end;

class function TAMem.GetUnitInfosPtr: Pointer;
begin
  Result := TAData.MainStruct.p_UNITINFOs;
end;

class function TAMem.GetUnitInfosCount: LongWord;
begin
  Result := TAData.MainStruct.lNumUnitTypeDefs;
end;

class function TAMem.GetColorsPalette: Pointer;
begin
  Result := Pointer(Cardinal(TAData.MainStruct)+$DCB);
end;

class function TAMem.GetSwitchesMask: Word;
begin
  Result := TAData.MainStruct.nSwitchesMask;
end;

class procedure TAMem.SetSwitchesMask(Mask: Word);
begin
  TAData.MainStruct.nSwitchesMask := Mask;
end;

class Function TAMem.GetPausedState: Boolean;
begin
  Result := TAData.MainStruct.cIsGamePaused <> 0;
end;

class Procedure TAMem.SetPausedState( value: Boolean);
begin
  TAData.MainStruct.cIsGamePaused := BoolValues[value];
end;


class function TAMem.UnitInfoId2Ptr(ID: Word): PUnitInfo;
begin
  Result := Pointer(Cardinal(TAData.UnitInfosPtr) + ID * SizeOf(TUnitInfo));
end;

class function TAMem.UnitInfoCrc2Ptr(CRC: Integer): PUnitInfo;
var
  i, Max: Integer;
  CheckedUnitInfo: PUnitInfo;
begin
  Result := nil;
  if CRC = 0 then
    Exit;
  Max := TAData.UnitInfosCount;
  for i := 0 to Max-1 do
  begin
    CheckedUnitInfo := TAMem.UnitInfoId2Ptr(i);
    if CheckedUnitInfo <> nil then
    begin
      if CheckedUnitInfo.CRC_FBI = CRC then
      begin
        Result := CheckedUnitInfo;
        Break;
      end;
    end;
  end;
end;

class function TAMem.MovementClassId2Ptr(index: Word): Pointer;
begin
  Result := Pointer(TAMovementClassArray + SizeOf(TMoveInfoClassStruct) * index);
end;

class function TAMem.FeatureDefId2Ptr(ID: Word): PFeatureDefStruct;
begin
  Result := Pointer(Cardinal(TAData.FeatureTypeDefArrayPtr) + SizeOf(TFeatureDefStruct) * ID);
end;

class function TAMem.FeatureAnimId2Ptr(ID: Word): PFeatureAnimData;
begin
  Result := Pointer(Cardinal(TAData.FeatureAnimArrayPtr) + SizeOf(TFeatureAnimData) * ID);
end;

class function TAMem.GetMaxUnitId: LongWord;
begin
  if TAData.GameingType = gtMenu then
    Result := TAData.MaxUnitLimit * MAXPLAYERCOUNT
  else
    Result := TAData.ActualUnitLimit * MAXPLAYERCOUNT;
end;

class function TAMem.GetFeatureInfo(FeatureDef: PFeatureDefStruct; FieldType: Byte): Cardinal;
begin
  Result := 0;
  if FeatureDef = nil then Exit;
  if FieldType <= Integer(fiNoDrawUnderGray) then
  begin
    if (FeatureDef.nMask and FeatureMaskArr[TFeatureMaskInfo(FieldType)]) = FeatureMaskArr[TFeatureMaskInfo(FieldType)] then
      Result := 1;
  end else
  begin
    case TFeatureInfo(FieldType) of
      fiFootPrintX: Result := FeatureDef.nFootPrintX;
      fiFootPrintZ: Result := FeatureDef.nFootPrintZ;
      fiHeight: Result := FeatureDef.ucHeight;
      fiDamage: Result := FeatureDef.nDamage;
      fiMetal: Result := Trunc(FeatureDef.fMetal);
      fiEnergy: Result := Trunc(FeatureDef.fEnergy);
      fiIsWreckage: if Pos('_', FeatureDef.Name) <> 0 then Result := 1;
    end;
  end;
end;

class procedure TAMem.Position2Grid(Position: TPosition; out GridPosX, GridPosZ: Word);
begin
  GridPosX := Word(Position.X div $100000);
  GridPosZ := Word(Position.Z div $100000);
end;

class function TAMem.PositionInMapArea(Position: TPosition): Boolean;
var
  GridPosX, GridPosZ: Word;
  TNTMemStruct: PTNTMemStruct;
begin
  Position.X := -1;
  TAMem.Position2Grid(Position, GridPosX, GridPosZ);
  TNTMemStruct := @TAData.MainStruct.TNTMemStruct;
  Result := not ((GridPosX < 1) or (GridPosZ < 1) or (GridPosX >= TNTMemStruct.lTilesetMapSizeX) or
   (GridPosZ >= TNTMemStruct.lTilesetMapSizeY));
end;

class function TAMem.DistanceBetweenPos(Pos1, Pos2: PPosition): Integer;
var
  x: Int64;
  z: Int64;
begin
  Result := 0;
  if (Pos1 <> nil) and (Pos2 <> nil) then
  begin
    x := Abs(Pos1.X - Pos2.X) div 65536;
    z := Abs(Pos1.Z - Pos2.Z) div 65536;
    Result := Round(Hypot(x, z));
  end;
end;

class function TAMem.DistanceBetweenPosCompare(Pos1, Pos2: PPosition;
  Range: Integer): Boolean;
var
  xDiff: Int64;
  zDiff: Int64;
  lRange: Int64;
begin
  xDiff := Pos1.X - Pos2.X;
  zDiff := Pos1.Z - Pos2.Z;
  lRange := Range * Range;
  Result := (((xDiff * xDiff) shr 32) + ((zDiff * zDiff) shr 32)) <= lRange;
end;

class function TAMem.RaceSideId2Data(Id: Byte): PRaceSideData;
begin
  Result := nil;
  if Id <= 4 then
    Result := @TAData.MainStruct.RaceSideData[Id];
end;

class function TAMem.ScriptActionName2Index(ActionName: String): Byte;
begin
  ScriptAction_Name2Index(nil, nil, @Result, PAnsiChar(ActionName));
end;

class function TAMem.ScriptActionIndex2Handler(ActionIndex: Byte): PActionHandler;
begin
  Result := ScriptAction_Index2Handler(nil, nil, @ActionIndex);
end;

class function TAMem.GetGameingType: TGameingType;
begin
  Result := gtMenu;
  if TAData.MainStruct.p_MapOTAFile <> nil then
    Result := TGameingType(PMapOTAFile(TAData.MainStruct.p_MapOTAFile).MissionType);
end;

class function TAMem.GetGUICallbackState: TGUICallbackState;
begin
  Result := TGUICallbackState(TAData.MainStruct.lGUICallbackState);
end;

class function TAMem.GetGameUIRect: tagRect;
begin
  Result := TAData.MainStruct.GameUI_Rect;
end;

class function TAMem.GetAIDifficulty: TAIDifficulty;
begin
  Result := TAIDifficulty(TAData.MainStruct.lCurrenTAIProfile);
end;


class function TAMem.GetControlPlayerRaceSide: Byte;
var
  LocalID: Byte;
begin
  Result := 0; // Safe default
  LocalID := TAData.LocalPlayerID;

  // Directly bounds-check the array index against MAXPLAYERCOUNT safely
  if (LocalID < 10) then
  begin
    Result := TAData.MainStruct.PlayersExt[LocalID].PlayerInfo.Raceside;
  end;
end;



class procedure TAMem.ShakeCam(X, Y, Duration: Cardinal);
begin
  TAData.MainStruct.field_1432F :=
    (TAData.MainStruct.field_1432F + Duration) div 2;
  TAData.MainStruct.field_14333 := Duration;
  if ( X <> 0 ) then
    TAData.MainStruct.ShakeMagnitude_1 :=
      TAData.MainStruct.ShakeMagnitude_1 + X;
  if ( Y <> 0 ) then
    TAData.MainStruct.ShakeMagnitude_2 :=
      TAData.MainStruct.ShakeMagnitude_2 + Y;
  if ( TAData.MainStruct.field_1432F > 0 ) then
    TAData.MainStruct.cShake := TAData.MainStruct.cShake or 1;
end;

class function TAMem.ProtectMemoryRegion(Address: Pointer; Writable: Boolean): Integer;
begin
  if Writable then
    Result := MEM_AllowReadWrite(Cardinal(Address))
  else
    Result := MEM_SetReadOnly(Cardinal(Address));
end;

{ TASfx }

class procedure TASfx.Speech(p_Unit: Pointer; SpeechType: Cardinal; Text: PAnsiChar);
begin
  PlaySound_UnitSpeech(p_Unit, SpeechType, Text);
end;

class function TASfx.Play3DSound(EffectID: Cardinal; Position: TPosition; NetBroadcast: Boolean): Integer;
begin
  Result := PlaySound_3D_ID(EffectID, @Position, BoolValues[NetBroadcast]);
end;

class function TASfx.PlayGafAnim(BmpType: Byte; X, Z: Word; Glow, Smoke: Byte): Integer;
var
  Position: TPosition;
  GlowInt, SmokeInt: Integer;
begin
  result := 0;
  GetTPosition(X, Z, Position);

  if Glow = 0 then
    GlowInt := -1
  else
    GlowInt := Glow - 1;

  if Smoke = 0 then
    SmokeInt := -1
  else
    SmokeInt := Smoke - 1;

  case BmpType of
        0: ShowExplodeGaf(@Position, TAData.MainStruct.explosion, GlowInt, SmokeInt); //explosion
        1: ShowExplodeGaf(@Position, TAData.MainStruct.explode2, GlowInt, SmokeInt); //explode2
        2: ShowExplodeGaf(@Position, TAData.MainStruct.explode3, GlowInt, SmokeInt); //explode3
        3: ShowExplodeGaf(@Position, TAData.MainStruct.explode4, GlowInt, SmokeInt); //explode4
        4: ShowExplodeGaf(@Position, TAData.MainStruct.explode5, GlowInt, SmokeInt); //explode5
        5: ShowExplodeGaf(@Position, TAData.MainStruct.nuke1, GlowInt, SmokeInt); //nuke1
    6..99 :
      begin
        // Bounds fix (2026-07-22): this only checked the array was non-empty,
        // not that (BmpType-6) was actually a valid index into it. Any COB
        // script anywhere in the mod calling PLAY_GAF_ANIM with a BmpType
        // that doesn't correspond to a real ExplodeN entry in this install's
        // customfx.gaf silently indexed a dynamic array out of range (no
        // range checking in a release build) - the resulting garbage pointer
        // gets passed straight into the native GAF blit, which is exactly
        // the "illegal write to a wild address" access-violation shape seen
        // in ErrorLog.txt right after custom GAF anims started actually
        // loading for the first time (ARMARAD shield-ring investigation).
        if (BmpType - 6 >= 0) and (BmpType - 6 <= High(ExtraGAFAnimations.Explode)) then
          ShowExplodeGaf(@Position, ExtraGAFAnimations.Explode[BmpType - 6], GlowInt, SmokeInt)
        else
          LogDiagOnce(DiagLoggedExplodeGafOutOfRange,
            Format('PlayGafAnim: BmpType=%d (Explode index %d) out of range, High(Explode)=%d - skipped instead of indexing out of bounds',
              [BmpType, BmpType - 6, High(ExtraGAFAnimations.Explode)]));
      end;
 100..199 :
      begin
        // Same bounds fix as above, for the CustAnim range. ARMARAD's own
        // Go()/Stop() only ever use 100-103 (CustAnim1-4), which are in
        // range for a 5-entry customfx.gaf, but any OTHER unit's COB script
        // in this mod calling PLAY_GAF_ANIM(105+, ...) against a customfx.gaf
        // that doesn't have that many CustAnimN entries would hit exactly
        // this same out-of-bounds write.
        if (BmpType - 100 >= 0) and (BmpType - 100 <= High(ExtraGAFAnimations.CustAnim)) then
          ShowExplodeGaf(@Position, ExtraGAFAnimations.CustAnim[BmpType - 100], GlowInt, SmokeInt)
        else
          LogDiagOnce(DiagLoggedCustAnimGafOutOfRange,
            Format('PlayGafAnim: BmpType=%d (CustAnim index %d) out of range, High(CustAnim)=%d - skipped instead of indexing out of bounds',
              [BmpType, BmpType - 100, High(ExtraGAFAnimations.CustAnim)]));
      end;
  end;
end;

class function TASfx.EmitSfxFromPiece(p_Unit: PUnitStruct; Targetp_Unit: PUnitStruct;
  PieceIdx: Integer; SfxType: Byte; Broadcast: Boolean): Cardinal;
var
  PiecePos: TPosition;
  TargetBase: TPosition;
  TargetNanoBase: TNanolathePos;
  BuildingUnitInfo: PUnitInfo;
begin
  Result := 0;
  BuildingUnitInfo := Targetp_Unit.p_UNITINFO;
  GetPiecePosition(PiecePos, p_Unit, PieceIdx);
  GetPiecePosition(TargetBase, Targetp_Unit, 0);

  TargetNanoBase.Pos1.X := Targetp_Unit.Position.X + BuildingUnitInfo.lModelWidthX;
  TargetNanoBase.Pos1.Y := Targetp_Unit.Position.Y + BuildingUnitInfo.lModelWidthY;
  TargetNanoBase.Pos1.Z := Targetp_Unit.Position.Z + BuildingUnitInfo.lModelHeight;

  TargetNanoBase.Pos2.X := Targetp_Unit.Position.X + BuildingUnitInfo.lFootPrintX;
  TargetNanoBase.Pos2.Y := Targetp_Unit.Position.Y + BuildingUnitInfo.lFootPrintY;
  TargetNanoBase.Pos2.Z := Targetp_Unit.Position.Z + BuildingUnitInfo.lFootPrintZ;

  case SfxType of
    6: Result := EmitSfx_NanoParticles(@PiecePos, @TargetNanoBase, 6);
    7: Result := EmitSfx_NanoParticlesReverse(@TargetNanoBase, @PiecePos, 6);
    8: Result := EmitSfx_Teleport(@PiecePos, @TargetBase, 30, 5);
  end;

  //if IniSettings.BroadcastNanolathe then
 // begin
   // if Broadcast and TAData.NetworkLayerEnabled then
     // GlobalDPlay.Broadcast_EmitSFXToUnit(TAUnit.GetID(p_Unit), TAUnit.GetID(Targetp_Unit), PieceIdx, SfxType);
  //end;
end;

class function TASfx.NanoParticles(StartPos: TPosition; TargetPos: TNanolathePos): Cardinal;
begin
  Result := EmitSfx_NanoParticles(@StartPos, @TargetPos, 6);
end;

class function TASfx.NanoReverseParticles(StartPos: TPosition;
  TargetPos: TNanolathePos): Cardinal;
begin
  Result := EmitSfx_NanoParticlesReverse(@TargetPos, @StartPos, 6);
end;

initialization
  // In Delphi, calling class methods through a nil class variable works because
  // class method dispatch goes through the VMT of the class type, not the instance.
  // FPC however dereferences the class variable to find the VMT, so a nil TAData
  // crashes every TAData.Xxx call. Assigning a real instance fixes all of these.
  TAData := TAMem.Create;
end.
