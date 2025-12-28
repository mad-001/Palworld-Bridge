import { takaro } from '@takaro/helpers';

/**
 * Helper function to get a player's live location
 *
 * This is a reusable helper that any module can use to get player locations.
 *
 * @param {string} gameServerId - The game server ID
 * @param {string} gameId - The player's gameId (Steam ID)
 * @returns {Promise<{x: number, y: number, z: number} | null>} - Location coordinates or null if failed
 *
 * Usage in other modules:
 *
 * import { getPlayerLocation } from './get-player-location-helper.js';
 *
 * const location = await getPlayerLocation(gameServerId, pog.gameId);
 * if (location) {
 *     console.log(`Player is at ${location.x}, ${location.y}, ${location.z}`);
 * }
 */

export async function getPlayerLocation(gameServerId, gameId) {
    try {
        // Call the bridge's location command
        const locationCmd = await takaro.gameserver.gameServerControllerExecuteCommand(gameServerId, {
            command: `location ${gameId}`
        });

        // Extract location from response
        const location = locationCmd.data?.data || locationCmd.data;

        // Validate coordinates
        if (!location || !location.x || (location.x === 0 && location.y === 0 && location.z === 0)) {
            return null;
        }

        return {
            x: location.x,
            y: location.y,
            z: location.z
        };
    } catch (error) {
        console.error(`Failed to get player location: ${error.message}`);
        return null;
    }
}

/**
 * Helper function to format location coordinates for display
 *
 * @param {{x: number, y: number, z: number}} location - Location coordinates
 * @returns {string} - Formatted location string
 */
export function formatLocation(location) {
    return `X: ${Math.round(location.x)}, Y: ${Math.round(location.y)}, Z: ${Math.round(location.z)}`;
}
