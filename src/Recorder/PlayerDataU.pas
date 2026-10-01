unit PlayerDataU;

interface
uses
  classes, DPlay, TA_MemoryStructures;

type
  TTAStatus = ( InBattleRoom, InLoading, InGame );
  TTAStatuses = set of TTAStatus;
  TALeaveState = ( PlayerLefted, PlayerDropped, PlayerKicked );
  TZeroIndexMeaning = (ZI_InvalidPlayer, ZI_HostPlayer, ZI_Everyone);
//  TSharedState = set of (Player1Allied,Player2Allied);
//Const
//  AlliedState : TSharedState = [Player1Allied,Player2Allied];

//type

  Tbuilding = record
    buildid     :word;
    posx        :smallint;
    posy        :smallint;
    hp          :word;
  end;


  PPacketMonitoring = ^TPacketMonitoring;
  TPacketMonitoring = record
    GoodPackets       : integer;
    Lostpackets       : integer;
    LastPacket        : longword;
    LatePacketLostHistory   : array [0..101] of boolean;
    PacketLostHistory       : array [0..11] of longword;
    PacketLostHistoryIndex  : integer;
    LossCount         : integer;
    MaxLoss           : integer;
  end;

  PPlayerEconomy = ^TPlayerEconomy;
  TPlayerEconomy = record
    LastTimeStamp     : longword;
    IncomeMetal       : single;
    IncomeEnergy      : single;
    SharedMetal       : single;
    SharedEnergy      : single;
    LastSharedMetal   : single;
    LastSharedEnergy  : single;
    LastTotalMetal    : single;
    LastTotalEnergy   : single;
    TotalSharedMetal  : single;
    TotalSharedEnergy : single;
  end;

  TPlayers = class;

  TPlayerData = class//record
    PlayerIndex : integer;
    Players : TPlayers;

    Name              : string;
    IP                : string;
    Id                : TDPID;
    Side              : byte;
    Color             : Byte;

    public
      LastTimeStamp     : longword;

      LastStatusMsg : string;
      // last time the player was heard from
      LastMsgTimeStamp           : longword;

      StartInfo : record
                  ID : longword;
                  X : word;
                  Y : word;
                  Z : word;
                  end;
    public
      Economy : TPlayerEconomy;
