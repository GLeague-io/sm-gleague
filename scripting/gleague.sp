#pragma semicolon 1

#define PLAYERSCOUNT 4
#define DEFAULT_LANGUAGE 22
#define VERSION "0.0.4prealpha"
#define STEAMID_SIZE 32
#define NICKNAME_SIZE 32

/* debug */
bool DEBUG = true;

/* include assist scripts */
#include <sourcemod>
#include <cstrike>
#include <sdktools>

/* database handler */
Handle db = INVALID_HANDLE;

int MatchID = -1;

/* players data storage */
char Match_SteamID[4][STEAMID_SIZE];
char Player_SteamID[10][STEAMID_SIZE];
char Player_Name[10][NICKNAME_SIZE];
bool Player_Connected[10] = false;
int Players_Indexes[10];  
int Players_Connected = 0;
int Players_TeamID[10];
int Players_BelongsToTeam[2][10];
int int_ClientDecisionSelector = 0;

/* server cvars */
Handle cvar_mp_warmuptime = INVALID_HANDLE;
Handle cvar_mp_restartgame = INVALID_HANDLE;
Handle cvar_team_name[2]  = INVALID_HANDLE;

/* custom cvars */
ConVar g_cvar_knife_round; 

/* match data */
bool bool_HasKnifeRoundStarted = false;
bool bool_PendingSwitchDecision = false;
bool bool_TeamsHasSwitched = false;
bool bool_MatchLive = false;
int int_ServerRestartsCount = 3;

/* include gleague additional functions */
#include <gleague/enums>
#include <gleague/mysql>
#include <gleague/functions>

/*********************************************************
 *  plugin description
 *********************************************************/
public Plugin myinfo =
{
  name = "GLeague",
  author = "Stanislav 'glmn' Gelman",
  description = "An additional cs:go matchmaking system with own rankings. From Russian for Russians w/ love :)",
  version = VERSION,
  url = "http://gleague.io/"
};

/*********************************************************
 *  event fire when plugin start
 *********************************************************/
public OnPluginStart()
{
  LoadTranslations("gleague.phrases.txt");

  /* server cvars */
  cvar_mp_warmuptime = FindConVar("mp_warmuptime");
  cvar_mp_restartgame = FindConVar("mp_restartgame");
  cvar_team_name[0] = FindConVar("mp_teamname_2");
  cvar_team_name[1] = FindConVar("mp_teamname_1");

  SetConVarString(cvar_team_name[0], "AVA Gaming");
  SetConVarString(cvar_team_name[1], "Natus Vincere");

  /* custom cvars */
  g_cvar_knife_round = CreateConVar("gleague_knife_round", "1", "Knife round on/off");

  /* Player event hooks */
  HookEvent("player_connect_full", Event_Player_Full_Connect, EventHookMode_Post);
  HookEvent("player_changename", Event_Player_Name);
  HookEvent("player_team", Event_Player_Team);
  AddCommandListener(Command_JoinTeam, "jointeam");

  /* Round event hooks */
  HookEvent("round_start", Event_Round_Start);
  HookEvent("round_end", Event_Round_End);

  /* Init MySQL connection and fill variables with data */
  MySQL_Connect();
  SetMatchID();
  SetMatchSteamIDs();
  SetTeamNames();

  if(DEBUG){ShowPlayersSteamIDs(Match_SteamID);} //Debug info

  if(DEBUG){PrintToServer("[DB] > UpdateMatchStatus > ready");} //Debug info
  UpdateMatchStatus(db, "ready");


}

/*********************************************************
 *  event fire when client set his steam id
 * 
 * @param  Client     database handle
 * @param  SteamID      string
 * @noreturn
 *********************************************************/
public OnClientAuthorized(int client, const char[] steam_id)
{
  if(IsFakeClient(client) || StrEqual(steam_id, "BOT")) {return;}

  SetClientLanguage(client, DEFAULT_LANGUAGE);
  strcopy(Player_SteamID[client], 32, steam_id);
  if(DEBUG){PrintToServer("[Steam ID] > %s", Player_SteamID[client]);} //Debug info


  if(!FindSteamID(Player_SteamID[client])){
    KickClient(client, "%t", "NoAccess");
  }
}

