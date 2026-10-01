unit QueueDiag;

{
  QueueDiag - diagnostic logging for the per-remote-player network queue
              allocator and the 16-slot player table.

  THE PROBLEM THIS MEASURES
  -------------------------
  TA keeps a FIXED table of network queues in .data:

      base    $0051404C
      stride  $00001044
      count   10          <- hard limit: 'cmp eax,0Ah' at $00461657,
                             $00461676 and $004616E6

  NetSend_GetOrCreatePlayerQueue ($00461630) hands out one queue per REMOTE
  player and returns NIL once all ten are gone. Measured live with Frida:

      host owns 8, client owns 8   ->  8 queues,  0 refusals   (works)
      host owns 15, client owns 1  -> 10 queues,  5 refusals   (5 red slots)

  So: a machine may have at most 10 REMOTE players. Beyond that the surplus
  get no queue, their data never flows, and they show a red 'Mem.' cell.

  The table cannot simply be grown - $0051E2F4 onward (where an 11th queue
  would land) already holds ~180 other globals, including TAunitsCategory
  ($0051E6B0) and ScoreBoardRoll ($0051F2D8).

  WHAT THIS UNIT DOES
  -------------------
  Two independent parts, each with its own switch:

    State_QueueDiag        passive. Reads the player table and logs changes.
                           Installs NO code patches. Always safe.

    State_QueueDiag_Hook   active. Splices a jump into
                           NetSend_GetOrCreatePlayerQueue so every allocation
                           is logged with its DPID and the queue it got (or
                           NIL). This is a real code patch - if the game
                           misbehaves, set this to False first.

  Set either to False and rebuild to disable.

  OUTPUT: <TA folder>\queuediag.log
}

interface

uses
  PluginEngine;

Procedure OnInstall;
Procedure OnUninstall;

// Detects and logs player-table changes. Safe to call from anywhere.
Procedure QueueDiag_Poll;

// Logs one roster registration (TDPlay.GetPlayerName -> Players.Add).
Procedure QueueDiag_LogRegister( dpid : Cardinal; const AName : PChar;
                                 ACount : Integer );

// ---------------------------------------------------------------------------
// PACKET CENSUS  ->  packetdiag.log
// ---------------------------------------------------------------------------

// One inbound packet seen by TDPlay.packethandler.
Procedure QueueDiag_CountIn( FromDPID : Cardinal; PacketType : Byte );

// One outbound packet handed to TDPlay.Send.
Procedure QueueDiag_CountOut( ToDPID : Cardinal; PacketType : Byte );

// Write the census table (also written automatically on uninstall).
Procedure QueueDiag_DumpPackets( const Reason : string );

// Engine native function helpers
function TA_DirectID2PlayerAry( dpid : Cardinal ) : Byte;
function TA_GetLocalHumanDPID : Cardinal;
function TA_GetLocalPlayerDPID : Cardinal;

const
  // passive player-table logging - no code patches
  // AUDIT 28 Sep: diagnostic plugin (queuediag.log / packetdiag.log) - debug builds only
  State_QueueDiag      : boolean = {$IFDEF TPLAYX_DEBUG}true{$ELSE}false{$ENDIF};
  State_QueueDiag_Hook : boolean = false;

  QUEUE_TABLE_BASE = $0053304C;  { NQ20 exe: NETQ object moved to .netq 0x532000 (was $0051404C) }
  QUEUE_STRIDE     = $00001044;
  QUEUE_COUNT      = 20;  { NQ20 exe: 20 per-player queues (was 10) }

  ADDR_GETQUEUE      = $00461630;
  ADDR_GETQUEUE_CONT = $00461635;

  // TA Engine Routine Addresses
  ADDR_GETLOCALPLAYERDPID = $0044FDB0; // cdecl
  ADDR_GETLOCALHUMANDPID  = $0044FE00; // stdcall
  ADDR_DIRECTID2PLAYERARY = $0044FE40; // stdcall

function GetPlugin : TPluginData;

implementation

uses
  SysUtils,
  MMSystem,            // timeGetTime, for the poll throttle
  TA_MemoryConstants,
  TA_MemoryStructures,
  TA_MemPlayers;

const
  POLL_INTERVAL_MS    = 250;
  PKT_UNITSTATANDMOVE = $2C;
  MAXPKTPEERS         = 32;

