// 16-player exe support: player-table layout detection.
//
// The 16-player TotalA.exe (ProTA 16P NETQ build) moves the player table from
// TAdynmem+0x1B63 (10 entries) to TAdynmem+0x3A000 (16 entries). Every TA
// instruction that indexes the table was rewritten, so the exe itself tells us
// which layout it uses. We read two of those instructions, at sites TDraw never
// hooks, before any hook is installed:
//
//   0x453CCB  LEA EDX,[EBP+disp32]    (CheckForDroppedPlayers)  disp = 0x1B63 / 0x3A000
//   0x45492B  MOV EDI,[EAX+disp32]    (player-info handler)     disp = 0x1B8A / 0x3A027
//
// Both must agree; anything else keeps the stock layout.

#include <windows.h>
#include "tamem.h"

int g_TAPlayerCount = 10;
unsigned g_TAPlayersOffset = 0x1B63;

static bool ReadExeDword(unsigned addr, unsigned* out)
{
	MEMORY_BASIC_INFORMATION mbi;
	if (!VirtualQuery((LPCVOID)addr, &mbi, sizeof(mbi)) || mbi.State != MEM_COMMIT)
		return false;
	if (mbi.Protect & (PAGE_NOACCESS | PAGE_GUARD))
		return false;
	*out = *(const unsigned*)addr;
	return true;
}

void TA16P_Detect()
{
	static bool done = false;
	if (done)
		return;
	done = true;

	if (GetModuleHandleA(NULL) != (HMODULE)0x00400000)
		return;

	const unsigned char* lea = (const unsigned char*)0x453CCB;
	const unsigned char* mov = (const unsigned char*)0x45492B;
	unsigned leaDisp = 0, movDisp = 0, probe = 0;
	if (!ReadExeDword(0x453CCB, &probe) || !ReadExeDword(0x45492B, &probe))
		return;
	if (lea[0] != 0x8D || lea[1] != 0x95 || mov[0] != 0x8B || mov[1] != 0xB8)
		return;
	if (!ReadExeDword(0x453CCD, &leaDisp) || !ReadExeDword(0x45492D, &movDisp))
		return;

	if (leaDisp == 0x3A000 && movDisp == 0x3A027)
	{
		g_TAPlayersOffset = 0x3A000;
		g_TAPlayerCount = 16;
	}
}

// Exported marker so other mods (e.g. TPLAYX) can tell this TDraw handles the
// 16-player layout itself and must not have its hooks removed.
// Returns the live player count (10 or 16).
extern "C" __declspec(dllexport) int __cdecl TDraw_16PlayerAware()
{
	TA16P_Detect();
	return g_TAPlayerCount;
}

// Runs while the DLL is being loaded, before TDraw installs any hook.
static struct TA16PAutoDetect { TA16PAutoDetect() { TA16P_Detect(); } } s_ta16pAutoDetect;

static_assert(offsetof(TAdynmemStruct, PlayersStock) == 0x1B63, "TAdynmemStruct::PlayersStock moved");
static_assert(sizeof(PlayerStruct) == 0x14B, "PlayerStruct size changed");
static_assert(offsetof(PlayerStruct, AllyFlagAry) == 0x108, "PlayerStruct::AllyFlagAry moved");
static_assert(offsetof(PlayerStruct, AllyTeam) == 0x13F, "PlayerStruct::AllyTeam moved");
