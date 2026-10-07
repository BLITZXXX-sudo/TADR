unit PacketBufferU;

{$DEFINE SanityAllocCheck}
interface
uses
  sysutils,
  classes,
  ListsU;
const
  DefaultBufferCount = 256;
  DefaultBufferSize = 2048;
  DefaultBufferFragmentCount = 256;
var
  InitialBufferCount : Integer = DefaultBufferCount;
  InitialBufferSize : Integer = DefaultBufferSize;
  InitialBufferFragmentCount : Integer = DefaultBufferFragmentCount;
type

  THeaderState = (

                  hs_CompletePacket,

                  hs_Header,

                  hs_MiniHeader,

                  hs_RawData
                 );
const

  PacketHeaderSize : array [THeaderState] of integer = (
                                                        3,
                                                        3,
                                                        1,
                                                        0
                                                       );

  PacketOverhead : array [THeaderState] of integer = (
                                                        7,
                                                        3,
                                                        1,
                                                        0
                                                       );

Type
  PPacketPayload = ^TPacketPayload;
  TPacketPayload = packed record

    TimeStamp : longword;

    Data : packed array [ 0 .. high(integer) - 5] of Byte;
  end;

Const
  TANM_ChecksummedPacket = $03;

type
  PChecksummedPacket = ^TChecksummedPacket;
  TChecksummedPacket = packed record
    Marker  : byte;
    CheckSum : Word;

  end;

Const
  TANM_CompressedPacket = $04;
type
  PCompressedPacket = ^TCompressedPacket;
  TCompressedPacket = packed record
    Marker  : byte;
    CheckSum : Word;

  end;

type

  TArrayOfByte = array of byte;

  TBufferedData = class;
  TBufferData = class;
  TBufferDataArray = array of TBufferData;

  TBufferData = class
  protected
    fSize : integer;
{$IFDEF SanityAllocCheck}
    WasFragment : boolean;
{$ENDIF}

    fFragments : TBufferDataArray;
    fFragmentCount : integer;

    FFragmentMaxSize : integer;
    fFragmentIndex : integer;

    fBufferedData : TBufferedData;
    Procedure SetDataSize( NewSize : integer);
    Procedure DoGrowth( NewSize : integer);
    Constructor Create(aBufferedData : TBufferedData);
    Procedure MakeFragment(aDataPtr : TArrayOfByte; StartOffset : integer; aSize : integer);
  protected
    fOffsetIndex : integer;
    Procedure SetOffset(Index : integer);
  protected
    fArraySize : integer;
    fData : PByteArray;
    fDataPtr : TArrayOfByte;
    fDataPtr2 : TArrayOfByte;
  public
    HeaderState : THeaderState;
    Destructor Destroy; override;

    Property Data : PByteArray read fData;
    Property DataPtr : TArrayOfByte read fDataPtr;
    Property ArraySize : integer read fArraySize;

    Procedure Reset;

    Property Size : integer read fSize write SetDataSize;

    procedure CheckGrowth( SizeIncrease : integer);

    Property OffsetIndex : integer read fOffsetIndex write SetOffset;

    function ResetOffsetIndex() : integer;

    Property BufferedData : TBufferedData read fBufferedData;

    Procedure InsertData( index : integer;var buff; DataSize : integer);

    Procedure DeleteData( index : integer; len : integer);

    function AddByte( value : byte ) : integer;
    function AddWord( value : word ) : integer;
    function AddDWord( value : longword ) : integer;

    function AddBuffer( SourceBufferData : TBufferData;
                        SourceIndex : integer = 0;
                        SourceLen : integer = -1 ) : integer;

    Procedure SetByte( index : integer; value : byte );
    Procedure SetWord( index : integer; value : word );
    Procedure SetDWord( index : integer; value : longword );

    function GetByte( index : integer ) : byte;
    function GetWord( index : integer) : word;
    function GetDWord( index : integer) : longword;

    function ToString( index : integer = 0; count : integer = -1) : String;
    function FragmentsToString( ) : String;

    Property Fragments : TBufferDataArray read fFragments;
    Property FragmentCount : integer read fFragmentCount;
    Function AllocFragment( StartIndex, aSize : integer) : TBufferData;

    Procedure CompileFragments( DestBuffer : TBufferData ); overload;
    Procedure CompileFragments( ); overload;
    Procedure DiscardFragments( );
  end;

  TBufferedData = class
  protected
    fReleaseList : TStack;
    fFreeList : TStack;

    fBufferCount : integer;
    fCurrent : TBufferData;
{$IFDEF SanityAllocCheck}
    fAllocatedFragments : integer;
{$ENDIF}
    Function GetPendingReleaseCount : integer;
  public
  currentindex : integer;
    Constructor Create;
    Destructor Destroy; override;

    Property BufferCount : integer Read fBufferCount;
    Property PendingReleaseCount : integer Read GetPendingReleaseCount;
    Property Current : TBufferData Read fCurrent;

    Procedure SwapBuffers;
  protected

    Function NewBuffer(AddToReleaseList : boolean) : TBufferData;  overload;
  public
    Function NewBuffer : TBufferData; overload;
    Function PrevBuffer : TBufferData;

    Procedure ReleaseBuffer;

    Procedure DiscardBuffer( BufferData : TBufferData );

    class Function MakeData(var Data : string; size : integer) : pointer;
    class Procedure CopyData(const s : string; offset: integer; size : integer; var dest);
  end;

