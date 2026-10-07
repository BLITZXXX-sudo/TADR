@echo off
rem  Same-PC 1v1 test for C:\CAVEDOG\TOTALA: host + join + start + .record, then checks the
rem  TA Demo Recorder logs, ErrorLog.txt and Windows crash events.  Result: totala_1v1_result_*.txt
rem  Options: --seconds N  --norecord  --nodeploy  --keep
cd /d C:\tpLAYX1\god_mw_god
python run_1v1_totala.py %*
pause
