unit InputHook;
interface
uses
  PluginEngine,
  PluginCommandHandlerU;

Procedure AddInputHook( CommandHandler : TCommandHandlerEvent; command: string);
Procedure RemoveInputHook( command: string);

Function GetPlugin : TPluginData;

var
  PluginCommands : TPluginCommands;
implementation
uses
  sysutils,
  classes,
  TA_FunctionsU;

Procedure AddInputHook( CommandHandler : TCommandHandlerEvent; command: string);
var
  CommandHandlerObj : TCommandHandler;
begin
if length(command) <= 0 then exit;
if command[1] in ['+','.'] then
  begin
  delete(command,1,1);
  if length(command) <= 0 then exit;
  end;
assert(PluginCommands <> nil);
CommandHandlerObj := PluginCommands.LookUpCommand(command);
if CommandHandlerObj = nil then
  PluginCommands.AddCommand(command,'','',0,false,false,true,false,CommandHandler);
end;

Procedure RemoveInputHook( command: string);
begin
if length(command) <= 0 then exit;
if command[1] in ['+','.'] then
  begin
  delete(command,1,1);
  if length(command) <= 0 then exit;
  end;
assert(PluginCommands <> nil);
PluginCommands.RemoveCommand(command);
end;

Procedure InputHandler(var CommandText : PChar; access : Longint); stdcall;
var
  Head, Tail: PChar;
  EOS : boolean;
var
  command,param : string;
  params : TStringList;
  CommandHandler : TCommandHandler;
  AllowTAToProcessCommand : boolean;
begin

CommandHandler := nil;
params := nil;
try
Tail := CommandText;
repeat
 while Tail^ = ' ' do
    Inc(Tail);
  Head := Tail;
  while (Tail^ <> ' ') and (Tail^ <> #0) do
    Inc(Tail);
  EOS := Tail^ = #0;
  if (Head <> Tail) and (Head^ <> #0) then
    begin
    if command = '' then
      begin
      SetString(command, Head, Tail - Head);
      CommandHandler := PluginCommands.LookUpCommand(command);
      if CommandHandler = nil then
        break;
      end
    else
      begin
      if params = nil then
        params := TStringList.Create;
      SetString(param, Head, Tail - Head);
      params.Add(param);
      end;
    end;
  inc(Tail);
until EOS;
except
 Exit;
end;

if assigned(CommandHandler) then
  begin
  if params = nil then
    params := TStringList.Create;

  AllowTAToProcessCommand := CommandHandler.CommandHandler(command,params);
  end
else
  AllowTAToProcessCommand := true;

if AllowTAToProcessCommand then
  DoInterpretCommand(CommandText,access);
end;

Procedure OnInstall;
begin
if PluginCommands = nil then
  PluginCommands := TPluginCommands.Create;
end;

Procedure OnUnInstall;
begin
FreeAndNil(PluginCommands);
end;

Function GetPlugin : TPluginData;
begin
result := TPluginData.Create(true,'TA Input extender',true,OnInstall,OnUnInstall);

result.MakeStaticCall(true, '', @InputHandler, $417B9B );
end;

end.
