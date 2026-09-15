import test from 'node:test';
import assert from 'node:assert/strict';
import { pickGameId, resolvePlayerId, resolveTargetPlayerId, bareSteamId } from '../dist/player-args.js';

const GID = 'steam_76561198000735875';

test('resolves the nested player object Takaro sends', () => {
  // giveItem
  assert.equal(resolvePlayerId({ player: { gameId: GID }, item: 'Wood', amount: 5, quality: '0' }), GID);
  // teleportPlayer / kickPlayer
  assert.equal(resolvePlayerId({ player: { gameId: GID, name: 'Limon' }, x: 1, y: 2, z: 3 }), GID);
  // banPlayer (BanDTO)
  assert.equal(resolvePlayerId({ player: { gameId: GID }, reason: 'nope', expiresAt: null }), GID);
});

test('keeps the historical flat fallbacks', () => {
  assert.equal(resolvePlayerId({ gameId: GID }), GID);
  assert.equal(resolvePlayerId({ playerId: GID }), GID);
  assert.equal(resolvePlayerId({ userId: GID }), GID);
  assert.equal(resolvePlayerId({ sourcePlayer: 'Limon' }), 'Limon');
});

test('returns undefined when there is no player at all', () => {
  assert.equal(resolvePlayerId({}), undefined);
  assert.equal(resolvePlayerId({ player: {} }), undefined);
  assert.equal(resolvePlayerId(null), undefined);
  assert.equal(pickGameId(''), undefined);
});

test('resolves teleport targets', () => {
  assert.equal(resolveTargetPlayerId({ targetPlayer: { gameId: GID } }), GID);
  assert.equal(resolveTargetPlayerId({ destinationPlayer: 'Limon' }), 'Limon');
  assert.equal(resolveTargetPlayerId({ x: 1, y: 2, z: 3 }), undefined);
});

test('strips the steam_ prefix only from well-formed ids', () => {
  assert.equal(bareSteamId(GID), '76561198000735875');
  assert.equal(bareSteamId('76561198000735875'), '76561198000735875');
  assert.equal(bareSteamId('steam_short'), 'steam_short');
});
