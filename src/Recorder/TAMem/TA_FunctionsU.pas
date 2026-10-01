unit TA_FunctionsU;

interface

uses
  TA_MemoryStructures, DPlay;

const
  // Renamed from 'access' to 'TA_ACCESS' to avoid Free Pascal identifier conflicts
  TA_ACCESS = 1;

type
  GetTAProgramStructHandler = function: Pointer; register;
  GetGameingTypeHandler = function(a1, a2, a3: Cardinal): Cardinal; register;
  Game_SetLOSStateHandler = function(flags: integer): integer; stdcall;
  TA_UpdateLOSHandler = function(FillFeatureMap_b: LongWord): LongWord; stdcall;
  ScrollViewHandler = function(X, Y: Cardinal; Smooth: LongBool): Cardinal; stdcall;
  Mouse_SetDrawMouseHandler = function(Draw: Boolean): Integer; stdcall;
  DrawOptionsTabHandler = function(p_Offscreen: Pointer): Cardinal; stdcall;
  SetGammaHandler = function(fGamma: Single): Integer; stdcall;
  FreeObjectStateHandler = function(ObjectState: Pointer): Integer; stdcall;
  FreeMoveClassHandler = function(a1: pointer; a2: pointer; MoveClass: Pointer): Integer; register;
  FreeUnitScriptDataHandler = function(uneax, unedx: Pointer; ScriptData: Pointer; a2: Byte): Pointer; register;

  // turret weap aiming
  sub_49D910Handler = function(a1: LongInt; a2: LongInt; a3: LongInt;
                               a9: LongInt; a8: LongInt; a7: LongInt;
                               a6: LongInt; a5: LongInt; a4: LongInt): LongInt; register;

  GetUnit_BuildWeaponProgressHandler = function(p_Unit: Pointer): Cardinal; stdcall;
  UnitExplosionHandler = procedure(p_Unit: Pointer; destructas: Cardinal); stdcall;
  TestHeal_Handler = function(ResPercentage: Pointer; Amount: Single): Integer; stdcall;
  UNITS_SetStateMaskHandler = function(uneax, unedx: Pointer; p_Unit: Pointer;
                                       ScriptIdx: Integer; NewState: Integer): Cardinal; register;
  Trajectory3Handler = function(Attackerp_Unit: Pointer; Position1: PPosition;
                                Position2: PPosition; WhichWeapon: Word): Integer; stdcall;
  UnitAutoAim_CheckUnitWeaponHandler = function(Attackerp_Unit: Pointer;
                                                Targetp_Unit: Pointer;
                                                WhichWeapon: Word): Byte; stdcall;
  TranslateStringHandler = function(const Str: PAnsiChar): PAnsiChar; stdcall;
  _strcmpiHandler = function(const Str1: PAnsiChar; const Str2: PAnsiChar): Integer; cdecl;
  TA_AttachDetachUnitHandler = procedure(Transportedp_Unit: Pointer;
                                         Transporterp_Unit: Pointer;
                                         Piece: ShortInt;
                                         Unknown: Byte); stdcall;
  TerminateProcess_WithWarningHandler = procedure(TerminateMessage: PAnsiChar); stdcall;
  LoadHPITerainFileHandler = function(FilePath: PAnsiChar): Pointer; stdcall;
  GetTA_ScreenWidthHandler = function: Integer; cdecl;
  CorrecLinetPositionHandler = function(p_Offscreen: Pointer; x1: Pointer; y1: Pointer;
                                        x2: Pointer; y2: Pointer): LongInt; stdcall;
  GetFontTypeHandler = function: Pointer; stdcall;
  GetFontBackgroundColorHandler = function: Cardinal; stdcall;
  SetFontColorHandler = procedure(Color: Integer; FontAlpha: Integer); stdcall;
  SetFontTypeHandler = procedure(p_FontHandle: Pointer); stdcall;
  GetFontCharWidthHandler = function: Integer; stdcall;
  Msg_ReminderHandler = function(Msg_Str: PAnsiChar; Msg_Type: Word): Integer; stdcall;
  InterpretCommandHandler = procedure(Command: PChar; access: Longint); stdcall;
  DoInterpretCommandHandler = procedure(var Command: PChar; access: Longint); stdcall;
  IterateMapsHandler = function(a1: Longint; a2: Longint; a3: Longint): Longint; stdcall;
  LoadCampaign_UniqueUnitsHandler = procedure(); cdecl;
  Campaign_ParseUnitInitialMissionHandler = function(p_Unit: PUnitStruct; Missions: PAnsiChar;
                                                     UniqueNameArray: Pointer): Pointer; stdcall;
  PLAYERS_Index2DPlayIDHandler = function(PlayerIndex: Word): Integer; stdcall;
  UNITINFO_Name2IDHandler = function(const UnitName: PAnsiChar): Word; stdcall;
  FindSpot_CategorysAryHandler = function(const CategoryName: String): Integer; stdcall;
  TestGridSpotHandler = function(BuildUnit: Pointer; Pos: Integer; unk: Word;
                                 Player: Pointer): Integer; stdcall;
  TestGridSpotAIHandler = function(UnitInfo: Pointer; GridPos: Cardinal): Integer; stdcall;
  TestBuildSpotHandler = procedure(); stdcall;
  CanAttachAtGridSpotHandler = function(UnitInfo: PUnitInfo; UnitID: Word;
                                        GridPos: Integer; State: Integer): Boolean; stdcall;
  CanCloseOrOpenYardHandler = function(p_Unit: Pointer; NewState: Integer): Boolean; stdcall;
  GetPiecePositionHandler = function(var PositionOut: TPosition; p_Unit: PUnitStruct;
                                     PieceIdx: Integer): PPosition; stdcall;
  GetUnitPiecePositionHandler = procedure(var PositionOut: TPosition; p_Unit: PUnitStruct;
                                          PieceIdx: Integer); stdcall;
  GetContextHandler = function(ptr: PChar): Longint; stdcall;
  TextCommand_LOSHandler = procedure; stdcall;
  rand2Handler = function: Integer; cdecl;
  TA_Atan2Handler = function(y, x: Integer): Integer; cdecl;
  TurnXLookupHandler = function(a1: Word; a2: Integer): Integer; stdcall;
  TurnZLookupHandler = function(a1: Word; a2: Integer): Integer; stdcall;
  LoadTNTFileHandler = function(lpFileName: PAnsiChar): PTNTHeaderStruct; stdcall;
  LoadGameData_MainHandler = procedure(); stdcall;
  CopyGafToContextHandler = function(p_Offscreen: Pointer; GafFrame: Pointer;
                                     Off_X, Off_Y: Integer): Pointer; stdcall;
  AlphaCompsteBuf2OFFScreenHandler = function(p_Offscreen: Pointer; GafFrame: Pointer;
                                              Off_X, Off_Y: Integer): Pointer; stdcall;
  InitRadarHandler = function(): Integer; cdecl;
  CompositeBufferHandler = function(Description: PAnsiChar; Width: Integer;
                                    Height: Integer): Pointer; stdcall;
  CompositeBuf2_OFFSCREENHandler = function(p_Offscreen: Pointer; CompositeBuf_ptr: Pointer): Pointer; stdcall;
  DeselectAllUnitsHandler = function: LongBool; cdecl;
  UpdateIngameGUIHandler = function(unk: Integer): Integer; stdcall;
  ApplySelectUnitMenuHandler = function: Integer; cdecl;

  // Chat messages and text commands
  ShowReminderMsgHandler = function(Text: PAnsiChar; TextType: Word): Integer; stdcall;
  ShowChatMessageHandler = procedure(Player: PPlayerStruct; Text: PAnsiChar;
                                     Priority: Longint; ToPlayerName: PAnsiChar); stdcall;
  NewChatTextHandler = procedure(Source: PAnsiChar; Access: Byte; Priority: Word;
                                 FromPlayerIdx: Byte); stdcall;
  ClearChatHandler = procedure; stdcall;

  // Map data
  LoadMapHandler = function(un1, un2: Pointer; MapOTA: PMapOTAFile;
                            MapName: PAnsiChar): Integer; register;
  sub_435D30Handler = function(un1, un2: Pointer; MapOTA: PMapOTAFile;
                               a1: Integer): Integer; register;
  CalculateOTACRCHandler = function(un1, un2: Pointer; MapOTA: PMapOTAFile): Cardinal; register;
  UpdateViewMapHandler = procedure; cdecl;
  GetPosHeightHandler = function(pPosition: Pointer): Integer; stdcall;
  UnitInPlayerLOSHandler = function(PlayerPtr: Pointer; p_Unit: Pointer): Integer; stdcall;
  PositionInPlayerMappedHandler = function(PlayerPtr: Pointer; Position: PPosition): LongBool; stdcall;
  LoadMap_AverageHeightMapHandler = function: Word; cdecl;
  LoadMap_PLOT3Handler = function(): Pointer; cdecl;
  GetUnitAtMouseHandler = function: Cardinal; stdcall;
  IsPositionInRectHandler = function(Rect: PtagRECT; x, y: Integer): LongBool; cdecl;
  Position2GridPlotWreckHandler = function(Position: PPosition): PPlotGrid; stdcall;
  Position2GridPlotHandler = function(Position: PPosition): PPlotGrid; stdcall;
  GetTPositionHandler = function(X, Z: Integer; out Position: TPosition): Pointer; stdcall;
  GetGridPosPLOTHandler = function(X, Z: Integer): Pointer; stdcall;
  GetFeatureTypeFromOrderHandler = function(p_Pos: PPosition; p_Order: PUnitOrder;
                                            p_FeatureSize: Pointer): Word; stdcall;
  GetGridPosFeatureHandler = function(PlotGrid: PPlotGrid): SmallInt; stdcall;
  FeatureName2IDHandler = function(FeatureName: PAnsiChar): SmallInt; stdcall;
  FeatureNameNotListed2IDHandler = function(FeatureName: PAnsiChar): SmallInt; stdcall;
  LoadFeatureHandler = function(FeatureName: PAnsiChar): SmallInt; stdcall;
  ReleaseFeature_TdfVectorHandler = procedure(); register;
  SpawnFeatureOnMapHandler = function(GridPosPLOT: PPlotGrid; CorpseIdx: SmallInt;
                                      Position: PPosition; Volume: PTurn;
                                      PlayerId: Byte): Pointer; stdcall;
  FEATURES_Destroy_3DHandler = procedure(X: Integer; Z: Integer; bReclamateOrDie: LongBool); stdcall;
  FEATURES_DestroyHandler = procedure(GridPlot: PPlotGrid; bMethod: Boolean); stdcall;
  FEATURES_StartBurnHandler = procedure(X: Integer; Z: Integer; bFromNetworkPacket: LongBool); stdcall;
  FEATURES_TakeWeaponDamageHandler = procedure(p_lotGrid: PPlotGrid; X: Integer;
                                               Y: Integer; p_Weapon: PWeaponDef); stdcall;

  // Weapons and projectiles
  WEAPONS_Name2PtrHandler = function(const WeaponName: PAnsiChar): Pointer; stdcall;
  PROJECTILES_FireMapWeapHandler = function(WeaponTypePtr: Pointer; StartPosition: PPosition;
                                            TargetPosition: PPosition; bBroadcast: LongBool): LongBool; stdcall;
  WEAPONS_ProjectileDamageHandler = procedure(p_WeaponProjectile: PWeaponProjectile;
                                              p_TargetUnit: PUnitStruct); stdcall;
  fire_callbackHandler = function(Attacker_p_Unit: Pointer; Weapon_Target_ID: Pointer;
                                  Victim_p_Unit: Pointer; Position_Target: Pointer): Cardinal; stdcall;
  fire_callback0Handler = function(Attacker_p_Unit: Pointer; Weapon_Target_ID: Pointer;
                                   Victim_p_Unit: Pointer; Position_Target: Pointer): Cardinal; cdecl;
  UNITS_FireProjectile_0_3Handler = function(p_UnitWeapon: PUnitWeapon; p_AttackerUnit: PUnitStruct;
                                             p_Position_Start: PPosition; p_Position_Target: PPosition;
                                             p_TargetUnit: PUnitStruct): LongBool; stdcall;
  UNITS_FireProjectile_1Handler = function(p_UnitWeapon: PUnitWeapon; p_AttackerUnit: PUnitStruct;
                                           p_Position_Start: PPosition; p_Position_Target: PPosition;
                                           p_TargetUnit: PUnitStruct; p_Interceptor: PWeaponProjectile): LongBool; stdcall;
  UNITS_FireProjectile_0Handler = function(p_UnitWeapon: PUnitWeapon; p_AttackerUnit: PUnitStruct;
                                           p_Position_Start: PPosition; p_Position_Target: PPosition;
                                           p_TargetUnit: PUnitStruct): LongBool; stdcall;
  InitProjectileHandler = procedure(p_WeaponProjectile: PWeaponProjectile; p_WeaponDef: PWeaponDef;
                                    p_Position_Start: PPosition; p_Position_Target: PPosition;
                                    FireTime: Integer; p_AttackerUnit: PUnitStruct); stdcall;

  // Units Orders
  GetPrepareOrderNameHandler = function(a1: Cardinal; DestStr: Pointer; UnitOrder: Cardinal): PAnsiChar; stdcall;
  ScriptAction_Name2IndexHandler = procedure(uneax, unedx: Pointer; RtnIndex: PByte;
                                             ActionName: PAnsiChar); register;
  ScriptAction_Index2HandlerHandler = function(uneax, unedx: Pointer; RtnIndex: PByte): Pointer; register;
  ScriptAction_Type2IndexHandler = procedure(p_RtnIndex_ptr: Pointer; Action_ID: Byte;
                                             p_OrderUnit: PUnitStruct; p_TargetUnit: PUnitStruct;
                                             p_Position: PPosition); stdcall;
  MOUSE_EVENT_2UnitOrderHandler = function(CurtMouseEvent_ptr: Pointer; ActionType: Cardinal;
                                           ActionIndex: Cardinal; Position_DWORD_p: Cardinal;
                                           lPar1: Cardinal; lPar2: Cardinal): Cardinal; stdcall;
  Order2UnitHandler = function(ScriptIndex: Cardinal; ShiftKey: Cardinal; pp_Unit: Pointer;
                               pTargetp_Unit: Pointer; Position: PPosition; lPar1: Cardinal;
                               lPar2: Cardinal): Cardinal; stdcall;
  SubOrder2UnitHandler = function(ScriptIndex: Cardinal; ShiftKey: Cardinal; pp_Unit: Pointer;
                                  pTargetp_Unit: Pointer; Position: PPosition; lPar1: Cardinal;
                                  lPar2: Cardinal): Cardinal; stdcall;
  ORDERS_NewSubBuildOrderHandler = function(OrderType: Cardinal; BuilderPtr: PUnitStruct;
                                            UnitInfoID: Cardinal; QueueAmount: Integer): PUnitOrder; stdcall;
  UnitSubBuildClickHandler = procedure(UnitInfoName: PAnsiChar; BuilderPtr: PUnitStruct;
                                       QueueAmount: Integer); stdcall;
  ORDERS_RemoveAllBuildQueuesHandler = procedure(p_Unit: PUnitStruct; Unk: LongBool); stdcall;
  GetUnitFirstOrderTargatHandler = function(p_Unit: Pointer): Cardinal; stdcall;
  ORDERS_CreateObjectHandler = function(uneax, unedx: Cardinal; p_Memory: Pointer; Flags: Cardinal;
                                        lPar2: Cardinal; lPar1: Cardinal; TargetPosition: PPosition;
                                        TargetUnit: PUnitStruct; ActionType: Cardinal): PUnitOrder; register;
  ORDERS_QueueOrderHandler = procedure(p_Unit: PUnitStruct; Order1: PUnitOrder; Order2: PUnitOrder); stdcall;
  ORDERS_CancelOrderHandler = procedure(eax, edx: Cardinal; p_UnitOrder: PUnitOrder); register;
  ORDERS_MovementRelatedHandler = procedure(eax, edx: Cardinal; p_UnitOrder: PUnitOrder;
                                            Dist: Integer; p_Position: PPosition); register;
  ORDERS_ChaseUnitToBeRepairedHandler = function(p_Builder: PUnitStruct; p_TargetUnit: PUnitStruct;
                                                 TestedStateMask: Cardinal): LongBool; stdcall;
  ORDERS_DelayCallbackHandler = procedure(eax, edx: Cardinal; p_UnitOrder: PUnitOrder;
                                          Delay: Integer); register;
  ORDERS_RecoverMainOrderHandler = procedure(p_Unit: PUnitStruct; p_UnitOrder: PUnitOrder); stdcall;
  ORDERS_BackupMainOrderHandler = procedure(eax, edx: Cardinal; p_UnitOrder: PUnitOrder;
                                            p_OrderCallBack: Pointer); register;
  ORDERS_PushOrderHandler = procedure(p_Unit: PUnitStruct; p_UnitOrder: PUnitOrder); stdcall;

  // Units
  UNITS_CreateHandler = function(OwnerIndex: Cardinal; UnitInfoId: Cardinal; PosX_: Cardinal;
                                 PosZ_: Cardinal; PosY_: Cardinal; FullHp: Cardinal;
                                 UnitStateMask: Cardinal; UnitId: Cardinal): Pointer; stdcall;
  UNITS_CreateModelScriptsHandler = function(p_Unit: Pointer): Pointer; stdcall;
  UNITS_CreateMoveClassHandler = function(p_Unit: Pointer): Pointer; stdcall;
  UNITS_FixYPosHandler = procedure(p_Unit: PUnitStruct); stdcall;
  UNITS_FixYPosOtherTypeHandler = procedure(p_Unit: PUnitStruct); stdcall;
  UNITS_NewUnitPositionHandler = function(p_Unit: Pointer; NewX, NewY, NewZ: Integer;
                                          State: Cardinal): Cardinal; stdcall;
  UNITS_SetMetalExtractionRatioHandler = procedure(p_Unit: Pointer); stdcall;
  UNITS_StartWeaponsScriptsHandler = procedure(p_Unit: Pointer); stdcall;
  UNITS_QueryWeaponPositionHandler = procedure(p_Unit: PUnitStruct; out OutPosition: TPosition;
                                               cWeapIdx: Byte; PieceIdx: Integer); stdcall;
  UNITS_CallAimScriptsHandler = procedure(p_Unit: PUnitStruct; out OutPosition: TPosition;
                                          cWeapIdx: Byte); stdcall;
  UNITS_AllocateUnitHandler = function(p_Unit: Pointer; PosX: Integer; PosY: Integer;
                                       PosZ: Integer; FullHp: Integer): LongBool; stdcall;
  UNITS_AllocateMovementClassHandler = function(p_Unit: Pointer): Pointer; stdcall;
  UNITS_RebuildLOSHandler = procedure(p_Unit: PUnitStruct); stdcall;
  UNITS_RebuildFootPrintHandler = function(p_Unit: Pointer): Cardinal; stdcall;
  UNITS_GiveUnitHandler = procedure(p_Unit: Pointer; PlayerStruct: PPlayerStruct;
                                    Packet: Pointer); stdcall;
  UNITS_KillUnitHandler = procedure(p_Unit: Pointer; a2: Cardinal); stdcall;
  UNITS_MakeDamageHandler = procedure(p_AttackerUnit: PUnitStruct; p_TargetUnit: PUnitStruct;
                                      Amount: Integer; DamageType: Cardinal; Angle: Word); stdcall;
  UNITS_HealUnitHandler = function(Healerp_Unit: Pointer; Healedp_Unit: Pointer;
                                   Amount: Single): Integer; stdcall;
  UNITS_SetHotKeyGroupHandler = procedure(p_Unit: Pointer; GroupNr: Integer); stdcall;
  UnitStateProbeHandler = function(OffscreenPtr: Cardinal): Integer; stdcall;
  UnitBuilderProbeHandler = function(OffscreenPtr: Cardinal): Integer; stdcall;
  Send_UnitBuildFinishedHandler = function(p_Unit: Pointer; Unit2Ptr: Pointer): Integer; stdcall;
  Send_UnitDeathHandler = function(p_Unit: Pointer; a2: Integer): Integer; stdcall;
  FreeUnitOrdersHandler = procedure(p_Unit: Pointer); stdcall;
  AutoAimHandler = procedure(p_Unit: PUnitStruct); stdcall;
  CallbackForUnitsInDistanceHandler = procedure(p_Position: PPosition; Distance: Integer;
                                                UnitSearchCallbackRec: PUnitSearchCallbackRec); stdcall;
  SearchForReclamateFeaturesHandler = function(p_Position: PPosition; Distance: Integer;
                                               p_FoundPosition: PPosition; p_OutFeatureEnergy: PSingle;
                                               p_Unk: PPosition; p_Unk2: PSingle): LongBool; stdcall;

  // Network and multiplayer games related stuff
