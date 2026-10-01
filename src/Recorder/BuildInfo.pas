unit BuildInfo;

{$MODE DELPHI}

interface

const
  TA16P_VERSION  = '2026.09.30';
  TA16P_CREDIT   = 'Modded by BLITZ CLAN - TA 16P NETQ build ' + TA16P_VERSION;
  TA16P_SHORT    = 'Modded by BLITZ CLAN';
  // unique per compile: two players only match if they run the same DLL build
  TA16P_BUILD_ID = 'TA16P ' + TA16P_VERSION + ' ' + {$I %DATE%} + ' ' + {$I %TIME%};

  // Rec2Rec sub-type for the build id (unused by TA Demo; older recorders ignore it)
  TANM_Rec2Rec_BuildId = $30;

implementation

end.
