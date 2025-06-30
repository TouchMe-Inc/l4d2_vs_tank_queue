#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <vs_tank_queue>
#include <nativevotes_rework>
#include <colors>


public Plugin myinfo =
{
    name 		= "VersusTankQueueVotepass",
    author 		= "TouchMe",
    description = "The plugin creates a vote for choosing a tank",
    version 	= "build0003",
    url 		= "https://github.com/TouchMe-Inc/l4d2_vs_tank_queue"
}


#define TRANSLATIONS            "vs_tq_votepass.phrases"

/*
 * Gamemode.
 */
#define GAMEMODE_VERSUS         "versus"
#define GAMEMODE_VERSUS_REALISM "mutation12"

/*
 * Team.
 */
#define TEAM_INFECTED           3

#define VOTE_TIME               15

bool
    g_bGamemodeAvailable = false,
    g_bRoundIsLive = false
;

int g_iVoteTarget = 0;

ConVar
    g_cvGameMode = null,
    g_cvCanPassInRound = null
;


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

/**
  * Called when the map starts loading.
  */
public void OnMapStart() {
    g_bRoundIsLive = false;
}

public void OnPluginStart()
{
    // Load translations.
    LoadTranslations(TRANSLATIONS);

    // Check Gamemode.
    HookConVarChange(g_cvGameMode = FindConVar("mp_gamemode"), OnGamemodeChanged);
    char sGameMode[16]; GetConVarString(g_cvGameMode, sGameMode, sizeof(sGameMode));
    g_bGamemodeAvailable = IsVersusMode(sGameMode);

    g_cvCanPassInRound = CreateConVar("sm_tq_votepass_can_pass_in_round", "0");

    // Event hooks.
    HookEvent("player_left_start_area", Event_LeftStartArea, EventHookMode_PostNoCopy);
    HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);

    // Player Commands.
    RegConsoleCmd("sm_votepass", Cmd_VotePass, "Shows who is becoming the tank.");
}

/**
 * Called when a console variable value is changed.
 */
void OnGamemodeChanged(ConVar hConVar, const char[] sOldGameMode, const char[] sNewGameMode) {
    g_bGamemodeAvailable = IsVersusMode(sNewGameMode);
}

/**
 * Called when the map has loaded, servercfgfile (server.cfg) has been executed, and all
 * plugin configs are done executing. This will always be called once and only once per map.
 * It will be called after OnMapStart().
*/
public void OnConfigsExecuted()
{
    char sGameMode[16]; GetConVarString(g_cvGameMode, sGameMode, sizeof(sGameMode));
    g_bGamemodeAvailable = IsVersusMode(sGameMode);
}

/**
 * Round start event.
 */
void Event_LeftStartArea(Event event, const char[] szEventName, bool bDontBroadcast)
{
    if (!g_bGamemodeAvailable) {
        return;
    }

    g_bRoundIsLive = true;
}

/**
 * Round end event.
 */
void Event_RoundEnd(Event event, const char[] szEventName, bool bDontBroadcast)
{
    if (!g_bGamemodeAvailable) {
        return;
    }

    g_bRoundIsLive = false;
}

/**
 * When a player wants to find out whos becoming tank,
 * output to them.
 */