implementation
uses
  textdata,
  logging;

class Function TBufferedData.MakeData(var Data : string; size : integer) : pointer;
begin
setlength(Data,size);
result := @Data[1];
assert(result <> nil);
end;

class Procedure TBufferedData.CopyData(const s : string; offset: integer; size : integer; var dest);
var
  lenToCopy : integer;
begin
if length(s)-Offset < size then
  lenToCopy := length(s)-Offset
else
  lenToCopy := size;
move(s[offset],dest,lenToCopy);
end;

Constructor TBufferData.Create(aBufferedData : TBufferedData);
begin
fBufferedData := aBufferedData;
HeaderState := hs_RawData;
setlength(fDataPtr2, InitialBufferSize);
fDataPtr := fDataPtr2;
fData := PByteArray(DataPtr);
fArraySize := InitialBufferSize;
end;

Destructor TBufferData.Destroy;
var i : integer;
begin
if fFragments <> nil then
  begin
  for i := length(fFragments)-1 downto 0 do
    FreeAndNil( fFragments[i] );
  fFragments := nil;
  end;
end;

Procedure TBufferData.MakeFragment(aDataPtr : TArrayOfByte; StartOffset : integer; aSize : integer);
begin
HeaderState := hs_RawData;
fSize := aSize;
fDataPtr := aDataPtr;
fArraySize := length(aDataPtr);
fData := @(DataPtr[StartOffset]);
FFragmentMaxSize := aSize;
fFragmentIndex := StartOffset;
{$IFDEF SanityAllocCheck}
WasFragment := true;
{$ENDIF}
end;

Procedure TBufferData.Reset();
begin
HeaderState := hs_RawData;
fDataPtr := fDataPtr2;
fData := @DataPtr[0];
fSize := 0;

DiscardFragments();
fOffsetIndex := 0;
fFragmentIndex := 0;
FFragmentMaxSize := 0;
end;

function TBufferData.ResetOffsetIndex( ) : integer;
begin
result := OffsetIndex;
inc(fSize, result);
fOffsetIndex := 0;
fData := @(DataPtr[fFragmentIndex]);
end;

Procedure TBufferData.SetOffset(Index : integer);
var
  newSize : integer;
begin
newSize := Size-index;
if (newSize > 0) and (newSize < Size) then
  begin
  fOffsetIndex := fOffsetIndex + Index;
  if fFragmentIndex+OffsetIndex >= length(DataPtr) then
    asm int 3 end;
  if fFragmentIndex+OffsetIndex < 0 then
    asm int 3 end;
  fData := PByteArray(@DataPtr[fFragmentIndex+OffsetIndex]);
  fSize := newSize;
  end
else
  begin
  fOffsetIndex := 0;
  fSize := 0;
  end;
end;

