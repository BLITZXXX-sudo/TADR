unit TA_NetworkingMessages;

interface
uses
  Dplay, TA_MemoryStructures, TA_MemoryLocations;

const
  TANM_SimulationSpeedChange = $19;
  SpeedChange = $01;
  PauseChange = $00;
type
  PSimulationSpeedChangeMessage = ^TSimulationSpeedChangeMessage;
  TSimulationSpeedChangeMessage = packed record
    Marker  : byte;
    case SimSpeedChangeType : Byte of
      PauseChange : ( PauseState  : Byte );
      SpeedChange : ( NewSimSpeed : Byte );
  end;

Const
  TANM_Rejection = $1B;

  PlayerDidProperlyClose = $01;
  PlayerDidnotProperlyClose = $06;
type
  PRejectionMessage = ^TRejectionMessage;
  TRejectionMessage = packed record
    Marker  : byte;
    DPlayPlayerID : TDPID;
    Reason : byte;
  end;

const
  TANM_Ally = $23;
type
  PAllyMessage = ^TAllyMessage;
  TAllyMessage = packed record
    Marker     : byte;
    PlayerID_1 : TDPID;
    PlayerID_2 : TDPID;
    Allied     : Byte;
    Unknown    : Longword;
  end;

const
  TANM_Team = $24;
type
  PTeamMessage = ^TTeamMessage;
  TTeamMessage = packed record
    Marker     : Byte;
    PlayerDPID : TDPID;
    TeamId     : Byte;
  end;

const
  TANM_Ping = $02;
type
  PPingMessage = ^TPingMessage;
  TPingMessage = packed record
    Marker     : byte;
    Unknown1   : longword;
    Unknown2   : Longword;
    Unknown3   : Longword;
  end;

Const
  TANM_UnitStatAndMove = $2C;
type
  PUnitStatAndMoveMessage = ^TUnitStatAndMoveMessage;
  TUnitStatAndMoveMessage = packed record
    Marker   : Byte;
    Size     : Word;
    Timstamp : Longword;
  end;

Const
  TANM_ChatMessage = $05;
  TANM_LoadingStarted = $08;
  TANM_UnitBuildStarted = $09;
  TANM_UnitTakeDamage = $0B;
  TANM_UnitKilled = $0C;
  TANM_UnitStartScript = $10;
  TANM_UnitState = $11;
  TANM_UnitBuildFinished = $12;
  TANM_PlaySound = $13;
  TANM_GiveUnit = $14;

  TANM_ShareResources = $16;
  TANM_PlayerResourcesInfo = $28;

  TANM_UnitTypesSync = $1A;

  TANM_HostMigration = $18;
  TANM_PlayerInfo = $20;

Const
  TANM_WeaponFired = $0D;
type
  PWeaponFiredMessage = ^TWeaponFiredMessage;
  TWeaponFiredMessage = packed record
    Marker          : Byte;
    Position_Start  : TPosition;
    Position_Target : TPosition;
    WeaponID        : Byte;
    Interceptor     : Byte;
    Angle           : Word;
    Trajectory      : Word;
    TargetUnitId    : Word;
    AttackerUnitId  : Word;
    WeapIdx         : Byte;
  end;

  PWeaponFiredMessagePatched = ^TWeaponFiredMessagePatched;
  TWeaponFiredMessagePatched = packed record
    Marker          : Byte;
    Position_Start  : TPosition;
    Position_Target : TPosition;
    WeaponID        : Cardinal;
    Interceptor     : Byte;
    Angle           : Word;
    Trajectory      : Word;
    TargetUnitId    : Word;
    AttackerUnitId  : Word;
    WeapIdx         : Byte;
  end;

Const
  TANM_AreaOfEffect = $0E;
