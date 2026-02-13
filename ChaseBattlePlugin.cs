using System.Reflection;
using AssettoServer.Server;
using AssettoServer.Server.Plugin;
using Microsoft.Extensions.Hosting;
using Serilog;

namespace ChaseBattlePlugin;

public class ChaseBattlePlugin : BackgroundService
{
    private readonly ChaseManager _chaseManager;

    public ChaseBattlePlugin(ChaseManager chaseManager, CSPServerScriptProvider scriptProvider)
    {
        _chaseManager = chaseManager;
        
        var assembly = Assembly.GetExecutingAssembly();
        var resources = assembly.GetManifestResourceNames();
        Log.Information($"[ChaseBattlePlugin] Found {resources.Length} resources: {string.Join(", ", resources)}");

        var resourceName = "ChaseBattlePlugin.lua.chase_battle.lua";
        var stream = assembly.GetManifestResourceStream(resourceName);
        if (stream != null)
        {
             scriptProvider.AddScript(stream, "chase_battle.lua");
             Log.Information($"[ChaseBattlePlugin] Successfully added Lua script: {resourceName}");
        }
        else
        {
             Log.Error($"[ChaseBattlePlugin] Could not find embedded resource: {resourceName}");
        }
    }

    protected override Task ExecuteAsync(CancellationToken stoppingToken)
    {
        Log.Information("ChaseBattlePlugin Service Started.");
        return Task.CompletedTask;
    }


    public override Task StopAsync(CancellationToken cancellationToken)
    {
        Log.Information("ChaseBattlePlugin Service Stopped.");
        return Task.CompletedTask;
    }
}
