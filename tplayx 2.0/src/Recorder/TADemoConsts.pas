unit TADemoConsts;

interface
uses
  windows,
  gphugef;
const

  FILE_FILE_COMPRESSION = $00000010;

  UNITSPACE = 5000;

  TADemoVersion_OTA = 0;
  TADemoVersion_97   = 1;
  TADemoVersion_98b1 = 2;
  TADemoVersion_99b2 = 3;
  TADemoVersion_99b3_beta1 = 4;
  TADemoVersion_99b3_beta2 = 5;

  TADemoVersion_99b3_beta3 = 6;
  TADemoVersion_4 = 7;

  TADemoVersion_99b3 = TADemoVersion_99b3_beta3;
  TADemoVersion_Current = TADemoVersion_99b3_beta3;

  FlushDeltaTime = 30*1000;
const
  NumDeities = 13;
  Deities :array[1..NumDeities] of string = ('Allah', 'Shiva', 'Odin', 'Zeus', 'Jehova', 'Buddha', 'Zarathustra', 'Thor', 'Mammon', 'Uncle Sam', 'Ra', 'Bill Gates', 'Sugar the Snow Fairy');

const
  NOP_Instruction      = $90;
  RelativeJump_Instruction = $e9;

function GetFileVersion(const aFileName: String ): String;

function GetTADemoVersion: string;
function SelfLocation : string;

Function IsWin9x : boolean;

Function SupportsCompression( const path : string) : boolean;

const
  FileAttributes = FILE_FLAG_SEQUENTIAL_SCAN;
  AccessMode : array [boolean] of longword = (GENERIC_READ, GENERIC_READ or GENERIC_WRITE);
  ShareFlags : array [boolean] of longword = (FILE_SHARE_READ or FILE_SHARE_DELETE, FILE_SHARE_READ);
  FileFlags : array [boolean] of THFOpenOptions = ([hfoBuffered], [hfoBuffered,hfoCompressed]) ;

function TempPath : string;
function MakeTempFilename : string;

var
  kernellib : Thandle;

function GetSysDir : string;
Function GetAppData : string;
Function GetMyDocs : string;

implementation
uses
  classes,
  sysutils,
  logging,
  SHFolder;

function GetMyDocs : string;
var
  len : longword;
  lpszPath : PChar;
begin
len := 2*MAX_PATH;
SetLength( result, len );
lpszPath := @result[1];
SHGetFolderPath( 0, CSIDL_PERSONAL, 0,0,lpszPath );
result := lpszPath;
end;

function GetAppData : string;
var
  len : longword;
  lpszPath : PChar;
  sAppData: String;
begin
  Result := '';
  len := 2*MAX_PATH;
  SetLength( result, len );
  lpszPath := @result[1];
  SHGetFolderPath(0, CSIDL_LOCAL_APPDATA, 0, 0, lpszPath);
  sAppData := IncludeTrailingPathDelimiter(lpszPath) + 'TADR\';
  if not DirectoryExists(sAppData) then
  begin
    try
      if CreateDir(sAppData) then
        Result := sAppData;
    except
    end;
  end else
    Result := sAppData;
end;

function GetSysDir : string;
var
  len : longword;
begin
len := 2*MAX_PATH;
SetLength( Result, len );
len := GetSystemDirectory( @Result[1], len );

SetLength( Result, len );
if len = 0 then
  RaiseLastOSError;

if len > 2*MAX_PATH then
  GetSystemDirectory( @Result[1], len );
Result := IncludeTrailingPathDelimiter(Result);
end;

var
  fIsWin9x : boolean;
  fVersionLazyInited : boolean = false;
Function IsWin9x : boolean;
var
  OSVersionInfo : TOSVersionInfo;
begin
if not fVersionLazyInited then
  begin
  fillchar(OSVersionInfo,sizeof(OSVersionInfo),0);
  OSVersionInfo.dwOSVersionInfoSize := sizeof(OSVersionInfo);
  GetVersionEx(OSVersionInfo);
  fIsWin9x := OSVersionInfo.dwPlatformId = VER_PLATFORM_WIN32_WINDOWS;
  fVersionLazyInited := true;
  end;
result := fIsWin9x;
end;

type
  TGetVolumePathNameAHandler = function( lpszFileName : pAnsiChar;
                                        lpszVolumePathName: pAnsiChar;
                                        cchBufferLength : longword) : longbool; stdcall;
var
  proc : TGetVolumePathNameAHandler;
function GetVolumePathName( lpszFileName : pAnsiChar;
                            lpszVolumePathName: pAnsiChar;
                            cchBufferLength : longword ) : longbool; stdcall;
begin
Result := False;
if kernellib = 0 then
  kernellib := LoadLibrary( kernel32 );
if kernellib <> 0 then
  begin
  proc := GetProcAddress( kernellib, 'GetVolumePathNameA' );
  if Assigned(proc) then
    Result := proc( lpszFileName, lpszVolumePathName, cchBufferLength );
  end;
end;

const
  COMPRESSION_FORMAT_DEFAULT = 1;
  FILE_DEVICE_FILE_SYSTEM    = 9;
  METHOD_BUFFERED            = 0;
  FILE_READ_DATA             = 1;
  FILE_WRITE_DATA            = 2;
  FSCTL_SET_COMPRESSION = (FILE_DEVICE_FILE_SYSTEM shl 16) OR
                          ((FILE_READ_DATA OR FILE_WRITE_DATA) shl 14) OR
                          (16 shl 2) OR
                          METHOD_BUFFERED;
  COMPRESSION_FORMAT_NONE    = 0;

