unit ColorFreeFix;

{
  ColorFreeFix - fixes the host crash when a player joins a battle room that
                 already has 12+ players (found with cdb, 2026-10-01).

  THE BUG (in the 16-player exe, not in TDRAW or TPLAYX)
  -------------------------------------------------------
  0x452570 IsColorFree(dpid, color) is called on the host when a player joins.
  It builds a small table on the STACK, indexed by colour:

      sub esp,0Ch                 ; 12 bytes of locals
      table[0..9] := $FF          ; only 10 entries initialised (stock TA: 10 colours)
      for p := 0 to 15 do         ; the 16-player patch raised this loop to 16 ...
        table[ player[p].colour ] := p     ; ... but not the table size

  With 16 colours, players using colour 12..15 write past the 12-byte table
  into the function's return address, e.g. bytes 0C 0D 0E 00. The function
  then "returns" to 0x000E0D0C / 0x450D15 / 0x450D20 and the host crashes;
  TA's crash handler then hangs, the client sees the reject screen.

  THE FIX
  -------
  The whole function is replaced (jump at its entry) by the routine below,
  which answers the same question without any table:
      colour is free  <=>  0 <= colour < 16 and no OTHER active player
                           (by DirectPlay id) already has that colour.
  Same stdcall signature and return value (1 = free, 0 = taken/invalid).
  Applied only if the exe still has the original bytes at 0x452570.
}

interface

uses
  PluginEngine;

Procedure OnInstall;
Procedure OnUninstall;

const
  State_ColorFreeFix : boolean = true;

function GetPlugin : TPluginData;

implementation

uses
  Windows,
  SysUtils;

const
  FIX_ADDR   = $00452570;
  TAMAIN_PTR = $00511DE8;
  PLAYERS    = $3A000;
  PLAYER_SZ  = $14B;
  // sub esp,0Ch / push ebx / mov ebx,[esp+18h]
  EXPECT : array[0..7] of Byte = ($83, $EC, $0C, $53, $8B, $5C, $24, $18);

function IsColorFree16(dpid : LongInt; color : LongInt) : LongInt; stdcall;
var
  ta, p, info : PByte;
  i : Integer;
begin
  result := 0;
  if (color < 0) or (color >= 16) then Exit;
  ta := PPointer(TAMAIN_PTR)^;
  if ta = nil then Exit;
  for i := 0 to 15 do
  begin
    p := ta + PLAYERS + i * PLAYER_SZ;
    if p[$73] = 0 then Continue;                 // empty slot
    if PLongInt(p + 4)^ = dpid then Continue;    // the asking player itself
    info := PPointer(p + $27)^;
    if info = nil then Continue;
    if info[$96] = $FF then Continue;            // no colour yet
    if info[$96] = Byte(color) then Exit;        // taken
  end;
  result := 1;
end;

function ExeMatches : boolean;
var
  i : Integer;
begin
  result := false;
  for i := 0 to High(EXPECT) do
    if PByte(FIX_ADDR + Cardinal(i))^ <> EXPECT[i] then Exit;
  // 16-player build: the colour range check is "cmp ebx,10h" at 0x45258F
  result := (PByte($0045258F)^ = $83) and (PByte($00452591)^ = $10);
end;

Procedure OnInstall;
begin
end;

Procedure OnUninstall;
begin
end;

function GetPlugin : TPluginData;
begin
  result := nil;
  if not State_ColorFreeFix then Exit;
  if not ExeMatches then Exit;
  result := TPluginData.create( true,
                                'IsColorFree 16-colour stack overflow fix',
                                State_ColorFreeFix,
                                @OnInstall, @OnUninstall );
  result.MakeRelativeJmp(State_ColorFreeFix, 'IsColorFree16', @IsColorFree16, FIX_ADDR);
end;

end.
