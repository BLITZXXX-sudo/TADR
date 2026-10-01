unit GUIEnhancements;

interface
uses
  PluginEngine, TA_MemoryStructures, Classes, SysUtils;

// -----------------------------------------------------------------------------

const
  State_GUIEnhancements : boolean = true;

function GetPlugin : TPluginData;

// -----------------------------------------------------------------------------

// Shared append-mode diagnostic logger (writes to tplayx_diag.log next to
// TotalA.exe). Exposed here so other units (UnitActions, UnitSearchHandlers,
// COB_extensions, ...) can log into the same file without each needing their
// own file-handling boilerplate. LogDiag always writes; LogDiagOnce only
// writes the first time IT SPECIFICALLY is called with a given AOnceFlag var
// (pass a unit-local Boolean by reference) - callers must use their OWN flag
// per distinct message, since a single shared flag would let whichever
// message fires first silently suppress every other one forever.
procedure LogDiag(const Msg: string);
procedure LogDiagOnce(var AOnceFlag: Boolean; const Msg: string); overload;

var
  ForceBottomStateRefresh: Integer;
  FormatSettings: TFormatSettings;
  // Set true after the first out-of-range UnitsCustomFields/UnitInfoCustomFields
  // index is logged anywhere in this unit, so a persistently out-of-range unit
  // being redrawn every frame doesn't flood tplayx_diag.log.
  DiagLoggedOnce: Boolean = False;
  // Diagnostic (2026-07-22): ARMARAD shield-radius-circle investigation.
  DiagLoggedRangeHookSeen: Boolean = False;
  DiagLoggedRangeCircleDrawn: Boolean = False;
  // Diagnostic (2026-07-22 round 3): per-nCategory one-shot, so we find out
  // whether DrawUnitRangesShowrangesOff EVER runs for ARMARAD's own
  // nCategory (18) specifically, instead of only ever capturing whichever
  // unit happens to be selected first in a play session.
  DiagSeenRangeCategory: array[0..500] of Boolean;
  // Diagnostic (2026-07-22 round 4): DrawUnitState-driven radius circle,
  // since DrawUnitRangesShowrangesOff is confirmed to never fire for
  // NOWEAPON units (ARMARAD). See DrawUnitState for the actual draw call.
  DiagLoggedRadiusCircleDrawn: Boolean = False;
  // Diagnostic (2026-07-22 round 8): dump the raw palette bytes the game's
  // OWN code uses for its known-good/known-bad health colors, so we can
  // pick a real, confirmed "green" (or whatever) byte for the shield circle
  // instead of guessing blind at TA's 256-color palette layout, which isn't
  // otherwise readable from outside the running process.
  DiagLoggedColorsPalDump: Boolean = False;

implementation
uses
  Windows,
  IniOptions,
  TA_MemoryConstants,
  TA_MemoryLocations,
  TA_MemPlayers,
  TA_MemUnits,
  ExtensionsMem,
  UnitInfoExpand,
  Math,
  TA_FunctionsU,
  logging,
  BuildInfo,
  Colors;

// ---- Bounds-check diagnostic log --------------------------------------------
// DrawUnitSelectBox indexes UnitInfoCustomFields[nUnitInfoID] and
// UnitsCustomFields[UnitID] every frame for every selected unit, with no
// bounds check (unlike other call sites in this codebase - see
// UnitInfoExpand.FreeCustomUnitInfo and GetUnitInfoProperty, which both guard
// their array access). An out-of-range index here used to be a raw
// Access-Violation crash during normal play (Main Thread, inside tplayx.dll).
// Self-contained append-mode log, same pattern as Plugins.pas's Log() -
// doesn't depend on TLog being initialized elsewhere.
// AUDIT 28 Sep: raw writer. Used directly only by the rate-limited
// LogDiagOnce (error paths); LogDiag below is debug-build only.
procedure WriteDiagLine(const Msg: string);
var
  DiagLogFile: TextFile;
  DiagLogPath: string;
begin
  try
    DiagLogPath := ExtractFilePath(ParamStr(0)) + 'tplayx_diag.log';
    AssignFile(DiagLogFile, DiagLogPath);
    {$I-}
    if FileExists(DiagLogPath) then
      Append(DiagLogFile)
    else
      Rewrite(DiagLogFile);
    {$I+}
    if IOResult <> 0 then Exit;
    Writeln(DiagLogFile, FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + '  ' + Msg);
    CloseFile(DiagLogFile);
  except end;
end;

// Verbose diagnostic line - compiled out unless -dTPLAYX_DEBUG.
procedure LogDiag(const Msg: string);
begin
  {$IFDEF TPLAYX_DEBUG}
  WriteDiagLine(Msg);
  {$ENDIF}
end;

// Same as LogDiag, but only writes the first time it's called across this
// whole unit for the current process. Use this at any per-frame draw call
// site so a persistently out-of-range unit doesn't spam tplayx_diag.log.
procedure LogDiagOnce(const Msg: string); overload;
begin
  if DiagLoggedOnce then Exit;
  DiagLoggedOnce := True;
  WriteDiagLine(Msg + ' (further occurrences this session will not be logged)');
end;

// Public overload for other units: caller supplies its OWN Boolean flag
// (by reference) instead of sharing this unit's DiagLoggedOnce, so several
// distinct diagnostic messages from different units/call sites don't
// compete for a single "already logged" flag and suppress each other.
procedure LogDiagOnce(var AOnceFlag: Boolean; const Msg: string); overload;
begin
  if AOnceFlag then Exit;
  AOnceFlag := True;
  WriteDiagLine(Msg + ' (further occurrences this session will not be logged)');
end;
// -----------------------------------------------------------------------------

const
  STANDARDUNIT : cardinal = 250;
  MEDIUMUNIT : cardinal = 1900;
  BIGUNIT : cardinal = 3000;
  HUGEUNIT : cardinal = 5000;
  EXTRALARGEUNIT : cardinal = 10000;
  VETERANLEVEL_RELOADBOOST = 12; // 30 * 0.2
  SCOREBOARD_WIDTH = 180;
  // Empirical elmos-to-screen-pixels scale for the shield radius circle drawn
  // in DrawUnitState (see below). The native DrawRangeCircle call needs a
  // "CirclePointer" viewport struct that's read from a global
  // (*(TAdynmemStructPtr)+0x391BF) which is confirmed via diagnostics to
  // always be 0 outside the vanilla show-ranges UI pass - so instead we use
  // DrawCircle, which draws directly in screen pixels using CenterPosX/
  // CenterPosZ (already provided to this hook) with no viewport pointer at
  // all. The tradeoff: DrawCircle can't account for camera zoom the way the
  // native per-point projection would, so this is an approximation, not a
  // pixel-exact conversion.
  // Round 6: the original 0.0625 guess rendered a ~16px radius that was
  // barely visible next to the CustAnim2 GAF ring (which visually looked
  // roughly 150-175px radius on screen in a shared screenshot, for what was
  // presumably ARMARAD's original/default ShieldRange of ~180 elmos before
  // it got bumped up during testing) - implying something close to 1 pixel
  // per elmo, not 1/16th. Re-estimated to 1.0 as a much closer starting
  // point. Still an approximation, not measured pixel-exact - if the circle
  // looks too big/small in game, this is the one constant to adjust.
  SHIELD_RADIUS_ELMOS_TO_PIXELS = 1.0;

procedure DrawUnitState(p_Offscreen: Pointer;
  Unit_p: PUnitStruct; CenterPosX: Integer; CenterPosZ: Integer); stdcall;
var
  { drawing }
  ColorsPal: Pointer;
  FontBackgroundColor: Integer;
  RectDrawPos: tagRect;

  LocalUnit: Boolean;

  { health bar }
  HPBackgRectWidth, HPFillRectWidth: Smallint;
  UnitHealth, HealthState : Word;
  UnitMaxHP : Cardinal;

  UnitId: Word;
  UnitInfo : PUnitInfo;
  UnitBuildTimeLeft : Single;
  //UnitPos : TPosition;

  { custom radius circle (shield range etc.) - drawn via DrawCircle using
    CenterPosX/CenterPosZ directly, since DrawUnitRangesShowrangesOff never
    fires for NOWEAPON units and the native DrawRangeCircle's CirclePointer
    is confirmed unavailable here - see round-5 comment below }
  ShieldCirclePixelRadius : Integer;
  ResurrectCirclePixelRadius : Integer;

  { hotkey group }
  BottomZ : Word;
  sGroup : PAnsiChar;
  AllowHotkeyDraw : Boolean;
  
  { weapons }
  MaxReloadTime : Integer;
  CurReloadTime : Integer;
  BarProgress : Cardinal;
  StockPile : Byte;
  WeapReloadColor : Byte;
  CustomReloadBar : Boolean;

  { transporters }
  TransportCount : Integer;
  TransportCap : Integer;
  WeightTransportCur : Integer;
  WeightTransportMax : Integer;
  WeightTransportPercent : Integer;

  { reclaim, resurrect feature }
  CurOrder : TTAActionType;
  OrderStateCorrect : Boolean;
  p_FeatureDef : PFeatureDefStruct;
  FeatureDefID : Word;
  ActionUnitType : Word;
  ActionUnit : PUnitStruct;
  ActionUnitBuildTime : Cardinal;
  ActionUnitBuildCost1, ActionUnitBuildCost2 : Single;
  ActionTime : Double;
  ActionWorkTime : Word;
  MaxActionVal : Integer;
  CurActionVal : Integer;
  ReclaimColor : Byte;
