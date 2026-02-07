using AssettoServer.Server;
using AssettoServer.Server.Plugin;
using Microsoft.Extensions.Hosting;
using Serilog;

namespace ChaseBattlePlugin;

[Plugin("ChaseBattlePlugin", "1.0.0", "Initial D Style Chase Battle Plugin")]
public class ChaseBattlePlugin : IHostedService
{
    private readonly ChaseManager _chaseManager;

    public ChaseBattlePlugin(ChaseManager chaseManager)
    {
        _chaseManager = chaseManager;
    }

    public Task StartAsync(CancellationToken cancellationToken)
    {
        Log.Information("ChaseBattlePlugin Service Started.");
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        Log.Information("ChaseBattlePlugin Service Stopped.");
        return Task.CompletedTask;
    }
}
