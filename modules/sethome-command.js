import { data, takaro } from '@takaro/helpers';

/**
 * SetHome Command Module
 *
 * Sets the player's home location to their current position.
 * Uses the bridge's live location system to get accurate X/Y/Z coordinates.
 *
 * Usage: !sethome
 */

async function main() {
    const { gameServerId, player, pog, module } = data;

    // Get current position using the bridge's location command
    const locationCmd = await takaro.gameserver.gameServerControllerExecuteCommand(gameServerId, {
        command: `location ${pog.gameId}`
    });

    // Extract location from response
    const location = locationCmd.data?.data || locationCmd.data;

    // Validate coordinates
    if (!location || !location.x || (location.x === 0 && location.y === 0 && location.z === 0)) {
        await takaro.gameserver.gameServerControllerSendMessage(gameServerId, {
            message: "Unable to get your current position. Please try again in a few seconds.",
            opts: {
                recipient: { gameId: pog.gameId }
            }
        });
        return;
    }

    const position = {
        x: location.x,
        y: location.y,
        z: location.z
    };

    // Check if home already exists
    const existingVars = await takaro.variable.variableControllerSearch({
        filters: {
            key: ['home_location'],
            playerId: [player.id],
            moduleId: [module.moduleId],
            gameServerId: [gameServerId]
        }
    });

    if (existingVars.data.data.length > 0) {
        // Update existing variable
        await takaro.variable.variableControllerUpdate(existingVars.data.data[0].id, {
            value: JSON.stringify(position)
        });
    } else {
        // Create new variable
        await takaro.variable.variableControllerCreate({
            key: 'home_location',
            value: JSON.stringify(position),
            playerId: player.id,
            moduleId: module.moduleId,
            gameServerId: gameServerId
        });
    }

    await takaro.gameserver.gameServerControllerSendMessage(gameServerId, {
        message: `Home location set at X: ${Math.round(position.x)}, Y: ${Math.round(position.y)}, Z: ${Math.round(position.z)}`,
        opts: {
            recipient: { gameId: pog.gameId }
        }
    });
}

await main();
