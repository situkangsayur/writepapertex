import 'dart:io';

import 'package:flutter/material.dart';

/// True on a device driven by fingers.
final bool isTouchPlatform = Platform.isAndroid || Platform.isIOS;

/// Material's window size classes, named for what WritePaperTeX does at each.
///
/// An editor needs more width than a reader: the file tree, the source and
/// the PDF all want to be visible at once, and that only fits on a tablet in
/// landscape or a desktop.
enum LayoutSize {
  /// Phone: one pane at a time.
  compact,

  /// Tablet in portrait: source and PDF, file tree in a drawer.
  medium,

  /// Tablet in landscape, or a desktop: all three.
  expanded;

  static const double mediumMin = 600;
  static const double expandedMin = 1100;

  static LayoutSize fromWidth(double width) {
    if (width >= expandedMin) return LayoutSize.expanded;
    if (width >= mediumMin) return LayoutSize.medium;
    return LayoutSize.compact;
  }

  static LayoutSize of(BuildContext context) => fromWidth(MediaQuery.sizeOf(context).width);

  /// The file tree only stays on screen at the largest size.
  bool get treeInDrawer => this != LayoutSize.expanded;

  /// Source and PDF side by side rather than behind tabs.
  bool get showsSourceAndPdf => this != LayoutSize.compact;
}

/// Touch targets need room; a 32dp row is a mis-tap on glass.
double get treeRowHeight => isTouchPlatform ? 44 : 32;
