import 'package:flutter_test/flutter_test.dart';
import 'package:writepapertex/src/features/compile/domain/latex_engine.dart';

void main() {
  const parser = LatexLogParser();

  test('keluhan penataan huruf bukan galat', () {
    final messages = parser.parse(
      './proposal.tex:122: Underfull \\hbox (badness 10000) in paragraph at lines 122--122',
    );
    expect(messages, hasLength(1));
    expect(messages.single.severity, LatexSeverity.warning);
    expect(messages.single.line, 122);
  });

  test('baris yang kelewat penuh juga bukan galat', () {
    final messages = parser.parse(
      './bab/01.tex:8: Overfull \\hbox (12.4pt too wide) in paragraph at lines 8--9',
    );
    expect(messages.single.severity, LatexSeverity.warning);
  });

  test('galat sungguhan tetap galat', () {
    final messages = parser.parse('./proposal.tex:42: Undefined control sequence.');
    expect(messages.single.severity, LatexSeverity.error);
    expect(messages.single.line, 42);
  });

  test('berkas yang tidak ada tetap galat', () {
    final messages = parser.parse("! LaTeX Error: File `gaya/itb-proposal.sty' not found.");
    expect(messages.single.severity, LatexSeverity.error);
  });

  test('peringatan LaTeX yang ditulis dengan bentuk berkas:baris tidak jadi merah', () {
    final messages = parser.parse(
      "./proposal.tex:3: Package hyperref Warning: Token not allowed in a PDF string.",
    );
    expect(messages.single.severity, LatexSeverity.warning);
  });
}
