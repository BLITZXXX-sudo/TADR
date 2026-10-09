unit SaveGame;

interface
uses
  PluginEngine,
  Classes,
  TA_MemoryStructures;

type
  TScriptSlotsSaveGameRec = packed record
    lCOBFileNode : Cardinal;
    SlotsData : array[0..63] of TScriptSlot;
    lStartRunningNow : Cardinal;
  end;

const
  State_SaveGame : boolean = true;

function GetPlugin : TPluginData;

Procedure OnInstallSaveGame;
Procedure OnUninstallSaveGame;

procedure SaveGame_SaveUnitScriptSlots;
procedure SaveGame_LoadUnitScriptSlots_1;
procedure SaveGame_LoadUnitScriptSlots_2;
procedure SaveGame_SaveAdditionHook;
procedure SaveGame_LoadAdditionHook;
procedure SaveGame_LoadNoScriptsFix;

implementation
uses
  SysUtils,
  IniOptions,
  TA_MemoryConstants,
  TA_MemoryLocations,
  TA_FunctionsU,
  ExtensionsMem,
  MaxScriptSlots,
  COB_Extensions;

{ -----------------------------------------------------------------------
  BUGFIX (crash: Access Violation, illegal read 0x00000002, inside
  SynCommons RecordSaveLength / RecordEquals while saving a single-player
  game).

  Root cause: UnitSearchArr / SpawnedMinionsArr are "array of TStoreUnitsRec",
  and TStoreUnitsRec itself contains a nested dynamic array field
  (UnitIds: array of LongWord). SynCommons' generic FPC-RTTI based
  TDynArray.SaveToStream/LoadFromStream (which call RecordSaveLength /
  RecordSave internally) cannot reliably walk this "array of record
  containing a dynamic array" shape under this FPC/mORMot combination,
  and reads through a bogus small pointer, causing the AV.

  Fix: serialize these two arrays manually with plain stream reads/writes,
  bypassing SynCommons' RTTI record walker entirely. This keeps the
  feature working (unit-search results / spawned-minions tracking survive
  a save/load) without touching the buggy generic path.
  ----------------------------------------------------------------------- }

procedure SaveStoreUnitsArrManual(const Arr: TUnitSearchArr; Count: Integer; Stream: TMemoryStream);
var
  i, j, n : Integer;
begin
  n := Count;
  if n > Length(Arr) then n := Length(Arr);
  if n < 0 then n := 0;
  Stream.WriteBuffer(n, SizeOf(n));
  for i := 0 to n - 1 do
  begin
    Stream.WriteBuffer(Arr[i].Id, SizeOf(Arr[i].Id));
    j := Length(Arr[i].UnitIds);
    Stream.WriteBuffer(j, SizeOf(j));
    if j > 0 then
      Stream.WriteBuffer(Arr[i].UnitIds[0], j * SizeOf(LongWord));
  end;
end;

procedure LoadStoreUnitsArrManual(var Arr: TUnitSearchArr; var Count: Integer; Stream: TMemoryStream);
var
  i, j, n : Integer;
begin
  n := 0;
  Stream.ReadBuffer(n, SizeOf(n));
  if (n < 0) or (n > 200000) then Exit; // sanity guard against a corrupt/foreign stream
  if Length(Arr) < n then
    SetLength(Arr, n);
  for i := 0 to n - 1 do
  begin
    Stream.ReadBuffer(Arr[i].Id, SizeOf(Arr[i].Id));
    j := 0;
    Stream.ReadBuffer(j, SizeOf(j));
    if (j < 0) or (j > 1000000) then Exit; // sanity guard
    SetLength(Arr[i].UnitIds, j);
    if j > 0 then
      Stream.ReadBuffer(Arr[i].UnitIds[0], j * SizeOf(LongWord));
  end;
  Count := n;
end;

Procedure OnInstallSaveGame;
begin
end;

Procedure OnUninstallSaveGame;
begin
end;

function GetPlugin : TPluginData;
var
  lReplacement : Cardinal;
begin
  if IsTAVersion31 and State_SaveGame then
  begin
    Result := TPluginData.create( False, 'SaveGame Plugin',
                                  State_SaveGame,
                                  @OnInstallSaveGame,
                                  @OnUninstallSaveGame );

    Result.MakeRelativeJmp( State_SaveGame,
                            'Save TADR structures to SAV file',
                            @SaveGame_SaveAdditionHook,
                            $00432A38, 0 );

    Result.MakeRelativeJmp( State_SaveGame,
                            'Load TADR structures from SAV file',
                            @SaveGame_LoadAdditionHook,
                            $0043267D, 1 );

    if IniSettings.ScriptSlotsLimit and
       (IniSettings.ModId > 1) then
    begin
      lReplacement := $00002908;
      Result.MakeReplacement( State_SaveGame,
                              'load game struct size fix',
                              $004B207A, lReplacement, SizeOf(lReplacement));

      Result.MakeRelativeJmp( State_SaveGame,
                              '',
                              @SaveGame_SaveUnitScriptSlots,
                              $004B1EDA, 1 );

      Result.MakeRelativeJmp( State_SaveGame,
                              '',
                              @SaveGame_LoadUnitScriptSlots_1,
                              $004B209A, 4 );

      Result.MakeRelativeJmp( State_SaveGame,
                              '',
                              @SaveGame_LoadUnitScriptSlots_2,
                              $004B20C1, 2 );

      Result.MakeReplacement( State_SaveGame,
                              'load game struct size fix 3',
                              $004B20AC, lReplacement, SizeOf(lReplacement));
    end;
  end else
    Result := nil;
