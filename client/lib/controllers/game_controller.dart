import 'dart:math';

import 'package:batufo/arena/arena.dart';
import 'package:batufo/controllers/bullets_controller.dart';
import 'package:batufo/controllers/helpers/bullets_spawner.dart';
import 'package:batufo/controllers/helpers/colliders.dart';
import 'package:batufo/controllers/player_controller.dart';
import 'package:batufo/diagnostics/logger.dart';
import 'package:batufo/game_props.dart';
import 'package:batufo/models/bullet_model.dart';
import 'package:batufo/models/client_game_state.dart';
import 'package:batufo/models/player_model.dart';

final _log = Log<GameController>();

class GameController {
  final BulletsSpawner _bulletsSpawner;
  final void Function(int score) onScored;
  final int clientID;
  PlayerController _playerController;
  BulletsController _bulletsController;
  final ClientGameState _gameState;

  final Arena _arena;

  GameController(
    this._arena,
    this._gameState,
    this.onScored,
    this.clientID,
  ) : _bulletsSpawner = BulletsSpawner(
          bulletForce: GameProps.bulletForce,
          playerSize: GameProps.playerSizeFactor * _arena.tileSize,
        ) {
    final playerSize = GameProps.playerSizeFactor * _arena.tileSize;
    final colliders = Colliders(
      _arena.nrows,
      _arena.ncols,
      walls: _arena.walls,
      playerRadius: playerSize,
    );

    _playerController = PlayerController(
      hitSize: playerSize,
      wallHitSlowdown: GameProps.playerHitsWallSlowdown,
      wallHitHealthTollFactor: GameProps.playerHitsWallHealthFactor,
      playerCollidingAt: colliders.playerCollidingAt,
      thrustForce: GameProps.playerThrustForce,
    );

    _bulletsController = BulletsController(
      _gameState.bullets,
      bulletCollidingAt: colliders.bulletCollidingAt,
      onPlayerHitByBullet: _onPlayerHitByBullet,
      tileSize: _arena.tileSize.toDouble(),
    );
  }

  ClientGameState get gameState => _gameState;

  ClientGameState update(double dt, double ts) {
    final players = _gameState.players;
    _log.finest('game loop ${players.length} players');
    for (final player in players.values) {
      _playerController.update(dt, player);
      if (player.shotBullet) _spawnBullet(player);
    }
    _bulletsController.update(dt, _gameState.players.values);

    return _gameState;
  }

  void _onPlayerHitByBullet(PlayerModel player) {
    final health =
        max(player.health - GameProps.bulletHitsPlayerHealthToll, 0.0);
    if (player.id == _gameState.clientID) {
      // if we are hit, we deal a health toll to ourselves
      player.health = health;
    } else {
      // if we (think) we hit someone, we gain score even if the someone doesn't
      // end up detecting he's hit. This is a bit inconsistent, but much easier
      // than having that someone communicate to us that he's hit.
      // In the worst case we get a bit more points.
      final score = health == 0 ? GameProps.scoreOnKill : GameProps.scoreOnHit;
      onScored(score);
    }
  }

  void cleanup() {
    for (final x in _gameState.players.entries) {
      _playerController.cleanup(x.value);
    }
  }

  void updatePlayer(PlayerModel player) {
    assert(player != null, 'cannot add null as player');
    _gameState.updatePlayer(player);
  }

  void removePlayer(int clientID) {
    _gameState.removePlayer(clientID);
  }

  void addBullet(BulletModel bullet) {
    _gameState.addBullet(bullet);
  }

  void _spawnBullet(PlayerModel player) {
    final bullet = _bulletsSpawner.spawnFor(player);
    _gameState.addBullet(bullet);
  }
}