//  HAPINET_guaranteepacketsHandler = function(NewState: Integer): Integer; stdcall;
  HAPI_BroadcastMessageHandler = function(FromPID: TDPID; p_Buffer: Pointer;
                                          BufferSize: Cardinal): LongBool; stdcall;
  HAPI_SendMessageHandler = function(FromPID: TDPID; ToPID: TDPID; p_Buffer: Pointer;
                                     BufferSize: Cardinal): LongBool; stdcall;
  //DirectID2PlayerAryHandler = function(a1: LongInt): Byte; stdcall;
  GetLocalPlayerDPIDHandler = function: TDPID; cdecl;
  GetSharedPlayerDPIDHandler = function: TDPID; cdecl;
  IsLocalPlayerHostHandler = function: LongBool; cdecl;
  //UpdateGameInfoHandler = function: LongBool; cdecl;
  //Send_PacketPlayerInfoHandler = procedure; cdecl;

  // Ingame reporter
  REPORTER_PlayerInfoHandler = function(InfoType: Integer): Integer; stdcall;

  // COB Engine
  COBEngine_LoadScriptFromFileHandler = function(FilePath: PAnsiChar): Pointer; stdcall;
  COBEngine_StartScriptHandler = procedure(a1: Cardinal; a2: Cardinal;
                                           UnitScriptsData_p: Pointer; lArg4: Integer;
                                           lArg3: Integer; lArg2: Integer; lArg1: Integer;
                                           lArgsCount: Cardinal; Guaranteed: LongBool;
                                           p_Callback: Pointer; const Name: PAnsiChar); register;
  COBEngine_QueryScriptHandler = function(a1: Cardinal; a2: Cardinal;
                                          UnitScriptsData_p: Pointer; lArg4: PInteger;
                                          lArg3: PInteger; lArg2: PInteger; lArg1: PInteger;
                                          const Name: PAnsiChar): LongInt; register;
  COBEngine_DoScriptsNowHandler = function(COBData_p: Pointer): Integer; stdcall;

  // GFX
  DrawGameScreenHandler = procedure(DrawUnits: Integer; BlitScreen: Integer); stdcall;
  DrawHealthBarsHandler = procedure(p_Offscreen: Pointer; p_Unit: PUnitStruct;
                                    PosX: Integer; PosY: Integer); stdcall;
  DrawUnitHandler = procedure(p_Offscreen: Pointer; p_Unit: PUnitStruct); stdcall;
  DrawUnitSelectBoxRectHandler = procedure(p_Offscreen: Pointer; p_Unit: PUnitStruct); stdcall;
  DrawBarHandler = procedure(p_Offscreen: Pointer; p_TagRect: PtagRECT; ColorOffset: Byte); stdcall;
  DrawTranspRectangleHandler = procedure(p_Offscreen: Pointer; Position: Pointer;
                                         ColorOffset: Byte); stdcall;
  DrawPointHandler = procedure(p_Offscreen: Pointer; X, Y: Integer; ColorOffset: Byte); stdcall;
  DrawUnk1Handler = procedure(p_Offscreen: Pointer; Position: Pointer; ColorOffset: Byte); stdcall;
  DrawLineHandler = procedure(p_Offscreen: Pointer; X, Y, X2, Y2: Integer;
                              ColorOffset: Byte); stdcall;
  DrawLightHandler = procedure(p_Offscreen: Pointer; X, Y, X2, Y2: Integer;
                               ColorOffset: Byte); stdcall;
  DrawAlphaHandler = procedure(p_Offscreen: Pointer; X, Y, X2, Y2: Integer;
                               ColorOffset: Byte); stdcall;
  DrawLine2Handler = procedure(p_Offscreen: Pointer; x1, y1, x2, y2: Integer;
                               Color: Byte); stdcall;
  DrawCircleHandler = procedure(p_Offscreen: Pointer; CenterX, CenterY, Radius: Integer;
                                ColorOffset: Byte); stdcall;
  DrawDotteCircleHandler = procedure(p_Offscreen: Pointer; CenterX, CenterY, Radius: Integer;
                                     ColorOffset: Integer; Spacing: Word; Dotte_b: Integer); stdcall;
  DrawRangeCircleHandler = procedure(p_Offscreen: Pointer; CirclePointer: Cardinal;
                                     Position: PPosition; Radius: Integer; ColorOffset: Integer;
                                     Text: PAnsiChar; Priority: Integer); stdcall;
  DrawProgressBarHandler = procedure(p_Offscreen: Pointer; Position: Pointer;
                                     BarPosition: Integer); stdcall;
  DrawTransparentBoxHandler = procedure(p_Offscreen: Pointer; Position: PtagRECT;
                                        Transp: Integer); stdcall;
  DrawTextCustomFontHandler = procedure(p_Offscreen: Pointer; const Str: PAnsiChar;
                                        Left: Integer; Top: Integer; MaxWidth: Integer); stdcall;
  DrawTextHandler = procedure(p_Offscreen: Pointer; const Str: PAnsiChar; Left: Integer;
                              Top: Integer; MaxLen: Integer; Background: Integer); stdcall;
  DrawText_ThinHandler = procedure(p_Offscreen: Pointer; const Str: PAnsiChar; Left: Integer;
                                   Top: Integer; MaxLen: Integer; a6: Integer;
                                   Background: Integer); stdcall;
  SetFONTLENGTH_ptrHandler = function(NewFontLength: Cardinal): LongInt; stdcall;
  GAF_Name2SequenceHandler = function(GafStruct: Pointer; SequenceName: PAnsiChar): PGAFSequence; stdcall;
  GAF_SequenceIndex2FrameHandler = function(p_GAFSequence: PGAFSequence; Index: Integer): PGAFFrame; stdcall;
  GAF_OpenAnimsFileHandler = function(FileName: PAnsiChar): Pointer; stdcall;
  GAF_DrawTransformedHandler = function(p_Offscreen: Pointer; GafSequence: Pointer;
                                        Position: PGAFFrameTransform; Pos2: PGAFFrameTransform): Pointer; stdcall;
  ShowExplodeGafHandler = procedure(Position: PPosition; p_GAFAnim: PGAFSequence;
                                    AddGlow: Integer; AddSmoke: Integer); stdcall;
  sub_4B8B30Handler = procedure(p_Exp: Pointer; p_GAFAnim: Pointer; StartingFrame: LongInt); stdcall;
  EmitSfx_SmokeInfiniteHandler = function(Position: PPosition; nPrior: Integer): Byte; stdcall;
  EmitSfx_BlackSmokeHandler = function(Position: PPosition; nPrior: Integer): Byte; stdcall;
  EmitSfx_GraySmokeHandler = function(Position: PPosition; nPrior: Integer): Byte; stdcall;
  EmitSfx_NanoParticlesHandler = function(p_PosStart: PPosition; p_PosTarget: PNanolathePos;
                                          nPrior: Word): Cardinal; stdcall;
  EmitSfx_NanoParticlesReverseHandler = function(p_PosTarget: PNanolathePos; p_PosStart: PPosition;
                                                 nPrior: Word): Cardinal; stdcall;
  EmitSfx_TeleportHandler = function(p_PosStart, p_PosTarget: PPosition; lSize: Integer;
                                     nPrior: Word): Cardinal; stdcall;
  EmitSfx_BubblesHandler = function(p_PosStart, p_PosTarget: PPosition; lSize: Integer;
                                    nPrior: Word): Cardinal; stdcall;
  EmitSfx_Unk5Handler = function(p_PosStart: PPosition; nPrior: Word): Cardinal; stdcall;

  // SFX - Sounds
  PlaySound_UnitSpeechHandler = function(p_Unit: PUnitStruct; speechtype: Cardinal;
                                         speechtext: PAnsiChar): byte; stdcall;
  PlaySound_2D_NameHandler = function(SoundName: PAnsiChar; Broadcast: Integer): Integer; stdcall;
  PlaySound_2D_IDHandler = function(SoundNum: Cardinal; Broadcast: Integer): Integer; stdcall;
  PlaySound_3D_NameHandler = function(SoundName: PAnsiChar; GridPosition: Pointer;
                                      Broadcast: Integer): Integer; stdcall;
  PlaySound_3D_IDHandler = function(SoundNum: Cardinal; Position: Pointer;
                                    Broadcast: Integer): Integer; stdcall;

  // GUI - menus
  GUIGADGET_GetStatusHandler = function(pTAUI: Pointer; Name: PAnsiChar): Integer; stdcall;
  GUIGADGET_SetStatusHandler = function(pTAUI: Pointer; Name: PAnsiChar; NewVal: Integer): Integer; stdcall;
  GUIGADGET_GetActiveHandler = function(pTAUI: Pointer; Name: PAnsiChar): Integer; stdcall;
  GUIGADGET_SetActiveHandler = function(pTAUI: Pointer; Name: PAnsiChar; NewVal: Integer): Integer; stdcall;
  GUIGADGET_SetTextHandler = function(pTAUI: Pointer; Name: PAnsiChar; NewStr: PAnsiChar;
                                      Length: Integer): Integer; stdcall;
  GUIGADGET_SetGrayedOutHandler = function(pTAUI: Pointer; Name: PAnsiChar; NewVal: Integer): Integer; stdcall;
  GUIGADGET_WasPressedHandler = function(pTAUI: Pointer; Name: PAnsiChar): LongBool; stdcall;
  GUICONTROL_IsOnTopHandler = function(pTAUI: Pointer; const Name: PAnsiChar): LongBool; stdcall;
  GetStrExtentHandler = function(Str: PAnsiChar): Integer; stdcall;
  GetCustomFontCharWidthHandler = function: Integer; stdcall;
  GetCustomFontStrExtentHandler = function(FontHandle: Pointer; Str: PAnsiChar): Integer; stdcall;

  // Engine registry and INI options
  REGISTRY_ReadIntegerHandler = function(const lpSubKey: PAnsiChar; const lpValueName: PAnsiChar;
                                         Buffer: Pointer): Integer; stdcall;
  REGISTRY_WriteIntegerHandler = function(const lpSubKey: PAnsiChar; const lpValueName: PAnsiChar;
                                          Data: Integer): Integer; stdcall;
  REGISTRY_SaveSettingsHandler = procedure; cdecl;

  // Memory
  MEM_AllocHandler = function(Size: Cardinal): Pointer; cdecl;
  MEM_ReAllocHandler = function(Memory: Pointer; NewSize: Cardinal): Pointer; cdecl;
  MEM_FreeHandler = procedure(Memory: Pointer); cdecl;
  MEM_Free_PointerHandler = procedure(Memory: Pointer); cdecl;
  MEM_Free_PPointerHandler = procedure(Memory: Pointer); cdecl;
  MEM_AllowReadWriteHandler = function(Address: Cardinal): Integer; cdecl;
  MEM_SetReadOnlyHandler = function(Address: Cardinal): Integer; cdecl;

  // HPI, HAPIBANK and TDF files
  HAPIFILE_GetFileLengthHandler = function(FilePath: PAnsiChar): Integer; stdcall;
  HAPIFILE_FindFirstHandler = function(lpFileName: PAnsiChar; finddata_ptr: Pointer;
                                       SearchType: Integer; TryNext: Integer): Integer; stdcall;
  HAPIFILE_FindNextHandler = function(SearchHandle: Integer; finddata_ptr: Pointer): Integer; stdcall;
  HAPIFILE_FindCloseHandler = function(SearchHandle: Integer): Integer; stdcall;
  HAPIFILE_ReadFileHandler = function(FilePath: PAnsiChar; StartOffset: Integer): Pointer; stdcall;
  GetLocalizedFilePathHandler = procedure(Buffer: Pointer; FileDir: PAnsiChar; FileName: PAnsiChar;
                                          FileExt: PAnsiChar); stdcall;
  Open3DOFileHandler = function(FileName: PAnsiChar): Pointer; stdcall;
  Parse3DOFileHandler = procedure(p_3DO: Pointer); stdcall;
  TextureMatch3DOHandler = procedure(p_3DO: Pointer; ModelName: PAnsiChar); stdcall;
  HAPIFILE_InsertToArrayHandler = function(Filename: PAnsiChar; Priority: Integer): Integer; stdcall;
  HAPIBANK_OpenAccountHandler = function(Eax: Pointer; Edx: Pointer; HAPIBANK: Pointer;
                                         const AccountName: PAnsiChar): LongBool; register;
  HAPIBANK_WriteIntegerHandler = function(Eax: Pointer; Edx: Pointer; HAPIBANK: Pointer;
                                          Value: Integer; const Description: PAnsiChar): LongBool; register;
  HAPIBANK_ReadIntegerHandler = function(Eax: Pointer; Edx: Pointer; HAPIBANK: Pointer;
                                         DefaultVal: Integer; const Description: PAnsiChar): Integer; register;
  HAPIBANK_WriteStringHandler = function(Eax: Pointer; Edx: Pointer; HAPIBANK: Pointer;
                                         Description: PAnsiChar; Value: PAnsiChar): LongBool; register;
  HAPIBANK_WriteBinDataHandler = function(Eax: Pointer; Edx: Pointer; HAPIBANK: Pointer;
                                          WriteSize: Cardinal; Data: Pointer): Cardinal; register;
  HAPIBANK_ReadBinDataHandler = function(Eax: Pointer; Edx: Pointer; HAPIBANK: Pointer;
                                         ReadSize: Cardinal; Dest: Pointer): Cardinal; register;
  HAPIBANK_GetItemSizeHandler = function(Eax: Pointer; Edx: Pointer; HAPIBANK: Pointer): Integer; register;
  HAPIBANK_AccessSafeDepositHandler = function(Eax: Pointer; Edx: Pointer; HAPIBANK: Pointer;
                                               Description: PAnsiChar): LongBool; register;
  HAPIBANK_SeekInHexHandler = function(Eax: Pointer; Edx: Pointer; HAPIBANK: Pointer;
                                       Position: Integer): Integer; register;
  TdfFile_SectionExistsHandler = function(Eax: Cardinal; Edx: Cardinal; Ecx: Cardinal;
                                          SectionName: PAnsiChar): Boolean; register;
  TdfFile_GetIntHandler = function(Eax: Cardinal; Edx: Cardinal; Ecx: Cardinal;
                                   DefaultNumber: LongInt; TagName: PAnsiChar): Integer; register;
  TdfFile_GetStrHandler = function(Eax: Cardinal; Edx: Cardinal; Ecx: Cardinal;
                                   Default: Pointer; BufLen: Integer; Name: Pointer;
                                   ReceiveBuf: Pointer): Integer; register;
  TdfFile_GetFloatHandler = function(Eax: Cardinal; Edx: Cardinal; Ecx: Cardinal;
                                     DefaultNumber: Double; TagName: PAnsiChar): Double; register;
  TdfFile_GetRootHandler = function(Eax: Cardinal; Edx: Cardinal; TDFhandle: Cardinal): Cardinal; register;
  TdfFile_SetRootHandler = procedure(Eax: Cardinal; Edx: Cardinal; TDFhandle: Cardinal;
                                     NewRoot: Cardinal); register;
  SetCurrentDirectoryToTAPathHandler = function: Boolean; cdecl;

  // Not used
  InitPlayerStructHandler = function(PlayerPtr: PPlayerStruct): Pointer; stdcall;

