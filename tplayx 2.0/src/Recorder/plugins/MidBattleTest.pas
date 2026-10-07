{$MODE DELPHI}
unit MidBattleTest;

interface

uses
  PluginEngine;

const
  MidBattleEnabled : Boolean = {$IFDEF TESTBUILD}True{$ELSE}False{$ENDIF};

function GetPlugin : TPluginData;

implementation

{$Q-}{$R-}

uses
  Windows, SysUtils, Classes, Math,
  InputHook, PluginCommandHandlerU,
  TA_MemoryStructures, TA_MemoryLocations, TA_MemoryConstants, TA_MemUnits,
  TA_MemPlayers, TA_FunctionsU;

const
  MAIN_PTR      = $00511DE8;
  OFS_GAME_TICK = $38A47;
  ENTRY_TICK    = $00490C40;
  PRO_TICK : array[0..4] of Byte = ($A1, $E8, $1D, $51, $00);
  MAX_TYPES     = 8;
  MID_DEPTH     = 6;
  SideName : array[Boolean] of string = ('west', 'east');

type
  TMidCfg = record
    Count, Cap, Side, Spread, CenterX, CenterZ, TargetX : Integer;
    Types : string;
  end;

  TMidCmd = class
    function CmdMidBattle(const Command : string; params : TStringList) : Boolean;
    function CmdMidCharge(const Command : string; params : TStringList) : Boolean;
  end;

var
  CmdObj   : TMidCmd = nil;
  LogPath  : string = '';
  CmdPath  : string = '';
  LastPoll : LongInt = 0;
  Wave     : Integer = 0;
  LastTick : LongInt = MaxInt;

procedure MLog(const s : string);
var f : Text;
begin
  if LogPath = '' then Exit;
  {$I-}
  AssignFile(f, LogPath);
  if FileExists(LogPath) then System.Append(f) else Rewrite(f);
  if IOResult = 0 then
  begin
    Writeln(f, FormatDateTime('hh:nn:ss', Now), ' pid ', GetCurrentProcessId, '  ', s);
    CloseFile(f);
  end;
  IOResult;
  {$I+}
end;

procedure Say(const s : string);
begin
  MLog(s);
  try SendTextLocal(s); except end;
end;

function GameTick : LongInt;
begin
  Result := PLongInt(PByte(PLongWord(MAIN_PTR)^) + OFS_GAME_TICK)^;
end;

function BytesAre(addr : LongWord; const expect : array of Byte) : Boolean;
var i : Integer;
begin
  Result := True;
  for i := 0 to High(expect) do
    if PByte(addr + LongWord(i))^ <> expect[i] then begin Result := False; Exit; end;
end;

function DefaultCfg : TMidCfg;
begin
  Result.Count := 20; Result.Cap := 0; Result.Side := 0; Result.Spread := 1200;
  Result.CenterX := 50; Result.CenterZ := 50; Result.TargetX := 0;
  Result.Types := 'ARMSTUMP,ARMFLASH';
end;

function ParseCfg(params : TStringList) : TMidCfg;
var i, p : Integer; k, v : string;
begin
  Result := DefaultCfg;
  if params = nil then Exit;
  for i := 0 to params.Count - 1 do
  begin
    p := Pos('=', params[i]);
    if p = 0 then Continue;
    k := LowerCase(Trim(Copy(params[i], 1, p - 1)));
    v := Trim(Copy(params[i], p + 1, MaxInt));
    if k = 'count' then Result.Count := Max(1, StrToIntDef(v, Result.Count))
    else if k = 'cap' then Result.Cap := Max(0, StrToIntDef(v, 0))
    else if k = 'side' then Result.Side := Max(-1, Min(1, StrToIntDef(v, 0)))
    else if k = 'spread' then Result.Spread := Max(64, StrToIntDef(v, Result.Spread))
    else if k = 'cx' then Result.CenterX := Min(95, Max(5, StrToIntDef(v, 50)))
    else if k = 'cz' then Result.CenterZ := Min(95, Max(5, StrToIntDef(v, 50)))
    else if k = 'target' then Result.TargetX := StrToIntDef(v, 0)
    else if k = 'units' then Result.Types := UpperCase(v);
  end;
end;

function FindUnitInfo(const name : string) : PUnitInfo;
var i : Integer; ui : PUnitInfo;
begin
  Result := nil;
  for i := 0 to Integer(TAData.UnitInfosCount) - 1 do
  begin
    ui := TAMem.UnitInfoId2Ptr(i);
    if ui = nil then Continue;
    if SameText(string(PAnsiChar(@ui^.szUnitName[0])), name) or
       SameText(string(PAnsiChar(@ui^.szName[0])), name) then
    begin
      Result := ui; Exit;
    end;
  end;
end;