end;

var
  ScriptSlotsSaveGameRec : TScriptSlotsSaveGameRec;
procedure SaveUnitScriptSlots(ScriptData: PNewScriptsData); stdcall;
var
  lSlotIdx : Integer;
  MaxSlots : Byte;
begin
  FillChar(ScriptSlotsSaveGameRec, SizeOf(ScriptSlotsSaveGameRec), 0);
  ScriptSlotsSaveGameRec.lCOBFileNode := Cardinal(ScriptData.pCOBFileNode);
  if IniSettings.ScriptSlotsLimit then
    MaxSlots := MAX_SCRIPT_SLOTS
  else
    MaxSlots := 8;

  for lSlotIdx := 0 to MaxSlots - 1 do
  begin
    ScriptSlotsSaveGameRec.SlotsData[lSlotIdx] := ScriptData.ScriptSlots[lSlotIdx];
  end;
  ScriptSlotsSaveGameRec.lStartRunningNow := ScriptData.lStartRunningNow;
end;

procedure SaveGame_SaveUnitScriptSlots;
asm
  push    ebx
  push    edx
  push    ecx

  push    ebx
  call    SaveUnitScriptSlots

  pop     ecx
  pop     edx
  pop     ebx

  mov     esi, [esp+5B0h]
  xor     ebp, ebp
  push    type TScriptSlotsSaveGameRec
  lea     eax, ScriptSlotsSaveGameRec
  push    eax
  mov     ecx, esi

  push $004B1F36
  Call PatchNJump;
end;

procedure SaveGame_LoadUnitScriptSlots_1;
asm
  lea     edx, ScriptSlotsSaveGameRec
  push    type TScriptSlotsSaveGameRec
  push    edx
  mov     ecx, ebp
  push $004B20A6
  Call PatchNJump;
end;

procedure LoadUnitScriptSlots(ScriptData: PNewScriptsData); stdcall;
var
  lSlotIdx : Integer;
  MaxSlots : Byte;
begin
  ScriptData.pCOBFileNode := Pointer(ScriptSlotsSaveGameRec.lCOBFileNode);
  if IniSettings.ScriptSlotsLimit then
    MaxSlots := MAX_SCRIPT_SLOTS
  else
    MaxSlots := 8;

  for lSlotIdx := 0 to MaxSlots - 1 do
  begin
    ScriptData.ScriptSlots[lSlotIdx] := ScriptSlotsSaveGameRec.SlotsData[lSlotIdx];
  end;
  ScriptData.lStartRunningNow := ScriptSlotsSaveGameRec.lStartRunningNow;
  FillChar(ScriptSlotsSaveGameRec, SizeOf(ScriptSlotsSaveGameRec), 0);
end;

procedure SaveGame_LoadUnitScriptSlots_2;
label
  ContinueParse;
asm
  mov     eax, [ebx+TNewScriptsData.pCOBFileNode]
  mov     ecx, ScriptSlotsSaveGameRec.lCOBFileNode
  cmp     eax, ecx
  jz      ContinueParse
  push $004B20CC
  call PatchNJump;
ContinueParse :
pushAD
  push    ebx
  call    LoadUnitScriptSlots
popAD
  mov     esi, [esp+10h]
  mov     edx, [ebx+10h]
  mov     ebp, [esp+54Ch]

  push $004B2122
  call PatchNJump;
end;

procedure SaveGame_SaveAddition(HAPIBANK: Pointer); stdcall;
var
  Stream: TMemoryStream;
