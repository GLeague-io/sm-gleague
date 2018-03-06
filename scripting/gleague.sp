#pragma semicolon 1

#define PLAYERSCOUNT 2
#define DEFAULT_LANGUAGE 22
#define VERSION "0.0.2prealpha"
#define STEAMID_SIZE 32
#define NICKNAME_SIZE 32

/* include assist scripts */
#include <sourcemod>
#include <cstrike>
#include <sdktools>

/* debug */
new bool:DEBUG = true;

/* database handler */
new Handle:db = INVALID_HANDLE;

int MatchID = -1;

/* players data storage */
new String:Match_SteamID[2][STEAMID_SIZE];
new String:Player_SteamID[10][STEAMID_SIZE];
new String:Player_Name[10][NICKNAME_SIZE];
new bool:Player_Connected[10] = false;
new Players_Indexes[10];
new Players_Connected = 0;
new Players_TeamID[10];
new Players_BelongsToTeam[2][10];

new int_ClientDecisionSelector = 0;


/* server cvars */
new Handle:cvar_mp_warmuptime = INVALID_HANDLE;
new Handle:cvar_team_name[2]  = INVALID_HANDLE;

/* match data */

bool bool_HasKnifeRoundStarted = false;
bool bool_PendingSwitchDecision = false;
bool bool_TeamsHasSwitched = false;

/* include gleague additional functions */
#include <gleague/enums>
#include <gleague/mysql>
#include <gleague/functions>







/*********************************************************
 *  plugin description
 *********************************************************/
public Plugin myinfo =
{
  name = "GLeague MM",
  author = "Stanislav 'glmn' Gelman",
  description = "An additional cs:go matchmaking system with own rankings by 'glmn'. From Russian for Russians w/ love :)",
  version = VERSION,
  url = "http://gleague.io/"
};

/*********************************************************
 *  event fire when plugin start
 *********************************************************/
public OnPluginStart()
{
  LoadTranslations("gleague.phrases.txt");

  cvar_mp_warmuptime = FindConVar("mp_warmuptime");
  cvar_team_name[0] = FindConVar("mp_teamname_2");
  cvar_team_name[1] = FindConVar("mp_teamname_1");

  SetConVarString(cvar_team_name[0], "AVA Gaming");
  SetConVarString(cvar_team_name[1], "Natus Vincere");

  /* Player event hooks */
  HookEvent("player_connect_full", Event_Player_Full_Connect, EventHookMode_Post);
  HookEvent("player_changename", Event_Player_Name);
  HookEvent("player_team", Event_Player_Team);

  /* Round event hooks */
  HookEvent("round_start", Event_Round_Start);
  HookEvent("round_end", Event_Round_End);

  /* Init MySQL connection and fill variables with data */
  MySQL_Connect();
  SetMatchID();
  GetMatchSteamIDs();

  if(DEBUG){ShowPlayersSteamIDs(Match_SteamID);} //Debug info

  UpdateMatchStatus(db, MatchID, "ready");

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
  new Handle:Datapack;

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

  if(Players_Connected > 0 && Players_Connected < PLAYERSCOUNT && enum_MatchState == MatchState_None)
  {
    ChangeState(MatchState_Warmup);
  }

  if(Players_Connected == 1 && enum_MatchState == MatchState_Warmup)
  {
    SetWarmupTime(10);
    ChangeState(MatchState_KnifeRound);
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
  new String:NewName[32];

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
  new Needle_TeamID;
  new New_TeamID;
  new Handle:Datapack;

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
  /* Set knife round */
  if(!IsWarmup() && enum_MatchState == MatchState_KnifeRound && !bool_HasKnifeRoundStarted){
    bool_HasKnifeRoundStarted = true;
    StartKnifeRound();
  }

  if(IsWarmup && enum_MatchState == MatchState_WaitingForKnifeRoundDecision && bool_PendingSwitchDecision)
  {
    HookEvent("player_say", Event_Player_Say);
  }
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
  new Winner = GetEventInt(event, "winner");
  char Winner_TeamName[32];

  if(Winner < 2) {return;}

  GetConVarString(cvar_team_name[Winner-2], Winner_TeamName, sizeof(Winner_TeamName));

  if(enum_MatchState == MatchState_KnifeRound && bool_HasKnifeRoundStarted){
    bool_HasKnifeRoundStarted = false;
    bool_PendingSwitchDecision = true;
    int_ClientDecisionSelector = Players_BelongsToTeam[Winner-2][0];

    PrintToChatAll(" \x01[GLeague.io] > \x01\x0B\x04 %t", "WinKnifeRound", Winner_TeamName);

    ChangeState(MatchState_WaitingForKnifeRoundDecision);
    ServerCommand("mp_warmup_start");
    SetWarmupTime(60);
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
  new String:text[20];
  new client = GetClientOfUserId(GetEventInt(event, "userid"));
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