/*********************************************************
 *  event fire when player fully connected to server
 * 
 * @param  Event      event handle
 * @param  Name       string
 * @param  Broadcast    boolean
 * @noreturn
 *********************************************************/
public Action:Event_Player_Full_Connect(Handle:event, const String:name[], bool:dontBroadcast)
{
  int TeamID;
  int client = GetClientOfUserId(GetEventInt(event, "userid"));
  Handle Datapack;

  if(IsFakeClient(client)) {return;}

  if(DEBUG){PrintToServer("[Event] (%s) > Event_Player_Full_Connect", Player_SteamID[client]);} //Debug info

  SetPlayerName(db, client, Player_SteamID[client]);
  SetPlayerData(db, client, Player_SteamID[client]);

  TeamID = Players_TeamID[client];
  if(bool_TeamsHasSwitched){
    TeamID = GetOtherTeam(Players_TeamID[client]);
  }

  CreateDataTimer(1.0, AssignPlayerTeam, Datapack);
  WritePackCell(Datapack, client);
  WritePackCell(Datapack, TeamID);

  if(DEBUG){ PrintToServer("[Team ID] (%s) > %i",Player_SteamID[client], TeamID); } //Debug info

  Player_Connected[client] = true;
  Players_Connected++; //increase connected players count

  if(DEBUG){PrintToServer("[Players] > Connected: %i", Players_Connected);} //Debug info

  UpdatePlayerStatus(db, MatchID, Player_SteamID[client], "connected");

  if(DEBUG){PrintToServer("[DB] (%s) > UpdatePlayerStatus > connected", Player_SteamID[client]);} //Debug info

  if(Players_Connected > 0 && Players_Connected < PLAYERSCOUNT && enum_MatchState == MatchState_None){
    ChangeState(MatchState_Warmup);
  }

  if(Players_Connected == 1 && enum_MatchState == MatchState_Warmup){
    SetWarmupTime(10);
    if(g_cvar_knife_round.IntValue){
      ChangeState(MatchState_KnifeRound);
    }else{
      ChangeState(MatchState_GoingLive);
    }
  }
}

/*********************************************************
 *  event fire when player want to change his name
 * 
 * @param  Event      event handle
 * @param  Name       string
 * @param  Broadcast    boolean
 * @noreturn
 *********************************************************/
public Event_Player_Name(Handle:event, const String:name[], bool:dontBroadcast)
{
  int client = GetClientOfUserId(GetEventInt(event, "userid"));
  char NewName[32];

  if(IsFakeClient(client)) {return;}
  GetEventString(event, "newname", NewName, sizeof(NewName));

  if(!StrEqual(NewName, Player_Name[client])){
    SetClientInfo(client, "name", Player_Name[client]);
  }
}

/*********************************************************
 *  event fire when player want to change team
 * 
 * @param  Event      event handle
 * @param  Name       string
 * @param  Broadcast    boolean
 * @noreturn
 *********************************************************/
public Event_Player_Team(Handle:event, const String:name[], bool:dontBroadcast)
{
  int client = GetClientOfUserId(GetEventInt(event, "userid"));
  int Needle_TeamID, New_TeamID;
  Handle Datapack;

  if(IsFakeClient(client) || !IsClientInGame(client) || !Player_Connected[client]){return;}

  if(bool_TeamsHasSwitched){return;}

  Needle_TeamID = Players_TeamID[client];
  New_TeamID = GetEventInt(event, "team");

  if(Needle_TeamID != New_TeamID){
    CreateDataTimer(1.0, AssignPlayerTeam, Datapack);
    WritePackCell(Datapack, client);
    WritePackCell(Datapack, Needle_TeamID);
  }
}

public Action Command_JoinTeam(int client, const char[] command, int argc)
{
  return Plugin_Stop;
}

/*********************************************************
 *  event fire when round starts
 * 
 * @param  Event      event handle
 * @param  Name       string
 * @param  Broadcast    boolean
 * @noreturn
 *********************************************************/
public Action Event_Round_Start(Event event, const char[] name, bool dontBroadcast)
{
  /* Set knife round state */
  if(ReadyForKnifeRound()){ StartKnifeRound(); }

  /* Set stay switch state */
  if(ReadyForStaySwitch()){ StartPendingStaySwitch(); }

  /* Set stay decision if missed */
  if(StaySwitchDecisionMissed()){ SetStayDecision(); }

  /* Make 3 restarts or change state to live */
  if(ReadyForLiveRestarts()){ StartPreLiveRestarts(); }

  /* Set live state */
  if(ReadyForLive()){ StartLive(); }
}

