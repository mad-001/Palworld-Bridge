import { data, takaro } from '@takaro/helpers';

/**
 * SetHome Command - Save your current location as home
 *
 * Usage: !sethome
 *
 * Uses Takaro's cached player position (updated from polling)
 * Saves X/Y/Z coordinates to Takaro variables for later teleport
 */

async function main() {
    const { gameServerId, player, pog, module } = data;

    // Use position from Takaro's polling (no command needed!)
    const position = {
        x: pog.positionX,
        y: pog.positionY,
        z: pog.positionZ || 0
    };

    if (!position.x && !position.y) {
        await takaro.gameserver.gameServerControllerSendMessage(gameServerId, {
            message: "Unable to get your position. Try again in a few seconds."
        });
        return;
    }

    const existingVars = await takaro.variable.variableControllerSearch({
        filters: {
            key: ['home_location'],
            playerId: [player.id],
            moduleId: [module.moduleId],
            gameServerId: [gameServerId]
        }
    });

    if (existingVars.data.data.length > 0) {
        await takaro.variable.variableControllerUpdate(existingVars.data.data[0].id, {
            value: JSON.stringify(position)
        });
    } else {
        await takaro.variable.variableControllerCreate({
            key: 'home_location',
            value: JSON.stringify(position),
            playerId: player.id,
            moduleId: module.moduleId,
            gameServerId: gameServerId
        });
    }

    await takaro.gameserver.gameServerControllerSendMessage(gameServerId, {
        message: `Home set at X: ${Math.round(position.x)}, Y: ${Math.round(position.y)}${position.z ? `, Z: ${Math.round(position.z)}` : ''}`
    });
}

await main();