//      Procedure ShareMetal;

    public
      UnitsAliveCount   : Integer;

      PacketMonitoring : TPacketMonitoring;

    OtherCheats       : Integer;
    public
      VotedGo           : boolean;
      ClickedIn         : boolean;
    public
      GiveBase          : boolean;
      WarpDone          : Boolean;
      ReceivedBRSettings : boolean;
      CanParticipateInVote : boolean;
      UnpauseReady      : Boolean;
      CanTake           : Boolean;
      IsAllied          : boolean;
      SharingLos        : boolean;
      TakeUnit          : Longword;

    AlliedTo          : array [1..16] of boolean;

    IsFirstPlayerWithb3 : Boolean;
    // versioning support
    VersionDetected   : Boolean;
    InternalVersion   : Integer;
    EnemyChat         : boolean;
    RecConnect        : boolean;
    Uses_Rec2Rec_Notification : Boolean;
    ModInfo : TPlayerModInfo;

    HasBrokenRecorder : Boolean;
    HasWarnedOnUnitLimit : Boolean;
  protected
    procedure OnPlayerRemoved( Index : Integer );
  public
    constructor Create( const aName : string; aID : Longword );
  public
    Function IsSelf : boolean;
    Function IsServer : boolean;
  end;


  TPlayersData = array [1..10] of TPlayerData;
  TSendChatLocal_proc = procedure (s : string) of object;
  TPlayerRemovedEvent = procedure ( player : TPlayerData ) of object;
  TGetServerPlayerEvent = function : TPlayerData of object;

  TPlayers = class
  protected
    fSendChatLocal : TSendChatLocal_proc;
    fPlayerRemoved : TPlayerRemovedEvent;
    fGetServerPlayer : TGetServerPlayerEvent;
    fData : TList;
    fDeletedPlayers : TList;
    fEveryonePlayer : TPlayerData;
    fUnknownPlayer : TPlayerData;
    function GetData_( Index : Integer ) : TPlayerData;
    function getCount : Integer;
   public
    Constructor Create( aSendChatLocal : TSendChatLocal_proc;
                        aPlayerRemoved : TPlayerRemovedEvent;
                        aGetServerPlayer : TGetServerPlayerEvent);
    destructor Destroy; override;

    function ConvertId( id : TDPID; ZeroIndexMeaning : TZeroIndexMeaning; exceptOnNotFound : Boolean = true ) : Byte;
    function Convert( id : TDPID; ZeroIndexMeaning : TZeroIndexMeaning; exceptOnNotFound : Boolean = true) : TPlayerData;

    procedure Clear;

    function Add( const aName : string; aID : Longword ) : TPlayerData;
    procedure Remove( DplayID : TDPID; LeaveState : TALeaveState); overload;
    procedure Remove( player : TPlayerData; LeaveState : TALeaveState); overload;
    property Count : Integer read getCount;
    property Data[ Index : integer] : TPlayerData read GetData_; default;
    function Name( Index : Integer ) : string;  overload;
    class function Name( PlayerData : TPlayerData ) : string; overload;

    Property SendChatLocal : TSendChatLocal_proc read fSendChatLocal write fSendChatLocal;
    Property PlayerRemoved : TPlayerRemovedEvent read fPlayerRemoved write fPlayerRemoved;
    Property GetServerPlayer : TGetServerPlayerEvent read fGetServerPlayer write fGetServerPlayer;

    Property EveryonePlayer : TPlayerData read fEveryonePlayer;
    Property UnknownPlayer : TPlayerData read fUnknownPlayer;

    Property DeletedPlayers : TList read fDeletedPlayers;
  end; {TPlayers} 


function StatusToStr( TAStatus : TTAStatus ) : string;

function BoolToStr( a : boolean ) : string;

implementation
uses
  sysutils,
  idplay;

const
  // MKChatMem is a SHARED memory mapping co-owned by TDRAW.dll and
  // the exe, both of which have 10 slots compiled in. It CANNOT be
  // widened from this DLL - doing so shifts every field after
  // 'tastatus' by up to 456 bytes and corrupts both sides.
  CHATVIEWSLOTS = 10;
function BoolToStr( a : boolean ) : string;
begin
if a then
  result := 'true'
else
  result := 'false';
end;

function StatusToStr( TAStatus : TTAStatus ) : string;
begin
case TAStatus of
  InBattleRoom : Result := 'battle room';
  InLoading : Result := 'loading';
  InGame : Result := 'game';
else
  Result := IntToStr(ord(TAStatus));
end;
end; {StatusToStr}

// -----------------------------------------------------------------------------
// TPlayerData
// -----------------------------------------------------------------------------

constructor TPlayerData.Create( const aName : string; aID : Longword );
begin
Assert( aName <>  '' );
Name := aName;
ID := aID;
StartInfo.ID := High(longword);
ModInfo.ModID := -1;
end; {Create}

procedure TPlayerData.OnPlayerRemoved( Index : Integer );
var i : Integer;
begin
if (Index >=1) and (Index <=16) then
  begin
  ModInfo.ModID := -1;
  for i := Index to 15 do
    AlliedTo[i] := AlliedTo[i+1];
  AlliedTo[16] := False;
  end;
end; {OnPlayerRemoved}

Function TPlayerData.IsSelf : boolean;
begin
assert(self <> nil);
result := PlayerIndex = 1;
end;

Function TPlayerData.IsServer : boolean;
begin
assert(self <> nil);
result := self = players.GetServerPlayer;
end;