begin
  BottomZ := 0;
  try
  // is drawing health bars enabled and any of local player units are actually on screen
  if ((TAData.MainStruct.GameOptionMask and 1) = 1) or
     (Unit_p.HotKeyGroup <> 0) then
  begin
    UnitInfo := Unit_p.p_UnitInfo;
    UnitId := TAUnit.GetId(Unit_p);
    ColorsPal := TAData.ColorsPalette;

    // Diagnostic (2026-07-22 round 8): ColorsPal[N] (MainStruct+$DCB+N) is
    // the same byte table used a few lines below via
    // GetRaceSpecificColor(23/24/25) -> ColorsPal[10/14/12] for the health
    // bar's green/yellow/red - i.e. ColorsPal[10] IS the actual raw palette
    // byte the game itself uses to draw "healthy = green", already proven
    // semantically correct by the existing health bar code. Dumping it here
    // once gives us a real, confirmed byte value to plug into
    // customrange1color for a green shield circle, instead of guessing at
    // TA's palette layout from outside the process (which isn't otherwise
    // readable - no palette file was found loose on disk, and there is no
    // debug-accessible RGB table, only this byte-remap array).
    if not DiagLoggedColorsPalDump then
    begin
      DiagLoggedColorsPalDump := True;  // AUDIT: was False -> logged EVERY FRAME (7 MB log, file open/close per frame)
      LogDiag(Format('ColorsPal dump: [10(HPgood/green)]=%d [12(HPlow/red)]=%d [14(HPmed/yellow)]=%d [16]=%d [17]=%d [18]=%d [26(reload)]=%d [27(reclaim)]=%d [28(stockpile)]=%d',
        [PByte(LongWord(ColorsPal)+10)^, PByte(LongWord(ColorsPal)+12)^, PByte(LongWord(ColorsPal)+14)^,
         PByte(LongWord(ColorsPal)+16)^, PByte(LongWord(ColorsPal)+17)^, PByte(LongWord(ColorsPal)+18)^,
         PByte(LongWord(ColorsPal)+26)^, PByte(LongWord(ColorsPal)+27)^, PByte(LongWord(ColorsPal)+28)^]));
    end;

    if ((TAData.MainStruct.GameOptionMask and 1) = 1) and
       (CenterPosX <> 0) and
       (CenterPosZ <> 0) and
       (UnitInfo <> nil) then
    begin

      LocalUnit := (PPlayerStruct(Unit_p.p_Owner).cPlayerIndex = TAData.LocalPlayerID);
