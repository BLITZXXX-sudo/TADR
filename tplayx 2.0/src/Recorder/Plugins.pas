unit Plugins;

interface

procedure Do_LoadTime_CodeInjections( OnMainRun : boolean );

Procedure UninstallCodeInjections;

implementation
uses
  SysUtils,
  PluginEngine,
  ErrorLog_ExtraData,
  Thread_marshaller,
  IniOptions,
  RegPathFix,
  InputHook,
  SpeedHack,
  PauseLock,
  UnitLimit,
  LOS_extensions,
  MultiAILimit,
  KeyboardHook,
  WeaponsExpand,
  UnitInfoExpand,
  Builders,
  ScriptCallsExtend,
  UnitActions,
  Transporters,
  OrdersOverride,
  WeaponAimNTrajectory,
  GAFSequences,
  MapExtensions,
  SideDataExpand,
  Colors,
  ClockPosition,
  GUIEnhancements,
  NanoFrameUnits,
  BroadcastNanolathe,
  BattleRoomEnhancements,
  SkirmishEnhancements,
  ExtensionsMem,
  COB_extensions,
  MaxScriptSlots,

  SaveGame,
  Developers,
  StatsLogging,
  CloakOnly,
  MidBattleTest,
  OnOffPortal;

const
  Test_Builders             : Boolean = True;
  Test_ScriptCallsExtend    : Boolean = True;
  Test_OrdersOverride       : Boolean = True;
  Test_UnitActions          : Boolean = True;
  Test_Transporters         : Boolean = True;
  Test_WeaponAimNTrajectory : Boolean = True;
  Test_GAFSequences         : Boolean = True;
  Test_MapExtensions        : Boolean = True;

procedure Do_LoadTime_CodeInjections( OnMainRun : boolean );
type
  TGetPluginFunc = function: TPluginData;
var
  LogFile: TextFile;
  LogPath: string;

  procedure Log(const Msg: string);
  begin
    try
      Writeln(LogFile, Msg);
      Flush(LogFile);
    except end;
  end;

  procedure SafeRegister(const PluginName: string; GetFunc: TGetPluginFunc);
  var
    Plugin: TPluginData;
  begin
    try
      Log('  RegisterPlugin: ' + PluginName + ' ...');
      Plugin := GetFunc();
      RegisterPlugin(Plugin);
      Log('  RegisterPlugin: ' + PluginName + ' OK');
    except
      on e: Exception do
        Log('  RegisterPlugin: ' + PluginName + ' FAILED: ' + e.ClassName + ' - ' + e.Message);
    end;
  end;

