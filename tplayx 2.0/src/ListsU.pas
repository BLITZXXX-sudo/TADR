unit ListsU;
interface
uses
  classes;

type
  TStack = class
  Protected
    fList : array of pointer;
    fcount : LongInt;

  Public
    Constructor Create(aCapacity : cardinal = 16);

    Procedure Grow; overload;
    Procedure Grow( NewSize : Integer ); overload;

    Procedure Clear;
    Procedure Push(aptr : pointer);
    Function Pop : pointer;
    Function Examine : pointer;

    Property Count : LongInt read fCount;
  end;

  TQueue = class
  Protected
    fList : array of pointer;
    fTail,fhead : LongInt;
    fcount : LongInt;
    Procedure Grow; overload;
    Procedure Grow(NewSize : integer); overload;
  public
    Constructor Create(aCapacity : cardinal = 16);

    Procedure EnQueue(const p : pointer);

    Function DeQueue : pointer;

    Function Examine : pointer;

    Function Last : pointer;

    procedure Clear;

    Property Count : LongInt read fCount;
  end;

  TStringQueue = class
  Protected
    fList : array of string;
    fTail,fhead : LongInt;
    fcount : LongInt;
    Procedure Grow;
  public
    Constructor Create(aCapacity : cardinal = 16);

    Procedure EnQueue(const p : string);

    Function DeQueue : string;

    Function Examine : string;

    Function Last : string;

    procedure Clear;

    Property Count : LongInt read fCount;
  end;

  TObjectQueue = class
  Protected
    fList : array of TObject;
    fTail,fhead : LongInt;
    fcount : LongInt;
    Procedure Grow;  virtual;
  public
    Constructor Create(aCapacity : cardinal = 16);

    Procedure EnQueue(p : TObject);

    Function DeQueue : TObject;

    Function Examine : TObject;

    Function Last : TObject;

    procedure Clear;

    Property Count : LongInt read fCount;
  end;

implementation
uses
  sysutils;

Constructor TStack.Create(aCapacity : cardinal = 16);
begin
Inherited create;
if aCapacity < 1 then
  aCapacity := 1;

SetLength( flist, aCapacity );
end;

Procedure TStack.Grow;
begin

SetLength(flist, (Length(flist) * 3) div 2 - 1 );
end;

Procedure TStack.Grow( NewSize : Integer );
begin
if NewSize > length(flist) then
  SetLength(flist, NewSize );
end;

Procedure TStack.Clear;
begin
fcount := 0;
end;

Procedure TStack.Push(aptr : pointer);
begin
flist[fcount] := aptr;
inc(fcount);
if fcount >= length(flist) then
  Grow;
end;

Function TStack.Pop : pointer;
begin
if fcount <> 0 then
  begin
  dec(fcount);
  Result := flist[fcount];
  end
else
  result := nil;
end;

Function TStack.Examine : pointer;
begin
if fcount <> 0 then
  Result := flist[fcount-1]
else
  Result := nil;
end;

Constructor TQueue.Create(aCapacity : cardinal = 16);
begin
Inherited create;
if aCapacity < 1 then
  aCapacity := 1;

SetLength( flist, aCapacity );
end;

procedure TQueue.Clear;
begin
fCount := 0;
ftail := 0;
fHead := 0;
end;

Procedure TQueue.Grow(NewSize : integer);
var
  Index,ToInx : cardinal;

begin
SetLength(flist, NewSize );
if Fhead = 0 then
  ftail := Count
else
  begin
  ToInx := Length(flist);
  For index := pred(Count) downto Fhead do
    begin
    dec(ToInx);
    flist[ToInx] := flist[index];
    end;
  Fhead := ToInx;
  end;
end;

Procedure TQueue.Grow;
begin

Grow((Length(flist) * 3) div 2 - 1 )
end;

Procedure TQueue.EnQueue(const p : pointer);
begin
flist[Ftail] := p;