//      DrawTransparentBox(p_Offscreen, @Rect, -24);
      if LocalUnit then
      begin
        UnitHealth := Unit_p.nHealth;
        UnitBuildTimeLeft := Unit_p.fBuildTimeLeft;

        if (UnitHealth > 0) then
        begin
          UnitMaxHP := UnitInfo.lMaxDamage;
          HPBackgRectWidth := 34;
          if IniSettings.HealthBarDynamicSize then
          begin
            if UnitMaxHP < STANDARDUNIT then
              HPBackgRectWidth := 28
            else
              if (UnitMaxHP >= STANDARDUNIT) and (UnitMaxHP < MEDIUMUNIT) then
                HPBackgRectWidth := 34
              else
                if (UnitMaxHP >= MEDIUMUNIT) and (UnitMaxHP < BIGUNIT) then
                  HPBackgRectWidth := 40
                else
                  if (UnitMaxHP >= BIGUNIT) and (UnitMaxHP < HUGEUNIT) then
                    HPBackgRectWidth := 46
                  else
                    if (UnitMaxHP >= HUGEUNIT) and (UnitMaxHP < EXTRALARGEUNIT) then
                      HPBackgRectWidth := 52
                    else
                      if UnitMaxHP >= HUGEUNIT then
                        HPBackgRectWidth := 58;
          end else
          begin
            if (IniSettings.HealthBarWidth <> 0) then
              HPBackgRectWidth := IniSettings.HealthBarWidth
          end;

          if (UnitHealth <= UnitMaxHP) and
             (UnitInfo.nCategory <= High(UnitInfoCustomFields)) and
             not UnitInfoCustomFields[UnitInfo.nCategory].HideHPBar then
          begin
            HPFillRectWidth := (HPBackgRectWidth div 2);

            RectDrawPos.Left := Word(CenterPosX) - HPFillRectWidth;
            RectDrawPos.Right := Word(CenterPosX) + HPFillRectWidth;
            RectDrawPos.Top := Word(CenterPosZ) - 2;
            RectDrawPos.Bottom := Word(CenterPosZ) + 2;

            DrawBar(p_Offscreen, @RectDrawPos, PByte(ColorsPal)^);
            Inc(RectDrawPos.Top);
            Dec(RectDrawPos.Bottom);
            Inc(RectDrawPos.Left);

            RectDrawPos.Right := Round(RectDrawPos.Left + ((HPBackgRectWidth-2) * UnitHealth) / UnitMaxHP);
            HealthState := UnitMaxHP div 3;

            if UnitHealth <= (HealthState * 2) then
            begin
              if UnitHealth <= HealthState then
                DrawBar(p_Offscreen, @RectDrawPos, PByte(LongWord(ColorsPal)+GetRaceSpecificColor(25))^)
              else
                DrawBar(p_Offscreen, @RectDrawPos, PByte(LongWord(ColorsPal)+GetRaceSpecificColor(24))^);
            end else
              DrawBar(p_Offscreen, @RectDrawPos, PByte(LongWord(ColorsPal)+GetRaceSpecificColor(23))^);
          end;

          // shield / custom radius circle (ARMARAD etc.). DrawUnitRangesShowrangesOff
          // (the vanilla "draw unit ranges" hook) is confirmed via diagnostics to
          // never fire for NOWEAPON units, so it's structurally unreachable for
          // ARMARAD - drawn here instead, since DrawUnitState is confirmed to run
          // every frame for ARMARAD regardless of weapon status.
          // Round 5: the native DrawRangeCircle attempt (kept in git history)
          // is out - its CirclePointer parameter is confirmed via diagnostics
          // to always resolve to 0 in this hook's context (the global that
          // caches it is only populated inside the vanilla show-ranges pass).
          // DrawCircle instead draws a plain screen-space circle directly
          // from CenterPosX/CenterPosZ (already provided to this hook) and a
          // pixel radius we compute ourselves - no viewport pointer needed.
          // Round 6: switched the radius source from CustomRange1Distance to
          // ShieldRange. Those are two SEPARATE FBI tags (customrange1dist
          // vs ShieldRange) - CustomRange1Distance is a cosmetic-only value
          // used elsewhere for a different purpose, while ShieldRange is the
          // one actually fed into CallbackForUnitsInDistance in
          // ExtraDataReload (UnitActions.pas) that determines real shield
          // protection. Confirmed via diagnostics that a live test had these
          // set to two different values (250 vs 400) - the circle was
          // drawing the wrong number entirely, not just at the wrong scale.
          // This also naturally stops the circle showing on unrelated unit
          // types (e.g. a radar tower) that have CustomRange1Distance set
          // for their own purposes but ShieldRange=0.
          if (UnitInfo.nCategory <= High(UnitInfoCustomFields)) and
             (UnitInfoCustomFields[UnitInfo.nCategory].ShieldRange <> 0) then
          begin
            ShieldCirclePixelRadius := Round(UnitInfoCustomFields[UnitInfo.nCategory].ShieldRange *
              SHIELD_RADIUS_ELMOS_TO_PIXELS);
            if ShieldCirclePixelRadius > 0 then
            begin
              LogDiagOnce(DiagLoggedRadiusCircleDrawn,
                Format('DrawUnitState: drawing ShieldRange circle via DrawCircle, nCategory=%d shieldRange=%d pixelRadius=%d color=%d centerX=%d centerZ=%d',
                  [UnitInfo.nCategory, UnitInfoCustomFields[UnitInfo.nCategory].ShieldRange,
                   ShieldCirclePixelRadius, UnitInfoCustomFields[UnitInfo.nCategory].CustomRange1Color,
                   CenterPosX, CenterPosZ]));
              DrawCircle(p_Offscreen, CenterPosX, CenterPosZ, ShieldCirclePixelRadius,
                Byte(UnitInfoCustomFields[UnitInfo.nCategory].CustomRange1Color));
            end;
          end;

          // "Portal" auto-resurrect radius circle (2026-07-23): same
          // DrawCircle approach as the ShieldRange circle above, but keyed
          // on the STANDARD engine nBuildDistance field (not a custom FBI
          // tag) for any stationary (p_MovementClass=nil) canresurrect unit,
          // so the circle always matches exactly what
          // Portal_AutoResurrectScan (UnitActions.pas) actually searches -
          // one shared radius value driving both, instead of the previous
          // customrange1dist=128 guess that didn't match real behavior.
          if (UnitInfo.nCategory <= High(UnitInfoCustomFields)) and
             (Unit_p.p_MovementClass = nil) and
             (TAUnit.GetUnitInfoField(Unit_p, uiCanResurrect) <> 0) and
             (UnitInfo.nBuildDistance > 0) then
          begin
            ResurrectCirclePixelRadius := Round(UnitInfo.nBuildDistance *
              SHIELD_RADIUS_ELMOS_TO_PIXELS);
            if ResurrectCirclePixelRadius > 0 then
              DrawCircle(p_Offscreen, CenterPosX, CenterPosZ, ResurrectCirclePixelRadius,
                Byte(UnitInfoCustomFields[UnitInfo.nCategory].CustomRange1Color));
          end;

        // weapons reload
        if ((IniSettings.MinWeaponReload <> 0) or
           ((UnitInfo.nCategory <= High(UnitInfoCustomFields)) and
            UnitInfoCustomFields[UnitInfo.nCategory].UseCustomReloadBar)) and
           (UnitBuildTimeLeft = 0.0) then
        begin
          MaxReloadTime := 0;
          CurReloadTime := 0;
          StockPile := 0;
          CustomReloadBar := False;
          if (UnitInfo.nCategory <= High(UnitInfoCustomFields)) and
             UnitInfoCustomFields[UnitInfo.nCategory].UseCustomReloadBar then
          begin
            if (UnitId <= High(UnitsCustomFields)) and
               (UnitsCustomFields[UnitId].CustomWeapReloadMax > 0) then
            begin
              MaxReloadTime := UnitsCustomFields[UnitId].CustomWeapReloadMax;
              CurReloadTime := UnitsCustomFields[UnitId].CustomWeapReloadCur;
              CustomReloadBar := True;
            end
            else if UnitId > High(UnitsCustomFields) then
              LogDiagOnce(Format('DrawUnitState reload bar: UnitId=%d out of range (High(UnitsCustomFields)=%d)',
                [UnitId, High(UnitsCustomFields)]));
          end else
          begin
            if (Unit_p.UnitWeapons[0].p_Weapon <> nil) or
               (Unit_p.UnitWeapons[1].p_Weapon <> nil) or
               (Unit_p.UnitWeapons[2].p_Weapon <> nil) then
            begin
              if (Unit_p.UnitWeapons[0].p_Weapon <> nil) then
              begin
                if (PWeaponDef(Unit_p.UnitWeapons[0].p_Weapon).lWeaponTypeMask and (1 shl 28) = 1 shl 28) then
                  StockPile := 1;
                if PWeaponDef(Unit_p.UnitWeapons[0].p_Weapon).nReloadTime >= IniSettings.MinWeaponReload * 30 then
                begin
                  MaxReloadTime := PWeaponDef(Unit_p.UnitWeapons[0].p_Weapon).nReloadTime;
                  CurReloadTime := MaxReloadTime - Unit_p.UnitWeapons[0].nReloadTime;
                end;
              end;
              if (Unit_p.UnitWeapons[1].p_Weapon <> nil) then
              begin
                if (PWeaponDef(Unit_p.UnitWeapons[1].p_Weapon).lWeaponTypeMask and (1 shl 28) = 1 shl 28) then
                  StockPile := 2;
                if PWeaponDef(Unit_p.UnitWeapons[1].p_Weapon).nReloadTime >= IniSettings.MinWeaponReload * 30 then
                begin
                  MaxReloadTime := PWeaponDef(Unit_p.UnitWeapons[1].p_Weapon).nReloadTime;
                  CurReloadTime := MaxReloadTime - Unit_p.UnitWeapons[1].nReloadTime;
                end;
              end;
              if (Unit_p.UnitWeapons[2].p_Weapon <> nil) then
              begin
                if (PWeaponDef(Unit_p.UnitWeapons[2].p_Weapon).lWeaponTypeMask and (1 shl 28) = 1 shl 28) then
                  StockPile := 3;
                if PWeaponDef(Unit_p.UnitWeapons[2].p_Weapon).nReloadTime >= IniSettings.MinWeaponReload * 30 then
                begin
                  MaxReloadTime := PWeaponDef(Unit_p.UnitWeapons[2].p_Weapon).nReloadTime;
                  CurReloadTime := MaxReloadTime - Unit_p.UnitWeapons[2].nReloadTime;
                end;
              end;
            end;
          end;

          if (UnitId <= High(UnitsCustomFields)) and
             (UnitsCustomFields[UnitId].TeleportReloadMax > 0) then
          begin
            MaxReloadTime := UnitsCustomFields[UnitId].TeleportReloadMax;
            CurReloadTime := UnitsCustomFields[UnitId].TeleportReloadCur;
            CustomReloadBar := True;
          end
          else if UnitId > High(UnitsCustomFields) then
            LogDiagOnce(Format('DrawUnitState teleport reload: UnitId=%d out of range (High(UnitsCustomFields)=%d)',
              [UnitId, High(UnitsCustomFields)]));

          if MaxReloadTime <> 0 then
          begin
            BottomZ := 6;
            if (Unit_p.nKills >= 5) and
               not CustomReloadBar then
            begin
              CurReloadTime := CurReloadTime - VETERANLEVEL_RELOADBOOST;
              MaxReloadTime := MaxReloadTime - VETERANLEVEL_RELOADBOOST;
            end;

            if CurReloadTime < 0 then
              CurReloadTime := 0;

            // stockpile weapon build progress instead of reload bar
            if (StockPile <> 0) and
               not CustomReloadBar then
            begin
              if (Unit_p.p_SubOrder <> nil) and
                 (IniSettings.Stockpile) then
              begin
                MaxReloadTime := 100;
                CurReloadTime := GetUnit_BuildWeaponProgress(Unit_p);
              end else
                MaxReloadTime := 0; // disable drawing bar
            end;

            if MaxReloadTime > 0 then
            begin
              RectDrawPos.Left := Word(CenterPosX) - 17;
              RectDrawPos.Right := Word(CenterPosX) + 17;
              RectDrawPos.Top := Word(CenterPosZ) + 5 - 2;
              RectDrawPos.Bottom := Word(CenterPosZ) + 5 + 2;
            {  if StockPile <> 0 then
                DrawRectangle(p_Offscreen, @RectDrawPos, PByte(LongWord(ColorsPal)+4)^)
              else   }
              DrawBar(p_Offscreen, @RectDrawPos, PByte(ColorsPal)^);

              Inc(RectDrawPos.Top);
              Dec(RectDrawPos.Bottom);
              Inc(RectDrawPos.Left);
              RectDrawPos.Right := Round(RectDrawPos.Left + (32 * CurReloadTime) / MaxReloadTime);

              if StockPile <> 0 then
              begin
                DrawBar(p_Offscreen, @RectDrawPos, PByte(LongWord(ColorsPal)+GetRaceSpecificColor(28))^)
              end else
              begin
                BarProgress := Round((CurReloadTime / MaxReloadTime) * 100);
                WeapReloadColor := GetRaceSpecificColor(26);
                DrawBar(p_Offscreen, @RectDrawPos, PByte(LongWord(ColorsPal)+WeapReloadColor - (BarProgress div 15))^);
              end;
            end;
          end;
        end; { IniSettings.WeaponReloadTimeBar }

        end; {UnitHealth > 0}

        if IniSettings.MinReclaimTime > 0 then
        begin
          CurOrder := TAUnit.GetCurrentOrderType(Unit_p);
          if (CurOrder = Action_Reclaim) or
             (CurOrder = Action_VTOL_Reclaim) or
             (CurOrder = Action_Capture) or
             (CurOrder = Action_Resurrect) then
          begin
            if (CurOrder = Action_Reclaim) or
               (CurOrder = Action_Resurrect) or
               (CurOrder = Action_Capture) then
              OrderStateCorrect := TAUnit.GetCurrentOrderState(Unit_p) and $400000 = $400000
            else
              OrderStateCorrect := TAUnit.GetCurrentOrderState(Unit_p) and $100000 = $100000;
            if OrderStateCorrect then
            begin
              if CurOrder = Action_Capture then
                FeatureDefID := 0
              else
                FeatureDefID := GetFeatureTypeFromOrder(@Unit_p.p_MainOrder.Position, Unit_p.p_MainOrder, nil);
              if FeatureDefID <> Word(-1) then
              begin
                MaxActionVal := 0;
                CurActionVal := 0;
                case CurOrder of
                  Action_Reclaim :
                  begin
                    p_FeatureDef := TAMem.FeatureDefId2Ptr(FeatureDefID);
                    MaxActionVal := Trunc( (p_FeatureDef.fMetal + p_FeatureDef.fEnergy) / 2 + 15);
                    CurActionVal := TAUnit.GetCurrentOrderParams(Unit_p, 1);
                  end;
                  Action_VTOL_Reclaim :
                  begin
                    p_FeatureDef := TAMem.FeatureDefId2Ptr(FeatureDefID);
                    MaxActionVal := Trunc( (p_FeatureDef.fMetal + p_FeatureDef.fEnergy) / 2 + 30);
                    CurActionVal := TAUnit.GetCurrentOrderParams(Unit_p, 1);
                  end;
                  Action_Capture:
                  begin
                    ActionUnit := TAUnit.GetCurrentOrderTargetUnit(Unit_p);
                    if ActionUnit <> nil then
                    begin
                      ActionUnitType := TAUnit.GetUnitInfoId(ActionUnit);
                      if ActionUnitType <> 0 then
                      begin
                        ActionUnitBuildCost1 := TAMem.UnitInfoId2Ptr(ActionUnitType).lBuildCostEnergy * 30 * 0.00050000002;
                        ActionUnitBuildCost2 := TAMem.UnitInfoId2Ptr(ActionUnitType).lBuildCostMetal * 30 * -0.0071428572;
                        ActionTime := (ActionUnitBuildCost1 - ActionUnitBuildCost2) + 150;

                        MaxActionVal := Round(ActionTime);
                        if MaxActionVal - TAUnit.GetCurrentOrderParams(Unit_p, 1) > 0 then
                        begin
                          CurActionVal := TAUnit.GetCurrentOrderParams(Unit_p, 1);
                          CurActionVal := MaxActionVal - CurActionVal;
                        end;
                      end;
                    end;
                  end;
                  Action_Resurrect :
                  begin
                    // p_FeatureDef := TAMem.FeatureDefId2Ptr(FeatureDefID);
                    ActionUnitType := TAUnit.GetCurrentOrderParams(Unit_p, 1);
                    if ActionUnitType <> 0 then
                    begin
                      ActionUnitBuildTime := TAMem.UnitInfoId2Ptr(ActionUnitType).lBuildTime;
                      ActionWorkTime := Unit_p.p_UnitInfo.nWorkerTime div 30;
                      ActionTime := (ActionUnitBuildTime * 0.3) / ActionWorkTime;
                      MaxActionVal := Trunc(ActionTime);
                      CurActionVal := TAUnit.GetCurrentOrderParams(Unit_p, 2);
                    end;
                  end;
                end;

                if (MaxActionVal > 0) and
                   (CurActionVal > 0) and
                   (CurActionVal <= MaxActionVal) and  // TA changes par1 to it once feature is reclaimed but order state remains "reclaiming"...
                   (MaxActionVal >= IniSettings.MinReclaimTime * 30) then
                begin
                  RectDrawPos.Left := Word(CenterPosX) - 17;
                  RectDrawPos.Right := Word(CenterPosX) + 17;
                  RectDrawPos.Top := Word(CenterPosZ) - 7;
                  RectDrawPos.Bottom := Word(CenterPosZ) - 3;

                  DrawBar(p_Offscreen, @RectDrawPos, PByte(ColorsPal)^);

                  Inc(RectDrawPos.Top);
                  Dec(RectDrawPos.Bottom);
                  Inc(RectDrawPos.Left);
                  RectDrawPos.Right := Round(RectDrawPos.Left + (32 * CurActionVal) / MaxActionVal);

                  BarProgress := Round((CurActionVal / MaxActionVal) * 100);
                  ReclaimColor := GetRaceSpecificColor(27);
                  DrawBar(p_Offscreen, @RectDrawPos, PByte(LongWord(ColorsPal)+ReclaimColor + (BarProgress div 25))^);
                end;
              end;
            end;
          end;
        end;

        // built weapons counter (nukes)
        if IniSettings.Stockpile then
          if Unit_p.UnitWeapons[0].cStock > 0 then
            DrawTextCustomFont(p_Offscreen, PAnsiChar(IntToStr(Unit_p.UnitWeapons[0].cStock)), Word(CenterPosX), Word(CenterPosZ) - 13, -1);

        // transporter count
        if IniSettings.Transporters and
           (UnitInfo.nCategory > High(UnitInfoCustomFields)) then
          LogDiagOnce(Format('DrawUnitState transporter: nCategory=%d out of range (High(UnitInfoCustomFields)=%d)',
            [UnitInfo.nCategory, High(UnitInfoCustomFields)]));
        if IniSettings.Transporters and
           (UnitInfo.nCategory <= High(UnitInfoCustomFields)) then
        begin
          if (UnitInfo.UnitTypeMask and 2048 = 2048) then   // unit is air
          begin
            if (UnitInfoCustomFields[UnitInfo.nCategory].MultiAirTransport = 0) then
              TransportCap := 0
            else
              if (UnitInfoCustomFields[UnitInfo.nCategory].TransportWeightCapacity = 0) then
              begin
                TransportCap := UnitInfo.cTransportCap;
              end else
              begin
                TransportCap := 0;
              end;
          end else
          begin
            TransportCap := UnitInfo.cTransportCap;
          end;

          if TransportCap > 0 then
          begin
            TransportCount := TAUnit.GetLoadCurAmount(Unit_p);
            if TransportCount > 0 then
              DrawTextCustomFont(p_Offscreen, PAnsiChar(IntToStr(TransportCount) + '/' + IntToStr(TransportCap)), Word(CenterPosX) - 10, Word(CenterPosZ) - 70, -1);
          end else
          begin
            WeightTransportMax := UnitInfoCustomFields[UnitInfo.nCategory].TransportWeightCapacity;
            if WeightTransportMax > 0 then
            begin
              WeightTransportCur := TAUnit.GetLoadWeight(Unit_p);
              TransportCap := UnitInfo.cTransportCap;
              TransportCount := TAUnit.GetLoadCurAmount(Unit_p);

              if (WeightTransportCur > 0) then
              begin
                WeightTransportPercent := Round((WeightTransportCur / WeightTransportMax) * 100);
                FontBackgroundColor := GetFontBackgroundColor;
                if WeightTransportPercent > 100 then
                  WeightTransportPercent := 100;
                if TransportCount = TransportCap then
                  WeightTransportPercent := 100;
                if (WeightTransportPercent > 85) then
                  SetFontColor(PByte(LongWord(ColorsPal)+18)^, FontBackgroundColor)
                else
                  if (WeightTransportPercent > 50) then
                    SetFontColor(PByte(LongWord(ColorsPal)+17)^, FontBackgroundColor)
                  else
                    SetFontColor(PByte(LongWord(ColorsPal)+16)^, FontBackgroundColor);

                DrawTextCustomFont(p_Offscreen,
                               PAnsiChar(IntToStr(WeightTransportPercent) + '%'),
                               Word(CenterPosX) - 10, Word(CenterPosZ) - 70, -1);
                SetFontColor(PByte(LongWord(ColorsPal)+255)^, FontBackgroundColor);
              end;
            end;
          end;

        end;
      end;

      if (PPlayerStruct(Unit_p.p_Owner).cPlayerIndex = TAData.LocalPlayerID) and
         (Unit_p.HotKeyGroup <> 0) then
      begin
        AllowHotkeyDraw := False;
        if Unit_p.p_TransporterUnit <> nil then
        begin
          if Unit_p.p_TransporterUnit.HotKeyGroup = 0 then
            AllowHotkeyDraw := True;
        end else
          AllowHotkeyDraw := True;
          
        if AllowHotkeyDraw then
        begin
          sGroup := PAnsiChar(Unit_p.HotKeyGroup + 48);
          DrawTextCustomFont(p_Offscreen, @sGroup, Word(CenterPosX), Word(CenterPosZ) + 3 + BottomZ, -1);
        end;
      end;
    end; { Bars enabled }
  end;
  except
    on e: exception do
  end;
