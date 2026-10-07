unit LOS_UpdateTables;

interface
uses
  PluginEngine;

type
  PLOS_Updates = ^TLOS_Updates;
  TLOS_Updates = packed record
    Player : pointer;
    LargeGrid : Pointer;
    UnitSightDistance : pointer;
    field_A : byte;
    field_B : byte;
    RecentDamageNStuff : pointer;
    XPos : longword;
    ZPos : longword;
    YPos : longword;
    unknown1 : longword;
    unknown2 : longword;
  end;

var
  LOS_Updates_PTR : PLOS_Updates;

  PlayerPtr : pointer;

  TestPlayer : longint;

Procedure GameUnit_LOS_Update_1_Start;
Procedure GameUnit_LOS_Update_1_Retry;

Procedure GameUnit_LOS_Update_2_Start;
Procedure GameUnit_LOS_Update_2_Retry;

Procedure GetCodeInjections( PluginData : TPluginData );

implementation
uses
  LOS_extensions,
  TADemoConsts,
  TA_MemoryConstants,
  TA_MemoryStructures;

Procedure GetCodeInjections( PluginData : TPluginData );
begin
PluginData.MakeRelativeJmp( State_LOS_UpdateTables,
                            'GameUnit_LOS_Update_1_Start',
                            @GameUnit_LOS_Update_1_Start ,
                            $481D63,
                            1);

PluginData.MakeRelativeJmp( State_LOS_UpdateTables,
                            'GameUnit_LOS_Update_1_Exit1',
                            @GameUnit_LOS_Update_1_Retry ,
                            $481FAF,
                            2);
PluginData.MakeRelativeJmp( State_LOS_UpdateTables,
                            'GameUnit_LOS_Update_1_Exit1',
                            @GameUnit_LOS_Update_1_Retry ,
                            $48207B,
                            2);

PluginData.MakeRelativeJmp( State_LOS_UpdateTables,
                            'GameUnit_LOS_Update_2_Start',
                            @GameUnit_LOS_Update_2_Start ,
                            $482283,
                            1);
PluginData.MakeRelativeJmp( State_LOS_UpdateTables,
                            'GameUnit_LOS_Update_2_Exit1',
                            @GameUnit_LOS_Update_2_Retry ,
                            $4824CF,
                            2);
PluginData.MakeRelativeJmp( State_LOS_UpdateTables,
                            'GameUnit_LOS_Update_2_Exit1',
                            @GameUnit_LOS_Update_2_Retry ,
                            $482597,
                            2);

end;

Procedure GameUnit_LOS_Update_1_Start;
asm
  mov LOS_Updates_PTR, ebx
  mov PlayerPtr, eax
  xor ecx, ecx
  mov TestPlayer, ecx;
  jmp GameUnit_LOS_Update_1_Retry;
end;

Procedure GameUnit_LOS_Update_1_Retry;
label
  CanSeeUnit,
  NoMoreAllies,
  TestPlayerLOS,
  TryNextPlayer_NextValue,
  TryNextPlayer_Condition,
  FinalExit,
  SkipChunk,
  DoLOSStuff,
  SkipRemotePlayerOptimization;
asm

  mov eax, PlayerPtr
  mov ecx, TestPlayer

  jmp TryNextPlayer_Condition;
TryNextPlayer_NextValue:

  inc ecx;

TryNextPlayer_Condition:
  cmp ecx, $A;
  jnb NoMoreAllies;

  cmp byte [eax+ecx+TPlayerStruct.cAllyFlagArray], 0
  jz TryNextPlayer_NextValue

  cmp byte [eax+TPlayerStruct.cPlayerIndex], cl
  jz TryNextPlayer_NextValue

  mov eax, ecx
  inc ecx
  mov TestPlayer, ecx

  mov ecx, type TPlayerStruct
  mul ecx;
  mov ecx, [TADynmemStructPtr];
  lea ecx, [ecx+TTADynMemStruct.Players];
  add eax, ecx

  cmp byte [eax], 0
  jnz DoLOSStuff

  mov ecx, TestPlayer

  jmp TryNextPlayer_Condition
