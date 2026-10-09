unit idplay;

interface
uses
  SyncObjs,
  Windows, sysutils, classes,
  DPlay, DPLobby,

  ListsU, CommandHandlerU, ConsoleTimer,

  TADemoConsts,
  TAMemManipulations,
  MemMappedDataStructure,
  TA_MemoryStructures,
  PlayerDataU,
  log2, statslogging,
  PacketBufferU;

var
  StartedFrom :string;
type
  ETADR = class(Exception);

  TTADRBattleroomState = record
    AutoPauseAtStart : Boolean;
    CommanderWarp : Byte;
    F1Disable : byte;
    SpeedLock : Boolean;
    FastSpeed : word;
    SlowSpeed : word;
    SpeedLockNative : Boolean;
    AIDifficulty : Byte;
  end;

  TDPlay = class ( TInterfacedObject, IDirectPlay,IDirectPlay2, IDirectPlay3)
  protected
    dp1 :IDirectPlay;
    dp3 :IDirectPlay3;
    cs : SyncObjs.TCriticalSection;
    hMemMap      :Cardinal;
    crcattempts  : integer;
  protected
    TAStatus     : TTAStatus;

    MaxUnits     : word;
    UnitStatus : array of record
                 LastDead : Cardinal;
                 Health : Integer;
                 DoneStatus : word;
                 UnitAlive : Boolean;
                 end;

    fBattleRoomState : TTADRBattleroomState;
    fBattleRoomStateUpdated : boolean;
    foldBattleRoomState : TTADRBattleroomState;

    Procedure SetAutoPauseAtStart( value : Boolean);
    Procedure SetCommanderWarp( value : Byte);
    Procedure SetF1Disable( value : byte);
    Procedure SetSpeedLock( value : Boolean);
    Procedure SetFastSpeed( value : word);
    Procedure SetSlowSpeed( value : word);
    Procedure SetSpeedLockNative( value : Boolean);
    Procedure SetAIDifficulty( value : Byte);
  public
    Property AutoPauseAtStart : Boolean read fBattleRoomState.AutoPauseAtStart write SetAutoPauseAtStart;
    Property CommanderWarp : Byte read fBattleRoomState.CommanderWarp write SetCommanderWarp;
    Property F1Disable : byte read fBattleRoomState.F1Disable write SetF1Disable;
    Property SpeedLock  : Boolean read fBattleRoomState.SpeedLock write SetSpeedLock;
    Property FastSpeed : word read fBattleRoomState.FastSpeed write SetFastSpeed;
    Property SlowSpeed : word read fBattleRoomState.SlowSpeed write SetSlowSpeed;
    Property SpeedLockNative : Boolean read fBattleRoomState.SpeedLockNative write SetSpeedLockNative;
    Property AIDifficulty : Byte read fBattleRoomState.AIDifficulty write SetAIDifficulty;
    procedure BroadcastExtraBattleRoomSettings(ToPlayer: TDPID);
    procedure BroadcastModInfo;
  protected

    fakecd       : boolean;
    fakewatch    : boolean;

    use3d        : boolean;
    auto3d       : boolean;

    EmitBuggyVersionWarnings : Boolean;

    compatibleTA : boolean;

    serverdir    : string;

  protected
    shareMapPos  : Boolean;
    OldMapX : Word;
    OldMapY : Word;
  protected

    NoRecording     : boolean;

    LastFlushTimeStamp : Longword;

    AutoRecording : boolean;
    RecordAuto : boolean;

    CreateTxtFile: boolean;

    IsRecording    : Boolean;

    starttime         : Longword;

    FileName          : string;
    StatsFileName     : string;
    RecordPlayerNames : Boolean;
    chatlog           : string;
    MapName           : string;
    demodir           : string;
    prevtime          : longword;

    NoFileName        : boolean;

    procedure createlogfile();
    procedure MakeAutoFileName;
    function fnRemoveInvalidChar(const sString: string) : String;
  protected
    fPlayers : TPlayers;
    fServerPlayer : TPlayerData;
    procedure OnRemovePlayer(player : TPlayerData);
    function GetServerPlayer : TPlayerData;

  public
    property ServerPlayer : TPlayerData read fServerPlayer write fServerPlayer;
    function ImServer : Boolean;
    property Players : TPlayers read fPlayers;
  protected
    procedure UnitCountChange(player: TPlayerData;amount: integer);
  protected
    fFixFacExps   : boolean;
    fProtectDT    : Boolean;
    fFixon        : Boolean;
    function GetFixFacExps : Boolean;
    function GetProtectDT : Boolean;
  public
    property FixFacExps : Boolean read GetFixFacExps Write fFixFacExps;
    property ProtectDT : Boolean read GetProtectDT Write fProtectDT;
    property FixOn : Boolean read fFixOn Write fFixOn;

    function facexpshandler( const s:string; from:TDPid;crccheck:boolean):string;
  protected
    sentpings    : array [0..101] of longword;
    pingtimer    : integer;
    logpl        : Boolean;
    procedure PacketLostHandler( TimeStamp :longword; player :TPlayerData);

  protected

    TakeStatus   : ( NoOneTaking,
                     OtherPlayerTaking_OldVersion_99b2, OtherPlayerTaking_OldVersion_Pre99b2,
                     OtherPlayerTaking, SelfTaking );
    TakePlayer : string;

    TakeRef : Integer;

    killunits    : string;

    procedure GetRandomMap (fname :string);

    function getRecorderStatusString : string;
  protected
    Commands : TCommands;

    PacketsToFilter : TArrayOfByte;

    {$I command_headers.inc}

    function PacketHandler(input : String;var FromPlayerDPID, ToPlayerDPID  : TDPID) :string;

    procedure ChatMsgHandler(s : string;from :TDPID);
  protected
    AlliedMarkerQueue : TStringQueue;
    MessageQueue    : TStringQueue;
    ChatSent : Boolean;
    ResourcesSent : boolean;

    procedure ProcessCRC(s:string);
    function GetGoodSource :integer;
  public

    procedure SendRecorderToRecorderMsg( MesageType : byte;
                                         const Data : string;
                                         EchoLocal : Boolean = False;
                                         Dest : TDPID = 0;
                                         Source : TDPID = TDPID(-1) );
    procedure SendRecorderToRecorderMsg2( const Msg : string;
                                          EchoLocal : Boolean = False;
                                          Dest : TDPID = 0;
                                          Source : TDPID = TDPID(-1) );

    procedure SendLocal( const msg :string; dest :TDPid; local, remote :boolean); overload;
    procedure SendLocal( const msg :string;  Source : TDPID; dest :TDPid; local, remote :boolean); overload;

    procedure SendChat( s : string; dest : TDPID = 0 );

    procedure SendChatLocal(s:string);

    procedure SendChatLocal2( s : string );

    procedure SendAlliedChat();
    procedure SendClipboard();

    procedure Broadcast_UnitWeapon(UnitID: Word; UnitWeaponIdx: Byte; WeaponID: Cardinal; Dest: TDPID = 0);
    procedure Broadcast_UnitGrantUnitInfo(UnitID: Word; ANewState: Byte; Dest: TDPID = 0);
    procedure Broadcast_UnitInfoEdit(UnitID: Word; FieldType: Cardinal; NewValue: Integer; Dest: TDPID = 0);
    procedure Broadcast_UnitInfoSwap(UnitID: Word; UnitInfoCrc: Cardinal; Dest: TDPID = 0);
    procedure Broadcast_NewUnitLocation(UnitID: Word; Position: TPosition; Dest: TDPID = 0);
    procedure Broadcast_EmitSFXToUnit(UnitID: Word; ToUnitID: Word; FromPieceIdx: SmallInt; SfxType: Byte; Dest: TDPID = 0);
    procedure Broadcast_SetNanolatheParticles(PosFrom: TPosition; PosTo: TNanolathePos; Reverse: Byte; Dest: TDPID = 0);
    procedure Broadcast_ExtraUnitState(UnitID: Word; FieldType: Cardinal; NewValue: Integer; Dest: TDPID = 0);

    procedure ExceptMessage;
    function OnException(E: Exception) : boolean;
  protected
    crash        : boolean;
    TADemoRecorderOff : boolean;
  protected
    ai : string;
    unitdata : string;

    procedure Handleunitdata(s : string; from , till :TDPID);
  protected
    MyCheats  : TTACheats;
    oldMyCheats  : TTACheats;
    procedure checkForCheats(CheatType: TCheatType);
  protected
    initbase     : array [0..UNITSPACE div 5] of Tbuilding;
    basecount    : integer;
    curbuilding  : integer;

    QuickBaseEnabled : Boolean;
    procedure dobase(till:TDPID);
    procedure initfastbase(namn:string);
    procedure initbuilding(num,id:word;xpos,ypos:smallint;hps:word);
  public

    NotViewingRecording :Boolean;
    IsInGame : Boolean;
    trCheckMemoryCheats: TConsoleTimer;
    trCheckProhibitedProcesses: TConsoleTimer;

    procedure OnFinishedCheatsCheck(CheatsFound: TTACheats);
    procedure OnMemoryCheckTick(Sender : TObject);
    procedure OnProcessCheckTick(Sender : TObject);
    procedure Exiting();
    procedure ResetRecorder;

    constructor Create (realdp :IDirectPlay);
    destructor Destroy; override;
 protected
    function SmartPak(c:string; const FromPlayer, ToPlayer : string) :string;

  protected
    forcego      : boolean;
    onlyunits    : boolean;
    datachanged  : boolean;
    RequireGuarantiedMsgDelivery : boolean;

    waitsync     : integer;

    notime       : boolean;
 public

    function AddPlayerToGroup(pidGroup: TDPID; pidPlayer: TDPID) : HResult; overload; stdcall;
    function Close: HResult; overload; stdcall;
    function CreatePlayer(var lppidID: TDPID; lpPlayerFriendlyName: PChar;
        lpPlayerFormalName: PChar; lpEvent: PHandle) : HResult; overload; stdcall;
    function CreateGroup(var lppidID: TDPID; lpGroupFriendlyName: PChar;
        lpGroupFormalName: PChar) : HResult; overload; stdcall;

    function DeletePlayerFromGroup(pidGroup: TDPID; pidPlayer: TDPID) : HResult; overload; stdcall;
    function DestroyPlayer(pidID: TDPID) : HResult; overload; stdcall;
    function DestroyGroup(pidID: TDPID) : HResult; overload; stdcall;
    function EnableNewPlayers(bEnable: BOOL) : HResult; stdcall;
    function EnumGroupPlayers(pidGroupPID: TDPID; lpEnumPlayersCallback:
        TDPEnumPlayersCallback; lpContext: Pointer; dwFlags: longword) : HResult; overload; stdcall;
    function EnumGroups(dwSessionID: longword; lpEnumPlayersCallback:
        TDPEnumPlayersCallback; lpContext: Pointer; dwFlags: longword) : HResult; overload; stdcall;
    function EnumPlayers(dwSessionId: longword; lpEnumPlayersCallback:
        TDPEnumPlayersCallback; lpContext: Pointer; dwFlags: longword) : HResult; overload; stdcall;
    function EnumSessions(const lpSDesc: TDPSessionDesc; dwTimeout: longword;
        lpEnumSessionsCallback: TDPEnumSessionsCallback; lpContext: Pointer;
        dwFlags: longword) : HResult; overload; stdcall;
    function GetCaps(const lpDPCaps: TDPCaps) : HResult; overload; stdcall;
    function GetMessageCount(pidID: TDPID; var lpdwCount: longword) : HResult; overload; stdcall;
    function GetPlayerCaps(pidID: TDPID; const lpDPPlayerCaps: TDPCaps) :
        HResult; overload; stdcall;
    function GetPlayerName(pidID: TDPID; lpPlayerFriendlyName: PChar;
        var lpdwFriendlyNameLength: longword; lpPlayerFormalName: PChar;
        var lpdwFormalNameLength: longword) : HResult; overload; stdcall;
    function Initialize(const lpGUID: TGUID) : HResult; overload; stdcall;
    function Open(const lpSDesc: TDPSessionDesc) : HResult; overload; stdcall;
    function Receive(var lppidFrom, lppidTo: TDPID; dwFlags: longword;
        var lpvBuffer; var lpdwSize: longword) : HResult; overload; stdcall;
    function SaveSession(lpSessionName: PChar) : HResult; stdcall;

    function SetPlayerName(pidID: TDPID; lpPlayerFriendlyName: PChar;
        lpPlayerFormalName: PChar) : HResult; overload; stdcall;

    function CreateGroup(var lpidGroup: TDPID; lpGroupName: PDPName;
        const lpData; dwDataSize: longword; dwFlags: longword) : HResult; overload; stdcall;
    function CreatePlayer(var lpidPlayer: TDPID; pPlayerName: PDPName;
        hEvent: THandle; lpData: Pointer; dwDataSize: longword; dwFlags: longword) :
        HResult; overload; stdcall;

    function EnumGroupPlayers(idGroup: TDPID; const lpguidInstance: TGUID;
        lpEnumPlayersCallback2: TDPEnumPlayersCallback2; lpContext: Pointer;
        dwFlags: longword) : HResult; overload; stdcall;
    function EnumGroups(lpguidInstance: PGUID; lpEnumPlayersCallback2:
        TDPEnumPlayersCallback2; lpContext: Pointer; dwFlags: longword) : HResult; overload; stdcall;
    function EnumPlayers(lpguidInstance: PGUID; lpEnumPlayersCallback2:
        TDPEnumPlayersCallback2; lpContext: Pointer; dwFlags: longword) : HResult; overload; stdcall;
    function EnumSessions(var lpsd: TDPSessionDesc2; dwTimeout: longword;
        lpEnumSessionsCallback2: TDPEnumSessionsCallback2; lpContext: Pointer;
        dwFlags: longword) : HResult; overload; stdcall;
    function GetCaps(var lpDPCaps: TDPCaps; dwFlags: longword) : HResult; overload; stdcall;
    function GetGroupData(idGroup: TDPID; lpData: Pointer; var lpdwDataSize: longword;
        dwFlags: longword) : HResult; stdcall;
    function GetGroupName(idGroup: TDPID; lpData: Pointer; var lpdwDataSize: longword) :
        HResult; stdcall;

    function GetPlayerAddress(idPlayer: TDPID; lpAddress: Pointer;
        var lpdwAddressSize: longword) : HResult; stdcall;
    function GetPlayerCaps(idPlayer: TDPID; var lpPlayerCaps: TDPCaps;
        dwFlags: longword) : HResult; overload; stdcall;
    function GetPlayerData(idPlayer: TDPID; lpData: Pointer; var lpdwDataSize: longword;
        dwFlags: longword) : HResult; stdcall;
    function GetPlayerName(idPlayer: TDPID; lpData: Pointer; var lpdwDataSize: longword)
        : HResult; overload; stdcall;
    function GetSessionDesc(lpData: Pointer; var lpdwDataSize: longword) : HResult; stdcall;

    function Open(var lpsd: TDPSessionDesc2; dwFlags: longword) : HResult; overload; stdcall;
    function Receive(var lpidFrom: TDPID; var lpidTo: TDPID; dwFlags: longword;
        lpData: Pointer; var lpdwDataSize: longword) : HResult; overload; stdcall;
    function Send(idFrom: TDPID; lpidTo: TDPID; dwFlags: longword; const lpData;
        lpdwDataSize: longword) : HResult; overload; stdcall;
    function SetGroupData(idGroup: TDPID; lpData: Pointer; dwDataSize: longword;
        dwFlags: longword) : HResult; stdcall;
    function SetGroupName(idGroup: TDPID; lpGroupName: PDPName;
        dwFlags: longword) : HResult; stdcall;
    function SetPlayerData(idPlayer: TDPID; lpData: Pointer; dwDataSize: longword;
        dwFlags: longword) : HResult; stdcall;
    function SetPlayerName(idPlayer: TDPID; lpPlayerName: PDPName;
        dwFlags: longword) : HResult; overload; stdcall;
    function SetSessionDesc(const lpSessDesc: TDPSessionDesc2; dwFlags: longword) :
        HResult; stdcall;

    function AddGroupToGroup(idParentGroup: TDPID; idGroup: TDPID) : HResult; stdcall;
    function CreateGroupInGroup(idParentGroup: TDPID; var lpidGroup: TDPID;
        lpGroupName: PDPName; lpData: Pointer; dwDataSize: longword;
        dwFlags: longword) : HResult; stdcall;
    function DeleteGroupFromGroup(idParentGroup: TDPID; idGroup: TDPID) :
        HResult; stdcall;
    function EnumConnections(const lpguidApplication: TGUID;
        lpEnumCallback: TDPEnumConnectionsCallback; lpContext: Pointer;
        dwFlags: longword) : HResult; stdcall;
    function EnumGroupsInGroup(idGroup: TDPID; const lpguidInstance: TGUID;
        lpEnumPlayersCallback2: TDPEnumPlayersCallback2; lpContext: Pointer;
        dwFlags: longword) : HResult; stdcall;
    function GetGroupConnectionSettings(dwFlags: longword; idGroup: TDPID;
        lpData: Pointer; var lpdwDataSize: longword) : HResult; stdcall;
    function InitializeConnection(var lpConnection: TDPLConnection; dwFlags: longword) :
         HResult; stdcall;
    function SecureOpen(const lpsd: TDPSessionDesc2; dwFlags: longword;
        const lpSecurity: TDPSecurityDesc; const lpCredentials: TDPCredentials)
        : HResult; stdcall;
    function SendChatMessage(idFrom: TDPID; idTo: TDPID; dwFlags: longword;
        const lpChatMessage: TDPChat) : HResult; stdcall;
    function SetGroupConnectionSettings(dwFlags: longword; idGroup: TDPID;
        const lpConnection: TDPLConnection) : HResult; stdcall;
    function StartSession(dwFlags: longword; idGroup: TDPID) : HResult; stdcall;
    function GetGroupFlags(idGroup: TDPID; var lpdwFlags: longword) : HResult; stdcall;
    function GetGroupParent(idGroup: TDPID; var lpidParent: TDPID) : HResult; stdcall;
    function GetPlayerAccount(idPlayer: TDPID; dwFlags: longword; var lpData;
        var lpdwDataSize: longword) : HResult; stdcall;
    function GetPlayerFlags(idPlayer: TDPID; var lpdwFlags: longword) : HResult; stdcall;
  end;