type
  // Engine function prototype definitions
  TDirectID2PlayerAry   = function(dpid: Cardinal): Byte; stdcall;
  TPlayersGetLocalHuman = function: Cardinal; stdcall;
  TGetLocalPlayerDPID   = function: Cardinal; cdecl;

  TPktPeer = record
    DPID    : Cardinal;
    InMove  : Int64;
    OutMove : Int64;
    InAll   : Int64;
    OutAll  : Int64;
  end;

  TSlotSnapshot = record
    Active     : Boolean;
    DPID       : Cardinal;
    Controller : Byte;
    Name       : string;
  end;

var
  LastSnap     : array [0..MAXPLAYERCOUNT-1] of TSlotSnapshot;
  HaveSnap     : Boolean  = False;
  LogPath      : string   = '';
  LogReady     : Boolean  = False;
  WarnedOver   : Boolean  = False;
  PollCount    : Cardinal = 0;
  LastPollTick : Cardinal = 0;

  PktPeers     : array [0..MAXPKTPEERS-1] of TPktPeer;
  PktPeerCount : Integer = 0;

  AllocCalls   : Cardinal = 0;
  AllocFails   : Cardinal = 0;
  LastDPID     : Cardinal = 0;

// -----------------------------------------------------------------------------
// TA Engine Function Wrappers
// -----------------------------------------------------------------------------

function TA_DirectID2PlayerAry(dpid: Cardinal): Byte;
begin
  try
    Result := TDirectID2PlayerAry(Pointer(ADDR_DIRECTID2PLAYERARY))(dpid);
  except
    Result := $10; // $10 = 16 (Not found / Invalid)
  end;
end;

function TA_GetLocalHumanDPID: Cardinal;
begin
  try
    Result := TPlayersGetLocalHuman(Pointer(ADDR_GETLOCALHUMANDPID))();
  except
    Result := $FFFFFFFF;
  end;
end;

function TA_GetLocalPlayerDPID: Cardinal;
begin
  try
    Result := TGetLocalPlayerDPID(Pointer(ADDR_GETLOCALPLAYERDPID))();
  except
    Result := $FFFFFFFF;
  end;
end;

// -----------------------------------------------------------------------------
// Logging Helper
// -----------------------------------------------------------------------------

procedure QLog(const Msg: string);
var
  f : TextFile;
begin
  if not LogReady then Exit;
  try
    AssignFile(f, LogPath);
    {$I-}
    if FileExists(LogPath) then Append(f) else Rewrite(f);
    {$I+}
    if IOResult <> 0 then Exit;
    try
      Writeln(f, FormatDateTime('hh:nn:ss.zzz', Now) + '  ' + Msg);
    finally
      CloseFile(f);
    end;
  except
  end;
end;

// -----------------------------------------------------------------------------
// Player Table Diagnostics
// -----------------------------------------------------------------------------

function ControllerName(c: Byte): string;
begin
  case c of
    1 : Result := 'local-human';
    2 : Result := 'local-AI';
    3 : Result := 'remote';
    4 : Result := 'open';
  else
    Result := 'ctrl=' + IntToStr(c);
  end;
end;

function SafeName(P: PPlayerStruct): string;
var
  i : Integer;
  c : Char;
