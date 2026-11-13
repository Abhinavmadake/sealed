import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Draws static art once into an image, then reuses it. Impeller has no raster cache, so without
/// this every frame would re-tessellate thousands of lines and dots.
class RasterCache {
  RasterCache(this.capacity);

  final int capacity;
  final _images = <Object, ui.Image>{};

  ui.Image get(Object key, Size size, double dpr, void Function(Canvas canvas) draw) {
    final hit = _images.remove(key);
    if (hit != null) {
      _images[key] = hit;
      return hit;
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(dpr);
    draw(canvas);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      (size.width * dpr).ceil().clamp(1, 8192),
      (size.height * dpr).ceil().clamp(1, 8192),
    );
    picture.dispose();
    _images[key] = image;
    while (_images.length > capacity) {
      _images.remove(_images.keys.first)!.dispose();
    }
    return image;
  }
}

void drawRaster(Canvas canvas, ui.Image image, Rect dst) => canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.low,
    );
