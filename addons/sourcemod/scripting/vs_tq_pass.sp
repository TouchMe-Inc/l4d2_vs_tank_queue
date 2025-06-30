#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <vs_tank_queue>
#include <colors>


public Plugin myinfo =
{
    name        = "VersusTankQueuePass",
    author      = "TouchMe",
    description = "Allows you to select a player who will play as a tank",
    version     = "build0001",
    url         = "https://github.com/TouchMe-Inc/l4d2_vs_tank_queue"
}


#define TRANSLATIONS            "vs_tq_pass.phrases"

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
    RegConsoleCmd("sm_passtank", Cmd_PassTank, "Gives the tank to a selected player");
}

/**
 * Give the tank to a specific player.
 */
Action Cmd_PassTank(int iClient, int args)
{
    if (!iClient) {
        return Plugin_Continue;
    }

    if (!IsNextTank(iClient))
    {
        CPrintToChat(iClient, "%T%T", "TAG", iClient, "ONLY_TANK", iClient);
        return Plugin_Handled;
    }

    ShowPassMenu(iClient);

    return Plugin_Handled;
}

/**
 *
 */
void ShowPassMenu(int iClient)
{
    Menu menu = CreateMenu(HandlerPassMenu, MenuAction_Select|MenuAction_End);

    menu.SetTitle("%T", "PASS_MENU_TITLE", iClient);

    char szId[4], szBuffer[64];
    char szMapName[32];

    for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
    {
        if (!IsClientInGame(iPlayer)
        || IsFakeClient(iPlayer)
        || !IsClientInfected(iPlayer)
        || iPlayer == iClient) {
            continue;
        }

        FormatEx(szId, sizeof szId, "%d", iPlayer);

        bool bIsWhoHadTank = IsWhoHadTankWithMap(iPlayer, szMapName, sizeof szMapName);

        if (bIsWhoHadTank) {
            FormatEx(szBuffer, sizeof szBuffer, "%N [%s]", iPlayer, szMapName);
        } else {
            FormatEx(szBuffer, sizeof szBuffer, "%N", iPlayer);
        }

        menu.AddItem(szId, szBuffer, bIsWhoHadTank ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
    }

    menu.Display(iClient, MENU_TIME_FOREVER);
}

/**
 *
 */
int HandlerPassMenu(Menu menu, MenuAction action, int iClient, int iItem)
{
    switch (action)
    {
        case MenuAction_End: delete menu;

        case MenuAction_Select:
        {
            char szId[4]; GetMenuItem(menu, iItem, szId, sizeof(szId));

            int iTarget = StringToInt(szId);

            if (!iTarget || !IsClientInGame(iTarget)) {
                return 0;
            }

            if (!IsClientInfected(iTarget))
            {
                CPrintToChat(iClient, "%T%T", "TAG", iClient, "TARGET_NOT_INFECTED", iClient, iTarget);
                return 0;
            }

            SetNextTank(iTarget);

            for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
            {
                if (!IsClientInGame(iPlayer) || !IsClientInfected(iPlayer)) {
                    continue;
                }

                CPrintToChat(iPlayer, "%T%T", "TAG", iPlayer, "PASSED_TANK", iPlayer, iClient, iTarget);
            }
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