// -----------------------------------------------------------------------------
//   TPlayers
// -----------------------------------------------------------------------------

Constructor TPlayers.Create( aSendChatLocal : TSendChatLocal_proc;
                             aPlayerRemoved : TPlayerRemovedEvent;
                             aGetServerPlayer : TGetServerPlayerEvent);
begin
inherited Create;
fData := TList.Create;
fDeletedPlayers := TList.Create;
fSendChatLocal := aSendChatLocal;
fGetServerPlayer := aGetServerPlayer;
fPlayerRemoved := aPlayerRemoved;
assert(assigned(fGetServerPlayer));
if TMethod(fSendChatLocal).Code <> nil then
  assert(assigned(TMethod(fSendChatLocal).Data));
if TMethod(fGetServerPlayer).Code <> nil then
  assert(assigned(TMethod(fGetServerPlayer).Data));

fEveryonePlayer := TPlayerData.Create('Everyone', 0);
fEveryonePlayer.PlayerIndex := 0;

// Placeholder handed out instead of nil for a DPID we have never seen.
// TDPlay.packethandler guards FromPlayer in about six places and then
// dereferences it bare in forty more (.IsSelf, .Side, .StartInfo, .Name,
// .PlayerIndex ...), which is the +$0C access violation. Returning a real,
// inert object keeps those reads valid; PlayerIndex 0 keeps it out of the
// live roster and out of any "is this a real player" test.
fUnknownPlayer := TPlayerData.Create('<unknown>', High(Longword));
fUnknownPlayer.PlayerIndex := 0;
end; {Create}

destructor TPlayers.Destroy;
begin
Clear;
FreeAndNil( fEveryonePlayer );
FreeAndNil( fUnknownPlayer );
FreeAndNil( fData );
FreeAndNil( fDeletedPlayers );
inherited;
end; {Destroy}

procedure TPlayers.Clear;
var
  i : integer;
  player : TObject;
begin
if fData <> nil then
while fData.Count > 0 do
  begin
  i := fData.Count-1;
  player := fData[i];
  if player <> nil then
    begin
    fData[i] := nil;
    player.Free;
    end;
  fDeletedPlayers.Remove(player);
  fData.Delete(i);
  end;
if fDeletedPlayers <> nil then
while fDeletedPlayers.Count > 0 do
  begin
  i := fDeletedPlayers.Count-1;
  player := fDeletedPlayers[i];
  if player <> nil then
    begin
    fDeletedPlayers[i] := nil;
    player.Free;
    end;
  fDeletedPlayers.Delete(i);
  end;
end; {Clear}

function TPlayers.Add( const aName : string; aID : Longword ) : TPlayerData;
begin
result := TPlayerData.Create( aName, aID );
Result.PlayerIndex := fData.Add( result )+1;
Result.Players := self;
end; {Add}

procedure TPlayers.Remove( player : TPlayerData; LeaveState : TALeaveState);
var
  i : Integer;
  s : string;
  aPlayerCount : Integer;