begin
  Result := '';
  if P = nil then Exit;
  try
    for i := 0 to High(P^.szName) do
    begin
      c := Char(P^.szName[i]);
      if c = #0 then Break;
      if (c < ' ') or (c > #126) then c := '.';
      Result := Result + c;
    end;
  except
    Result := '<unreadable>';
  end;
end;

function GetSlot(Index: Integer; var S: TSlotSnapshot): Boolean;
var
  P : PPlayerStruct;
begin
  Result := False;
  S.Active := False; S.DPID := 0; S.Controller := 0; S.Name := '';
  try
    P := TAPlayer.GetPlayerByIndex(Byte(Index));
    if P = nil then Exit;
    S.Active     := P^.lPlayerActive <> 0;
    S.DPID       := P^.lDirectPlayID;
    S.Controller := Byte(P^.cPlayerController);
    S.Name       := SafeName(P);
    Result       := True;
  except
    Result := False;
  end;
end;

function DescribeDPID(dpid: Cardinal): string;
var
  slot      : Byte;
  S         : TSlotSnapshot;
  localDPID : Cardinal;
  tag       : string;
begin
  Result := '(unknown)';
  if (dpid = 0) or (dpid = $FFFFFFFF) then Exit;

  localDPID := TA_GetLocalHumanDPID;
  if dpid = localDPID then
    tag := ' [THIS MACHINE]'
  else
    tag := '';

  // Use engine DirectID2PlayerAry for O(1) lookup first
  slot := TA_DirectID2PlayerAry(dpid);
  if (slot < MAXPLAYERCOUNT) and GetSlot(slot, S) and S.Active then
  begin
    Result := Format('slot %d "%s" %s%s', [slot, S.Name, ControllerName(S.Controller), tag]);
    Exit;
  end;

  // Fallback iteration
  for slot := 0 to MAXPLAYERCOUNT - 1 do
    if GetSlot(slot, S) and S.Active and (S.DPID = dpid) then
    begin
      Result := Format('slot %d "%s" %s%s', [slot, S.Name, ControllerName(S.Controller), tag]);
      Exit;
    end;
end;

function CountRemote: Integer;
var
  i : Integer;
  S : TSlotSnapshot;
begin
  Result := 0;
  for i := 0 to MAXPLAYERCOUNT - 1 do
    if GetSlot(i, S) and S.Active and (S.Controller = 3) then Inc(Result);
end;

// -----------------------------------------------------------------------------
// Allocator Hook Routine
// -----------------------------------------------------------------------------

procedure LogQueueRequest(dpid: Cardinal); stdcall;
var
  nRemote : Integer;
begin
  if not LogReady then Exit;
  try
    Inc(AllocCalls);

    if dpid = LastDPID then Exit;
    LastDPID := dpid;

    nRemote := CountRemote;
    QLog(Format('QUEUE REQUEST dpid=%.8x  %s   (remote players=%d, queues=%d)',
                [dpid, DescribeDPID(dpid), nRemote, QUEUE_COUNT]));

    if nRemote > QUEUE_COUNT then
    begin
      Inc(AllocFails);
      QLog(Format('    *** %d remote players vs %d queues - %d will get NOTHING',
                  [nRemote, QUEUE_COUNT, nRemote - QUEUE_COUNT]));
    end;
  except
  end;
end;

procedure GetQueueStub;
asm
  mov  eax, [esp+4]

  PushAD
  PushFD

  push eax
  call LogQueueRequest

  PopFD
  PopAD

  push ecx
  push ebx
  mov  ebx, ecx
  push ebp
  push esi

  push ADDR_GETQUEUE_CONT
  call PatchNJump
end;

// -----------------------------------------------------------------------------
// Table Dump Routine
// -----------------------------------------------------------------------------

procedure DumpTable(const Reason: string);
var
  i, nRemote, nLocal : Integer;
  S : TSlotSnapshot;
  localDPID : Cardinal;
  isLocal   : string;
begin
  localDPID := TA_GetLocalHumanDPID;
  QLog('');
  QLog('---- player table (' + Reason + ') ----');
  nRemote := 0;
  nLocal  := 0;

  for i := 0 to MAXPLAYERCOUNT - 1 do
  begin
    if not GetSlot(i, S) then Continue;
    if not S.Active then Continue;
    if S.Controller = 3 then Inc(nRemote) else Inc(nLocal);

    if S.DPID = localDPID then isLocal := ' [LOCAL]' else isLocal := '';

    QLog(Format('  slot %2d  dpid=%.8x  %-12s "%s"%s',
                [i, S.DPID, ControllerName(S.Controller), S.Name, isLocal]));
  end;

  QLog(Format('  locally owned=%d   remote=%d   queue capacity=%d',
              [nLocal, nRemote, QUEUE_COUNT]));
  QLog(Format('  allocator calls=%d', [AllocCalls]));

  if nRemote > QUEUE_COUNT then
  begin
    QLog('');
    QLog(Format('  *** %d remote players but only %d queues.',
                [nRemote, QUEUE_COUNT]));
    QLog(Format('  *** %d player(s) get NO queue -> red Mem. cell, no data.',
                [nRemote - QUEUE_COUNT]));
    QLog('  *** Split ownership so neither machine exceeds 10 remote players.');
  end;
  QLog('');
end;

// ---------------------------------------------------------------------------
// Packet Census
// ---------------------------------------------------------------------------

function PktSlotFor( dpid : Cardinal ) : Integer;
var
  i : Integer;
begin
  for i := 0 to PktPeerCount - 1 do
    if PktPeers[i].DPID = dpid then
    begin
      Result := i;
      Exit;
    end;
  if PktPeerCount >= MAXPKTPEERS then
  begin
    Result := -1;
    Exit;
  end;
  Result := PktPeerCount;
  PktPeers[Result].DPID := dpid;
  PktPeers[Result].InMove  := 0;
  PktPeers[Result].OutMove := 0;
  PktPeers[Result].InAll   := 0;
  PktPeers[Result].OutAll  := 0;
  Inc(PktPeerCount);
end;

Procedure QueueDiag_CountIn( FromDPID : Cardinal; PacketType : Byte );
var
  i : Integer;
begin
  if not State_QueueDiag then Exit;
  i := PktSlotFor( FromDPID );
  if i < 0 then Exit;
  Inc( PktPeers[i].InAll );
  if PacketType = PKT_UNITSTATANDMOVE then
    Inc( PktPeers[i].InMove );
end;

Procedure QueueDiag_CountOut( ToDPID : Cardinal; PacketType : Byte );
var
  i : Integer;
begin
  if not State_QueueDiag then Exit;
  i := PktSlotFor( ToDPID );
  if i < 0 then Exit;
  Inc( PktPeers[i].OutAll );
  if PacketType = PKT_UNITSTATANDMOVE then
    Inc( PktPeers[i].OutMove );
end;

Procedure QueueDiag_DumpPackets( const Reason : string );
var
  i : Integer;
  f : TextFile;
  Path : string;
  localDPID : Cardinal;
  dpidTag   : string;
begin
  if not State_QueueDiag then Exit;
  localDPID := TA_GetLocalHumanDPID;
  Path := ExtractFilePath( ParamStr(0) ) + 'packetdiag.log';
  try
    AssignFile( f, Path );
    if FileExists( Path ) then Append( f ) else Rewrite( f );
    try
      Writeln( f, '' );
      Writeln( f, '==================================================================' );
      Writeln( f, 'packet census (' + Reason + ')  '
                  + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) );
      Writeln( f, 'TA: ' + ParamStr(0) );
      Writeln( f, Format('Local Human DPID: %.8x', [localDPID]) );
      Writeln( f, '' );
      Writeln( f, '  $2C = TANM_UnitStatAndMove (unit movement)' );
      Writeln( f, '' );
      Writeln( f, '  dpid         IN($2C)   OUT($2C)     IN(all)   OUT(all)   Note' );
      Writeln( f, '  --------    --------   --------    --------  --------   ----' );
      for i := 0 to PktPeerCount - 1 do
      begin
        if PktPeers[i].DPID = localDPID then dpidTag := ' [LOCAL]' else dpidTag := '';
        Writeln( f, Format('  %.8x   %8d   %8d    %8d   %8d%s',
                           [PktPeers[i].DPID,
                            PktPeers[i].InMove,  PktPeers[i].OutMove,
                            PktPeers[i].InAll,   PktPeers[i].OutAll,
                            dpidTag]) );
      end;
      Writeln( f, '' );
      Writeln( f, 'Compare with the OTHER machine''s packetdiag.log:' );
      Writeln( f, '  this machine IN($2C) for a dpid  vs' );
      Writeln( f, '  that machine OUT($2C) for the same dpid.' );
      Writeln( f, '  IN noticeably GREATER  -> packets are being DUPLICATED.' );
      Writeln( f, '  roughly EQUAL          -> counts are fine; each packet is' );
      Writeln( f, '                            being over-applied instead.' );
      Writeln( f, '==================================================================' );
    finally
      CloseFile( f );
    end;
  except
  end;