function LiveUnits(pl : Integer; skipFirst : Boolean; out first, last : PUnitStruct) : Integer;
var p : PPlayerStruct; u : PUnitStruct;
begin
  Result := 0; first := nil; last := nil;
  p := TAPlayer.GetPlayerByIndex(pl);
  if (p = nil) or (p^.lPlayerActive = 0) then Exit;
  first := p^.p_UnitsArray; last := p^.p_LastUnit;
  if (first = nil) or (last = nil) or (PtrUInt(last) < PtrUInt(first)) then Exit;
  u := first;
  if skipFirst then Inc(u);
  while PtrUInt(u) <= PtrUInt(last) do
  begin
    if u^.nUnitInfoID <> 0 then Inc(Result);
    Inc(u);
  end;
end;

procedure CenterCamera(pxX, pxZ : Integer);
var x, z, w, h : Integer; m : PByte;
begin
  m := PByte(PLongWord(MAIN_PTR)^);
  w := PLongInt(m + $37E1F)^;
  h := PLongInt(m + $37E23)^;
  if (w <= 0) or (h <= 0) then Exit;
  x := Max(0, pxX - (w - 128) div 2);
  z := Max(0, pxZ - (h - 64) div 2);
  ScrollView(x, z, True);
end;

function Side(const c : TMidCfg; me : Integer) : Integer;
begin
  if c.Side <> 0 then Result := c.Side
  else if Odd(me) then Result := -1 else Result := 1;
end;

function TMidCmd.CmdMidBattle(const Command : string; params : TStringList) : Boolean;
var
  c : TMidCfg;
  me, sd, i, nt, cell, slot, tries, spawned, depth, lane, lat, cx, cz, gx, gz, x, z, h, mapW, mapH, want, live : Integer;
  jx, jz, wet : Integer;
  l : TStringList;
  types : array[0..MAX_TYPES - 1] of PUnitInfo;
  ui : PUnitInfo;
  pos, tpos : TPosition;
  haveTarget : Boolean;
  state : LongWord;
  u, f, e : PUnitStruct;
begin
  Result := True;
  c := ParseCfg(params);
  me := TAData.LocalPlayerID;
  if me >= MAXPLAYERCOUNT then begin Say('midbattle: no local player'); Exit; end;
  if GameTick < LastTick then Wave := 0;
  LastTick := GameTick;
  live := LiveUnits(me, True, f, e);
  want := c.Count;
  if c.Cap > 0 then want := Min(c.Count, c.Cap - live);
  if want <= 0 then begin MLog(Format('midbattle: %d live >= cap %d, nothing spawned', [live, c.Cap])); Exit; end;
  sd := Side(c, me);
  mapW := TAData.MainStruct.TNTMemStruct.lMapWidth;
  mapH := TAData.MainStruct.TNTMemStruct.lMapHeight;
  cx := mapW * c.CenterX div 100; cz := mapH * c.CenterZ div 100;
  gx := cx + sd * c.Spread; gz := cz;
  nt := 0; cell := 32;
  l := TStringList.Create;
  try
    l.CommaText := c.Types;
    for i := 0 to l.Count - 1 do
      if nt < MAX_TYPES then
      begin
        ui := FindUnitInfo(Trim(l[i]));
        if ui = nil then begin MLog('midbattle: unit ' + l[i] + ' not found'); Continue; end;
        types[nt] := ui; Inc(nt);
        cell := Max(cell, Max(Integer(ui^.nFootPrintSizeX), Integer(ui^.nFootPrintSizeZ)) * 16);
      end;
  finally
    l.Free;
  end;
  if nt = 0 then begin Say('midbattle: none of the units exist (' + c.Types + ')'); Exit; end;
  cell := cell + 16;

  if sd > 0 then gx := Min(gx, mapW - 32 - MID_DEPTH * cell)
  else gx := Max(gx, 32 + MID_DEPTH * cell);
  haveTarget := GetTPosition(cx + c.TargetX, cz, tpos) <> nil;
  jx := ((Wave mod 3) - 1) * (cell div 3);
  jz := (((Wave div 3) mod 3) - 1) * (cell div 3);
  Inc(Wave);
  spawned := 0; slot := -1; tries := 0; wet := 0;
  while (spawned < want) and (tries < want * 6) do
  begin
    Inc(slot); Inc(tries);
    depth := slot mod MID_DEPTH;
    lane := slot div MID_DEPTH;
    if lane = 0 then lat := 0
    else if Odd(lane) then lat := (lane + 1) div 2
    else lat := -(lane div 2);
    x := gx + sd * depth * cell + jx;
    z := gz + lat * cell + jz;
    if (x <= 16) or (z <= 16) or (x >= mapW - 16) or (z >= mapH - 16) then Continue;
    if GetTPosition(x, z, pos) = nil then Continue;
    ui := types[slot mod nt];
    if (ui^.UnitTypeMask and 2048) = 2048 then
    begin
      if ui^.nCruiseAlt > 0 then pos.Y := ui^.nCruiseAlt * 65536;
      state := 6;
    end else
    begin
      h := GetPosHeight(@pos);
      if h < Integer(TAData.MainStruct.TNTMemStruct.SeaLevel) then
      begin
        Inc(wet);
        Continue;
      end;
      pos.Y := h * 65536;
      state := 1;
    end;
    u := TAUnit.CreateUnit(me, ui, pos, nil, False, True, state);
    if u <> nil then
    begin
      Inc(spawned);
      if TAData.NetworkLayerEnabled then
        Send_UnitBuildFinished(u, u);
      if haveTarget then
        TAUnit.CreateMainOrder(u, nil, Action_Patrol, @tpos, 0, 0, 0);
    end;
  end;
  if Wave = 1 then
    try CenterCamera(cx, cz); except end;
  Say(Format('midbattle: player %d spawned %d units %s of the centre at (%d,%d), live %d, %d water spots skipped',
             [me, spawned, SideName[sd > 0], gx, gz, live + spawned, wet]));