begin
if Player <> nil then
  try
    if assigned(PlayerRemoved) then
      PlayerRemoved(Player);
    aPlayerCount := Count;
    if aPlayerCount > 16 then
      asm int 3 end;
    // update based on the player being removed
    for i := Player.PlayerIndex to aPlayerCount-1 do
      begin
      Data[i].OnPlayerRemoved( player.PlayerIndex );
      // chatview is a fixed 10-slot SHARED mapping: only shuffle inside it
      if (i >= 1) and (i < CHATVIEWSLOTS) then
        begin
        chatview^.playernames[i] := chatview^.playernames[i+1];
        chatview^.allies[i] := chatview^.allies[i+1];
        chatview^.deathtimes[i] := chatview^.deathtimes[i+1];
        chatview^.playerColors[i] := chatview^.playerColors[i+1];
        chatview^.yehaplayground[i] := chatview^.yehaplayground[i+1];

        chatview^.otherMapX[i] := chatview^.otherMapX[i+1];
        chatview^.otherMapY[i] := chatview^.otherMapY[i+1];
        end;
      end;
    // remove the player
    fData.Delete( player.PlayerIndex-1 );      
    // reset the player indexs
    for i := 0 to fData.Count-1 do
      TPlayerData(fData[i]).PlayerIndex := i+1;
    // zero out the last entry
    if (aPlayerCount >= 1) and (aPlayerCount <= CHATVIEWSLOTS) then
      begin
      for i := 1 to high(chatview^.playernames[aPlayerCount]) do
        chatview^.playernames[aPlayerCount][i] := #0;
      chatview^.allies[aPlayerCount] := 0;
      chatview^.deathtimes[aPlayerCount] := 0;
      chatview^.playerColors[aPlayerCount] := 0;
      chatview^.yehaplayground[aPlayerCount] := 0;
      chatview^.otherMapX[aPlayerCount] := -1;
      chatview^.otherMapY[aPlayerCount] := -1;
      end;


    case LeaveState of
      PlayerKicked  : s := ' rejected';
      PlayerDropped : s := ' dropped';
      PlayerLefted  : s := ' left';
    end;
    if assigned(fSendChatLocal) then
      SendChatLocal('player ' + player.Name + s)
  finally
    // TOMBSTONE, do not Free.
    // Convert() already searches fDeletedPlayers as a fallback, but nothing
    // ever populated it - so any packet still in flight for this DPID after
    // the removal fell through to "Result := nil" and was dereferenced at
    // +$0C (the IP field) inside TDPlay.packethandler -> access violation.
    // Keeping the object alive in the tombstone list makes those late packets
    // resolve to a real, inactive TPlayerData instead of nil.
    // The list is drained and freed in Clear/Destroy, so nothing leaks beyond
    // the lifetime of the TPlayers instance.
    if fDeletedPlayers <> nil then
      begin
      if fDeletedPlayers.IndexOf( player ) < 0 then
        begin
        player.PlayerIndex := 0;   // 0 = not in the live roster any more
        fDeletedPlayers.Add( player );
        // cap the tombstone list so a long game with lots of joins/leaves
        // cannot grow it without bound
        while fDeletedPlayers.Count > 64 do
          begin
          TPlayerData(fDeletedPlayers[0]).Free;
          fDeletedPlayers.Delete(0);
          end;
        end;
      end
    else
      player.Free;
  end
end;

procedure TPlayers.Remove( DplayID : TDPID;
                           LeaveState : TALeaveState );
var
  player : TPlayerData;
begin
Player := Convert( DplayID, ZI_Invalidplayer, False );
// Convert() also searches the tombstone list, so a duplicate/late "player
// left" for an already-removed DPID can hand us an entry that is no longer
// in fData. Removing it a second time would re-run the compaction with a
// bogus PlayerIndex of 0. Ignore it.
if (Player <> nil) and (Player.PlayerIndex >= 1) then
  Remove(player,LeaveState);
end; 

function TPlayers.getCount : Integer;
begin
result := fData.Count;
end; {getCount}

class function TPlayers.Name( PlayerData : TPlayerData ) : string;
var
  ReturnAddr: Pointer;
begin
if PlayerData = nil then
  Result := '<error>'
else if (PlayerData = nil) or (PlayerData.Name = '') then
  begin
  asm
    push eax;
    MOV EAX,[EBP+4];
    Mov ReturnAddr, EAX;
    pop eax;
  end;
  raise ETADR.Create('Referancing a non existant player ') at ReturnAddr
  end
else
  Result := PlayerData.Name
end;

function TPlayers.Name( Index : Integer ) : string;
var
  ReturnAddr: Pointer;
begin
if Index = 0 then
  Result := '<host>'
