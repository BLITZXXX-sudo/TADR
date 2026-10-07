unit uDebug;

interface

uses
  contnrs;

var

  MapFileName : string = '';
function LoadAndParseMapFile: Boolean;
procedure CleanUpMapFile;
function GetMapAddressFromAddress(const Address: Longword): Longword;
function GetMapFileName: string;
function GetModuleNameFromAddress(const Address: Longword): string;
function GetProcNameFromAddress(const Address: Longword): string;
function GetLineNumberFromAddress(const Address: Longword): string;

var
  Units,
  Procedures,
  LineNumbers: TObjectList;
  MapFileSetup : Boolean;
implementation
uses
  windows,
  SysUtils;

const

  NAME_CLASS           = 'StartLengthNameClass';
  SEGMENT_MAP          = 'Detailedmapofsegments';
  PUBLICS_BY_NAME      = 'AddressPublicsbyName';
  PUBLICS_BY_VAL       = 'AddressPublicsbyValue';
  LINE_NUMBERS         = 'Linenumbersfor';
  RESOURCE_FILES       = 'Boundresourcefiles';

type

  THeaderType = (htNameClass, htSegmentMap, htPublicsByName, htPublicsByValue,
    htLineNumbers, htResourceFiles);

  TUnitItem = class
    UnitName: string;
    UnitStart,
    UnitEnd: Longword;
  end;

  TProcedureItem = class
    ProcName: string;
    ProcStart: Longword;
  end;

  TLineNumberItem = class
    UnitName,
    LineNo: string;
    LineStart: Longword;
  end;

function StripFromString(const Strip: char; var AString: string): string;
var
  Pos: Cardinal;
begin
  Pos := Length(AString);
  while Pos > 0 do
  begin
    if AString[Pos] = Strip then
      Delete(AString, Pos, Length(Strip))
    else
      Dec(Pos);
  end;
  Result := AString;
end;

function LoadAndParseMapFile: Boolean;
var
  F: TextFile;
  CurrentLine,
  CurrentUnit: string;
  CurrentHeader: THeaderType;

  function CompareHeaders(AHeader, ALine: string): Boolean;
  begin
  Result := Copy(ALine, 1, Length(AHeader)) = AHeader;
  end;

  procedure SyncHeaders(var Header: THeaderType; Line: string);
  const
    Pfx = Length('Line numbers for ');
  begin
    Line := StripFromString(' ', Line);

    if CompareHeaders(NAME_CLASS, Line)      then Header := htNameClass;
    if CompareHeaders(SEGMENT_MAP, Line)     then Header := htSegmentMap;
    if CompareHeaders(PUBLICS_BY_NAME, Line) then Header := htPublicsByName;
    if CompareHeaders(PUBLICS_BY_VAL, Line)  then Header := htPublicsByValue;
    if CompareHeaders(LINE_NUMBERS, Line)    then
    begin
      Header := htLineNumbers;
      CurrentUnit := Copy(Line, Pfx -2, Pos('(', Line) - Pfx + 2);
    end;
    if CompareHeaders(RESOURCE_FILES, Line)  then Header := htResourceFiles;
  end;

  procedure AddUnit(ALine: string);
  var
    SStart: string;
    SLength: string;
    AUnitItem: TUnitItem;
  begin
    if StrToInt(Trim(Copy(ALine, 1, Pos(':', ALine) -1))) = 1 then
    begin
      SStart  := Copy(ALine, Pos(':', ALine) + 1, 8);
      SLength := Copy(ALine, Pos(':', ALine) + 10, 8);
      AUnitItem := TUnitItem.create;
      with AUnitItem do
      begin
        UnitStart := StrToInt('$' + SStart);
        UnitEnd   := UnitStart + Longword(StrToInt('$' + SLength));
        Delete(ALine, 1, Pos('M', ALine) + 1);
        UnitName := Copy(ALine, 1, Pos(' ', ALine) -1);
      end;
      Units.Add(AUnitItem);
    end;
  end;

  procedure AddProcedure(ALine: string);
  var
    SStart: string;
    AProcedureItem: TProcedureItem;
  begin
    if StrToInt(Trim(Copy(ALine, 1, Pos(':', ALine) -1))) = 1 then
    begin
      SStart  := Copy(ALine, Pos(':', ALine) + 1, 8);
      AProcedureItem := TProcedureItem.create;
      with AProcedureItem do
      begin
        ProcStart := StrToInt('$' + SStart);
        Delete(ALine, 1, Pos(':', ALine) + 1);
        ProcName  := Trim(Copy(ALine, Pos(' ', ALine), Length(ALine) - Pos(' ', ALine) + 1));
      end;
      Procedures.Add(AProcedureItem);
    end;
  end;

  procedure AddLineNo(ALine: string);
  var
    ALineNumberItem: TLineNumberItem;
  begin
    while Length(Trim(ALine)) > 0 do
    begin
      ALineNumberItem := TLineNumberItem.create;
      with ALineNumberItem do
      begin
        Aline     := Trim(ALine);
        UnitName  := CurrentUnit;
        LineNo    := Copy(ALine, 1, Pos(' ', ALine)-1);
        Delete(ALine, 1, Pos(' ', ALine) + 5);
        LineStart := StrToInt('$' + Copy(ALine, 1, 8));
        Delete(ALine, 1, 8);
      end;
      LineNumbers.Add(ALineNumberItem);
    end;
  end;