begin

  LogPath := ExtractFilePath(ParamStr(0)) + 'tplayx_init.log';
  AssignFile(LogFile, LogPath);
  {$I-}
  if FileExists(LogPath) then
    Append(LogFile)
  else
    Rewrite(LogFile);
  {$I+}
  Log('');
  Log('=== tplayx Do_LoadTime_CodeInjections ===');
  Log('Date/Time: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
  Log('OnMainRun=' + BoolToStr(OnMainRun, True));
  Log('TA path: ' + ParamStr(0));

  if OnMainRun then
  begin
    Log('--- Registering plugins ---');
    SafeRegister('ErrorLog_ExtraData', @   ErrorLog_ExtraData.GetPlugin);
    SafeRegister('Thread_marshaller', @    Thread_marshaller.GetPlugin);
    Log('IniSettings check: ModId=' + IntToStr(IniSettings.ModId) + ' IniFile check...');
    Log('ParamStr(0)=' + ParamStr(0));
    SafeRegister('IniOptions', @           IniOptions.GetPlugin);
    SafeRegister('InputHook', @            InputHook.GetPlugin);
    SafeRegister('SpeedHack', @            SpeedHack.GetPlugin);
    SafeRegister('PauseLock', @            PauseLock.GetPlugin);
    SafeRegister('UnitLimit', @            UnitLimit.GetPlugin);
    SafeRegister('LOS_extensions', @       LOS_extensions.GetPlugin);
    SafeRegister('MultiAILimit', @         MultiAILimit.GetPlugin);
    SafeRegister('KeyboardHook', @         KeyboardHook.GetPlugin);
    SafeRegister('WeaponsExpand', @        WeaponsExpand.GetPlugin);
    SafeRegister('UnitInfoExpand', @       UnitInfoExpand.GetPlugin);
    SafeRegister('SideDataExpand', @       SideDataExpand.GetPlugin);
    SafeRegister('RegPathFix', @           RegPathFix.GetPlugin);
    Log('IniSettings.ModId=' + IntToStr(IniSettings.ModId));

    Log('Bisection: Builders=' + BoolToStr(Test_Builders, True) +
        ' ScriptCallsExtend=' + BoolToStr(Test_ScriptCallsExtend, True) +
        ' OrdersOverride=' + BoolToStr(Test_OrdersOverride, True) +
        ' UnitActions=' + BoolToStr(Test_UnitActions, True) +
        ' Transporters=' + BoolToStr(Test_Transporters, True) +
        ' WeaponAimNTrajectory=' + BoolToStr(Test_WeaponAimNTrajectory, True) +
        ' GAFSequences=' + BoolToStr(Test_GAFSequences, True) +
        ' MapExtensions=' + BoolToStr(Test_MapExtensions, True));
    if Test_Builders then
      SafeRegister('Builders', @             Builders.GetPlugin);
    if Test_ScriptCallsExtend then
      SafeRegister('ScriptCallsExtend', @    ScriptCallsExtend.GetPlugin);
    if Test_OrdersOverride then
      SafeRegister('OrdersOverride', @       OrdersOverride.GetPlugin);
    if Test_UnitActions then
      SafeRegister('UnitActions', @          UnitActions.GetPlugin);
    if Test_Transporters then
      SafeRegister('Transporters', @         Transporters.GetPlugin);
    if Test_WeaponAimNTrajectory then
      SafeRegister('WeaponAimNTrajectory', @ WeaponAimNTrajectory.GetPlugin);
    if Test_GAFSequences then
      SafeRegister('GAFSequences', @         GAFSequences.GetPlugin);
    if Test_MapExtensions then
      SafeRegister('MapExtensions', @        MapExtensions.GetPlugin);
    Log('IniSettings.Colors=' + BoolToStr(IniSettings.Colors, True));
    if IniSettings.Colors then
      SafeRegister('Colors', @             Colors.GetPlugin);
    SafeRegister('ClockPosition', @        ClockPosition.GetPlugin);
    SafeRegister('GUIEnhancements', @      GUIEnhancements.GetPlugin);
    SafeRegister('NanoFrameUnits', @       NanoFrameUnits.GetPlugin);
    Log('IniSettings.BroadcastNanolathe=' + BoolToStr(IniSettings.BroadcastNanolathe, True));
    if IniSettings.BroadcastNanolathe then
      SafeRegister('BroadcastNanolathe', @ BroadcastNanolathe.GetPlugin);
    Log('IniSettings.BattleRoomEnh=' + BoolToStr(IniSettings.BattleRoomEnh, True));
    if IniSettings.BattleRoomEnh then
      SafeRegister('BattleRoomEnhancements', @BattleRoomEnhancements.GetPlugin);
    SafeRegister('SkirmishEnhancements', @ SkirmishEnhancements.GetPlugin);
    SafeRegister('ExtensionsMem', @        ExtensionsMem.GetPlugin);
    SafeRegister('COB_extensions', @       COB_extensions.GetPlugin);
    SafeRegister('MaxScriptSlots', @       MaxScriptSlots.GetPlugin);
    Log('IniSettings.CreateStatsFile=' + BoolToStr(IniSettings.CreateStatsFile, True));
    if IniSettings.CreateStatsFile then
      SafeRegister('StatsLogging', @       StatsLogging.GetPlugin);
    SafeRegister('SaveGame', @             SaveGame.GetPlugin);
    SafeRegister('Developers', @           Developers.GetPlugin);
    SafeRegister('CloakOnly', @            CloakOnly.GetPlugin);
    SafeRegister('OnOffPortal', @          OnOffPortal.GetPlugin);
    SafeRegister('MidBattleTest', @        MidBattleTest.GetPlugin);
    Log('--- All plugins registered ---');
  end;

  Log('InstallPlugins start');
  try
    InstallPlugins( OnMainRun );
    Log('InstallPlugins completed OK');
  except
    on e: Exception do
      Log('InstallPlugins FAILED: ' + e.ClassName + ' - ' + e.Message);
  end;

  Log('=== Do_LoadTime_CodeInjections done ===');
  CloseFile(LogFile);
end;

Procedure UninstallCodeInjections;
begin
  UnInstallPlugins;
end;

end.
