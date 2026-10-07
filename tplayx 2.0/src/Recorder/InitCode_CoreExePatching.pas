unit InitCode_CoreExePatching;

interface

implementation
uses
  windows,
  sysutils,
  logging,
  Dplayx_exports,
  PluginEngine,
  InitCode;

{$Q-}

procedure LibraryProc(Reason: Integer);
begin
if Reason = DLL_PROCESS_DETACH then
  begin
  if assigned(DoFinalize) then
    DoFinalize();
  end;
end;

var
  CodeInjectionData : TCodeInjectionData;

procedure InitThunk_Stage2; stdcall;
begin
UnSpliceJump( CodeInjectionData );
if Assigned(DoInitialize) then
  try
    DoInitialize( true );
  except
    On e : Exception do
      begin
      LogException(e);
      if e is EValidationFailed then
        raise;
      end;
  end;
end;

procedure InitThunk_Stage1;
asm
  call InitThunk_Stage2;

  push $004E6FA0;
  ret;
end;

initialization
  DoInitialize := @OnInitialize;
  DoFinalize := @OnFinalize;

  CodeInjectionData.AddyToPatch := Pointer($004E6FA0);
  CodeInjectionData.MyAddy := @InitThunk_Stage1;
  SpliceInJump( CodeInjectionData );

finalization
  if Assigned(DoFinalize) then
    DoFinalize();
end.
