unit InitCode_CoreExePatching;
// todo : Write code to programically find the TA exe base incase it has been relocated
{
http://blogs.msdn.com/oleglv/archive/2003/10/24/56141.aspx

The following operations are specifically identified as being safe to perform inside a DllMain function: 

�Initialization statics and globals. 

�Calling functions in Kernel32.dll. This is always safe since Kernel32.dll must be loaded by the time DllMain is called. 

�Creating synchronization objects such as critical sections and mutexes.

�Accessing Thread Local Storage (TLS). 


The OS loader lock prohibits:
�Dynamic binds. That includes LoadLibrary/UnloadLibrary calls or anything that
 may call implicitly call them

�Locking of any kind. If you are trying to acquire a lock that is currently
 help by a thread that needs OS loader lock (which you may be holding),
 you'll deadlock.

�Cross-binary calls. As been discussed the binary youre calling into may not
 have been initialized or have already been unutilized.

�Starting new threads and then wait for completion. As discussed, thread in
 question may need to acquire OS lock that you are holding.

So we on-demand load stuff and work out some better finalization code
}
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

{
  A 2 stage process to thunk between the TA exe and the TADR init code.

  The 1st stage is a thin asm shim which thunks betwen the raw asm of the TA exe
  and the pascal code in the 2nd stage.
  The 2nd stage is written in pure pascal, and handles calling the dynamic
  InitCode function and Unsplicing the jump insert.
}

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
  // push the return addres for the 'ret' instruction to jump to
  // 3.1       004E6FA0
  // Boneyards 004E0FD1
  push $004E6FA0;
  ret;
end;

initialization
  DoInitialize := @OnInitialize;
  DoFinalize := @OnFinalize;

  CodeInjectionData.AddyToPatch := Pointer($004E6FA0);
  CodeInjectionData.MyAddy := @InitThunk_Stage1;
  SpliceInJump( CodeInjectionData );

  // NOTE: previously used System.DllProc to detect DLL_PROCESS_DETACH and
  // call DoFinalize from there (a Delphi RTL hook not reliably present in FPC).
  // Replaced with the 'finalization' section below, which both Delphi and
  // FPC guarantee runs on library/unit unload.

finalization
  if Assigned(DoFinalize) then
    DoFinalize();
end.
