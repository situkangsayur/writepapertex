import 'package:flutter_test/flutter_test.dart';
import 'package:writepapertex/src/features/compile/domain/latex_engine.dart';

void main() {
  test('nomor rujukan yang belum mantap minta dijalankan lagi', () {
    expect(logAsksForRerun('LaTeX Warning: Label(s) may have changed. Rerun to get cross-references right.'), isTrue);
  });

  test('sitasi yang belum dikenal minta dijalankan lagi', () {
    expect(logAsksForRerun("LaTeX Warning: Citation `nielsen2010' on page 3 undefined on input line 42."), isTrue);
  });

  test('daftar pustaka yang belum terbentuk minta dijalankan lagi', () {
    expect(logAsksForRerun('No file proposal.bbl.'), isTrue);
  });

  test('log yang bersih tidak minta apa-apa', () {
    expect(logAsksForRerun('Output written on proposal.pdf (28 pages).'), isFalse);
  });

  test('peringatan hbox biasa bukan alasan mengulang', () {
    expect(logAsksForRerun('Underfull \\hbox (badness 4048) in paragraph at lines 122--122'), isFalse);
  });
}