var
  chatview  : PMKChatMem;
  logsave   : TLog2 = nil;
  GlobalDPlay: TDPlay;

implementation

uses
 mmsystem, registry,
 shfolder,
 DPLobbyWrapper,
 uDebug, textdata,
 TextFileU, Logging,
 packet_old,
{$IFDEF ThreadLogging}
 threadlogging,
{$ENDIF}
 LOS_extensions,
 SpeedHack,
 TA_MemoryLocations,
 TA_MemPlayers,
 TA_MemUnits,
 TA_NetworkingMessages,
 TA_FunctionsU,
 InputHook,
 IniOptions,
 KeyboardHook,
 ModsList, GUIEnhancements, UnitActions,
 CloakOnly;

{$WARNINGS ON}
{$HINTS ON}
{$STACKFRAMES ON}

function Rec2RecExpectedSize(SubType: Byte): Integer;
begin
  case SubType of
    TANM_Rec2Rec_GameStateInfo : Result := SizeOf(TRec2Rec_GameStateInfo_Message);
    TANM_Rec2Rec_ModInfo : Result := SizeOf(TRec2Rec_ModInfo_Message);
    TANM_Rec2Rec_CheatDetection : Result := SizeOf(TRec2Rec_CheatsDetected_Message);
    TANM_Rec2Rec_Sharelos : Result := SizeOf(TRec2Rec_Sharelos_Message);
    TANM_Rec2Rec_UnitWeapon : Result := SizeOf(TRec2Rec_UnitWeapon_Message);
    TANM_Rec2Rec_UnitInfoSwap : Result := SizeOf(TRec2Rec_UnitInfoSwap_Message);
    TANM_Rec2Rec_UnitGrantUnitInfo : Result := SizeOf(TRec2Rec_UnitGrantUnitInfo_Message);
    TANM_Rec2Rec_UnitInfoEdit : Result := SizeOf(TRec2Rec_UnitInfoEdit_Message);
    TANM_Rec2Rec_NewUnitLocation : Result := SizeOf(TRec2Rec_NewUnitLocation_Message);
    TANM_Rec2Rec_EmitSFXToUnit : Result := SizeOf(TRec2Rec_EmitSFXToUnit_Message);
    TANM_Rec2Rec_SetNanolatheParticles : Result := SizeOf(TRec2Rec_SetNanolatheParticles_Message);
    TANM_Rec2Rec_ExtraUnitState : Result := SizeOf(TRec2Rec_ExtraUnitState_Message);
  else
    Result := -1;
  end;
end;

function Rec2RecPacketOK(const Pkt: string): Boolean;
var
  R: PRecorderToRecorderMessage;
  Need: Integer;
begin
  Result := False;
  if Length(Pkt) < SizeOf(TRecorderToRecorderMessage) then Exit;
  R := PRecorderToRecorderMessage(@Pkt[1]);
  if Length(Pkt) < SizeOf(TRecorderToRecorderMessage) + R^.MsgSize then Exit;
  Need := Rec2RecExpectedSize(R^.MsgSubType);
  if (Need >= 0) and (R^.MsgSize <> Need) then Exit;
  Result := True;
end;

function Rec2Rec_GetUnitName(pUnit: PUnitStruct): AnsiString;
var Info: PUnitInfo;
begin
  Result := '?';
  if (pUnit = nil) or (DWORD(pUnit) <= $10000) then Exit;
  if pUnit^.nUnitInfoID = 0 then Exit;
  Info := TAMem.UnitInfoId2Ptr(pUnit^.nUnitInfoID);
  if (Info <> nil) and (DWORD(Info) > $10000) then
    Result := AnsiString(Info^.szUnitName);
end;

const
  MaxTextMsgSize = 63;
procedure TDPlay.SendChat( s : string; dest :TDPID = 0 );
var
  s2 : string;
