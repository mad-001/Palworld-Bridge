import { data, takaro } from '@takaro/helpers';

/**
 * Home Command - Teleport to your saved home location
 *
 * Usage: !home
 *
 * Retrieves saved home coordinates from Takaro variables
 * Uses teleportplayer command to teleport to coordinates
 */

async function main() {
    const { gameServerId, player, pog, module } = data;

    // Get saved home location
    const homeVars = await takaro.variable.variableControllerSearch({
        filters: {
            key: ['home_location'],
            playerId: [player.id],
            moduleId: [module.moduleId],
            gameServerId: [gameServerId]
        }
    });

    if (homeVars.data.data.length === 0) {
        await takaro.gameserver.gameServerControllerSendMessage(gameServerId, {
            message: "You haven't set a home location yet. Use !sethome first."
        });
        return;
    }

    const position = JSON.parse(homeVars.data.data[0].value);

    // Use teleportplayer command (same as !visit)
    await takaro.gameserver.gameServerControllerExecuteCommand(gameServerId, {
        command: `teleportplayer ${player.name} ${position.x} ${position.y} ${position.z}`
    });

    await takaro.gameserver.gameServerControllerSendMessage(gameServerId, {
        message: `Teleporting to home... (X: ${Math.round(position.x)}, Y: ${Math.round(position.y)}, Z: ${Math.round(position.z)})`
    });
}

await main();
