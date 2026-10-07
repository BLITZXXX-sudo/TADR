unit SpeedHack;

interface
uses
  PluginEngine;

const
  State_SpeedHack : boolean = true;

function GetPlugin : TPluginData;

Procedure OnInstallSpeedHack;
Procedure OnUninstallSpeedHack;

Const

  Game_MaxSpeed = high(byte);
  Game_MinSpeed = low(byte);

  TA_MaxSpeed = 20;
  TA_MinSpeed = 0;

var
  Upperlimit : word = TA_MaxSpeed;
  LowerLimit : word = TA_MinSpeed;

Procedure ResetGameSpeedLimits;

Procedure SpeedState_IncreaseSpeed_Check;
Procedure SpeedState_DecreaseSpeed_Check;
Procedure SpeedState_SetSpeed_Check;

implementation
uses
  TADemoConsts,
  TA_MemoryConstants,
  TA_MemoryStructures,
  TA_MemoryLocations;

Procedure ResetGameSpeedLimits;
begin
Upperlimit := TA_MaxSpeed;
LowerLimit := TA_MinSpeed;
end;

Procedure OnInstallSpeedHack;
begin
ResetGameSpeedLimits;
end;

Procedure OnUninstallSpeedHack;
begin
end;

function GetPlugin : TPluginData;
begin
if IsTAVersion31 and State_SpeedHack then
  begin

  result := TPluginData.create( true,
                                'Speed hack',
                                State_SpeedHack,
                                @OnInstallSpeedHack, @OnUnInstallSpeedHack );

  result.MakeRelativeJmp( State_SpeedHack,
                          'Increase speed check',
                          @SpeedState_IncreaseSpeed_Check,
                          $4965B3,
                          $10 );

  result.MakeRelativeJmp( State_SpeedHack,
                          'Decrease speed check',
                          @SpeedState_DecreaseSpeed_Check,
                          $496559,
                          $10 );

  result.MakeRelativeJmp( State_SpeedHack,
                          'Set speed Check',
                          @SpeedState_SetSpeed_Check,
                          $490DF9,
                          $10 );
  end
else
  result := nil;
end;

Procedure SpeedState_DecreaseSpeed_Check;

label
  DontSetSpeed;
asm

  xor  ecx, ecx
  xor  eax, eax
  mov  cx, LowerLimit
  inc  cx

  mov  ax, [edx+TTADynMemStruct.nTAGameSpeed]
  cmp  ax, LowerLimit
  jbe  DontSetSpeed

  push 1
  dec  eax
  push $4965C8;
  call PatchNJump;
DontSetSpeed:
  push $4965CE;
  call PatchNJump;
end;

Procedure SpeedState_IncreaseSpeed_Check;

label
  DontSetSpeed;
asm

  xor  ecx, ecx
  xor  eax, eax
  mov  cx, UpperLimit

  mov  ax, [edx+TTADynMemStruct.nTAGameSpeed]
  cmp  ax, cx
  jnb  DontSetSpeed

  push 1
  inc  eax
  push $4965C8;
  call PatchNJump;
DontSetSpeed:
  push $4965CE;
  call PatchNJump;
end;

procedure SpeedState_SetSpeed_Check;

label
  DoMinSpeedCheck,
  ExitPoint;
asm
  push edi

  xor  eax, eax
  mov  ax, UpperLimit

  cmp  ebx, eax
  jle  DoMinSpeedCheck

  mov  ebx, eax
DoMinSpeedCheck:

  mov  ax, lowerLimit

  cmp  ebx, eax
  jge  ExitPoint

  mov  ebx, eax
ExitPoint:

  push $490E0E;
  call PatchNJump;
end;

end.