type
  PAreaOfEffectMessage = ^TAreaOfEffectMessage;
  TAreaOfEffectMessage = packed record
    Marker     : Byte;
    Position   : TPosition;
    WeaponID   : Byte;
  end;

  PAreaOfEffectMessagePatched = ^TAreaOfEffectMessagePatched;
  TAreaOfEffectMessagePatched = packed record
    Marker     : Byte;
    Position   : TPosition;
    WeaponID   : Cardinal;
  end;

Const
  TANM_FeatureAction = $0F;
type
  PFeatureActionMessage = ^TFeatureActionMessage;
  TFeatureActionMessage = packed record
    Marker     : Byte;
    WeaponID   : Byte;
    X          : Word;
    Y          : Word;
  end;

  PFeatureActionMessagePatched = ^TFeatureActionMessagePatched;
  TFeatureActionMessagePatched = packed record
    Marker     : Byte;
    WeaponID   : Cardinal;
    X          : Word;
    Y          : Word;
  end;

const
  TANM_EnemyChat = $F9;
type

  PEnemyChatMessage = ^TEnemyChatMessage;
  TEnemyChatMessage = packed record
    Marker     : Byte;
    FromPlayer : TDPID;
    ToPlayer   : TDPID;
    Text       : array [0..64-1] of char;
  end;

const
  TANM_ReplayerServer = $FA;
type
  PReplayerServerMessage = ^TReplayerServerMessage;
  TReplayerServerMessage = packed record
    Marker  : Byte;
  end;

const
  TANM_RecorderToRecorder = $FB;
type
  PRecorderToRecorderMessage = ^TRecorderToRecorderMessage;
  TRecorderToRecorderMessage = packed record
    Marker     : Byte;
    MsgSize    : Byte;
    MsgSubType : Byte;
  end;

const

  TANM_Rec2Rec_MarkerData = $0;
type
  PRec2Rec_MarkerData_Message = ^TRec2Rec_MarkerData_Message;
  TRec2Rec_MarkerData_Message = packed record
    PacketCount : Byte;

  end;

const

  TANM_Rec2Rec_CmdWarp = $1;

const
  TANM_Rec2Rec_CheatDetection = $2;
type
  PRec2Rec_CheatsDetected_Message = ^TRec2Rec_CheatsDetected_Message;
  TRec2Rec_CheatsDetected_Message = packed record
    CheatsDetected : Cardinal;
  end;

const
  TANM_Rec2Rec_Sharelos = $3;
type
  PRec2Rec_Sharelos_Message = ^TRec2Rec_Sharelos_Message;
  TRec2Rec_Sharelos_Message = packed record
    ShareLosState : byte;
  end;

const
  TANM_Rec2Rec_GameStateInfo = $4;
type
  PRec2Rec_GameStateInfo_Message = ^TRec2Rec_GameStateInfo_Message;
  TRec2Rec_GameStateInfo_Message = packed record
    AutopauseState : Byte;
    F1Disable      : Byte;
    Commanderwarp  : Byte;
    SpeedLock      : Byte;
    SpeedLockNative: Byte;
    SlowSpeed      : Byte;
    FastSpeed      : Byte;
    AIDifficulty   : Byte;
  end;

const
  TANM_Rec2Rec_ModInfo = $5;
type
  PRec2Rec_ModInfo_Message = ^TRec2Rec_ModInfo_Message;
  TRec2Rec_ModInfo_Message = packed record
    PlayerID       : TDPID;
    ModID          : Integer;
    ModMajorVer    : AnsiChar;
    ModMinorVer    : AnsiChar;
  end;

const
  TANM_Rec2Rec_UnitGrantUnitInfo = $0A;
type
  PRec2Rec_UnitGrantUnitInfo_Message = ^TRec2Rec_UnitGrantUnitInfo_Message;
  TRec2Rec_UnitGrantUnitInfo_Message = packed record
    UnitId        : Word;
    NewState      : Byte;
  end;

const
  TANM_Rec2Rec_UnitWeapon = $0B;