begin
Result := False;
if Units <> nil then
  FreeAndNil(Units);
if Procedures <> nil then
  FreeAndNil(Procedures);
if LineNumbers <> nil then
  FreeAndNil(LineNumbers);
Units       := TObjectList.Create(true);
Procedures  := TObjectList.Create(true);
LineNumbers := TObjectList.Create(true);
if FileExists(GetMapFileName) then
  begin
  AssignFile(F, GetMapFileName);
  {$I-}
  Reset(F);
  {$I+}
  if IOResult <> 0 then Exit;
  try
  while not EOF(F) do
    begin
    ReadLn(F, CurrentLine);
    SyncHeaders(CurrentHeader, CurrentLine);
    if Length(CurrentLine) > 0 then
      if (Pos(':', CurrentLine) > 0) and (CurrentLine[1] = ' ') then
        case CurrentHeader of
          htSegmentMap:     AddUnit(CurrentLine);
          htPublicsByValue: AddProcedure(CurrentLine);
          htLineNumbers:    AddLineNo(CurrentLine);
        end;
    end;
  finally
    CloseFile(F);
  end;
  Result := (Units.Count > 0) and (Procedures.Count > 0) and (LineNumbers.Count > 0);
  MapFileSetup := Result;
  end;
end;

procedure CleanUpMapFile;
begin
FreeAndNil(Units);
FreeAndNil(Procedures);
FreeAndNil(LineNumbers);
MapFileSetup := False;
end;

function GetModuleNameFromAddress(const Address: Longword): string;
var
  i: Integer;
  UnitItem : TUnitItem;
begin
Result := '';
if Units <> nil then
for i := Units.Count -1 downto 0 do
  begin
  UnitItem := TUnitItem(Units.Items[i]);
  if ((UnitItem.UnitStart <= Address) and
      (UnitItem.UnitEnd >= Address)) then
    begin
    Result := UnitItem.UnitName;
    Break;
    end;
  end;
end;

function GetProcNameFromAddress(const Address: Longword): string;
var
  i: Integer;
  ProcedureItem : TProcedureItem;
begin
Result := '';
if Procedures <> nil then
for i := Procedures.Count -1 downto 0 do
  begin
  ProcedureItem := TProcedureItem(Procedures.Items[i]);
  if (ProcedureItem.ProcStart <= Address) then
    begin
    Result := ProcedureItem.ProcName;
    Break;
    end;
  end;
end;

function GetLineNumberFromAddress(const Address: Longword): string;
var
  i: Cardinal;
  LastLineNo: string;
  UnitName: string;
  LineNumberItem : TLineNumberItem;
begin
Result     := '';
LastLineNo := '';
UnitName   := GetModuleNameFromAddress(Address);
if (UnitName <> '') and (LineNumbers <> nil) then
for i := 0 to LineNumbers.Count -1 do
  begin
  LineNumberItem := TLineNumberItem(LineNumbers.Items[i]);
  if LineNumberItem.UnitName = UnitName then
    begin
    if (LineNumberItem.LineStart >= Address) then
      begin
      Result := LastLineNo;
      Break;
      end
    else
      LastLineNo := LineNumberItem.LineNo;
    end
  end;
end;

function GetMapFileName: string;
begin
if MapFileName = '' then
  begin
  if IsLibrary then
    begin
    setlength( Result, MAX_PATH );
    SetLength( Result, GetModuleFileName( HInstance, @Result[1], Length(Result) ) );
    end
  else
    Result := ParamStr(0);
  Result := ChangeFileExt(Result, '.map');
  end
else
  Result := MapFileName;
end;

function GetMapAddressFromAddress(const Address: Longword): Longword;
const
  CodeBase = $1000;
var
  OffSet: Longword;
  ImageBase: Longword;
begin
ImageBase := hInstance;
OffSet := ImageBase + CodeBase;

if OffSet <= Address then

  Result := Address - OffSet
else
  Result := Address;
end;

end.
