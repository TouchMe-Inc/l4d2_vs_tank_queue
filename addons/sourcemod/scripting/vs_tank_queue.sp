#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <left4dhooks>
#include <colors>


public Plugin myinfo =
{
    name        = "VersusTankQueue",
    author      = "TouchMe",
    description = "Determines the player who will play as the tank",
    version     = "build0004",
    url         = "https://github.com/TouchMe-Inc/l4d2_vs_tank_queue"
}


#define TRANSLATIONS            "vs_tank_queue.phrases"
#define INVALID_TANK            -1

/*
 * Gamemode.
 */
#define GAMEMODE_VERSUS         "versus"
#define GAMEMODE_VERSUS_REALISM "mutation12"

/*
 * Infected Class.
 */
#define SI_CLASS_TANK           8

/*
 * Team.
 */
#define TEAM_SPECTATOR          1
#define TEAM_SURVIVOR           2
#define TEAM_INFECTED           3

/*
 * Ticket for change tank control.
 */
#define TANK_TICKET_MAX         20000
#define TANK_TICKET_MIN         0

/*
 * Sugar for left4dhooks.
 */
#define ReplaceTank             L4D_ReplaceTank
#define SetTankTickets          L4D2Direct_SetTankTickets
#define SetTankPassedCount      L4D2Direct_SetTankPassedCount
#define GetTankPassedCount      L4D2Direct_GetTankPassedCount
#define GetVSCampaignScore      L4D2Direct_GetVSCampaignScore
#define OnSpawnTank_Post        L4D_OnSpawnTank_Post
#define OnTryOfferingTankBot    L4D_OnTryOfferingTankBot
#define OnTankPassControl       L4D2_OnTankPassControl

/*
 * Native errors.
 */
#define ERR_INVALID_INDEX       "Invalid client index %d"


int g_iNextTank = INVALID_TANK;

bool
    g_bGamemodeAvailable = false,
    g_bRoundIsLive = false
;

int g_iLastTankFrustration = -1;
float g_fTankGrace = 0.0;

char g_szWhoHadTankSteamId[64];
StringMap g_smWhoHadTank = null;

ConVar g_cvGameMode = null;


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

    // Natives.
    CreateNative("GetNextTank", Native_GetNextTank);
    CreateNative("SetNextTank", Native_SetNextTank);
    CreateNative("IsNextTank", Native_IsNextTank);
    CreateNative("HasNextTank", Native_HasNextTank);
    CreateNative("IsWhoHadTank", Native_IsWhoHadTank);
    CreateNative("IsWhoHadTankWithMap", Native_IsWhoHadTankWithMap);

    // Library.
    RegPluginLibrary("vs_tank_queue");

    return APLRes_Success;
}

/**
 * Returns next tank.
 *
 * @param hPlugin           Handle to the plugin.
 * @param iParams           Number of parameters.
 * @return                  Return client index or -1.
 */
int Native_GetNextTank(Handle hPlugin, int iParams) {
    return GetNextTank();
}

/**
 * Returns next tank.
 *
 * @param hPlugin           Handle to the plugin.
 * @param iParams           Number of parameters.
 */
int Native_SetNextTank(Handle hPlugin, int iParams)
{
    int iClient = GetNativeCell(1);

    if (!IsValidClient(iClient)) {
        return ThrowNativeError(SP_ERROR_NATIVE, ERR_INVALID_INDEX, iClient);
    }

    SetNextTank(iClient);

    return 0;
}

/**
 * Returns next tank.
 */
int Native_IsNextTank(Handle hPlugin, int iParams)
{
    int iClient = GetNativeCell(1);

    if (!IsValidClient(iClient)) {
        return ThrowNativeError(SP_ERROR_NATIVE, ERR_INVALID_INDEX, iClient);
    }

    return IsNextTank(iClient);
}

/**
 * Returns next tank.
 */
int Native_HasNextTank(Handle hPlugin, int iParams) {
    return HasNextTank();
}

/**
 * Is who had tank.
 */
int Native_IsWhoHadTank(Handle hPlugin, int iParams)
{
    int iClient = GetNativeCell(1);

    if (!IsValidClient(iClient)) {
        return ThrowNativeError(SP_ERROR_NATIVE, ERR_INVALID_INDEX, iClient);
    }

    return IsWhoHadTank(iClient);
}

/**
 * Is who had tank with map.
 */
int Native_IsWhoHadTankWithMap(Handle hPlugin, int iParams)
{
    int iClient = GetNativeCell(1);

    if (!IsValidClient(iClient)) {
        return ThrowNativeError(SP_ERROR_NATIVE, ERR_INVALID_INDEX, iClient);
    }

    char szSteamId[64];
    GetClientAuthId(iClient, AuthId_Steam2, szSteamId, sizeof(szSteamId));

    char szMapName[32];
    bool bIsWhoTank = g_smWhoHadTank.GetString(szSteamId, szMapName, sizeof szMapName);

    SetNativeString(2, szMapName, GetNativeCell(3), true);

    return bIsWhoTank;
}


