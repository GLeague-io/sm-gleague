#pragma semicolon 1

#define PLAYERSCOUNT 2
#define DEFAULT_LANGUAGE 22
#define VERSION "0.0.1prealpha"
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
new String:Match_SteamIDs[PLAYERSCOUNT][STEAMID_SIZE];
new String:Players_SteamIDs[PLAYERSCOUNT][STEAMID_SIZE];
new String:Players_Names[PLAYERSCOUNT][NICKNAME_SIZE];
new bool:Players_Connected[PLAYERSCOUNT] = false;
new Players_TotalConnected = 0;

/* include gleague additional functions */
#include <gleague/enums>
#include <gleague/mysql>
#include <gleague/functions>

/* match data */
MatchState g_MatchState = MatchState_None;




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

  /* Event hooks */
  HookEvent("player_connect_full", Event_Player_Full_Connect, EventHookMode_Post);
  HookEvent("player_changename", Event_Player_Name);
  HookEvent("player_team", Event_Player_Team);

  /* Init MySQL connection and fill variables with data */
  MySQL_Connect();
  SetMatchID();
  GetMatchSteamIDs();

  if(DEBUG){ShowPlayersSteamIDs(Match_SteamIDs);} //Debug info

  UpdateMatchStatus(db, MatchID, "ready");

}

/*********************************************************
 *  event fire when client set his steam id
 * 
 * @param  Client			database handle
 * @param  SteamID			string
 * @noreturn
 *********************************************************/
public OnClientAuthorized(int client, const char[] steam_id)
{
  if(IsFakeClient(client)) {return;}

  SetClientLanguage(client, DEFAULT_LANGUAGE);
  strcopy(Players_SteamIDs[client], 32, steam_id);

  if(DEBUG){PrintToServer("[Steam ID] > %s", Players_SteamIDs[client]);} //Debug info

  if(!FindSteamID(Players_SteamIDs[client])){
    KickClient(client, "%t", "NoAccess");
  }
}

/*********************************************************
 *  event fire when player fully connected to server
 * 
 * @param  Event			event handle
 * @param  Name				string
 * @param  Broadcast		boolean
 * @noreturn
 *********************************************************/
public Action:Event_Player_Full_Connect(Handle:event, const String:name[], bool:dontBroadcast)
{
  int TeamID;
  int client = GetClientOfUserId(GetEventInt(event, "userid"));
  new Handle:Datapack;

  if(IsFakeClient(client)) {return;}

  if(DEBUG){PrintToServer("[Event] (%s) > Event_Player_Full_Connect", Players_SteamIDs[client]);} //Debug info

  SetPlayerName(db, client, Players_SteamIDs[client]);

  TeamID = GetPlayerTeamID(db, Players_SteamIDs[client]);

  CreateDataTimer(1.0, AssignPlayerTeam, Datapack);
  WritePackCell(Datapack, client);
  WritePackCell(Datapack, TeamID);

  if(DEBUG){ PrintToServer("[Team ID] (%s) > %i",Players_SteamIDs[client], TeamID); } //Debug info

  Players_Connected[client] = true;
  Players_TotalConnected++; //increase connected players count

  if(DEBUG){PrintToServer("[Players] > Connected: %i", Players_TotalConnected);} //Debug info

  UpdatePlayerStatus(db, MatchID, Players_SteamIDs[client], "connected");

  if(DEBUG){PrintToServer("[DB] (%s) > UpdatePlayerStatus > connected", Players_SteamIDs[client]);} //Debug info

  if(DEBUG){ PrintToServer("[Match State] > %s",g_MatchState); } //Debug info
  if(Players_TotalConnected > 0 && Players_TotalConnected < PLAYERSCOUNT && g_MatchState == MatchState_None)
  {
  	g_MatchState = MatchState_Warmup;
  	if(DEBUG){ PrintToServer("[Match State] > %s",g_MatchState); } //Debug info
  }
}

/*********************************************************
 *  event fire when player want to change his name
 * 
 * @param  Event			event handle
 * @param  Name				string
 * @param  Broadcast		boolean
 * @noreturn
 *********************************************************/
public Event_Player_Name(Handle:event, const String:name[], bool:dontBroadcast)
{
  int client = GetClientOfUserId(GetEventInt(event, "userid"));
  new String:NewName[32];

  if(IsFakeClient(client)) {return;}
  GetEventString(event, "newname", NewName, sizeof(NewName));

  if(!StrEqual(NewName, Players_Names[client])){
  	SetClientInfo(client, "name", Players_Names[client]);
  }
}

/*********************************************************
 *  event fire when player want to change team
 * 
 * @param  Event			event handle
 * @param  Name				string
 * @param  Broadcast		boolean
 * @noreturn
 *********************************************************/
public Event_Player_Team(Handle:event, const String:name[], bool:dontBroadcast)
{
  int client = GetClientOfUserId(GetEventInt(event, "userid"));
  new Handle:Datapack;

  if(IsFakeClient(client) || !IsClientInGame(client) || !Players_Connected[client]){return;}


  new Needle_TeamID = GetPlayerTeamID(db, Players_SteamIDs[client]);
  new New_TeamID = GetEventInt(event, "team");

  if(Needle_TeamID != New_TeamID){
  	CreateDataTimer(1.0, AssignPlayerTeam, Datapack);
  	WritePackCell(Datapack, client);
  	WritePackCell(Datapack, Needle_TeamID);
  }
}

/*********************************************************
 *  event fire when player disconnect from server
 * @param  Client			integer
 * @noreturn
 *********************************************************/
public OnClientDisconnect(int client)
{
  if(IsFakeClient(client) || !Players_Connected[client]) {return;}

  UpdatePlayerStatus(db, MatchID, Players_SteamIDs[client], "disconnected");
  if(DEBUG){PrintToServer("[DB] (%s)> UpdatePlayerStatus > disconnected",Players_SteamIDs[client]);} //Debug info

  Players_Names[client] = "";
  Players_SteamIDs[client] = "";
  Players_Connected[client] = false;
  Players_TotalConnected--;

  if(DEBUG){PrintToServer("[Players] > Connected: %i", Players_TotalConnected);} //Debug info
}