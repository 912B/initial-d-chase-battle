using AssettoServer.Network.Tcp;
using AssettoServer.Server;
using AssettoServer.Server.Plugin;
using AssettoServer.Shared.Network.Packets.Shared;
using Serilog;

namespace ChaseBattlePlugin;

public class ChaseManager
{
    private readonly EntryCarManager _entryCarManager;
    
    // Key: Leader SessionID, Value: ChaseBattle
    private readonly Dictionary<int, ChaseBattle> _activeBattles = new();

    public ChaseManager(EntryCarManager entryCarManager)
    {
        _entryCarManager = entryCarManager;
        _entryCarManager.ClientDisconnected += OnClientDisconnected;
    }

    private void OnClientDisconnected(ACTcpClient client, EventArgs args)
    {
        // Check if client was in a battle
        var battle = _activeBattles.Values.FirstOrDefault(b => b.Leader == client || b.Chaser == client);
        if (battle == null) return;

        _activeBattles.Remove(battle.Leader.SessionId);
        Log.Information($"Chase Battle Ended: {client.Name} disconnected.");

        // Notify other player
        var otherPlayer = battle.Leader == client ? battle.Chaser : battle.Leader;
        if (otherPlayer.IsConnected)
        {
             otherPlayer.SendPacket(new ChatMessage { SessionId = 255, Message = "Chase Battle Ended: Opponent disconnected." });
             otherPlayer.SendPacket(new ChatMessage { SessionId = 255, Message = $"CHASE_END: {battle.Leader.SessionId}" }); 
        }
    }

    public void Reset()
    {
        _activeBattles.Clear();
        Log.Information("Chase Manager Reset by Admin.");
        _entryCarManager.BroadcastPacket(new ChatMessage { SessionId = 255, Message = "Chase Battle System has been RESET by Admin." });
        _entryCarManager.BroadcastPacket(new ChatMessage { SessionId = 255, Message = "CHASE_END" });
    }

    public bool TryStartBattle(ACTcpClient leader, ACTcpClient chaser)
    {
        if (_activeBattles.ContainsKey(leader.SessionId) ||
            _activeBattles.Values.Any(b => b.Chaser == chaser || b.Leader == chaser))
        {
            return false;
        }

        var battle = new ChaseBattle(leader, chaser);
        _activeBattles.Add(leader.SessionId, battle);
        
        Log.Information($"Chase Battle Started: {leader.Name} (Leader) vs {chaser.Name} (Chaser)");
        
        // Notify clients to start Lua logic
        // Notify clients to start Lua logic
        _entryCarManager.BroadcastPacket(new ChatMessage { SessionId = 255, Message = $"CHASE_START: {leader.SessionId} vs {chaser.SessionId}" });

        return true;
    }

    public void ReportResult(ACTcpClient reporter, string result)
    {
        // Find battle where reporter is involved
        var battle = _activeBattles.Values.FirstOrDefault(b => b.Leader == reporter || b.Chaser == reporter);
        if (battle == null) return;
        
        // Ensure only one result is processed
        _activeBattles.Remove(battle.Leader.SessionId);
        
        if (result == "DRAW")
        {
            Log.Information($"Chase Draw: {battle.Leader.Name} vs {battle.Chaser.Name}");
            _entryCarManager.BroadcastPacket(new ChatMessage { SessionId = 255, Message = "Chase Result: DRAW! Swapping roles..." });
            
            // Auto-Swap and Restart
            // Small delay to ensure clients process the end message? 
            // Actually, immediate might be fine, but let's just call it.
            // We need to swap: Chaser becomes Leader
            bool success = TryStartBattle(battle.Chaser, battle.Leader);
            if (!success)
            {
                 _entryCarManager.BroadcastPacket(new ChatMessage { SessionId = 255, Message = "Could not auto-start swap battle." });
            }
        }
        else
        {
 
            string message = result == "WIN" 
                ? $"Chase Result: {battle.Chaser.Name} CAUGHT {battle.Leader.Name}!" 
                : $"Chase Result: {battle.Leader.Name} ESCAPED from {battle.Chaser.Name}!";
                
            Log.Information($"Chase Ended: {message}");
            _entryCarManager.BroadcastPacket(new ChatMessage { SessionId = 255, Message = message });
        }

        // Send Leader SessionID to identify which battle ended (for HUD cleanup)
        _entryCarManager.BroadcastPacket(new ChatMessage { SessionId = 255, Message = $"CHASE_END: {battle.Leader.SessionId}" }); 
    }
}

public class ChaseBattle
{
    public ACTcpClient Leader { get; }
    public ACTcpClient Chaser { get; }
    public DateTime StartTime { get; }

    public ChaseBattle(ACTcpClient leader, ACTcpClient chaser)
    {
        Leader = leader;
        Chaser = chaser;
        StartTime = DateTime.UtcNow;
    }
}
