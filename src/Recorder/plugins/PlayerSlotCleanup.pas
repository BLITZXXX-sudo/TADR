unit PlayerSlotCleanup;
{
Clears cPlayerController (+0x73) when a player is removed.

THE BUG (stock Cavedog, verified byte-identical in TotalA.exe,
TA_11P.exe, TA_16P.exe and TA_16P_NETQ.exe):

  Player_Remove @ 0x00452D00 clears three fields:
      [ESI+0x00] lPlayerActive  = 0
      [ESI+0x04] lDirectPlayID  = -1
      [ESI+0x0C]                = 0
  but it NEVER clears [ESI+0x73] cPlayerController.

  Across ~80 accesses to +0x73 in the whole exe there is exactly ONE
  write - Network_Add_Player_Remote @ 0x00450B16 setting it to 3.
  Nothing ever sets it back to 0.

  The two functions that decide "is this slot real" test ONLY +0x73:

      PLAYERS_Index2DPlayID:  if (+0x73 <> 0) return lDirectPlayID
      DirectID2PlayerAry:     if (+0x73 =  0) skip else compare DPID

  So after ANY removal the slot still reads as occupied:

    in-game path  -> +0x73 set, DPID = -1     -> "present but invalid"
                                                 = the RED SLOTS
    lobby path    -> +0x73 set, DPID = stale  -> DestroyPlayer called on
                                                 an ID DirectPlay already
                                                 dropped = the 48 failed
                                                 destroys seen in the logs

WHY 16 PLAYERS EXPOSES IT
  At 10 players slots recycle fast enough that Network_Add_Player_Remote
  overwrites +0x73 before anything notices. At 16 there is enough room
  for stale slots to persist, and DirectID2PlayerAry then returns its
  0x10 not-found sentinel, which HAPI_SendMessage and
  MultiplayerPlayerLost use as an array index without bounds checking.

THE FIX
  Re-implement the three original writes plus a fourth that zeroes
  +0x73. Purely additive - no existing branch is altered, so this
  cannot repeat the NetSend_Init Q11 failure mode.

  Splice site 0x00452E67, 20 bytes:
      c7 06 00 00 00 00        MOV [ESI], 0
      c7 46 04 ff ff ff ff     MOV [ESI+4], -1
      c7 46 0c 00 00 00 00     MOV [ESI+0xC], 0

  ESI holds the player-slot pointer throughout. LAB_00452E81 (the
  lobby-skip jump target) is AFTER this range, so it is untouched.
}
interface
uses
  PluginEngine;

Procedure OnInstall;
Procedure OnUninstall;

const
  State_PlayerSlotCleanup : boolean = true;

function GetPlugin : TPluginData;

implementation
uses
  sysutils,
  TADemoConsts,
  logging,
  TA_MemoryLocations;

Procedure OnInstall;
begin
end;

Procedure OnUninstall;
begin
end;

// ---------------------------------------------------------------------
// Replacement for the slot-clearing block at 0x00452E67.
// ESI = pointer to the player slot (TADynMemStruct + idx*0x14B + 0x3A000)
// ---------------------------------------------------------------------
procedure ClearSlotStub;
asm
  // original three writes
  mov dword ptr [esi],       $00000000   // lPlayerActive
  mov dword ptr [esi+$04],   $FFFFFFFF   // lDirectPlayID
  mov dword ptr [esi+$0C],   $00000000

  // THE FIX: mark the slot genuinely free.
  // PLAYERS_Index2DPlayID and DirectID2PlayerAry both key off this byte.
  mov byte  ptr [esi+$73],   $00         // cPlayerController

  // continue at the instruction after the block we replaced
  push $00452E7B;
  call PatchNJump;
end;

function GetPlugin : TPluginData;
begin
if IsTAVersion31 and State_PlayerSlotCleanup then
  begin
  result := TPluginData.create( true,
                                'Player Slot Cleanup',
                                State_PlayerSlotCleanup,
                                @OnInstall, @OnUnInstall );
  // 20 bytes replaced: 0x00452E67 .. 0x00452E7A
  // 5 for the jmp + 15 extra
  result.MakeRelativeJmp( State_PlayerSlotCleanup,
                          'Clear cPlayerController on remove',
                          @ClearSlotStub,
                          $00452E67,
                          15 );
  end
else
  result := nil;
end;

end.