end;

procedure DrawTrueIncome(p_Offscreen: Pointer;
  RaceSideData: PRaceSideData; ViewResBar: PViewResBar); stdcall;
var
  ResourceIncome : Single;
  PlayerResourceString : PAnsiChar;
  ColorsPal : Pointer;
  FontBackgroundColor: Integer;
  SideIndex: Integer;
begin
  SideIndex := RaceSideData.lSideIdx;
  if SideIndex <= High(ExtraSideData) then
  begin
    ColorsPal := TAData.ColorsPalette;
    FontBackgroundColor := GetFontBackgroundColor;

    if ExtraSideData[SideIndex].rectRealEIncome.Left <> 0 then
    begin
      ResourceIncome := ViewResBar.fEnergyProduction - ViewResBar.fEnergyExpense;
      if ResourceIncome >= 0.0 then
      begin
        SetFontColor(PByte(LongWord(ColorsPal)+10)^, FontBackgroundColor);
        if ResourceIncome < 10000 then
          PlayerResourceString := PAnsiChar(Format('+%.0f', [ResourceIncome], FormatSettings))
        else
        begin
          ResourceIncome := ResourceIncome / 1000;
          PlayerResourceString := PAnsiChar(Format('+%.0fK', [ResourceIncome], FormatSettings));
        end;
      end else
      begin
        SetFontColor(PByte(LongWord(ColorsPal)+12)^, FontBackgroundColor);
        if ResourceIncome > -10000 then
          PlayerResourceString := PAnsiChar(Format('%.0f', [ResourceIncome], FormatSettings))
        else
        begin
          ResourceIncome := ResourceIncome / 1000;
          PlayerResourceString := PAnsiChar(Format('%.0fK', [ResourceIncome], FormatSettings));
        end;
      end;
      DrawTextCustomFont(p_Offscreen, PlayerResourceString,
        ExtraSideData[SideIndex].rectRealEIncome.Left,
        ExtraSideData[SideIndex].rectRealEIncome.Top, -1);
    end;

    if ExtraSideData[SideIndex].rectRealMIncome.Left <> 0 then
    begin
      ResourceIncome := ViewResBar.fMetalProduction - ViewResBar.fMetalExpense;
      if ResourceIncome >= 0.0 then
      begin
        SetFontColor(PByte(LongWord(ColorsPal)+10)^, FontBackgroundColor);
        if ResourceIncome < 10000 then
          PlayerResourceString := PAnsiChar(Format('+%.1f', [ResourceIncome], FormatSettings))
        else
        begin
          ResourceIncome := ResourceIncome / 1000;
          PlayerResourceString := PAnsiChar(Format('+%.1fK', [ResourceIncome], FormatSettings));
        end;
      end else
      begin
        SetFontColor(PByte(LongWord(ColorsPal)+12)^, FontBackgroundColor);
        if ResourceIncome > -10000 then
          PlayerResourceString := PAnsiChar(Format('%.1f', [ResourceIncome], FormatSettings))
        else
        begin
          ResourceIncome := ResourceIncome / 1000;
          PlayerResourceString := PAnsiChar(Format('%.1fK', [ResourceIncome], FormatSettings));
        end;
      end;
      DrawTextCustomFont(p_Offscreen, PlayerResourceString,
        ExtraSideData[SideIndex].rectRealMIncome.Left,
        ExtraSideData[SideIndex].rectRealMIncome.Top, -1);
    end;
  end;
end;

procedure ExtraUnitBars_MainCall;
asm
  lea     eax, [esp+224h+OFFSCREEN_off]
  push    edx             // PosY
  push    ebp             // PosX
  push    edi             // p_Unit
  push    eax             // OFFSCREEN_ptr
  call    DrawUnitState
  push $00469CFE;
  call PatchNJump;
end;

procedure TrueIncomeHook;
asm
  mov     ecx, [esi+126h]
  mov     edx, [esi+122h]
  push    0FFFFFFFFh      // MaxWidth
  push    ecx             // top
  lea     eax, [esp+22Ch-$170]
  push    edx             // left
  lea     ecx, [esp+230h+OFFSCREEN_off]
  push    eax             // Source
  push    ecx             // OFFSCREEN_ptr
  call    DrawTextCustomFont
  pushAD
  lea     ecx, [esp+224h-$1AC]
  mov     edx, esi
  push    ecx             // ViewResBar
  push    edx             // RaceSideData
  lea     ecx, [esp+22Ch+OFFSCREEN_off]
  push    ecx             // OFFSCREEN_ptr
  call    DrawTrueIncome
  popAD
  push $00469610;
  call PatchNJump;
end;

procedure DrawHealthPercentage(p_Offscreen: Pointer; p_Unit: PUnitStruct;
  SideData: PRaceSideData; CurrentHP, MaxHP: Cardinal; Yoffset: Integer); stdcall;
var
  HealthPercent : Single;
  HealthPercentStr : PAnsiChar;
  FontBackgroundColor: Integer;
  FormatSettings: TFormatSettings;
  GafFrame: Pointer;
begin
  if (MaxHP = 0) or (CurrentHP > MaxHP) then
    Exit;

  if SideData.lSideIdx <= High(ExtraSideData) then
  begin
    if (TAUnit.GetId(p_Unit) > High(UnitsCustomFields)) then
      LogDiagOnce(Format('DrawHealthPercentage: UnitId=%d out of range (High(UnitsCustomFields)=%d)',
        [TAUnit.GetId(p_Unit), High(UnitsCustomFields)]));
    if (TAUnit.GetId(p_Unit) <= High(UnitsCustomFields)) and
       (UnitsCustomFields[TAUnit.GetId(p_Unit)].ShieldedBy <> nil) then
    begin
      if ExtraSideData[SideData.lSideIdx].rectShieldIcon.Left <> 0 then
      begin
        if ExtraGAFAnimations.GafSequence_ShieldIcon <> nil then
        begin
          GafFrame := GAF_SequenceIndex2Frame(ExtraGAFAnimations.GafSequence_ShieldIcon, SideData.lSideIdx);
          CopyGafToContext(p_Offscreen, GafFrame,
            ExtraSideData[SideData.lSideIdx].rectShieldIcon.Left,
            ExtraSideData[SideData.lSideIdx].rectShieldIcon.Top + Yoffset);
        end;
      end;
    end;

    if ExtraSideData[SideData.lSideIdx].rectDamageVal.Left <> 0 then
    begin
      HealthPercent := (CurrentHP / MaxHP) * 100;
      if HealthPercent > 0.0 then
      begin
        FontBackgroundColor := GetFontBackgroundColor;
        SetFontColor(83, FontBackgroundColor);
        FormatSettings.DecimalSeparator := '.';
        HealthPercentStr := PAnsiChar(Format('%.1f%%', [HealthPercent], FormatSettings));
        DrawTextCustomFont(p_Offscreen, HealthPercentStr,
          ExtraSideData[SideData.lSideIdx].rectDamageVal.Left,
          ExtraSideData[SideData.lSideIdx].rectDamageVal.Top + Yoffset, -1);
      end;
    end;
  end;
end;

procedure HealthPercentage;
asm
  add     eax, ebx
  mov     [esp+18h], ecx
  pushAD
  push    ebx
  mov     ebx, [esp+34h]
  push    ebx      // max
  push    edx      // current
  push    ebp      // sidedata
  mov     ebx, [esp+54h]
  push    ebx
  push    edi      // offscreen
  call    DrawHealthPercentage
  popAD
  push $0046B08E;
  call PatchNJump;
end;

