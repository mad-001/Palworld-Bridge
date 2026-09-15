/**
 * Argument-shape helpers for actions coming from Takaro.
 *
 * Takaro's Generic game server adapter
 * (takaro/packages/lib-gameserver/src/gameservers/generic/index.ts) does NOT send a
 * flat player id. Verified against the `development` branch:
 *
 *   giveItem        -> { player: { gameId }, item, amount, quality }
 *   teleportPlayer  -> { player: <IGamePlayer>, x, y, z, dimension }
 *   kickPlayer      -> { player: <IGamePlayer>, reason }
 *   banPlayer       -> BanDTO.toJSON() = { player: <IGamePlayer>, reason, expiresAt }
 *   unbanPlayer     -> <IGamePlayer>.toJSON()          (gameId at top level)
 *   getPlayer       -> { gameId }                      (IPlayerReferenceDTO)
 *   getPlayerLocation / getPlayerInventory -> { gameId }
 *   listBans / shutdown / getPlayers / listItems ... -> {}
 *
 * so every handler must accept both the nested and the historical flat shapes.
 */

/** Extract a game id out of either a bare string or a player-ish object. */
export function pickGameId(value: any): string | undefined {
  if (typeof value === 'string') {
    return value.length > 0 ? value : undefined;
  }
  if (value && typeof value === 'object') {
    const candidate = value.gameId ?? value.userId ?? value.playerId ?? value.id;
    if (typeof candidate === 'string' && candidate.length > 0) return candidate;
  }
  return undefined;
}

/**
 * Resolve the target player id for give/teleport/kick/ban style actions.
 * Nested `player` (what Takaro actually sends) wins, the old flat fallbacks are kept
 * so console commands and third-party callers keep working.
 */
export function resolvePlayerId(args: any): string | undefined {
  if (!args || typeof args !== 'object') return pickGameId(args);
  return (
    pickGameId(args.player) ??
    pickGameId(args.gameId) ??
    pickGameId(args.playerId) ??
    pickGameId(args.userId) ??
    pickGameId(args.sourcePlayer)
  );
}

/** Resolve the destination player for a player-to-player teleport. */
export function resolveTargetPlayerId(args: any): string | undefined {
  if (!args || typeof args !== 'object') return undefined;
  return (
    pickGameId(args.targetPlayer) ??
    pickGameId(args.destinationPlayer) ??
    pickGameId(args.target)
  );
}

/**
 * Palworld's REST API reports the account as `steam_7656…`. Takaro stores whatever the
 * connector calls `steamId` verbatim and its Steam enrichment then silently finds nothing.
 * Keep `gameId` raw (stable identity) and hand Takaro the bare 17-digit id.
 */
export function bareSteamId(userId: string): string {
  const match = /^steam_(\d{17})$/.exec(userId ?? '');
  return match ? match[1] : userId;
}

/** Compact one-line rendering of an args object, for failure logs. */
export function describeArgs(args: any): string {
  try {
    return JSON.stringify(args);
  } catch {
    return String(args);
  }
}