Procedure TBufferData.DoGrowth( NewSize : integer );
var
  newDataPtr : TArrayOfByte;
  copylen : integer;
  newBufferCount : integer;
  Procedure Report();
  begin
  Tlog.Add( 3, 'TBufferData.DoGrowth, increasing initial buffer size from ' +
               IntToStr(InitialBufferSize) +' to '+IntToStr(newBufferCount) );
  end;
begin
if NewSize > InitialBufferSize then
  begin
  while NewSize > InitialBufferSize do
    begin
    newBufferCount := (InitialBufferSize * 3) div 2 - 1;
    if Log_.VerboseLoggingLevel >= 3 then
       Report;
    InitialBufferSize := newBufferCount;
    end;
  end;
NewSize := InitialBufferSize;
assert( NewSize > 0 );
if (FFragmentMaxSize <> 0) then
  begin
  newDataPtr := fDataPtr2;
  if NewSize > length(newDataPtr) then
    setlength(newDataPtr, NewSize);
  if (NewSize >= FFragmentMaxSize) then
    copylen := FFragmentMaxSize
  else
    copylen := NewSize;
  move( DataPtr[fFragmentIndex], newDataPtr[0], copylen);
  fDataPtr := newDataPtr;
  fDataPtr2 := newDataPtr;

  fFragmentIndex := 0;
  FFragmentMaxSize := 0;
  end
else
  begin
  setlength(fDataPtr, NewSize);
  fDataPtr2 := fDataPtr;
  end;
fArraySize := NewSize;
fData := PByteArray(@DataPtr[fFragmentIndex+OffsetIndex]);
end;

procedure TBufferData.CheckGrowth( SizeIncrease : integer);
var NewSize : integer;
begin
NewSize := OffsetIndex+Size + SizeIncrease;
if NewSize > ArraySize then
  DoGrowth( NewSize )
else if (FFragmentMaxSize <> 0) and (NewSize > FFragmentMaxSize) then
  DoGrowth( NewSize );
end;

Procedure TBufferData.SetDataSize( NewSize : integer);
begin
if NewSize <> fSize then
  begin
  NewSize := OffsetIndex+NewSize;
  if NewSize > ArraySize then
    DoGrowth( NewSize )
  else if (FFragmentMaxSize <> 0) and (NewSize > FFragmentMaxSize) then
    DoGrowth( NewSize );
  fSize := NewSize-OffsetIndex;
  end;
end;

function TBufferData.AddBuffer( SourceBufferData : TBufferData;
                                SourceIndex : integer = 0;
                                SourceLen : integer = -1 ) : integer;
begin
assert( SourceBufferData <> nil );
if SourceIndex < 0 then
  SourceIndex := 0;
if (SourceLen < 0) or
   (SourceLen + SourceIndex > SourceBufferData.Size) then
  SourceLen := SourceBufferData.Size - SourceIndex;
if SourceLen > 0 then
  begin
  result := Size;
  Size := result+SourceLen;
  move( SourceBufferData.Data[SourceIndex], Data[result], SourceLen );
  end
else
  result := -1;
end;

Procedure TBufferData.InsertData( index : integer; var Buff; DataSize : integer);
begin
Size := Size + DataSize;
move( Data[index], Data[index+DataSize], Size-DataSize);
move( Buff, Data[index], DataSize);
end;

Procedure TBufferData.DeleteData( index : integer; len : integer);
begin
if (index < 0) or (index >= Size) or (len <= 0) then
 exit;
if index+len >= Size then
  len := Size - index;
if len < Size -1 then
  move( Data[index+len], Data[index], len);
Size := Size -len;
end;

function TBufferData.AddByte( value : byte ) : integer;
begin
result := Size;
Size := Size + sizeof(value);
Data[result] := value;
end;

function TBufferData.AddWord( value : word ) : integer;
begin
result := Size;
Size := Size + sizeof(value);
PWord(@Data[result])^ := value;
end;

function TBufferData.AddDWord(value : longword ) : integer;
begin
result := Size;
Size := Size + sizeof(value);
Plongword(@Data[result])^ := value;
end;

