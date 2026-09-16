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

/**
 * Resolve the Palworld game id (the `steam_7656…` account id) for an UNBAN.
 *
 * F20 (hardtest-7R-A7-A8-A9-A10.txt): Takaro's `unbanPlayer` does NOT arrive in the
 * nested `{ player: { gameId } }` shape that kick/ban/give/teleport use. It arrives as
 * the flattened POG payload with the game id at the TOP LEVEL plus a `player` sub-object
 * that only carries Takaro's own ids:
 *   { id:"<pog>", playerId:"<takaro playerId>", gameId:"steam_7656…", steamId:"7656…",
 *     player:{ id:"<takaro playerId>", steamId:"steam_7656…" } }
 * The generic resolvePlayerId() picks pickGameId(args.player) first, and because that
 * sub-object has no gameId it falls through to `.id` = the Takaro playerId, so the bridge
 * unbanned "d479004e…" (a no-op) while the real steam id stayed banned.
 *
 * So unban reads the game id the way F0 reads it for ban, but WITHOUT the misleading
 * player.id fallback: player.gameId -> top-level gameId -> steamId -> player.steamId.
 * A bare 17-digit steam id is normalised to the `steam_` form the Palworld ban list and
 * REST /v1/api/unban expect (the console `unban` path already passes `steam_…`).
 */
export function resolveUnbanGameId(args: any): string | undefined {
  if (!args || typeof args !== 'object') return pickGameId(args);
  const raw =
    (typeof args.player?.gameId === 'string' && args.player.gameId) ||
    (typeof args.gameId === 'string' && args.gameId) ||
    (typeof args.steamId === 'string' && args.steamId) ||
    (typeof args.player?.steamId === 'string' && args.player.steamId) ||
    undefined;
  if (!raw) return undefined;
  return /^\d{17}$/.test(raw) ? `steam_${raw}` : raw;
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