/*********************************************************
 *  event fire when round ends
 * 
 * @param  Event      event handle
 * @param  Name       string
 * @param  Broadcast    boolean
 * @noreturn
 *********************************************************/
public Event_Round_End(Handle:event, const String:name[], bool:dontBroadcast)
{
  int Winner = GetEventInt(event, "winner");
  int aliveCT = 0;
  int aliveT = 0;
  int healthCT = 0;
  int healthT = 0;
  char Winner_TeamName[32];

  if(Winner < 2) {return;}

  if(enum_MatchState == MatchState_KnifeRound && bool_HasKnifeRoundStarted){

    aliveCT = GetAlivePlayersPerTeam(3);
    aliveT = GetAlivePlayersPerTeam(2);
    healthCT = GetHealthPointsPerTeam(3);
    healthT = GetHealthPointsPerTeam(2);

    if(aliveCT > 0 && aliveT > 0){

      if(aliveCT > aliveT) { Winner = 3; }
      if(aliveCT < aliveT) { Winner = 2; }

      if(aliveCT == aliveT){
        if(healthCT > healthT) { Winner = 3; }
        if(healthCT < healthT) { Winner = 2; }
        if(healthCT == healthT) { Winner = 3; }
      }
    }


    PrintToChatAll("Alive. CT: %i T: %i | Health. CT: %i T: %i", aliveCT, aliveT, healthCT, healthT);

    GetConVarString(cvar_team_name[Winner-2], Winner_TeamName, sizeof(Winner_TeamName));

    bool_HasKnifeRoundStarted = false;
    bool_PendingSwitchDecision = true;
    int_ClientDecisionSelector = Players_BelongsToTeam[Winner-2][0];

    PrintToChatAll(" \x01[GLeague.io] > \x01\x0B\x04 %t", "WinKnifeRound", Winner_TeamName);

    ChangeState(MatchState_WaitingForKnifeRoundDecision);
    SetWarmupTime(60);
    CreateTimer(3.0, StartWarmup);
  }
}

/*********************************************************
 *  event fire when player say something to chat
 * 
 * @param  Event      event handle
 * @param  Name       string
 * @param  Broadcast    boolean
 * @noreturn
 *********************************************************/
public Event_Player_Say(Handle:event, const String:name[], bool:dontBroadcast)
{
  char text[20];
  int client = GetClientOfUserId(GetEventInt(event, "userid"));
  GetEventString(event, "text", text, sizeof(text));

  if(enum_MatchState == MatchState_WaitingForKnifeRoundDecision && bool_PendingSwitchDecision && client == int_ClientDecisionSelector){
    if(StrEqual(text,"!stay") || StrEqual(text,"!switch")){
      if(StrEqual(text,"!stay")){
        PrintToChatAll(" \x01[GLeague.io] > \x01\x0B\x04 Staying!");
      }
      else if(StrEqual(text,"!switch")){
        PrintToChatAll(" \x01[GLeague.io] > \x01\x0B\x04 Switching teams!");
        SwapTeams();
        SwitchTeamNames();
        bool_TeamsHasSwitched = true;
      }

      bool_PendingSwitchDecision = false;
      bool_HasKnifeRoundStarted = false;
      ChangeState(MatchState_GoingLive);
      UnhookEvent("player_say", Event_Player_Say);

      CreateTimer(0.5,EndWarmup);
    }
  }
}

/*********************************************************
 *  event fire when player disconnect from server
 * @param  Client     integer
 * @noreturn
 *********************************************************/
public OnClientDisconnect(int client)
{
  if(IsFakeClient(client) || !Player_Connected[client]) {return;}

  UpdatePlayerStatus(db, MatchID, Player_SteamID[client], "disconnected");
  if(DEBUG){PrintToServer("[DB] (%s)> UpdatePlayerStatus > disconnected",Player_SteamID[client]);} //Debug info

  Player_Name[client] = "";
  Player_SteamID[client] = "";
  Player_Connected[client] = false;
  Players_Connected--;

  if(DEBUG){PrintToServer("[Players] > Connected: %i", Players_Connected);} //Debug info
}