else if (fData = nil) or (Index < 1) or (Index > fData.Count) or
        (fData[Index-1] = nil) or (TPlayerData(fData[Index-1]).Name = '') then
  begin
  asm
    push eax;
    MOV EAX,[EBP+4];
    Mov ReturnAddr, EAX;
    pop eax;
  end;
  raise ETADR.Create('Invalid access to playerdata array: '+IntToStr(Index)) at ReturnAddr
  end
else
  Result := TPlayerData(fData[Index-1]).Name
end; {Name}

function TPlayers.GetData_( Index : Integer ) : TPlayerData;
var
  ReturnAddr: Pointer;
begin
assert( Self <> nil );
if Index = 0 then
  begin // host/everyone pseudo-id
  Result := GetServerPlayer;
  if Result <> nil then
    exit;
  end;  
try
if (Index <= 0) or
   (fdata = nil) or
   (Index > fdata.Count) or
   (fData[Index-1] = nil) or
   (TPlayerData(fData[Index-1]).Name = '') then
  begin
  asm
    push eax;
    MOV EAX,[EBP+4];
    Mov ReturnAddr, EAX;
    pop eax;
  end;
  raise ETADR.Create('Invalid access to playerdata array: '+IntToStr(Index)) at ReturnAddr;
  end;
except
  on e : ETADR do raise;
  else
    begin
    asm int 3 end;
    end;
end;
Result := fData[ Index-1];
end; {GetData_}

function TPlayers.Convert( id : TDPID; ZeroIndexMeaning : TZeroIndexMeaning;  exceptOnNotFound : Boolean = true) : TPlayerData;
var
  ReturnAddr : pointer;
  i :Integer;
begin
for i := fData.Count-1 downto 0 do
  begin
  Result := TPlayerData(fData[i]);
  if Result.Id = Id then
    Exit;
  end;
if Id = 0 then
  begin // host/everyone pseudo-id
  if ZeroIndexMeaning = ZI_HostPlayer then
    begin
    Result := GetServerPlayer;
    if Result <> nil then
      exit;
    end
  else if ZeroIndexMeaning = ZI_Everyone then
    begin
    result := everyoneplayer;
    exit;
    end;
  end;
for i := fDeletedPlayers.Count-1 downto 0 do
  begin
  Result := TPlayerData(fDeletedPlayers[i]);
  if Result.Id = Id then  
    Exit;
  end;  
if ExceptOnNotFound then
  begin
  asm
    PUSH EAX;
    MOV EAX,[EBP+4];
    MOV ReturnAddr, EAX;
    POP EAX;
  end;
  raise Exception.Create('Unknown player ID: '+IntToHex(id,8)) at ReturnAddr
  end
else
  Result := nil;
end; 

function TPlayers.ConvertId( id : TDPID;
                             ZeroIndexMeaning : TZeroIndexMeaning; 
                             exceptOnNotFound : Boolean = true) : byte;

var
  ReturnAddr : pointer;
  i :Integer;
  player : TPlayerData;
begin
for i := fData.Count-1 downto 0 do
  if TPlayerData(fData[i]).Id = Id then
    begin
    Result := i+1;
    Exit;
    end;
if Id = 0 then
  begin // host/everyone pseudo-id
  if ZeroIndexMeaning = ZI_HostPlayer then
    begin
    player := GetServerPlayer;
    if player <> nil then
      begin
      result := player.PlayerIndex;
      exit;
      end;
    end
  else if ZeroIndexMeaning = ZI_Everyone then
    begin
    result := EveryonePlayer.PlayerIndex;
    exit;
    end;
  end;
if ExceptOnNotFound then
  begin
  asm
    PUSH EAX;
    MOV EAX,[EBP+4];
    MOV ReturnAddr, EAX;
    POP EAX;
  end;
  raise Exception.Create('Unknown player ID: '+IntToHex(id,8)) at ReturnAddr
  end
else
  Result := 0;
end;

end.
