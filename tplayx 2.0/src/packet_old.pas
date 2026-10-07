unit packet_old;
interface

const
  SY_UNIT = $92549357;

type
  TPacket = class
  protected
    procedure SetTimestamp (l :longword);
    function GetKind :byte;
    procedure SetKind (b :byte);

    function GetRawData :String;
    function GetRawData2 :String;
    function GetSize :integer;
    function GetTAData :string;
  public
    FData :string;
    constructor Create (const adata :String); overload;

    constructor Create (from :TPacket); overload;

    constructor SJCreateNew (data :string); overload;

    Class function KnownPacketType( const s : String; index :integer) : boolean;

    class function PacketLength( const s :String; index :integer) :Integer;

    class function Split (var s :string) :string;

    class function Split2 (var s :string;smartpak:Boolean; const FromPlayer, ToPlayer : string) :string;

    class function Decrypt( Data : string ) : string;

    class function Encrypt( Data : string) : string;

    class function Decompress( const Data :string ) : string;

    class function Compress (const Data :String) :string;

    function GetTimestamp :Longword;

    property Timestamp :longword read GetTimestamp write SetTimestamp;
    property Kind :byte read GetKind write SetKind;
    property RawData :string read GetRawData;
    property RawData2 :string read GetRawData2;

    property Size :integer read GetSize;
    property TAData :string read GetTAData;
  end;

var
  DecompressionBufferSize : Integer = 2048;
  UseCompression : Boolean = false;
implementation

uses
  TextData, Logging, IniOptions, SysUtils, TA_NetworkingMessages;

{$WARNINGS OFF}

constructor TPacket.Create( const adata : String);
begin
inherited Create;
FData := Decompress( Decrypt( adata ) );
end;

constructor TPacket.Create (from :TPacket);
var
  s :String;
begin
  s := from.RawData;
  FData := #$3#00#00 + s;
  inherited Create;
end;

constructor TPacket.SJCreateNew (data :string);
begin
  FData := #$3#00#00#$ff#$ff#$ff#$ff + data;
end;

function TPacket.GetTimestamp :longword;
begin
Result := Plongword(@FData[4])^;
end;

procedure TPacket.SetTimestamp (l :longword);
begin
Move (l, Fdata[4], sizeof(l));
end;

function TPacket.GetKind :byte;
begin
Result := Byte(FData[8]);
end;

procedure TPacket.SetKind (b :byte);
begin
FData[8] := char (b);
end;

function TPacket.GetRawData :String;
begin
Result := Copy (FData, 4, Length(fData)-3);
end;

function TPacket.GetRawData2 :String;
begin
Result := Copy (FData, 8, Length(fData)-7);
end;

function TPacket.GetSize :integer;
begin
Result := Length (FData) - 3;
end;

function TPacket.GetTAData :string;
begin
Result := Encrypt( Compress( FData ) );
end;

class function TPacket.KnownPacketType( const s : String; index :integer) : Boolean;
begin
Result := PacketLength( s, index ) <> 0;
end;

class function TPacket.PacketLength(const s :string; index :integer) :integer;
begin
case byte(s[index]) of
  $02       :Result := 13;
  $06       :Result := 1;
  $07       :Result := 1;
  $1a       :Result := 14;
  $17       :Result := 2;
  $18       :Result := 2;
  $15       :Result := 1;
  $08       :Result := 1;
  $05       :
            begin
            Result := 65;
            if s[index+Result-1] <> #0 then
              begin

              result := length(s) - index +1;

              if s[length(s) - 5+1] = #$fc then
                dec(result, 5 );
              end;
            end;

  $20       :Result := 192;
  $24       :Result := 6;
  $26       :Result := 41;

  $2e       :Result := 9;
  $22       :Result := 6;
  $2a       :Result := 2;
  $1e       :Result := 2;
  $2c       :Result := pword(@s[index+1])^;

  $09       :result := 23;
  $11       :result := 4;
  $10       :result := 22;
  $12       :result := 5;
  $0a       :result := 7;
  $28       :result := 58;
  $19       :result := 3;
  $0b       :result := 9;
  $0c       :result := 11;

  TANM_WeaponFired :
    if iniSettings.WeaponsIDPatch then
      Result:= SizeOf(TWeaponFiredMessagePatched)
    else
      Result := SizeOf(TWeaponFiredMessage);
  TANM_AreaOfEffect :
    if iniSettings.WeaponsIDPatch then
      Result:= SizeOf(TAreaOfEffectMessagePatched)
    else
      Result := SizeOf(TAreaOfEffectMessage);
  TANM_FeatureAction :
    if iniSettings.WeaponsIDPatch then
      Result:= SizeOf(TFeatureActionMessagePatched)
    else
      Result := SizeOf(TFeatureActionMessage);
  $1f       :result := 5;
  $23       :result := 14;

  $16       :result := 17;
  $1b       :result := 6;
  $29       :result := 3;
  $14       :result := 24;

  $21       :result := 10;
  $03       :result := 7;

  $f6       :result := 1;
  $f9       :result := 73;
  $fa       :result := 1;
  $fb       :result := Integer(s[index+1])+3;
  $fc       :Result := 5;
  $fd       :Result := pword(@s[index+1])^-4;
  $fe       :result := 5;
  $ff       :result := 1;
  else       result := 0;
