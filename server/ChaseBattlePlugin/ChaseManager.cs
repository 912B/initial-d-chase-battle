using AssettoServer.Server;
using AssettoServer.Server.Plugin;
using Serilog;

namespace ChaseBattlePlugin;

public class ChaseManager
{
    private readonly EntryCarManager _entryCarManager;
    
    // Key: Leader SessionID, Value: Chaser SessionID
    private readonly Dictionary<int, int> _activeBattles = new();

    public ChaseManager(EntryCarManager entryCarManager)
    {
        _entryCarManager = entryCarManager;
    }

    public bool TryStartBattle(int leaderId, int chaserId)
    {
        if (_activeBattles.ContainsKey(leaderId) || _activeBattles.ContainsValue(leaderId) ||
            _activeBattles.ContainsKey(chaserId) || _activeBattles.ContainsValue(chaserId))
        {
            return false; // Already in battle
        }

        _activeBattles[leaderId] = chaserId;
        Log.Information($"Chase Battle Started: {leaderId} vs {chaserId}");
        
        // Broadcast start message (Implementation depends on AssettoServer chat API)
        // _chatManager.Broadcast($"CHASE_START: {leaderId} vs {chaserId}");
        
        return true;
    }

    public void EndBattle(int leaderId, string winnerName, string reason)
    {
        if (_activeBattles.Remove(leaderId, out int chaserId))
        {
             Log.Information($"Chase Battle Ended: Winner {winnerName} ({reason})");
        }
    }
}
