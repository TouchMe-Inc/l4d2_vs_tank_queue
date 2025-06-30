#if defined  _vs_tank_queue_included_
 #endinput
#endif
#define _vs_tank_queue_included_


native int GetNextTank();

native void SetNextTank(int iClient);

/**
 * @brief Returns whether the player is a next tank
 *
 * @param iClient       Client ID
 *
 * @return              true or false
 **/
native bool IsNextTank(int iClient);

native bool HasNextTank();

native bool IsWhoHadTank(int iClient);

native bool IsWhoHadTankWithMap(int iClient, char[] szMapName, int iMaxLen);

public SharedPlugin __pl_tank_queue =
{
	name = "vs_tank_queue",
	file = "vs_tank_queue.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_tank_queue_SetNTVOptional()
{
	MarkNativeAsOptional("GetNextTank");
	MarkNativeAsOptional("SetNextTank");
	MarkNativeAsOptional("IsNextTank");
	MarkNativeAsOptional("HasNextTank");
	MarkNativeAsOptional("IsWhoHadTank");
	MarkNativeAsOptional("IsWhoHadTankWithMap");
}
#endif
