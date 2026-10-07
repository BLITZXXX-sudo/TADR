# tplayx 2.0

tplayx.dll (Total Annihilation recorder / plugin DLL) - Lazarus / Free Pascal, i386-win32.
Source layout mirrors https://github.com/BLITZXXX-sudo/TADR (`src/`, `src/Recorder/{plugins,TAMem,packets,netmsgHandling}`, `src/3rdparty`).

## Build

    lazbuild --build-all src\Recorder\tplayx.lpi

Output: `src\Recorder\tplayx.dll`. Copy it next to `TotalA.exe`.

Build modes:
- **Default (release)** - `-Xs -XX -CX`: debug info stripped + smart linking, ~0.85 MB. `-Xm` still writes `tplayx.map` (used for crash addresses).
- **Debug** - `lazbuild --build-all --build-mode=Debug src\Recorder\tplayx.lpi` (or `BUILD_AND_TEST.bat -Debug`): DWARF debug + line info, ~4.4 MB, for stepping in a debugger.
`BUILD_AND_TEST.bat` builds, checks for new compiler warnings, deploys to `C:\CAVEDOG\TOTALA`, starts the game and checks plugin start-up.

## Notes

auto transports
cloak generator 
