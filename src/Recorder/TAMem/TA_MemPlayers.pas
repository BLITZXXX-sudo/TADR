unit TA_MemPlayers;

interface
uses
  dplay, TA_MemoryStructures;

type
  TAPlayer = class
  public
    class Function GetDPID(Player: PPlayerStruct) : TDPID;
    class Function GetPlayerByIndex(playerIndex: Byte) : PPlayerStruct;
    class Function GetPlayerPtrByDPID(playerPID: TDPID) : PPlayerStruct;
    class Function GetPlayerByDPID(playerPID: TDPID) : Byte;

    class function PlayerIndex(Player: PPlayerStruct) : Byte;
    class Function PlayerController(Player: PPlayerStruct) : TTAPlayerController;
    class Function PlayerSide(Player: PPlayerStruct) : TTAPlayerSide;
    class Function PlayerSideIdx(Player: PPlayerStruct) : Byte;
    class function PlayerLogoIndex(Player: PPlayerStruct) : Byte;
    class function PlayerSideLogoSequence(Player: PPlayerStruct): PGAFSequence;

    class function GetShareRadar(Player: PPlayerStruct) : Boolean;
    class Procedure SetShareRadar(Player: PPlayerStruct; ANewState: Boolean);

    class function IsKilled(Player: PPlayerStruct) : Boolean;
    class function IsActive(Player: PPlayerStruct) : Boolean;

    class function GetAlliedState(Player1: PPlayerStruct; Player2: Byte) : Boolean;
    class Procedure SetAlliedState(Player1: PPlayerStruct; Player2: Byte; ANewState: Boolean);
  end;

implementation
uses
  TA_MemoryConstants,
  TA_MemoryLocations;

// -----------------------------------------------------------------------------
// TAPlayer
// -----------------------------------------------------------------------------

class Function TAPlayer.GetDPID(Player: PPlayerStruct) : TDPID;
begin
  Result := 0;
  if Player = nil then Exit;
  Result := Player.lDirectPlayID;
end;

class Function TAPlayer.GetPlayerByIndex(playerIndex : Byte) : PPlayerStruct;
begin
  Result := nil;
  if playerindex < MAXPLAYERCOUNT then
    Result := @TAData.MainStruct.PlayersExt[playerIndex];
end;

class Function TAPlayer.GetPlayerPtrByDPID(playerPID : TDPID) : PPlayerStruct;
var
  i : Integer;
begin
  Result := nil;
  for i := 0 to MAXPLAYERCOUNT - 1 do
  begin
    if TAData.MainStruct.PlayersExt[i].lDirectPlayID = playerPID then
    begin
      Result := @TAData.MainStruct.PlayersExt[i];
      Break;
    end;
  end;
end;

class Function TAPlayer.GetPlayerByDPID(playerPID : TDPID) : Byte;
var
  i : Integer;
begin
  Result := MAXPLAYERCOUNT;
  for i := 0 to MAXPLAYERCOUNT - 1 do
  begin
    if TAData.MainStruct.PlayersExt[i].lDirectPlayID = playerPID then
    begin
      Result := i + 1;
      Break;
    end;
  end;
end;

class Function TAPlayer.PlayerIndex(Player: PPlayerStruct) : Byte;
begin
  Result := 0;
  if Player = nil then Exit;
  Result := Player.cPlayerIndex;
end;

class Function TAPlayer.PlayerController(Player: PPlayerStruct) : TTAPlayerController;
begin
  Result := TTAPlayerController(0); // none of Player_LocalHuman/LocalAI/RemotePlayer
  if Player = nil then Exit;
  Result := Player.cPlayerController;
end;

class Function TAPlayer.PlayerSide(Player: PPlayerStruct) : TTAPlayerSide;
begin
  Result := TTAPlayerSide(0);
  if Player = nil then Exit;
  Result := TTAPlayerSide(Player.PlayerInfo.Raceside);
end;

class function TAPlayer.PlayerSideIdx(Player: PPlayerStruct): Byte;
begin
  Result := 0;
  if Player = nil then Exit;
  Result := Player.PlayerInfo.Raceside;
end;