type
  PRec2Rec_UnitWeapon_Message = ^TRec2Rec_UnitWeapon_Message;
  TRec2Rec_UnitWeapon_Message = packed record
    UnitId        : Word;
    WeaponIdx     : Byte;
    NewWeaponID   : Cardinal;
  end;

const
  TANM_Rec2Rec_UnitInfoEdit = $0C;
type
  PRec2Rec_UnitInfoEdit_Message = ^TRec2Rec_UnitInfoEdit_Message;
  TRec2Rec_UnitInfoEdit_Message = packed record
    UnitId        : Word;
    FieldType     : Cardinal;
    NewValue      : Integer;
  end;

const
  TANM_Rec2Rec_UnitInfoSwap = $0D;
type
  PRec2Rec_UnitInfoSwap_Message = ^TRec2Rec_UnitInfoSwap_Message;
  TRec2Rec_UnitInfoSwap_Message = packed record
    UnitID         : Word;
    UnitInfoCRC    : Integer;
  end;

const
  TANM_Rec2Rec_NewUnitLocation = $0E;
type
  PRec2Rec_NewUnitLocation_Message = ^TRec2Rec_NewUnitLocation_Message;
  TRec2Rec_NewUnitLocation_Message = packed record
    UnitID         : Word;
    NewX           : Integer;
    NewY           : Integer;
    NewZ           : Integer;
  end;

const
  TANM_Rec2Rec_EmitSFXToUnit = $0F;
type
  PRec2Rec_EmitSFXToUnit_Message = ^TRec2Rec_EmitSFXToUnit_Message;
  TRec2Rec_EmitSFXToUnit_Message = packed record
    FromUnitID     : Word;
    ToUnitID       : Word;
    FromPieceIdx   : SmallInt;
    SfxType        : Byte;
  end;

const
  TANM_Rec2Rec_SetNanolatheParticles = $10;
type
  PRec2Rec_SetNanolatheParticles_Message = ^TRec2Rec_SetNanolatheParticles_Message;
  TRec2Rec_SetNanolatheParticles_Message = packed record
    PosFrom        : TPosition;
    PosTo          : TNanolathePos;
    Reverse        : Byte;
  end;

const
  TANM_Rec2Rec_ExtraUnitState = $11;
type
  PRec2Rec_ExtraUnitState_Message = ^TRec2Rec_ExtraUnitState_Message;
  TRec2Rec_ExtraUnitState_Message = packed record
    UnitId        : Word;
    FieldType     : Cardinal;
    NewValue      : Integer;
  end;

const
  TANM_Rec2Rec_VoteStart = $14;
type
  PRec2Rec_VoteStart_Message = ^TRec2Rec_VoteStart_Message;
  TRec2Rec_VoteStart_Message = packed record
    VoteType       : byte;
    VoteExpireTime : Word;
    VoteString     : string[64];

  end;

const
  TANM_Rec2Rec_VoteAnswer = $15;
type
  PRec2Rec_VoteAnswer_Message = ^TRec2Rec_VoteAnswer_Message;
  TRec2Rec_VoteAnswer_Message = packed record
    Answer       : byte;
  end;

const
  TANM_Rec2Rec_VoteStatus = $16;
type
  PRec2Rec_VoteStatus_Message = ^TRec2Rec_VoteStatus_Message;
  TRec2Rec_VoteStatus_Message = packed record
    YesCount       : byte;
    NoCount        : byte;
  end;

const
  TANM_Rec2Rec_VoteEnd = $17;
type
  PRec2Rec_VoteEnd_Message = ^TRec2Rec_VoteEnd_Message;
  TRec2Rec_VoteEnd_Message = packed record
    VoteResult       : byte;
  end;

const
  TANM_ShareMapPos = $FC;

type
  PShareMapPosMessage = ^TShareMapPosMessage;
  TShareMapPosMessage = packed record
    Marker  : byte;
    MapX : Word;
    MapY : Word;
  end;

implementation

end.
