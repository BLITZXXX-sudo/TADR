unit UnitLimit;

interface
uses
  PluginEngine;

Procedure OnInstallUnitLimit;
Procedure OnUninstallUnitLimit;

const
  NewUnitLimit : word = 1500;

const
  State_UnitLimit : boolean = true;

function GetPlugin : TPluginData;

implementation
uses
  sysutils,
  TADemoConsts,
  TA_MemoryLocations,
  IniOptions;

Procedure OnInstallUnitLimit;
begin

end;

Procedure OnUninstallUnitLimit;
begin
end;

function GetPlugin : TPluginData;
var
  aUnitLimit : Word;
begin
if IsTAVersion31 and State_UnitLimit then
  begin
  if IniSettings.UnitLimit <> 0 then
    aUnitLimit := Word(IniSettings.UnitLimit)
  else
  begin
    IniSettings.UnitLimit := NewUnitLimit;
    aUnitLimit := NewUnitLimit;
  end;

  result := TPluginData.create( true,
                                IntToStr(NewUnitLimit)+' unit limit',
                                State_UnitLimit,
                                @OnInstallUnitLimit, @OnUnInstallUnitLimit );
  result.MakeReplacement( State_UnitLimit,
                          'Default unit limit',
                          $491640,
                          aUnitLimit,sizeof(aUnitLimit));
  result.MakeReplacement( State_UnitLimit,
                          'Unit Limit Compare',
                          $491659,
                          aUnitLimit,sizeof(aUnitLimit));
  result.MakeReplacement( State_UnitLimit,
                          'Unit Limit SetMax',
                          $491666,
                          aUnitLimit,sizeof(aUnitLimit));

  end
else
  result := nil;
end;

end.
