import 'package:flutter_test/flutter_test.dart';
import 'package:writepapertex/src/features/table/domain/latex_table.dart';

void main() {
  LatexTable sample() => const LatexTable(
    rows: <List<String>>[
      <String>['Metode', 'Akurasi'],
      <String>['Dasar', '0,91'],
      <String>['Usulan', '0,97'],
    ],
    aligns: <ColumnAlign>[ColumnAlign.left, ColumnAlign.right],
    caption: 'Perbandingan',
    label: 'tab:hasil',
  );

  group('generated LaTeX', () {
    test('uses booktabs rules, with a midrule under the heading', () {
      final tex = sample().toLatex();
      expect(tex, contains(r'\toprule'));
      expect(tex, contains(r'\midrule'));
      expect(tex, contains(r'\bottomrule'));
      expect(tex, isNot(contains(r'\hline')));
      // The midrule sits after the heading row, not anywhere else.
      expect(tex.indexOf(r'\midrule'), greaterThan(tex.indexOf('Metode')));
      expect(tex.indexOf(r'\midrule'), lessThan(tex.indexOf('Dasar')));
    });

    test('the preamble matches the number of columns', () {
      expect(sample().toLatex(), contains(r'\begin{tabular}{lr}'));
      expect(sample().addColumn().toLatex(), contains(r'\begin{tabular}{lrr}'));
    });

    test('every row ends with a row separator and joins with ampersands', () {
      expect(sample().toLatex(), contains(r'Dasar & 0,91 \\'));
    });

    test('caption and label are written when the table floats', () {
      final tex = sample().toLatex();
      expect(tex, contains(r'\begin{table}[ht]'));
      expect(tex, contains(r'\caption{Perbandingan}'));
      expect(tex, contains(r'\label{tab:hasil}'));
      expect(tex, contains(r'\centering'));
    });

    test('without floating, only the tabular is produced', () {
      final tex = sample().toLatex(floating: false);
      expect(tex, isNot(contains(r'\begin{table}')));
      expect(tex, startsWith(r'\begin{tabular}'));
      expect(tex.trimRight(), endsWith(r'\end{tabular}'));
    });

    test('hline mode is available for people who want it', () {
      final tex = sample().copyWith(booktabs: false).toLatex();
      expect(tex, contains(r'\hline'));
      expect(tex, isNot(contains(r'\toprule')));
    });

    test('no heading rows means no midrule', () {
      expect(sample().copyWith(headerRows: 0).toLatex(), isNot(contains(r'\midrule')));
    });

    test('characters that would break the table are escaped', () {
      final tex = LatexTable(
        rows: const <List<String>>[
          <String>[r'a & b', '50%', r'x_y', r'$z$'],
        ],
        aligns: const <ColumnAlign>[
          ColumnAlign.left,
          ColumnAlign.left,
          ColumnAlign.left,
          ColumnAlign.left,
        ],
        headerRows: 0,
      ).toLatex();
      expect(tex, contains(r'a \& b'));
      expect(tex, contains(r'50\%'));
      expect(tex, contains(r'x\_y'));
      expect(tex, contains(r'\$z\$'));
    });
  });

  group('editing the grid', () {
    test('a cell can be set without disturbing the others', () {
      final t = sample().setCell(1, 1, '0,99');
      expect(t.rows[1][1], '0,99');
      expect(t.rows[2][1], '0,97');
    });

    test('adding a row keeps every row the same width', () {
      final t = sample().addRow();
      expect(t.rowCount, 4);
      expect(t.rows.every((r) => r.length == t.columnCount), isTrue);
    });

    test('adding a column widens every row and the preamble together', () {
      final t = sample().addColumn();
      expect(t.columnCount, 3);
      expect(t.aligns.length, 3);
      expect(t.rows.every((r) => r.length == 3), isTrue);
    });

    test('a column can be removed from the middle', () {
      final t = sample().addColumn(at: 1).removeColumn(1);
      expect(t.columnCount, 2);
      expect(t.rows.first, <String>['Metode', 'Akurasi']);
    });

    test('the last row and the last column cannot be removed', () {
      var t = LatexTable.empty(rows: 1, columns: 1);
      t = t.removeRow(0).removeColumn(0);
      expect(t.rowCount, 1);
      expect(t.columnCount, 1);
    });

    test('deleting rows never leaves the heading count past the end', () {
      var t = sample().copyWith(headerRows: 3);
      t = t.removeRow(0).removeRow(0);
      expect(t.headerRows, lessThanOrEqualTo(t.rowCount));
      // And it still generates valid LaTeX.
      expect(t.toLatex(), contains(r'\begin{tabular}'));
    });

    test('alignment is per column', () {
      final t = sample().setAlign(0, ColumnAlign.center);
      expect(t.toLatex(), contains(r'\begin{tabular}{cr}'));
    });
  });

  group('pasting', () {
    test('a tab-separated spreadsheet selection becomes a grid', () {
      final t = LatexTable.fromDelimited('Metode\tAkurasi\nDasar\t0,91\nUsulan\t0,97');
      expect(t.rowCount, 3);
      expect(t.columnCount, 2);
      expect(t.rows[2], <String>['Usulan', '0,97']);
    });

    test('a comma-separated file works too', () {
      final t = LatexTable.fromDelimited('a,b\n1,2');
      expect(t.rows.first, <String>['a', 'b']);
    });

    test('a quoted field containing the separator stays one cell', () {
      final t = LatexTable.fromDelimited('a,b\n"satu, dua",3');
      expect(t.rows[1], <String>['satu, dua', '3']);
    });

    test('doubled quotes inside a field become one quote', () {
      final t = LatexTable.fromDelimited('a\n"dia bilang ""ya"""');
      expect(t.rows[1].first, 'dia bilang "ya"');
    });

    test('a short row is padded rather than losing the rest of the data', () {
      final t = LatexTable.fromDelimited('a,b,c\n1,2');
      expect(t.columnCount, 3);
      expect(t.rows[1], <String>['1', '2', '']);
    });

    test('numeric columns are guessed and right-aligned', () {
      final t = LatexTable.fromDelimited('Metode,Akurasi\nDasar,0,91'.replaceAll('0,91', '0.91'));
      expect(t.aligns.first, ColumnAlign.left);
      expect(t.aligns.last, ColumnAlign.right);
    });

    test('empty text yields a usable table rather than nothing', () {
      final t = LatexTable.fromDelimited('   \n\n');
      expect(t.rowCount, 1);
      expect(t.columnCount, 1);
      expect(t.toLatex(), contains(r'\begin{tabular}'));
    });
  });

  test('an empty table starts with the first column left and the rest right', () {
    final t = LatexTable.empty(columns: 3);
    expect(t.aligns, <ColumnAlign>[ColumnAlign.left, ColumnAlign.right, ColumnAlign.right]);
  });
}