DoLOSStuff:

  cmp byte ptr [eax+TPlayerStruct.cPlayerController], Player_RemotePlayer
  jnz SkipRemotePlayerOptimization

  mov ecx, ViewPlayer
  cmp cl, byte ptr [eax+TPlayerStruct.cPlayerIndex]
  jz SkipRemotePlayerOptimization

  mov eax, PlayerPtr
  mov ecx, TestPlayer

  jmp TryNextPlayer_Condition;
SkipRemotePlayerOptimization:

  xor edx, edx
  mov ecx, [TADynmemStructPtr];

  mov ebx, LOS_Updates_PTR
  mov [ebx], eax

  mov dl, [eax+TPlayerStruct.cPlayerIndex]
  mov al, dl

  cmp dl, al
  jnz SkipChunk
  and word ptr [ecx+TTADynMemStruct.TNTMemStruct.nLOS_Type], 0FFF7h
  or byte ptr [ecx+142F1h], 4

SkipChunk:

  push $481D8E
  call PatchNJump;
NoMoreAllies:

  cmp ecx, longword(-1)
  jz FinalExit;

  mov ecx, longword(-1)
  mov TestPlayer, ecx
  mov eax, PlayerPtr

  jmp DoLOSStuff;

FinalExit:
  pop     edi
  pop     esi
  pop     ebp
  pop     ebx
  add     esp, 38h
  ret   4
end;

Procedure GameUnit_LOS_Update_2_Start;
label
  SkipChunk;
asm
  mov LOS_Updates_PTR, ebx

  mov PlayerPtr, eax
  xor ecx, ecx
  mov TestPlayer, ecx;

  jmp GameUnit_LOS_Update_2_Retry;
end;

Procedure GameUnit_LOS_Update_2_Retry;
label
  CanSeeUnit,
  NoMoreAllies,
  TestPlayerLOS,
  TryNextPlayer_NextValue,
  TryNextPlayer_Condition,
  FinalExit,
  SkipChunk,
  DoLOSStuff,
  SkipRemotePlayerOptimization;
asm

  mov eax, PlayerPtr
  mov ecx, TestPlayer

  jmp TryNextPlayer_Condition;
TryNextPlayer_NextValue:

  inc ecx;

TryNextPlayer_Condition:
  cmp ecx, $A;
  jnb NoMoreAllies;

  cmp byte [eax+ecx+TPlayerStruct.cAllyFlagArray], 0
  jz TryNextPlayer_NextValue

  cmp byte [eax+TPlayerStruct.cPlayerIndex], cl
  jz TryNextPlayer_NextValue

  mov eax, ecx
  inc ecx
  mov TestPlayer, ecx

  mov ecx, type TPlayerStruct
  mul ecx;
  mov ecx, [TADynmemStructPtr];
  lea ecx, [ecx+TTADynMemStruct.Players];
  add eax, ecx

  cmp byte [eax], 0
  jnz DoLOSStuff

  mov ecx, TestPlayer

  jmp TryNextPlayer_Condition
DoLOSStuff:

  cmp byte ptr [eax+TPlayerStruct.cPlayerController], Player_RemotePlayer
  jnz SkipRemotePlayerOptimization

  mov ecx, ViewPlayer
  cmp cl, byte ptr [eax+TPlayerStruct.cPlayerIndex]
  jz SkipRemotePlayerOptimization

  mov eax, PlayerPtr
  mov ecx, TestPlayer

  jmp TryNextPlayer_Condition;
SkipRemotePlayerOptimization:

  xor edx, edx
  mov ecx, [TADynmemStructPtr];

  mov ebx, LOS_Updates_PTR
  mov [ebx], eax

  mov dl, [eax+TPlayerStruct.cPlayerIndex]
  mov al, dl

  cmp dl, al
  jnz SkipChunk
  and word ptr [ecx+TTADynMemStruct.TNTMemStruct.nLOS_Type], 0FFF7h
  or byte ptr [ecx+142F1h], 4

SkipChunk:

  push $4822AE
  call PatchNJump;
NoMoreAllies:

  cmp ecx, longword(-1)
  jz FinalExit;

  mov ecx, longword(-1)
  mov TestPlayer, ecx
  mov eax, PlayerPtr

  jmp DoLOSStuff;

FinalExit:

  mov esi, [TADynmemStructPtr]

  pop     edi
  pop     esi
  pop     ebp
  pop     ebx
  add     esp, 38h
  ret   4
end;

end.
