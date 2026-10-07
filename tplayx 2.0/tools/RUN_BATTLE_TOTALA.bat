@echo off
rem  Battle test for C:\CAVEDOG\TOTALA (like RUN_BUZZ_LAG.bat, without the attack args):
rem  builds the TEST tplayx (has +midbattle), host + join + start + .record, host spawns units
rem  east of the map centre, joiner west, both patrol to the middle. Logs checked at the end,
rem  release tplayx.dll put back.  Result: totala_1v1_result_*.txt
rem  Options: --seconds N  --wave N  --live N  --spread PX  --cx P --cz P  --host-units A,B  --join-units A,B  --keep
cd /d C:\tpLAYX1\god_mw_god
python run_1v1_totala.py --battle %*
pause
