unit TA_MemoryConstants;

interface

const
  MAXPLAYERCOUNT = 16;        // ProTA: array at TAMain+0x3A000, 16 * 0x14B
  MAXUNITLIMITPLAYERS = 10;   // NO LONGER USED. Kept for reference.
                              // Pinning the unit-limit math to 10 caused a
                              // load-thread crash: unit ids span ALL player
                              // slots, so UnitsCustomFields must be sized
                              // with MAXPLAYERCOUNT. Only the chatview
                              // arrays must stay at 10 (shared with TDRAW).

  TAdynmemStructPtr = $00511DE8;
  TAMovementClassArray = $00512358;
  TAunitsCategory = $0051E6B0;
  COBScriptHandler_Begin = $00512344;
  COBScriptHandler_End = $00512348;
  MultiplayerMapsList = $005122D4;

  ScoreBoardRoll = $0051F2D8;

  OFFSCREEN_off = -$1F0;  

  // Strings
  Rev31GP3_Name = $005028CC;
  Rev31GP3_31 = $005028D8;
  Totala_ini = $005098A3;
  OldMapName = $00512990;
  Null_str = $005119B8;
  QueryPrimary = $505284;
  QuerySecondary = $00505274;
  QueryTertiary = $00505264;
  ImmediateOrders = $0050271C;
  SpecialOrders = $005026E4;
  FIXEDLOC = $00505598;

implementation

end.
