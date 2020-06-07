import 'dart:math';
import 'dart:ui' show Canvas, Offset, Size;

import 'package:batufo/arena/arena.dart';
import 'package:batufo/controllers/game_controller.dart';
import 'package:batufo/controllers/helpers/player_status.dart';
import 'package:batufo/diagnostics/logger.dart';
import 'package:batufo/engine/game.dart';
import 'package:batufo/engine/world_position.dart';
import 'package:batufo/game/assets/assets.dart';
import 'package:batufo/game/entities/background.dart';
import 'package:batufo/game/entities/bullets.dart';
import 'package:batufo/game/entities/grid.dart';
import 'package:batufo/game/entities/planets.dart';
import 'package:batufo/game/entities/player.dart';
import 'package:batufo/game/entities/stars.dart';
import 'package:batufo/game/entities/walls.dart';
import 'package:batufo/game/inputs/gestures.dart';
import 'package:batufo/game/inputs/input_processor.dart';
import 'package:batufo/game/inputs/keyboard.dart';
import 'package:batufo/game_props.dart';
import 'package:batufo/models/client_game_state.dart';
import 'package:batufo/models/player_model.dart';
import 'package:batufo/rpc/client_player_update.dart';
import 'package:batufo/rpc/client_spawned_bullet_update.dart';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

final _log = Log<ClientGame>();

class ClientGame extends Game {
  final Arena arena;
  final void Function(ClientGameState state) onGameStateUpdated;
  final Background _background;
  final Grid _grid;
  final Stars _starsBack;
  final Stars _starsMiddle;
  final Stars _starsFront;
  final Planets _planetsBack;
  final Planets _planetsFront;
  final Walls _walls;
  final InputProcessor inputProcessor;
  final int clientID;
  final ClientPlayerUpdate _clientPlayerUpdate;
  final ClientSpawnedBulletUpdate _clientSpawnedBulletUpdate;
  final _clientPlayerUpdate$ = BehaviorSubject<ClientPlayerUpdate>();
  final _clientSpawnedBulletUpdate$ =
      BehaviorSubject<ClientSpawnedBulletUpdate>();

  GameController _gameController;
  Map<int, Player> _players;
  Bullets _bullets;

  Offset _camera;
  Offset _starsBackCamera;
  Offset _starsMiddleCamera;
  Offset _starsFrontCamera;
  Offset _planetsBackCamera;
  Offset _planetsFrontCamera;
  Size _size;
  bool _disposed;
  bool _started;
  bool _finished;

  bool get disposed => _disposed;
  bool get started => _started;
  bool get finished => _finished;
  bool get ready => _started && !_disposed;
  bool hasPlayer(int clientID) => gameState.hasPlayer(clientID);

  Stream<ClientPlayerUpdate> get clientPlayerUpdate$ =>
      _clientPlayerUpdate$.stream;
  Stream<ClientSpawnedBulletUpdate> get clientSpawnedBulletUpdate$ =>
      _clientSpawnedBulletUpdate$.stream;

  ClientGame({
    @required this.inputProcessor,
    @required this.arena,
    @required this.clientID,
    @required this.onGameStateUpdated,
    @required void Function(int score) onScored,
    @required int playerIndex,
  })  : _started = false,
        _finished = false,
        _disposed = false,
        _clientPlayerUpdate = ClientPlayerUpdate(),
        _clientSpawnedBulletUpdate = ClientSpawnedBulletUpdate(),
        _grid = Grid(arena.tileSize.toDouble()),
        _starsBack = Stars(
          arena,
          GameProps.backgroundOversizeFactor,
          minRadius: 0.1,
          maxRadius: 0.4,
          density: 12,
        ),
        _starsMiddle = Stars(
          arena,
          GameProps.backgroundOversizeFactor,
          minRadius: 0.3,
          maxRadius: 0.7,
          density: 6,
        ),
        _starsFront = Stars(
          arena,
          GameProps.backgroundOversizeFactor,
          minRadius: 0.8,
          maxRadius: 1.2,
          density: 2,
        ),
        _planetsBack = Planets(
          arena.tileSize.toDouble(),
          GameProps.backgroundOversizeFactor,
          density: 8,
          minRadius: 0.1,
          maxRadius: 0.5,
        ),
        _planetsFront = Planets(
          arena.tileSize.toDouble(),
          GameProps.backgroundOversizeFactor,
          minRadius: 0.6,
          maxRadius: 0.9,
          density: 2,
        ),
        _background = Background(
          arena.floorTiles,
          arena.tileSize.toDouble(),
          GameProps.renderBackground,
        ),
        _walls = Walls(arena.walls, arena.tileSize.toDouble()),
        _camera = Offset.zero,
        _starsBackCamera = Offset.zero,
        _starsMiddleCamera = Offset.zero,
        _starsFrontCamera = Offset.zero,
        _planetsBackCamera = Offset.zero,
        _planetsFrontCamera = Offset.zero {
    _bullets = Bullets(
      msToExplode: GameProps.bulletMsToExplode,
      tileSize: arena.tileSize.toDouble(),
    );

    assert(playerIndex < arena.players.length,
        '$playerIndex is out of range for ${arena.players}');
    _players = <int, Player>{clientID: _initPlayer()};
    _gameController = GameController(
      arena,
      _heroOnlyGameState(playerIndex),
      onScored,
      clientID,
    );
  }