inc(Ftail);
if Ftail >= length(fList) then
  Ftail := 0;
inc(Fcount);
if Ftail = FHead then
  Grow;
end;

Function TQueue.DeQueue : pointer;
begin
if Count <> 0 then
  begin
  Result := flist[FHead];
  flist[fhead] := nil;
  inc(fHead);
  if fHead >= length(fList) then
    fHead := 0;

  dec(fCount);
  end
else
  Result := nil;
end;

Function TQueue.Examine : pointer;
begin
if Count <> 0 then
  Result := flist[fHead]
else
  Result := nil;
end;

Function TQueue.Last : pointer;
begin
if Count <> 0 then
  Result := flist[fTail-1]
else
  Result := nil;
end;

Constructor TStringQueue.Create(aCapacity : cardinal = 16);
begin
Inherited create;
if aCapacity < 1 then
  aCapacity := 1;

SetLength( flist, aCapacity );
end;

procedure TStringQueue.Clear;
begin
fCount := 0;
ftail := 0;
fHead := 0;
end;

Procedure TStringQueue.Grow;
var
  Index,ToInx : cardinal;

begin

SetLength(flist, (Length(flist) * 3) div 2 - 1 );
if Fhead = 0 then
  ftail := Count
else
  begin
  ToInx := Length(flist);
  For index := pred(Count) downto Fhead do
    begin
    dec(ToInx);
    flist[ToInx] := flist[index];
    end;
  Fhead := ToInx;
  end;
end;

Procedure TStringQueue.EnQueue(const p : string);
begin
flist[Ftail] := p;

inc(Ftail);
if Ftail >= length(fList) then
  Ftail := 0;
inc(Fcount);
if Ftail = FHead then
  Grow;
end;

Function TStringQueue.DeQueue : string;
begin
if Count <> 0 then
  begin
  Result := flist[FHead];
  flist[fhead] := '';
  inc(fHead);
  if fHead >= length(fList) then
    fHead := 0;

  dec(fCount);
  end
else
  Result := '';
end;

Function TStringQueue.Examine : string;
begin
if Count <> 0 then
  Result := flist[fHead]
else
  Result := '';
end;

Function TStringQueue.Last : string;
begin
if Count <> 0 then
  Result := flist[fTail-1]
else
  Result := '';
end;

Constructor TObjectQueue.Create(aCapacity : cardinal = 16);
begin
Inherited create;
if aCapacity < 1 then
  aCapacity := 1;

SetLength( flist, aCapacity );
end;

procedure TObjectQueue.Clear;
begin
fCount := 0;
ftail := 0;
fHead := 0;
end;

Procedure TObjectQueue.Grow;
var
  Index,ToInx : cardinal;

begin

SetLength(flist, (Length(flist) * 3) div 2 - 1 );
if Fhead = 0 then
  ftail := Count
else
  begin
  ToInx := Length(flist);
  For index := pred(Count) downto Fhead do
    begin
    dec(ToInx);
    flist[ToInx] := flist[index];
    end;
  Fhead := ToInx;
  end;
end;

Procedure TObjectQueue.EnQueue(p : TObject);
begin
flist[Ftail] := p;

inc(Ftail);
if Ftail >= length(fList) then
  Ftail := 0;
inc(Fcount);
if Ftail = FHead then
  Grow;
end;

Function TObjectQueue.DeQueue : TObject;
begin
if Count <> 0 then
  begin
  Result := flist[FHead];
  flist[fhead] := nil;
  inc(fHead);
  if fHead >= length(fList) then
    fHead := 0;

  dec(fCount);
  end
else
  Result := nil;
end;

Function TObjectQueue.Examine : TObject;
begin
if Count <> 0 then
  Result := flist[fHead]
else
  Result := nil;
end;

Function TObjectQueue.Last : TObject;
begin
if Count <> 0 then
  Result := flist[fTail-1]
else
  Result := nil;
end;

end.
