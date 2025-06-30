#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <left4dhooks>
#include <vs_tank_queue>
#include <colors>


public Plugin myinfo =
{
    name        = "VersusTankQueueSpawnPass",
    author      = "TouchMe",
    description = "Allows you to select a player who will play as a tank",
    version     = "build0001",
    url         = "https://github.com/TouchMe-Inc/l4d2_vs_tank_queue"
}


#define TRANSLATIONS            "vs_tq_spawnpass.phrases"

#define MENU_TIME               10

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


Handle g_iClientPassTimer[MAXPLAYERS + 1] = {null, ...};

int g_iClientPassTimerTick[MAXPLAYERS + 1] = {MENU_TIME, ...};

/**
  * Called when the map starts loading.
  */
public void OnMapStart()
{
    for (int iClient = 1; iClient <= MaxClients; iClient ++)
    {
        g_iClientPassTimer[iClient] = null;
    }
}

public void OnPluginStart()
{
    // Load translations.
    LoadTranslations(TRANSLATIONS);

    // Event hooks.
    HookEvent("tank_spawn", Event_TankSpawn, EventHookMode_Post);
}

/**
 * Tank spawn event.
 */
void Event_TankSpawn(Event event, const char[] sEventName, bool bDontBroadcast)
{
    int iClient = GetClientOfUserId(GetEventInt(event, "userid"));

    if (iClient <= 0 || !IsClientInGame(iClient) || IsFakeClient(iClient)) {
        return;
    }

    g_iClientPassTimerTick[iClient] = MENU_TIME;
    g_iClientPassTimer[iClient] = CreateTimer(1.0, Timer_ShowPassMenu, iClient, .flags = TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
}

Action Timer_ShowPassMenu(Handle hTimer, int iClient)
{
    if (!IsClientInGame(iClient) || IsFakeClient(iClient) || !IsClientInfected(iClient)
    || GetInfectedClass(iClient) != SI_CLASS_TANK
    || g_iClientPassTimer[iClient] == null
    || g_iClientPassTimerTick[iClient] <= 0) {
        g_iClientPassTimer[iClient] = null;
        return Plugin_Stop;
    }

    ShowPassMenu(iClient);

    g_iClientPassTimerTick[iClient] --;

    return Plugin_Continue;
}

/**
 *
 */
void ShowPassMenu(int iClient)
{
    Menu hMenu = CreateMenu(HandlerPassMenu, MenuAction_Select|MenuAction_End);

    SetMenuTitle(hMenu, "%T", "MENU_TITLE_PASS", iClient, g_iClientPassTimerTick[iClient]);

    char szId[4], sName[64];

    FormatEx(szId, sizeof(szId), "%d", iClient);
    FormatEx(sName, sizeof(sName), "%T", "MENU_SKIP", iClient);
    AddMenuItem(hMenu, szId, sName);

    for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
    {
        if (!IsClientInGame(iPlayer) || IsFakeClient(iPlayer)
        || !IsClientInfected(iPlayer) || !IsValidClass(GetInfectedClass(iPlayer))
        || IsInfectedWithVictim(iClient)
        || iPlayer == iClient) {
            continue;
        }

        FormatEx(szId, sizeof(szId), "%d", iPlayer);
        FormatEx(sName, sizeof(sName), "%N", iPlayer);
        AddMenuItem(hMenu, szId, sName);
    }

    DisplayMenu(hMenu, iClient, 1);
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
            char szId[4]; GetMenuItem(hMenu, iItem, szId, sizeof(szId));

            int iTarget = StringToInt(szId);

            if (!iTarget || !IsClientInGame(iTarget)) {
                return 0;
            }

            if (iClient == iTarget)
            {
                g_iClientPassTimer[iClient] = null;
                return 0;
            }

            if (!IsClientInfected(iTarget) || !IsValidClass(GetInfectedClass(iTarget)) || IsInfectedWithVictim(iClient)) {
                return 0;
            }

            L4D_ReplaceTank(iClient, iTarget);
            g_iClientPassTimer[iClient] = null;
        }
    }

    return 0;
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
int GetInfectedClass(int iClient) {
    return GetEntProp(iClient, Prop_Send, "m_zombieClass");
}

/**
 * The class is included in the pool of infected.
 */
bool IsValidClass(int iClass) {
    return (iClass >= SI_CLASS_SMOKER && iClass <= SI_CLASS_CHARGER);
}

/**
 * Checks if the Infected client has a victim.
 *
 * @param iClient           The client identifier.
 *
 * @return                  true if the client has a victim, otherwise false.
 */
bool IsInfectedWithVictim(int iClient) {
    return GetEntProp(iClient, Prop_Send, "m_tongueVictim") > 0
    || GetEntProp(iClient, Prop_Send, "m_pounceVictim") > 0
    || GetEntProp(iClient, Prop_Send, "m_pummelVictim") > 0
    || GetEntProp(iClient, Prop_Send, "m_jockeyVictim") > 0
    || GetEntPropEnt(iClient, Prop_Send, "m_carryVictim") > 0;
}