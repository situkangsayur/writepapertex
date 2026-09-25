import 'package:meta/meta.dart';

/// How a column's text sits.
enum ColumnAlign {
  left('l', 'Kiri'),
  center('c', 'Tengah'),
  right('r', 'Kanan');

  const ColumnAlign(this.spec, this.label);

  final String spec;
  final String label;

  static ColumnAlign fromSpec(String s) => switch (s) {
    'c' => ColumnAlign.center,
    'r' => ColumnAlign.right,
    _ => ColumnAlign.left,
  };
}

/// A table being edited as a grid, rather than as a line of `&` and `\\`.
///
/// Tables are the worst part of LaTeX to write by hand: the separators are
/// invisible, the column count has to match the preamble, and one missing `&`
/// breaks the whole document. On a tablet it is worse still. So the grid is
/// the thing being edited, and the LaTeX is generated from it.
@immutable
class LatexTable {
  const LatexTable({
    required this.rows,
    required this.aligns,
    this.headerRows = 1,
    this.caption = '',
    this.label = '',
    this.booktabs = true,
  });

  /// Cell text, row by row. Every row has [columnCount] entries.
  final List<List<String>> rows;

  final List<ColumnAlign> aligns;

  /// How many rows at the top are headings, separated by a rule.
  final int headerRows;

  final String caption;
  final String label;

  /// `\toprule`/`\midrule`/`\bottomrule` instead of `\hline` everywhere.
  ///
  /// Doubled `\hline`s almost never look right, and booktabs is what every
  /// journal style guide asks for.
  final bool booktabs;

  int get rowCount => rows.length;
  int get columnCount => aligns.length;

  /// An empty table to start from.
  factory LatexTable.empty({int rows = 3, int columns = 3}) => LatexTable(
    rows: <List<String>>[
      for (var r = 0; r < rows; r++) <String>[for (var c = 0; c < columns; c++) ''],
    ],
    aligns: <ColumnAlign>[
      // The first column is usually a label and the rest numbers, which read
      // better right-aligned.
      for (var c = 0; c < columns; c++) c == 0 ? ColumnAlign.left : ColumnAlign.right,
    ],
  );

  LatexTable copyWith({
    List<List<String>>? rows,
    List<ColumnAlign>? aligns,
    int? headerRows,
    String? caption,
    String? label,
    bool? booktabs,
  }) => LatexTable(
    rows: rows ?? this.rows,
    aligns: aligns ?? this.aligns,
    headerRows: headerRows ?? this.headerRows,
    caption: caption ?? this.caption,
    label: label ?? this.label,
    booktabs: booktabs ?? this.booktabs,
  );

  LatexTable setCell(int row, int column, String value) {
    final copy = <List<String>>[for (final r in rows) List<String>.of(r)];
    copy[row][column] = value;
    return copyWith(rows: copy);
  }

  LatexTable addRow({int? at}) {
    final copy = <List<String>>[for (final r in rows) List<String>.of(r)];
    copy.insert(at ?? copy.length, <String>[for (var c = 0; c < columnCount; c++) '']);
    return copyWith(rows: copy);
  }

  LatexTable removeRow(int at) {
    if (rowCount <= 1) return this;
    final copy = <List<String>>[for (final r in rows) List<String>.of(r)];
    copy.removeAt(at);
    // A header row that was deleted must not leave the count pointing past
    // the end of the table.
    return copyWith(rows: copy, headerRows: headerRows.clamp(0, copy.length));
  }

  LatexTable addColumn({int? at}) {
    final index = at ?? columnCount;
    final copy = <List<String>>[for (final r in rows) List<String>.of(r)..insert(index, '')];
    final newAligns = List<ColumnAlign>.of(aligns)..insert(index, ColumnAlign.right);
    return copyWith(rows: copy, aligns: newAligns);
  }

  LatexTable removeColumn(int at) {
    if (columnCount <= 1) return this;
    final copy = <List<String>>[for (final r in rows) List<String>.of(r)..removeAt(at)];
    final newAligns = List<ColumnAlign>.of(aligns)..removeAt(at);
    return copyWith(rows: copy, aligns: newAligns);
  }

