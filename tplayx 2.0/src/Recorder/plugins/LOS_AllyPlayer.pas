unit LOS_AllyPlayer;

interface
uses
  PluginEngine;

Procedure Player_SetAlliedState_JumpHook;
Procedure Player_SetAlliedState_RetHook;
Procedure Signal_AlliedStateChange;

var
  AlliedStateChanged : integer;

Procedure GetCodeInjections( PluginData : TPluginData );

implementation
uses
  LOS_extensions,
  TADemoConsts,
  TA_MemoryConstants,
  TA_MemoryStructures,
  TA_FunctionsU;

Procedure GetCodeInjections( PluginData : TPluginData );
begin
PluginData.MakeRelativeJmp( State_LOS_AllyPlayer,
                            'Player_SetAlliedState_Jump1Hook',
                            @Player_SetAlliedState_JumpHook,
                            $452B5E,
                            5);

PluginData.MakeRelativeJmp( State_LOS_AllyPlayer,
                            'Player_SetAlliedState_RetHook',
                            @Player_SetAlliedState_RetHook,
                            $452B54,
                            5);

PluginData.MakeRelativeJmp( State_LOS_AllyPlayer,
                            'Signal_AlliedStateChange',
                            @Signal_AlliedStateChange,
                            $46555F,
                            1);

end;

Procedure Signal_AlliedStateChange;
label
  SkipLOSReset,
  SkipRadarNMiniMapUpdate;
asm

  mov ecx, AlliedStateChanged
  cmp ecx, 0
  jz SkipLOSReset

  xor ecx,ecx
  mov AlliedStateChanged, ecx

  PushAD
  PushFD

  push 0
  mov ecx, Game_SetLOSState
  call ecx;

  popFD
  popAD
SkipLOSReset:
  mov ecx, [TAdynmemStructPtr]
  cmp bl, [ecx+TTADynMemStruct.cViewPlayerID]
  jnz SkipRadarNMiniMapUpdate

  push $46556D
  Call PatchNJump;

SkipRadarNMiniMapUpdate:
  push $4655A6
  Call PatchNJump;
end;

Procedure Player_SetAlliedState_JumpHook;
asm
  mov AlliedStateChanged, 1

  xor     eax, eax

  pop edi
  pop esi
  pop ebp
  pop ebx
  pop ecx
  ret 10h
end;

Procedure Player_SetAlliedState_RetHook;
asm
  mov AlliedStateChanged, 1

  mov eax, ebx

  pop edi
  pop esi
  pop ebp
  pop ebx
  pop ecx
  ret 10h
end;

end.
