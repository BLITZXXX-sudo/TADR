unit MultiAILimit;

interface
uses
  PluginEngine;

Procedure OnInstall;
Procedure OnUninstall;

const
  State_MultiAILimit : boolean = true;

function GetPlugin : TPluginData;

implementation
uses
  sysutils,
  TADemoConsts,
  TA_MemoryLocations;

Procedure OnInstall;
begin
end;

Procedure OnUninstall;
begin
end;

var
  AIName : string = 'AI:%s %d';
procedure BetterAIName( AIPlayerSlot : integer; name : pchar; buffer : pchar) stdcall;
var
  len : integer;
begin
buffer[16] := #0;
len := FormatBuf(buffer^,16,AIName[1],length(AIName),[name,AIPlayerSlot]);
buffer[len] := #0;
end;

procedure BetterAINameStub;
asm
  mov eax, [esp+$118+4];

  push edx
  push ecx
  push eax

  call BetterAIName

  push $451323;
  call PatchNJump;
end;

function GetPlugin : TPluginData;
begin
if IsTAVersion31 and State_MultiAILimit then
  begin
  result := TPluginData.create( true,
                                'Multi AI Limit',
                                State_MultiAILimit,
                                @OnInstall, @OnUnInstall );
  result.MakeNOPReplacement(State_MultiAILimit,'Remove 1 AI check',$447D87,6);
  result.MakeRelativeJmp(State_MultiAILimit,'Better AI naming',@BetterAINameStub,$45130F,1);

  end
else
  result := nil;
end;

end.
