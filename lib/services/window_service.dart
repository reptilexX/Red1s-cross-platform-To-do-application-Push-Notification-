import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';

/// Controls the native desktop window: normal mode vs. a small
/// always-on-top "mini" window pinned to a screen corner.
///
/// Has no effect on Android/iOS/web — guard with [isDesktop] before
/// calling anything here.
///
/// Note: this keeps the normal OS title bar even in mini mode (rather
/// than a fully frameless custom one). That's a deliberate choice —
/// it means Windows/macOS/Linux handle dragging and closing for us
/// natively. The maximize button and resize handles are explicitly
/// disabled in mini mode so the window can't accidentally snap to
/// full height (a real bug in an earlier version of this file).
class WindowService {
  static const Size normalSize = Size(420, 700);
  static const Size normalMinSize = Size(320, 400);
  static const Size miniSize = Size(260, 200);
  static const Size miniMinSize = Size(220, 160);

  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// Call once at startup, before runApp(), only on desktop platforms.
  static Future<void> init() async {
    if (!isDesktop) return;
    await windowManager.ensureInitialized();

    const options = WindowOptions(
      size: normalSize,
      minimumSize: normalMinSize,
      center: true,
      titleBarStyle: TitleBarStyle.normal,
      title: 'To-Do',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  /// Shrinks the window, pins it on top of other windows, and moves it
  /// to the bottom-right corner of the primary monitor.
  static Future<void> enterMiniMode() async {
    if (!isDesktop) return;

    // IMPORTANT: lower the minimum size FIRST. The window manager clamps
    // setSize() to whatever minimumSize is currently set, so leaving it
    // at the normal-mode minimum (320x400) silently blocks shrinking
    // below that, no matter what size you ask for afterwards.
    await windowManager.setMinimumSize(miniMinSize);
    await windowManager.setMaximumSize(miniSize);

    await windowManager.setResizable(false);
    // Explicitly disable the maximize button so double-clicking the
    // title bar (or clicking □) can't snap the window to full height.
    await _trySetMaximizable(false);

    await windowManager.setSize(miniSize);
    await windowManager.setAlwaysOnTop(true);
    await _moveToBottomRightCorner();
  }

  /// Restores the normal window: resizable, no longer pinned on top,
  /// centered at the regular size.
  static Future<void> exitMiniMode() async {
    if (!isDesktop) return;
    await windowManager.setAlwaysOnTop(false);
    await _trySetMaximizable(true);
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(normalMinSize);
    // NOTE: double.infinity does NOT survive the platform channel call
    // reliably (it doesn't serialize the way a normal number does), so
    // the old, smaller maximum size was silently staying in effect —
    // that's why "restore" only grew the window a little. A large
    // finite size works correctly instead.
    await windowManager.setMaximumSize(const Size(4000, 4000));
    await windowManager.setSize(normalSize);
    await windowManager.center();
  }

  /// setMaximizable isn't implemented on every platform/version — don't
  /// let a missing-plugin exception break entering/exiting mini mode.
  static Future<void> _trySetMaximizable(bool value) async {
    try {
      await windowManager.setMaximizable(value);
    } catch (_) {
      // Ignore — resizable(false) still prevents manual resizing even
      // if this particular call isn't supported on this platform.
    }
  }

  static Future<void> _moveToBottomRightCorner() async {
    // Use the actual monitor's size (NOT the app's own window size).
    final display = await screenRetriever.getPrimaryDisplay();
    final screenSize = display.size;

    const margin = 24.0;
    const taskbarAllowance = 56.0; // rough space for the Windows taskbar
    final x = screenSize.width - miniSize.width - margin;
    final y = screenSize.height - miniSize.height - margin - taskbarAllowance;
    await windowManager.setPosition(Offset(x, y));
  }
}