public void OnPluginStart()
{
    // Load translations.
    LoadTranslations(TRANSLATIONS);

    // Check Gamemode.
    HookConVarChange(g_cvGameMode = FindConVar("mp_gamemode"), OnGamemodeChanged);
    char szGameMode[16]; GetConVarString(g_cvGameMode, szGameMode, sizeof szGameMode);
    g_bGamemodeAvailable = IsVersusMode(szGameMode);

    // Event hooks.
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("player_left_start_area", Event_LeftStartArea, EventHookMode_PostNoCopy);
    HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
    HookEvent("player_bot_replace", Event_PlayerBotReplace, EventHookMode_Pre);

    // Player Commands.
    RegConsoleCmd("sm_boss", Cmd_WhoTank, "Shows who is becoming the tank");
    RegConsoleCmd("sm_tank", Cmd_WhoTank, "Shows who is becoming the tank");

    g_smWhoHadTank = new StringMap();
}

/**
 * Called when a console variable value is changed.
 */
void OnGamemodeChanged(ConVar hConVar, const char[] sOldGameMode, const char[] sNewGameMode) {
    g_bGamemodeAvailable = IsVersusMode(sNewGameMode);
}

public void OnMapStart()
{
    if (IsNewGame()) {
        g_smWhoHadTank.Clear();
    }
}

/**
 * Round start event.
 */
void Event_RoundStart(Event event, const char[] sName, bool bDontBroadcast)
{
    g_bRoundIsLive = false;
    g_iNextTank = INVALID_TANK;
    g_szWhoHadTankSteamId[0] = '\0';
    g_iLastTankFrustration = -1;

    if (IsNewGame()) {
        
    }
}

/**
 * Round start event.
 */
void Event_LeftStartArea(Event event, const char[] sName, bool bDontBroadcast)
{
    if (!g_bGamemodeAvailable) {
        return;
    }

    g_bRoundIsLive = true;

    if (!HasNextTank()) {
        SetNextTank(FindNextTank());
    }

    PrintNextTankAll();
}

/**
 * Round end event.
 */
void Event_RoundEnd(Event event, const char[] sName, bool bDontBroadcast)
{
    if (!g_bGamemodeAvailable) {
        return;
    }

    if (!IsRoundStarted()) {
        return;
    }

    if (g_szWhoHadTankSteamId[0] != '\0')
    {
        char szMapName[32];
        GetCurrentMap(szMapName, sizeof szMapName);
        g_smWhoHadTank.SetString(g_szWhoHadTankSteamId, szMapName);
    }

    g_bRoundIsLive = false;
    g_iNextTank = INVALID_TANK;
}

/**
 * When the queued tank switches teams, choose a new one.
 * Called before player change his team.
 */
void Event_PlayerTeam(Event event, char[] szEventName, bool bDontBroadcast)
{
    if (!g_bGamemodeAvailable) {
        return;
    }

    if (!IsRoundStarted()) {
        return;
    }

    int iClient = GetClientOfUserId(GetEventInt(event, "userid"));

    if (iClient <= 0 || IsFakeClient(iClient)) {
        return;
    }

    if (!HasNextTank() && GetEventInt(event, "team") == TEAM_INFECTED)
    {
        RequestFrame(Frame_ResetNextTank);
        return;
    }

    if (IsNextTank(iClient)) {
        RequestFrame(Frame_ResetNextTank);
    }

    if (IsClientTank(iClient) && GetEventInt(event, "oldteam") == TEAM_INFECTED)
    {
        g_iLastTankFrustration = GetTankFrustration(iClient);
        g_fTankGrace = CTimer_GetRemainingTime(GetFrustrationTimer(iClient));

        // Slight fix due to the timer seemingly always getting stuck between 0.5s~1.2s even after Grace period has passed.
        // CTimer_IsElapsed still returns false as well.
        if (g_fTankGrace < 0.0 || g_iLastTankFrustration < 100)  {
            g_fTankGrace = 0.0;
        }
    }
}

/**
 *
 */
void Frame_ResetNextTank()
{
    SetNextTank(FindNextTank());
    PrintNextTankAll();
}

/**
 *
 */
void Event_PlayerDeath(Event event, const char[] szEventName, bool bDontBroadcast)
{
    if (!g_bGamemodeAvailable) {
        return;
    }

    int iVictim = GetClientOfUserId(GetEventInt(event, "userid"));

    if (iVictim <= 0 || !IsClientInGame(iVictim)
    || !IsClientInfected(iVictim) || !IsClientTank(iVictim)) {
        return;
    }

    g_iLastTankFrustration = -1;
    SetNextTank(FindNextTank());
}

