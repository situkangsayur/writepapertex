import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writepapertex/src/core/utils/layout_size.dart';

void main() {
  test('a phone gets one pane at a time', () {
    expect(LayoutSize.fromWidth(360), LayoutSize.compact);
    expect(LayoutSize.fromWidth(599), LayoutSize.compact);
    expect(LayoutSize.compact.showsSourceAndPdf, isFalse);
    expect(LayoutSize.compact.treeInDrawer, isTrue);
  });

  test('a tablet in portrait shows source and PDF, tree in a drawer', () {
    expect(LayoutSize.fromWidth(600), LayoutSize.medium);
    expect(LayoutSize.fromWidth(960), LayoutSize.medium, reason: 'Moto Pad tegak');
    expect(LayoutSize.medium.showsSourceAndPdf, isTrue);
    expect(LayoutSize.medium.treeInDrawer, isTrue);
  });

  test('a tablet in landscape shows all three panes', () {
    expect(LayoutSize.fromWidth(1100), LayoutSize.expanded);
    expect(LayoutSize.fromWidth(1536), LayoutSize.expanded, reason: 'Moto Pad mendatar');
    expect(LayoutSize.expanded.treeInDrawer, isFalse);
  });

  testWidgets('the width decides, not the height', (tester) async {
    Future<LayoutSize> measure(Size size) async {
      late LayoutSize seen;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: size),
          child: Builder(
            builder: (context) {
              seen = LayoutSize.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      return seen;
    }

    expect(await measure(const Size(960, 1536)), LayoutSize.medium);
    expect(await measure(const Size(1536, 960)), LayoutSize.expanded);
  });
}