function DrawUnitRangesShowrangesOn(p_Offscreen: Pointer; CirclePointer: Cardinal; UnitInfo: PUnitInfo;
  UnitOrder: PUnitOrder; ReturnVal: Integer): Integer; stdcall;
begin
  // as a result give amount of circles that were drawn
  if UnitInfo.nCategory > High(UnitInfoCustomFields) then
  begin
    LogDiagOnce(Format('DrawUnitRangesShowrangesOn: nCategory=%d out of range (High=%d)',
      [UnitInfo.nCategory, High(UnitInfoCustomFields)]));
    Result := ReturnVal;
    Exit;
  end;
  if ( UnitInfoCustomFields[UnitInfo.nCategory].TeleportMinDistance <> 0 ) then
  begin
    Inc(ReturnVal);
    DrawRangeCircle(
        p_Offscreen,
        CirclePointer,
        @UnitOrder.p_Unit.Position,
        UnitInfoCustomFields[UnitInfo.nCategory].TeleportMinDistance,
        138,
        PAnsiChar('minteleport'),
        ReturnVal);
  end;
  if ( UnitInfoCustomFields[UnitInfo.nCategory].TeleportMaxDistance <> 0 ) then
  begin
    Inc(ReturnVal);
    DrawRangeCircle(
        p_Offscreen,
        CirclePointer,
        @UnitOrder.p_Unit.Position,
        UnitInfoCustomFields[UnitInfo.nCategory].TeleportMaxDistance,
        140,
        PAnsiChar('maxteleport'),
        ReturnVal);
  end;
  Result := ReturnVal;
end;

procedure DrawUnitRanges_ShowrangesOnHook;
asm
  push    edi
  push    edx
  push    ecx
  push    ebx
  push    eax

  push    esi
  push    ebx
  push    eax // unitinfo
  push    edi // circle point
  push    ebp
  call    DrawUnitRangesShowrangesOn
  mov     esi, eax

  pop     eax
  pop     ebx
  pop     ecx
  pop     edx
  pop     edi

  mov     dx, [eax+TUnitInfo.nSightDistance]
  push $00439251;
  call PatchNJump;
end;

procedure DrawUnitRangesShowrangesOff(p_Offscreen: Pointer;
  CirclePointer: Cardinal; UnitOrder: PUnitOrder); stdcall;
var
  CustomRange: Integer;
  Radius: Integer;
  GameTime: Integer;
  UnitInfo: PUnitInfo;
begin
  UnitInfo := UnitOrder.p_Unit.p_UnitInfo;
  if UnitInfo = nil then
    Exit;
  if UnitInfo.nCategory > High(UnitInfoCustomFields) then
  begin
    LogDiagOnce(Format('DrawUnitRangesShowrangesOff: nCategory=%d out of range (High=%d)',
      [UnitInfo.nCategory, High(UnitInfoCustomFields)]));
    Exit;
  end;

  // Diagnostic (2026-07-22): confirms this hook actually runs (i.e. fires
  // for a selected unit at all) and what CustomRange1Distance it sees -
  // see ARMARAD shield-radius-circle investigation. Logs the first call
  // only, regardless of which unit triggered it.
  LogDiagOnce(DiagLoggedRangeHookSeen,
    Format('DrawUnitRangesShowrangesOff running: nCategory=%d CustomRange1Distance=%d CustomRange1Color=%d',
      [UnitInfo.nCategory, UnitInfoCustomFields[UnitInfo.nCategory].CustomRange1Distance,
       UnitInfoCustomFields[UnitInfo.nCategory].CustomRange1Color]));

  // Diagnostic (round 3): logs the FIRST time THIS SPECIFIC nCategory reaches
  // here, so ARMARAD (nCategory=18) gets its own guaranteed log line even if
  // some other unit's nCategory already used up DiagLoggedRangeHookSeen above.
  if (UnitInfo.nCategory >= 0) and (UnitInfo.nCategory <= High(DiagSeenRangeCategory))
     and not DiagSeenRangeCategory[UnitInfo.nCategory] then
  begin
    DiagSeenRangeCategory[UnitInfo.nCategory] := True;
    LogDiag(Format('DrawUnitRangesShowrangesOff: nCategory=%d first seen here, CustomRange1Distance=%d CustomRange1Color=%d',
      [UnitInfo.nCategory, UnitInfoCustomFields[UnitInfo.nCategory].CustomRange1Distance,
       UnitInfoCustomFields[UnitInfo.nCategory].CustomRange1Color]));
  end;

  if ( UnitInfoCustomFields[UnitInfo.nCategory].CustomRange1Distance <> 0 ) then
  begin
    LogDiagOnce(DiagLoggedRangeCircleDrawn,
      Format('DrawUnitRangesShowrangesOff: drawing CustomRange1 circle, nCategory=%d dist=%d color=%d',
        [UnitInfo.nCategory, UnitInfoCustomFields[UnitInfo.nCategory].CustomRange1Distance,
         UnitInfoCustomFields[UnitInfo.nCategory].CustomRange1Color]));
    DrawRangeCircle(
        p_Offscreen,
        CirclePointer,
        @UnitOrder.p_Unit.Position,
        UnitInfoCustomFields[UnitInfo.nCategory].CustomRange1Distance,
        UnitInfoCustomFields[UnitInfo.nCategory].CustomRange1Color,
        nil,
        0);
  end;
  if ( UnitInfoCustomFields[UnitInfo.nCategory].CustomRange2Distance <> 0 ) then
  begin
    if UnitInfoCustomFields[UnitInfo.nCategory].CustomRange2Animate then
    begin
      CustomRange := UnitInfoCustomFields[UnitInfo.nCategory].CustomRange2Distance;
      Radius := 8;
      GameTime := TAData.GameTime mod 60;
      if ((2 * CustomRange * GameTime div 60) >= 8 ) then
        Radius := 2 * CustomRange * GameTime div 60;
      if ( Radius >= CustomRange ) then
        Radius := UnitInfoCustomFields[UnitInfo.nCategory].CustomRange2Distance;
    end else
      Radius := UnitInfoCustomFields[UnitInfo.nCategory].CustomRange2Distance;

    DrawRangeCircle( p_Offscreen,
                     CirclePointer,
                     @PUnitStruct(UnitOrder.p_Unit).Position,
                     Radius,
                     UnitInfoCustomFields[UnitInfo.nCategory].CustomRange2Color,
                     nil, 0 );
  end;
end;

procedure DrawUnitRanges_CustomRanges;
label
  loc_439CC8;
asm
  push    edx
  mov     edx, [esp+30h]
  push    ecx
  push    ebx
  push    eax
  mov     eax, [esp+38h]

  push    esi // unit order
  push    edx // circle point
  push    eax
  call    DrawUnitRangesShowrangesOff

  pop     eax
  pop     ebx
  pop     ecx
  pop     edx

  and     eax, edx;
  test    al, 10h;
  jz      loc_439CC8
  push $00439CA1;
  call PatchNJump;
loc_439CC8 :
  push $00439CC8;
  call PatchNJump;
end;

function DrawExplosionsRectExpand(Rect: PtagRECT; x, y: Integer): Boolean; stdcall;
begin
  Result := (x >= (Rect.Left - IniSettings.ExplosionsGameUIExpand)) and
            (x <= (Rect.Right + IniSettings.ExplosionsGameUIExpand)) and
            (y >= (Rect.Top - IniSettings.ExplosionsGameUIExpand)) and
            (y <= (Rect.Bottom + IniSettings.ExplosionsGameUIExpand));
end;

procedure DrawExplosionsRectExpandHook;
asm
  push    edi                         // y
  push    ebx                         // x
  push    eax                         // Rect
  call    DrawExplosionsRectExpand
  push $00420C4F;
  call PatchNJump;
end;

procedure DrawExplosionsRectExpandHook2;
asm
  push    edi                         // y
  push    esi                         // x
  push    eax                         // Rect
  call    DrawExplosionsRectExpand
  push $00420BAA;
  call PatchNJump;
end;

procedure LoadSideSpecificLogos; stdcall;
var
  i: Integer;
begin
  for i := Low(ExtraSideData) to High(ExtraSideData) do
  begin
    if Trim(ExtraSideData[i].logoGAF) <> '' then
      ExtraSideData[i].p_LogoGAF := GAF_Name2Sequence(TAData.MainStruct.p_LogosGaf,
                                                      PAnsiChar(ExtraSideData[i].logoGAF))
  end;
end;

procedure LoadArmCore32ltGafSequences;
asm
  pushAD
  call    LoadSideSpecificLogos
  popAD
  mov     edx, [TADynMemStructPtr]
  push $00431911;
  call PatchNJump;
end;

function GetStorageText(AValue: Single): String;
begin
  Result := '';
  if AValue < 10000 then
  begin
    Result := Format('%.0f', [AValue], FormatSettings);
  end else
  begin
    if AValue < 100000 then
    begin
      AValue := AValue / 1000;
      Result := Format('%.1fK', [AValue], FormatSettings);
    end;
  end;
  if Result = '' then
  begin
    AValue := AValue / 1000;
    Result := Format('%.0fK', [AValue], FormatSettings);
  end;
end;

procedure DrawShadowedText(p_Offscreen: Pointer;
  Str: String; left: Integer; top: Integer; MaxWidth: Integer; Color: Byte; AlignRight: Boolean);
begin
  if AlignRight then
    Left := Left - GetCustomFontStrExtent(GetFontType, PAnsiChar(Str));
  SetFontColor(0, GetFontBackgroundColor);
  DrawTextCustomFont(p_Offscreen, PAnsiChar(Str), Left + 2, Top + 2, MaxWidth);
  SetFontColor(Color, GetFontBackgroundColor);
  DrawTextCustomFont(p_Offscreen, PAnsiChar(Str), Left, Top, MaxWidth);
end;

// kill/loss flash arrays in the exe are only 10 bytes (players 0..9)
function FlashCol(Base: Cardinal; Idx: Byte): Byte;
begin
  if Idx < 10 then Result := PByte(Base + Idx)^ else Result := 0;
end;

procedure DrawScoreboard(p_Offscreen: Pointer); stdcall;
var
  i: Integer;
  v2, v3, c: Byte;
  v4, v5, v7, v8, v9: Integer;
  ScoreBoardPos, LocalPlayerBox: tagRect;
  PlayersDrawListTop: Integer;
  cCurActivePlayer, IteratePlayerIdx : Byte;
  cCurActiveSortPlayer: Byte;
  cIterateSort : Byte;
  PlayerPtr, PlayerSort: PPlayerStruct;
  PlayerType, PlayerSortType: TTAPlayerController;
  TextLeftOff : Integer;
  p_ColorLogo : PGAFFrame;
  Counter : Integer;
  PlayerLogoRect, PlayerLogoTransform : TGAFFrameTransform;
  ScoreBoardWidth: Integer;
  bDraw: Boolean;
  p_OldFont: Pointer;
  BarTagRect: tagRECT;
