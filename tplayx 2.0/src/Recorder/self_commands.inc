function TDPlay.OnHelp( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;

  procedure OutputInfo( const Command : string; HelpString : boolean );
  var
    CommandHandler : TCommandHandler;
  begin
  CommandHandler := Commands.LookUpCommand( Command );
  if CommandHandler <> nil then
    begin
    if HelpString then
      SendChatLocal2( CommandHandler.HelpInfo )
    else
      SendChatLocal2( 'Syntax is .'+Command +' '+CommandHandler.Syntax);
    end
  else
    SendChatLocal2( 'Command .'+command+' is not registered' )
  end;

var
  KnownCommands : string;
  i : Integer;
begin
Result := True;
if params.Count <> 0 then
  begin
  if params[0] = 'info' then
    begin
    if params.Count = 1 then
      SendChatLocal('Returns the help information about a command')
    else
      OutputInfo( params[1], True );
    end
  else if params[0] = 'syntax' then
    begin
    if params.Count = 1 then
      SendChatLocal('Returns information about the syntax of a command')
    else
      OutputInfo( params[1], false );
    end
  else if params[0] = 'commands' then
    begin
    KnownCommands := 'Known commands: ';
    for i := 0 to Commands.Count-1 do
      begin
      KnownCommands := KnownCommands + Commands[i].Name;
      if i <> Commands.Count-1 then
        KnownCommands := KnownCommands +', ';
      end;
    SendChatLocal2( KnownCommands );
    end
  else
    OutputInfo( Command, True );
  end
else
  OutputInfo( Command, True );
end;

function TDPlay.OnStatus( const Command : string;  Sender : TPlayerData; params : TStringList ) : Boolean;
begin
Result := True;
sendchatlocal('TA demo recorder ' + GetTADemoVersion + ' ('+getRecorderStatusString+')');
datachanged := true;

end;

function TDPlay.OnYankSpank( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
begin
Result := True;
SendChat('One free krogoth for every Swede');
end;

function TDPlay.OnCrashMe( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
begin
raise Exception.Create('Crash Me');
end;

function TDPlay.OnLoggingVerbosity( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
begin
Result := True;
if params.Count >= 1 then
  begin
  Log_.VerboseLoggingLevel := StrToInt(params[0]);
  SendChatLocal('Setting logging verbosity level to '+IntToStr(Log_.VerboseLoggingLevel));
  end
else
  SendChatLocal('Current logging verbosity level:'+IntToStr(Log_.VerboseLoggingLevel));
end;

function TDPlay.OnCrash( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
begin
Result := True;
if not crash then
  begin
  SendChatLocal ('Recorder will not catch exceptions');
  SendChatLocal ('If TA crashes, please send your errorlog.txt to us');

  crash := true;
  end
else
  begin
  SendChatLocal ('Recorder will catch exceptions');
  crash := false;
  end;
end;

function TDPlay.OnPanic( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
begin
Result := True;
SendChatLocal('Recorder for '+Players[1].name+' off');
TADemoRecorderOff := True;
end;

function TDPlay.OnAbout( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
begin
Result := True;
SendChatLocal('TA demo recorder ' + GetTADemoVersion);
SendChatLocal('Written by SY_SJ and SY_Fnordia');
SendChatLocal('Updated by Xon, Xpoy and Rime');
SendChatLocal('Visit http://www.tauniverse.com for more info');
end;

function TDPlay.OnFixall( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
begin
Result := True;
if fixon then
  begin
  protectdt := true;
  fixfacexps := true;

  SendChatLocal('All fixes turned on');
  end
else
  SendChatLocal('Lag fixes are disabled by the host');
end;

function TDPlay.OnFixFactoryExplosions( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
begin
Result := True;
if not fixon then
  begin
  SendChatLocal('Lag fixes disabled');
  Exit;
  end;
if fixfacexps then
  begin
  fixfacexps := false;
  SendChatLocal('Factory explosion fix disabled');
  end
else
  begin
  fixfacexps := true;
  SendChatLocal('Factory explosion fix enabled');
  end;
end;

function TDPlay.OnProtectdt( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
begin
Result := True;
if not fixon then
  begin
  SendChatLocal('Lag fixes disabled');
  Exit;
  end;
if protectdt then
  begin
  protectdt:=false;
  SendChatLocal('Missing DT fix disabled');
  end
else
  begin
  protectdt:=true;
  SendChatLocal('Missing DT fix enabled');
  end;
end;

function TDPlay.OnSharemappos( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
var i : Integer;
begin
Result := True;
if chatview = nil then Exit;
OldMapX := high(word);
OldMapY := high(word);
if shareMapPos or (chatview^.ehaOff>0) then
  begin
  shareMapPos:=false;
  for i :=1 to 10 do
    begin
    chatview^.otherMapX[i]:=-1;
    chatview^.otherMapY[i]:=-1;
    end;
  SendRecorderToRecorderMsg2( #$fc#$ff#$ff#$ff#$ff );
  SendChatLocal('Toggled ShareMapPos to: OFF');
  end
else
  begin
  ShareMapPos := true;
  SendChatLocal('Toggled ShareMapPos to: ON');
  end;
end;

function TDPlay.OnTime( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
var
  i : Integer;
  tmp : String;
begin
Result := True;
SendChatLocal ('Current position of the players:');
for i := 1 to Players.Count do
  begin
  tmp := IntToStr ((Players[i].LastTimeStamp div 30) mod 60);
  if length (tmp) = 1 then
    tmp := '0' + tmp;
  SendChatLocal (' (' + IntToStr (Players[i].LastTimeStamp div 1800)+':'+ tmp + ') - ' +Players[i].name);

  end;

end;

function TDPlay.OnReportFilter( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
var
  I : Integer;
  s : string;
begin
Result := True;
if PacketsToFilter <> nil then
  begin
  SendChatLocal('Packet filtering enabled');
  s := '';
  for i :=  0 to High(PacketsToFilter) do
    s := s+'$'+InttoHex(PacketsToFilter[i],2)+' ';
  SendChatLocal('Filtering out '+s);
  end
else
  SendChatLocal('Packet filtering disabled');
end;

function TDPlay.OnDisableFilter( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
begin
Result := True;
if PacketsToFilter <> nil then
  begin
  PacketsToFilter := nil;
  SendChatLocal('Packet filtering disabled');
  end;
end;

function TDPlay.OnAddFilter( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
var
  I, i2, count : Integer;
  s : string;
  Filter : Byte;
  DuplicateFilter : Boolean;
  PacketsToFilter2 : TArrayOfByte;
begin
Result := True;
if params.Count <> 0 then
  begin
  if PacketsToFilter = nil then
    SendChatLocal('Packet filtering enabled');
  s := '';
  setlength( PacketsToFilter2, Length(PacketsToFilter)+params.Count );
  for i := 0 to High(PacketsToFilter) do
    PacketsToFilter2[i] := PacketsToFilter[i];
  Count := Length(PacketsToFilter);
  for i := 0 to params.Count-1 do
    begin
    if not IsStrByte(params[i],Filter) then
      continue;
    DuplicateFilter := False;
    for i2 := 0 to High(PacketsToFilter2) do
      if Filter = PacketsToFilter2[i2] then
        begin
        DuplicateFilter := True;
        break;
        end;
    if not DuplicateFilter then
      begin
      PacketsToFilter2[count] := Filter;
      s := s+'$'+InttoHex(Filter,2)+' ';
      inc(count);
      end;
    end;
  if s <> '' then
    begin
    setlength( PacketsToFilter2, Count );
    PacketsToFilter := PacketsToFilter2;
    SendChatLocal('Filtering out '+s);
    end;
  end;
end;

function TDPlay.OnRemoveFilter( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
var
  i, i2,i3, Count : Integer;
  s : string;
  PacketsToFilter2 : TArrayOfByte;
  Filter : Byte;
begin
Result := True;
if params.Count <> 0 then
  begin
  s := '';
  Count := Length(PacketsToFilter);
  setlength( PacketsToFilter2, Length(PacketsToFilter) );
  for i := 0 to High(PacketsToFilter) do
    PacketsToFilter2[i] := PacketsToFilter[i];
  for i := 0 to params.Count-1 do
    begin
    Filter := StrToInt(params[i]);
    for i2 := 0 to High(PacketsToFilter2) do
      if Filter = PacketsToFilter2[i2] then
        begin
        s := s+'$'+InttoHex(Filter,2)+' ';
        Dec(Count);
        for i3 := i2 to Count-1 do
          PacketsToFilter2[i3] := PacketsToFilter2[i3+1];
        break;
        end;
    end;
  if s <> '' then
    begin
    setlength( PacketsToFilter2, Count );
    PacketsToFilter := PacketsToFilter2;
    SendChatLocal('Removed filtering of '+s);
    end;
  if PacketsToFilter = nil then
    SendChatLocal('Packet filtering enabled');
  end;
end;

function TDPlay.OnRecord( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
begin
Result := True;
if TAStatus = InBattleRoom then
  begin
  RecordAuto := params.Count = 0;
  if params.Count <> 0 then
    FileName := params[0]
  else
    FileName := '';

  if (ExtractFileExt(FileName)='') and (FileName<>'') and (FileName<>'none') then
    if iniSettings.demosprefix <> '' then FileName := iniSettings.demosprefix + FileName+'.tad' else FileName := FileName+'.tad';
  if RecordAuto then
    begin
    MakeAutoFileName;
    SendChatLocal('Recording to '+ExtractFileName(FileName)+' (auto name, set when the game starts)');
    FileName := '';
    end
  else if FileName<>'none' then
    SendChatLocal('Recording to '+FileName)
  else
    SendChatLocal('Recording disabled');

  if ai <> '' then
    SendChatLocal ('Warning: A custom AI (' + ai + ') is enabled');
  end
else
  begin
  if FileName='' then
    begin
    if params.Count <> 0 then
      FileName := params[0]
    else
      FileName := '';

    if (ExtractFileExt(FileName)='') and (FileName<>'') then
      if iniSettings.demosprefix <> '' then FileName := iniSettings.demosprefix + FileName+'.tad' else FileName := FileName+'.tad';
    if FileName <> '' then
      FileName := removeinvalid (FileName)
    else
      MakeAutoFileName;
    createlogfile();
    end;
  if FileName<>'' then
    begin
    IsRecording := true;
    prevtime := GetTickCount;
    SendChatLocal('Recording to '+ExtractFileName(FileName));
    end;
  end;
end;

function TDPlay.OnRecordStatus( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
var
  value : boolean;
begin
Result := True;
if params.Count = 0 then
  begin
  if NoRecording then
    SendChatLocal('Recording of games disabled')
  else
    SendChatLocal('Recording of games enabled');
  end
else if IsStrBool( params[0], Value ) then
  begin
  if Value then
    begin
    NoRecording := true;
    SendChatLocal('Ok, you will not be able to record');
    end
  else
    begin
    NoRecording := false;
    SendChatLocal('Ok, you will be able to record');
    end
  end
else
  SendChatLocal( 'Paramater not understood, true/false or any numerical integer evaluated to 0/1' );
end;

function TDPlay.On3dta( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
var
  Value : Boolean;
begin
Result := True;
if (params.Count = 0) or (TAStatus = InGame) then
  begin
  if use3d then
    SendChatLocal ('3D TA is enabled')
  else
    SendChatLocal ('3D TA is disabled');
  end
else if IsStrBool( params[0], Value ) then
  begin
  if Value then
    begin
    use3d := true;
    SendChatLocal ('3D TA now enabled');
    end
  else
    begin
    use3d := false;
    SendChatLocal ('3D TA now disabled');
    end
  end
else
  SendChatLocal( 'Paramater not understood, true/false or any numerical integer evaluated to 0/1' );
end;

function TDPlay.OnStopLog( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
begin
Result := True;
IsRecording := False;

SendChatLocal('logging halted');
end;

function TDPlay.OnOnlyUnits( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
begin
Result := True;
if onlyunits then
  begin
  onlyunits := false;
  SendChatLocal('All packets recorded');
  end
else
  begin
  onlyunits := true;
  SendChatLocal('Only the units will be recorded');
  end;
end;

function TDPlay.OnCreatetxt( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
begin
Result := True;
if createtxtfile then
  begin
  createTxtFile:=false;
  SendChatLocal('Not creating a txt file');
  end
else
  begin
  createTxtFile:=true;
  SendChatLocal('Will create a txt file with game info');
  end;
end;

function TDPlay.OnLockOn( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
var
  i : Integer;
  s : string;
begin
Result := True;
if chatview = nil then Exit;
chatview^.lockviewon := 0;
if not NotViewingRecording and (params.Count <> 0) then
  begin
  s := uppercase(params[0]);
  for i:=2 to Players.Count do
    if s = uppercase(Players[i].Name) then
      chatview^.lockviewon := i-1;
  end;
end;

function TDPlay.OnRandMap( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
var
  mapname : string;
begin
Result := True;
if params.Count = 0 then
  mapname := 'maps.txt'
else
  mapname := params[0];

if FileExists( mapname )then
   GetRandomMap(mapname)
else
   GetRandomMap(serverdir + mapname);
end;

function TDPlay.OnFakeWatch( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
begin
Result := True;
if fakewatch then
  begin
  fakewatch := false;
  SendChatLocal('Normal player mode');
  end
else
  begin
  fakewatch := true;
  SendChatLocal('Fake watcher mode');
  end;
end;

function TDPlay.OnForceCd( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
begin
Result := true;
datachanged := true;
fakecd := not fakecd;
if fakecd then
  SendChatLocal( 'Fake CD enabled for '+Players[1].name)
else
  SendChatLocal( 'Fake CD disabled for '+Players[1].Name)
end;

function TDPlay.OnLookUpAddr( const Command : string; Sender : TPlayerData; params : TStringList ) : Boolean;
var
  errorAddress : Longword;
begin
Result := True;
errorAddress := StrToInt(Params[0]);
if not MapFileSetup then
  LoadAndParseMapFile;
errorAddress := GetMapAddressFromAddress(errorAddress);
SendChatLocal('Module:'+GetModuleNameFromAddress(errorAddress));
SendChatLocal('function:'+ GetProcNameFromAddress(errorAddress));
SendChatLocal('line:'+ GetLineNumberFromAddress(errorAddress));
end;
