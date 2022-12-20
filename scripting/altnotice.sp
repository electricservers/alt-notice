#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <discord>
#include <sourcebanspp>
#include <autoexecconfig>

#define PLUGIN_VERSION "1.1"

Database g_DB;
ConVar g_cvWebhook;
ConVar g_cvEmbedColor;
char g_cWebhook[512];
char g_cEmbedColor[32];

enum struct PlayerInfo {
	char Name[32];
	char SteamID[32];
	char IP[16];
	int BanTime;
	ArrayList AltsFound;
}

public Plugin myinfo = 
{
	name = "Alt Notice", 
	author = "ampere", 
	description = "Detects alt accounts of banned people picked up by WhoIs and noticed them via Discord.", 
	version = PLUGIN_VERSION, 
	url = "https://electricservers.com.ar"
};

public void OnAllPluginsLoaded() {
	if (!LibraryExists("whois")) {
		SetFailState("This plugin depends on the WhoIs plugin. Please install it first.\nhttps://github.com/maxijabase/sm-whois");
	}
}

public void OnPluginStart() {
	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_SetFile("altnotice");
		
	g_cvWebhook = AutoExecConfig_CreateConVar("sm_altnotice_webhook", "", "Discord webhook.");
	
	g_cvWebhook.GetString(g_cWebhook, sizeof(g_cWebhook));
	g_cvWebhook.AddChangeHook(OnWebhookChange);
	
	g_cvEmbedColor = AutoExecConfig_CreateConVar("sm_altnotice_embedcolor", "3447003", "Embed color.");
	
	g_cvEmbedColor.GetString(g_cEmbedColor, sizeof(g_cEmbedColor));
	g_cvEmbedColor.AddChangeHook(OnEmbedColorChange);
	
	Database.Connect(SQL_OnDatabaseConnect, "whois");
	
	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();
}

public void SQL_OnDatabaseConnect(Database db, const char[] error, any data) {
	if (error[0] != '\0') {
		LogError(error);
		return;
	}
	g_DB = db;
}

public void SBPP_OnBanPlayer(int admin, int target, int time, const char[] reason) {
	// Create player
	PlayerInfo player;
		
	// Get target name
	GetClientName(target, player.Name, sizeof(player.Name));
	
	// Get target Steam ID
	GetClientAuthId(target, AuthId_Steam2, player.SteamID, sizeof(player.SteamID));
		
	// Get target IP address
	GetClientIP(target, player.IP, sizeof(player.IP));
	
	// Set ban time
	player.BanTime = time;
	
	// Get dbset with all its Steam IDs
	char query[512];
	g_DB.Format(query, sizeof(query), "SELECT DISTINCT steam_id FROM whois_logs WHERE ip = '%s'", player.IP);
	
	DataPack pack = new DataPack();
	pack.WriteCellArray(player, sizeof(player));
	g_DB.Query(SQL_OnIPsReceived, query, pack);
}

public void SQL_OnIPsReceived(Database db, DBResultSet results, const char[] error, DataPack pack) {
	if (db == null || results == null) {
		LogError(error);
		delete pack;
		return;
	}
	
	if (results.RowCount <= 1) {
		delete pack;
		return;
	}
	
	PlayerInfo player;
	pack.Reset();
	pack.ReadCellArray(player, sizeof(player));
	delete pack;
	
	player.AltsFound = new ArrayList(ByteCountToCells(32));
	
	while (results.FetchRow()) {
		char steamid[32];
		results.FetchString(0, steamid, sizeof(steamid));
		player.AltsFound.PushString(steamid);
	}
	
	SendDiscordMessage(player);
		
} 

void SendDiscordMessage(PlayerInfo player) {
	DiscordWebHook hook = new DiscordWebHook(g_cWebhook);
	hook.SlackMode = true;
	
	MessageEmbed embed = new MessageEmbed();
	
	// Set color
	embed.SetColor(g_cEmbedColor);
	
	// Set title
	char bantime[32];
	if (player.BanTime <= 0) {
		Format(bantime, sizeof(bantime), "permanently");
	}
	else {
		char time[8];
		IntToString(player.BanTime, time, sizeof(time));
		Format(bantime, sizeof(bantime), "%s minutes", time);
	}
	char title[128];
	Format(title, sizeof(title), "User '%s' has been banned - %s", player.Name, bantime);
	embed.SetTitle(title);
	
	// Set fields
	embed.AddField("IP Address", player.IP, true);
	embed.AddField("Steam ID", player.SteamID, true);
	
	// Set description
	char ipList[256], buffer[64];
	StrCat(ipList, sizeof(ipList), "The following accounts have been found under this IP address:\n");
	for (int i = 0; i < player.AltsFound.Length; i++) {
		player.AltsFound.GetString(i, buffer, sizeof(buffer));
		Format(buffer, sizeof(buffer), "- %s\n", buffer);
		StrCat(ipList, sizeof(ipList), buffer);
	}
	
	hook.SlackMode = false;
	embed.SetDescription(ipList);
	
	hook.Embed(embed);
	hook.Send();
	delete hook;
	delete player.AltsFound;
}

public void OnWebhookChange(ConVar convar, const char[] oldValue, const char[] newValue) {
	strcopy(g_cWebhook, sizeof(g_cWebhook), newValue);
}

public void OnEmbedColorChange(ConVar convar, const char[] oldValue, const char[] newValue) {
	strcopy(g_cEmbedColor, sizeof(g_cEmbedColor), newValue);
}