Procedure TBufferData.SetByte( index : integer; value : byte );
begin
assert( index+(sizeof(value)-1) < Size );
Data[index] := value;
end;

Procedure TBufferData.SetWord( index : integer; value : word );
begin
assert( index+(sizeof(value)-1) < Size );
PWord(@Data[index])^ := value;
end;

Procedure TBufferData.SetDWord( index : integer; value : longword );
begin
assert( index+(sizeof(value)-1) < Size );
Plongword(@Data[index])^ := value;
end;

function TBufferData.GetByte( index : integer ) : byte;
begin
assert( index+(sizeof(result)-1) < Size );
result := PByte(@Data[index])^;
end;

function TBufferData.GetWord( index : integer) : word;
begin
if index+(sizeof(result)-1) >= Size then
  asm int 3 end;
assert( index+(sizeof(result)-1) < Size );
result := PWord(@Data[index])^;
end;

function TBufferData.GetDWord( index : integer) : longword;
begin
assert( index+(sizeof(result)-1) < Size );
result := Plongword(@Data[index])^;
end;

function TBufferData.ToString( index : integer = 0; count : integer = -1) : String;
begin
if index < Size then
  begin
  if (count < 0) or (index + count >= Size) then
    count := Size - index
  else if (count = 0) then
    begin
    result := '';
    exit;
    end;
  result := PtrToStr(@Data[index], count)
  end
else
  result := '';
end;

function TBufferData.FragmentsToString( ) : String;
var
  i : integer;
begin
if fFragmentCount > 0 then
  begin
  result := '';
  for i := 0 to fFragmentCount -1 do
    result := result + fFragments[i].ToString();
  end
else
  result := ToString( );
end;

Function TBufferData.AllocFragment( StartIndex, aSize : integer) : TBufferData;

  Procedure Report;
  begin
  Tlog.Add( 3, 'TBufferData.AllocFragment, increasing fragment buffer size from ' +
               IntToStr(fFragmentCount) +' to '+IntToStr(InitialBufferFragmentCount) );
  end;
begin
if fFragmentCount >= length(fFragments) then
  begin
  if fFragmentCount <> 0 then
    begin
    InitialBufferFragmentCount := (fFragmentCount * 3) div 2 - 1;
    if Log_.VerboseLoggingLevel >= 3 then
      Report();
    end;
  setlength( fFragments, InitialBufferFragmentCount );
  end;
result := BufferedData.NewBuffer(false);
inc( BufferedData.fAllocatedFragments );
result.MakeFragment( DataPtr,fFragmentIndex+fOffsetIndex+ StartIndex, aSize);
fFragments[fFragmentCount] := result;
inc(fFragmentCount);
end;

Procedure TBufferData.DiscardFragments( );
begin
if fFragments <> nil then
while fFragmentCount > 0 do
  begin
  dec(fFragmentCount);
  BufferedData.DiscardBuffer( fFragments[fFragmentCount] );
  fFragments[fFragmentCount] := nil;
  end;
end;

Procedure TBufferData.CompileFragments( DestBuffer : TBufferData );
var
  i : integer;
  TotalSize : integer;
begin
if (fFragments <> nil) and (fFragmentCount > 0) then
  begin
  assert(DestBuffer <> nil);

  TotalSize := 0;
  for i := fFragmentCount-1 downto 0 do
    inc( TotalSize, fFragments[i].Size );
  DestBuffer.HeaderState := hs_RawData;
  DestBuffer.CheckGrowth( TotalSize );

  while (fFragmentCount > 0) do
    begin
    dec(fFragmentCount);
    DestBuffer.AddBuffer( fFragments[fFragmentCount] );
    BufferedData.DiscardBuffer( fFragments[fFragmentCount] );
    fFragments[fFragmentCount] := nil;
    end;
  end;
end;

Procedure TBufferData.CompileFragments( );
var
  DestBuffer : TBufferData;
begin
if (fFragments <> nil) and (fFragmentCount > 0) then
  begin
  DestBuffer := BufferedData.NewBuffer;

  CompileFragments( DestBuffer );

  BufferedData.SwapBuffers;
  BufferedData.ReleaseBuffer;
  end
end;

