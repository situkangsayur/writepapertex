import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/latex_table.dart';

/// Builds a table as a grid, and hands back the LaTeX.
///
/// Returns null when nothing should be inserted.
Future<String?> showTableEditor(BuildContext context, {LatexTable? initial}) => showDialog<String>(
  context: context,
  builder: (context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: _TableEditor(initial: initial ?? LatexTable.empty()),
  ),
);

class _TableEditor extends StatefulWidget {
  const _TableEditor({required this.initial});

  final LatexTable initial;

  @override
  State<_TableEditor> createState() => _TableEditorState();
}

class _TableEditorState extends State<_TableEditor> {
  late LatexTable _table = widget.initial;
  late final TextEditingController _caption = TextEditingController(text: _table.caption);
  late final TextEditingController _label = TextEditingController(text: _table.label);

  /// One controller per cell, rebuilt whenever the shape changes, so typing
  /// does not fight the grid being resized underneath it.
  final Map<String, TextEditingController> _cells = <String, TextEditingController>{};

  @override
  void dispose() {
    _caption.dispose();
    _label.dispose();
    for (final c in _cells.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// The controller owns its cell's text while the editor is open.
  ///
  /// It is deliberately never written to from a rebuild. Doing that made the
  /// field fight the person typing into it and characters went missing —
  /// "Waktu" arrived as "Wa". The model is brought up to date from the
  /// controllers instead, at the few moments that matters.
  TextEditingController _cellController(int r, int c) =>
      _cells.putIfAbsent('$r:$c', () => TextEditingController(text: _table.rows[r][c]));

  /// Copies what is in the fields back into the table.
  LatexTable _synced() {
    var table = _table;
    for (var r = 0; r < table.rowCount; r++) {
      for (var c = 0; c < table.columnCount; c++) {
        final controller = _cells['$r:$c'];
        if (controller != null && controller.text != table.rows[r][c]) {
          table = table.setCell(r, c, controller.text);
        }
      }
    }
    return table.copyWith(caption: _caption.text, label: _label.text);
  }

  void _resetControllers() {
    for (final c in _cells.values) {
      c.dispose();
    }
    _cells.clear();
  }

  /// [reshaped] means rows or columns moved, so the controllers no longer
  /// line up with the cells and have to be rebuilt from the model.
  void _apply(LatexTable Function(LatexTable current) change, {bool reshaped = false}) {
    final next = change(reshaped ? _synced() : _table);
    setState(() {
      if (reshaped) _resetControllers();
      _table = next;
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Papan klip kosong')));
      }
      return;
    }
    // Caption and label are the author's, not the spreadsheet's, so they stay.
    _apply(
      (_) => LatexTable.fromDelimited(text).copyWith(caption: _caption.text, label: _label.text),
      reshaped: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text('Tabel', style: text.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste, size: 18),
                  label: const Text('Tempel dari spreadsheet'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _caption,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      labelText: 'Keterangan',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _label,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      labelText: 'Label',
                      hintText: 'tab:hasil',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(child: _grid()),
            const SizedBox(height: 8),
            _options(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Batal'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_synced().toLatex()),
                  child: const Text('Sisipkan'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid() => FocusTraversalGroup(
    // Tab must walk the cells in reading order. Without an explicit order it
    // walks every icon button between them instead, which for a table editor
    // makes the keyboard useless.
    policy: OrderedTraversalPolicy(),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Column headers: alignment and delete, above each column.
            Row(
              children: <Widget>[
                const SizedBox(width: 34),
                for (var c = 0; c < _table.columnCount; c++)
                  SizedBox(
                    width: 150,
                    child: ExcludeFocusTraversal(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          for (final align in ColumnAlign.values)
                            IconButton(
                              iconSize: 16,
                              visualDensity: VisualDensity.compact,
                              tooltip: align.label,
                              isSelected: _table.aligns[c] == align,
                              icon: Icon(switch (align) {
                                ColumnAlign.left => Icons.format_align_left,
                                ColumnAlign.center => Icons.format_align_center,
                                ColumnAlign.right => Icons.format_align_right,
                              }),
                              onPressed: () => _apply((t) => t.setAlign(c, align)),
                            ),
                          IconButton(
                            iconSize: 16,
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Hapus kolom',
                            icon: const Icon(Icons.close),
                            onPressed: _table.columnCount <= 1
                                ? null
                                : () => _apply((t) => t.removeColumn(c), reshaped: true),
                          ),
                        ],
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: 'Tambah kolom',
                  icon: const Icon(Icons.add),
                  onPressed: () => _apply((t) => t.addColumn(), reshaped: true),
                ),
              ],
            ),
            for (var r = 0; r < _table.rowCount; r++)
              Row(
                children: <Widget>[
                  SizedBox(
                    width: 34,
                    child: ExcludeFocusTraversal(
                      child: IconButton(
                        iconSize: 16,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Hapus baris',
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _table.rowCount <= 1
                            ? null
                            : () => _apply((t) => t.removeRow(r), reshaped: true),
                      ),
                    ),
                  ),
                  for (var c = 0; c < _table.columnCount; c++)
                    Padding(
                      padding: const EdgeInsets.all(2),
                      child: SizedBox(
                        width: 146,
                        child: FocusTraversalOrder(
                          order: NumericFocusOrder((r * _table.columnCount + c).toDouble()),
                          child: TextField(
                            controller: _cellController(r, c),
                            textAlign: switch (_table.aligns[c]) {
                              ColumnAlign.left => TextAlign.left,
                              ColumnAlign.center => TextAlign.center,
                              ColumnAlign.right => TextAlign.right,
                            },
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: r < _table.headerRows
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.only(left: 34, top: 4),
              child: TextButton.icon(
                onPressed: () => _apply((t) => t.addRow(), reshaped: true),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Tambah baris'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _options() => Wrap(
    spacing: 16,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: <Widget>[
      Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text('Baris judul'),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _table.headerRows.clamp(0, _table.rowCount),
            onChanged: (v) => v == null ? null : _apply((t) => t.copyWith(headerRows: v)),
            items: <DropdownMenuItem<int>>[
              for (var i = 0; i <= _table.rowCount; i++)
                DropdownMenuItem<int>(value: i, child: Text('$i')),
            ],
          ),
        ],
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Switch(
            value: _table.booktabs,
            onChanged: (v) => _apply((t) => t.copyWith(booktabs: v)),
          ),
          const SizedBox(width: 4),
          // Said out loud because the alternative looks the same in the
          // editor and only differs in the PDF.
          Tooltip(
            message:
                r'booktabs: \toprule, \midrule, \bottomrule. '
                r'Tanpa ini dipakai \hline, yang garis gandanya jarang benar.',
            child: const Text('booktabs'),
          ),
        ],
      ),
    ],
  );
}
