unit PauseLock;

interface
uses
  PluginEngine;

const
  State_PauseLock : boolean = true;

function GetPlugin : TPluginData;

Procedure OnInstall;
Procedure OnUninstall;

var
  StopPauseStateChange : integer = 0;

Procedure SetPausedState( LockState : boolean; pause : boolean);

Procedure PauseHandling;

implementation
uses
  TADemoConsts,
  TA_MemoryConstants,
  TA_MemoryLocations;

Procedure OnInstall;
begin
end;

Procedure OnUninstall;
begin
end;

function GetPlugin : TPluginData;
begin
if IsTAVersion31 and State_PauseLock then
  begin

  result := TPluginData.create( false,
                                'Pause lock',
                                State_PauseLock,
                                @OnInstall, @OnUnInstall );

  result.MakeRelativeJmp( false,
                          'Lock pause state handler',
                          @PauseHandling,
                          $496099,
                          $1 );

  end
else
  result := nil;
end;

Procedure SetPausedState( LockState : boolean; pause : boolean);
begin
StopPauseStateChange := BoolValues[LockState];
TAData.Paused := Pause;
end;

Procedure PauseHandling;
label
  PauseStateLocked;
asm
  mov eax, StopPauseStateChange
  cmp eax, 0
  jnz PauseStateLocked

  mov ecx, [TAdynmemStructPtr]

  push $49609F;
  call PatchNJump;

PauseStateLocked:

  push $4965CE;
  call PatchNJump;
end;

end.
