#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <vs_tank_queue>
#include <left4dhooks>
#include <colors>


public Plugin myinfo =
{
	name        = "VersusTankQueueForcePass",
	author      = "TouchMe",
	description = "Allows the administrator to intercept the tank",
	version     = "build0000",
	url         = "https://github.com/TouchMe-Inc/l4d2_vs_tank_queue"
}


#define TRANSLATIONS            "vs_tq_forcepass.phrases"

/*
 * Infected Class.
 */
#define SI_CLASS_SMOKER         1
#define SI_CLASS_CHARGER        6
#define SI_CLASS_TANK           8

/*
 * Team.
 */
#define TEAM_INFECTED           3


/**
 * Called before OnPluginStart.
 */
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if (GetEngineVersion() != Engine_Left4Dead2)
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

public void OnPluginStart()
{
	// Load translations.
	LoadTranslations(TRANSLATIONS);

	// Player Commands.
	RegAdminCmd("sm_forcepass", Cmd_PassTank, ADMFLAG_BAN,  "Gives the tank to a selected player");
}

/**
 * Give the tank to a specific player.
 */
Action Cmd_PassTank(int iClient, int args)
{
	if (!iClient) {
		return Plugin_Continue;
	}

	ShowPassMenu(iClient);

	return Plugin_Handled;
}

/**
 *
 */
void ShowPassMenu(int iClient)
{
	Menu hMenu = CreateMenu(HandlerPassMenu, MenuAction_Select|MenuAction_End);

	SetMenuTitle(hMenu, "%T", "PASS_MENU_TITLE", iClient);

	char sId[4], sName[32];

	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
	{
		if (!IsClientInGame(iPlayer)
		|| IsFakeClient(iPlayer)
		|| !IsClientInfected(iPlayer)
		|| !IsValidClass(GetClientClass(iPlayer))) {
			continue;
		}

		FormatEx(sId, sizeof(sId), "%d", iPlayer);
		FormatEx(sName, sizeof(sName), "%N", iPlayer);
		AddMenuItem(hMenu, sId, sName);
	}

	DisplayMenu(hMenu, iClient, -1);
}

/**
 *
 */
int HandlerPassMenu(Menu hMenu, MenuAction hAction, int iClient, int iItem)
{
	switch(hAction)
	{
		case MenuAction_End: CloseHandle(hMenu);

		case MenuAction_Select:
		{
			char sId[4]; GetMenuItem(hMenu, iItem, sId, sizeof(sId));

			int iTarget = StringToInt(sId);

			if (!iTarget || !IsClientInGame(iTarget))
			{
				ShowPassMenu(iClient);
				return 0;
			}

			if (!IsClientInfected(iTarget))
			{
				CPrintToChat(iClient, "%T%T", "TAG", iClient, "TARGET_NOT_INFECTED", iClient, iTarget);
				ShowPassMenu(iClient);
				return 0;
			}

			if (!IsValidClass(GetClientClass(iTarget)))
			{
				ShowPassMenu(iClient);
				return 0;
			}

			SetNextTank(iTarget);

			int iTank = FindClientTank();

			if (iTank != -1)
			{
				if (IsPlayerAlive(iTarget)) {
					ForcePlayerSuicide(iTarget);
				}

				L4D_ReplaceTank(iTank, iTarget);
			}
		}
	}

	return 0;
}

int FindClientTank()
{
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient)
		|| !IsClientInfected(iClient)
		|| GetClientClass(iClient) != SI_CLASS_TANK) {
			continue;
		}

		return iClient;
	}

	return -1;
}

/**
 * Infected team player?
 */
bool IsClientInfected(int iClient) {
	return (GetClientTeam(iClient) == TEAM_INFECTED);
}

/**
 * Get the zombie player class.
 */
int GetClientClass(int iClient) {
	return GetEntProp(iClient, Prop_Send, "m_zombieClass");
}

/**
 * The class is included in the pool of infected.
 */
bool IsValidClass(int iClass) {
	return (iClass >= SI_CLASS_SMOKER && iClass <= SI_CLASS_CHARGER);
}
