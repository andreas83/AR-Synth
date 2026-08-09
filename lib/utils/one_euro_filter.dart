import 'dart:math' as math;

/// A **1€ filter** (Casiez, Roussel & Vogel, CHI 2012): an adaptive low-pass
/// that smooths a noisy signal while keeping latency low. When the signal is
/// (nearly) still it filters hard to kill jitter; when it moves quickly it opens
/// up so the output tracks without lag.
///
/// Ideal for the raw MediaPipe landmark coordinates, which jitter frame-to-frame
/// even when a hand is held still. Pure Dart, so it is unit-testable.
class OneEuroFilter {
  OneEuroFilter({
    this.minCutoff = 1.2,
    this.beta = 0.02,
    this.dCutoff = 1.0,
  });

  /// Minimum cutoff frequency (Hz). Lower ⇒ smoother (but laggier) when still.
  final double minCutoff;

  /// Speed coefficient. Higher ⇒ less lag while the signal moves fast.
  final double beta;

  /// Cutoff frequency (Hz) for the derivative used to detect speed.
  final double dCutoff;

  double? _x; // last filtered value
  double? _dx; // last filtered derivative

  /// Whether the filter has seen at least one sample since construction/[reset].
  bool get hasValue => _x != null;

  /// The most recent filtered value, or null before the first sample.
  double? get value => _x;

  /// Forgets all history; the next [filter] call re-seeds from its input.
  void reset() {
    _x = null;
    _dx = null;
  }

  /// Smoothing factor for a low-pass at [cutoff] Hz over a step of [dt] seconds.
  static double _alpha(double cutoff, double dt) {
    final double tau = 1.0 / (2 * math.pi * cutoff);
    return 1.0 / (1.0 + tau / dt);
  }

  /// Filters [value]; [dt] is the elapsed time since the previous sample in
  /// seconds. A non-positive [dt] (or the first sample) passes [value] through
  /// untouched and seeds the filter.
  double filter(double value, double dt) {
    if (_x == null || dt <= 0) {
      _x = value;
      _dx = 0.0;
      return value;
    }
    // Low-pass the derivative, then use its magnitude to widen the cutoff.
    final double dxRaw = (value - _x!) / dt;
    final double aD = _alpha(dCutoff, dt);
    final double dx = aD * dxRaw + (1 - aD) * _dx!;
    _dx = dx;

    final double cutoff = minCutoff + beta * dx.abs();
    final double a = _alpha(cutoff, dt);
    final double x = a * value + (1 - a) * _x!;
    _x = x;
    return x;
  }
}