/**
 *
 */
public void OnSpawnTank_Post(int iTank, const float vecPos[3], const float vecAng[3])
{
    if (!g_bGamemodeAvailable) {
        return;
    }

    int iNextTank = GetNextTank();

    if (!IsValidClient(iNextTank) || !IsClientConnected(iNextTank) || !IsClientInfected(iNextTank)) {
        SetNextTank(iNextTank = FindNextTank());
    }

    if (iNextTank != INVALID_TANK)
    {
        ForceClientTank(iNextTank);
        GetClientAuthId(iNextTank, AuthId_Steam2, g_szWhoHadTankSteamId, sizeof g_szWhoHadTankSteamId);

        if (L4D_IsMissionFinalMap() && !g_smWhoHadTank.ContainsKey(g_szWhoHadTankSteamId))
        {
            char szMapName[32];
            GetCurrentMap(szMapName, sizeof szMapName);
            g_smWhoHadTank.SetString(g_szWhoHadTankSteamId, szMapName);
        }
    }
}

public void OnTankPassControl(int iOldTank, int iNewTank, int iPassCount)
{
    /**
     * As the Player switches to AI on disconnect/team switch, we have to make sure we're only checking this if the old Tank was AI.
     * Then apply the previous' Tank's Frustration and Grace Period (if it still had Grace)
     * We'll also be keeping the same Tank pass, which resolves Tanks that dc on 1st pass resulting into the Tank instantly going to 2nd pass.
     */
    if (g_iLastTankFrustration != -1 && IsFakeClient(iOldTank))
    {
        SetTankFrustration(iNewTank, g_iLastTankFrustration);
        CTimer_Start(GetFrustrationTimer(iNewTank), g_fTankGrace);
        L4D2Direct_SetTankPassedCount(L4D2Direct_GetTankPassedCount() - 1);
    }
}

/**
 *
 */
public Action OnTryOfferingTankBot(int iTank, bool &bEnterStatis)
{
    if (!g_bGamemodeAvailable) {
        return Plugin_Continue;
    }

    if (IsFakeClient(iTank)) {
        return Plugin_Continue;
    }

    SetTankFrustration(iTank, 100);
    SetTankPassedCount(GetTankPassedCount() + 1);

    return Plugin_Handled;
}

/**
 *
 */
public void Event_PlayerBotReplace(Event event, const char[] szEventName, bool bDontBroadcast)
{
    if (!g_bGamemodeAvailable) {
        return;
    }

    int iPlayer = GetClientOfUserId(GetEventInt(event, "player"));

    if (!IsClientInGame(iPlayer) || !IsClientInfected(iPlayer)|| !IsClientTank(iPlayer)) {
        return;
    }

    if (GetTankPassedCount() == 1)
    {
        int iBot = GetClientOfUserId(GetEventInt(event, "bot"));

        DataPack hPack;
        CreateDataTimer(0.1, Timer_RecontrolTank, hPack, TIMER_FLAG_NO_MAPCHANGE);
        WritePackCell(hPack, iPlayer);
        WritePackCell(hPack, iBot);
    }
}

/**
 *
 */
Action Timer_RecontrolTank(Handle hTimer, Handle hPack)
{
    ResetPack(hPack);

    int iPlayer = ReadPackCell(hPack);
    int iBot = ReadPackCell(hPack);

    if (IsClientInGame(iPlayer) && !IsFakeClient(iPlayer)
        && IsClientInfected(iPlayer) && !IsClientTank(iPlayer))
    {
        ReplaceTank(iBot, iPlayer);
        SetTankFrustration(iPlayer, 100);
        SetTankPassedCount(GetTankPassedCount() + 1);
        CTimer_Start(GetFrustrationTimer(iPlayer), 0.0);
    }

    return Plugin_Stop;
}

/**
 * When a player wants to find out whos becoming tank,
 * output to them.
 */
Action Cmd_WhoTank(int iClient, int args)
{
    if (!iClient) {
        return Plugin_Continue;
    }

    if (!g_bGamemodeAvailable) {
        return Plugin_Continue;
    }

    if (!IsClientInfected(iClient)) {
        return Plugin_Handled;
    }

    PrintNextTank(iClient);

    return Plugin_Handled;
}

/**
 *
 */
int GetRandomInfectedPlayer(bool bWithoutWhoHadTank)
{
    int iTotalPlayers = 0;
    int[] iPlayers = new int[MaxClients];

    for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
    {
        if (!IsClientInGame(iPlayer) || IsFakeClient(iPlayer)
        || !IsClientInfected(iPlayer)
        || (bWithoutWhoHadTank && IsWhoHadTank(iPlayer))) {
            continue;
        }

        iPlayers[iTotalPlayers++] = iPlayer;
    }

    if (!iTotalPlayers) {
        return -1;
    }

    return iPlayers[GetRandomInt(0, iTotalPlayers - 1)];
}

