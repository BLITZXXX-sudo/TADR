unit LOS_extensions;
interface
uses
  PluginEngine;

const
  State_LOS_UpdateTables = true;
  State_LOS_MiniMap = true;
  State_LOS_Radar = true;
  State_LOS_PlayerSeeUnit = true;
  State_LOS_GUIText = true;
  State_LOS_AllyPlayer = true;

function GetPlugin : TPluginData;

Procedure ResetShareLosState;

var

  ViewPlayer : longint;

implementation
uses
  sysutils,
  classes,
  TADemoConsts,
  TA_MemoryLocations,
  TA_MemoryConstants,
  TA_MemoryStructures,
  TA_FunctionsU,
  InputHook,
  LOS_Radar,
  LOS_MiniMapUnits,
  LOS_PlayerSeeUnit,
  LOS_GuiText,
  LOS_UpdateTables,
  LOS_AllyPlayer;

Procedure ResetShareLosState;
var
  MainStructPtr: PTADynMemStruct;
begin

  if PCardinal(TAdynmemStructPtr)^ = 0 then Exit;
  MainStructPtr := PTADynMemStruct(PCardinal(TAdynmemStructPtr)^);
  ViewPlayer := MainStructPtr.cControlPlayerID;
end;

Procedure OnInstallShareLOS;
begin

ResetShareLosState;

end;

Procedure OnUninstallShareLOS;
begin
ResetShareLosState;
end;

Procedure TextCommand_View_Hook;
asm
  mov  ecx, [TADynmemStructPtr]
  mov  [ecx+TTADynMemStruct.cViewPlayerID], al

  xor ecx, ecx
  mov cl, al
  mov  ViewPlayer, ecx

  mov AlliedStateChanged, 1

  push $416BC7
  call PatchNJump;
end;

Procedure TextCommand_ShareAll_Hook;
asm

  xor edx, edx
  mov dl, [eax+TTADynMemStruct.cControlPlayerID]

  push $4190BD;
  call PatchNJump;
end;

function GetPlugin : TPluginData;
begin
if IsTAVersion31 then
  begin

  result := TPluginData.create( false,
                                'Sharelos',
                                State_LOS_Radar or State_LOS_PlayerSeeUnit or State_LOS_GUIText,
                                @OnInstallShareLOS, @OnUnInstallShareLOS );

  result.MakeRelativeJmp( result.Enabled, '+view hook', @TextCommand_View_Hook, $416BBB, 1 );

  LOS_Radar.GetCodeInjections( result );
  LOS_MiniMapUnits.GetCodeInjections( result );
  LOS_PlayerSeeUnit.GetCodeInjections( result );
  LOS_GuiText.GetCodeInjections( result );
  LOS_UpdateTables.GetCodeInjections( result );
  LOS_AllyPlayer.GetCodeInjections( result );
  end
else
  result := nil;
end;

end.