begin
  if TAData.GUICallbackState = gsPlaying then
  begin
    HAPIBANK_OpenAccount(nil, nil, HAPIBANK, PAnsiChar('TADR Extensions'));
    HAPIBANK_AccessSafeDeposit(nil, nil, HAPIBANK, PAnsiChar('UnitsSharedData'));
    HAPIBANK_WriteBinData(nil, nil, HAPIBANK, 1024, @UnitsSharedData[0]);

    if not UnitSearchResults.IsVoid then
    begin
      Stream := TMemoryStream.Create;
      try
        try
          // BUGFIX: was UnitSearchResults.SaveToStream(Stream) - that went through
          // SynCommons' generic RTTI record walker (RecordSaveLength) which crashes
          // (AV reading address 0x2) on this "array of record-with-nested-dynamic-
          // array" shape. Serialize it by hand instead.
          SaveStoreUnitsArrManual(UnitSearchArr, UnitSearchCount, Stream);
          Stream.Position := 0;
          HAPIBANK_AccessSafeDeposit(nil, nil, HAPIBANK, PAnsiChar('UnitSearch')) ;
          HAPIBANK_WriteBinData(nil, nil, HAPIBANK, Stream.Size, Stream.Memory);
        except
          on E: Exception do ; // swallow: do not let custom-data serialization crash the game save
        end;
      finally
        Stream.Free;
      end;
    end;

    if not SpawnedMinions.IsVoid then
    begin
      Stream := TMemoryStream.Create;
      try
        try
          // BUGFIX: was SpawnedMinions.SaveToStream(Stream) - same crash as above.
          SaveStoreUnitsArrManual(SpawnedMinionsArr, SpawnedMinionsCount, Stream);
          Stream.Position := 0;
          HAPIBANK_AccessSafeDeposit(nil, nil, HAPIBANK, PAnsiChar('SpawnedMinions'));
          HAPIBANK_WriteBinData(nil, nil, HAPIBANK, Stream.Size, Stream.Memory);
        except
          on E: Exception do ; // swallow: do not let custom-data serialization crash the game save
        end;
      finally
        Stream.Free;
      end;
    end;
  end;
end;

procedure SaveGame_SaveAdditionHook;
asm
  pushAD
  lea     ecx, [esp+24h]
  push    ecx
  call    SaveGame_SaveAddition
  popAD
  mov     eax, [TADynMemStructPtr]
  push $00432A3D
  call PatchNJump;
end;

procedure SaveGame_LoadAddition(HAPIBANK: Pointer); stdcall;
var
  Stream: TMemoryStream;
  StreamSize: Integer;
begin
  if HAPIBANK_OpenAccount(nil, nil, HAPIBANK, PAnsiChar('TADR Extensions')) then
  begin
    if HAPIBANK_AccessSafeDeposit(nil, nil, HAPIBANK, PAnsiChar('UnitsSharedData')) then
      HAPIBANK_ReadBinData(nil, nil, HAPIBANK, 1024, @UnitsSharedData[0]);

    if HAPIBANK_AccessSafeDeposit(nil, nil, HAPIBANK, PAnsiChar('UnitSearch')) then
    begin
      Stream := TMemoryStream.Create;
      try
        try
          StreamSize := HAPIBANK_GetItemSize(nil, nil, HAPIBANK);
          if StreamSize > 0 then
          begin
            Stream.SetSize(StreamSize);
            HAPIBANK_ReadBinData(nil, nil, HAPIBANK, StreamSize, Stream.Memory);
            Stream.Position := 0;
            // BUGFIX: was UnitSearchResults.LoadFromStream(Stream) - paired with the
            // manual writer above; see SaveStoreUnitsArrManual for why.
            if not UnitSearchResults.IsVoid then
              LoadStoreUnitsArrManual(UnitSearchArr, UnitSearchCount, Stream);
          end;
        except
          on E: Exception do ; // swallow: a mismatched/corrupt block must not crash the load
        end;
      finally
        Stream.Free;
      end;
    end;

    if HAPIBANK_AccessSafeDeposit(nil, nil, HAPIBANK, PAnsiChar('SpawnedMinions')) then
    begin
      Stream := TMemoryStream.Create;
      try
        try
          StreamSize := HAPIBANK_GetItemSize(nil, nil, HAPIBANK);
          if StreamSize > 0 then
          begin
            Stream.SetSize(StreamSize);
            HAPIBANK_ReadBinData(nil, nil, HAPIBANK, StreamSize, Stream.Memory);
            Stream.Position := 0;
            // BUGFIX: was SpawnedMinions.LoadFromStream(Stream) - same reasoning.
            if not SpawnedMinions.IsVoid then
              LoadStoreUnitsArrManual(SpawnedMinionsArr, SpawnedMinionsCount, Stream);
          end;
        except
          on E: Exception do ; // swallow: a mismatched/corrupt block must not crash the load
        end;
      finally
        Stream.Free;
      end;
    end;
  end;
end;

procedure SaveGame_LoadAdditionHook;
asm
  pushAD
  push    esi
  call    SaveGame_LoadAddition
  popAD
  mov     edx, [TADynMemStructPtr]
  push $00432683
  call PatchNJump;
end;

procedure SaveGame_LoadNoScriptsFix;
label
  AvoidLoad;
asm
  mov     ecx, [esi+TUnitStruct.p_UnitScriptsData]
  test    ecx, ecx
  jz      AvoidLoad
  push $004875FF
  call PatchNJump;
AvoidLoad:
  push $00487605
  call PatchNJump;
end;

end.