end;

Procedure QueueDiag_LogRegister( dpid : Cardinal; const AName : PChar;
                                 ACount : Integer );
var
  N : string;
begin
  if not State_QueueDiag then Exit;
  if not LogReady then Exit;
  if AName = nil then N := '<nil>' else N := string(AName);
  QLog(Format('REGISTER dpid=%.8x roster#%-3d "%s"', [dpid, ACount, N]));
end;

Procedure QueueDiag_Poll;
var
  i, nRemote : Integer;
  S : TSlotSnapshot;
  Changed : Boolean;
  Now_ : Cardinal;
begin
  if not State_QueueDiag then Exit;
  if not LogReady then Exit;

  Now_ := timeGetTime;
  if (LastPollTick <> 0) and (Now_ - LastPollTick < POLL_INTERVAL_MS) then
    Exit;
  LastPollTick := Now_;

  Inc(PollCount);
  Changed := False;
  nRemote := 0;

  for i := 0 to MAXPLAYERCOUNT - 1 do
  begin
    if not GetSlot(i, S) then Continue;
    if S.Active and (S.Controller = 3) then Inc(nRemote);

    if not HaveSnap then
    begin
      LastSnap[i] := S;
      Continue;
    end;

    if (S.Active     <> LastSnap[i].Active)     or
       (S.DPID       <> LastSnap[i].DPID)       or
       (S.Controller <> LastSnap[i].Controller) or
       (S.Name       <> LastSnap[i].Name)       then
    begin
      Changed := True;
      if S.Active and (not LastSnap[i].Active) then
        QLog(Format('SLOT %2d ADDED     dpid=%.8x %-12s "%s"',
                    [i, S.DPID, ControllerName(S.Controller), S.Name]))
      else if (not S.Active) and LastSnap[i].Active then
        QLog(Format('SLOT %2d REMOVED   was dpid=%.8x "%s"',
                    [i, LastSnap[i].DPID, LastSnap[i].Name]))
      else
        QLog(Format('SLOT %2d CHANGED   dpid %.8x->%.8x  %s->%s  "%s"->"%s"',
                    [i, LastSnap[i].DPID, S.DPID,
                     ControllerName(LastSnap[i].Controller),
                     ControllerName(S.Controller),
                     LastSnap[i].Name, S.Name]));
      LastSnap[i] := S;
    end;
  end;

  if not HaveSnap then
  begin
    HaveSnap := True;
    DumpTable('first poll');
    Exit;
  end;

  if Changed then
    DumpTable('after change');

  if (nRemote > QUEUE_COUNT) and (not WarnedOver) then
  begin
    WarnedOver := True;
    QLog(Format('*** QUEUE LIMIT EXCEEDED: %d remote players, %d queues ***',
                [nRemote, QUEUE_COUNT]));
  end;
  if nRemote <= QUEUE_COUNT then
    WarnedOver := False;