  LatexTable setAlign(int column, ColumnAlign align) {
    final copy = List<ColumnAlign>.of(aligns);
    copy[column] = align;
    return copyWith(aligns: copy);
  }

  /// Writes the LaTeX.
  ///
  /// [floating] wraps it in a `table` environment with the caption and label;
  /// without it only the `tabular` is produced, which is what is wanted when
  /// replacing a table already sitting inside one.
  String toLatex({bool floating = true, String indent = ''}) {
    final b = StringBuffer();
    final inner = floating ? '$indent  ' : indent;

    if (floating) {
      b.writeln('$indent\\begin{table}[ht]');
      b.writeln('$indent  \\centering');
      if (caption.isNotEmpty) b.writeln('$indent  \\caption{${_escape(caption)}}');
      if (label.isNotEmpty) b.writeln('$indent  \\label{$label}');
    }

    b.writeln('$inner\\begin{tabular}{${aligns.map((a) => a.spec).join()}}');
    b.writeln('$inner  ${booktabs ? r'\toprule' : r'\hline'}');

    for (var r = 0; r < rows.length; r++) {
      final cells = rows[r].map(_escape).join(' & ');
      b.writeln('$inner  $cells \\\\');
      final isLastHeader = headerRows > 0 && r == headerRows - 1 && r < rows.length - 1;
      if (isLastHeader) b.writeln('$inner  ${booktabs ? r'\midrule' : r'\hline'}');
    }

    b.writeln('$inner  ${booktabs ? r'\bottomrule' : r'\hline'}');
    b.write('$inner\\end{tabular}');

    if (floating) {
      b.writeln();
      b.write('$indent\\end{table}');
    }
    return b.toString();
  }

  /// Characters that would otherwise change the table's shape or vanish.
  static String _escape(String s) => s
      .replaceAll(r'\', r'\textbackslash{}')
      .replaceAll('&', r'\&')
      .replaceAll('%', r'\%')
      .replaceAll(r'$', r'\$')
      .replaceAll('#', r'\#')
      .replaceAll('_', r'\_')
      .replaceAll('{', r'\{')
      .replaceAll('}', r'\}');

  /// Builds a table from delimited text — a spreadsheet selection, or a CSV.
  ///
  /// The delimiter is guessed because pasting is the point: being asked which
  /// separator was used defeats it.
  factory LatexTable.fromDelimited(String text, {String? delimiter}) {
    final lines = text.split(RegExp(r'\r\n|\r|\n')).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return LatexTable.empty(rows: 1, columns: 1);

    final sep = delimiter ?? _guessDelimiter(lines.first);
    final grid = <List<String>>[for (final line in lines) _splitRow(line, sep)];

    // Ragged input is padded rather than rejected: a short last row is a
    // normal thing to paste, and losing the data would be worse.
    final width = grid.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    for (final row in grid) {
      while (row.length < width) {
        row.add('');
      }
    }

    return LatexTable(
      rows: grid,
      aligns: <ColumnAlign>[
        for (var c = 0; c < width; c++)
          _columnLooksNumeric(grid, c) ? ColumnAlign.right : ColumnAlign.left,
      ],
    );
  }

  static String _guessDelimiter(String line) {
    for (final candidate in <String>['\t', ';', ',', '|']) {
      if (line.contains(candidate)) return candidate;
    }
    return ',';
  }

  /// Splits on [sep], honouring the double quotes CSV uses around a field
  /// that contains the separator.
  static List<String> _splitRow(String line, String sep) {
    final out = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (!inQuotes && line.startsWith(sep, i)) {
        out.add(buffer.toString().trim());
        buffer.clear();
        i += sep.length - 1;
      } else {
        buffer.write(ch);
      }
    }
    out.add(buffer.toString().trim());
    return out;
  }

  /// True when every filled cell below the heading reads as a number.
  static bool _columnLooksNumeric(List<List<String>> grid, int column) {
    var seen = 0;
    for (var r = 1; r < grid.length; r++) {
      if (column >= grid[r].length) continue;
      final cell = grid[r][column].trim();
      if (cell.isEmpty) continue;
      // Indonesian decimals use a comma.
      if (!RegExp(r'^[-+]?[\d.,]+%?$').hasMatch(cell)) return false;
      seen++;
    }
    return seen > 0;
  }
}