Action Cmd_VotePass(int iClient, int args)
{
    if (!g_bGamemodeAvailable) {
        return Plugin_Continue;
    }

    if (iClient <= 0 || !IsClientInfected(iClient)) {
        return Plugin_Handled;
    }

    if (IsRoundStarted() && !GetConVarBool(g_cvCanPassInRound))
    {
        CPrintToChat(iClient, "%T%T", "TAG", iClient, "ROUND_STARTED", iClient);
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
    Menu hMenu = CreateMenu(HandlerPassMenu, MenuAction_Select|MenuAction_End);

    SetMenuTitle(hMenu, "%T", "PASS_MENU_TITLE", iClient);

    char szId[4], szBuffer[64];
    char szMapName[32];

    for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
    {
        if (!IsClientInGame(iPlayer)
        || IsFakeClient(iPlayer)
        || !IsClientInfected(iPlayer)) {
            continue;
        }

        FormatEx(szId, sizeof szId, "%d", iPlayer);

        bool bIsWhoHadTank = IsWhoHadTankWithMap(iPlayer, szMapName, sizeof szMapName);

        if (bIsWhoHadTank) {
            FormatEx(szBuffer, sizeof szBuffer, "%N [%s]", iPlayer, szMapName);
        } else {
            FormatEx(szBuffer, sizeof szBuffer, "%N", iPlayer);
        }

        AddMenuItem(hMenu, szId, szBuffer, bIsWhoHadTank ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
    }

    DisplayMenu(hMenu, iClient, MENU_TIME_FOREVER);
}

/**
 *
 */
int HandlerPassMenu(Menu hMenu, MenuAction action, int iClient, int iItem)
{
    switch (action)
    {
        case MenuAction_End: delete hMenu;

        case MenuAction_Select:
        {
            if (IsRoundStarted() && !GetConVarBool(g_cvCanPassInRound))
            {
                CPrintToChat(iClient, "%T%T", "TAG", iClient, "ROUND_STARTED", iClient);
                return 0;
            }

            char szId[4]; GetMenuItem(hMenu, iItem, szId, sizeof(szId));

            int iTarget = StringToInt(szId);

            if (!iTarget || !IsClientInGame(iTarget)) {
                return 0;
            }

            if (!IsClientInfected(iTarget))
            {
                CPrintToChat(iClient, "%T%T", "TAG", iClient, "TARGET_NOT_INFECTED", iClient, iTarget);
                return 0;
            }

            RunVotePass(iClient, iTarget);
        }
    }

    return 0;
}

void RunVotePass(int iClient, int iTarget)
{
    if (!NativeVotes_IsNewVoteAllowed())
    {
        CPrintToChat(iClient, "%T%T", "TAG", iClient, "VOTE_COULDOWN", iClient, NativeVotes_CheckVoteDelay());
        return;
    }

    int iTotalPlayers;
    int[] iPlayers = new int[MaxClients];

    for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
    {
        if (!IsClientInGame(iPlayer) || IsFakeClient(iPlayer) || !IsClientInfected(iPlayer)) {
            continue;
        }

        iPlayers[iTotalPlayers++] = iPlayer;
    }

    g_iVoteTarget = iTarget;

    NativeVote hVote = new NativeVote(HandlerVote, NativeVotesType_Custom_YesNo);
    hVote.Initiator = iClient;
    hVote.Team = TEAM_INFECTED;
    hVote.DisplayVote(iPlayers, iTotalPlayers, VOTE_TIME);
}

/**
 * Called when a vote action is completed.
 *
 * @param hVote             The vote being acted upon.
 * @param tAction           The action of the vote.
 * @param iParam1           First action parameter.
 * @param iParam2           Second action parameter.
 */
Action HandlerVote(NativeVote hVote, VoteAction tAction, int iParam1, int iParam2)
{
    switch (tAction)
    {
        case VoteAction_Display:
        {
            char sVoteDisplayMessage[128];

            FormatEx(sVoteDisplayMessage, sizeof(sVoteDisplayMessage), "%T", "VOTE_TITLE", iParam1, g_iVoteTarget);

            hVote.SetDetails(sVoteDisplayMessage);

            return Plugin_Changed;
        }

        case VoteAction_Cancel: hVote.DisplayFail();

        case VoteAction_Finish:
        {
            if (iParam1 == NATIVEVOTES_VOTE_NO
            || !IsClientConnected(g_iVoteTarget)
            || !IsClientInfected(g_iVoteTarget))
            {
                hVote.DisplayFail();

                return Plugin_Continue;
            }

            SetNextTank(g_iVoteTarget);

            for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
            {
                if (!IsClientInGame(iPlayer) || !IsClientInfected(iPlayer)) {
                    continue;
                }

                CPrintToChat(iPlayer, "%T%T", "TAG", iPlayer, "PASSED_TANK", iPlayer, g_iVoteTarget);
            }

            hVote.DisplayPass();
        }

        case VoteAction_End: hVote.Close();
    }

    return Plugin_Continue;
}

bool IsRoundStarted() {
    return g_bRoundIsLive;
}

/**
 * Infected team player?
 */
bool IsClientInfected(int iClient) {
    return (GetClientTeam(iClient) == TEAM_INFECTED);
}

/**
 * Is the game mode versus.
 *
 * @param sGameMode         A string containing the name of the game mode.
 *
 * @return                  Returns true if verus, otherwise false.
 */
bool IsVersusMode(const char[] sGameMode)
{
    return (StrEqual(sGameMode, GAMEMODE_VERSUS, false)
        || StrEqual(sGameMode, GAMEMODE_VERSUS_REALISM, false));
}