  ClientGameState get gameState => _gameController.gameState;
  int get totalPlayers => arena.players.length;

  PlayerModel get clientPlayer {
    final player = gameState.players[clientID];
    assert(player != null, 'our player with id $clientID should exist');
    return player;
  }

  ClientGameState _heroOnlyGameState(int playerIndex) {
    final playerStartPosition = arena.players[playerIndex];
    final hero = PlayerModel.forInitialPosition(
      clientID,
      playerStartPosition,
      GameProps.playerTotalHealth,
    );
    return ClientGameState(
      clientID: clientID,
      bullets: [],
      totalPlayers: arena.players.length,
      players: {clientID: hero},
    );
  }

  void updatePlayers(PlayerModel player) {
    final id = player.id;
    _gameController.updatePlayer(player);
    _players.putIfAbsent(id, _initPlayer);
  }

  void removePlayer(int clientID) {
    _gameController.removePlayer(clientID);
    _players.remove(clientID);
  }

  void updateBullets(ClientSpawnedBulletUpdate update) {
    _gameController.addBullet(update.spawnedBullet);
  }

  void start() {
    if (_started) return;
    // this.gameState = gameState;
    for (final clientID in gameState.players.keys) {
      _players[clientID] = _initPlayer();
    }
    _started = true;
  }

  void update(double dt, double ts) {
    if (!ready) return;
    final player = clientPlayer;
    if (!PlayerStatus.isDead(player)) {
      final pressedKeys = GameKeyboard.pressedKeys;
      final gestures = GameGestures.instance.aggregatedGestures;

      inputProcessor.udate(dt, pressedKeys, gestures, player);
    }
    _gameController.update(dt, ts);
    _clientPlayerUpdate.player = gameState.players[clientID];
    _clientPlayerUpdate$.add(_clientPlayerUpdate);

    if (player.shotBullet) {
      _clientSpawnedBulletUpdate.spawnedBullet = gameState.bullets.last;
      _clientSpawnedBulletUpdate$.add(_clientSpawnedBulletUpdate);
    }
    onGameStateUpdated(gameState);
  }

  void updateUI(double dt, double ts) {
    if (_disposed) return;
    _cameraFollow(
      clientPlayer.tilePosition.toWorldPosition(),
      dt,
    );
    if (!started) return;

    for (final entry in gameState.players.entries) {
      final player = _players[entry.key];
      if (player == null) continue;
      player.updateSprites(entry.value, dt);
    }
    _bullets.updateSprites(gameState.bullets, dt);
  }

  void _renderArena(Canvas canvas) {
    _lowerLeftCanvas(canvas, _size.height);

    if (GameProps.debugGrid) {
      _renderGrid(canvas);
    } else {
      _renderUniverse(canvas);
    }

    canvas.translate(-_camera.dx, -_camera.dy);
    _background.render(canvas);
    _walls.render(canvas);
  }

  void _renderGrid(Canvas canvas) {
    canvas.save();
    {
      canvas.translate(-_starsBackCamera.dx, -_starsBackCamera.dy);
      _grid.render(canvas, arena.nrows, arena.ncols);
    }
    canvas.restore();
  }

