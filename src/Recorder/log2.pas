unit log2;

interface
uses
  gphugef,
  PacketBufferU;
type
  TLog2 = class
  private
    FileName : string;
    filehandle : TGpHugeFile;
    HasFlushed : boolean;
    Broken : boolean;   // 16P safety: set on first I/O error, then logging stops
  public
    crc :longword;
    docrc :boolean;
    constructor Create (const Filename :string);
    destructor Destroy; override;

    procedure Add( const text :string ); overload;
    procedure Add( const data : TArrayOfByte ); overload;

    procedure Flush();
  end;

implementation

uses
  windows,
  SysUtils,
  TADemoConsts,
  textdata,
  logging,
  uDebug;

constructor TLog2.Create(const Filename :string);
begin
inherited Create;
Self.Filename := Filename;

filehandle := TGpHugeFile.CreateEx( FileName,
                                    FileAttributes,
                                    AccessMode[true],
                                    ShareFlags[IsWin9x]);
Win32Check(filehandle.RewriteEx(1,1024,0,0,[hfoBuffered,hfoCompressed],0) <> hfError);
HasFlushed := true;
crc := 0;
docrc := false;
end;

procedure TLog2.Flush();
begin
if Broken or (filehandle = nil) then exit;
if not HasFlushed then
  begin
  HasFlushed := true;
  try
    filehandle.Flush;
  except
    on E: Exception do
      begin
      Broken := true;
      try TLog.Add(0, 'TLog2.Flush failed, demo recording stopped: ' + E.Message); except end;
      end;
  end;
  end;
end; {Flush}

procedure TLog2.Add(const text :String);
var
  ReturnAddr : longword;
  len : Integer;
begin
assert( filehandle <> nil );
len := Length(text);
if len > 0 then
  begin
  if Broken then exit;
  HasFlushed := false;
  try
    filehandle.BlockWriteUnsafe( text[1], len );
  except
    on E: Exception do
      begin
      Broken := true;
      try TLog.Add(0, 'TLog2.Add failed, demo recording stopped: ' + E.Message); except end;
      exit;
      end;
  end;
  if docrc then
    crc := CalcCRC(crc, @text[1], len);
  end
else
  begin
  asm
    PUSH EAX;
    MOV EAX,[EBP+4];
    MOV ReturnAddr, EAX;
    POP EAX;
  end;
  TLog.Add(0,'Empty string passed to TLog2.Add from $'+IntToHex( ReturnAddr, 8) );
  LogError( ReturnAddr );
  end;
end;

procedure TLog2.Add( const data : TArrayOfByte );
var
  ReturnAddr : Longword;
  len : Integer;
begin
assert( filehandle <> nil );
len := Length(data);
if len > 0 then
  begin
  if Broken then exit;
  HasFlushed := false;
  try
    filehandle.BlockWriteUnsafe( data[0], len );
  except
    on E: Exception do
      begin
      Broken := true;
      try TLog.Add(0, 'TLog2.Add failed, demo recording stopped: ' + E.Message); except end;
      exit;
      end;
  end;
  if docrc then
    crc := CalcCRC( crc, @data[0], len);
  end
else
  begin
  asm
    PUSH EAX;
    MOV EAX,[EBP+4];
    MOV ReturnAddr, EAX;
    POP EAX;
  end;
  TLog.Add(0,'Empty data passed to TLog2.Add from $'+IntToHex( ReturnAddr, 8) );
  LogError( ReturnAddr );
  end;
end; {Add}

destructor TLog2.Destroy;
begin
FreeAndNil( filehandle );
inherited Destroy;
end;

end.
