unit HangWatch;

{
  HangWatch - writes where the game is stuck when it freezes ("Not responding").

  A freeze leaves no ErrorLog/CrashTrace report, because nothing crashes.
  This plugin runs a small background thread:
    - every second it pings the game window (WM_NULL, 2 s timeout);
    - when the window has not answered for HANG_SECS seconds it suspends the
      game's main thread for a moment, copies its registers and stack,
      resumes it, and writes the code addresses found on the stack (with the
      module they belong to) to  <TA folder>\tplayx_hang.log ;
    - while the freeze lasts it repeats that every REPEAT_SECS seconds (max
      MAX_DUMPS times), so we can see whether it is stuck in one place (a
      deadlock) or looping.
  Nothing is written while the game is healthy.

  While the main thread is suspended the thread only copies memory (no heap,
  no loader calls), so it cannot deadlock against the thread it inspects.

  Off switch without rebuilding: empty file  hangwatch.off  in the game folder.
}

interface

uses
  PluginEngine;

Procedure OnInstall;
Procedure OnUninstall;

const
  State_HangWatch : boolean = true;

function GetPlugin : TPluginData;

implementation

uses
  Windows,
  SysUtils;

const
  HANG_SECS   = 8;
  REPEAT_SECS = 20;
  MAX_DUMPS   = 4;
  STACK_DW    = 4096;            // 16 KB of stack
  MAX_HITS    = 160;

  MY_THREAD_GET_CONTEXT   = $0008;
  MY_THREAD_SUSPEND_RESUME = $0002;
  MY_THREAD_QUERY_INFO    = $0040;
  MY_SMTO_ABORTIFHUNG     = $0002;

function MyOpenThread(dwDesiredAccess: DWORD; bInheritHandle: BOOL; dwThreadId: DWORD): THandle;
  stdcall; external 'kernel32.dll' name 'OpenThread';
function MySendMessageTimeout(h: HWND; Msg: UINT; w: WPARAM; l: LPARAM; flags, timeout: UINT;
  res: PDWORD): LRESULT; stdcall; external 'user32.dll' name 'SendMessageTimeoutA';

var
  StopFlag   : boolean = false;
  ThreadH    : THandle = 0;
  LogPath    : string = '';
  Installed  : boolean = false;
  FoundWnd   : HWND;
  FoundArea  : Integer;

  // filled while the main thread is suspended - static, no heap use
  SnapCtx    : TContext;
  SnapStack  : array[0..STACK_DW - 1] of Cardinal;
  SnapCount  : Integer;
  SnapChain  : array[0..31] of Cardinal;
  SnapChainN : Integer;

procedure HLog(const s : string);
var
  f : TextFile;
begin
  try
    AssignFile(f, LogPath);
    if FileExists(LogPath) then Append(f) else Rewrite(f);
    Writeln(f, FormatDateTime('hh:nn:ss', Now) + ' ' + s);
    CloseFile(f);
  except
  end;
end;

function EnumProc(h : HWND; l : LPARAM) : BOOL; stdcall;
var
  pid : DWORD;
  r   : TRect;
  a   : Integer;
begin
  result := True;
  pid := 0;
  GetWindowThreadProcessId(h, @pid);
  if (pid <> GetCurrentProcessId) or not IsWindowVisible(h) then Exit;
  if not GetWindowRect(h, r) then Exit;
  a := (r.Right - r.Left) * (r.Bottom - r.Top);
  if a > FoundArea then
  begin
    FoundArea := a;
    FoundWnd := h;
  end;
end;

function FindGameWindow : HWND;
begin
  FoundWnd := 0;
  FoundArea := -1;
  EnumWindows(@EnumProc, 0);
  result := FoundWnd;
end;

function Readable(a : Cardinal; len : Cardinal) : boolean;
var
  mbi : TMemoryBasicInformation;
begin
  result := False;
  if VirtualQuery(Pointer(a), mbi, SizeOf(mbi)) = 0 then Exit;
  if mbi.State <> MEM_COMMIT then Exit;
  if (mbi.Protect and (PAGE_NOACCESS or PAGE_GUARD)) <> 0 then Exit;
  result := (a + len) <= (PtrUInt(mbi.BaseAddress) + mbi.RegionSize);
end;

function IsCode(a : Cardinal) : boolean;
var
  mbi : TMemoryBasicInformation;
begin
  result := False;
  if a < $10000 then Exit;
  if VirtualQuery(Pointer(a), mbi, SizeOf(mbi)) = 0 then Exit;
  if mbi.State <> MEM_COMMIT then Exit;
  result := (mbi.Protect and (PAGE_EXECUTE or PAGE_EXECUTE_READ or
                               PAGE_EXECUTE_READWRITE or PAGE_EXECUTE_WRITECOPY)) <> 0;
end;

function Where(a : Cardinal) : string;
var
  mbi  : TMemoryBasicInformation;
  name : array[0..MAX_PATH] of AnsiChar;
  base : Cardinal;
begin
  result := Format('%.8x', [a]);
  if VirtualQuery(Pointer(a), mbi, SizeOf(mbi)) = 0 then Exit;
  base := PtrUInt(mbi.AllocationBase);
  if (mbi._Type = MEM_IMAGE) and
     (GetModuleFileNameA(HMODULE(base), name, MAX_PATH) > 0) then
    result := result + Format('  %s+%x', [ExtractFileName(string(name)), a - base])
  else
    result := result + '  (no module - JIT/hook stub)';
end;

// Copies the main thread's registers and stack while it is suspended.
function Snapshot(tid : DWORD) : boolean;
var
  th  : THandle;
  esp, ebp, i, n : Cardinal;
