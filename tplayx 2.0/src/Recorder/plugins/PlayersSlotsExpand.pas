unit PlayersSlotsExpand;

interface
uses
  PluginEngine,
  TA_MemoryLocations,
  TA_MemoryStructures,
  TA_MemoryConstants;

const
  State_PlayersSlotsExpand : boolean = true;

var
  PlayersExp : array[0..32] of TPlayerStruct;

function GetPlugin : TPluginData;

Procedure OnInstallPlayersSlotsExpand;
Procedure OnUninstallPlayersSlotsExpand;

Procedure InitPlayersArray;
Procedure SetPlayerStructMem;

implementation
uses
  Windows,
  TADemoConsts,
  TA_FunctionsU;

Procedure OnInstallPlayersSlotsExpand;
begin
end;

Procedure OnUninstallPlayersSlotsExpand;
begin
end;

function GetPlugin : TPluginData;
var
  cMaxplayers : Byte;
begin
  if IsTAVersion31 and State_PlayersSlotsExpand then
  begin
    Result := TPluginData.create( State_PlayersSlotsExpand,
                                  'PlayersSlotsExpand Plugin',
                                  State_PlayersSlotsExpand,
                                  @OnInstallPlayersSlotsExpand,
                                  @OnUninstallPlayersSlotsExpand );

    cMaxplayers := 32;

    Result.MakeReplacement( State_PlayersSlotsExpand,
                            '',
                            $00464995, cMaxPlayers, 1);

    Result.MakeRelativeJmp( State_PlayersSlotsExpand,
                            'Load game init players array',
                            @InitPlayersArray,
                            $00464992, 0);

    Result.MakeRelativeJmp( State_PlayersSlotsExpand,
                            '',
                            @SetPlayerStructMem,
                            $00401083, 1);
  end else
    Result := nil;
end;

procedure InitPlayersArr; stdcall;
var
  i : Integer;
begin
  for i := 0 to 32 do
  begin
    InitPlayerStruct(@PlayersExp[i]);

    if i < 11 then
      InitPlayerStruct(@TAData.MainStruct.Players[i]);
  end;
end;

procedure InitPlayersArray;
asm
  pushAD
  call    InitPlayersArr
  popAD
  push $004649BF;
  call    PatchNJump;
end;

procedure SetPlayerStructMem;
asm
  lea     esi, PlayersExp
  and     eax, 255
  pop     edi
  mov     ecx, eax
  shl     ecx, 5
  add     ecx, eax
  lea     ecx, [ecx+ecx*4]
  lea     eax, [esi+ecx*2]
  push $004010A2;
  call PatchNJump;
end;

end.