begin
TLog.Add(1,'"'+s+'"');
repeat
  if Length(s) > MaxTextMsgSize then
    begin
    s2 := Copy( s, 1, MaxTextMsgSize );
    Delete( s, 1, MaxTextMsgSize );
    end
  else
    begin
    s2 := s;
    s := '';
    end;
  while length(s2) < MaxTextMsgSize+1 do
    s2 := s2 + #$0;
  SendLocal( #5 + s2, dest, true, true);
until s = '';
end;

procedure TDPlay.SendChatLocal( s : string );
var
  s2 : string;
begin
TLog.add(1,'"'+s+'"');
repeat
  if Length(s) > MaxTextMsgSize then
    begin
    s2 := Copy( s, 1, MaxTextMsgSize );
    Delete( s, 1, MaxTextMsgSize );
    end
  else
    begin
    s2 := s;
    s := '';
    end;
  while length(s2) < MaxTextMsgSize+1 do
    s2 := s2 + #$0;
  SendLocal( #5 + s2, 0, true, false);
until s = '';
end;

procedure TDPlay.SendChatLocal2( s : string );
var
  s2 : string;
  I : Integer;
begin
repeat
  i := Pos( #10, s );
  if i <> 0 then
    begin
    s2 := Copy( s, 1, I-1 );
    Delete( s, 1, i );
    end
  else
    begin
    s2 := s;
    s := '';
    end;
  SendChatLocal( s2 );
until s = '';
end;

procedure TDPlay.SendLocal( const msg :string; dest :TDPid; local, remote :boolean);
begin
SendLocal( msg, TDPID(-1), dest, local, remote );
end;

procedure TDPlay.SendLocal( const msg :string; Source, dest :TDPid; local, remote :boolean);
var
  p :TPacket;
  s :String;

  sendID : TDPid;
begin
// BUGFIX: Guard against offline/single-player mode where Players list is empty
// In offline mode (single-player save), do NOT send network messages
if (Players.Count = 0) and (Source = TDPID(-1)) then
  begin
  TLog.add(4, 'SendLocal: Offline mode detected, skipping DirectPlay send');
  if local then
    MessageQueue.EnQueue( Msg );
  Exit;
  end;

if Source = TDPID(-1) then
  begin
  if Players.Count > 0 then
    sendID := Players[1].Id
  else
    begin
    // Offline mode: no valid player ID, use default
    sendID := TDPID(1);
    TLog.add(4, 'WARNING: SendLocal called in offline mode (empty Players list)');
    end;
  end
else
  sendID := Source;

if remote then
  begin
  p := TPacket.SJCreateNew (msg);
  try
    s := p.TaData;

    dp3.Send (sendID, dest, DPSEND_GUARANTEED, s[1], length(s));
  finally
    p.Free;
  end;
  end;

if local then
  begin
  MessageQueue.EnQueue( Msg );
  TLog.Add(6,'adding ' + datatostr2(msg));
  end;
end;

procedure TDPlay.SendAlliedChat();
var
  data : string;
begin
  if (chatview = nil) or (chatview^.toAlliesLength = 0) then
    Exit;
  data := '';
  SetLength( data, chatview^.toAlliesLength );
  move( chatview^.toAllies, data[1], chatview^.toAlliesLength );
  chatview^.toAlliesLength := 0;
  SendRecorderToRecorderMsg( TANM_Rec2Rec_MarkerData, data );
end;

procedure TDPlay.SendRecorderToRecorderMsg2( const Msg : string;
                                             EchoLocal : Boolean = False;
                                             Dest : TDPID = 0;
                                             Source : TDPID = TDPID(-1) );
var
  i : Integer;
  player : TPlayerData;

  c,s     :string;
  a,b     :integer;
begin
  if EchoLocal then
    Sendlocal( msg, Source, 0, True, False );
  if Dest = 0 then
    for i := 2 to Players.Count do
    begin
      player := Players[i];
      if player.RecConnect then
        Sendlocal( msg, Source, player.Id, false, True );
    end
  else
    Sendlocal( msg, Source, Dest, false, True );

if IsRecording then
  begin
  c := SmartPak( msg, Players.Name(1), Players.Name(1));
  if length(c)>1 then
    begin
    SetLength( s, 5 );
    a:=integer(timeGetTime);
    b:=a-integer(prevtime);
    prevtime:=a;
    if b<0 then
      b:=b+1000*60*60*24;
    s[3] := char(b and $ff);
    s[4] := char(b shr 8);

    if Source = TDPID(-1) then
      s[5] := char(1)
    else
      s[5] := char(Players.ConvertId(Source,ZI_Everyone,false));
    s:=s+c;
    s[1] :=char(length(s) and $ff);
    s[2] :=char(length(s) shr 8);
    logsave.add(s);
    end;
  end;
end;

procedure TDPlay.SendRecorderToRecorderMsg( MesageType : byte;
                                            const Data : string;
                                            EchoLocal : Boolean = False;
                                            Dest : TDPID = 0;
                                            Source : TDPID = TDPID(-1) );
var
  msg   : string;
  Rec2Rec : PRecorderToRecorderMessage;
begin
Assert( Length(Data) <= High(byte) );
SetLength( Msg, SizeOf(TRecorderToRecorderMessage)+Length(data));
Rec2Rec := PRecorderToRecorderMessage(@msg[1]);
Rec2Rec^.Marker := TANM_RecorderToRecorder;
Rec2Rec^.MsgSize := Byte(Length(Data));
Rec2Rec^.MsgSubType := MesageType;
if Length(Data) <> 0 then
  Move( Data[1], Msg[SizeOf(TRecorderToRecorderMessage)+1], Rec2Rec^.MsgSize );
SendRecorderToRecorderMsg2( Msg, EchoLocal, Dest, Source );
end;

procedure TDPlay.SendClipboard();
var
  s : string;
  i : integer;
  len : integer;
begin

if chatview = nil then Exit;

len := high(chatview^.chat)-low(chatview^.chat)+1;
setlength(s,len);
move(chatview^.chat,s[1],len);
i := pos(#0,s);
if i > 0 then
  setlength(s,i);
SendChatLocal2(s);
chatview^.NewData := 0;
end;

procedure TDPlay.Broadcast_UnitWeapon(UnitID: Word;
  UnitWeaponIdx: Byte; WeaponID: Cardinal; Dest: TDPID = 0);
var
  customPacket : AnsiString;
begin
  SetLength( customPacket, SizeOf(TRec2Rec_UnitWeapon_Message));
  Move( UnitID, customPacket[1], SizeOf(Word));
  Move( UnitWeaponIdx, customPacket[3], SizeOf(Byte));
  Move( WeaponID, customPacket[4], SizeOf(Cardinal));
  SendRecorderToRecorderMsg( TANM_Rec2Rec_UnitWeapon, customPacket, False, Dest );
end;

procedure TDPlay.Broadcast_UnitGrantUnitInfo(UnitID: Word;
  ANewState: Byte; Dest: TDPID = 0);
var
  customPacket : AnsiString;
begin
  SetLength( customPacket, SizeOf(TRec2Rec_UnitGrantUnitInfo_Message));
  Move( UnitID, customPacket[1], SizeOf(Word));
  Move( ANewState, customPacket[3], SizeOf(Byte));
  SendRecorderToRecorderMsg( TANM_Rec2Rec_UnitGrantUnitInfo, customPacket, False, Dest );
end;

procedure TDPlay.Broadcast_UnitInfoEdit(UnitID: Word;
  FieldType: Cardinal; NewValue: Integer; Dest: TDPID = 0);
var
  customPacket : AnsiString;
begin
  SetLength( customPacket, SizeOf(TRec2Rec_UnitInfoEdit_Message));
  Move( UnitID, customPacket[1], SizeOf(Word));
  Move( FieldType, customPacket[3], SizeOf(Cardinal));
  Move( NewValue, customPacket[7], SizeOf(Integer));
  SendRecorderToRecorderMsg( TANM_Rec2Rec_UnitInfoEdit, customPacket, False, Dest );
end;

procedure TDPlay.Broadcast_UnitInfoSwap(UnitID: Word;
  UnitInfoCrc: Cardinal; Dest: TDPID = 0);
var
  customPacket : AnsiString;
begin
  SetLength( customPacket, SizeOf(TRec2Rec_UnitInfoSwap_Message));
  Move( UnitID, customPacket[1], SizeOf(Word));
  Move( UnitInfoCrc, customPacket[3], SizeOf(Cardinal));
  SendRecorderToRecorderMsg( TANM_Rec2Rec_UnitInfoSwap, customPacket, False, Dest );
end;

procedure TDPlay.Broadcast_NewUnitLocation(UnitID: Word;
  Position: TPosition; Dest: TDPID = 0);
var
  customPacket : AnsiString;
begin
  SetLength( customPacket, SizeOf(TRec2Rec_NewUnitLocation_Message));
  Move( UnitID, customPacket[1], SizeOf(Word));
  Move( Position.X, customPacket[3], SizeOf(Integer));
  Move( Position.Z, customPacket[7], SizeOf(Integer));
  Move( Position.Y, customPacket[11], SizeOf(Integer));
  SendRecorderToRecorderMsg( TANM_Rec2Rec_NewUnitLocation, customPacket, False, Dest );
end;

procedure TDPlay.Broadcast_EmitSFXToUnit(UnitID: Word;
  ToUnitID: Word; FromPieceIdx: SmallInt; SfxType: Byte; Dest: TDPID = 0);
var
  customPacket : AnsiString;
begin
  SetLength( customPacket, SizeOf(TRec2Rec_EmitSFXToUnit_Message));
  Move( UnitID, customPacket[1], SizeOf(Word));
  Move( ToUnitID, customPacket[3], SizeOf(Word));
  Move( FromPieceIdx, customPacket[5], SizeOf(SmallInt));
  Move( SfxType, customPacket[7], SizeOf(Byte));
  SendRecorderToRecorderMsg( TANM_Rec2Rec_EmitSFXToUnit, customPacket, False, Dest );
end;

procedure TDPlay.Broadcast_SetNanolatheParticles(PosFrom: TPosition;
  PosTo: TNanolathePos; Reverse: Byte; Dest: TDPID = 0);
var
  customPacket : AnsiString;
begin
  SetLength( customPacket, SizeOf(TRec2Rec_SetNanolatheParticles_Message));
  Move( PosFrom, customPacket[1], SizeOf(TPosition));
  Move( PosTo, customPacket[13], SizeOf(TNanolathePos));
  Move( Reverse, customPacket[37], SizeOf(Byte));
  SendRecorderToRecorderMsg( TANM_Rec2Rec_SetNanolatheParticles, customPacket, False, Dest );
end;

procedure TDPlay.Broadcast_ExtraUnitState(UnitID: Word;
  FieldType: Cardinal; NewValue: Integer; Dest: TDPID = 0);
var
  customPacket : AnsiString;
begin
  SetLength( customPacket, SizeOf(TRec2Rec_ExtraUnitState_Message));
  Move( UnitID, customPacket[1], SizeOf(Word));
  Move( FieldType, customPacket[3], SizeOf(Cardinal));
  Move( NewValue, customPacket[7], SizeOf(Integer));
  SendRecorderToRecorderMsg( TANM_Rec2Rec_ExtraUnitState, customPacket, False, Dest );
end;

procedure TDPlay.OnMemoryCheckTick(Sender : TObject);
begin
  trCheckMemoryCheats.Enabled:= False;
  CheckForCheats(ctMemory);
  trCheckMemoryCheats.Enabled:= True;
end;

procedure TDPlay.OnProcessCheckTick(Sender : TObject);
begin
  if not trCheckProhibitedProcesses.FirstTick then
  begin
    trCheckProhibitedProcesses.FirstTick := True;
    Exit;
  end;
  trCheckProhibitedProcesses.Enabled:= False;
  CheckForCheats(ctProcesses);
  trCheckProhibitedProcesses.Enabled:= True;
end;

procedure TDPlay.CheckForCheats(CheatType: TCheatType);
begin
{$IFNDEF Debug}
TAMemManipulations.CheckForCheats(CheatType);
{$ELSE}
MyCheats := 0;
{$ENDIF}
end;

procedure TDplay.OnFinishedCheatsCheck(CheatsFound: TTACheats);
begin
  MyCheats:= CheatsFound;
  if chatview <> nil then
    chatview^.myCheats := MyCheats;
end;

procedure TDPlay.GetRandomMap (fname :string);
var
  maps  :TStringList;
  mf    :TextFile;
  state :integer;
  st    :string;
  nr    :integer;
  part  :string;
  error :integer;
  tot   :integer;
  i     :integer;
begin
  fname := Trim (fname);
  if fname = '' then
    fname := 'maps.txt';

  maps := TStringlist.create;
  try
  if not FileExists (fname) then
  begin
    SendChat( 'Unable to open file ' + fname);
    exit;
  end;

  AssignFile (mf, fname);
  Reset (mf);
  try
  state := 0;
  tot := 0;

  while not Eof (mf) do
  begin
    Readln (mf, st);
    st := Trim (st);
    If length (st) = 0 then
      continue;
    if st[1] = ';' then
      continue;

    case state of
      0  :begin
            if st[1] = '+' then
              state := 1;
          end;
      1  :begin
            part := Copy (st, 1, Pos (' ', st) - 1);
            Val (part, nr, error);
            if error <> 0 then
              state := 0;
            if st[1] = '+' then
              state := 1;

            if error = 0 then
            begin
              maps.AddObject (Copy (st, Pos (' ', st) + 1, 500), pointer (nr));
              tot := tot + nr;
            end;
          end;
    end;
  end;

  if maps.count = 0 then
  begin
    SendChat( 'Could not find any map names to pick from');
    SendChat( 'Used filename: ' + fname);
    exit;
  end;

  nr := Random (tot);
  error := 0;
  st := 'none!! should not happen heh';
  for i := 0 to maps.count - 1 do
  begin
    inc (error, integer(maps.Objects [i]));
    if nr < error then
    begin
      st := maps.strings [i];
      break;
    end;
  end;

  SendChat( 'The randomly selected map is:');
  SendChat (st + ' (Odds: ' + inttostr (integer(maps.Objects [i])) + ' out of ' + inttostr (tot) + ')');
  finally
    CloseFile (mf);
  end;
  finally
    maps.Free;
  end;
end;

procedure TDPlay.initbuilding(num,id:word;xpos,ypos:smallint;hps:word);
begin
  initbase[num].buildid:=id;
  initbase[num].posx:=xpos;
  initbase[num].posy:=ypos;
  initbase[num].hp:=hps;
end;

procedure TDPlay.initfastbase(namn:string);
var
  mf    :TextFile;
  state :integer;
  st    :string;
  nr    :integer;
  part  :string;
  error :integer;
  typ,posx,posy,hp :integer;
  i    :integer;
begin
  namn := Trim (namn);
  if namn='' then begin
    basecount:=15;
    initbuilding(1,$84,-100,140,2500);
    initbuilding(2,$16,100,140,2500);
    initbuilding(3,$3a,0,40,8000);
    initbuilding(4,$57,0,-60,1000);
    initbuilding(5,$0a,0,-120,4000);
    initbuilding(6,$44,-100,-200,2500);
    initbuilding(7,$08,100,-200,2800);
    initbuilding(8,$40,-220,160,2000);
    initbuilding(9,$40,220,160,2000);
    initbuilding(10,$40,-220,-160,2000);
    initbuilding(11,$40,220,-160,2000);
    initbuilding(12,$34,-190,160,1700);
    initbuilding(13,$34,190,160,1700);
    initbuilding(14,$34,-190,-160,1700);
    initbuilding(15,$34,190,-160,1700);

    initbuilding(16,$0112,-100,140,2500);
    initbuilding(17,$9b,100,140,2500);
    initbuilding(18,$bd,0,60,8000);
    initbuilding(19,$da,0,-60,1000);
    initbuilding(20,$cd,0,-120,4000);
    initbuilding(21,$ca,-100,-200,2500);
    initbuilding(22,$91,100,-200,2800);
    initbuilding(23,$c3,-220,160,2000);
    initbuilding(24,$c3,220,160,2000);
    initbuilding(25,$c3,-220,-160,2000);
    initbuilding(26,$c3,220,-160,2000);
    initbuilding(27,$b8,-190,160,1700);
    initbuilding(28,$b8,190,160,1700);
    initbuilding(29,$b8,-190,-160,1700);
    initbuilding(30,$b8,190,-160,1700);
    for i:=1 to Players.Count do
      Players[i].GiveBase := true;
    SendChat('Standard base initiated .baseoff to disable');
    exit;
  end;

  if not FileExists (namn) then
  begin
    SendChat( 'Unable to open file ' + namn);
    exit;
  end;

  AssignFile (mf, namn);
  Reset (mf);
  state := 0;

  while not Eof (mf) do
  begin
    Readln (mf, st);
    Trim (st);
    If length (st) = 0 then
      continue;
    if st[1] = ';' then
      continue;
    if state=0 then begin
      Val (st, basecount, error);
      if error<>0 then begin
        SendChat('Erroneous number of possible buildings');
        exit;
      end;
      state:=1;
      continue;
    end;

    i:= Pos (' ', st);
    part := Copy (st, 1, i-1);
    st:=Copy (st, i+1, 2000);
    Val (part, nr, error);

    if error<>0 then begin
      SendChat('Erroneous base file1');
      exit;
    end;

    i:= Pos (' ', st);
    part := Copy (st, 1, i-1);
    st:=Copy (st, i+1, 2000);
    Val (part, typ, error);

    if error<>0 then begin
      SendChat('Erroneous base file2');
      exit;
    end;

    i:= Pos (' ', st);
    part := Copy (st, 1, i-1);
    st:=Copy (st, i+1, 2000);
    Val (part, posx, error);

    if error<>0 then begin
      SendChat('Erroneous base file3');
      exit;
    end;

    i:= Pos (' ', st);
    part := Copy (st, 1, i-1);
    st:=Copy (st, i+1, 2000);
    Val (part, posy, error);

    if error<>0 then begin
      SendChat('Erroneous base file4');
      exit;
    end;

    i:= Pos (';', st);
    part := Copy (st, 1, i-1);
    st:=Copy (st, i+1, 2000);
    Val (part, hp, error);

    if error<>0 then begin
      SendChat('Erroneous base file5');
      exit;
    end;

    initbuilding(nr,typ,posx,posy,hp);
  end;
  for i:=1 to Players.Count do
    Players[i].GiveBase := true;
  SendChat('Fast base initiated from '+namn+' .baseoff to disable');
end;

procedure TDPlay.dobase(till:TDPID);
var
  holdstring :string;
  a          :integer;
  player : TplayerData;
begin
player := Players.Convert(till, ZI_InvalidPlayer, false);
if player = nil then Exit;
if (player.Side <> 0) or (player.Side <> 1) then
  begin
  SendChat('not arm/core');
  exit;
  end;
SendChat(player.Name+' just built a base');
for a := 1 to basecount do
  begin
  curbuilding:=a+player.Side*basecount;
  holdstring:=#9+'F'+#$00+'12'+#0#0#$20#$07#$00#$00#$02#$00#$00#$00#$10#$04#$00#$00#$E9+'t'+#$00#$00;
  setword(StrPtr(holdstring, 2),initbase[curbuilding].buildid);
  if player.IsSelf then
    setword(StrPtr(holdstring, 4),Players[2].StartInfo.ID+maxunits-1)
  else
    setword(StrPtr(holdstring, 4),Players[1].StartInfo.ID+maxunits-1);
  setword(StrPtr(holdstring, 8),player.StartInfo.X +initbase[curbuilding].posx);
  setword(StrPtr(holdstring, 12),player.StartInfo.Z );
  setword(StrPtr(holdstring, 16),player.StartInfo.Y +initbase[curbuilding].posy);
  if (player.StartInfo.X+initbase[curbuilding].posx>0) and
     (player.StartInfo.Y+initbase[curbuilding].posy>0) then
    begin
    if player.IsSelf then
      SendLocal( holdstring, 0, true, false)
    else
      SendLocal( holdstring, till, false, true);

    holdstring:=#$11#$05#$00#$01;
    if player.IsSelf then
      begin
      setword(StrPtr(holdstring, 2),Players[2].StartInfo.ID+maxunits-1);
      SendLocal( holdstring, 0, true, false);
      end
    else
      begin
      setword(StrPtr(holdstring, 2),Players[1].StartInfo.ID+maxunits-1);
      SendLocal( holdstring, till, false, true);
      end;

    holdstring:=#$14+'123456'+#$00#$00#$00#$00+'F'+#$01#$00#$00#$00#$00+'d'+#$7E#$00#$00#$00#$00#$00;
    setword(StrPtr(holdstring, 12),initbase[curbuilding].hp);
    if player.IsSelf then
      begin
      setword(StrPtr(holdstring, 2),Players[2].StartInfo.ID+maxunits-1);
      setlongword(StrPtr(holdstring, 4),Players[1].Id);
      SendLocal( holdstring, 0, true, false)
      end
    else
      begin
      setword(StrPtr(holdstring, 2),Players[1].StartInfo.ID+maxunits-1);
      setlongword(StrPtr(holdstring, 4),till);
      SendLocal( holdstring, till, false, true);
      end;

    end;
  end;
end;

procedure TDPlay.processcrc(s:string);
var
  cpoint       :^integer;
  s2           :string;
begin
  cpoint:=StrPtr(s, 5);
  s2:='Version '+inttostr(integer(s[2]))+'.'+inttostr(integer(s[3]));
  s2:=s2+'.'+inttostr(integer(s[4]))+' Checksum '+inttostr(cpoint^);
  SendChat(s2);
end;

procedure TDPlay.MakeAutoFileName;
var
  a : Integer;
begin
  filename := FormatDateTime('yyyy-mm-dd',Date);
  if IniSettings.demosprefix <> '' then
    filename := filename + ' - ' + IniSettings.demosprefix + ' - '
  else
    filename:= filename + ' - ';
  filename := filename + mapname;
  if RecordPlayerNames then
  begin
    filename := filename + ' - ';
    for a := 1 to Players.Count do
    begin
      filename := filename +Players[a].Name;
      if a < Players.Count then
        filename := filename + ', ';
    end;
  end;
  filename := RemoveInvalid (filename);

  if demodir <> '' then
  begin
    if IniSettings.modid > 0 then
    begin
      if (IniSettings.Name <> '') and
         (IniSettings.Version <> '') then
      begin
        filename := IncludeTrailingPathDelimiter(demodir) +
                    IncludeTrailingPathDelimiter(fnRemoveInvalidChar(IniSettings.name)) +
                    IncludeTrailingPathDelimiter(fnRemoveInvalidChar(IniSettings.Version)) +
                    filename;
      end else
        if (IniSettings.Name <> '') then
          filename := IncludeTrailingPathDelimiter(demodir) +
                      IncludeTrailingPathDelimiter(fnRemoveInvalidChar(IniSettings.name)) +
                      filename
        else
          filename := IncludeTrailingPathDelimiter(demodir) + filename;
    end else
      filename := IncludeTrailingPathDelimiter(demodir) + filename;
  end;

  if fileexists (filename + '.tad') then
  begin
    a := 1;
    repeat
      inc (a);
    until not fileexists (filename + ' - nr ' + inttostr (a) + '.tad');
    filename := filename + ' - nr ' + inttostr (a);
  end;
  filename := filename + '.tad';
end;

function TDPlay.getRecorderStatusString : string;
begin
result:='';
if (filename<>'') or ((AutoRecording or RecordAuto) and (filename<>'none'))then
  result:=result+'T'
else
  result:=result+'-';
if fixfacexps then
  result:=result+'T'
else
  result:=result+'-';
if protectdt then
  result:=result+'T'
else
  result:=result+'-';
{$IFDEF Debug}
result:=result+'D';
{$ENDIF}
end;

procedure TDPlay.ChatMsgHandler(s : string;from :TDPID);
var
  i : Integer;
  Sender : TPlayerData;
  handled : Boolean;
  Command, s2 : string;
  params : TStringList;
  CommandHandler : TCommandHandler;
begin
Sender := Players.Convert(from, ZI_HostPlayer);
if Sender.IsSelf then
  begin
  if assigned(chatview) and (chatview^.NewData = 0) then
    begin
    for i := 1 to length(s) do
      chatview^.chat[i] := s[i];
    chatview^.chat[length(s)+1] := #0;
    chatview^.NewData := 2;
    end;
  end;
i := pos('>',s);
if i>0 then
  begin
  s2 := PChar(copy(s,i+2,64));

  if (s2 <> '') and (from <> 0) then
    begin
    if (s2[1]= '.') then
    begin
    TLog.add( 2, 'Command:'+s2);
    i := pos(' ',s2)-1;
    if I = -1 then
      begin
      Command := LowerCase(Copy(s2,2,Length(s2)-1));
      s2 := '';
      end
    else
      begin
      Command := LowerCase(copy(s2,2,i-1));
      Delete( s2, 1, i+1 );
      end;
    handled := False;
    CommandHandler := Commands.LookUpCommand( Command );
    if CommandHandler <> nil then
      begin
      if CommandHandler.IsSelfOnly and not Sender.IsSelf then
        handled := True;
      if not handled and CommandHandler.IsServerOnly and not Sender.IsServer then
        begin
        if Sender.IsSelf then
          SendChatLocal( 'Only the host can use .'+Command);
        handled := True;
        end;
      if not handled and CommandHandler.RequireCompatibleTA and not CompatibleTA then
        begin
        if Sender.IsSelf then
          SendChatLocal( 'Sorry .'+Command+' only work with TA 3.1');
        handled := true;
        end;
      if not handled and CommandHandler.IsDevModeOnly and not TAData.DevMode then
        begin
        if Sender.IsSelf then
          SendChatLocal( 'Sorry .'+Command+' only work in development mode');
        handled := true;
        end;
      if not handled then
        begin
        params := TStringList.Create;
        try
          ParseParams( s2, params);
          if params.Count < CommandHandler.RequiredParams  then
            begin
            SendChatLocal( 'Require at least '+inttostr(CommandHandler.RequiredParams) + ' parameters for command .'+Command+' but found '+inttostr(params.Count) +' parameters' );
            SendChatLocal( 'Syntax is .'+Command +' '+CommandHandler.Syntax);
            handled := True;
            end;
          if not handled and not (TAStatus in CommandHandler.ValidCommandIn) then
            begin
            SendChatLocal( 'Sorry .'+Command+' is not valid in '+StatusToStr(TAStatus));
            handled := True;
            end;

          try
            if not handled then
              begin
              handled := CommandHandler.CommandHandler( Command, Sender, params );
              if CommandHandler.IsSelfOnly and Sender.IsSelf then
                datachanged := true;
              end;
          except
            on e : Exception do
              begin
              SendChat('Error in command handler:'+CommandHandler.Name);
              if OnException(e) then raise;
              end;
          end;
        finally
          params.Free;
        end;
        end;
      end;
    if not handled then
      begin
      if Sender.IsSelf then
        begin
        if uppercase(Command) = uppercase(Players[1].Name) then
          SendChat(Players[1].Name+' '+Players[1].Name+'!!')
        else if uppercase(Command) = uppercase(Copy(Players[1].Name,1,4)) then
          SendChat(Copy(Players[1].Name,1,4)+' '+Copy(Players[1].Name,1,4)+'!!')
        end;
      end;
    end
    end;

  if TAStatus = InGame then
    chatlog := chatlog+timetostr(now)+': ' + Trim(s) +#13+#10
  else if not datachanged then
   chatlog := chatlog + Trim(s) + #13;
  end;
end;

procedure TDPlay.UnitCountChange(player: TPlayerData;amount:integer);
begin
if player <> nil then
  begin
  if (player.UnitsAliveCount <= 0) and (amount < 0) then
    TLog.Add( 0, player.Name+' attempting to decrease player count below zero' )
  else
    Inc( player.UnitsAliveCount, amount );
  end;
end;

procedure TDPlay.PacketLostHandler( TimeStamp :longword; player :TPlayerData);
var
  i,i2   : integer;
  PacketMonitoring : PPacketMonitoring;
begin
assert(player <> nil);
if timestamp = $ffffffff then
  exit;
PacketMonitoring := @player.PacketMonitoring;
if PacketMonitoring^.LastPacket = 0 then
  PacketMonitoring^.LastPacket := timestamp;
if timestamp < PacketMonitoring^.LastPacket then
  begin
  i := PacketMonitoring^.LastPacket - timestamp;
  if i > 100 then
    begin
    SendChat('PL anomaly detected');
    i := 100;
    end;
  if i > 1 then
  for i2 :=2 to i do
    begin
    inc(PacketMonitoring^.LostPackets);
    if not PacketMonitoring^.LatePacketLostHistory[PacketMonitoring^.PacketLostHistoryIndex] then
      inc(PacketMonitoring^.LossCount);
    PacketMonitoring^.LatePacketLostHistory[PacketMonitoring^.PacketLostHistoryIndex] := true;
    inc(PacketMonitoring^.PacketLostHistoryIndex);
    if PacketMonitoring^.LossCount > PacketMonitoring^.MaxLoss then
      PacketMonitoring^.MaxLoss := PacketMonitoring^.LossCount;
    if (PacketMonitoring^.LossCount div 2)<10 then
      inc(PacketMonitoring^.PacketLostHistory[PacketMonitoring^.LossCount div 2])
    else
      inc(PacketMonitoring^.PacketLostHistory[10]);
    if PacketMonitoring^.PacketLostHistoryIndex > 100 then
      PacketMonitoring^.PacketLostHistoryIndex := 1;
    end;
  inc(PacketMonitoring^.GoodPackets);
  if PacketMonitoring^.LatePacketLostHistory[PacketMonitoring^.PacketLostHistoryIndex] then
    dec(PacketMonitoring^.LossCount);
  PacketMonitoring^.LatePacketLostHistory[PacketMonitoring^.PacketLostHistoryIndex] := false;
  inc(PacketMonitoring^.PacketLostHistoryIndex);
  if PacketMonitoring^.PacketLostHistoryIndex>100 then
    PacketMonitoring^.PacketLostHistoryIndex:=1;
  if (PacketMonitoring^.LossCount div 2)<10 then
    inc(PacketMonitoring^.PacketLostHistory[PacketMonitoring^.LossCount div 2])
  else
    inc(PacketMonitoring^.PacketLostHistory[10]);
  PacketMonitoring^.LastPacket := timestamp;
  end;
end;

procedure TDPlay.createlogfile();
var
  s,path    :string;
  crc     :string;
  a       :integer;
begin
if NoRecording then
  exit;

if ExtractFilePath(filename) = '' then
begin
  if IniSettings.modid > 0 then
  begin
    if (IniSettings.Name <> '') and
       (IniSettings.Version <> '') then
    begin
      filename := IncludeTrailingPathDelimiter(demodir) +
                IncludeTrailingPathDelimiter(fnRemoveInvalidChar(IniSettings.name)) +
                IncludeTrailingPathDelimiter(fnRemoveInvalidChar(IniSettings.Version)) +
                filename;
    end else
      if (IniSettings.Name <> '') then
      filename := IncludeTrailingPathDelimiter(demodir) +
                IncludeTrailingPathDelimiter(fnRemoveInvalidChar(IniSettings.name)) +
                filename
      else
        filename := IncludeTrailingPathDelimiter(demodir) + filename;
  end else
    filename := IncludeTrailingPathDelimiter(demodir) + filename;
end;

path := ExtractFilePath(filename);
try
  ForceDirectories( path );
except
  on e : EInOutError do
    LogException(e);
end;

if logsave <> nil then
  FreeAndNil( logsave );
try
  logsave := Tlog2.create(filename);
except
  on e : Exception do
    begin
    SendChat( 'Unable to create file with filename: ');
    SendChat( filename );
    LogException(e);
    exit;
    end;
end;

  if IniSettings.CreateStatsFile then
  begin
    StatsFileName:= ChangeFileExt(FileName, '.egs');
    if statslog <> nil then
      FreeAndNil( statslog );
    try
      statslog := TStatsLogging.create(StatsFileName);
    except
      on e : Exception do
      begin
        SendChat( 'Unable to prepare stats. ');
        LogException(e);
        exit;
      end;
    end;
  end;

  IsRecording := true;

  logsave.docrc := true;
  s:=#0#0;
  s:=s+'TA Demo'+#0;
  if IniSettings.modid > 0 then s:=s+#7#0 else s:=s+#5#0;
  s:=s+char(Players.Count);
  s:=s+char(maxunits and $ff)+char(maxunits div 256);
  s:=s+mapname;
  s[1] :=char(length(s) and $ff);
  s[2] :=char(length(s) shr 8);
  logsave.add(s);

  s:=#0#0#0#0#0#0;

  if IniSettings.modid > 0 then
    setLongword (StrPtr(s, 3), 5 + Players.Count)
  else
    setLongword (StrPtr(s, 3), 4 + Players.Count);
  s[1] :=char(length(s) and $ff);
  s[2] :=char(length(s) shr 8);
  logsave.add(s);

  s := #0#0;
  s := s + #2#0#0#0;
  s := s + chatlog;
  s[1] :=char(length(s) and $ff);
  s[2] :=char(length(s) shr 8);
  logsave.add(s);

  s := #0#0;
  s := s + #3#0#0#0;
  if IniSettings.modid > 0 then
  begin
    if IniSettings.version <> '' then
      s := s + IniSettings.version
    else
      s := s + 'Patch ' + GetTADemoVersion;
  end else
    s := s + GetTADemoVersion;

  s[1] :=char(length(s) and $ff);
  s[2] :=char(length(s) shr 8);
  logsave.add(s);

  s := #0#0;
  s := s + #4#0#0#0;
  s := s + datetostr (now);
  s[1] :=char(length(s) and $ff);
  s[2] :=char(length(s) shr 8);
  logsave.add(s);

  s := #0#0;
  s := s + #5#0#0#0;
  s := s + startedfrom;
  s[1] :=char(length(s) and $ff);
  s[2] :=char(length(s) shr 8);
  logsave.add(s);

  for a := 1 to Players.Count do
  begin
    s := #0#0;
    s := s + #6#0#0#0;
    s := s + SimpleCrypt(Players[a].IP );
    s[1] :=char(length(s) and $ff);
    s[2] :=char(length(s) shr 8);
    logsave.add(s);
  end;

  if IniSettings.modid > 0 then
  begin
  s := #0#0;
  s := s + #7#0#0#0;
  s := s + IntToStr(IniSettings.modid);
  s[1] :=char(length(s) and $ff);
  s[2] :=char(length(s) shr 8);
  logsave.add(s);
  end;

  for a:=1 to Players.Count do begin
    s:=#0#0;
    s:=s+char(Players[a].Color);
    s:=s+char(Players[a].Side);
    s:=s+char(a);
    s:=s+Players[a].Name;
    s[1] :=char(length(s) and $ff);
    s[2] :=char(length(s) shr 8);
    logsave.add(s);
  end;
  for a:=1 to Players.Count do begin
    s:=#0#0;
    s:=s+char(a);
    s:=s+Players[a].LastStatusMsg;
    s[1] :=char(length(s) and $ff);
    s[2] :=char(length(s) shr 8);
    logsave.add(s);
  end;
  s:=#0#0;
  s:=s+unitdata;

  crc := #$1a + #$9 + '    ' + #$ff#$ff#$ff#$ff + #$01#$00#$00#$00;
  setLongword (StrPtr(crc, 3), logsave.crc);
  s := s + crc;

  logsave.docrc := false;

  s[1] :=char(length(s) and $ff);
  s[2] :=char(length(s) shr 8);
  logsave.add(s);
end;

function TDPlay.fnRemoveInvalidChar(const sString: string) : String;
var
  sInvalidCharacters : array [1..10] of String;
  iIndex : Integer;
  sNewCharacter : String;
begin
  sNewCharacter := '';
  sInvalidCharacters[1] := ':';
  sInvalidCharacters[2] := '/';
  sInvalidCharacters[3] := '*';
  sInvalidCharacters[4] := '\';
  sInvalidCharacters[5] := '?';
  sInvalidCharacters[6] := '>';
  sInvalidCharacters[7] := '<';
  sInvalidCharacters[8] := '|';
  sInvalidCharacters[9] := '&';
  sInvalidCharacters[10] := '"';

  Result := sString;

  for iIndex := 1 to Length(sInvalidCharacters) do
  begin
    Result := StringReplace(Result, sInvalidCharacters[iIndex], sNewCharacter, [rfReplaceAll]);
  end;
end;

function TDPlay.SmartPak(c:string; const FromPlayer, ToPlayer : string) :string;
var
   tosave,s     : string;
   firstpak     : boolean;
begin
tosave:='';
firstpak:=true;
repeat
  s:=TPacket.split2(c,False,FromPlayer,ToPlayer);
  if s[1]=#$2c then
    begin
    if firstpak then
      begin
      firstpak:=false;
      tosave:=tosave+#$fe+copy(s,4,4);
      end;
    s:=copy(s,1,3)+copy(s,8,10000);
    s[1] :=#$fd;
    if ((s[2]=#$0b) and (s[3]=#$00)) then
      begin
      {$IFDEF Debug}
      if copy(s,4,4)<>#$ff#$ff#01#00 then
        begin
        SendChat('From '+FromPlayer+' to '+ ToPlayer+',Warning erroneous compression assumption');
        TLog.add(4,'Packet:'+datatostr(@s[1],length(s)));
        end;
      {$ENDIF}
      s:=#$ff;
      end;
    end
  else if onlyunits then
    s:='';
  tosave:=tosave+s;
until c='';
tosave := TPacket.Compress('xxx'+tosave);
tosave := tosave[1]+copy(tosave,4,10000);
Result := tosave;
end;

procedure TDPlay.HandleUnitData(s : string;from , till :TDPID);
var
  a         :integer;
  b         :^longword;
  notai     :boolean;
begin
if (Players.Convert(from, ZI_HostPlayer ,false) <> nil) and (Players.Convert(till, ZI_Everyone,false) <> nil) or
   (not ImServer) then
  begin
  if s[2]=#$0 then
    unitdata:='';
  if (s[2]=char($2)) or (s[2]=char($3)) then
    begin
    a:=1;
    while (a<length(unitdata)) do
      begin
      if ((unitdata[a+1]=s[2]) and (copy(unitdata,a+6,4)=copy(s,7,4))) then
        delete(unitdata,a,14);
      a:=a+14;
      end;
    unitdata:=unitdata+s;

    if (s[2] = #$3) and (s[11] = #$01) then
      begin
      b := StrPtr(s, 7);
      notai := false;
      case b^ of
        $6da73737 :ai := 'BAI';
        $62cc5579 :ai := 'Queller';

      else
        notai := true;
      end;

      if (not notai) and (s[12] = #$00) then
        ai := '';
      if (not notai) and (s[12] = #$01) and (AutoRecording) and
         (Players[1].ClickedIn) then
        SendChat( 'Warning: A custom AI (' + ai + ') is enabled');
      end;
    end;
  end;
end;

function TDPlay.facexpshandler( const s:string; from:TDPid;crccheck:boolean):string;
var
  wp     :^word;
  w      :word;
  TimeStamp : Longword;
  Sender : TPlayerData;
begin
Result := s;
TimeStamp := timeGetTime;
sender := Players.Convert(from,ZI_HostPlayer);
if (s[1]=#$0c) and Sender.IsSelf then
  begin
  wp := @s[2];
  w := wp^;
  Assert( (Integer(w) >= Low(UnitStatus)) and ( w <= High(UnitStatus) ) );
  UnitStatus[w].lastdead := TimeStamp;
  end
else if (s[1]=#$0b) and (not Sender.IsSelf) then
  begin
  wp := @s[2];
  w := wp^;
  Assert( (Integer(w) >= Low(UnitStatus)) and ( w <= High(UnitStatus) ) );
  if (UnitStatus[w].lastdead>TimeStamp-3000) and
     (UnitStatus[w].lastdead<TimeStamp+12*60*60*1000)then
    begin
    datachanged := true;
    Result := #$2a'd';

    end;
  end;
end;

function compare (Item1, Item2: Pointer): Integer;
begin
if TPlayerData(item1).Id < TPlayerData(item2).Id then
  Result := -1
else if TPlayerData(item1).Id > TPlayerData(item2).Id then
  Result := 1
else
  Result := 0;
end;

Procedure TDPlay.SetAutoPauseAtStart( value : Boolean);
begin
fBattleRoomStateUpdated := true;
fBattleRoomState.AutoPauseAtStart := value;
end;

Procedure TDPlay.SetCommanderWarp( value : Byte);
begin
fBattleRoomStateUpdated := true;
fBattleRoomState.CommanderWarp := value;
if assigned(chatview) then
  chatview^.commanderWarp := value;
end;

Procedure TDPlay.SetF1Disable( value : byte);
begin
fBattleRoomStateUpdated := true;
fBattleRoomState.F1Disable := value;
if assigned(chatview) then
  chatview^.F1Disable := value;
end;

Procedure TDPlay.SetSpeedLock( value  : Boolean);
begin
fBattleRoomStateUpdated := true;
fBattleRoomState.SpeedLock := value;
end;

Procedure TDPlay.SetFastSpeed( value : word);
begin
fBattleRoomStateUpdated := true;
fBattleRoomState.FastSpeed := value;
end;

Procedure TDPlay.SetSlowSpeed( value : word);
begin
fBattleRoomStateUpdated := true;
fBattleRoomState.SlowSpeed := value;
end;

Procedure TDPlay.SetSpeedLockNative( value  : Boolean);
begin
fBattleRoomStateUpdated := true;
fBattleRoomState.SpeedLockNative := value;
if Value then
begin
  notime := False;
  SpeedHack.LowerLimit := 10;
  SpeedHack.Upperlimit := 10;
  TAData.MainStruct.nTAGameSpeed := 10;
end else
begin
  notime := True;
  SpeedHack.LowerLimit := 0;
  SpeedHack.Upperlimit := 20;
end;
fBattleRoomState.SpeedLock := Value;
end;

Procedure TDPlay.SetAIDifficulty( value : Byte);
begin
fBattleRoomStateUpdated := true;
fBattleRoomState.AIDifficulty := value;
end;

procedure TDPlay.BroadcastExtraBattleRoomSettings(ToPlayer: TDPID);
var
  BattleRoomRecorderOptions  : string;
begin
  BattleRoomRecorderOptions:= '';
  SetLength( BattleRoomRecorderOptions, SizeOf(TRec2Rec_GameStateInfo_Message) );

  move( AutopauseAtStart, BattleRoomRecorderOptions[1], 1 );
  move( F1Disable, BattleRoomRecorderOptions[2], 1 );
  move( CommanderWarp, BattleRoomRecorderOptions[3], 1 );
  move( SpeedLock, BattleRoomRecorderOptions[4], 1 );
  move( SpeedLockNative, BattleRoomRecorderOptions[5], 1 );
  move( SlowSpeed, BattleRoomRecorderOptions[6], 1 );
  move( FastSpeed, BattleRoomRecorderOptions[7], 1 );
  move( AIDifficulty, BattleRoomRecorderOptions[8], 1 );

  if ToPlayer <> 0 then
    SendRecorderToRecorderMsg( TANM_Rec2Rec_GameStateInfo, BattleRoomRecorderOptions, False, ToPlayer, Players[1].ID )
  else
    SendRecorderToRecorderMsg( TANM_Rec2Rec_GameStateInfo, BattleRoomRecorderOptions, False );
end;

procedure TDPlay.BroadcastModInfo();
var
  sModInfo: String;
  PlayerIdx: Byte;
  Player: PPlayerStruct;
begin
  sModInfo:= '';
  SetLength( sModInfo, SizeOf(TRec2Rec_ModInfo_Message) );

  for PlayerIdx := 1 to Players.Count do
  begin
    Player := TAPlayer.GetPlayerPtrByDPID(Players[PlayerIdx].Id);
    if Player <> nil then
    begin
      if (Player.cPlayerController = Player_LocalHuman) or
         (Player.cPlayerController = Player_LocalAI) then
      begin
        sModInfo:= '';
        SetLength( sModInfo, SizeOf(TRec2Rec_ModInfo_Message) );
        move( Players[PlayerIdx].Id, sModInfo[1], 4 );
        move( LocalModInfo.ModID, sModInfo[5], 4 );
        move( LocalModInfo.ModMajorVer, sModInfo[9], 1 );
        move( LocalModInfo.ModMinorVer, sModInfo[10], 1 );
        SendRecorderToRecorderMsg( TANM_Rec2Rec_ModInfo, sModInfo, False );
      end;
    end;
  end;
end;

function TDPlay.packetHandler(input : String; var FromPlayerDPID, ToPlayerDPID : TDPID):string;
var
  RejectionMsg : PRejectionMessage;
  res : HRESULT;

  SimulationSpeedChange : PSimulationSpeedChangeMessage;
  AllyMessage : PAllyMessage;
  Player1 : TPlayerData;
  Player2 : TPlayerData;

  ShareMapPosMsg : PShareMapPosMessage;

  Rec2Rec : PRecorderToRecorderMessage;
  Rec2Rec_Data : Pointer;

  RecvUnitId   : Word;
  RecvNewValue : Integer;
  RecvUnitPtr  : PUnitStruct;

  amaxunits : word;
  i,a,b             : integer;
  s,tmp,s2          : string;
  packet            : TPacket;
  c                 : string;
  uc                : byte;
  w,w2,w3,dtfix     : word;
  pw                : ^word;
  plw               : ^LongWord;
  pf                : ^single;
  lw, lw2           : LongWord;
  f,f2,f3,f4        : single;
  ip                : ^integer;
  InternalVersion   : Integer;
  tmp2              : Longword;
  currnr            : ^longword;
  ally              : ^byte;
  playerlist        : TList;
  tmps              : string;

  player : TPlayerData;
  FromPlayer : TPlayerData;
  ToPlayer : TPlayerData;
  TimeStamp : Longword;

  PacketType: Byte;

begin
  Result := input;
  TimeStamp := timeGetTime;
  FromPlayer := Players.Convert( FromPlayerDPID , ZI_HostPlayer, false );
  ToPlayer := Players.Convert( ToPlayerDPID, ZI_Everyone, false );

  if Assigned(chatview) then
  begin
    if (chatview^.myCheats<>oldMyCheats) and (TAStatus = InGame) then
    begin
      oldMyCheats := chatview^.myCheats;
      Players[1].OtherCheats := oldMyCheats;

      s := '$$$$';
      PRec2Rec_CheatsDetected_Message(@s[1])^.CheatsDetected := oldMyCheats;
      SendRecorderToRecorderMsg( TANM_Rec2Rec_CheatDetection, s );
      if ListCheats(oldMyCheats) <> '' then
        SendChat(Players[1].Name+' has cheats enabled: ' + ListCheats(oldMyCheats));
    end;
    if (chatview^.NewData = 1) then
      SendClipboard();
    if (chatview^.toAlliesLength > 0) then
      SendAlliedChat();
    if (chatview^.fromAlliesLength = 0) and (AlliedMarkerQueue.Count > 0) then
    begin
      tmps := AlliedMarkerQueue.DeQueue;
      for b := 1 to Length (tmps) do
        chatview^.fromAllies[b] := tmps[b];
      chatview^.fromAlliesLength := length (tmps);
    end;
    if (chatview^.commanderWarp = 2) then
    begin
      if not Players[1].WarpDone then
      begin

        SendRecorderToRecorderMsg( TANM_Rec2Rec_CmdWarp, '' );
        Players[1].WarpDone := true;
      end;
      b:=1;
      for a:=1 to Players.Count do
        if not Players[a].warpdone then
        begin
          b:=0;
          Break;
        end;
      if b=1 then
      begin
        CommanderWarp := 3;
        SendLocal( #$19#$00#$00, 0, true, True)

      end;
    end;
  end;

  if TimeStamp - LastFlushTimeStamp  > FlushDeltaTime then
  begin
    LastFlushTimeStamp := TimeStamp;
    TLog.Flush;
    If logsave <> nil then
      try
        logsave.Flush;
      except
      end;
  end;

  if FromPlayer <> nil then
    FromPlayer.LastMsgTimeStamp := timeGetTime;

  packet := TPacket.Create( input );
  try
    if logpl and (TAStatus = InGame) and
       (FromPlayer <> nil) then
      PacketLostHandler(packet.Timestamp,FromPlayer);
    c := packet.RawData2;
    result := #3#0#0 + Copy (packet.FData, 4, 4);
  finally
    packet.Free;
  end;
  datachanged := False;

  if TAStatus = InBattleRoom then
  begin
    repeat
      s := TPacket.Split2(c, False, TPlayers.Name(FromPlayer), TPlayers.Name(ToPlayer));
      tmp := s;
      PacketType := Byte(tmp[1]);
      {$IFDEF Debug}
      if PacketsToFilter <> nil then
      begin
        for a := Low(PacketsToFilter) to High(PacketsToFilter) do
        begin
          if (PacketType = PacketsToFilter[a]) then
          begin

            tmp := #$2a'd';
            datachanged := True;
            Break;
          end;
        end;
        if datachanged then
        begin
          Result := Result+tmp;
          Continue;
        end;
      end;
      {$ENDIF}
      case PacketType of
        TANM_ChatMessage :
          begin
            ChatMsgHandler(s, FromPlayerDPID);
            if datachanged then
              tmp := '';
          end;
        TANM_Rejection :
          begin
            RejectionMsg := PRejectionMessage(@tmp[1]);

            if FromPlayer.IsSelf then
            begin
              if FromPlayer.IsServer then
              begin
                case RejectionMsg^.Reason of
                  PlayerDidnotProperlyClose :
                    begin
                      res := DestroyPlayer( RejectionMsg^.DPlayPlayerID );
                      if res <> DP_OK then
                        TLog.add( 0, Errorstring(res) );
                    end;

                  PlayerDidProperlyClose :
                    begin
                      res := DestroyPlayer( RejectionMsg^.DPlayPlayerID );
                      if res <> DP_OK then
                        TLog.add( 0, Errorstring(res) );
                    end;
                end;
              end

            end;
          end;
        TANM_UnitTypesSync :
          begin
            handleunitdata(s, FromPlayerDPID, ToPlayerDPID);

            currnr := StrPtr(s, 7);
            if currnr^ = SY_UNIT then
            begin
              currnr := StrPtr(tmp, 11);
              if s[2] = #$2 then
              begin
                currnr^ := Random(400000000);
                datachanged := True;
              end;
            end;
          end;
        TANM_Ping :
          begin
            ip := StrPtr(s, 6);
            a := ip^;
            if a<>0 then
            begin
              ip := StrPtr(s, 2);
              a := ip^;
              if ((a>0) and (a<101)) then
                Sentpings[a] := timeGetTime;
            end;
          end;
        TANM_HostMigration :
          begin
            if FromPlayer <> nil then
              ServerPlayer := FromPlayer;
          end;
        TANM_PlayerInfo :
          begin
            if (length(s)>170) then
            begin

              if FromPlayer <> nil then
              begin
                packet := TPacket.sjcreatenew(s);
                try
                  FromPlayer.LastStatusMsg := packet.tadata;
                finally
                  packet.Free;
                end;
                if (byte(s[157]) and $40)=$40 then
                  FromPlayer.Side := 2
                else
                  FromPlayer.Side := byte(s[151]);
                end;

                if FromPlayer.IsServer then
                begin
                  mapname:=copy(s,2,pos(#0,s)-2);
                  if assigned(chatview) then
                  begin
                    for a:=1 to length(mapname) do
                      chatview^.mapname[a] :=mapname[a];
                    chatview^.mapname[length(mapname)+1] :=#0;
                  end;
                  amaxunits := word(byte(s[167]))+word(byte(s[168]))*256;
                  if amaxunits <> maxunits then
                  begin
                    maxunits := amaxunits;
                    if chatview <> nil then
                      chatview^.unitCount := maxunits;
                    if maxunits > 500 then
                    begin
                      if NotViewingRecording and EmitBuggyVersionWarnings then
                        for i := 2 to Players.Count do
                        begin
                          if not Players[i].HasWarnedOnUnitLimit and
                             (Players[i].InternalVersion <> TADemoVersion_OTA) and
                             (Players[i].InternalVersion <= TADemoVersion_99b2) then
                          begin
                            Players[i].HasWarnedOnUnitLimit := True;
                            SendChat( 'Warning: ' + Players[i].Name + ' is using a broken recorder');
                            SendChat( 'This player is unable to handle more than 500 units per side');
                            SendChat( 'Visit www.tauniverse.com to download a different version');
                          end;
                        end;
                    end;
                    if 10*maxunits+1 > Length(UnitStatus) then
                    begin
                      a := high(UnitStatus);
                      if a = -1 then
                        a := 0;
                      SetLength( UnitStatus, 10*maxunits+1 );
                      for i := a to maxunits do
                      begin
                        UnitStatus[i].lastdead := 0;
                        UnitStatus[i].health := 42;
                        UnitStatus[i].DoneStatus := 1000;
                        UnitStatus[i].unitalive := false;
                      end;
                    end;
                  end;
                end;

                if forcego and ((byte(s[157]) and $40)=$40) then
                begin
                  tmp[157] := char(byte(tmp[157]) or (byte('!')-1));
                  datachanged:=true;
                end;
                if assigned(chatview) and (FromPlayer <> nil) and
                   ( (FromPlayer.PlayerIndex >= 1) and (FromPlayer.PlayerIndex <= 10) ) then
                  chatview^.playerColors[FromPlayer.PlayerIndex] := integer(tmp[152]);
                if fakecd then
                begin
                  tmp[159] := #$04;
                  datachanged:=true;
                end;
                if fakewatch and
                   not FromPlayer.IsSelf then
                begin
                  tmp[158] := char(byte(s[158]) or $20);
                  datachanged:=true;
                end;

                if FromPlayer.IsSelf then
                begin
                  if ((byte(tmp[157]) and $20) <> 0) and (not Players[1].ClickedIn) then
                  begin
                    if (ai <> '') and AutoRecording then
                      SendChat( 'Warning: A custom AI (' + ai + ') is enabled');
                    Players[1].ClickedIn := True;
                  end;

                  tmp[182] := char(TADemoVersion_4);
                  datachanged := True;
                end else
                begin
                  InternalVersion := byte(s[182]);
                  FromPlayer.InternalVersion := InternalVersion;
                  FromPlayer.EnemyChat := InternalVersion > TADemoVersion_OTA;
                  FromPlayer.RecConnect := InternalVersion > TADemoVersion_97;
                  FromPlayer.Uses_Rec2Rec_Notification := InternalVersion >= TADemoVersion_99b3_beta2;

                  BroadcastModInfo;
                  if ImServer and
                     (not FromPlayer.ReceivedBRSettings) and
                     (not FromPlayer.IsServer) then
                  begin
                    if FromPlayer.Uses_Rec2Rec_Notification then
                       BroadcastExtraBattleRoomSettings(FromPlayer.ID);
                    FromPlayer.ReceivedBRSettings := True;
                  end;

                  if  EmitBuggyVersionWarnings and
                    (InternalVersion <> TADemoVersion_OTA) and
                    (InternalVersion < TADemoVersion_98b1) and
                    (not FromPlayer.HasBrokenRecorder) then
                  begin
                    SendChat( 'Warning: ' + FromPlayer.Name + ' is using a broken recorder');
                    SendChat( 'This may give him/her advantages such as permanent LOS');
                    SendChat( 'Visit www.tauniverse.com to download a different version');

                    FromPlayer.HasBrokenRecorder := true;

                  end else
                  begin
                    if EmitBuggyVersionWarnings and
                       (InternalVersion <> TADemoVersion_OTA) and
                       (InternalVersion <= TADemoVersion_99b2) and
                       (maxunits > 500) and NotViewingRecording and
                       not FromPlayer.HasWarnedOnUnitLimit then
                    begin
                      FromPlayer.HasBrokenRecorder := True;
                      FromPlayer.HasWarnedOnUnitLimit := True;
                      SendChat( 'Warning: ' + FromPlayer.Name + ' is using a broken recorder');
                      SendChat( 'This player is unable to handle more than 500 units per side');
                      SendChat( 'Visit www.tauniverse.com to download a different version');
                    end;
                  end;
                end;
            end;
          end;
        TANM_ReplayerServer :
          begin
            TLog.Add(0,'Entering recording replay mode');

            NotViewingRecording := False;

            Players[TAData.LocalPlayerID+1].SharingLos := true;

          end;
        TANM_RecorderToRecorder :
          begin
            Rec2Rec := PRecorderToRecorderMessage(@tmp[1]);
            Rec2Rec_Data := Pointer(Longword(Rec2Rec)+SizeOf(TRecorderToRecorderMessage) );
            if Rec2RecPacketOK(tmp) then
            case Rec2Rec^.MsgSubType of
              TANM_Rec2Rec_GameStateInfo :
                begin
                  assert( Rec2Rec^.MsgSize = SizeOf(TRec2Rec_GameStateInfo_Message) );
                  if PRec2Rec_GameStateInfo_Message(Rec2Rec_Data)^.AutopauseState = 1 then
                    SetAutoPauseAtStart(True)
                  else
                    SetAutoPauseAtStart(False);
                  SetF1Disable(PRec2Rec_GameStateInfo_Message(Rec2Rec_Data)^.F1Disable);
                  SetCommanderWarp(PRec2Rec_GameStateInfo_Message(Rec2Rec_Data)^.CommanderWarp);
                  if PRec2Rec_GameStateInfo_Message(Rec2Rec_Data)^.SpeedLockNative = 1 then
                    SetSpeedLockNative(True)
                  else
                    SetSpeedLockNative(False);
                  if PRec2Rec_GameStateInfo_Message(Rec2Rec_Data)^.SpeedLock = 1 then
                    SetSpeedLock(True)
                  else
                    SetSpeedLock(False);
                  SetSlowSpeed(PRec2Rec_GameStateInfo_Message(Rec2Rec_Data)^.SlowSpeed);
                  SetFastSpeed(PRec2Rec_GameStateInfo_Message(Rec2Rec_Data)^.FastSpeed);
                  SetAIDifficulty(PRec2Rec_GameStateInfo_Message(Rec2Rec_Data)^.AIDifficulty);
                end;
              TANM_Rec2Rec_ModInfo :
                begin
                  assert( Rec2Rec^.MsgSize = SizeOf(TRec2Rec_ModInfo_Message) );
                  uc := Players.ConvertId(PRec2Rec_ModInfo_Message(Rec2Rec_Data)^.PlayerID,ZI_Everyone,false);
                  Players[uc].ModInfo.ModID := PRec2Rec_ModInfo_Message(Rec2Rec_Data)^.ModID;
                  Players[uc].ModInfo.ModMajorVer := PRec2Rec_ModInfo_Message(Rec2Rec_Data)^.ModMajorVer;
                  Players[uc].ModInfo.ModMinorVer := PRec2Rec_ModInfo_Message(Rec2Rec_Data)^.ModMinorVer;
                end;
            end;
            tmp := #$2a'd';
            datachanged := True;
          end;
        TANM_Ally :
          begin

            AllyMessage := PAllyMessage(@s[1]);
            Player1 := Players.Convert(AllyMessage^.PlayerID_1,ZI_InvalidPlayer,false);
            Player2 := Players.Convert(AllyMessage^.PlayerID_2,ZI_InvalidPlayer,false);
            if (Player1 <> nil) and (Player2 <> nil) then
            begin
              if Player2.IsSelf then
              begin
                Player1.CanTake := AllyMessage^.Allied <> 0;
                Player1.IsAllied := AllyMessage^.Allied <> 0;
                if (chatview <> nil) and ( (FromPlayer.PlayerIndex >= 1) and
                   (FromPlayer.PlayerIndex <= 10) ) then
                  chatview^.allies[Player1.PlayerIndex] := AllyMessage^.Allied;
              end;
            end;
          end;
        TANM_LoadingStarted :
          begin
            TLog.add(3,'loading started');
            TAStatus := InLoading;
            keyboardHookLevel := 0;

            if assigned(chatview) then
            begin
              if (not NotViewingRecording) then
                chatview^.playingDemo := 1;
              if use3d then
              begin
                if NotViewingRecording then
                begin
                  if Players[1].Side = 2 then
                    chatview^.ta3d := 1;
                end else
                  chatview^.ta3d := 1;
              end;
              if (auto3d) and (not NotViewingRecording) then
                chatview^.ta3d := 1;
              chatview^.TAStatus := 2;
            end;

            if (filename<>'') and (filename<>'none') then
            begin
              filename := RemoveInvalid (filename);
              createlogfile();
              prevtime := timeGetTime;
            end;

            if (filename = '') and (AutoRecording or RecordAuto) and NotViewingRecording then
            begin
              MakeAutoFileName;
              createlogfile();
              prevtime := timeGetTime;
            end;

            playerlist := TList.Create;
            try
              for a := 1 to Players.Count do
                playerlist.Add (Players[a]);
              playerlist.Sort(compare);

              b := 0;
              for a := 1 to Players.Count do
              begin
                player := TPlayerData(playerlist.items[a - 1]);
                TLog.add (3,'setting ' + inttostr(player.id) + ' to ' + inttostr (b));
                player.StartInfo.ID := b;
                player.IsFirstPlayerWithb3 := (a = 1) and (player.InternalVersion >= TADemoVersion_99b3_beta2);
                Inc( b, MaxUnits );
              end;

              if statslog <> nil then
              begin
                statslog.Init_StatEvent;
                for a := 1 to Players.Count do
                begin
                  statslog.AddPlayer_StatEvent(Players[a].PlayerIndex,
                    Players[a].Side, Players[a].Name, Players[a].StartInfo.ID);
                end;
              end;
            finally
              playerlist.Free;
            end;
          end;
      end;
      Result := Result + tmp;
    until c = '';
    c := #6;
  end;

  if TAStatus = InLoading then
  begin
    tmp := c;
    repeat
      s := TPacket.Split2(tmp, False, TPlayers.Name(FromPlayer), TPlayers.Name(ToPlayer));
      PacketType := Byte(s[1]);

      if not IsInGame then
      begin

        if (PacketType = TANM_UnitStatAndMove) or
           (PacketType = TANM_UnitBuildStarted) then
        begin
          IsInGame := True;
          TAStatus := InGame;
          if NotViewingRecording and
             compatibleTA and
             not TAPlayer.IsKilled(TAPlayer.GetPlayerByIndex(TAData.LocalPlayerID)) then
          begin
            if (not Assigned(trCheckMemoryCheats)) then
            begin
              trCheckMemoryCheats := TConsoleTimer.Create;
              with trCheckMemoryCheats do
              begin
                Interval := 3000;
                OnTimerEvent := OnMemoryCheckTick;
                Enabled := True;
              end;

              trCheckProhibitedProcesses := TConsoleTimer.Create;
              with trCheckProhibitedProcesses do
              begin
                Interval := 14000;
                OnTimerEvent := OnProcessCheckTick;
                Enabled := True;
              end;
            end;
          end;

          if Assigned(chatview) then
          begin
            chatview^.TAStatus := 3;
            if (chatview^.commanderWarp=1) or AutoPauseAtStart then
              sendlocal( #$19#$00#$01, 0, true,true);
          end;
          prevtime := timeGetTime;
          starttime := timeGetTime;

          for i := 1 to Players.Count do
          begin
            if Players[i].InternalVersion < TADemoVersion_99b3_beta3 then
            begin
              if Players[i].Uses_Rec2Rec_Notification then
                SendRecorderToRecorderMsg( TANM_Rec2Rec_Sharelos, #$01 )
              else
                SendLocal('.sharelos',Players[i].Id,false,true);
            end
          end;
        end;
      end;
      Result := Result + s;
    until tmp = '';
  end;

  if TAStatus = InGame then
  begin
    s := c;
    dtfix := 0;
    repeat
      tmp := TPacket.Split2(s, False, TPlayers.Name(FromPlayer), TPlayers.Name(ToPlayer));
      PacketType := Byte(tmp[1]);
      case PacketType of
        TANM_HostMigration :
          begin
            if FromPlayer <> nil then
              ServerPlayer := FromPlayer;
          end;
        TANM_ChatMessage :
          begin
            ChatSent:=true;

            ChatMsgHandler (tmp, FromPlayerDPID);

            if ToPlayerDPID <> 0 then
            begin
              if ( (Pos ('->', tmp) > 0) and
                   ( (Pos ('->Allies', tmp) > 0) or (Pos ('->Enemies', tmp) > 0) ) and
                   (Pos ('->', tmp) < Pos ('> ', tmp)) ) or
                 (Pos ('->', tmp) = 0) then
              begin
                for w := 2 to Players.Count do
                begin
                  if Players[w].EnemyChat and (ToPlayerDPID <> Players[w].ID) then
                  begin

                    s2 := #$F9 + '####' + '>>>>' + Copy (tmp, 2, 100);
                    Setlongword (StrPtr(s2, 2), FromPlayerDPID);
                    Setlongword (StrPtr(s2, 6), ToPlayerDPID);
                    SendLocal( s2, Players[w].ID, false, true);
                  end;
                end;
              end;
            end;

            if datachanged then
              tmp := #$2a'd';

            if fakewatch and FromPlayer.IsSelf then
            begin
              ToPlayerDPID := 0;
              ToPlayer := players.EveryonePlayer;
            end;
          end;
        TANM_UnitBuildStarted :
          begin

            pw:=StrPtr(tmp, 2);
            w:=pw^;
            w2:=w;
            Assert( (Integer(w) >= Low(UnitStatus)) and ( w <= High(UnitStatus) ) );
            pw:=StrPtr(tmp, 4);
            w:=pw^;
            if statslog <> nil then
              statslog.NewUnit_StatEvent(FromPlayer.PlayerIndex,w,w2,TAData.GameTime);

            UnitStatus[w - 1].DoneStatus := 255;
            if not UnitStatus[w-1].Unitalive then
            begin
              UnitStatus[w-1].Unitalive := True;
              UnitCountChange(FromPlayer, 1);
            end;

            FromPlayer.StartInfo.ID :=w-w mod maxunits;
            if w-FromPlayer.StartInfo.ID=2 then
            begin

              pw:=StrPtr(tmp, 8);
              FromPlayer.StartInfo.X:=pw^;
              pw:=StrPtr(tmp, 12);
              FromPlayer.StartInfo.Z:=pw^;
              pw:=StrPtr(tmp, 16);
              FromPlayer.StartInfo.Y:=pw^;

              pw:=StrPtr(tmp, 2);
              w:=pw^;
            end;

            if FromPlayer.IsSelf and  (integer(w)-integer(Players[1].StartInfo.ID)=1) then
            begin
              if (w<$25) and (w>$20) then Players[1].Side :=0;
              if (w<$a9) and (w>$a3) then Players[1].Side :=1;
            end;
          end;
        TANM_SimulationSpeedChange :
          begin

            RequireGuarantiedMsgDelivery := True;
            SimulationSpeedChange := PSimulationSpeedChangeMessage(@tmp[1]);

            if (SimulationSpeedChange^.Marker = TANM_SimulationSpeedChange ) and
               (SimulationSpeedChange^.SimSpeedChangeType = PauseChange) and
               (SimulationSpeedChange^.PauseState = 0) then
            begin
              if AutoPauseAtStart then
              begin
                if not FromPlayer.IsServer then
                begin

                  tmp := #$19#$00#$01;

                  SendLocal( tmp, 0, true, true);

                  SendChat( '***'+FromPlayer.Name+' tried to unpause.' );

                  tmp := #$2a'd';
                  datachanged := True;
                end else
                  AutoPauseAtStart := False;
              end;

              if not AutoPauseAtStart then
                for i :=1 to Players.Count do
                  Players[i].UnpauseReady := False;
            end;
            if not notime and
             (SimulationSpeedChange^.SimSpeedChangeType <> PauseChange) then
            begin
              if tmp[3] > char(SpeedHack.Upperlimit) then
              begin

                tmp := #19#0#0;
                SimulationSpeedChange := PSimulationSpeedChangeMessage(@tmp[1]);
                SimulationSpeedChange^.SimSpeedChangeType := SpeedChange;
                SimulationSpeedChange^.PauseState := SpeedHack.Upperlimit;
                SendLocal( tmp, 0, true, true);

                tmp := #$2a'd';
                datachanged := true;
              end else
              begin
                if tmp[3] < char(SpeedHack.LowerLimit) then
                begin

                  tmp := #19#0#0;
                  SimulationSpeedChange := PSimulationSpeedChangeMessage(@tmp[1]);
                  SimulationSpeedChange^.SimSpeedChangeType := SpeedChange;
                  SimulationSpeedChange^.PauseState := SpeedHack.LowerLimit;
                  SendLocal( tmp, 0, true, true);

                  tmp := #$2a'd';
                  datachanged := true;
                end;
              end;
            end;
            SimulationSpeedChange := PSimulationSpeedChangeMessage(@tmp[1]);
            if (SimulationSpeedChange^.Marker = TANM_SimulationSpeedChange ) and
               (SimulationSpeedChange^.SimSpeedChangeType = PauseChange) then
            begin
              if (SimulationSpeedChange^.PauseState = 0) then
              begin
                if NotViewingRecording then
                  SendChatLocal( '***'+FromPlayer.Name+' unpaused the game' );
                if assigned(chatview) then
                  CommanderWarp := 0;
              end else
                if NotViewingRecording then
                  SendChatLocal( '***'+FromPlayer.Name+' paused the game' );
            end;
          end;
        TANM_UnitStatAndMove :
          begin
            currnr := StrPtr(tmp, 4);
            FromPlayer.LastTimeStamp := currnr^;

            if FromPlayer.StartInfo.ID <> High(longword) then
            begin
              a := (currnr^ mod maxunits) + FromPlayer.StartInfo.ID;
              if tmp[2] = #$0b then
              begin
                UnitStatus[a].DoneStatus := 1000;
                if UnitStatus[a].UnitAlive then
                begin
                  UnitStatus[a].UnitAlive := False;
                  UnitCountChange(FromPlayer,-1);
                end;
              end;

              pw := StrPtr(tmp, 8);
              if (pw^ = $ffff) and (Length (tmp) > 13) then
              begin
                if not UnitStatus[a].UnitAlive then
                begin
                  UnitStatus[a].UnitAlive := true;
                  UnitCountChange(FromPlayer,1);
                end;
                UnitStatus[a].health := BinToInt(tmp, 11, 2, 16);
                b := UnitStatus[a].DoneStatus;
                UnitStatus[a].DoneStatus := BinToInt(tmp, 13, 2, 8);
                if (UnitStatus[a].DoneStatus = 0) and (b > 0) then
                begin

                end;
              end;
            end;
            if (FromPlayer.UnitsAliveCount > 0) and (chatview <> nil) and
               (FromPlayer.PlayerIndex >= 1) and (FromPlayer.PlayerIndex <= 10) then
            begin
              chatview^.deathtimes[FromPlayer.PlayerIndex] := FromPlayer.LastMsgTimeStamp
            end else
            begin
            end;
          end;
        TANM_Ally :
          begin
            AllyMessage := PAllyMessage(@tmp[1]);

            Player1 := Players.Convert(AllyMessage^.PlayerID_1,ZI_InvalidPlayer,false);
            Player2 := Players.Convert(AllyMessage^.PlayerID_2,ZI_InvalidPlayer,false);
            if (Player1 <> nil) and (Player2 <> nil) then
            begin
              if Player2.IsSelf then
              begin
                Player1.CanTake := AllyMessage^.Allied <> 0;
                Player1.IsAllied := AllyMessage^.Allied <> 0;
                if (chatview <> nil) and ( (FromPlayer.PlayerIndex >= 1) and
                   (FromPlayer.PlayerIndex <= 10) ) then
                  chatview^.allies[Player1.PlayerIndex] := AllyMessage^.Allied;
              end;
            end;
          end;
        TANM_UnitBuildFinished :
          begin
            pw:=StrPtr(tmp, 2);
            w:=pw^;
            if statslog <> nil then
              statslog.UnitFinished_StatEvent(FromPlayer.PlayerIndex,w,TAData.GameTime);
            UnitStatus[w - 1].DoneStatus := 0;

          end;
        TANM_UnitKilled :
          begin
            pw:=StrPtr(tmp, 2);
            w:=pw^;
            if statslog <> nil then
            begin
              pw:=StrPtr(tmp, 8);
              w2:=pw^;
              statslog.Kill_StatEvent(w,w2,TAData.GameTime);
            end;
            UnitStatus[w - 1].DoneStatus := 1000;
            if UnitStatus[w - 1].unitalive then
            begin
              UnitStatus[w - 1].unitalive := false;
              UnitCountChange(FromPlayer,-1);
            end;
          end;
        TANM_UnitTakeDamage :
          begin
            if statslog <> nil then
            begin
              pw:=StrPtr(tmp, 2);
              w:=pw^;
              pw:=StrPtr(tmp, 4);
              w2:=pw^;
              pw:=StrPtr(tmp, 6);
              w3:=pw^;
              statslog.Damage_StatEvent(w,w2,w3,Byte(tmp[9]),TAData.GameTime);
            end;
          end;
        TANM_FeatureAction :
          begin

            if (statslog <> nil) and
               not FromPlayer.IsSelf then
            begin
              pw:=StrPtr(tmp, 3);
              w:=pw^;
              pw:=StrPtr(tmp, 5);
              w2:=pw^;
              statslog.FeatureDestroyed_StatEvent(FromPlayer.PlayerIndex,Byte(tmp[2]),w,w2,nil,TAData.GameTime);
            end;
          end;
        TANM_Rejection :
          begin
            RejectionMsg := PRejectionMessage(@tmp[1]);

            player := players.Convert(RejectionMsg^.DPlayPlayerID, ZI_InvalidPlayer, false);

            if AutoPauseAtStart and (player <> nil) and (player.IsServer) then
              AutoPauseAtStart := False;

            case TakeStatus of
              NoOneTaking, SelfTaking :
                begin
                  if (FromPlayer.Name = TakePlayer) then
                    FromPlayer.CanTake := False;
                end;
              OtherPlayerTaking_OldVersion_Pre99b2 :
                begin

                  TakeRef := 0;
                  TakeStatus := NoOneTaking;
                  TakePlayer := '';
                  SendLocal( killunits, 0, true, true);
                  SendChatLocal( 'Sending killing packets');
                end;
              OtherPlayerTaking_OldVersion_99b2, OtherPlayerTaking :
                begin
                  SendChatLocal(TakePlayer+' take claim released');

                  TakeRef := 0;
                  TakeStatus := NoOneTaking;
                  TakePlayer := '';
                end;
            else
              begin
                SendChat( Players[1].Name+' has invalid take status ' +
                          IntToStr(ord(TakeStatus))+' resetting to '+
                          IntToStr(ord(NoOneTaking)));
                TakeStatus := NoOneTaking;
              end;
            end;
          end;
        TANM_PlayerResourcesInfo :
          begin
            a:=FromPlayer.LastTimeStamp-FromPlayer.Economy.LastTimeStamp;
            if a<180 then
              a:=120;
            pf:=StrPtr(tmp, 47);
            f:=pf^;
            f3:=(f-FromPlayer.Economy.LastTotalMetal);
            if f3>0 then
            begin
              FromPlayer.Economy.LastSharedMetal:=FromPlayer.Economy.SharedMetal;
              FromPlayer.Economy.SharedMetal := 0;
              FromPlayer.Economy.IncomeMetal := f3 / a*30;
              FromPlayer.Economy.LastTotalMetal := f;
            end;
            pf:=StrPtr(tmp, 35);
            f:=pf^;
            f3:=(f-FromPlayer.Economy.LastTotalEnergy);
            if f3>0 then
            begin
              FromPlayer.Economy.LastSharedEnergy := FromPlayer.Economy.SharedEnergy;
              FromPlayer.Economy.SharedEnergy := 0;
              FromPlayer.Economy.IncomeEnergy := f3 / a*30;
              FromPlayer.Economy.LastTotalEnergy := f;
            end;
            FromPlayer.Economy.LastTimeStamp := FromPlayer.LastTimeStamp;
            pf:=StrPtr(tmp, 19);
            f:=pf^;
            pf:=StrPtr(tmp, 23);
            f2:=pf^;
            pf:=StrPtr(tmp, 27);
            f3:=pf^;
            pf:=StrPtr(tmp, 31);
            f4:=pf^;
            b:=a;
            if assigned(chatview) and ( (FromPlayer.PlayerIndex >= 1) and
              (FromPlayer.PlayerIndex <= 10) ) then
            begin
              chatview^.incomeM[FromPlayer.PlayerIndex] := FromPlayer.Economy.IncomeMetal -FromPlayer.Economy.LastSharedMetal/b*30;
              chatview^.incomeE[FromPlayer.PlayerIndex] := FromPlayer.Economy.IncomeEnergy-FromPlayer.Economy.LastSharedEnergy/b*30;
              chatview^.totalM[FromPlayer.PlayerIndex] := FromPlayer.Economy.LastTotalMetal-FromPlayer.Economy.TotalSharedMetal;
              chatview^.totalE[FromPlayer.PlayerIndex] := FromPlayer.Economy.LastTotalEnergy-FromPlayer.Economy.TotalSharedEnergy;
              chatview^.storedM[FromPlayer.PlayerIndex] :=f;
              chatview^.storedE[FromPlayer.PlayerIndex] :=f2;
              chatview^.storageM[FromPlayer.PlayerIndex] :=f3;
              chatview^.storageE[FromPlayer.PlayerIndex] :=f4;
            end;
            if statslog <> nil then
            begin
              statslog.Stats_StatEvent(FromPlayer.PlayerIndex,f,f2,f3,f4,
                                       FromPlayer.Economy.IncomeMetal,
                                       FromPlayer.Economy.IncomeEnergy,
                                       TAPlayer.GetPlayerByIndex(FromPlayer.PlayerIndex-1).nKills,
                                       TAPlayer.GetPlayerByIndex(FromPlayer.PlayerIndex-1).nLosses,
                                       TAData.GameTime);
            end;
          end;
        TANM_ShareResources :
          begin
            ResourcesSent := True;

            pf:=StrPtr(tmp, 14);
            f:=pf^;
            if tmp[2]=#2 then
            begin
              FromPlayer.Economy.SharedMetal := FromPlayer.Economy.SharedMetal+f;
              FromPlayer.Economy.TotalSharedMetal := FromPlayer.Economy.TotalSharedMetal+f;
            end else
            begin
              FromPlayer.Economy.SharedEnergy := FromPlayer.Economy.SharedEnergy+f;
              FromPlayer.Economy.TotalSharedEnergy := FromPlayer.Economy.TotalSharedEnergy+f;
            end;
            if statslog <> nil then
            begin
              plw:=StrPtr(tmp, 6);
              lw:=plw^;
              plw:=StrPtr(tmp, 10);
              lw2:=plw^;
              statslog.ResourcesShare_StatEvent(TAPlayer.GetPlayerByDPID(lw),
                                                TAPlayer.GetPlayerByDPID(lw2), f, Byte(tmp[2]),
                                                TAData.GameTime);
            end;
            if FromPlayer.IsSelf then
            begin
              ToPlayerDPID := 0;
              ToPlayer := Players.EveryonePlayer;
            end;
          end;
        TANM_RecorderToRecorder :
          begin
            Rec2Rec := PRecorderToRecorderMessage(@tmp[1]);
            Rec2Rec_Data := Pointer(Longword(Rec2Rec)+SizeOf(TRecorderToRecorderMessage) );
            if Rec2RecPacketOK(tmp) then
            case Rec2Rec^.MsgSubType of
              TANM_Rec2Rec_MarkerData:
                begin
                  if (not FromPlayer.IsSelf) and
                     ((not NotViewingRecording) or FromPlayer.CanTake) then
                  begin

                    tmps := copy(tmp,4,integer (tmp[2]));

                    AlliedMarkerQueue.EnQueue(tmps);
                  end;
                end;
              TANM_Rec2Rec_CmdWarp:
                begin
                  FromPlayer.WarpDone := true;
                end;
              TANM_Rec2Rec_CheatDetection:
                begin
                  assert( Rec2Rec^.MsgSize = SizeOf(TRec2Rec_CheatsDetected_Message) );
                  FromPlayer.otherCheats := PRec2Rec_CheatsDetected_Message(Rec2Rec_Data)^.CheatsDetected;
                  if (date>36983) and (ListCheats(FromPlayer.otherCheats) <> '') then
                    SendChat(FromPlayer.Name+' has cheats enabled: ' + ListCheats(FromPlayer.otherCheats));
                end;
              TANM_Rec2Rec_Sharelos :
                begin
                  assert( Rec2Rec^.MsgSize = SizeOf(TRec2Rec_Sharelos_Message) );
                  FromPlayer.SharingLos := PRec2Rec_Sharelos_Message(Rec2Rec_Data)^.ShareLosState <> 0;
                end;
              TANM_Rec2Rec_UnitWeapon :
                begin
                   assert( Rec2Rec^.MsgSize = SizeOf(TRec2Rec_UnitWeapon_Message) );
                   if not TAUnit.IsOnThisComp(TAUnit.Id2Ptr(PRec2Rec_UnitWeapon_Message(Rec2Rec_Data)^.UnitId), True) then
                   begin
                     TAUnit.SetWeapon(TAUnit.Id2Ptr(PRec2Rec_UnitWeapon_Message(Rec2Rec_Data)^.UnitId),
                                      PRec2Rec_UnitWeapon_Message(Rec2Rec_Data)^.WeaponIdx,
                                      PRec2Rec_UnitWeapon_Message(Rec2Rec_Data)^.NewWeaponID);
                   end;
                end;
              TANM_Rec2Rec_UnitInfoSwap :
                begin
                  if (not FromPlayer.IsSelf) then
                  begin
                    assert( Rec2Rec^.MsgSize = SizeOf(TRec2Rec_UnitInfoSwap_Message) );
                    TAUnit.SetUnitInfo(TAUnit.Id2Ptr(PRec2Rec_UnitInfoSwap_Message(Rec2Rec_Data)^.UnitID),
                                       TAMem.UnitInfoCrc2Ptr(PRec2Rec_UnitInfoSwap_Message(Rec2Rec_Data)^.UnitInfoCRC));
                  end;
                end;
              TANM_Rec2Rec_UnitGrantUnitInfo :
                begin
                  if (not FromPlayer.IsSelf) then
                  begin
                    assert( Rec2Rec^.MsgSize = SizeOf(TRec2Rec_UnitGrantUnitInfo_Message) );
                    TAUnit.GrantUnitInfo( TAUnit.Id2Ptr(PRec2Rec_UnitGrantUnitInfo_Message(Rec2Rec_Data)^.UnitId),
                                          PRec2Rec_UnitGrantUnitInfo_Message(Rec2Rec_Data)^.NewState,
                                          False );
                  end;
                end;
              TANM_Rec2Rec_UnitInfoEdit :
                begin
                   if (not FromPlayer.IsSelf) then
                   begin
                     assert( Rec2Rec^.MsgSize = SizeOf(TRec2Rec_UnitInfoEdit_Message) );
                     TAUnit.setUnitInfoField( TAUnit.Id2Ptr(PRec2Rec_UnitInfoEdit_Message(Rec2Rec_Data)^.UnitId),
                                              TUnitInfoExtensions(PRec2Rec_UnitInfoEdit_Message(Rec2Rec_Data)^.FieldType),
                                              PRec2Rec_UnitInfoEdit_Message(Rec2Rec_Data)^.NewValue );
                   end;
                 end;
              TANM_Rec2Rec_NewUnitLocation :
                begin
                  assert( Rec2Rec^.MsgSize = SizeOf(TRec2Rec_NewUnitLocation_Message) );
                  if (not FromPlayer.IsSelf) then
                  begin
                    UNITS_NewUnitPosition( TAUnit.Id2Ptr(PRec2Rec_NewUnitLocation_Message(Rec2Rec_Data)^.UnitId),
                                           PRec2Rec_NewUnitLocation_Message(Rec2Rec_Data)^.NewX,
                                           PRec2Rec_NewUnitLocation_Message(Rec2Rec_Data)^.NewY,
                                           PRec2Rec_NewUnitLocation_Message(Rec2Rec_Data)^.NewZ,
                                           1 );
                  end;
                end;
              TANM_Rec2Rec_EmitSFXToUnit :
                begin
                  assert( Rec2Rec^.MsgSize = SizeOf(TRec2Rec_EmitSFXToUnit_Message) );
                  if not FromPlayer.IsSelf then
                  begin
                    TASfx.EmitSfxFromPiece( TAUnit.Id2Ptr(PRec2Rec_EmitSFXToUnit_Message(Rec2Rec_Data)^.FromUnitID),
                                            TAUnit.Id2Ptr(PRec2Rec_EmitSFXToUnit_Message(Rec2Rec_Data)^.ToUnitID),
                                            PRec2Rec_EmitSFXToUnit_Message(Rec2Rec_Data)^.FromPieceIdx,
                                            PRec2Rec_EmitSFXToUnit_Message(Rec2Rec_Data)^.SfxType,
                                            False );
                  end;
                end;
              TANM_Rec2Rec_SetNanolatheParticles :
                begin
                  assert( Rec2Rec^.MsgSize = SizeOf(TRec2Rec_SetNanolatheParticles_Message) );
                  if not FromPlayer.IsSelf then
                  begin
                    if PRec2Rec_SetNanolatheParticles_Message(Rec2Rec_Data)^.Reverse = 0 then
                      TASfx.NanoParticles(PRec2Rec_SetNanolatheParticles_Message(Rec2Rec_Data)^.PosFrom,
                                          PRec2Rec_SetNanolatheParticles_Message(Rec2Rec_Data)^.PosTo)
                    else
                      TASfx.NanoReverseParticles(PRec2Rec_SetNanolatheParticles_Message(Rec2Rec_Data)^.PosFrom,
                                                 PRec2Rec_SetNanolatheParticles_Message(Rec2Rec_Data)^.PosTo);
                  end;
                end;
              TANM_Rec2Rec_ExtraUnitState :
                begin
                  if (not FromPlayer.IsSelf) then
                  begin
                    assert( Rec2Rec^.MsgSize = SizeOf(TRec2Rec_ExtraUnitState_Message) );
                    case PRec2Rec_ExtraUnitState_Message(Rec2Rec_Data)^.FieldType of
                     1 :
                       begin
                         UnitsCustomFields[PRec2Rec_ExtraUnitState_Message(Rec2Rec_Data)^.UnitId].ShieldedBy :=
                           TAUnit.Id2Ptr(PRec2Rec_ExtraUnitState_Message(Rec2Rec_Data)^.NewValue);
                       end;
                     2 :
                       begin
                         RecvUnitId   := PRec2Rec_ExtraUnitState_Message(Rec2Rec_Data)^.UnitId;
                         RecvNewValue := PRec2Rec_ExtraUnitState_Message(Rec2Rec_Data)^.NewValue;
                         RecvUnitPtr  := TAUnit.Id2Ptr(RecvUnitId);

                         if (RecvUnitPtr <> nil) and (RecvUnitPtr.p_UNITINFO <> nil) and
                            (RecvNewValue in [0, 1]) then
                           TAUnit.SetCloak(RecvUnitPtr, RecvNewValue);
                       end;
                    end;
                  end;
                end;
            end;
            tmp := #$2a'd';
            datachanged := true;
          end;
        TANM_ShareMapPos :
          begin
            if shareMapPos and Assigned(chatview) and
               ( (FromPlayer.PlayerIndex >= 1) and (FromPlayer.PlayerIndex <= 10) ) then
            begin
              ShareMapPosMsg := PShareMapPosMessage(@tmp[1]);
              if (FromPlayer.UnitsAliveCount > 0) then
              begin
                chatview^.otherMapX[FromPlayer.PlayerIndex] := ShareMapPosMsg^.MapX;
                chatview^.otherMapY[FromPlayer.PlayerIndex] := ShareMapPosMsg^.MapY;
              end else
              begin
                chatview^.otherMapX[FromPlayer.PlayerIndex] := -1;
                chatview^.otherMapY[FromPlayer.PlayerIndex] := -1;
              end;

              tmp := #$2a'd';
              datachanged := true;
            end;
          end;
      end;

      {$IFDEF Debug}
      if PacketsToFilter <> nil then
        for a := Low(PacketsToFilter) to High(PacketsToFilter) do
          if (byte(tmp[1])=PacketsToFilter[a]) then
          begin

            tmp := #$2a'd';
            datachanged := true;
            break;
          end;
      {$ENDIF}

      if fixfacexps then
        tmp := facexpshandler (tmp, FromPlayerDPID, false);

      if protectdt then
      begin
        if tmp[1] = #$12 then
        begin
          pw := StrPtr(tmp, 2);
          dtfix := pw^;
        end else
          if (tmp[1]=#$0c) and (dtfix<>0) then
          begin
            pw := StrPtr(tmp, 2);
            if dtfix = pw^ then
              RequireGuarantiedMsgDelivery := true;
          end;
      end;

      if fakewatch and (FromPlayer <> nil) and FromPlayer.IsSelf then
      begin

        if Longword(timeGetTime - starttime) > 5000 then
        begin
          datachanged := true;
          if ((tmp[1]<>#5) and (tmp[1]<>#$2c)) then
            tmp:=#$2a'd'
          else
            if tmp[1] = #$2c then
              tmp:=#$2c#$b#0+copy(tmp,4,4)+#$ff#$ff#1#0
        end;
      end;

      Result := Result + tmp;
    until s = '';

    if IsRecording and (FromPlayer <> nil) then
    begin
      if shareMapPos and (chatview <> nil) and
         ( (chatview^.mapX <> OldMapX) or (chatview^.mapY <> OldMapY) ) then
      begin
        a := Length(c);
        SetLength( c, a+SizeOf(TShareMapPosMessage));
        ShareMapPosMsg := PShareMapPosMessage(@c[a+1]);
        ShareMapPosMsg^.Marker := TANM_ShareMapPos;
        if FromPlayer.IsSelf then
        begin
          ShareMapPosMsg^.MapX := Word( chatview^.Mapx );
          ShareMapPosMsg^.MapY := Word( chatview^.Mapy );
        end else
        begin
          if (FromPlayer.PlayerIndex >= 1) and (FromPlayer.PlayerIndex <= 10) then
          begin
            ShareMapPosMsg^.MapX := Word( chatview^.otherMapx[FromPlayer.PlayerIndex] );
            ShareMapPosMsg^.MapY := Word( chatview^.othermapy[FromPlayer.PlayerIndex] );
          end;
        end;
      end;

      if ToPlayer = nil then
        c := SmartPak( c, FromPlayer.Name, '' )
      else
        c := SmartPak( c, FromPlayer.Name, ToPlayer.Name );
      if length(c)>1 then
      begin
        SetLength( s, 5 );
        a:=integer(timeGetTime);
        b:=a-integer(prevtime);
        prevtime:=longword(a);
        if b<0 then
          b:=b+1000*60*60*24;
        s[3] := char(b and $ff);
        s[4] := char(b shr 8);
        s[5] := char(FromPlayer.playerindex);
        s:= s+c;
        s[1] := char(length(s) and $ff);
        s[2] := char(length(s) shr 8);
        logsave.add(s);
      end;
    end;
  end;

  if shareMapPos and (chatview <> nil ) and (TAStatus = InGame) and FromPlayer.IsSelf and
     ( (chatview^.mapX <> OldMapX) or (chatview^.mapY <> OldMapY) ) then
  begin
    OldMapX := chatview^.mapX;
    OldMapY := chatview^.mapY;
    datachanged:=true;
    a := Length(Result);
    SetLength( Result, a+SizeOf(TShareMapPosMessage));
    ShareMapPosMsg := PShareMapPosMessage(@Result[a+1]);
    ShareMapPosMsg^.Marker := TANM_ShareMapPos;
    ShareMapPosMsg^.MapX := chatview^.mapX;
    ShareMapPosMsg^.MapY := chatview^.mapY;

  end;

  if datachanged then
  begin

    if length(result)=7 then
      result:=result+#$2a'd';
    if UseCompression then
      Result := TPacket.Compress( Result );
    Result := TPacket.Encrypt( Result );
  end;
end;

{$I WrapperFunctions.inc}

function TDPlay.GetPlayerName(idPlayer: TDPID; lpData: Pointer; var lpdwDataSize: longword)
        : HResult;
var
  i : integer;
  NotVotedGoCount : Integer;
  ip : TArrayOfByte;
  iplen :longword;
  player : TPlayerData;
  player2 : TPlayerData;
  lpName: PDPName;
  playerlist : TList;
  NameLen : integer;
begin
try
cs.Acquire;
try
  Result := dp3.GetPlayerName (idPlayer, lpData, lpdwDataSize);
  if (lpData = nil) or (Result = DPERR_BUFFERTOOSMALL) or TADemoRecorderOff then Exit;
{$IFDEF ThreadLogging}  ThreadLogger.LogThreadID;{$ENDIF}
  lpName := lpData;
  player := Players.Add( lpName^.lpszLongName, idPlayer );
  if Players.Count = 1 then
    begin

    player.InternalVersion := TADemoVersion_4;
    player.EnemyChat := true;
    player.RecConnect := true;
    player.Uses_Rec2Rec_Notification := True;

    end
  else
    begin
    playerlist := TList.Create;
    try
    for i := 1 to Players.Count do
      playerlist.Add(Players[i]);
    playerlist.Sort(compare);
    for i := 1 to Players.Count do
      begin
      player2 := TPlayerData(playerlist.items[i - 1]);
      player2.IsFirstPlayerWithb3 := (i = 1) and (player.InternalVersion >= TADemoVersion_99b3_beta2);
      end;
    finally
      playerlist.Free;
    end;
    end;

  TLog.add(3,'Player #'+IntToStr(Players.Count)+': '+player.Name);
  player.Side := 0;
  player.Color := Players.Count;

  if Players[1].GiveBase then
    begin
    if ImServer then
      SendChat('New player. Quick base toggled off');
    for i := 1 to Players.Count-1 do
      Players[i].GiveBase := false;
    end;

  NotVotedGoCount := 0;
  for i := 1 to Players.Count-1 do
    if (not Players[i].VotedGo or not not Players[i].ClickedIn ) and

       ((Players[i].Side =0) or (Players[i].Side=1)) then
      inc( NotVotedGoCount );
  ForceGo := NotVotedGoCount = 0;

  iplen := 1000;
  dp3.GetPlayerAddress( idPlayer, nil, iplen );
  if iplen > 0 then
    begin
    setlength(ip, iplen);
    dp3.GetPlayerAddress( idPlayer, ip, iplen );
    Player.IP := PtrToStr( @ip[0], iplen);
    end
  else
    Player.IP := '127.0.0.1';

  if assigned(chatview) and (Players.Count <= 10) then
    begin
    NameLen := length(Player.Name);
    if NameLen >= high(chatview^.playernames[Players.Count]) then
      NameLen := high(chatview^.playernames[Players.Count])-1;
    for i := 1 to NameLen do
      chatview^.playernames[Players.Count][i] := Player.Name[i];
    chatview^.playernames[Players.Count][NameLen+1] :=#0;
    end;
  if IniSettings.BattleRoomEnh then
  begin
    if (PPlayerStruct(TAPlayer.GetPlayerByIndex(Player.PlayerIndex -1)).cPlayerController = Player_LocalAI) or
       (PPlayerStruct(TAPlayer.GetPlayerByIndex(Player.PlayerIndex -1)).cPlayerController = Player_LocalHuman) then
    begin
      Players[Player.PlayerIndex].ModInfo.ModID := LocalModInfo.ModID;
      Players[Player.PlayerIndex].ModInfo.ModMajorVer := LocalModInfo.ModMajorVer;
      Players[Player.PlayerIndex].ModInfo.ModMinorVer := LocalModInfo.ModMinorVer;
    end;
    BroadcastModInfo;
  end;
finally
  cs.Release;
end;
except
  on e : Exception do
     begin
     if OnException(e) then raise else Result := DP_OK;
    end;
end;
end;

{$IFDEF FindRetAddr}
var
  SendReturnAddr : Longword;
  RecieveReturnAddr : Longword;
{$ENDIF}

function TDPlay.Send(idFrom: TDPID; lpidTo: TDPID; dwFlags: longword; const lpData;
        lpdwDataSize: longword) : HRESULT;
var
  s :string;
  till:TDPID;
  errorAddress,errorAddress2 : Longword;
begin
if TADemoRecorderOff then
  begin
  Result := dp3.Send (idFrom, lpidTo, dwFlags, lpData, lpdwDataSize);
  exit;
  end;
cs.Acquire;
try
{$IFDEF FindRetAddr}
if SendReturnAddr = 0 then
  asm
    push eax;
    MOV EAX,[EBP+4];
    Mov SendReturnAddr, EAX;
    pop eax;
  end;
{$ENDIF}
{$IFDEF ThreadLogging}  ThreadLogger.LogThreadID;{$ENDIF}
Result := DP_OK;
try
  ChatSent := false;
  ResourcesSent := false;
  RequireGuarantiedMsgDelivery := false;
  s := PtrToStr (@lpdata, lpdwDataSize);
  till := lpidto;
  s := packethandler (s, idfrom, till);
  if RequireGuarantiedMsgDelivery then
     dwFlags := dwflags or DPSEND_GUARANTEED;
  if datachanged then
    begin
    datachanged:=false;
    if length (s) > 0 then
      begin
      if (ResourcesSent and not ChatSent) or fakewatch then
        Result := dp3.Send (idFrom, till, dwFlags, s[1], length(s))
      else
        Result := dp3.Send (idFrom, lpidTo, dwFlags, s[1], length(s))
      end
    else
      Result := DP_OK;
    end
  else if (ResourcesSent and not ChatSent) or fakewatch then
    Result := dp3.Send (idFrom, till, dwFlags, lpData, lpdwDataSize)
  else
    Result := dp3.Send (idFrom, lpidTo, dwFlags, lpData, lpdwDataSize);
except
  on E: Exception do
    begin
    LogException(E);
    try
      errorAddress := Longword(ExceptAddr);
      SendChat('Exception caught in TDPlay.Send; $'+IntToHex(errorAddress,8));
      if not MapFileSetup then
        LoadAndParseMapFile;
      errorAddress2 := GetMapAddressFromAddress(errorAddress);
      s := GetModuleNameFromAddress(errorAddress2);
      if s <> '' then
        begin
        SendChat(s+':'+GetProcNameFromAddress(errorAddress2)+':'+GetLineNumberFromAddress(errorAddress2));
        end;
      SendChat(e.message);

      if E is EInvalidPointer then
        raise e at ExceptAddr
      else if crash then
        raise e at ExceptAddr
      else
        begin
        ExceptMessage;
        Result := DP_OK;
        end;
    finally
      TLog.Flush;
      if logsave <> nil then
        try
          logsave.Flush;
        except
        end;

    end;
    end;
end;
finally
  cs.Release;
end;
end;

function TDPlay.Receive(var lpidFrom: TDPID; var lpidTo: TDPID; dwFlags: longword;
        lpData: Pointer; var lpdwDataSize: longword) : HResult;
var
   p      :TPacket;
   s      :string;
   wp     :^word;
   w      :word;
   ip     :^cardinal;
   holdstring :string;
   bufsize :integer;
   bogustill :TDPID;
   errorAddress,errorAddress2 : Longword;
   i : Integer;
begin
if TADemoRecorderOff then
  begin
  Result := dp3.Receive (lpidFrom, lpidTo, dwFlags, lpData, lpdwDataSize);
  exit;
  end;
cs.Acquire;
try
{$IFDEF FindRetAddr}
if RecieveReturnAddr = 0 then
  asm
    push eax;
    MOV EAX,[EBP+4];
    Mov RecieveReturnAddr, EAX;
    pop eax;
  end;
{$ENDIF}
{$IFDEF ThreadLogging}  ThreadLogger.LogThreadID;{$ENDIF}
Result := DP_OK;
bufsize := lpdwDataSize;
try
    // BUGFIX: Guard against empty Players list crash (AV at 0x00000002)
    if MessageQueue.count <> 0 then
      begin
      if Players.Count > 0 then
        lpidFrom := Players[GetGoodSource].ID
      else
        begin
        TLog.add(4, 'ERROR: MessageQueue has messages but Players list is empty!');
        Result := DPERR_INVALIDPLAYER;
        Exit;
        end;
      end
    else if TakeStatus = SelfTaking then
      begin
      for i := 1 to Players.Count do
      if (TakeStatus = SelfTaking) and (Players[i].TakeUnit <> 0) then
        begin
        TLog.add(2,'inserting give data');
        lpidFrom := Players[i].ID;

        holdstring := '123456';
        wp := StrPtr(holdstring, 1);
        w := Players[i].TakeUnit + Players[i].StartInfo.ID;
        wp^ := w;
        ip := StrPtr(holdstring, 3);
        ip^ := Players[1].Id;
        holdstring:=#$14+holdstring+#$00#$00#$00#$00+'F'+#$01#$00#$00#$00#$00+'d'+#$7F#$00#$00#$00#$00#$00;
        Assert( (integer(w)-1 >= Low(UnitStatus)) and ( (w-1) <= High(UnitStatus) ) );
        setword(StrPtr(holdstring, 12), UnitStatus[w - 1].health);

        if UnitStatus[w - 1].DoneStatus = 0 then
          SendLocal( holdstring, 0, true, false);

        if Players[i].TakeUnit >= maxunits-Longword(2) then
          begin
          TLog.add(2,'rejecting');
          holdstring:='1234'+#$06;
          ip:=StrPtr(holdstring, 1);
          ip^ := Players[i].ID;
          holdstring:=#$1b+holdstring;
          sendlocal(holdstring,0,false,true);

          Dec(TakeRef);
          Players[i].TakeUnit := 0;
          end
        else
          Inc( Players[i].TakeUnit );

        end;
      if (TakeRef = 0) and (TakeStatus = SelfTaking) then
        begin
        TakeStatus := NoOneTaking;
        TakePlayer := '';
        end;
      end;

    if MessageQueue.count <> 0 then
    begin
      holdstring := MessageQueue.Examine;

      if Longword(length(holdstring))+10 > lpdwdatasize then
        begin
        lpdwdatasize := length (holdstring) + 10;
        Result := DPERR_BUFFERTOOSMALL;
        exit;
        end;

      p:=TPacket.sjcreatenew(holdstring);
      try
        s := p.tadata;
      finally
        p.free;
      end;

      if Longword(length(s)) > bufsize then
        begin
        lpdwdatasize := length (s) + 10;
        Result := DPERR_BUFFERTOOSMALL;
        exit;
        end;

      MessageQueue.DeQueue;
      lpidTo := Players[1].Id;
      lpdwDataSize := length(s);
      if lpdwDataSize <> 0 then
        Move( s[1], lpData^, lpdwDatasize );

      result := DP_OK;
      exit;
    end;

    Result := dp3.Receive (lpidFrom, lpidTo, dwFlags, lpData, lpdwDataSize);

    if Result = DP_OK then
      begin
      if lpidfrom = DPID_SYSMSG then
        begin
        if (longword(lpdata^) = DPSYS_HOST) then

          ServerPlayer := Players[1]
        else if (longword(lpdata^)=DPSYS_DESTROYPLAYERORGROUP) and (TAStatus = InBattleRoom) then
          Players.Remove( PDPMsg_DestroyPlayerGroup (lpData)^.TDPID, PlayerLefted );
        end
      else
        begin
        bogustill := lpidTo;
        s := PtrToStr (lpdata, lpdwDataSize);
        if UseCompression then
          try
            UseCompression := False;
          s := PacketHandler( s, lpidfrom, bogustill );
          finally
            UseCompression := True;
          end
        else
          s := PacketHandler( s, lpidfrom, bogustill );
        if datachanged then
          begin
          datachanged := false;

          if length (s) > bufsize then
            begin
            {$IFDEF Debug}
            SendChat( 'Overflow correction 2');
            {$ENDIF}
            lpdwdatasize := length (s) + 10;
            Result := DPERR_BUFFERTOOSMALL;
            p := TPacket.Create( s );
            try
              SendLocal( p.rawdata2, 0, true, false);
            finally
              p.free;
            end;
            exit;
            end;
          lpdwDataSize := length(s);
          if lpdwDataSize <> 0 then
            Move( s[1], lpData^, lpdwDataSize );
          end;
        end;
      end
    else if (Result <> DPERR_NOMESSAGES) and (Result <> DPERR_BUFFERTOOSMALL) then
      TLog.add(2, 'In TDPlay.Receive: '+ErrorString( result ) );
except
  on E: Exception do
    begin
    LogException(E);
    try
      errorAddress := Longword(ExceptAddr);
      SendChat('Exception caught in TDPlay.Receive; $'+IntToHex(errorAddress,8));
      if not MapFileSetup then
        LoadAndParseMapFile;
      errorAddress2 := GetMapAddressFromAddress(errorAddress);
      s := GetModuleNameFromAddress(errorAddress2);
      if s <> '' then
        begin
        SendChat(s+':'+GetProcNameFromAddress(errorAddress2)+':'+GetLineNumberFromAddress(errorAddress2));
        end;
      SendChat(e.message);

      if E is EInvalidPointer then
        raise e at ExceptAddr
      else if crash then
        raise e at ExceptAddr
      else
        begin
        ExceptMessage;
        Result := DP_OK;
        end;
    finally
      TLog.Flush;
      if logsave <> nil then
        try
          logsave.Flush;
        except
        end;

    end;
    end;
end;
finally
  cs.Release;
end;
end;

function TDPlay.GetFixFacExps : Boolean;
begin
Result := Fixon and fFixFacExps;
end;

function TDPlay.GetProtectDT : Boolean;
begin
Result := Fixon and fProtectDT;
end;

{$I Misc_Commands.inc}
{$I server_commands.inc}
{$I self_commands.inc}

function TDPlay.OnException(E: Exception) : boolean;
begin
LogException(E);
result := true;

end;

procedure TDPlay.ExceptMessage;
begin

SendLocal( #$19#$00#$01, 0, true, true);

SendChat( 'The affected person is: ' + Players[1].Name);

SendChat( 'The recorder has caused an illegal operation. If');
SendChat( 'you want to help us fix this bug, do the following:');
SendChat( ' 1)  Type .crash and unpause. This will cause TA to quit.');
SendChat( ' 2)  Send the file "errorlog.txt" from your TA dir to us.');
SendChat( '     Please send the file immediately after TA exits.');
SendChat( 'You can shutdown the recorder by typing .panic (hopefully)')
end;

function TDPlay.GetGoodSource :integer;
var
  cur :integer;
  i   :integer;
  max :longword;
begin
// BUGFIX: Guard against empty Players list and invalid index access
if Players.Count <= 0 then
  begin
  TLog.add(4, 'ERROR: GetGoodSource called with empty Players list!');
  Result := 1;  // Return safe default (will be guarded by caller)
  Exit;
  end;

max := 0;
cur := 1;
// Safely iterate from player 2 onwards
for i := 2 to Players.Count do
  if Players[i].LastMsgTimeStamp > max then
    begin
    max := Players[i].LastMsgTimeStamp;
    cur := i;
    end;

// Ensure returned index is within bounds
if (cur < 1) or (cur > Players.Count) then
  cur := 1;

Result := cur;
end;

procedure TDPlay.OnRemovePlayer(player : TPlayerData);
begin
if IniSettings.BattleRoomEnh then
begin
  Player.ModInfo.ModID := -1;
  Player.ModInfo.ModMajorVer := '0';
  Player.ModInfo.ModMinorVer := '0';
  BroadcastModInfo;
end;
if (player = ServerPlayer) then
  ServerPlayer := nil;
end;

function FindHostPlayer(
                          DPID: TDPID;
                          dwPlayerType: DWORD;
                          const lpName: TDPName;
                          dwFlags: DWORD;
                          lpContext: Pointer) : BOOL;  stdcall;
var
  self : TDPlay;
  playerCaps : TDPCaps;
  player : TPlayerData;
begin
result := true;
self := TDPlay(lpContext);

Fillchar(playerCaps,sizeof(playerCaps),0);
playerCaps.dwSize := sizeof(playerCaps);
self.dp3.GetPlayerCaps(dpId,playerCaps,DPGETCAPS_GUARANTEED );

if (playerCaps.dwFlags and DPCAPS_ISHOST) = DPCAPS_ISHOST then
  begin
  player := self.Players.Convert(dpId, ZI_InvalidPlayer, false);
  if player <> nil then
    self.ServerPlayer := player;
  result := false;
  end

end;

function TDPlay.GetServerPlayer : TPlayerData;
begin
if ServerPlayer = nil then
  dp3.EnumPlayers( nil, @FindHostPlayer, pointer(self), 0 );
result := ServerPlayer;
end;

function TDPlay.ImServer : boolean;
begin
result := Players[1] = GetServerPlayer();
end;

function TDPlay.Open(var lpsd: TDPSessionDesc2; dwFlags: longword) : HResult;
begin
try
cs.Acquire;
try
  TLog.add(2, 'TDPlay.Open, dwFlags = $'+IntToHex( dwFlags, 8 ) );

  lpsd.dwFlags := lpsd.dwFlags or DPSESSION_KEEPALIVE or DPSESSION_MIGRATEHOST;
  Result := dp3.Open (lpsd, dwFlags);
  if Result = DP_OK then
    begin
    ResetRecorder;

    end
  else if Result <> DPERR_TIMEOUT then
    TLog.add(2, 'In TDPlay.Open: '+ErrorString( result ) );
{$IFDEF ThreadLogging}  ThreadLogger.LogThreadID;{$ENDIF}
finally
  cs.Release;
end;
except
  on e : Exception do
    begin
    if OnException(e) then raise else Result := DP_OK;
    end;
end;
end;

function TDPlay.Close: HResult;

begin
try
cs.Acquire;
try

{$IFDEF ThreadLogging}  ThreadLogger.LogThreadID;{$ENDIF}
  Exiting;
  Result := dp3.Close;
finally
  cs.Release;
end;
except
  on e : Exception do
    begin
    if OnException(e) then raise else Result := DP_OK;
    end;
end;
end;

procedure TDPlay.ResetRecorder;
var
  reg :TRegIniFile;
begin
cs.Acquire;
try
  reg := TRegInifile.Create('Software\TA Patch\TA Demo');
try
{$IFDEF ThreadLogging}
  ThreadLogger.KnownThreads.Clear;
{$ENDIF}
  if chatview <> nil then
    begin
    fillchar(chatview^,sizeof(MKChatMem), 0);
    chatview^.TAStatus := 1;
    if TAStatus <> InGame then
    begin
      if Assigned(trCheckMemoryCheats) then
        trCheckMemoryCheats.Enabled:= False;
      if Assigned(trCheckProhibitedProcesses) then
        trCheckProhibitedProcesses.Enabled:= False;
    end;
    MyCheats := 0;
    end;
  fillchar(fBattleRoomState,sizeof(fBattleRoomState),0);
  fBattleRoomStateUpdated := false;
  fBattleRoomState.SlowSpeed := 1;
  fBattleRoomState.FastSpeed := 20;
  foldBattleRoomState := fBattleRoomState;

  ServerPlayer := nil;
  PacketsToFilter := nil;
  TAStatus := InBattleRoom;
  keyboardHookLevel:= 1;

  IsRecording := false;

  fixon := True;
  DecompressionBufferSize := reg.ReadInteger( 'Options', 'DecompressionBufferSize', 2048);

  fixfacexps := reg.ReadBool ('Options', 'fixall', False);
  protectdt := reg.ReadBool ('Options', 'fixall', False);
  shareMapPos := reg.ReadBool ('Options', 'sharepos', True);
  createTxtFile:= reg.ReadBool ('Options', 'createtxt', False);

  logpl:=false;
  EmitBuggyVersionWarnings := reg.ReadBool( 'Options', 'EmitBuggyVersionWarnings', False );
  AutoRecording := reg.ReadBool( 'Options', 'autorec', False );
  auto3d := reg.ReadBool( 'Options', 'ta3d', True );
  UseCompression := reg.ReadBool( 'Options', 'usecomp', False );
  RecordPlayerNames := reg.ReadBool( 'Options', 'playernames', True );
  serverdir := IncludeTrailingPathDelimiter(reg.ReadString ( 'Options', 'serverdir', ''));
  demodir := reg.ReadString('Options', 'defdir', '');

  if reg.ReadString('Options', 'TADir', '') = '' then
    reg.WriteString('Options', 'TADir', ParamStr(0));

  if demodir <> '' then
  begin
    demodir := IncludeTrailingPathDelimiter(demodir);
    try
      if IniSettings.modid > 0 then
      begin
        if IniSettings.name <> '' then
          ForceDirectories(demodir+IncludeTrailingPathDelimiter(fnRemoveInvalidChar(IniSettings.name)))
        else
          ForceDirectories(demodir);
      end else
        ForceDirectories(demodir);
    except
      on e : EInOutError do
        demodir := '';
    end;
  end;
  if demodir = '' then
  begin
    demodir := GetMyDocs();
    if demodir <> '' then
    begin
      demodir := IncludeTrailingPathDelimiter(demodir)+'My Games\Total Annihilation\demos\';
      try
        ForceDirectories( demodir );
      except
        on e : EInOutError do
          demodir := '';
      end;
      if demodir <> '' then
        reg.WriteString( 'Options', 'defdir', demodir );
    end;
  end;

  crash := false;
  TADemoRecorderOff := false;
  IsInGame := False;
  fakecd := false;

  OldMapX := high(word);
  OldMapY := high(word);

  QuickBaseEnabled := true;

  onlyunits := false;
  notime := true;

  fakewatch := false;
  FileName := '';
  unitdata := '';

  LOS_extensions.ResetShareLosState;
  SpeedHack.ResetGameSpeedLimits;

  NotViewingRecording:=true;
  use3d := false;
  oldMyCheats:=0;

  CompatibleTA := IsTAVersion31;
  forcego:=False;
  UnitStatus := nil;
  maxunits := 0;

  waitsync:=0;
  chatlog := '';
  crcattempts:=0;

  ai := '';

  NoRecording := false;

  AlliedMarkerQueue.Clear;
  MessageQueue.Clear;
  Players.Clear();

  TLog.add(1,'initialization finished');
finally
  reg.free;
end;
finally
  cs.Release;
end;
end;

procedure TDPlay.Exiting();
var
  LogFile : TTextFile;
  i : Integer;
  reg : TRegInifile;
begin
cs.Acquire;
try
  if assigned ( logsave ) then
    begin
    TLog.Add (1,'flushing recording');
    FreeAndNil( logsave );
    end;
  if assigned ( statslog ) then
    begin
    statslog.GameFinished_StatEvent(TAData.GameTime);
    TLog.Add (1,'flushing stats');
    FreeAndNil( statslog );
    end;

if not IsInGame then Exit;
IsInGame := False;
TADemoRecorderOff := True;
try

  reg := TRegInifile.Create ('Software\TA Patch\TA Demo');
  try
    reg.WriteInteger( 'Options', 'DecompressionBufferSize', DecompressionBufferSize);
  finally
    reg.Free;
  end;

  if assigned ( logsave ) then
    begin
    TLog.Add (1,'flushing recording');
    FreeAndNil( logsave );
    end;
  if assigned ( statslog ) then
    begin
    TLog.Add (1,'flushing stats');
    FreeAndNil( statslog );
    end;

  if not (filename='') and createtxtfile and IsRecording then
    begin
    FileName := ChangeFileExt( filename, '.txt');

    LogFile := TTextFile.Create_Rewrite( filename );
    try
      Logfile.Writeln( 'Num players: '+IntToStr(Players.Count));
      Logfile.Writeln( 'Players in game:');
      for i := 1 to Players.Count do
        Logfile.Writeln( Players[i].Name);
      Logfile.Writeln( 'Map played: '+mapname);
      Logfile.Writeln( 'Max units: '+inttostr(maxunits));
      Logfile.Writeln( 'Date recorded: '+datetostr (now));
      Logfile.Writeln( 'Chat msgs sent:' );

      Logfile.Writeln( chatlog );
    finally
      FreeAndNil( LogFile );
    end;
    filename:='';
    end;

  TLog.Flush;

  if assigned(chatview) then
    chatview^.tastatus := 1000;

except
  on e : Exception do
     begin
     if OnException(e) then raise;
     end;
end;
finally
  IsRecording := false;
  cs.Release;
end;
end;

constructor TDPlay.Create (realdp :IDirectPlay);
begin
  inherited Create;
  cs := SyncObjs.TCriticalSection.create;

{$IFDEF DplayRedirector}
  dp1 := nil;
  dp3 := dp_redirector;
{$ELSE}
  dp1 := realdp;
  dp1.QueryInterface (IID_IDirectPlay3, dp3);
{$ENDIF}

  OpenMemMap( hMemMap, chatview );

  AlliedMarkerQueue := TStringQueue.Create;
  MessageQueue := TStringQueue.Create;
  Commands := TCommands.create;
  fPlayers := TPlayers.create(sendchatlocal,OnRemovePlayer,GetServerPlayer);

  {$I AddCommands.inc}

  GlobalDPlay:= Self;

  ResetRecorder;
end;

destructor TDPlay.Destroy;
begin
GlobalDPlay.trCheckMemoryCheats.Free;
GlobalDPlay.trCheckProhibitedProcesses.Free;

GlobalDPlay:= nil;
  cs.Acquire;
  cs.Release;
Exiting;
{$IFDEF FindRetAddr}
TLog.Add( 0, 'Dplay.Send caller :'+IntToHex( SendReturnAddr, 8 ) );
TLog.Add( 0, 'Dplay.Receive caller :'+IntToHex( RecieveReturnAddr, 8 ) );
{$ENDIF}
{$IFDEF ThreadLogging}
 ThreadLogger.Report;
 ThreadLogger.KnownThreads.Clear;
{$ENDIF}
if Commands <> nil then
  FreeAndNil( Commands );
Players.Clear();
FreeAndNil( fPlayers );
FreeAndNil( AlliedMarkerQueue );
FreeAndNil( MessageQueue );
FreeAndNil( Log_ );
CleanUpMapFile;
FreeAndNil( cs );
inherited;
end;

end.
