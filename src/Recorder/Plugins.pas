unit Plugins;

interface

// some code injects must occur before the exe's main has run
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
  PlayerSlotCleanup,
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
  //KillDamage,
  //MinimapExpand,
 PlayersSlotsExpand,
  SaveGame,
  Developers,
  StatsLogging,
  CloakOnly,
  QueueDiag,
  TDrawUnhook,
  Fix16PRuntime,
  HangWatch,
  JoinGuard,
  ColorFreeFix;

// ---- Plugin enable switches --------------------------------------------------
// Bisected 2026-07-20: of these eight, "Builders" alone causes the Load Thread
// Access Violation (confirmed over 4 rounds - crashes whenever Builders=True,
// loads clean whenever it's False, regardless of the other seven). Now
// sub-bisecting INSIDE Builders.pas itself (see its Test_* consts) to find
// which one of its five always-active patches is the actual culprit -
// Builders re-enabled here (True) so it registers again for that test; its
// own internal Test_* flags control which of its patches actually apply.
const
  Test_Builders             : Boolean = True; // re-enabled for Builders.pas internal sub-bisection
  Test_ScriptCallsExtend    : Boolean = True;
  Test_OrdersOverride       : Boolean = True;
  Test_UnitActions          : Boolean = True;
  Test_Transporters         : Boolean = True;
  Test_WeaponAimNTrajectory : Boolean = True;
  Test_GAFSequences         : Boolean = True;
  Test_MapExtensions        : Boolean = True;
// -----------------------------------------------------------------------------

procedure Do_LoadTime_CodeInjections( OnMainRun : boolean );
type
  TGetPluginFunc = function: TPluginData; // function pointer type for all GetPlugin() calls
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

  // GetFunc is called INSIDE the try block so exceptions from GetPlugin()
  // are caught, not just exceptions from RegisterPlugin().
  procedure SafeRegister(const PluginName: string; GetFunc: TGetPluginFunc);
  var
    Plugin: TPluginData;
  begin
    try
      {$IFDEF TPLAYX_DEBUG}
      Log('  RegisterPlugin: ' + PluginName + ' ...');
      {$ENDIF}
      Plugin := GetFunc();  // GetPlugin() called here, inside try
      RegisterPlugin(Plugin);
      {$IFDEF TPLAYX_DEBUG}
      Log('  RegisterPlugin: ' + PluginName + ' OK');
      {$ENDIF}
      // failures are always logged (except branch below)
    except
      on e: Exception do
        Log('  RegisterPlugin: ' + PluginName + ' FAILED: ' + e.ClassName + ' - ' + e.Message);
    end;
  end;

begin
  // ---- Log file (append mode so multiple calls don't overwrite each other) ----
  LogPath := ExtractFilePath(ParamStr(0)) + 'tplayx_init.log';
  AssignFile(LogFile, LogPath);
  {$I-}
  if FileExists(LogPath) then
    Append(LogFile)   // append to existing log
  else
    Rewrite(LogFile); // create new if doesn't exist
  {$I+}
  Log('');
  Log('=== tplayx Do_LoadTime_CodeInjections ===');
  Log('Date/Time: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
  Log('OnMainRun=' + BoolToStr(OnMainRun, True));
  Log('TA path: ' + ParamStr(0));

  // only register once
  if OnMainRun then
  begin
    Log('--- Registering plugins ---');
    SafeRegister('ErrorLog_ExtraData', @   ErrorLog_ExtraData.GetPlugin);
    SafeRegister('Thread_marshaller', @    Thread_marshaller.GetPlugin);
    Log('IniSettings check: ModId=' + IntToStr(IniSettings.ModId) + ' IniFile check...');
    Log('ParamStr(0)=' + ParamStr(0));
    SafeRegister('IniOptions', @           IniOptions.GetPlugin);
  // safeRegister('PlayersSlotsExpand', @           PlayersSlotsExpand.GetPlugin);

    SafeRegister('InputHook', @            InputHook.GetPlugin);
    SafeRegister('SpeedHack', @            SpeedHack.GetPlugin);
    SafeRegister('PauseLock', @            PauseLock.GetPlugin);
    SafeRegister('UnitLimit', @            UnitLimit.GetPlugin);
    SafeRegister('LOS_extensions', @       LOS_extensions.GetPlugin);
    SafeRegister('MultiAILimit', @         MultiAILimit.GetPlugin);
    SafeRegister('PlayerSlotCleanup', @    PlayerSlotCleanup.GetPlugin);
    SafeRegister('KeyboardHook', @         KeyboardHook.GetPlugin);
    SafeRegister('WeaponsExpand', @        WeaponsExpand.GetPlugin);
    SafeRegister('UnitInfoExpand', @       UnitInfoExpand.GetPlugin);
    SafeRegister('SideDataExpand', @       SideDataExpand.GetPlugin);
    SafeRegister('RegPathFix', @           RegPathFix.GetPlugin);
    Log('IniSettings.ModId=' + IntToStr(IniSettings.ModId));
    // NOTE: these 8 used to be gated behind "if IniSettings.ModId > 1".
    // Decoupled for bisection testing - see Test_* consts above. ModId no
    // longer affects this group at all; it can be left at any value.
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
    SafeRegister('QueueDiag', @            QueueDiag.GetPlugin);
    SafeRegister('TDrawUnhook', @          TDrawUnhook.GetPlugin);
  SafeRegister('Fix16PRuntime', @        Fix16PRuntime.GetPlugin);
    SafeRegister('HangWatch', @            HangWatch.GetPlugin);
    SafeRegister('JoinGuard', @            JoinGuard.GetPlugin);
    SafeRegister('ColorFreeFix', @         ColorFreeFix.GetPlugin);
    Log('--- All plugins registered ---');
  end;

  // Run the code injection engine
  Log('InstallPlugins start');
  try
    InstallPlugins( OnMainRun );
    Log('InstallPlugins completed OK');
  except
    on e: Exception do
      Log('InstallPlugins FAILED: ' + e.ClassName + ' - ' + e.Message);
  end;

  Log('=== Do_LoadTime_CodeInjections done ===');
  // AUDIT 28 Sep: CloseFile raised (outside any try) when the open had failed
  try
    CloseFile(LogFile);
  except end;
end;

Procedure UninstallCodeInjections;
begin
  UnInstallPlugins;
end;

end.