class Function TAPlayer.PlayerLogoIndex(Player: PPlayerStruct) : Byte;
begin
  Result := 0;
  if Player = nil then Exit;
  Result := Player.PlayerInfo.PlayerLogoColor;
end;

class function TAPlayer.PlayerSideLogoSequence(Player: PPlayerStruct): PGAFSequence;
var
  PlayerSideIdx: Byte;
begin
  // Player=nil is handled by TAPlayer.PlayerSideIdx above (returns 0), so this
  // still resolves to a safe default sequence below rather than crashing.
  PlayerSideIdx := TAPlayer.PlayerSideIdx(Player);
  if PlayerSideIdx <= High(ExtraSideData) then
  begin
    if ExtraSideData[PlayerSideIdx].p_LogoGAF <> nil then
      Result := ExtraSideData[PlayerSideIdx].p_LogoGAF
    else
      Result := TAData.MainStruct.p_GafSequence_32xlogos;
  end else
    Result := TAData.MainStruct.p_GafSequence_32xlogos;
end;

Class function TAPlayer.GetShareRadar(Player: PPlayerStruct) : Boolean;
begin
  Result := False;
  if Player = nil then Exit;
  Result := PlayerState_ShareRadar in Player.PlayerInfo.SharedBits;
end;

Class Procedure TAPlayer.SetShareRadar(Player: PPlayerStruct; ANewState: Boolean);
begin
  if Player = nil then Exit;
  if ANewState then
    Include(Player.PlayerInfo.SharedBits, PlayerState_ShareRadar)
  else
    Exclude(Player.PlayerInfo.SharedBits, PlayerState_ShareRadar);
end;

Class function TAPlayer.IsKilled(Player: PPlayerStruct) : Boolean;
begin
  Result := False;
  if Player = nil then Exit;
  Result := Player.PlayerInfo.PropertyMask and $40 = $40;
end;

// NOTE (2026-07-22): root cause of the tplayx.dll+0x100454B0 "Global
// Exception Handler" crash (destroy a unit, then spawn another via the
// debug hotkey -> crash a moment later). Disassembly of the live DLL
// showed the fault is a nil dereference at "cmp dword ptr [edx], 0"
// inside this exact function (IsActive reads Player.lPlayerActive, the
// struct's first field, at offset 0 - hence the "read address 0x0"
// access violation when Player itself is nil).
//
// Traced the caller chain via COB_extensions.pas: the PLAYER_ACTIVE (and
// sibling PLAYER_TYPE/PLAYER_SIDE/PLAYER_KILLS/PLAYER_ECONOMY/
// UNIT_IN_PLAYER_LOS/POSITION_IN_PLAYER_LOS) COB extension handlers call
// TAPlayer.GetPlayerByIndex(arg1) with arg1 coming straight from a COB
// script argument (e.g. a "get PLAYER_ACTIVE, <expr>" call), then
// immediately dereference the result. GetPlayerByIndex only returns
// non-nil for index 0..MAXPLAYERCOUNT (0..10 - the Players array has an
// 11th slot), so any script that passes an out-of-range value (a
// mis-computed owner/player id, a -1 "none" sentinel truncated to a
// Byte = 255, etc.) gets nil back, which every one of these TAPlayer
// accessors then dereferenced unconditionally. Since script arguments
// are effectively untrusted input, the accessors need to be nil-safe on
// their own rather than relying on every call site to pre-check -
// hence the nil guards added throughout this unit.
Class function TAPlayer.IsActive(Player: PPlayerStruct) : Boolean;
begin
  Result := False;
  if Player = nil then Exit;
  Result := Player.lPlayerActive <> 0;
end;

class function TAPlayer.GetAlliedState(Player1: PPlayerStruct; Player2: Byte) : Boolean;
begin
  Result := False;
  if (Player1 = nil) or
     (Player2 >= MAXPLAYERCOUNT) then
    Exit;
  Result := Player1.cAllyFlagArray[Player2] <> 0;
end;

class Procedure TAPlayer.SetAlliedState(Player1: PPlayerStruct; Player2: Byte; ANewState: Boolean);
begin
  if (Player1 = nil) or
     (Player2 >= MAXPLAYERCOUNT) then
    Exit;
  Player1.cAllyFlagArray[Player2] := BoolValues[ANewState];
end;

end.
