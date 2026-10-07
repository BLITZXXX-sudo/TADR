unit LOS_PlayerSeeUnit;

interface
uses
  PluginEngine, TA_MemoryStructures;

var

  PlayerSeeUnit_p_Unit : PUnitStruct;
  PlayerSeeUnit_PlayerPtr : PPlayerStruct;

  PlayerSeeUnit_TestPlayer : longint;
  PlayerSeeUnit_ViewPlayerPlSeeU: longint;
  PlayerSeeUnit_TestPlayerPlSeeU: longint;

Procedure GameUnit_LOS_PlayerSeeUnit_IsOwnerAllowedToSee;
Procedure GameUnit_LOS_PlayerSeeUnit_EpilogCode_Exit;
Procedure GameUnit_LOS_PlayerSeeUnit_EpilogCode_Retry;
Procedure GameUnit_LOS_PlayerSeeUnit_EpilogCode_Test;
Procedure GameUnit_LOS_PlayerSeeUnit_EpilogCode_FinalCheck;

Procedure GetCodeInjections( PluginData : TPluginData );

implementation
uses
  LOS_extensions,
  TADemoConsts,
  TA_MemoryConstants;

Procedure GetCodeInjections( PluginData : TPluginData );
begin

PluginData.MakeNOPReplacement( State_LOS_PlayerSeeUnit,
                               'GameUnit_LOS_Sight_PlayerSeeUnit_CallSite',
                               $48BC3D, $13 );

PluginData.MakeRelativeJmp( State_LOS_PlayerSeeUnit,
                 'GameUnit_LOS_PlayerSeeUnit_IsOwnerAllowedToSee',
                 @GameUnit_LOS_PlayerSeeUnit_IsOwnerAllowedToSee,
                 $465AD4);

end;

Procedure GameUnit_LOS_PlayerSeeUnit_IsOwnerAllowedToSee;

label
  CanSeeUnit;
asm

  push edi

  xor ecx, ecx;

  mov PlayerSeeUnit_p_Unit, ebx;
  mov PlayerSeeUnit_PlayerPtr, esi;
  mov PlayerSeeUnit_TestPlayer, ecx;

  mov eax, [TADynmemStructPtr]
  mov cl, [eax+TTADynMemStruct.cViewPlayerID]
  mov PlayerSeeUnit_ViewPlayerPlSeeU, ecx;

  xor eax, eax
  mov al, [esi+TPlayerStruct.cPlayerIndex]
  mov ecx, [ebx+TUnitStruct.p_Owner]
  cmp byte [eax+ecx+TPlayerStruct.cAllyFlagArray], 0
  jnz CanSeeUnit

  push $465AE8
  call PatchNJump;
CanSeeUnit:

  mov eax, 1;
  jmp GameUnit_LOS_PlayerSeeUnit_EpilogCode_Exit;
end;

Procedure GameUnit_LOS_PlayerSeeUnit_EpilogCode_Test;

label
  DoProlog, KeepLooping;
asm
  mov eax, ecx;

  test eax, eax
  jz GameUnit_LOS_PlayerSeeUnit_EpilogCode_Retry;
  jmp GameUnit_LOS_PlayerSeeUnit_EpilogCode_Exit;
end;

Procedure GameUnit_LOS_PlayerSeeUnit_EpilogCode_Retry;

label
  CanSeeUnit,
  CanNotSeeUnit,
  TestPlayerLOS,
  TryNextPlayer_NextValue,
  TryNextPlayer_Condition;
asm

  mov ebx, PlayerSeeUnit_p_Unit;

  mov edi, PlayerSeeUnit_ViewPlayerPlSeeU
  mov ecx, [ebx+TUnitStruct.p_Owner]
  cmp byte [edi+ecx+TPlayerStruct.cAllyFlagArray], 0
  jnz CanSeeUnit

  mov ebp, PlayerSeeUnit_TestPlayerPlSeeU;
  jmp TryNextPlayer_Condition;
TryNextPlayer_NextValue:

  inc ebp;

TryNextPlayer_Condition:
  cmp ebp, $A;
  jnb CanNotSeeUnit;

  cmp byte [ebp+ecx+TPlayerStruct.cAllyFlagArray], 0
  jz TryNextPlayer_NextValue

  cmp byte [ecx+TPlayerStruct.cPlayerIndex], bl
  jnz TryNextPlayer_NextValue

  mov PlayerSeeUnit_TestPlayerPlSeeU, ebp;

  mov eax, ebp
  mov ecx, type TPlayerStruct
  mul ecx;
  mov ecx, [TADynmemStructPtr];
  lea ecx, [ecx+TTADynMemStruct.Players];
  add eax, ecx;

  mov esi, PlayerSeeUnit_PlayerPtr;
  cmp eax, esi
  jz TryNextPlayer_NextValue;

  mov esi, eax;

  mov eax, [esi]
  test eax, eax
  jz TryNextPlayer_NextValue;
TestPlayerLOS:

  inc ebp;
  mov PlayerSeeUnit_TestPlayerPlSeeU, ebp;

  push $465AFD
  call PatchNJump;
CanSeeUnit:

  mov eax, 1;

  mov esi, PlayerSeeUnit_PlayerPtr;
  jmp GameUnit_LOS_PlayerSeeUnit_EpilogCode_Exit;
CanNotSeeUnit:
  mov PlayerSeeUnit_TestPlayerPlSeeU, ebp;

  xor eax, eax;

  mov esi, PlayerSeeUnit_PlayerPtr;
  jmp GameUnit_LOS_PlayerSeeUnit_EpilogCode_Exit;
end;

Procedure GameUnit_LOS_PlayerSeeUnit_EpilogCode_FinalCheck;

label
  CheckNextPlayer_value,
  CheckNextPlayer_Condition,

  CheckReturn,
  DoReturn;
asm
  test ecx, ecx
  jnz DoReturn

  xor edi, edi;
  jmp CheckNextPlayer_Condition;
CheckNextPlayer_value:
  inc edi;
CheckNextPlayer_Condition:

  cmp ebp, $A;
  jnb DoReturn;

  push eax;
  push edx;
  mov     cl, [ebx+TTADynMemStruct.cViewPlayerID]
  shl     edx, cl
  and     eax, edx
  neg     eax
  sbb     eax, eax
  xor     ecx, ecx
  neg     eax
  test    eax, eax
  setnz   cl
  mov     eax, ecx
  pop edx;
  pop eax;

  test ecx, ecx
  jnz DoReturn
  jmp CheckNextPlayer_value;

DoReturn:
  mov     eax, ecx;
  add     esp, $0C;
  ret    8;
end;

Procedure GameUnit_LOS_PlayerSeeUnit_EpilogCode_Exit;

asm

  pop edi
  pop esi
  pop ebp
  pop ebx
  add esp, $0C
  ret 8
end;

end.