label
  SortPlayers;
begin
  if ( PInteger($51F2F4)^ < TAData.GameTime ) then
  begin
    PInteger($51F2F4)^ := TAData.GameTime + 1;
    i := 0;
    repeat
      v2 := PByte($51F2C8 + i)^;
      if (v2 > 0) then
        PByte($51F2C8 + i)^ := v2 - 2;
      v3 := PByte($51E810 + i)^;
      if (v3 > 0) then
        PByte($51E810 + i)^ := v3 - 2;
      Inc(i);
    until ( i = 10 );
  end;

  if TAData.NetworkLayerEnabled then
    ScoreBoardWidth := SCOREBOARD_WIDTH
  else
    ScoreBoardWidth := 200;

  v4 := PInteger(Cardinal(TAData.MainStruct) + $57D)^;
  c := 3;
  if v4 <> -1 then
    c := PByte(PCardinal(PCardinal(Cardinal(TAData.MainStruct) + $531)^+4)^+347*Cardinal(v4))^;
  if (((TAData.MainStruct.GameOptionMask and $80) <> 0) or (GetAsyncKeyState(VK_SPACE) <> 0)) and
     ((v4 = -1) or (c <> 3)) then
  begin
    v8 := PInteger(ScoreBoardRoll)^;
    if ( PInteger(ScoreBoardRoll)^ < ScoreBoardWidth ) then
    begin
      if ( PInteger(ScoreBoardRoll)^ <= 0 ) then
      begin
        PlaySound_2D_Name(PAnsiChar('Panel'), 0);
        v8 := PInteger(ScoreBoardRoll)^;
      end;
      v9 := (ScoreBoardWidth - v8) div 4;
      if ( v9 <= 1 ) then
        v9 := 1;
      PInteger(ScoreBoardRoll)^ := v9 + v8;
      if ( v9 + v8 >= ScoreBoardWidth ) then
      begin
        PInteger(ScoreBoardRoll)^ := ScoreBoardWidth;
        PlaySound_2D_Name(PAnsiChar('Options'), 0);
      end;
    end;
  end else
  begin
    v5 := PInteger(ScoreBoardRoll)^;
    if ( PInteger(ScoreBoardRoll)^ <= 0 ) then
      Exit;
    if ( PInteger(ScoreBoardRoll)^ = ScoreBoardWidth ) then
    begin
      PlaySound_2D_Name(PAnsiChar('Panel'), 0);
      v5 := PInteger(ScoreBoardRoll)^;
    end;
    v7 := v5 div 4;
    if ( v5 div 4 <= 1 ) then
      v7 := 1;
    PInteger(ScoreBoardRoll)^ := v5 - v7;
    if ( v5 - v7 <= 0 ) then
    begin
      PInteger(ScoreBoardRoll)^ := 0;
      PlaySound_2D_Name(PAnsiChar('Options'), 0);
    end;
  end;

  ScoreBoardPos.Left := GetTA_ScreenWidth - PInteger(ScoreBoardRoll)^;
  ScoreBoardPos.Right := ScoreBoardPos.Left + ScoreBoardWidth;
  ScoreBoardPos.Top := 32;
  ScoreBoardPos.Bottom := 40 * (TAData.MainStruct.nActivePlayersCount) + 46 + 15;
  DrawTransparentBox(p_Offscreen, @ScoreBoardPos, -26);
  // credit line at the bottom of the scoreboard
  DrawText(p_Offscreen, PAnsiChar(TA16P_SHORT),
    ScoreBoardPos.Left + 5, ScoreBoardPos.Bottom - 14, ScoreBoardWidth - 10, 0);

  DrawText(p_Offscreen, TranslateString(PAnsiChar('Kills')),
    ScoreBoardPos.Left + 5, ScoreBoardPos.Top, 119, 0);

  DrawText(p_Offscreen, TranslateString(PAnsiChar('Losses')),
           ScoreBoardPos.Right - GetStrExtent(TranslateString(PAnsiChar('Losses'))) - 2,
           ScoreBoardPos.Top, 119, 0);
  {
  if TAData.NetworkLayerEnabled then
  begin
    StrExt := GetStrExtent(TranslateString(PAnsiChar('Ping')));
    DrawText(p_Offscreen, TranslateString(PAnsiChar('Ping')),
      ScoreBoardPos.Right - StrExt - 2, ScoreBoardPos.Top, 119, 0);
  end;
  }
  PlayersDrawListTop := ScoreBoardPos.Top + 15;
  cCurActivePlayer := 0;
  if TAData.MainStruct.nActivePlayersCount > 0 then
  begin
    repeat
      PlayerPtr := TAPlayer.GetPlayerByIndex(0);
      IteratePlayerIdx := 0;
      bDraw := True;
      while True do
      begin
        if TAPlayer.IsActive(PlayerPtr) then
        begin
          PlayerType := TAPlayer.PlayerController(PlayerPtr);
          if (PlayerType = Player_LocalHuman) or
             (PlayerType = Player_LocalAI) or
             (PlayerType = Player_RemotePlayer) then
          begin
            if (PlayerPtr.cPlayerIndex <> $FF) then
              if (PlayerPtr.nNumUnits <> 0) and (PlayerPtr.lUnitsCounter <> 0) then
                if ((PlayerPtr.PlayerInfo^.PropertyMask and $40) = 0) then
                  if (PlayerPtr.cPlayerScoreboard = cCurActivePlayer) then
                    Break;
          end;
        end;
        Inc(IteratePlayerIdx);
        PlayerPtr := TAPlayer.GetPlayerByIndex(IteratePlayerIdx);
        if IteratePlayerIdx = 16 then
        begin
          bDraw := False;
          Break;
        end;
      end;

      if not bDraw then goto SortPlayers;

      LocalPlayerBox.Left := ScoreBoardPos.Left + 4;
      LocalPlayerBox.Right := ScoreBoardPos.Right - 4;
      LocalPlayerBox.Top := PlayersDrawListTop - 1;
      LocalPlayerBox.Bottom := PlayersDrawListTop + 37;
      if ( IteratePlayerIdx = TAData.LocalPlayerID ) then
        DrawTransparentBox(p_OFFSCREEN, @LocalPlayerBox, -22);

      p_ColorLogo := GAF_SequenceIndex2Frame(TAPlayer.PlayerSideLogoSequence(PlayerPtr),
                                             TAPlayer.PlayerLogoIndex(PlayerPtr));
      if p_ColorLogo <> nil then
      begin
        TextLeftOff := ScoreBoardPos.Left + 39 + 3;
        PlayerLogoRect.Rect1.Left := ScoreBoardPos.Left + 7;
        PlayerLogoRect.Rect1.Top := PlayersDrawListTop + 2;
        PlayerLogoRect.Rect1.Right := ScoreBoardPos.Left + 39;
        PlayerLogoRect.Rect1.Bottom := PlayersDrawListTop + 2;

        PlayerLogoRect.Rect2.Left := ScoreBoardPos.Left + 39;
        PlayerLogoRect.Rect2.Top := PlayersDrawListTop + 34;
        PlayerLogoRect.Rect2.Right := ScoreBoardPos.Left + 7;
        PlayerLogoRect.Rect2.Bottom := PlayersDrawListTop + 34;

        PlayerLogoTransform.Rect1.Left := 0;
        PlayerLogoTransform.Rect1.Top := 0;
        PlayerLogoTransform.Rect1.Right := p_ColorLogo.Width - 1;
        PlayerLogoTransform.Rect1.Bottom := 0;

        PlayerLogoTransform.Rect2.Left := p_ColorLogo.Width - 1;
        PlayerLogoTransform.Rect2.Top := p_ColorLogo.Height - 1;
        PlayerLogoTransform.Rect2.Right := 0;
        PlayerLogoTransform.Rect2.Bottom := p_ColorLogo.Height - 1;

        GAF_DrawTransformed(p_Offscreen, p_ColorLogo, @PlayerLogoRect, @PlayerLogoTransform);
      end else
      begin
        TextLeftOff := ScoreBoardPos.Left + 7 + 3;
      end;
      DrawText(p_Offscreen, PlayerPtr.szName,
        TextLeftOff, PlayersDrawListTop + 1, ScoreBoardWidth-6, 0);
      if ( TAData.MainStruct.bAlterKills = 2 ) then
        Counter := PlayerPtr.nKills_Last
      else
        Counter := PlayerPtr.nKills;
      DrawText(p_Offscreen, PAnsiChar(IntToStr(Counter)),
        TextLeftOff, PlayersDrawListTop + 21, 119, FlashCol($51F2C8, IteratePlayerIdx));

      if ( TAData.MainStruct.bAlterKills = 2 ) then
        Counter := PlayerPtr.nLosses_Last
      else
        Counter := PlayerPtr.nLosses;
      DrawText(p_Offscreen, PAnsiChar(IntToStr(Counter)),
        ScoreBoardPos.Left + ScoreBoardWidth-6 - GetStrExtent(PAnsiChar(IntToStr(Counter))) - 2,
        PlayersDrawListTop + 21, 119, FlashCol($51E810, IteratePlayerIdx));

      if (TAData.GameingType = gtSkirmish) or TAData.NetworkLayerEnabled then
      begin
        p_OldFont := GetFontType;
        SetFontType(TAData.MainStruct.p_Font_SMLFONT);
        //SetFontType(Fonts.p_Courier);
        if TAPlayer.GetAlliedState(PlayerPtr, TAData.LocalPlayerID) and
           (TAData.LocalPlayerID <> PlayerPtr.cPlayerIndex) then
        begin
          BarTagRect.Left := ScoreBoardPos.Left - 200;
          BarTagRect.Top := PlayersDrawListTop;
          BarTagRect.Right := BarTagRect.Left + 200;
          BarTagRect.Bottom := PlayersDrawListTop + 40;
          DrawTransparentBox(p_Offscreen, @BarTagRect, -25);
          
          DrawShadowedText(p_Offscreen, GetStorageText(PlayerPtr.Resources.fCurrentMetal),
            BarTagRect.Left + 34, PlayersDrawListTop + 8, 30, 145, True);
          DrawShadowedText(p_Offscreen, GetStorageText(PlayerPtr.Resources.fCurrentEnergy),
            BarTagRect.Left + 34, PlayersDrawListTop + 24, 30, 145, True);

          DrawShadowedText(p_Offscreen, Format('+%.1f', [PlayerPtr.Resources.fMetalProduction], FormatSettings),
            BarTagRect.Left + 150, PlayersDrawListTop + 8, 50, 145, False);
          DrawShadowedText(p_Offscreen, Format('+%.0f', [PlayerPtr.Resources.fEnergyProduction], FormatSettings),
            BarTagRect.Left + 150, PlayersDrawListTop + 24, 50, 145, False);

          BarTagRect.Left := BarTagRect.Left + 39 + 3;
          BarTagRect.Top := PlayersDrawListTop + 10;
          BarTagRect.Right := BarTagRect.Left + 100;
          BarTagRect.Bottom := PlayersDrawListTop + 13;
          DrawBar(p_Offscreen, @BarTagRect, 0);
          if PlayerPtr.Resources.fMetalStorageMax > 0 then
            BarTagRect.Right := BarTagRect.Left + Round((PlayerPtr.Resources.fCurrentMetal / PlayerPtr.Resources.fMetalStorageMax) * 100)
          else
            BarTagRect.Right := BarTagRect.Left + 1;
          DrawBar(p_Offscreen, @BarTagRect, 128);

          BarTagRect.Top := PlayersDrawListTop + 26;
          BarTagRect.Right := BarTagRect.Left + 100;
          BarTagRect.Bottom := PlayersDrawListTop + 29;
          DrawBar(p_Offscreen, @BarTagRect, 0);
          if PlayerPtr.Resources.fEnergyStorageMax > 0 then
            BarTagRect.Right := BarTagRect.Left + Round((PlayerPtr.Resources.fCurrentEnergy / PlayerPtr.Resources.fEnergyStorageMax) * 100)
          else
            BarTagRect.Right := BarTagRect.Left + 1;
          DrawBar(p_Offscreen, @BarTagRect, 193);
        end;
        SetFontType(p_OldFont);
      end;
{      if TAData.NetworkLayerEnabled then
      begin
        if ( IteratePlayerIdx = TAData.LocalPlayerID ) then
        begin
          StrExt := GetStrExtent(PAnsiChar('n/a'));
          DrawText(p_Offscreen, PAnsiChar('n/a'),
            ScoreBoardPos.Left + ScoreBoardWidth-6 - StrExt - 2,
            PlayersDrawListTop + 21, 119, 0);
        end else
        begin
          Counter := PlayerPtr.nPing;
          StrExt := GetStrExtent(PAnsiChar(IntToStr(Counter)));
          DrawText(p_Offscreen, PAnsiChar(IntToStr(Counter)),
            ScoreBoardPos.Left + ScoreBoardWidth-6 - StrExt - 2,
            PlayersDrawListTop + 21, 119, 0);
        end;
      end;  }
      PlayersDrawListTop := PlayersDrawListTop + 40;