begin
  result := False;
  SnapCount := 0;
  SnapChainN := 0;
  th := MyOpenThread(MY_THREAD_GET_CONTEXT or MY_THREAD_SUSPEND_RESUME or MY_THREAD_QUERY_INFO, False, tid);
  if th = 0 then Exit;
  try
    if SuspendThread(th) = DWORD(-1) then Exit;
    try
      FillChar(SnapCtx, SizeOf(SnapCtx), 0);
      SnapCtx.ContextFlags := CONTEXT_CONTROL or CONTEXT_INTEGER;
      if not GetThreadContext(th, SnapCtx) then Exit;
      esp := SnapCtx.Esp;
      n := 0;
      while (n < STACK_DW) and Readable(esp + n * 4, 4) do
      begin
        SnapStack[n] := PCardinal(esp + n * 4)^;
        Inc(n);
      end;
      SnapCount := n;
      ebp := SnapCtx.Ebp;
      i := 0;
      while (i < 32) and (ebp > esp) and Readable(ebp, 8) do
      begin
        SnapChain[i] := PCardinal(ebp + 4)^;
        Inc(i);
        if PCardinal(ebp)^ <= ebp then Break;
        ebp := PCardinal(ebp)^;
      end;
      SnapChainN := i;
      result := True;
    finally
      ResumeThread(th);
    end;
  finally
    CloseHandle(th);
  end;
end;

procedure WriteSnapshot(tid : DWORD; hungFor : Integer; dumpNo : Integer);
var
  i, hits : Integer;
begin
  HLog(Format('=== game window not responding for %d s - main thread %d - dump %d of %d ===',
              [hungFor, tid, dumpNo, MAX_DUMPS]));
  HLog('EIP ' + Where(SnapCtx.Eip));
  HLog(Format('EAX=%.8x EBX=%.8x ECX=%.8x EDX=%.8x ESI=%.8x EDI=%.8x EBP=%.8x ESP=%.8x',
              [SnapCtx.Eax, SnapCtx.Ebx, SnapCtx.Ecx, SnapCtx.Edx, SnapCtx.Esi,
               SnapCtx.Edi, SnapCtx.Ebp, SnapCtx.Esp]));
  HLog('EBP chain (return addresses):');
  for i := 0 to SnapChainN - 1 do
    HLog('  ' + Where(SnapChain[i]));
  HLog(Format('code addresses on the stack (first %d of %d dwords scanned):', [MAX_HITS, SnapCount]));
  hits := 0;
  for i := 0 to SnapCount - 1 do
    if IsCode(SnapStack[i]) then
    begin
      HLog(Format('  [esp+%.4x] ', [i * 4]) + Where(SnapStack[i]));
      Inc(hits);
      if hits >= MAX_HITS then Break;
    end;
end;

function WatchThread(Parameter : Pointer) : PtrInt;
var
  wnd     : HWND;
  tid     : DWORD;
  res     : DWORD;
  hungFor : Integer;
  sinceDump, dumps : Integer;
begin
  result := 0;
  hungFor := 0;
  dumps := 0;
  sinceDump := 0;
  wnd := 0;
  while not StopFlag do
  begin
    Sleep(1000);
    if StopFlag then Break;
    try
      if (wnd = 0) or not IsWindow(wnd) then
      begin
        wnd := FindGameWindow;
        hungFor := 0;
        if wnd = 0 then Continue;
      end;
      res := 0;
      if MySendMessageTimeout(wnd, WM_NULL, 0, 0, MY_SMTO_ABORTIFHUNG, 2000, @res) <> 0 then
      begin
        if hungFor >= HANG_SECS then
          HLog(Format('game window responding again after %d s', [hungFor]));
        hungFor := 0;
        sinceDump := 0;
        Continue;
      end;
      Inc(hungFor, 3);                // ~1 s sleep + up to 2 s timeout
      Inc(sinceDump, 3);
      if (hungFor >= HANG_SECS) and (dumps < MAX_DUMPS) and
         ((dumps = 0) or (sinceDump >= REPEAT_SECS)) then
      begin
        tid := GetWindowThreadProcessId(wnd, nil);
        if Snapshot(tid) then
        begin
          Inc(dumps);
          sinceDump := 0;
          WriteSnapshot(tid, hungFor, dumps);
        end
        else
          HLog(Format('freeze detected (%d s) but could not read thread %d', [hungFor, tid]));
      end;
    except
      on e : Exception do HLog('watch error: ' + e.Message);
    end;
  end;
end;

Procedure OnInstall;
var
  tid : TThreadID;
  dir : string;
begin
  if Installed then Exit;
  Installed := True;
  dir := ExtractFilePath(ParamStr(0));
  LogPath := dir + 'tplayx_hang.log';
  if FileExists(dir + 'hangwatch.off') then Exit;
  StopFlag := False;
  ThreadH := THandle(BeginThread(nil, 0, @WatchThread, nil, 0, tid));
end;

Procedure OnUninstall;
begin
  StopFlag := True;
  if ThreadH <> 0 then
  begin
    WaitForSingleObject(ThreadH, 4000);
    CloseHandle(ThreadH);
    ThreadH := 0;
  end;
end;

function GetPlugin : TPluginData;
begin
  if not State_HangWatch then
  begin
    result := nil;
    Exit;
  end;
  result := TPluginData.create( true,
                                'Hang watch (freeze diagnostics)',
                                State_HangWatch,
                                @OnInstall, @OnUninstall );
end;

end.
