unit LOS_Radar;

interface
uses
  PluginEngine;

var

  TestPlayerIndex : longint;
  TestPlayerPtr : pointer;
  PlayerPtr : pointer;
  ViewPlayerRadar: longint;

Procedure GameUnit_LOS_Radar_CanDirectlySeeUnit;

Procedure GameUnit_LOS_Radar_LoopStart;
Procedure GameUnit_LOS_Radar_LoopCondition;

Procedure GetCodeInjections( PluginData : TPluginData );

implementation
uses
  LOS_extensions,
  TADemoConsts,
  TA_MemoryStructures,
  TA_MemoryConstants;

Procedure GetCodeInjections( PluginData : TPluginData );
begin
PluginData.MakeRelativeJmp( State_LOS_Radar,
                            'GameUnit_LOS_Radar_CanDirectlySeeUnit',
                            @GameUnit_LOS_Radar_CanDirectlySeeUnit,
                            $4674AB,
                            4);

PluginData.MakeRelativeJmp( State_LOS_Radar,
                            'GameUnit_LOS_Radar_LoopStart',
                            @GameUnit_LOS_Radar_LoopStart ,
                            $46750E,

                            1);
PluginData.MakeRelativeJmp( State_LOS_Radar,
                            'GameUnit_LOS_Radar_LoopCondition',
                            @GameUnit_LOS_Radar_LoopCondition,
                            $46782F,
                            2);
end;

Procedure GameUnit_LOS_Radar_CanDirectlySeeUnit;

label
  CanSeeUnitOnRadar,
  CanNotSeeUnitOnRadar,
  SetRadarVisibleState,
  SkipUnit;
asm

  mov ecx, [eax]
  test ecx, 10000000h
  jz SkipUnit

  mov esi, ecx
  xor ecx, ecx
  mov cl, [eax-11h]
  and  esi, 0FFFFEFFFh
  mov  [eax], esi

  mov ecx, [eax-7Ah]
  xor ebx, ebx
  mov bl, [ebp+TPlayerStruct.cPlayerIndex]
  cmp byte [ebx+ecx+TPlayerStruct.cAllyFlagArray], 0
  jnz CanSeeUnitOnRadar

  cmp dword ptr [ebp], 0
  jz CanNotSeeUnitOnRadar
  mov ecx, [ebp+TPlayerStruct.PlayerInfo]
  test [ecx+TPlayerInfoStruct.PropertyMask], 40h
  jnz CanSeeUnitOnRadar

CanNotSeeUnitOnRadar:
  mov ecx, [eax]
  and ch, 0F8h
  jmp SetRadarVisibleState

CanSeeUnitOnRadar:
  mov ecx, [eax]
  or ch, 3

SetRadarVisibleState:
  mov [eax], ecx

SkipUnit:
  push $4674FB
  call PatchNJump;
end;

Procedure GameUnit_LOS_Radar_LoopStart;
label
  l1,l2;
asm

  mov esi, [ebp+TPlayerStruct.p_UnitsArray]
  mov eax, [ebp+TPlayerStruct.p_LastUnit]
  cmp esi, eax
  ja l2
  jmp l1;

l2:
  push $4675D2;
  call PatchNJump;
l1:

  xor ecx, ecx
  mov TestPlayerIndex, ecx;

  mov esi, [TADynmemStructPtr]
  mov cl, [esi+TTADynMemStruct.cViewPlayerID]
  mov ViewPlayerRadar, ecx;

  mov eax, esi
  add eax, Cardinal(TTADynMemStruct.Players)
  mov TestPlayerPtr, eax

  add esi, Cardinal(TTADynMemStruct.Players)
  mov eax, type TPlayerStruct
  mul ecx
  add esi, eax
  mov PlayerPtr, esi

  jmp GameUnit_LOS_Radar_LoopCondition;
end;

Procedure GameUnit_LOS_Radar_LoopCondition;

label
  NextValue,
  CleanupNExit,
  SkipTest,
  TryNextPlayer_NextValue,
  TryNextPlayer_Condition;

asm
  mov ecx, TestPlayerIndex;
  mov eax, TestPlayerPtr;
  mov esi, ViewPlayerRadar;
  jmp TryNextPlayer_Condition

TryNextPlayer_NextValue:

  inc ecx;

  add eax, type TPlayerStruct

TryNextPlayer_Condition:
  cmp ecx, 10
  jnb CleanupNExit

  cmp byte [eax+esi+TPlayerStruct.cAllyFlagArray], 0
  jz TryNextPlayer_NextValue

  mov esi, [TADynmemStructPtr]
  mov [esi+TTADynMemStruct.cViewPlayerID], cl

  inc ecx
  mov TestPlayerIndex, ecx
  add eax, type TPlayerStruct
  mov TestPlayerPtr, eax

  mov     dl, [esi+TTADynMemStruct.cViewPlayerID]
  mov     edi, [esi+TTADynMemStruct.p_Units]
  mov     eax, edx
  mov     ebx, [esi+TTADynMemStruct.p_LastUnitInArray]
  and     eax, 0FFh
  add     edi, 118h
  mov     ecx, eax
  add     esi, eax
  shl     ecx, 5
  add     ecx, eax
  cmp     edi, ebx
  mov     [esp+14h], edi
  mov     [esp+10h], ebx
  lea     ecx, [ecx+ecx*4]
  lea     ebp, [esi+ecx*2+TTADynMemStruct.Players]

  mov esi, [ebp+TPlayerStruct.p_UnitsArray]
  mov eax, [ebp+TPlayerStruct.p_LastUnit]
  cmp esi, eax
  ja SkipTest

  push $46751C;
  call PatchNJump

SkipTest:
  push $4675D2;
  call PatchNJump;

CleanupNExit:

  mov ecx, ViewPlayerRadar;
  mov esi, [TADynmemStructPtr]
  mov [esi+TTADynMemStruct.cViewPlayerID], cl
  xor eax, eax

  pop edi
  pop esi
  pop ebp
  pop ebx
  add esp, $28
  retn
end;

end.
