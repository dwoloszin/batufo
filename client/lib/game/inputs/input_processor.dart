import 'dart:math';

import 'package:batufo/game/inputs/input_types.dart';
import 'package:batufo/models/player_model.dart';
import 'package:flutter/foundation.dart';

const twopi = 2 * pi;

class InputProcessor {
  final double keyboardThrustForce;
  final double keyboardRotationFactor;
  final double timeBetweenThrusts;
  final double timeBetweenBullets;

  double timeSinceLastThrust;
  double timeSinceLastBullet;

  InputProcessor._({
    @required this.keyboardThrustForce,
    @required this.keyboardRotationFactor,
    @required this.timeBetweenThrusts,
    @required this.timeBetweenBullets,
  }) {
    timeSinceLastThrust = 0.0;
    timeSinceLastBullet = 0.0;
  }

  bool get canApplyThrust {
    return timeBetweenThrusts <= timeSinceLastThrust;
  }

  bool get canShootBullet {
    return timeBetweenBullets <= timeSinceLastBullet;
  }

  int get percentReadyToShoot =>
      min((timeSinceLastBullet / timeBetweenBullets * 100).floor(), 100);

  int get percentReadyToThrust =>
      min((timeSinceLastThrust / timeBetweenThrusts * 100).floor(), 100);

  void udate(
    double dt,
    GameKeys keys,
    AggregatedGestures gestures,
    PlayerModel player,
  ) {
    // rotation
    if (keys.contains(GameKey.Left)) {
      player.angle = _increaseAngle(player.angle, dt * keyboardRotationFactor);
    }
    if (keys.contains(GameKey.Right)) {
      player.angle = _increaseAngle(player.angle, -dt * keyboardRotationFactor);
    }
    if (gestures.rotation != 0.0) {
      player.angle = _increaseAngle(player.angle, gestures.rotation);
    }
    timeSinceLastThrust = min(timeBetweenThrusts, timeSinceLastThrust + dt);
    timeSinceLastBullet = min(timeBetweenBullets, timeSinceLastBullet + dt);

    // bullets
    if (canShootBullet) {
      if (keys.contains(GameKey.Fire) || gestures.fire) {
        player.shotBullet = true;
        timeSinceLastBullet = 0.0;
      }
    }

    // thrust
    if (canApplyThrust) {
      if (keys.contains(GameKey.Up)) {
        player.appliedThrust = true;
        timeSinceLastThrust = 0.0;
      }
      if (gestures.thrust != 0.0) {
        player.appliedThrust = true;
        timeSinceLastThrust = 0.0;
      }
    }
  }

  double _increaseAngle(double angle, double delta) {
    final res = angle + delta;
    // Make sure angle is never < 0 nor too large.
    // This is important for network communication as the double is packed
    // and sending negative value causes problems due to 31-bit limit in V8.
    if (res > twopi) return res - twopi;
    if (res < 0) return res + twopi;
    return res;
  }

  static InputProcessor _instance;
  static InputProcessor get instance => _instance;

  static void create({
    @required double keyboardThrustForce,
    @required double keyboardRotationFactor,
    @required double timeBetweenThrusts,
    @required double timeBetweenBullets,
  }) {
    assert(_instance == null, 'input processor should only be created once');
    _instance = InputProcessor._(
      keyboardThrustForce: keyboardThrustForce,
      keyboardRotationFactor: keyboardRotationFactor,
      timeBetweenThrusts: timeBetweenThrusts,
      timeBetweenBullets: timeBetweenBullets,
    );
  }
}