/**
 *
 */
bool IsWhoHadTank(int iClient)
{
    char szSteamId[64];
    GetClientAuthId(iClient, AuthId_Steam2, szSteamId, sizeof(szSteamId));

    return (g_smWhoHadTank.ContainsKey(szSteamId));
}

/**
 *
 */
int FindNextTank()
{
    int iNextTank = GetRandomInfectedPlayer(.bWithoutWhoHadTank = true);

    if (iNextTank == INVALID_TANK) {
        return GetRandomInfectedPlayer(.bWithoutWhoHadTank = false);
    }

    return iNextTank;
}

/**
 *
 */
void SetTankFrustration(int iClient, int iFrustration) {
    SetEntProp(iClient, Prop_Send, "m_frustration", 100 - iFrustration);
}

int GetTankFrustration(int iClient) {
    return 100 - GetEntProp(iClient, Prop_Send, "m_frustration");
}

/**
 *
 */
bool IsNextTank(int iClient) {
    return g_iNextTank == iClient;
}

/**
 *
 */
void SetNextTank(int iClient) {
    g_iNextTank = iClient;
}

/**
 *
 */
int GetNextTank() {
    return g_iNextTank;
}

/**
 *
 */
bool HasNextTank() {
    return g_iNextTank != INVALID_TANK;
}

/**
 * Output who will become tank for player.
 */
void PrintNextTank(int iClient)
{
    if (HasNextTank()) {
        CPrintToChat(iClient, "%T%T", "TAG", iClient, "HAS_NEXT_TANK", iClient, GetNextTank());
    } else {
        CPrintToChat(iClient, "%T%T", "TAG", iClient, "NO_TANK", iClient);
    }
}

/**
 * Output who will become tank for all.
 */
void PrintNextTankAll()
{
    for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
    {
        if (!IsClientInGame(iPlayer) || !IsClientInfected(iPlayer)) {
            continue;
        }

        PrintNextTank(iPlayer);
    }
}

/**
 *
 */
void ForceClientTank(int iClient)
{
    for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
    {
        if (!IsClientInGame(iPlayer) || !IsClientInfected(iPlayer)) {
            continue;
        }

        SetTankTickets(iPlayer, (iClient == iPlayer) ? TANK_TICKET_MAX : TANK_TICKET_MIN);
    }
}

bool IsNewGame()
{
    int iScoreTeamA = GetVSCampaignScore(0);
    int iScoreTeamB = GetVSCampaignScore(1);

    return (iScoreTeamA == 0 && iScoreTeamB == 0);
}

/**
 * Returns whether an entity is a player.
 */
bool IsRoundStarted() {
    return g_bRoundIsLive;
}

CountdownTimer GetFrustrationTimer(int client)
{
    static int s_iOffs_m_frustrationTimer = -1;

    if (s_iOffs_m_frustrationTimer == -1)
        s_iOffs_m_frustrationTimer = FindSendPropInfo("CTerrorPlayer", "m_frustration") + 4;

    return view_as<CountdownTimer>(GetEntityAddress(client) + view_as<Address>(s_iOffs_m_frustrationTimer));
}

/**
 * Returns whether an entity is a player.
 */
bool IsValidClient(int iClient) {
    return (iClient > 0 && iClient <= MaxClients);
}

/**
 * Returns whether the player is infected.
 */
bool IsClientInfected(int iClient) {
    return (GetClientTeam(iClient) == TEAM_INFECTED);
}

/**
 *
 */
bool IsClientTank(int iClient) {
    return (GetInfectedClass(iClient) == SI_CLASS_TANK);
}

/**
 * Gets the client L4D1/L4D2 zombie class id.
 *
 * @param client     Client index.
 * @return 	         1=SMOKER, 2=BOOMER, 3=HUNTER, 4=SPITTER, 5=JOCKEY, 6=CHARGER, 7=WITCH, 8=TANK, 9=NOT INFECTED
 */
int GetInfectedClass(int iClient) {
    return GetEntProp(iClient, Prop_Send, "m_zombieClass");
}

/**
 * Is the gamemode versus.
 *
 * @param szGameMode         A string containing the name of the game mode.
 *
 * @return                  Returns true if verus, otherwise false.
 */
bool IsVersusMode(const char[] szGameMode)
{
    return (StrEqual(szGameMode, GAMEMODE_VERSUS, false) || StrEqual(szGameMode, GAMEMODE_VERSUS_REALISM, false));
}
