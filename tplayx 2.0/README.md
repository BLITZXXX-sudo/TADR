# tplayx 2.0

tplayx.dll (Total Annihilation recorder / plugin DLL) - Lazarus / Free Pascal, i386-win32.
Source layout mirrors https://github.com/BLITZXXX-sudo/TADR (`src/`, `src/Recorder/{plugins,TAMem,packets,netmsgHandling}`, `src/3rdparty`).

## Build

    lazbuild --build-all src\Recorder\tplayx.lpi

Output: `src\Recorder\tplayx.dll`. Copy it next to `TotalA.exe`.
`BUILD_AND_TEST.bat` builds, checks for new compiler warnings, deploys to `C:\CAVEDOG\TOTALA`, starts the game and checks plugin start-up.

## Notes

- Comments were removed from the project's own units. Third-party units keep their original headers and licences:
  `DPlay.pas`, `DPLobby.pas` (DirectX headers), `SynCommons.pas`, `SynLZ.pas`, `SynFPCTypInfo.pas`, `Synopse.inc`, `SynopseCommit.inc` (Synopse mORMot), `src/3rdparty/gphugef.pas` (GpHugeFile).
- The top-bar Wind / Tidal / Game Time display is drawn by tdraw.dll 2025.8.29 (fullscreen), not by tplayx.