end;

function TMidCmd.CmdMidCharge(const Command : string; params : TStringList) : Boolean;
var
  c : TMidCfg;
  me, n, cx, cz : Integer;
  u, f, e : PUnitStruct;
  tpos : TPosition;
begin
  Result := True;
  c := ParseCfg(params);
  me := TAData.LocalPlayerID;
  if me >= MAXPLAYERCOUNT then Exit;
  cx := TAData.MainStruct.TNTMemStruct.lMapWidth * c.CenterX div 100;
  cz := TAData.MainStruct.TNTMemStruct.lMapHeight * c.CenterZ div 100;
  if GetTPosition(cx + c.TargetX, cz, tpos) = nil then Exit;
  LiveUnits(me, True, f, e);
  if f = nil then Exit;
  n := 0;
  u := f; Inc(u);
  while PtrUInt(u) <= PtrUInt(e) do
  begin
    if u^.nUnitInfoID <> 0 then
    begin
      TAUnit.CreateMainOrder(u, nil, Action_Patrol, @tpos, 0, 0, 0);
      Inc(n);
    end;
    Inc(u);
  end;
  MLog(Format('midcharge: %d units patrolling to (%d,%d)', [n, cx + c.TargetX, cz]));
end;

procedure PollCmdFile;
var l, prm : TStringList; i, t : Integer; s, w : string;
begin
  t := GameTick;
  if (t - LastPoll < 15) and (t >= LastPoll) then Exit;
  LastPoll := t;
  if not FileExists(CmdPath) then Exit;
  l := TStringList.Create;
  prm := TStringList.Create;
  try
    try l.LoadFromFile(CmdPath); except Exit; end;
    DeleteFile(CmdPath);
    for i := 0 to l.Count - 1 do
    begin
      s := Trim(l[i]);
      if s = '' then Continue;
      if s[1] = '+' then Delete(s, 1, 1);
      prm.DelimitedText := s;
      if prm.Count = 0 then Continue;
      w := LowerCase(prm[0]);
      prm.Delete(0);
      if w = 'midbattle' then CmdObj.CmdMidBattle(w, prm)
      else if w = 'midcharge' then CmdObj.CmdMidCharge(w, prm)
      else MLog('unknown command ' + s);
    end;
  finally
    prm.Free;
    l.Free;
  end;
end;

procedure TickWork;
begin
  try
    if CmdObj <> nil then PollCmdFile;
  except
    on E : Exception do MLog('tick exception: ' + E.Message);
  end;
end;

procedure Tick_Stub; assembler; nostackframe;
asm
  pushad
  pushfd
  call TickWork
  popfd
  popad
  mov  eax, dword ptr [$00511DE8]
  push dword $00490C45
  ret
end;

procedure OnInstall;
begin
  if CmdObj = nil then CmdObj := TMidCmd.Create;
  AddInputHook(CmdObj.CmdMidBattle, 'midbattle');
  AddInputHook(CmdObj.CmdMidCharge, 'midcharge');
end;

procedure OnUninstall;
begin
end;

function GetPlugin : TPluginData;
var dir : string;
begin
  Result := nil;
  if not MidBattleEnabled then Exit;
  dir := ExtractFilePath(ParamStr(0));
  LogPath := dir + 'midbattle.log';
  CmdPath := dir + 'aio_' + IntToStr(GetCurrentProcessId) + '.cmd';
  if not BytesAre(ENTRY_TICK, PRO_TICK) then
  begin
    MLog('MidBattleTest NOT installed: unexpected bytes at 00490C40');
    Exit;
  end;
  MLog('MidBattleTest installed (TEST BUILD) - commands from ' + ExtractFileName(CmdPath));
  Result := TPluginData.Create(True, 'MidBattleTest (test build only)', True, @OnInstall, @OnUninstall);
  Result.MakeRelativeJmp(True, 'MidBattleTest tick', @Tick_Stub, ENTRY_TICK, 0);
end;

end.