var
  GetTAProgramStruct: GetTAProgramStructHandler;
  GetGameingType: GetGameingTypeHandler;
  Game_SetLOSState: Game_SetLOSStateHandler;
  TA_UpdateLOS: TA_UpdateLOSHandler;
  ScrollView: ScrollViewHandler;
  Mouse_SetDrawMouse: Mouse_SetDrawMouseHandler;
  DrawOptionsTab: DrawOptionsTabHandler;
  SetGamma: SetGammaHandler;
  FreeObjectState: FreeObjectStateHandler;
  FreeMoveClass: FreeMoveClassHandler;
  FreeUnitScriptData: FreeUnitScriptDataHandler;

  // turret weap aiming
  sub_49D910: sub_49D910Handler;

  GetUnit_BuildWeaponProgress: GetUnit_BuildWeaponProgressHandler;
  UnitExplosion: UnitExplosionHandler;
  TestHeal: TestHeal_Handler;
  UNITS_SetStateMask: UNITS_SetStateMaskHandler;
  Trajectory3: Trajectory3Handler;
  UnitAutoAim_CheckUnitWeapon: UnitAutoAim_CheckUnitWeaponHandler;
  TranslateString: TranslateStringHandler;
  _strcmpi: _strcmpiHandler;
  TA_AttachDetachUnit: TA_AttachDetachUnitHandler;
  TerminateProcess_WithWarning: TerminateProcess_WithWarningHandler;
  LoadHPITerainFile: LoadHPITerainFileHandler;
  GetTA_ScreenWidth: GetTA_ScreenWidthHandler;
  CorrecLinetPosition: CorrecLinetPositionHandler;
  GetFontType: GetFontTypeHandler;
  GetFontBackgroundColor: GetFontBackgroundColorHandler;
  SetFontColor: SetFontColorHandler;
  SetFontType: SetFontTypeHandler;
  GetFontCharWidth: GetFontCharWidthHandler;
  Msg_Reminder: Msg_ReminderHandler;
  InterpretCommand: InterpretCommandHandler;
  DoInterpretCommand: DoInterpretCommandHandler;
  IterateMaps: IterateMapsHandler;
  LoadCampaign_UniqueUnits: LoadCampaign_UniqueUnitsHandler;
  Campaign_ParseUnitInitialMission: Campaign_ParseUnitInitialMissionHandler;
  PLAYERS_Index2DPlayID: PLAYERS_Index2DPlayIDHandler;
  UNITINFO_Name2ID: UNITINFO_Name2IDHandler;
  FindSpot_CategorysAry: FindSpot_CategorysAryHandler;
  TestGridSpot: TestGridSpotHandler;
  TestGridSpotAI: TestGridSpotAIHandler;
  TestBuildSpot: TestBuildSpotHandler;
  CanAttachAtGridSpot: CanAttachAtGridSpotHandler;
  CanCloseOrOpenYard: CanCloseOrOpenYardHandler;
  GetPiecePosition: GetPiecePositionHandler;
  GetUnitPiecePosition: GetUnitPiecePositionHandler;
  GetContext: GetContextHandler;
  TextCommand_LOS: TextCommand_LOSHandler;
  rand2: rand2Handler;
  TA_Atan2: TA_Atan2Handler;
  TurnXLookup: TurnXLookupHandler;
  TurnZLookup: TurnZLookupHandler;
  LoadTNTFile: LoadTNTFileHandler;
  LoadGameData_Main: LoadGameData_MainHandler;
  CopyGafToContext: CopyGafToContextHandler;
  AlphaCompsteBuf2OFFScreen: AlphaCompsteBuf2OFFScreenHandler;
  InitRadar: InitRadarHandler;
  CompositeBuffer: CompositeBufferHandler;
  CompositeBuf2_OFFSCREEN: CompositeBuf2_OFFSCREENHandler;
  DeselectAllUnits: DeselectAllUnitsHandler;
  UpdateIngameGUI: UpdateIngameGUIHandler;
  ApplySelectUnitMenu: ApplySelectUnitMenuHandler;

  // Chat messages and text commands
  ShowReminderMsg: ShowReminderMsgHandler;
  ShowChatMessage: ShowChatMessageHandler;
  NewChatText: NewChatTextHandler;
  ClearChat: ClearChatHandler;

  // Map data
  LoadMap: LoadMapHandler;
  sub_435D30: sub_435D30Handler;
  CalculateOTACRC: CalculateOTACRCHandler;
  UpdateViewMap: UpdateViewMapHandler;
  GetPosHeight: GetPosHeightHandler;
  UnitInPlayerLOS: UnitInPlayerLOSHandler;
  PositionInPlayerMapped: PositionInPlayerMappedHandler;
  LoadMap_AverageHeightMap: LoadMap_AverageHeightMapHandler;
  LoadMap_PLOT3: LoadMap_PLOT3Handler;
  GetUnitAtMouse: GetUnitAtMouseHandler;
  IsPositionInRect: IsPositionInRectHandler;
  Position2GridPlotWreck: Position2GridPlotWreckHandler;
  Position2GridPlot: Position2GridPlotHandler;
  GetTPosition: GetTPositionHandler;
  GetGridPosPLOT: GetGridPosPLOTHandler;
  GetFeatureTypeFromOrder: GetFeatureTypeFromOrderHandler;
  GetGridPosFeature: GetGridPosFeatureHandler;
  FeatureName2ID: FeatureName2IDHandler;
  FeatureNameNotListed2ID: FeatureNameNotListed2IDHandler;
  LoadFeature: LoadFeatureHandler;
  ReleaseFeature_TdfVector: ReleaseFeature_TdfVectorHandler;
  SpawnFeatureOnMap: SpawnFeatureOnMapHandler;
  FEATURES_Destroy_3D: FEATURES_Destroy_3DHandler;
  FEATURES_Destroy: FEATURES_DestroyHandler;
  FEATURES_StartBurn: FEATURES_StartBurnHandler;
  FEATURES_TakeWeaponDamage: FEATURES_TakeWeaponDamageHandler;

  // Weapons and projectiles
  WEAPONS_Name2Ptr: WEAPONS_Name2PtrHandler;
  PROJECTILES_FireMapWeap: PROJECTILES_FireMapWeapHandler;
  WEAPONS_ProjectileDamage: WEAPONS_ProjectileDamageHandler;
  fire_callback1: fire_callbackHandler;
  fire_callback2: fire_callbackHandler;
  fire_callback3: fire_callbackHandler;
  fire_callback0: fire_callback0Handler;
  UNITS_FireProjectile_0_3: UNITS_FireProjectile_0_3Handler;
  UNITS_FireProjectile_1: UNITS_FireProjectile_1Handler;
  UNITS_FireProjectile_0: UNITS_FireProjectile_0Handler;
  InitProjectile: InitProjectileHandler;

  // Units Orders
  GetPrepareOrderName: GetPrepareOrderNameHandler;
  ScriptAction_Name2Index: ScriptAction_Name2IndexHandler;
  ScriptAction_Index2Handler: ScriptAction_Index2HandlerHandler;
  ScriptAction_Type2Index: ScriptAction_Type2IndexHandler;
  MOUSE_EVENT_2UnitOrder: MOUSE_EVENT_2UnitOrderHandler;
  Order2Unit: Order2UnitHandler;
  SubOrder2Unit: SubOrder2UnitHandler;
  ORDERS_NewSubBuildOrder: ORDERS_NewSubBuildOrderHandler;
  UnitSubBuildClick: UnitSubBuildClickHandler;
  ORDERS_RemoveAllBuildQueues: ORDERS_RemoveAllBuildQueuesHandler;
  GetUnitFirstOrderTargat: GetUnitFirstOrderTargatHandler;
  ORDERS_CreateObject: ORDERS_CreateObjectHandler;
  ORDERS_QueueOrder: ORDERS_QueueOrderHandler;
  ORDERS_CancelOrder: ORDERS_CancelOrderHandler;
  ORDERS_MovementRelated: ORDERS_MovementRelatedHandler;
  ORDERS_ChaseUnitToBeRepaired: ORDERS_ChaseUnitToBeRepairedHandler;
  ORDERS_DelayCallback: ORDERS_DelayCallbackHandler;
  ORDERS_RecoverMainOrder: ORDERS_RecoverMainOrderHandler;
  ORDERS_BackupMainOrder: ORDERS_BackupMainOrderHandler;
  ORDERS_PushOrder: ORDERS_PushOrderHandler;

  // Units
  UNITS_Create: UNITS_CreateHandler;
  UNITS_CreateModelScripts: UNITS_CreateModelScriptsHandler;
  UNITS_CreateMoveClass: UNITS_CreateMoveClassHandler;
  UNITS_FixYPos: UNITS_FixYPosHandler;
  UNITS_FixYPosOtherType: UNITS_FixYPosOtherTypeHandler;
  UNITS_NewUnitPosition: UNITS_NewUnitPositionHandler;
  UNITS_SetMetalExtractionRatio: UNITS_SetMetalExtractionRatioHandler;
  UNITS_StartWeaponsScripts: UNITS_StartWeaponsScriptsHandler;
  UNITS_QueryWeaponPosition: UNITS_QueryWeaponPositionHandler;
  UNITS_CallAimScripts: UNITS_CallAimScriptsHandler;
  UNITS_AllocateUnit: UNITS_AllocateUnitHandler;
  UNITS_AllocateMovementClass: UNITS_AllocateMovementClassHandler;
  UNITS_RebuildLOS: UNITS_RebuildLOSHandler;
  UNITS_RebuildFootPrint: UNITS_RebuildFootPrintHandler;
  UNITS_GiveUnit: UNITS_GiveUnitHandler;
  UNITS_KillUnit: UNITS_KillUnitHandler;
  UNITS_MakeDamage: UNITS_MakeDamageHandler;
  UNITS_HealUnit: UNITS_HealUnitHandler;
  UNITS_SetHotKeyGroup: UNITS_SetHotKeyGroupHandler;
  UnitStateProbe: UnitStateProbeHandler;
  UnitBuilderProbe: UnitBuilderProbeHandler;
  Send_UnitBuildFinished: Send_UnitBuildFinishedHandler;
  Send_UnitDeath: Send_UnitDeathHandler;
  FreeUnitOrders: FreeUnitOrdersHandler;
  AutoAim: AutoAimHandler;
  CallbackForUnitsInDistance: CallbackForUnitsInDistanceHandler;
  SearchForReclamateFeatures: SearchForReclamateFeaturesHandler;

  // Network and multiplayer games related stuff
  //  HAPINET_guaranteepackets: HAPINET_guaranteepacketsHandler;
  HAPI_BroadcastMessage: HAPI_BroadcastMessageHandler;
  HAPI_SendMessage: HAPI_SendMessageHandler;
  //  DirectID2PlayerAry: DirectID2PlayerAryHandler;
  GetLocalPlayerDPID: GetLocalPlayerDPIDHandler;
  GetSharedPlayerDPID: GetSharedPlayerDPIDHandler;
  IsLocalPlayerHost: IsLocalPlayerHostHandler;
 // UpdateGameInfo: UpdateGameInfoHandler;
 //  Send_PacketPlayerInfo: Send_PacketPlayerInfoHandler;

  // Ingame reporter
  REPORTER_PlayerInfo: REPORTER_PlayerInfoHandler;

  // COB Engine                                                      ApplySelectUnitMenuHandler
  COBEngine_LoadScriptFromFile: COBEngine_LoadScriptFromFileHandler;
  COBEngine_StartScript: COBEngine_StartScriptHandler;
  COBEngine_QueryScript: COBEngine_QueryScriptHandler;
  COBEngine_DoScriptsNow: COBEngine_DoScriptsNowHandler;

  // GFX
  DrawGameScreen: DrawGameScreenHandler;
  DrawHealthBars: DrawHealthBarsHandler;
  DrawUnit: DrawUnitHandler;
  DrawUnitSelectBoxRect: DrawUnitSelectBoxRectHandler;
  DrawBar: DrawBarHandler;
  DrawTranspRectangle: DrawTranspRectangleHandler;
  DrawPoint: DrawPointHandler;
  DrawUnk1: DrawUnk1Handler;
  DrawLine: DrawLineHandler;
  DrawLight: DrawLightHandler;
  DrawAlpha: DrawAlphaHandler;
  DrawLine2: DrawLine2Handler;
  DrawCircle: DrawCircleHandler;
  DrawDotteCircle: DrawDotteCircleHandler;
  DrawRangeCircle: DrawRangeCircleHandler;
  DrawProgressBar: DrawProgressBarHandler;
  DrawTransparentBox: DrawTransparentBoxHandler;
  DrawTextCustomFont: DrawTextCustomFontHandler;
  DrawText: DrawTextHandler;
  DrawText_Thin: DrawText_ThinHandler;
  SetFONTLENGTH_ptr: SetFONTLENGTH_ptrHandler;
  GAF_Name2Sequence: GAF_Name2SequenceHandler;
  GAF_SequenceIndex2Frame: GAF_SequenceIndex2FrameHandler;
  GAF_OpenAnimsFile: GAF_OpenAnimsFileHandler;
  GAF_DrawTransformed: GAF_DrawTransformedHandler;
  ShowExplodeGaf: ShowExplodeGafHandler;
  sub_4B8B30: sub_4B8B30Handler;
  EmitSfx_SmokeInfinite: EmitSfx_SmokeInfiniteHandler;
  EmitSfx_BlackSmoke: EmitSfx_BlackSmokeHandler;
  EmitSfx_GraySmoke: EmitSfx_GraySmokeHandler;
  EmitSfx_NanoParticles: EmitSfx_NanoParticlesHandler;
  EmitSfx_NanoParticlesReverse: EmitSfx_NanoParticlesReverseHandler;
  EmitSfx_Teleport: EmitSfx_TeleportHandler;
  EmitSfx_Bubbles: EmitSfx_BubblesHandler;
  EmitSfx_Unk5: EmitSfx_Unk5Handler;

  // SFX - Sounds
  PlaySound_UnitSpeech: PlaySound_UnitSpeechHandler;
  PlaySound_2D_Name: PlaySound_2D_NameHandler;
  PlaySound_2D_ID: PlaySound_2D_IDHandler;
  PlaySound_3D_Name: PlaySound_3D_NameHandler;
  PlaySound_3D_ID: PlaySound_3D_IDHandler;

  // GUI - menus
  GUIGADGET_GetStatus: GUIGADGET_GetStatusHandler;
  GUIGADGET_SetStatus: GUIGADGET_SetStatusHandler;
  GUIGADGET_GetActive: GUIGADGET_GetActiveHandler;
  GUIGADGET_SetActive: GUIGADGET_SetActiveHandler;
  GUIGADGET_SetText: GUIGADGET_SetTextHandler;
  GUIGADGET_SetGrayedOut: GUIGADGET_SetGrayedOutHandler;
  GUIGADGET_WasPressed: GUIGADGET_WasPressedHandler;
  GUICONTROL_IsOnTop: GUICONTROL_IsOnTopHandler;
  GetStrExtent: GetStrExtentHandler;
  GetCustomFontCharWidth: GetCustomFontCharWidthHandler;
  GetCustomFontStrExtent: GetCustomFontStrExtentHandler;

  // Engine registry and INI options
  REGISTRY_ReadInteger: REGISTRY_ReadIntegerHandler;
  REGISTRY_WriteInteger: REGISTRY_WriteIntegerHandler;
  REGISTRY_SaveSettings: REGISTRY_SaveSettingsHandler;

  // Memory
  MEM_Alloc: MEM_AllocHandler;
  MEM_ReAlloc: MEM_ReAllocHandler;
  MEM_Free: MEM_FreeHandler;
  MEM_Free_Pointer: MEM_Free_PointerHandler;
  MEM_Free_PPointer: MEM_Free_PPointerHandler;
  MEM_AllowReadWrite: MEM_AllowReadWriteHandler;
  MEM_SetReadOnly: MEM_SetReadOnlyHandler;

  // HPI, HAPIBANK and TDF files
  HAPIFILE_GetFileLength: HAPIFILE_GetFileLengthHandler;
  HAPIFILE_FindFirst: HAPIFILE_FindFirstHandler;
  HAPIFILE_FindNext: HAPIFILE_FindNextHandler;
  HAPIFILE_FindClose: HAPIFILE_FindCloseHandler;
  HAPIFILE_ReadFile: HAPIFILE_ReadFileHandler;
  GetLocalizedFilePath: GetLocalizedFilePathHandler;
  Open3DOFile: Open3DOFileHandler;
  Parse3DOFile: Parse3DOFileHandler;
  TextureMatch3DO: TextureMatch3DOHandler;
  HAPIFILE_InsertToArray: HAPIFILE_InsertToArrayHandler;
  HAPIBANK_OpenAccount: HAPIBANK_OpenAccountHandler;
  HAPIBANK_WriteInteger: HAPIBANK_WriteIntegerHandler;
  HAPIBANK_ReadInteger: HAPIBANK_ReadIntegerHandler;
  HAPIBANK_WriteString: HAPIBANK_WriteStringHandler;
  HAPIBANK_WriteBinData: HAPIBANK_WriteBinDataHandler;
  HAPIBANK_ReadBinData: HAPIBANK_ReadBinDataHandler;
  HAPIBANK_GetItemSize: HAPIBANK_GetItemSizeHandler;
  HAPIBANK_AccessSafeDeposit: HAPIBANK_AccessSafeDepositHandler;
  HAPIBANK_SeekInHex: HAPIBANK_SeekInHexHandler;
  TdfFile_SectionExists: TdfFile_SectionExistsHandler;
  TdfFile_GetInt: TdfFile_GetIntHandler;
  TdfFile_GetStr: TdfFile_GetStrHandler;
  TdfFile_GetFloat: TdfFile_GetFloatHandler;
  TdfFile_GetRoot: TdfFile_GetRootHandler;
  TdfFile_SetRoot: TdfFile_SetRootHandler;
  SetCurrentDirectoryToTAPath: SetCurrentDirectoryToTAPathHandler;

  // Not used
  InitPlayerStruct: InitPlayerStructHandler;