function Compress(const fileName: string; fileHandle: THandle): boolean;
var
  comp            : SHORT;
  isFileCompressed: boolean;
  res             : DWORD;
begin
  Result := true;
  if Win32Platform = VER_PLATFORM_WIN32_NT then begin
    isFileCompressed := (GetFileAttributes(PChar(fileName)) AND
      FILE_ATTRIBUTE_COMPRESSED) = FILE_ATTRIBUTE_COMPRESSED;
    if not isFileCompressed then begin
      res := 0;
      comp := COMPRESSION_FORMAT_DEFAULT;
      Result := DeviceIoControl (fileHandle, FSCTL_SET_COMPRESSION, @comp,
        SizeOf(SHORT), nil, 0, res, nil);
    end;
  end;
end;

Function SupportsCompression( const path : string) : boolean;
var
  Rootpath : string;

  VolumeNameBuffer : string;
  VolumeNameBufferLen : integer;
  lpVolumeSerialNumber : longword;
  MaximumComponentLength : longword;
  FileSystemFlags : longword;
  FileSystemNameBuffer : string;
  FileSystemNameBufferLen : integer;

  handle : THandle;
begin
if not IsWin9x then
  begin

  setlength(Rootpath,MAX_PATH+1);
  Win32Check( GetVolumePathName( pchar(path), @Rootpath[1], length(Rootpath)) );
  Rootpath := Pchar(Rootpath);

  VolumeNameBufferLen := MAX_PATH+1;
  setlength(VolumeNameBuffer,VolumeNameBufferLen);
  FileSystemNameBufferLen := MAX_PATH+1;
  setlength(FileSystemNameBuffer,FileSystemNameBufferLen);
  Win32Check( GetVolumeInformation( pchar(Rootpath),
                        @VolumeNameBuffer[1], VolumeNameBufferLen,
                        @lpVolumeSerialNumber,
                        MaximumComponentLength,
                        FileSystemFlags,
                        @FileSystemNameBuffer[1], FileSystemNameBufferLen) );
  VolumeNameBuffer := pchar(VolumeNameBuffer);
  FileSystemNameBuffer := pchar(FileSystemNameBuffer);
  result := (FileSystemFlags and FILE_FILE_COMPRESSION) = FILE_FILE_COMPRESSION;

  if result then
    begin

    handle := CreateFile( pchar(path),
                          GENERIC_READ or GENERIC_WRITE,
                          0, nil,OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL ,0);
    if handle <> INVALID_HANDLE_VALUE then
    try
      result := Compress( path, handle);
    finally
      CloseHandle(handle);
    end;
    end;
  end
else
  result := false;
end;

var
  SelfLocation_cache : string;
function SelfLocation : string;
var
  len : longword;
begin
if SelfLocation_cache = '' then
  begin
  len := 2*MAX_PATH;
  SetLength(Result, len);
  len := GetModuleFileName( HInstance, @Result[1], len );

  SetLength( Result, len );
  if len = 0 then
    RaiseLastOSError;

  if len > 2*MAX_PATH then
    GetModuleFileName( HInstance, @Result[1], len );
  SelfLocation_cache := result;
  end;
result := SelfLocation_cache;
end;

function TempPath: string;
var
	i: integer;
begin
SetLength(Result, MAX_PATH);
i := GetTempPath(Length(Result), PChar(Result));
SetLength(Result, i);
Result := IncludeTrailingPathDelimiter( Result );
end;

function MakeTempFilename : string;
begin
setlength(result, MAX_PATH);
GetTempFileName( pchar(TempPath), 'tad', 0, @result[1]);
result := pchar(result);
end;

function GetFileVersion(const aFileName: String ): String;

  Procedure GetFileVersion_internal(const aFileName: String );
  var
    iBufSize: DWORD;
    iRes: DWORD;
    pBuf: Pointer;
    pFileInfo: Pointer;
    FileName : string;
    pFileName : pchar;
  begin
  try

    FileName := AFileName;
    UniqueString(FileName);
    pFileName := Pchar(FileName);
    iBufSize := GetFileVersionInfoSize(pFileName, iRes);
    if iBufSize = 0 then
      RaiseLastOSError;
    GetMem(pBuf, iBufSize);
    try
      GetFileVersionInfo(pFileName, 0, iBufSize, pBuf);

      VerQueryValue(pBuf, '\', pFileInfo, iRes);

      iRes := PVSFixedFileInfo(pFileInfo)^.dwFileVersionMS;
      Result := IntToStr( HiWord(iRes) );
      Result := Result + '.' + IntToStr( LoWord(iRes) );

      iRes := PVSFixedFileInfo(pFileInfo)^.dwFileVersionLS;
      Result := Result + '.' + IntToStr( HiWord(iRes) );
      Result := Result + '.' + IntToStr( LoWord(iRes) );
    finally
      FreeMem(pBuf);
    end;
  except
    on E : exception do
      begin
      LogException(e);
      result := '';
      end;
  end;
  end;

var
  aNewFileName : string;
begin

if not IsWin9x and
   (ExtractFileName(aFileName) = 'spank.dll') then
  GetFileVersion_internal(aFileName)
else
  begin
  aNewFileName := MakeTempFilename;
  Windows.CopyFile( pchar(aFileName), pchar(aNewFileName), false );
  try
    GetFileVersion_internal(aNewFileName);
  finally
    Windows.DeleteFile( pchar(aNewFileName) );
  end;
  end;
end;

var
  TADemoVersion_cache : string;
function GetTADemoVersion: string;
begin
if TADemoVersion_cache = '' then
  TADemoVersion_cache := GetFileVersion( SelfLocation );
result := TADemoVersion_cache;
end;

end.