end;
end;

class function TPacket.Split (var s :string) :string;
var
  len :byte;
  tmp, ut :string;
begin
if s = '' then
  begin
  Result := '';
  exit;
  end;

tmp := Decompress( Decrypt( s ) );

len := PacketLength(tmp, 8);

ut := #3#0#0#$ff#$ff#$ff#$ff + Copy (tmp, len + 3 + 4 + 1, 10000);

if len = 0 then
  begin
    TLog.Add(1,'Unknown packet : ' + intToStr (byte(tmp[8])));
    ut := #3#0#0#$ff#$ff#$ff#$ff;

  end
else
    tmp := Copy (tmp, 1, len + 3 + 4);

Result := Encrypt( Compress( tmp ) );

if Length(ut) = 7 then
  begin
    s := '';
    exit;
  end;

  s := Encrypt( Compress( ut ) );
end;

class function TPacket.Split2 (var s :string;smartpak:boolean; const FromPlayer, ToPlayer : string) :string;
var
  len :integer;
  tmp :string;
begin
if s = '' then
  begin
  Result := '';
  exit;
  end;

len := PacketLength(s,1);
if (((s[1]=#$ff) or (s[1]=#$fe) or (s[1]=#$fd)) and not smartpak) then
  begin
  Tlog.add(1,'From '+FromPlayer+' to '+ ToPlayer+',Warning erroneous compression assumption');
  Tlog.add(1,'Packet:'+datatostr2(s));
  end;
if length(s) < len then
  begin
  Tlog.add(1,'From '+FromPlayer+' to '+ ToPlayer+', Error subpacket longer than packet '+inttostr(length(s))+' '+inttostr(len)+' '+datatostr2(s));
  len:=0;
  end;
if len = 0 then
  begin
  TLog.Add (1,'From '+FromPlayer+' to '+ ToPlayer+', unknown packet : $' + IntToHex( byte(s[1]), 2) + ' '+datatostr2(s));
  Result := s;
  s := '';
  end
else
  begin
  tmp := s;
  s := Copy( tmp, len+1 , Length(s) );
  result := Copy (tmp, 1, len);
  end;
end;

{$IFOPT R+} {$DEFINE tmp53262} {$R-} {$ENDIF}
{$IFOPT Q+} {$DEFINE tmp3654273} {$Q-}{$ENDIF}
class function TPacket.Decrypt (Data :string) :string;
var
  i :integer;
  check :word;
  p :^word;
begin
if length(data)<4 then
  begin
  result:=data+#$06;
  exit;
  end;
check := 0;
for i := 4 to Length (Data) - 3 do
  begin
  Check := Check + Byte(Data[i]);
  data[i] := Char(Byte(Data [i]) xor byte(i - 1));
  end;
p := @Data[2];
if Check <> p^ then
  begin
  TLog.Add(0,'Removing corrupted packet ');
  Result := #3#0#0#$ff#$ff#$ff#$ff#$2a'd'
  end
else
  Result := Data;
end;
{$IFDEF tmp53262} {$UNDEF tmp53262} {$R+} {$ENDIF}
{$IFDEF tmp3654273} {$UNDEF tmp3654273} {$Q+}{$ENDIF}

{$IFOPT R+} {$DEFINE tmp53262} {$R-} {$ENDIF}
{$IFOPT Q+} {$DEFINE tmp3654273} {$Q-}{$ENDIF}

class function TPacket.Encrypt( Data : string ) : string;
var
  i :integer;
  check :word;
  p :^Word;
begin
if Length (data) < 4 then
  begin
  TLog.Add(0,'Removing corrupted packet ');
  Result := #3#0#0#$ff#$ff#$ff#$ff#$2a'd';
  exit;
  end;
check := 0;
for i := 4 to Length (Data) - 3 do
  begin
  Data [i] := Char(Byte(Data[i]) xor (i - 1));
  Check := Check + Byte(Data[i]);
  end;
p := @data[2];
p^ := check;

Result := Data;
end;
{$IFDEF tmp53262} {$UNDEF tmp53262} {$R+} {$ENDIF}
{$IFDEF tmp3654273} {$UNDEF tmp3654273} {$Q+}{$ENDIF}

class function TPacket.Decompress(const Data :string) :string;
var
  SourceIndex, ChunkNumber :integer;
  SourceLen : Integer;

  a,uop : Integer;
  RunIndex : Integer;

  Fixup1stByte : Boolean;
  IsCompressedBitMask : byte;
  count : Integer;

  newBufferSize : Integer;

begin
if Data[1] <> #$04 then
  begin
  Result := Data;
  exit;
  end;
SourceLen := Length(Data);
SourceIndex := 4;

setlength(Result, DecompressionBufferSize );
Result[1] := Data[1];
Result[2] := Data[2];
Result[3] := Data[3];
count := 3;

Fixup1stByte := True;
try
  while SourceIndex <= SourceLen do
    begin
    IsCompressedBitMask := byte(Data[SourceIndex]);
    Inc( SourceIndex );
    for ChunkNumber := 0 to 7 do
      begin
      if SourceIndex > SourceLen then
        begin
        Fixup1stByte := False;
        exit;
        end;
      if (( IsCompressedBitMask shr ChunkNumber) and 1) = 0 then
        begin
        inc( Count );
        if Count > DecompressionBufferSize then
          begin
          newBufferSize := 2*(DecompressionBufferSize+1);
          Tlog.Add( 3, 'TPacket.Decompress, increasing decompression buffer size from ' +IntToStr(DecompressionBufferSize) +' to '+IntToStr(newBufferSize) );
          DecompressionBufferSize := newBufferSize;
          setlength(Result, DecompressionBufferSize );
          end;
        Result[Count] := Data[SourceIndex];
        Inc( SourceIndex );
        end
      else
        begin
        uop := PWord(@Data[SourceIndex])^;
        Inc( SourceIndex, 2 );
        a := uop shr 4;
      	if a = 0 then
          exit;
        uop := uop and $0f;
        for RunIndex := a to a + uop + 1 do
          begin
          inc( Count );
          if Count > DecompressionBufferSize then
            begin
            newBufferSize := 2*(DecompressionBufferSize+1);
            Tlog.Add( 3, 'TPacket.Decompress, increasing decompression buffer size from ' +IntToStr(DecompressionBufferSize) +' to '+IntToStr(newBufferSize) );
            DecompressionBufferSize := newBufferSize;
            setlength(Result, DecompressionBufferSize );
            end;
          Result[Count] := Result[RunIndex+3];
          end;
        end;
      end;
    end;
finally
  SetLength( Result, count );

  if Fixup1stByte then
    Result[1] := #3;
end;
end;

class function TPacket.Compress (const Data :String) :string;
var
  index,cbf,count,a,matchl,cmatchl       : integer;
  kommando,match                         : word;
  p                                      : ^word;
begin
  if not UseCompression then
    begin
    Result := Data;
    Result[1] := #3;
    Exit;
    end;
  result:='';
  count:=7;
  index:=4;
  while index<length(data)+1 do
  begin
    if count=7 then
    begin
      count:=-1;
      result:=result+#$0;
      cbf:=length(result);
    end;
    count:=count+1;
    if (index<6) or (index>2000) then
    begin
      result:=result+data[index];
      index:=index+1;
    end else
    begin
      matchl:=2;
      for a:=4 to index-2 do
      begin
        cmatchl:=0;
        while (data[a+cmatchl]=data[index+cmatchl]) and ((index+cmatchl)<length(data)) and (a+cmatchl<index) do
          cmatchl:=cmatchl+1;
        if (cmatchl>matchl) then
        begin
          matchl:=cmatchl;
          match:=a;
          if matchl>17 then
            break;
        end;
      end;
      cmatchl:=0;
      while (data[index+cmatchl]=data[index-1]) and (index+cmatchl < length(data)) do
        cmatchl:=cmatchl+1;
      if (cmatchl>matchl) then
      begin
        matchl:=cmatchl;
        match:=index-1;
      end;
      if matchl>2 then
      begin
        byte(result[cbf]):=byte(result[cbf]) or (1 shl count);
        matchl:=(matchl - 2) and $0f;
        kommando:=((match-3) shl 4) or matchl;
        result:=result+#0#0;
        p:=@result[length(result)-1];
        p^:=kommando;
        index:=index+matchl+2;
      end else
      begin
        result:=result+data[index];
        index:=index+1;
      end;
    end;
  end;
  if count=7 then
    result:=result+#$ff
  else
    result[cbf] := char( byte(result[cbf]) or ($ff shl (count+1)) );
  result:=result+#0#0;

  if (length(result)+3 < length(data)) then
    result:=#$04+data[2]+data[3]+result
  else begin
    result:=data;
    result[1]:=#$03;
  end;
end;

end.