SortPlayers:
      if ( IteratePlayerIdx = 16 ) then
      begin
        cCurActiveSortPlayer := 0;
        PlayerSort := TAPlayer.GetPlayerByIndex(cCurActiveSortPlayer);
        cIterateSort := 16;
        repeat
          if ( TAPlayer.IsActive(PlayerSort) ) then
          begin
            PlayerSortType := TAPlayer.PlayerController(PlayerSort);
            if (PlayerSortType = Player_LocalHuman) or
               (PlayerSortType = Player_LocalAI) or
               (PlayerSortType = Player_RemotePlayer) then
            begin
              if (PlayerSort.cPlayerIndex <> $FF) then
                if (PlayerSort.nNumUnits <> 0) then
                  if ((PlayerSort.PlayerInfo^.PropertyMask and $40) = 0) then
                    if (PlayerSort.cPlayerScoreboard > cCurActivePlayer) then
                      PlayerSort.cPlayerScoreboard := PlayerSort.cPlayerScoreboard - 1;
            end;
          end;
          Inc(cCurActiveSortPlayer);
          PlayerSort := TAPlayer.GetPlayerByIndex(cCurActiveSortPlayer);
          Dec(cIterateSort);
        until ( cIterateSort = 0 );
      end;
      Inc(cCurActivePlayer);
    until cCurActivePlayer = TAData.MainStruct.nActivePlayersCount;

    // now draw watchers
    for IteratePlayerIdx := 0 to 9 do
    begin
      PlayerPtr := TAPlayer.GetPlayerByIndex(IteratePlayerIdx);
      if TAPlayer.IsActive(PlayerPtr) then
      begin
        PlayerType := TAPlayer.PlayerController(PlayerPtr);
        if (PlayerType = Player_LocalHuman) or
           (PlayerType = Player_LocalAI) or
           (PlayerType = Player_RemotePlayer) then
        begin
          if (PlayerPtr.nNumUnits = 0) then
          begin
            TextLeftOff := ScoreBoardPos.Left + 7 + 3;

            DrawText(p_Offscreen, PlayerPtr.szName,
              TextLeftOff, PlayersDrawListTop + 1, ScoreBoardWidth-6, 0);

            DrawText(p_Offscreen, TranslateString(PAnsiChar('Watcher')),
              TextLeftOff, PlayersDrawListTop + 21, 119, 0);
            {
            if TAData.NetworkLayerEnabled then
            begin
              if ( IteratePlayerIdx = TAData.LocalPlayerID ) then
              begin
                StrExt := GetStrExtent(PAnsiChar('n/a'));
                DrawText(p_Offscreen, PAnsiChar('n/a'),
                  ScoreBoardPos.Left + ScoreBoardWidth-6 - StrExt - 2,
                  PlayersDrawListTop + 21, 119, 0);
              end else
              begin
                Counter := PlayerPtr.nPing;
                StrExt := GetStrExtent(PAnsiChar(IntToStr(Counter)));
                DrawText(p_Offscreen, PAnsiChar(IntToStr(Counter)),
                  ScoreBoardPos.Left + ScoreBoardWidth-6 - StrExt - 2,
                  PlayersDrawListTop + 21, 119, 0);
              end;
            end;
            }
            PlayersDrawListTop := PlayersDrawListTop + 40;
          end;
        end;
      end;
    end;
  end;
end;

function GetCustomFlameStream(Weapon: PWeaponDef): Pointer; stdcall;
begin
  if Length(ExtraGAFAnimations.FlameStream) > 0 then
  begin
    if ExtraGAFAnimations.FlameStream[Weapon.ucColor - 1] <> nil then
      Result := ExtraGAFAnimations.FlameStream[Weapon.ucColor - 1]
    else
      Result := TAData.MainStruct.flamestream;
  end else
    Result := TAData.MainStruct.flamestream;
end;

procedure WeaponProjectileFlameStreamHook;
label
  CustomFlameStream,
  GoBack;
asm
  mov     cl, byte ptr [ebx+TWeaponDef.ucColor]
  test    cl, cl
  jnz     CustomFlameStream
  mov     edi, [edi+TTADynMemStruct.flamestream]
  jmp GoBack
CustomFlameStream :
  push    esi
  push    eax
  push    ebx
  push    ecx
  push    edx
  push    ebx // weapon
  call    GetCustomFlameStream
  mov     edi, eax
  pop     edx
  pop     ecx
  pop     ebx
  pop     eax
  pop     esi
GoBack :
  push $0049C3A4
  call PatchNJump
end;

type
  TPoints = array of TPoint;

procedure DrawDashCircle(p_Offscreen: Pointer;
  CenterX, CenterZ, Radius: Integer; Angle: Integer; ColorOffset: Byte);

  procedure RotateCircle(const Source: TPoints;
    lAngle: Integer; var Output: TPoints);
  var
    i: Integer;
    c, s, dx, dy: Real;
  begin
    if Length(Source) > 0 then
    Begin
      lAngle := EnsureRange(lAngle, 0, 360);
      c := cos(lAngle * PI / 180);
      s := sin(lAngle * PI / 180);
      SetLength(Output, Length(Source));
      for i := Low(Source) to High(Source) do
      begin
        dx := Source[i].X - CenterX;
        dy := Source[i].Y - CenterZ;
        Output[i].X := Round(CenterX + dx*c - dy*s);
        Output[i].Y := Round(CenterZ + dx*s + dy*c);
      end;
    end;
  end;

var
  Points: TPoints;
  OutPoints: TPoints;
  x, y: Integer;
  lRadiusError: Integer;
  i: Integer;
  bDrawOrSkip: Boolean;
begin
  x := Radius;
  y := 0;
  lRadiusError := 1 - x;
  bDrawOrSkip := True;
  while (x >= y) do
  begin
    if (y mod (Round(Radius / PI) - 1)) = 0 then
      bDrawOrSkip := not bDrawOrSkip;
    if bDrawOrSkip then
    begin
      SetLength(Points, Length(Points) + 8);
      Points[High(Points)-7].X := x + CenterX;
      Points[High(Points)-7].Y := y + CenterZ;
      Points[High(Points)-6].X := y + CenterX;
      Points[High(Points)-6].Y := x + CenterZ;
      Points[High(Points)-5].X := -x + CenterX;
      Points[High(Points)-5].Y := y + CenterZ;
      Points[High(Points)-4].X := -y + CenterX;
      Points[High(Points)-4].Y := x + CenterZ;
      Points[High(Points)-3].X := -x + CenterX;
      Points[High(Points)-3].Y := -y + CenterZ;
      Points[High(Points)-2].X := -y + CenterX;
      Points[High(Points)-2].Y := -x + CenterZ;
      Points[High(Points)-1].X := x + CenterX;
      Points[High(Points)-1].Y := -y + CenterZ;
      Points[High(Points)].X := y + CenterX;
      Points[High(Points)].Y := -x + CenterZ;
    end;
    Inc(y);
    if lRadiusError < 0 then
      lRadiusError := lRadiusError + (2 * y + 1)
    else
    begin
      Dec(x);
      lRadiusError := lRadiusError + (2 * (y - x) + 1);
    end;
  end;
  if (Angle <> 0) or (Angle <> 360) then
    RotateCircle(Points, Angle, OutPoints)
  else
    OutPoints := Points;
  for i := Low(OutPoints) to High(OutPoints) do
    DrawPoint(p_Offscreen, OutPoints[I].X, OutPoints[I].Y, ColorOffset);
end;

procedure DrawUnitSelectBox(p_Offscreen: Pointer; p_Unit: PUnitStruct); stdcall;
var
  x, z, y: Integer;
  CenterX, CenterZ: Integer;
  Radius: Integer;
  InMove: Boolean;
  Speed: Integer;
  CurOrder: TTAActionType;
  AnimDelay: Integer;
  IsMobileUnit: Boolean;
  ColorOffset: Byte;
  Angle: Integer;

  OffY, OffX: Integer;
  p_GAFFrame: PGAFFrame;
  ScreenPos: TPosition;
  p_Animation: PGAFSequence;
  UnitID: Word;
