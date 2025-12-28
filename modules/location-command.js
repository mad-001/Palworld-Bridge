import { data, takaro } from '@takaro/helpers';

/**
 * Location Command Module
 *
 * Gets a player's current live location using the bridge's location system.
 *
 * Usage:
 *   !location              - Get your own location
 *   !location <player>     - Get another player's location (admin only)
 *
 * Can also be called from other modules:
 *   const location = await takaro.gameserver.gameServerControllerExecuteCommand(gameServerId, {
 *       command: `location ${gameId}`
 *   });
 */

async function main() {
    const { gameServerId, pog, arguments: args } = data;

    let targetGameId = pog.gameId;
    let targetName = pog.playerName;

    // If a player name was provided, look them up
    if (args.player) {
        const players = await takaro.player.playerControllerSearch({
            filters: {
                name: [args.player]
            }
        });

        if (players.data.data.length === 0) {
            await takaro.gameserver.gameServerControllerSendMessage(gameServerId, {
                message: `Player "${args.player}" not found.`,
                opts: {
                    recipient: { gameId: pog.gameId }
                }
            });
            return;
        }

        const targetPlayer = players.data.data[0];

        // Get the POG for this player on this server
        const pogs = await takaro.player.playerOnGameServerControllerSearch({
            filters: {
                playerId: [targetPlayer.id],
                gameServerId: [gameServerId]
            }
        });

        if (pogs.data.data.length === 0) {
            await takaro.gameserver.gameServerControllerSendMessage(gameServerId, {
                message: `Player "${args.player}" is not online.`,
                opts: {
                    recipient: { gameId: pog.gameId }
                }
            });
            return;
        }

        targetGameId = pogs.data.data[0].gameId;
        targetName = args.player;
    }

    // Get location using bridge's location command
    const locationCmd = await takaro.gameserver.gameServerControllerExecuteCommand(gameServerId, {
        command: `location ${targetGameId}`
    });

    // Extract location from response
    const location = locationCmd.data?.data || locationCmd.data;

    // Check if we got valid coordinates
    if (!location || !location.x || (location.x === 0 && location.y === 0 && location.z === 0)) {
        await takaro.gameserver.gameServerControllerSendMessage(gameServerId, {
            message: `Unable to get location for ${targetName}. They may not be online or the location system may be unavailable.`,
            opts: {
                recipient: { gameId: pog.gameId }
            }
        });
        return;
    }

    // Send location to player
    const message = targetGameId === pog.gameId
        ? `Your location: X: ${Math.round(location.x)}, Y: ${Math.round(location.y)}, Z: ${Math.round(location.z)}`
        : `${targetName}'s location: X: ${Math.round(location.x)}, Y: ${Math.round(location.y)}, Z: ${Math.round(location.z)}`;

    await takaro.gameserver.gameServerControllerSendMessage(gameServerId, {
        message: message,
        opts: {
            recipient: { gameId: pog.gameId }
        }
    });
}

await main();
