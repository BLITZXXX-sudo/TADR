unit ErrorLog_ExtraData;

interface
uses
  PluginEngine;

function GetPlugin : TPluginData;

Procedure Errorlog_Thunk1;

implementation
uses
  Windows,
  SysUtils,
  Contnrs,
  Classes,
  TADemoConsts,
  TA_MemoryLocations,
  TA_FunctionsU,
  logging;

Procedure OnInstall;
begin
end;

Procedure OnUnInstall;
begin
end;

function GetPlugin : TPluginData;
begin
  if IsTAVersion31 then
  begin
    Result := TPluginData.Create( False,
                                  'Errorlog extra data',
                                  True,
                                  @OnInstall,
                                  @OnUnInstall );

    Result.MakeRelativeJmp( True,
                            'Errorlog extra data',
                            @Errorlog_Thunk1,
                            $004D989B, 2 );

    Result.MakeReplacement( True,
                            'Errorlog entry spacer from 5 to 1 line',
                            $0050C35C,
                            [$0A, 0] );
  end else
    Result := nil;
end;

type
  TModuleInfo = class
    name: String;
    Fullimagepath: String;
    imagepath: String;
    basePTR: Pointer;
    size: LongWord;

    Constructor Create(aname, aimagepath: String; abasePTR: Pointer; asize: LongWord);
  end;

const
  TH32CS_SNAPMODULE = $00000008;

type
  PMODULEENTRY32 = ^MODULEENTRY32;
  MODULEENTRY32 = record
    dwSize: DWORD;
    th32ModuleID: DWORD;
    th32ProcessID: DWORD;
    GlblcntUsage: DWORD;
    ProccntUsage: DWORD;
    modBaseAddr: PByte;
    modBaseSize: DWORD;
    hModule: HMODULE;
    szModule: array[0..255] of AnsiChar;
    szExePath: array[0..MAX_PATH-1] of AnsiChar;
  end;
  TModuleEntry32 = MODULEENTRY32;

function CreateToolhelp32Snapshot(dwFlags, th32ProcessID: DWORD): THandle; stdcall;
  external 'kernel32.dll' name 'CreateToolhelp32Snapshot';
function Module32First(hSnapshot: THandle; var lpme: MODULEENTRY32): BOOL; stdcall;
  external 'kernel32.dll' name 'Module32First';
function Module32Next(hSnapshot: THandle; var lpme: MODULEENTRY32): BOOL; stdcall;
  external 'kernel32.dll' name 'Module32Next';

Constructor TModuleInfo.Create(aname, aimagepath: String; abasePTR: Pointer; asize: LongWord);
begin
  name := aname;
  Fullimagepath := aimagepath;
  imagepath := AnsiLowerCase(ExtractFileDir(aimagepath));
  basePTR := abasePTR;
  size := asize;
end;

function ModuleInfoComparer(Item1, Item2: Pointer): Integer;
begin
  if Longword(TModuleInfo(Item1).basePTR) > Longword(TModuleInfo(Item2).basePTR) then
    result := 1
  else if Longword(TModuleInfo(Item1).basePTR) < Longword(TModuleInfo(Item2).basePTR) then
    result := -1
  else
    result := 0
end;

Procedure Errorlog_Thunk2( filehandle: THandle ); stdcall;
var
  data: String;
  DataWritten: LongWord;
  ModuleSnap: THandle;
  me32: MODULEENTRY32;

  moduleList: TObjectList;
  item: TModuleInfo;
  i: Integer;

  systemPath: String;
begin
  try

    ModuleSnap := CreateToolhelp32Snapshot( TH32CS_SNAPMODULE, 0 );
    if( ModuleSnap <> INVALID_HANDLE_VALUE ) then
      try

        me32.dwSize := sizeof( MODULEENTRY32 );

        if not Module32First( ModuleSnap, me32 ) then
          exit;
        moduleList := TObjectList.create(True);
      try

        systemPath := AnsiLowerCase( ExcludeTrailingPathDelimiter( GetSysDir() ) );

        repeat
          moduleList.Add( TModuleInfo.create( PAnsiChar(@me32.szModule[0]),
                                              PAnsiChar(@me32.szExePath[0]),
                                              me32.modBaseAddr,
                                              me32.modBaseSize) );
        until not Module32Next( ModuleSnap, me32 );

        moduleList.Sort( ModuleInfoComparer );

        data := '';
        if moduleList.count > 0 then
          data := 'Modules:' +#13#10;
        for i := 0 to moduleList.count-1 do
          begin
          item := TModuleInfo(moduleList[i]);
          if item.imagepath = systemPath then
            continue;
          data := data +
                  item.name+ ' : ' +
                  IntToHex(Longword(item.basePTR),8) +' : '+
                  IntToHex(item.size,8) +' : '+
                  GetFileVersion(item.Fullimagepath) + #13#10;
          end;

        if length(data) > 0 then
        begin
          data := data + #13#10 + #13#10 + #13#10 + #13#10 + #13#10;
          WriteFile( filehandle, data[1], length(data), DataWritten, nil );
        end;
      finally
        moduleList.free;
      end;
      finally

        CloseHandle( ModuleSnap );
      end;
  finally
    CloseHandle(filehandle);
  end;
  if TLog <> nil then
    TLog.Flush;
end;

Procedure Errorlog_Thunk1;
asm
  push esi
  Call Errorlog_Thunk2;

  push $4D98A2
  call PatchNJump;
end;

end.