  void _renderUniverse(Canvas canvas) {
    _starsBack.renderBackground(canvas, _size);

    canvas.save();
    {
      canvas.translate(_size.width / 2, _size.height / 2);
      canvas.translate(-_starsBackCamera.dx, -_starsBackCamera.dy);
      _starsBack.render(canvas, _size);
      canvas.translate(-_starsMiddleCamera.dx, -_starsMiddleCamera.dy);
      _starsMiddle.render(canvas, _size);
      canvas.translate(-_starsFrontCamera.dx, -_starsFrontCamera.dy);
      _starsFront.render(canvas, _size);
      canvas.translate(-_planetsBackCamera.dx, -_planetsBackCamera.dy);
      _planetsBack.render(canvas, _size);
      canvas.translate(-_planetsFrontCamera.dx, -_planetsFrontCamera.dy);
      _planetsFront.render(canvas, _size);
    }
    canvas.restore();
  }

  void render(Canvas canvas) {
    if (disposed) return;
    _renderArena(canvas);

    for (final entry in gameState.players.entries) {
      final player = _players[entry.key];
      if (player == null) continue;
      _players[entry.key].render(canvas, entry.value);
    }
    _bullets.render(canvas, gameState.bullets);
  }

  void cleanup() {
    if (!ready) return;
    _gameController.cleanup();
  }

  void resize(Size size) {
    _size = size;
    _starsBack.needsRegenerate = true;
    _starsMiddle.needsRegenerate = true;
    _starsFront.needsRegenerate = true;
    _planetsBack.needsRegenerate = true;
    _planetsFront.needsRegenerate = true;
  }

  void _cameraFollow(WorldPosition wp, double dt) {
    if (_size == null) return;
    final pos = wp.toOffset();
    final centerScreen = Offset(_size.width / 2, _size.height / 2);
    final moved = Offset(pos.dx - centerScreen.dx, pos.dy - centerScreen.dy);

    final lerp = min(0.0025 * dt, 1.0);
    const starsBackLerp = 0.15;
    const starsMiddleLerp = 0.15;
    const starsFrontLerp = 0.15;
    const planetsBackLerp = 0.15;
    const planetsFrontLerp = 0.15;
    final dx = (moved.dx - _camera.dx) * lerp;
    final dy = (moved.dy - _camera.dy) * lerp;
    _camera = _camera.translate(dx, dy);
    _starsBackCamera = _starsBackCamera.translate(
      dx * starsBackLerp,
      dy * starsBackLerp,
    );
    _starsMiddleCamera = _starsMiddleCamera.translate(
      dx * starsMiddleLerp,
      dy * starsMiddleLerp,
    );
    _starsFrontCamera = _starsFrontCamera.translate(
      dx * starsFrontLerp,
      dy * starsFrontLerp,
    );
    _planetsBackCamera = _planetsBackCamera.translate(
      dx * planetsBackLerp,
      dy * planetsBackLerp,
    );
    _planetsFrontCamera = _planetsFrontCamera.translate(
      dx * planetsFrontLerp,
      dy * planetsFrontLerp,
    );
  }

  void _lowerLeftCanvas(Canvas canvas, double height) {
    canvas
      ..translate(0, height)
      ..scale(1, -1);
  }

  Player _initPlayer() {
    final playerSize = GameProps.playerSizeFactor * arena.tileSize;
    return Player(
      playerImagePath: assets.player.imagePath,
      deadPlayerImagePath: assets.skull.imagePath,
      tileSize: arena.tileSize.toDouble(),
      hitSize: playerSize,
      thrustAnimationDurationMs: GameProps.playerThrustAnimationDurationMs,
    );
  }

  void finish() {
    _finished = true;
  }

  void dispose() {
    _finished = true;
    if (_disposed) return;
    _log.fine('disposing');
    if (_clientPlayerUpdate$ != null && !_clientPlayerUpdate$.isClosed) {
      _clientPlayerUpdate$.close();
    }
    if (_clientSpawnedBulletUpdate$ != null &&
        !_clientSpawnedBulletUpdate$.isClosed) {
      _clientSpawnedBulletUpdate$.close();
    }
    _disposed = true;
  }
}
