using AssettoServer.Server;
using AssettoServer.Server.Plugin;
using Qmmands;

namespace ChaseBattlePlugin;

public class ChaseCommands : CheckBaseAttribute
{
    private readonly ChaseManager _chaseManager;

    public ChaseCommands(ChaseManager chaseManager)
    {
        _chaseManager = chaseManager;
    }

    [Command("chase")]
    public void ChaseCommand(int targetId)
    {
        // This would be hooked up to the actual chat command system
        // For now, this is a placeholder for the logic
        // var client = Context.Client;
        // _chaseManager.TryStartBattle(client.SessionId, targetId);
    }
}
