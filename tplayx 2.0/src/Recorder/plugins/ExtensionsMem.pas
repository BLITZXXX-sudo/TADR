unit ExtensionsMem;

interface
uses
  PluginEngine, TA_MemoryStructures;

const
  State_ExtensionsMem: Boolean = True;

function GetPlugin: TPluginData;

Procedure OnInstallExtensionsMem;
Procedure OnUninstallExtensionsMem;

procedure FreeUnitMem(p_Unit: PUnitStruct);

implementation
uses
  SysUtils,
  UnitInfoExpand,
  COB_Extensions,
  TA_MemoryConstants,
  TA_MemoryLocations,
  TA_FunctionsU,
  IniOptions;

procedure ExtensionsFreeMemory; stdcall;
var
  i: Integer;
begin
  MouseLock := False;

  for i := Low(UnitsCustomFields) to High(UnitsCustomFields) do
    if UnitsCustomFields[i].UnitInfo <> nil then
    begin
      MEM_Free(UnitsCustomFields[i].UnitInfo);
      UnitsCustomFields[i].UnitInfo := nil;
    end;

  if not UnitsCustomFieldsDynArr.IsVoid then
    UnitsCustomFieldsDynArr.Clear;
  if not UnitSearchResults.IsVoid then
    UnitSearchResults.Clear;
  if not SpawnedMinions.IsVoid then
    SpawnedMinions.Clear;

  if MapMissionsUnit.p_UnitScriptsData <> nil then
  begin
    UNITS_KillUnit(@MapMissionsUnit, 8);
    FreeUnitMem(@MapMissionsUnit);
  end;

  if MapMissionsSounds <> nil then
    FreeAndNil(MapMissionsSounds);
  if MapMissionsFeatures <> nil then
    FreeAndNil(MapMissionsFeatures);
  if MapMissionsUnitsInitialMissions <> nil then
    FreeAndNil(MapMissionsUnitsInitialMissions);
  if MapMissionsTextMessages <> nil then
    FreeAndNil(MapMissionsTextMessages);

  FillChar(MapMissionsUnit, SizeOf(TUnitStruct), 0);
  FillChar(NanoSpotUnitSt, SizeOf(TUnitStruct), 0);
  FillChar(NanoSpotQueueUnitSt, SizeOf(TUnitStruct), 0);
  FillChar(NanoSpotUnitInfoSt, SizeOf(TUnitInfo), 0);
  FillChar(NanoSpotQueueUnitInfoSt, SizeOf(TUnitInfo), 0);
  FillChar(UnitsSharedData, SizeOf(UnitsSharedData), 0);
end;

procedure FreeExtensionsMemory;
asm
  pushAD
  call    ExtensionsFreeMemory
  popAD
  mov     eax, [TAdynMemStructPtr]
  push    $00496B1A
  call    PatchNJump;
end;

procedure FreeExtensionsMemory2;
asm
  pushAD
  call    ExtensionsFreeMemory
  popAD
  mov     edx, [TAdynMemStructPtr]
  push    $00491BBE
  call    PatchNJump;
end;

procedure InitExtensionsArrays; stdcall;
begin
  ExtensionsFreeMemory;
  UnitsCustomFieldsDynArr.Init(TypeInfo(TUnitsCustomFields), UnitsCustomFields, @UnitsCustomFieldsCount);
  UnitsCustomFieldsDynArr.Capacity := 1 + (IniSettings.UnitLimit * MAXPLAYERCOUNT);

  UnitSearchResults.Init(TypeInfo(TUnitSearchArr), UnitSearchArr, @UnitSearchCount);
  SpawnedMinions.Init(TypeInfo(TSpawnedMinionsArr), SpawnedMinionsArr, @SpawnedMinionsCount);

  SetLength(UnitSearchArr, High(Word));
  UnitSearchCount := High(Word);
  SetLength(SpawnedMinionsArr, High(Word));
  SpawnedMinionsCount := High(Word);
end;

procedure InitExtensionsMemory;
asm
  pushAD
  call InitExtensionsArrays
  popAD
  mov     eax, [TADynMemStructPtr]
  push $004971B8
  call PatchNJump
end;

procedure FreeUnitMem(p_Unit: PUnitStruct);
begin
  p_Unit.nKills := 0;
  p_Unit.ucOwningPlayerID := 10;
  p_Unit.p_Attacker := nil;
  p_Unit.lUnitStateMask := p_Unit.lUnitStateMask or $40;
  FreeUnitOrders(p_Unit);
  if p_Unit.p_UnitScriptsData <> nil then
  begin
    FreeUnitScriptData(nil, nil, p_Unit.p_UnitScriptsData, 1);
    p_Unit.p_UnitScriptsData := nil;
  end;
  if p_Unit.p_Object3DO <> nil then
  begin
    FreeObjectState(p_Unit.p_Object3DO);
    p_Unit.p_Object3DO := nil;
  end;
  if p_Unit.p_MovementClass <> nil then
  begin
    FreeMoveClass(p_Unit.p_Object3DO, nil, p_Unit.p_MovementClass);
    MEM_Free(p_Unit.p_MovementClass);
    p_Unit.p_MovementClass := nil;
  end;
  p_Unit.nUnitInfoID := 0;
  FillChar(p_Unit^, SizeOf(TUnitStruct), 0);
end;

procedure LoadFonts; stdcall;
var
  Buffer: String[255];
  tmp: Pointer;
  MainStructPtr: PTADynMemStruct;
begin

  MainStructPtr := PTADynMemStruct(PCardinal(TAdynmemStructPtr)^);
  if MainStructPtr = nil then
    Exit;

  GetLocalizedFilePath(@Buffer[1], PAnsiChar('fonts'), PAnsiChar('COMIX'), PAnsiChar('FNT'));
  tmp := HAPIFILE_ReadFile(PAnsiChar(@Buffer[1]), 0);
  if tmp = nil then
    TerminateProcess_WithWarning(PAnsiChar(PAnsiChar(@Buffer[1])));
  MainStructPtr.p_Font_COMIX := tmp;

  GetLocalizedFilePath(@Buffer[1], PAnsiChar('fonts'), PAnsiChar('smlfont'), PAnsiChar('FNT'));
  tmp := HAPIFILE_ReadFile(PAnsiChar(@Buffer[1]), 0);
  if tmp = nil then
    TerminateProcess_WithWarning(PAnsiChar(PAnsiChar(@Buffer[1])));
  MainStructPtr.p_Font_SMLFONT := tmp;

end;

Procedure OnInstallExtensionsMem;
begin
end;

Procedure OnUninstallExtensionsMem;
begin
end;

function GetPlugin : TPluginData;
begin
  if IsTAVersion31 and State_ExtensionsMem then
  begin
    Result := TPluginData.Create( True,
                                  '',
                                  State_ExtensionsMem,
                                  @OnInstallExtensionsMem,
                                  @OnUnInstallExtensionsMem );

    Result.MakeRelativeJmp( State_ExtensionsMem,
                            'Init extensions search arrays, units custom fields etc.',
                            @InitExtensionsMemory,
                            $004971B3, 0 );

    Result.MakeRelativeJmp( State_ExtensionsMem,
                            '',
                            @FreeExtensionsMemory,
                            $00496B15, 0 );

    Result.MakeRelativeJmp( State_ExtensionsMem,
                            '',
                            @FreeExtensionsMemory2,
                            $00491BB8, 0 );

    Result.MakeStaticCall( State_ExtensionsMem,
                           'Load more fonts',
                           @LoadFonts,
                           $00491373 );

  end else
    Result := nil;
end;

end.