end;

// -----------------------------------------------------------------------------
// Plugin Lifecycle
// -----------------------------------------------------------------------------

Procedure OnInstall;
begin
  LogPath    := ExtractFilePath(ParamStr(0)) + 'queuediag.log';
  LogReady   := True;
  HaveSnap   := False;
  WarnedOver := False;
  PollCount  := 0;
  AllocCalls := 0;
  AllocFails := 0;
  LastDPID   := 0;

  QLog('');
  QLog('==================================================================');
  QLog('QueueDiag installed  ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
  QLog('TA: ' + ParamStr(0));
  QLog(Format('Local Human DPID: %.8x  (Local Player DPID: %.8x)',
              [TA_GetLocalHumanDPID, TA_GetLocalPlayerDPID]));
  QLog(Format('queue table base=%.8x stride=%.4x count=%d  MAXPLAYERCOUNT=%d',
              [QUEUE_TABLE_BASE, QUEUE_STRIDE, QUEUE_COUNT, MAXPLAYERCOUNT]));
  if State_QueueDiag_Hook then
    QLog(Format('allocator hook: ON  (spliced at %.8x)', [ADDR_GETQUEUE]))
  else
    QLog('allocator hook: OFF (passive logging only)');
  QLog('==================================================================');
end;

Procedure OnUninstall;
begin
  if LogReady then
  begin
    DumpTable('final - on uninstall');
    QueueDiag_DumpPackets('final - on uninstall');
    QLog(Format('QueueDiag uninstalled. polls=%d allocator-calls=%d over-limit-events=%d',
                [PollCount, AllocCalls, AllocFails]));
    QLog('==================================================================');
  end;
  LogReady := False;
end;

function GetPlugin : TPluginData;
begin
  if not State_QueueDiag then
  begin
    result := nil;
    Exit;
  end;

  result := TPluginData.create( true,
                                'Queue Diagnostics',
                                State_QueueDiag,
                                @OnInstall, @OnUninstall );

  if State_QueueDiag_Hook then
    result.MakeRelativeJmp( State_QueueDiag_Hook,
                            'Log queue allocations',
                            @GetQueueStub,
                            ADDR_GETQUEUE );
end;

end.
