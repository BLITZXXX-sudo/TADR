unit InitCode;

interface
uses
  sysutils;

type
  EValidationFailed = class(Exception);

procedure OnInitialize( OnMainRun : boolean );
procedure OnFinalize;

implementation
uses
  mmsystem,
  windows,
  logging,
  Dplayx_exports,
  FreeListU,
{$IFDEF ThreadLogging}
  threadlogging,
{$ENDIF}
  TADemoConsts,
  TA_MemoryLocations,
  Plugins,
  IniOptions;

{$IFNDEF Debug}

Procedure CheckTADemoIntegrity;
begin
end;
{$ENDIF}

type
  TDisableThreadLibraryCallsHandler = function( hModule : THandle ) : longbool; stdcall;
var
  proc : TDisableThreadLibraryCallsHandler;
function DisableThreadLibraryCalls( hModule : THandle ) : longbool; stdcall;
begin
Result := True;
if kernellib = 0 then
  kernellib := LoadLibrary( kernel32 );
if kernellib <> 0 then
  begin
  proc := GetProcAddress( kernellib, 'DisableThreadLibraryCalls' );
  if Assigned(proc) then
    Result := proc( hModule );
  end;
end;

procedure OnInitialize( OnMainRun : boolean );
var
  aTimeCaps : TTimeCaps;
begin
{$IFNDEF Debug}
CheckTADemoIntegrity;
{$ENDIF}

try
if not OnMainRun then
  begin
  FreeListU.OnInitialize();

  DisableThreadLibraryCalls( hinstance );

  timeGetDevCaps( @aTimeCaps, SizeOf(aTimeCaps) );
  timeBeginPeriod( aTimeCaps.wPeriodMin );

  if (logdir = '') or (logdir = '.') then
    logdir := IncludeTrailingPathDelimiter( ExtractFilePath( SelfLocation ) + 'log');

  if logFilename = '' then
    logFilename := 'TA Demo Recorder Log -'+DateTimeToStr(now)+'.txt';

  if Log_ = nil then
    Log_ := TLog.Create( logFilename, False, VerboseLoggingLevelc );
  Tlog.add( 0, 'Recorder version:'+ GetTADemoVersion );
  if IsWin9x then
    TLog.Add( 0, 'Running in Win9x compatibility mode' );
  if not IsTAVersion31 then
    TLog.Add( 0, 'Not running Total Annihilation 3.1' );
  if iniSettings.modid <> -1 then
    TLog.Add( 0, 'MOD ID: ' +IntToStr(iniSettings.modid) );
{$IFNDEF NoDplayExports}

  if DPlayxHandleInvalid then
    begin
{$IFDEF DplayRedirector}

    dplayxLibHandle := LoadLibrary(Pchar(Paramstr(0)));
{$ELSE}
    dplayxLibHandle := LoadLibrary(PChar( GetSysDir + 'dplayx.dll' ));
{$ENDIF}
    end;
{$ENDIF}

  Randomize;

{$IFDEF ThreadLogging}
  ThreadLogger := TThreadLogger.create;
  ObjectsToFree.add( ThreadLogger );
{$ENDIF}

  end;

  Do_LoadTime_CodeInjections( OnMainRun );
except
  on e : Exception do
    begin
    LogException(e);
    raise;
    end;
end;
end;

Procedure OnFinalize;
begin
UninstallCodeInjections;
FreeListU.OnFinalize();
{$IFNDEF NoDplayExports}
if not DPlayxHandleInvalid then
  begin
  FreeLibrary(dplayxLibHandle);
  dplayxLibHandle := 0;
  end;
{$ENDIF}
Tlog.Flush;

end;

Initialization
DoInitialize := @OnInitialize;
DoFinalize := @OnFinalize;
end.
