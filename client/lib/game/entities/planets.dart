import 'dart:ui' show Canvas, Rect, Size;

import 'package:batufo/engine/sprite.dart';
import 'package:batufo/engine/sprite_sheet.dart';
import 'package:batufo/engine/tile_position.dart';
import 'package:batufo/game/assets/assets.dart';
import 'package:batufo/game/entities/scene.dart';
import 'package:batufo/util/math.dart';
import 'package:flutter/material.dart';

class Planet {
  final TilePosition tilePosition;
  final Sprite sprite;
  final double radius;
  const Planet(this.tilePosition, this.sprite, this.radius);
}

class Planets extends Scene {
  final int density;
  final double _tileSize;
  final double _tileRangeMin;
  final double _tileRangeMax;
  final double minRadius;
  final double maxRadius;
  final List<Planet> _planets = [];
  final RandomNumber _rnd;
  final SpriteSheet planets;
  final bool _skipRender;

  Planets(
    this._tileSize, {
    @required double lerpFactor,
    @required bool enableRecording,
    @required this.minRadius,
    @required this.maxRadius,
    @required this.density,
  })  : _rnd = RandomNumber(),
        _tileRangeMin = -(_tileSize / 2),
        _tileRangeMax = _tileSize / 2,
        planets = SpriteSheet.fromImageAsset(assets.planets),
        _skipRender = density <= 0,
        super(enableRecording: enableRecording, sizeFactor: lerpFactor);

  bool get skipRender => _skipRender;

  Sprite _randomPlanetSprite() {
    // purposely generating a number too large most of the time which means we
    // won't draw a planet
    final idx = _rnd.nextInt(0, 10000 ~/ density);
    return idx >= assets.planets.cols ? null : planets.getIndex(idx);
  }

  void _addPlanet(int col, int row) {
    final sprite = _randomPlanetSprite();
    if (sprite == null) return;
    final dx = _rnd.nextDouble(_tileRangeMin, _tileRangeMax);
    final dy = _rnd.nextDouble(_tileRangeMin, _tileRangeMax);
    final tp = TilePosition(col, row, dx, dy);
    final radiusFactor = _rnd.nextDouble(minRadius, maxRadius);
    final planet = Planet(tp, sprite, radiusFactor * planets.spriteWidth);
    _planets.add(planet);
  }

  void _initPlanets(Size size) {
    final ncols = size.width / _tileSize + 1;
    final nrows = size.height / _tileSize + 1;
    _planets.clear();
    for (int row = 0; row < nrows; row++) {
      for (int col = 0; col < ncols; col++) {
        _addPlanet(col, row);
      }
    }
  }

  void _renderPlanet(Canvas canvas, Planet planet) {
    final worldOffset = planet.tilePosition.toWorldOffset();
    final rect = Rect.fromCircle(center: worldOffset, radius: planet.radius);
    planet.sprite.renderRect(canvas, rect);
  }

  void resizeScene(Size fullSize) {
    _initPlanets(fullSize);
  }

  void renderScene(Canvas canvas, Size size) {
    for (final planet in _planets) _renderPlanet(canvas, planet);
  }
}
