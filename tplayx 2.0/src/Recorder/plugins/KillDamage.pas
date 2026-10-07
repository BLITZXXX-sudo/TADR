unit KillDamage;

interface
uses
  PluginEngine;

const
  State_KillDamage : boolean = true;

function GetPlugin : TPluginData;

Procedure OnInstallKillDamage;
Procedure OnUninstallKillDamage;

procedure KillDamage_FixVeteranCloneBug;

implementation
uses
  IniOptions,
  TA_MemoryConstants,
  TA_MemoryLocations,
  TA_MemoryStructures;

var
  KillDamagePlugin: TPluginData;

Procedure OnInstallKillDamage;
begin
end;

Procedure OnUninstallKillDamage;
begin
end;

function GetPlugin : TPluginData;
begin
  if IsTAVersion31 and State_KillDamage then
  begin
    KillDamagePlugin := TPluginData.create( false,
                            'Increase damage to kill units',
                            State_KillDamage,
                            @OnInstallKillDamage,
                            @OnUnInstallKillDamage );

    KillDamagePlugin.MakeRelativeJmp( State_KillDamage,
                          'KillDamage_FixVeteranCloneBug',
                          @KillDamage_FixVeteranCloneBug,
                          $00489C2F, 0);

    Result:= KillDamagePlugin;
  end else
    Result := nil;
end;

procedure KillDamage_FixVeteranCloneBug;
label
  GiveUnitCall;
asm
   shr     eax, 1Fh
   add     edx, eax
   pushf
   cmp     ebx, Integer(dtGiveUnit)
   jz      GiveUnitCall
   popf
   push $00489C34;
   call PatchNJump;
GiveUnitCall :
   popf
   mov     eax, [esi+92h]
   mov     edx, [eax+1FAh]
   push $00489C34;
   call PatchNJump;
end;

end.
