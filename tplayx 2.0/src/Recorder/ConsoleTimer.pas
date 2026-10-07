unit ConsoleTimer;

interface

uses
  Windows, Classes, SyncObjs;

type
  TConsoleTimer = Class(TThread)
  private
    FCancelFlag: TSimpleEvent;
    FTimerEnabledFlag: TSimpleEvent;
    FTimerProc: TNotifyEvent;
    FInterval: integer;
    FFirstTick : Boolean;
    procedure SetEnabled(doEnable: boolean);
    function GetEnabled: boolean;
    procedure SetInterval(interval: integer);
  public
    Constructor Create;
    Destructor Destroy; override;
    procedure Execute; override;
    property Enabled : boolean read GetEnabled write SetEnabled;
    property Interval: integer read FInterval write SetInterval;
    property FirstTick: Boolean read FFirstTick write FFirstTick;

    property OnTimerEvent: TNotifyEvent read FTimerProc write FTimerProc;
  end;

implementation
uses
  StopWatch;

constructor TConsoleTimer.Create;
begin
  inherited Create(false);
  FTimerEnabledFlag := TSimpleEvent.Create;
  FCancelFlag := TSimpleEvent.Create;
  FTimerProc := nil;
  FInterval := 1000;
  Self.FreeOnTerminate := false;
end;

destructor TConsoleTimer.Destroy;
begin
  FTimerEnabledFlag.ResetEvent;
  FCancelFlag.SetEvent;
  Waitfor;
  FCancelFlag.Free;
  FTimerEnabledFlag.Free;
  inherited;
end;

procedure TConsoleTimer.SetEnabled(doEnable: boolean);
begin
  if doEnable then
    FTimerEnabledFlag.SetEvent
  else
    FTimerEnabledFlag.ResetEvent;
end;

procedure TConsoleTimer.SetInterval(interval: integer);
begin
  FInterval := interval;
end;

procedure TConsoleTimer.Execute;
var
  waitList: array [0 .. 1] of THandle;
  waitInterval: Int64;
  sw: TStopWatch;
begin
  sw:= TStopWatch.Create;

waitList[0] := THandle(FTimerEnabledFlag.Handle);
waitList[1] := THandle(FCancelFlag.Handle);

  while not Terminated do
  begin
    if (WaitForMultipleObjects(2, @waitList[0], false, INFINITE) <>
      WAIT_OBJECT_0) then
      break;
    if Assigned(FTimerProc) then
    begin
      sw.Start;
      FTimerProc(Self);
      sw.Stop;

      waitInterval := FInterval - sw.ElapsedMilliSeconds;
      if (waitInterval < 0) then
         waitInterval := 0;

WaitForSingleObject(THandle(FCancelFlag.Handle), waitInterval);
    end;
  end;
end;

function TConsoleTimer.GetEnabled: boolean;
begin
  Result := (FTimerEnabledFlag.Waitfor(0) = wrSignaled);
end;

end.