begin
  // Defensive bounds check: nUnitInfoID indexes UnitInfoCustomFields (sized to
  // IniSettings.UnitType at load). If it's ever out of range - bad/freed unit
  // state, whatever - fall back to the plain rect box instead of an AV.
  if p_Unit.nUnitInfoID > High(UnitInfoCustomFields) then
  begin
    LogDiagOnce(Format('DrawUnitSelectBox: nUnitInfoID=%d out of range (High(UnitInfoCustomFields)=%d) - falling back to rect box',
      [p_Unit.nUnitInfoID, High(UnitInfoCustomFields)]));
    DrawUnitSelectBoxRect(p_Offscreen, p_Unit);
    Exit;
  end;

  if (UnitInfoCustomFields[p_Unit.nUnitInfoID].SelectBoxType = 2) and
     (UnitInfoCustomFields[p_Unit.nUnitInfoID].SelectAnimation <> 0) then
  begin
    p_Animation := ExtraGAFAnimations.CustAnim[UnitInfoCustomFields[p_Unit.nUnitInfoID].SelectAnimation - 1];
    if p_Animation <> nil then
    begin
      UnitID := TAUnit.GetId(p_Unit);
      // Same check for UnitsCustomFields (sized to IniSettings.UnitLimit *
      // MAXPLAYERCOUNT at load) - this is the array actually implicated in
      // the "random" crash after ~45s of normal play.
      if UnitID > High(UnitsCustomFields) then
      begin
        LogDiagOnce(Format('DrawUnitSelectBox: UnitID=%d out of range (High(UnitsCustomFields)=%d) - falling back to rect box',
          [UnitID, High(UnitsCustomFields)]));
        DrawUnitSelectBoxRect(p_Offscreen, p_Unit);
        Exit;
      end;
      ScreenPos.X := p_Unit.Position.X - (TAData.MainStruct.lEyeBallMapX shl 16);
      ScreenPos.Y := p_Unit.Position.Y;
      ScreenPos.Z := p_Unit.Position.Z - (TAData.MainStruct.lEyeBallMapY shl 16);
      OffY := SHIWORD(ScreenPos.z) - (SHIWORD(ScreenPos.y) div 2) + 32;
      OffX := SHIWORD(ScreenPos.x) + 128;
      if UnitsCustomFields[UnitID].SelectAnimStartTime = 0 then
        UnitsCustomFields[UnitID].SelectAnimStartTime := TAData.GameTime;
      p_GAFFrame := GAF_SequenceIndex2Frame(p_Animation,
        (TAData.GameTime - UnitsCustomFields[UnitID].SelectAnimStartTime) mod p_Animation.Frames);
      if UnitInfoCustomFields[p_Unit.nUnitInfoID].SelectAnimationAlpha then
        AlphaCompsteBuf2OFFScreen(p_Offscreen, p_GAFFrame, OffX, OffY)
      else
        CopyGafToContext(p_Offscreen, p_GAFFrame, OffX, OffY);
      Exit;
    end;
  end;
  IsMobileUnit := TAMem.UnitInfoId2Ptr(p_Unit.nUnitInfoID).cBMCode = 1;
  if ((IniSettings.UnitSelectBoxType = 1) and not IsMobileUnit) then
    DrawUnitSelectBoxRect(p_Offscreen, p_Unit)
  else
    if (UnitInfoCustomFields[p_Unit.nUnitInfoID].SelectBoxType = 1) or
       ((IniSettings.UnitSelectBoxType = 1) and IsMobileUnit) or
       (IniSettings.UnitSelectBoxType = 2) then
    begin
      x := SHiWord(p_Unit.Position.X - (TAData.MainStruct.lEyeBallMapX shl 16));
      z := SHiWord(p_Unit.Position.Z - (TAData.MainStruct.lEyeBallMapY shl 16));
      y := SHiWord(p_Unit.Position.Y);
      CenterX := x + 128;
      CenterZ := z - (y div 2) + 32;
      Radius := 1 + (p_Unit.p_UnitInfo.lWidthHypot shr 16);

      InMove := False;
      if p_unit.p_MovementClass <> nil then
      begin
        Speed := TAUnit.GetCurrentSpeedPercent(p_Unit);
        if Speed > 0 then
        begin
          InMove := True;
          Radius := Round(Radius + (Radius * Speed) / IniSettings.UnitSelectZoomRatio);
        end;
      end else
      begin
        CurOrder := TAUnit.GetCurrentOrderType(p_Unit);
        if (CurOrder <> Action_Ready) and
           (CurOrder <> Action_Standby) and
           (CurOrder <> Action_VTOL_Standby) and
           (CurOrder <> Action_Wait) and
           (CurOrder <> Action_Guard_NoMove) and
           (CurOrder <> Action_NoResult) then
        begin
          InMove := True;
        end;
      end;
      if InMove then
        AnimDelay := 240
      else
        AnimDelay := 320;

      ColorOffset := PByte(Cardinal(TAData.ColorsPalette)+GetRaceSpecificColor(0))^;
      if (IniSettings.UnitSelectCircAnimType and 1) = 1 then
      begin
        if (IniSettings.UnitSelectCircAnimType and 4) = 4 then
          Angle := (p_Unit.Turn.Z div 182) mod 360
        else
          Angle := 360 - (360 * (TAData.GameTime mod AnimDelay) div AnimDelay);
        DrawDashCircle(p_Offscreen, CenterX, CenterZ, Radius, Angle, ColorOffset);
      end;
      if (IniSettings.UnitSelectCircAnimType and 2) = 2 then
      begin
        if (IniSettings.UnitSelectCircAnimType and 8) = 8 then
          Angle := 360 - (p_Unit.Turn.Z div 182) mod 360
        else
          Angle := 360 * (TAData.GameTime mod AnimDelay) div AnimDelay;
        DrawDashCircle(p_Offscreen, CenterX, CenterZ, Radius, Angle, ColorOffset);
      end;
    end else
      if (UnitInfoCustomFields[p_Unit.nUnitInfoID].SelectBoxType = 0) then
        DrawUnitSelectBoxRect(p_Offscreen, p_Unit)
end;

procedure DrawingBottomStateRefresh;
label
  ForceDraw,
  DoNotRefresh;
asm
  jnz     ForceDraw
  mov     ecx, ForceBottomStateRefresh
  test    ecx, ecx
  jz      DoNotRefresh
  mov     ForceBottomStateRefresh, 0
ForceDraw :
  push    $0046ACE3
  call    PatchNJump
DoNotRefresh :
  push    $0046B8EA
  call    PatchNJump
end;

Procedure OnInstallGUIEnhancements;
begin
  if IniSettings.HealthBarDynamicSize then
  begin
    if IniSettings.HealthBarCategories[0] <> 0 then
      STANDARDUNIT := IniSettings.HealthBarCategories[0];
    if IniSettings.HealthBarCategories[1] <> 0 then
      MEDIUMUNIT := IniSettings.HealthBarCategories[1];
    if IniSettings.HealthBarCategories[2] <> 0 then
      BIGUNIT := IniSettings.HealthBarCategories[2];
    if IniSettings.HealthBarCategories[3] <> 0 then
      HUGEUNIT := IniSettings.HealthBarCategories[3];
    if IniSettings.HealthBarCategories[4] <> 0 then
      EXTRALARGEUNIT := IniSettings.HealthBarCategories[4];
  end;
end;

Procedure OnUninstallGUIEnhancements;
begin
end;

function GetPlugin : TPluginData;
begin
  if IsTAVersion31 and State_GUIEnhancements then
  begin
    Result := TPluginData.Create( True,
                                  'GUIEnhancements',
                                  State_GUIEnhancements,
                                  @OnInstallGUIEnhancements,
                                  @OnUninstallGUIEnhancements );

    Result.MakeRelativeJmp( State_GUIEnhancements,
                            'ExtraUnitBars_MainCall',
                            @ExtraUnitBars_MainCall,
                            $00469CB1, 1 );

    Result.MakeRelativeJmp( State_GUIEnhancements,
                            'TrueIncomeHook',
                            @TrueIncomeHook,
                            $004695EE, 0 );

    Result.MakeRelativeJmp( State_GUIEnhancements,
                            'HealthPercentage',
                            @HealthPercentage,
                            $0046B088, 1 );

    Result.MakeStaticCall( State_GUIEnhancements,
                           'Draw unit selection box',
                           @DrawUnitSelectBox,
                           $00469B8A );
    Result.MakeStaticCall( State_GUIEnhancements,
                           'Draw unit selection box 2',
                           @DrawUnitSelectBox,
                           $004699EB );

    Result.MakeRelativeJmp( State_GUIEnhancements,
                            'Draw new unit ranges for +showranges mode',
                            @DrawUnitRanges_ShowrangesOnHook,
                            $0043924A, 2 );

    Result.MakeRelativeJmp( State_GUIEnhancements,
                            'Draw new unit ranges, showranges disabled',
                            @DrawUnitRanges_CustomRanges,
                            $00439C9B, 1 );

    if IniSettings.ExplosionsGameUIExpand > 0 then
    begin
      Result.MakeRelativeJmp( State_GUIEnhancements,
                              '',
                              @DrawExplosionsRectExpandHook,
                              $00420C47, 0 );
      Result.MakeRelativeJmp( State_GUIEnhancements,
                              '',
                              @DrawExplosionsRectExpandHook2,
                              $00420BA2, 0 );
    end;

    if IniSettings.ScoreBoard then
    begin
      Result.MakeRelativeJmp( State_GUIEnhancements,
                              'load core and arm logos',
                              @LoadArmCore32ltGafSequences,
                              $0043190B, 1 );

      Result.MakeStaticCall( State_GUIEnhancements,
                             'Draw score board with side logos and allied AI economy',
                             @DrawScoreboard,
                             $00469F65 );
    end;

    Result.MakeRelativeJmp( State_GUIEnhancements,
                            'WeaponProjectileFlameStreamHook',
                            @WeaponProjectileFlameStreamHook,
                            $0049C39E, 1 );

    Result.MakeRelativeJmp( State_GUIEnhancements,
                            'Unit bottom state force refresh',
                            @DrawingBottomStateRefresh,
                            $0046ACDD, 1 );
  end else
    Result := nil;
end;

initialization
  FormatSettings.DecimalSeparator := '.';

end.
