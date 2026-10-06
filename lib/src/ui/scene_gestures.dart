import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../scene/camera_rig.dart';

/// Turns pointer, trackpad and touch input into camera intents, map style:
///
/// - Mouse: left drag orbits; right or middle drag (or shift + drag) pans;
///   the wheel zooms toward the cursor.
/// - Trackpad: two-finger swipe pans, pinch zooms toward the fingers,
///   click-drag orbits, and a two-finger twist rotates (macOS app).
/// - Touch: one finger orbits; two fingers pinch to zoom and move to pan.
class SceneGestures extends StatefulWidget {
  const SceneGestures({
    super.key,
    required this.input,
    required this.child,
    this.enabled = true,
  });

  final CameraInput input;
  final bool enabled;
  final Widget child;

  @override
  State<SceneGestures> createState() => _SceneGesturesState();
}

class _SceneGesturesState extends State<SceneGestures> {
  final _pointers = <int, Offset>{};
  final _panning = <int, bool>{};
  double _lastScale = 1;
  double _lastRotation = 0;

  CameraInput get _input => widget.input;

  bool get _shiftHeld => HardwareKeyboard.instance.logicalKeysPressed.any(
    (k) =>
        k == LogicalKeyboardKey.shiftLeft || k == LogicalKeyboardKey.shiftRight,
  );

  void _down(PointerDownEvent e) {
    if (!widget.enabled) return;
    _pointers[e.pointer] = e.localPosition;
    _panning[e.pointer] =
        e.kind != PointerDeviceKind.touch &&
        (e.buttons & (kSecondaryMouseButton | kMiddleMouseButton) != 0 ||
            _shiftHeld);
  }

  void _move(PointerMoveEvent e) {
    final previous = _pointers[e.pointer];
    if (!widget.enabled || previous == null) return;
    final current = e.localPosition;

    if (_pointers.length >= 2 && e.kind == PointerDeviceKind.touch) {
      // Two fingers: pinch about the midpoint and drag it along.
      final other = _pointers.entries
          .firstWhere((p) => p.key != e.pointer)
          .value;
      final before = (previous - other).distance;
      final after = (current - other).distance;
      final midBefore = (previous + other) / 2,
          midAfter = (current + other) / 2;
      if (before > 1) _input.zoomAt(after / before, midAfter);
      _input.panDrag(midBefore, midAfter);
    } else if (_panning[e.pointer] ?? false) {
      _input.panDrag(previous, current);
    } else {
      _input.orbitDrag(current - previous);
    }
    _pointers[e.pointer] = current;
  }

  void _up(PointerEvent e) {
    _pointers.remove(e.pointer);
    _panning.remove(e.pointer);
  }

  void _signal(PointerSignalEvent e) {
    if (!widget.enabled) return;
    // Claim the event so the browser does not also scroll or zoom the page.
    GestureBinding.instance.pointerSignalResolver.register(e, (event) {
      switch (event) {
        case PointerScrollEvent(kind: PointerDeviceKind.trackpad):
          // Two-finger swipe: the content follows the fingers.
          _input.panDrag(
            event.localPosition,
            event.localPosition - event.scrollDelta,
          );
        case PointerScrollEvent():
          // Mouse wheel: zoom toward the cursor.
          _input.zoomAt(
            math.exp(-event.scrollDelta.dy / 400),
            event.localPosition,
          );
        case PointerScaleEvent():
          // Pinch on the web arrives as a scale signal.
          _input.zoomAt(event.scale, event.localPosition);
        default:
          break;
      }
    });
  }

  void _panZoomStart(PointerPanZoomStartEvent e) {
    _lastScale = 1;
    _lastRotation = 0;
  }

  void _panZoomUpdate(PointerPanZoomUpdateEvent e) {
    if (!widget.enabled) return;
    // Trackpad gestures in the desktop app: pan, pinch and twist at once.
    final p = e.localPosition;
    if (e.localPanDelta != Offset.zero) {
      _input.panDrag(p, p + e.localPanDelta);
    }
    if (e.scale > 0 && (e.scale - _lastScale).abs() > 1e-4) {
      _input.zoomAt(e.scale / _lastScale, p);
      _lastScale = e.scale;
    }
    if ((e.rotation - _lastRotation).abs() > 1e-4) {
      _input.rotate(e.rotation - _lastRotation);
      _lastRotation = e.rotation;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _input.viewportSize = constraints.biggest;
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _up,
          onPointerSignal: _signal,
          onPointerPanZoomStart: _panZoomStart,
          onPointerPanZoomUpdate: _panZoomUpdate,
          child: widget.child,
        );
      },
    );
  }
}