function SHiWord(A: Cardinal): SmallInt; overload;
function SHiWord(A: Integer): SmallInt; overload;
procedure InterpretInternalCommand(CommandText: string);
procedure SendTextLocal(Text: string);

implementation

procedure InterpretInternalCommand(CommandText: string);
begin
  InterpretCommand(PChar(CommandText), TA_ACCESS);
end;

procedure SendTextLocal(Text: string);
begin
  ShowReminderMsg(PAnsiChar(Text), 0);
end;

function SHiWord(A: Cardinal): SmallInt; overload;
begin
  Result := SmallInt(A div 65536);
end;

function SHiWord(A: Integer): SmallInt; overload;
begin
  Result := SmallInt(Cardinal(A) div 65536);
end;

initialization
  @GetTAProgramStruct            := Pointer($004B6220);
  @GetGameingType                := Pointer($00435100);
  @Game_SetLOSState              := Pointer($004816A0);
  @TA_UpdateLOS                  := Pointer($004816A0);
  @ScrollView                    := Pointer($0041C4C0);
  @Mouse_SetDrawMouse            := Pointer($004C22D0);
  @DrawOptionsTab                := Pointer($0045FFB0);
  @SetGamma                      := Pointer($004BA590);
  @FreeObjectState               := Pointer($0045AAA0);
  @FreeMoveClass                 := Pointer($0043DD10);
  @FreeUnitScriptData            := Pointer($00485E30);

  @sub_49D910                    := Pointer($49D910);
  @GetUnit_BuildWeaponProgress   := Pointer($439D20);
  @UnitExplosion                 := Pointer($0049B000);
  @TestHeal                      := Pointer($00401180);
  @UNITS_SetStateMask            := Pointer($0048B090);
  @Trajectory3                   := Pointer($0049AA80);
  @UnitAutoAim_CheckUnitWeapon   := Pointer($0049ABB0);
  @TranslateString               := Pointer($004C5740);
  @_strcmpi                      := Pointer($004F8A70);
  @TA_AttachDetachUnit           := Pointer($0048AAC0);
  @TerminateProcess_WithWarning  := Pointer($004B6290);
  @LoadHPITerainFile             := Pointer($00429660);
  @GetTA_ScreenWidth             := Pointer($004B6700);
  @CorrecLinetPosition           := Pointer($004BEA20);
  @GetFontType                   := Pointer($004C1440);
  @GetFontBackgroundColor        := Pointer($004C13F0);
  @SetFontColor                  := Pointer($004C13A0);
  @SetFontType                   := Pointer($004C1420);
  @GetFontCharWidth              := Pointer($004C1450);
  @Msg_Reminder                  := Pointer($046BC70);
  @InterpretCommand              := Pointer($417B50);
  @DoInterpretCommand            := Pointer($4B7900);
  @IterateMaps                   := Pointer($434BF0);
  @LoadCampaign_UniqueUnits      := Pointer($00488310);
  @Campaign_ParseUnitInitialMission := Pointer($00487BF0);
  @PLAYERS_Index2DPlayID         := Pointer($0044FFD0);
  @UNITINFO_Name2ID              := Pointer($00488B10);
  @FindSpot_CategorysAry         := Pointer($00488C50);
  @TestGridSpot                  := Pointer($0047D2E0);
  @TestGridSpotAI                := Pointer($0047D820);
  @TestBuildSpot                 := Pointer($004197D0);
  @CanAttachAtGridSpot           := Pointer($0047DB70);
  @CanCloseOrOpenYard            := Pointer($0047D970);
  @GetPiecePosition              := Pointer($0043E060);
  @GetUnitPiecePosition          := Pointer($0043DEF0);
  @GetContext                    := Pointer($4C5E70);
  @TextCommand_LOS               := Pointer($416D50);
  @rand2                         := Pointer($004E4870);
  @TA_Atan2                      := Pointer($004B715A);
  @TurnXLookup                   := Pointer($004B70EF);
  @TurnZLookup                   := Pointer($004B7123);
  @LoadTNTFile                   := Pointer($00429660);
  @LoadGameData_Main             := Pointer($004917D0);
  @CopyGafToContext              := Pointer($004B7F90);
  @AlphaCompsteBuf2OFFScreen     := Pointer($004B8500);
  @InitRadar                     := Pointer($4669B0);
  @CompositeBuffer               := Pointer($4B8DA0);
  @CompositeBuf2_OFFSCREEN       := Pointer($004B8A80);
  @DeselectAllUnits              := Pointer($0048BD00);
  @UpdateIngameGUI               := Pointer($00491D70);
  @ApplySelectUnitMenu           := Pointer($00495860);

  @ShowReminderMsg               := Pointer($0046BC70);
  @ShowChatMessage               := Pointer($00463E50);
  @NewChatText                   := Pointer($00463CA0);
  @ClearChat                     := Pointer($00463C80);

  @LoadMap                       := Pointer($00435A20);
  @sub_435D30                    := Pointer($00435D30);
  @CalculateOTACRC               := Pointer($004373A0);
  @UpdateViewMap                 := Pointer($00444A20);
  @GetPosHeight                  := Pointer($00485070);
  @UnitInPlayerLOS               := Pointer($00465AC0);
  @PositionInPlayerMapped        := Pointer($00408090);
  @LoadMap_AverageHeightMap      := Pointer($483370);
  @LoadMap_PLOT3                 := Pointer($4833B0);
  @GetUnitAtMouse                := Pointer($0048CD80);
  @IsPositionInRect              := Pointer($004B6720);
  @Position2GridPlotWreck        := Pointer($004815F0);
  @Position2GridPlot             := Pointer($004815A0);
  @GetTPosition                  := Pointer($00484B50);
  @GetGridPosPLOT                := Pointer($00481550);
  @GetFeatureTypeFromOrder       := Pointer($00421DA0);
  @GetGridPosFeature             := Pointer($00421E60);
  @FeatureName2ID                := Pointer($00422DD0);
  @FeatureNameNotListed2ID       := Pointer($00422E40);
  @LoadFeature                   := Pointer($004224B0);
  @ReleaseFeature_TdfVector      := Pointer($4223E0);
  @SpawnFeatureOnMap             := Pointer($00423C50);
  @FEATURES_Destroy_3D           := Pointer($00423550);
  @FEATURES_Destroy              := Pointer($004246B0);
  @FEATURES_StartBurn            := Pointer($004233A0);
  @FEATURES_TakeWeaponDamage     := Pointer($004244B0);

  @WEAPONS_Name2Ptr              := Pointer($0049E5B0);
  @PROJECTILES_FireMapWeap       := Pointer($49DF10);
  @WEAPONS_ProjectileDamage      := Pointer($00499EB0);
  @fire_callback1                := Pointer($0049DB70);
  @fire_callback2                := Pointer($0049DD60);
  @fire_callback3                := Pointer($0049D9C0);
  @fire_callback0                := Pointer($0049D580);
  @UNITS_FireProjectile_0_3      := Pointer($0049C9C0);
  @UNITS_FireProjectile_1        := Pointer($0049CC20);
  @UNITS_FireProjectile_0        := Pointer($0049CDE0);
  @InitProjectile                := Pointer($0049C740);

  @GetPrepareOrderName           := Pointer($0049FED0);
  @ScriptAction_Name2Index       := Pointer($00438760);
  @ScriptAction_Index2Handler    := Pointer($00438830);
  @ScriptAction_Type2Index       := Pointer($0043F0E0);
  @MOUSE_EVENT_2UnitOrder        := Pointer($0048CF30);
  @Order2Unit                    := Pointer($0043AFC0);
  @SubOrder2Unit                 := Pointer($0043ADC0);
  @ORDERS_NewSubBuildOrder       := Pointer($0043B0B0);
  @UnitSubBuildClick             := Pointer($00419B00);
  @ORDERS_RemoveAllBuildQueues   := Pointer($00439EB0);
  @GetUnitFirstOrderTargat       := Pointer($439DD0);
  @ORDERS_CreateObject           := Pointer($0043A0C0);
  @ORDERS_QueueOrder             := Pointer($0043AC60);
  @ORDERS_CancelOrder            := Pointer($0043A1F0);
  @ORDERS_MovementRelated        := Pointer($00438930);
  @ORDERS_ChaseUnitToBeRepaired  := Pointer($0043B400);
  @ORDERS_DelayCallback          := Pointer($00439E80);
  @ORDERS_RecoverMainOrder       := Pointer($0043A020);
  @ORDERS_BackupMainOrder        := Pointer($004388D0);
  @ORDERS_PushOrder              := Pointer($0043ACB0);

  @UNITS_Create                  := Pointer($00485F50);
  @UNITS_CreateModelScripts      := Pointer($00485D40);
  @UNITS_CreateMoveClass         := Pointer($00485E50);
  @UNITS_FixYPos                 := Pointer($0048A870);
  @UNITS_FixYPosOtherType        := Pointer($0048A490);
  @UNITS_NewUnitPosition         := Pointer($0048A9F0);
  @UNITS_SetMetalExtractionRatio := Pointer($00437840);
  @UNITS_StartWeaponsScripts     := Pointer($0049E070);
  @UNITS_QueryWeaponPosition     := Pointer($0043E240);
  @UNITS_CallAimScripts          := Pointer($0043E2E0);
  @UNITS_AllocateUnit            := Pointer($00485A40);
  @UNITS_AllocateMovementClass   := Pointer($00485E50);
  @UNITS_RebuildLOS              := Pointer($00482AC0);
  @UNITS_RebuildFootPrint        := Pointer($0047CC30);
  @UNITS_GiveUnit                := Pointer($00488570);
  @UNITS_KillUnit                := Pointer($004864B0);
  @UNITS_MakeDamage              := Pointer($00489BB0);
  @UNITS_HealUnit                := Pointer($0041BD10);
  @UNITS_SetHotKeyGroup          := Pointer($00480250);
  @UnitStateProbe                := Pointer($00467E50);
  @UnitBuilderProbe              := Pointer($004685A0);
  @Send_UnitBuildFinished        := Pointer($004560C0);
  @Send_UnitDeath                := Pointer($004864B0);
  @FreeUnitOrders                := Pointer($00489740);
  @AutoAim                       := Pointer($0049E1A0);
  @CallbackForUnitsInDistance    := Pointer($0047E890);
  @SearchForReclamateFeatures    := Pointer($0047EA40);

 // @HAPINET_guaranteepackets      := Pointer($004C9790);
  @HAPI_BroadcastMessage         := Pointer($00451DF0);
  @HAPI_SendMessage              := Pointer($00451BC0);
  //@DirectID2PlayerAry            := Pointer($44FE40);
  @GetLocalPlayerDPID            := Pointer($0044FDB0);
  @GetSharedPlayerDPID           := Pointer($00450030);
  @IsLocalPlayerHost             := Pointer($00457A50);
  //@UpdateGameInfo                := Pointer($00451180);
  //@Send_PacketPlayerInfo         := Pointer($00450F90);

  @REPORTER_PlayerInfo           := Pointer($00450F90);

  @COBEngine_LoadScriptFromFile  := Pointer($004B2450);
  @COBEngine_StartScript         := Pointer($004B0A70);
  @COBEngine_QueryScript         := Pointer($004B0BC0);
  @COBEngine_DoScriptsNow        := Pointer($004B0D60);

  @DrawGameScreen                := Pointer($00468CF0);
  @DrawHealthBars                := Pointer($0046A430);
  @DrawUnit                      := Pointer($0045AC20);
  @DrawUnitSelectBoxRect         := Pointer($0046A530);
  @DrawBar                       := Pointer($004BF6F0);
  @DrawTranspRectangle           := Pointer($004BF8C0);
  @DrawPoint                     := Pointer($004BEE60);
  @DrawUnk1                      := Pointer($004BFD60);
  @DrawLine                      := Pointer($004BE950);
  @DrawLight                     := Pointer($004BEC70);
  @DrawAlpha                     := Pointer($004BED70);
  @DrawLine2                     := Pointer($004CC7AB);
  @DrawCircle                    := Pointer($004C0070);
  @DrawDotteCircle               := Pointer($004C01A0);
  @DrawRangeCircle               := Pointer($00438EA0);
  @DrawProgressBar               := Pointer($00468310);
  @DrawTransparentBox            := Pointer($004BF4D0);
  @DrawTextCustomFont            := Pointer($004C14F0);
  @DrawText                      := Pointer($004A50E0);
  @DrawText_Thin                 := Pointer($004A51D0);
  @SetFONTLENGTH_ptr             := Pointer($004C1420);
  @GAF_Name2Sequence             := Pointer($004B8D40);
  @GAF_SequenceIndex2Frame       := Pointer($004B7F30);
  @GAF_OpenAnimsFile             := Pointer($00429700);
  @GAF_DrawTransformed           := Pointer($004C7580);
  @ShowExplodeGaf                := Pointer($00420A30);
  @sub_4B8B30                    := Pointer($4B8B30);
  @EmitSfx_SmokeInfinite         := Pointer($00472C50);
  @EmitSfx_BlackSmoke            := Pointer($004728F0);
  @EmitSfx_GraySmoke             := Pointer($00472810);
  @EmitSfx_NanoParticles         := Pointer($004720D0);
  @EmitSfx_NanoParticlesReverse  := Pointer($00472200);
  @EmitSfx_Teleport              := Pointer($00471FD0);
  @EmitSfx_Bubbles               := Pointer($00472530);
  @EmitSfx_Unk5                  := Pointer($00472AB0);

  @PlaySound_UnitSpeech          := Pointer($0047F780);
  @PlaySound_2D_Name             := Pointer($0047F1A0);
  @PlaySound_2D_ID               := Pointer($0047F0C0);
  @PlaySound_3D_Name             := Pointer($0047F610);
  @PlaySound_3D_ID               := Pointer($0047F300);

  @GUIGADGET_GetStatus           := Pointer($004A0F60);
  @GUIGADGET_SetStatus           := Pointer($004A1080);
  @GUIGADGET_GetActive           := Pointer($004A04F0);
  @GUIGADGET_SetActive           := Pointer($004A0570);
  @GUIGADGET_SetText             := Pointer($004A0BF0);
  @GUIGADGET_SetGrayedOut        := Pointer($004A1450);
  @GUIGADGET_WasPressed          := Pointer($0049FD60);
  @GUICONTROL_IsOnTop            := Pointer($004AB060);
  @GetStrExtent                  := Pointer($004A5030);
  @GetCustomFontCharWidth        := Pointer($004C1450);
  @GetCustomFontStrExtent        := Pointer($004C1480);

  @REGISTRY_ReadInteger          := Pointer($004B69D0);
  @REGISTRY_WriteInteger         := Pointer($004B6A50);
  @REGISTRY_SaveSettings         := Pointer($00430F00);

  @MEM_Alloc                     := Pointer($004B4F10);
  @MEM_ReAlloc                   := Pointer($004D8580);
  @MEM_Free                      := Pointer($004D85A0);
  @MEM_Free_Pointer              := Pointer($004D8670);
  @MEM_Free_PPointer             := Pointer($004B4F20);
  @MEM_AllowReadWrite            := Pointer($004D8780);
  @MEM_SetReadOnly               := Pointer($004D8710);

  @HAPIFILE_GetFileLength        := Pointer($004BBC40);
  @HAPIFILE_FindFirst            := Pointer($004BC4B0);
  @HAPIFILE_FindNext             := Pointer($004BC640);
  @HAPIFILE_FindClose            := Pointer($004BC8D0);
  @HAPIFILE_ReadFile             := Pointer($004BBE50);
  @GetLocalizedFilePath          := Pointer($004290F0);
  @Open3DOFile                   := Pointer($004CB560);
  @Parse3DOFile                  := Pointer($004CB590);
  @TextureMatch3DO               := Pointer($0042A140);
  @HAPIFILE_InsertToArray        := Pointer($004BE0B0);
  @HAPIBANK_OpenAccount          := Pointer($004B4560);
  @HAPIBANK_WriteInteger         := Pointer($004B4630);
  @HAPIBANK_ReadInteger          := Pointer($004B4800);
  @HAPIBANK_WriteString          := Pointer($004B4750);
  @HAPIBANK_WriteBinData         := Pointer($004B4CF0);
  @HAPIBANK_ReadBinData          := Pointer($004B4C80);
  @HAPIBANK_GetItemSize          := Pointer($004B4BF0);
  @HAPIBANK_AccessSafeDeposit    := Pointer($004B4BA0);
  @HAPIBANK_SeekInHex            := Pointer($004B4C10);
  @TdfFile_SectionExists         := Pointer($004C3410);
  @TdfFile_GetInt                := Pointer($004C46C0);
  @TdfFile_GetStr                := Pointer($004C48C0);
  @TdfFile_GetFloat              := Pointer($004C4760);
  @TdfFile_GetRoot               := Pointer($004C3E20);
  @TdfFile_SetRoot               := Pointer($004C3E30);
  @SetCurrentDirectoryToTAPath   := Pointer($0049F540);

  @InitPlayerStruct              := Pointer($00464700);

end.