Constructor TBufferedData.Create;
begin
inherited;
if InitialBufferFragmentCount <= 0 then
  InitialBufferFragmentCount := DefaultBufferFragmentCount;
if InitialBufferCount <= 0 then
  InitialBufferCount := DefaultBufferCount;
if InitialBufferSize <= 0 then
  InitialBufferSize := DefaultBufferSize;
fReleaseList := TStack.create(InitialBufferCount);
fFreeList := TStack.create(InitialBufferCount);

NewBuffer;
end;

Destructor TBufferedData.Destroy;
begin
if fReleaseList <> nil then
  begin
  while fReleaseList.Count > 0 do
    TObject(fReleaseList.Pop).Free;
  FreeAndNil(fReleaseList);
  end;
if fFreeList <> nil then
  begin
  while fFreeList.Count > 0 do
    TObject(fFreeList.Pop).Free;
  FreeAndNil(fFreeList);
  end;
FreeAndNil( fcurrent );
fcurrent := nil;
inherited;
end;

Procedure TBufferedData.SwapBuffers;
var
  AlmostTop : TBufferData;
begin
assert( fReleaseList <> nil );
assert( fFreeList <> nil );
assert( fReleaseList.Count >= 1 );
AlmostTop := fReleaseList.Pop;
fReleaseList.Push( fCurrent );
fCurrent := AlmostTop;
end;

Function TBufferedData.NewBuffer : TBufferData;
begin
result := NewBuffer(true);
end;

Function TBufferedData.NewBuffer(AddToReleaseList : boolean) : TBufferData;

  var
    i : integer;
    oldBufferCount : integer;
  Procedure Report();
  begin
  Tlog.Add( 3, 'TBufferedData.NewBuffer, increasing initial buffer count from ' +
               IntToStr(InitialBufferCount) +' to '+IntToStr(fBufferCount) );
  end;

{$IFDEF SanityAllocCheck}
var
  ActualCount : integer;
{$ENDIF}
begin
{$IFDEF SanityAllocCheck}

ActualCount := fReleaseList.Count + fFreeList.Count + fAllocatedFragments;
if fCurrent <> nil then
  inc(ActualCount);
if fBufferCount <> ActualCount then
  asm int 3 end;
{$ENDIF}

if AddToReleaseList and (fCurrent <> nil) then
  begin
  fReleaseList.Push( fCurrent );
  fCurrent := nil;
  end;
if fFreeList.Count <= 0 then
  begin
  oldBufferCount := BufferCount;
  if BufferCount > 0 then
    begin

    fBufferCount := (InitialBufferCount * 3) div 2 - 1;
    if Log_.VerboseLoggingLevel >= 3 then
       Report;
    InitialBufferCount := fBufferCount;
    end
  else
    fBufferCount := InitialBufferCount;
  fFreeList.Grow( fBufferCount );
  fReleaseList.Grow( fBufferCount );
  for i := oldBufferCount to BufferCount-1 do
    fFreeList.Push( TBufferData.Create( self ) );
  end;
result := fFreeList.Pop();
result.Reset();
if AddToReleaseList then
  fCurrent := result;
end;

Function TBufferedData.GetPendingReleaseCount : integer;
begin
result := fReleaseList.Count;
end;

Function TBufferedData.PrevBuffer : TBufferData;
begin
result := fReleaseList.Examine;
end;

Procedure TBufferedData.ReleaseBuffer;
begin
assert( fReleaseList <> nil );
If fReleaseList.Count >= 1 then
  begin
  DiscardBuffer( fCurrent );
  fCurrent := fReleaseList.Pop;
  end;
end;

Procedure TBufferedData.DiscardBuffer( BufferData : TBufferData );
begin
assert( fFreeList <> nil );
if BufferData <> nil then
  begin
{$IFDEF SanityAllocCheck}
  if BufferData.WasFragment then
    begin
    BufferData.WasFragment := false;
    dec( fAllocatedFragments );
    end;
{$ENDIF}
  fFreeList.Push( BufferData );
  if fCurrent.fFragmentCount > 0 then
    BufferData.DiscardFragments();
  end;
end;

end.
