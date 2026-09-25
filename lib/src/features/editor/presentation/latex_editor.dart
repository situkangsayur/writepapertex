import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/autocomplete.dart';
import '../domain/latex_language.dart';

/// The source editor: LaTeX colouring, autocomplete, and a key row for the
/// characters Android keyboards bury.
class LatexEditor extends StatefulWidget {
  const LatexEditor({
    required this.controller,
    required this.autocomplete,
    this.onSave,
    this.showKeyRow = false,
    super.key,
  });

  final TextEditingController controller;
  final LatexAutocomplete autocomplete;
  final VoidCallback? onSave;

  /// The extra key row, worth its space only on a touch keyboard.
  final bool showKeyRow;

  @override
  State<LatexEditor> createState() => _LatexEditorState();
}

class _LatexEditorState extends State<LatexEditor> {
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();
  List<Completion> _suggestions = const <Completion>[];
  CompletionRequest? _request;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refreshSuggestions);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refreshSuggestions);
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _refreshSuggestions() {
    final selection = widget.controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const <Completion>[]);
      return;
    }
    final request = widget.autocomplete.requestAt(widget.controller.text, selection.baseOffset);
    final suggestions = widget.autocomplete.suggest(request);
    if (suggestions.length != _suggestions.length || _request?.prefix != request.prefix) {
      setState(() {
        _request = request;
        // Long lists are noise; the first ones are the ones meant.
        _suggestions = suggestions.take(12).toList(growable: false);
      });
    }
  }

  void _accept(Completion completion) {
    final request = _request;
    if (request == null) return;
    final text = widget.controller.text;
    final end = widget.controller.selection.baseOffset;

    String inserted;
    int caret;
    if (completion.kind == CompletionKind.environment) {
      // Completing an environment writes the closing tag too: forgetting
      // \end{...} is the single most common way a LaTeX file stops compiling.
      final expanded = expandEnvironment(completion.insert, indent: _indentAt(text, end));
      inserted = expanded.text;
      caret = expanded.caret;
      // Replace from the \begin{ itself, not just the word inside it.
      final beginAt = text.lastIndexOf(r'\begin{', end);
      final endAt = text.lastIndexOf(r'\end{', end);
      final from = beginAt > endAt ? beginAt : endAt;
      if (from >= 0) {
        _replace(from, end, inserted, caret);
        return;
      }
    } else {
      inserted = completion.insert;
      caret = completion.cursorOffset ?? inserted.length;
    }
    _replace(request.replaceFrom, end, inserted, caret);
  }

  void _replace(int from, int to, String inserted, int caret) {
    final text = widget.controller.text;
    widget.controller.value = TextEditingValue(
      text: text.replaceRange(from, to, inserted),
      selection: TextSelection.collapsed(offset: from + caret),
    );
    setState(() => _suggestions = const <Completion>[]);
  }

  /// The leading whitespace of the line the caret is on.
  String _indentAt(String text, int offset) {
    final lineStart = text.lastIndexOf('\n', offset - 1) + 1;
    final line = text.substring(lineStart, offset);
    return RegExp(r'^\s*').firstMatch(line)?.group(0) ?? '';
  }

  void _insertRaw(String s, {int? caretBack}) {
    final selection = widget.controller.selection;
    final at = selection.isValid ? selection.baseOffset : widget.controller.text.length;
    final text = widget.controller.text;
    widget.controller.value = TextEditingValue(
      text: text.replaceRange(at, selection.isValid ? selection.extentOffset : at, s),
      selection: TextSelection.collapsed(offset: at + s.length - (caretBack ?? 0)),
    );
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        Expanded(
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Shortcuts(
                  shortcuts: <ShortcutActivator, Intent>{
                    const SingleActivator(LogicalKeyboardKey.keyS, control: true):
                        const _SaveIntent(),
                  },
                  child: Actions(
                    actions: <Type, Action<Intent>>{
                      _SaveIntent: CallbackAction<_SaveIntent>(
                        onInvoke: (_) {
                          widget.onSave?.call();
                          return null;
                        },
                      ),
                    },
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focus,
                      scrollController: _scroll,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      keyboardType: TextInputType.multiline,
                      // Autocorrect rewrites \section into \Section, and
                      // suggestions fight the completion list for the same
                      // strip of screen.
                      autocorrect: false,
                      enableSuggestions: false,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 14, height: 1.45),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.fromLTRB(14, 12, 14, 12),
                      ),
                    ),
                  ),
                ),
              ),
              if (_suggestions.isNotEmpty)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 8,
                  child: _SuggestionBar(suggestions: _suggestions, onAccept: _accept),
                ),
            ],
          ),
        ),
        if (widget.showKeyRow)
          _KeyRow(onInsert: _insertRaw, background: scheme.surfaceContainerHighest),
      ],
    );
  }
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}

class _SuggestionBar extends StatelessWidget {
  const _SuggestionBar({required this.suggestions, required this.onAccept});

  final List<Completion> suggestions;
  final ValueChanged<Completion> onAccept;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(10),
      color: scheme.surfaceContainerHighest,
      child: SizedBox(
        // Tall enough for the label and its one-line description; at 46 the
        // description was clipped in half, which looked like a rendering bug.
        height: 56,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          itemCount: suggestions.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, i) {
            final c = suggestions[i];
            return ActionChip(
              visualDensity: VisualDensity.compact,
              label: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(c.label, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
                  if (c.detail.isNotEmpty)
                    Text(c.detail, style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant)),
                ],
              ),
              onPressed: () => onAccept(c),
            );
          },
        ),
      ),
    );
  }
}

/// The characters LaTeX needs constantly and Android keyboards hide.
class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.onInsert, required this.background});

  final void Function(String, {int? caretBack}) onInsert;
  final Color background;

  static const List<(String, String, int)> _keys = <(String, String, int)>[
    (r'\', r'\', 0),
    ('{ }', '{}', 1),
    (r'$', r'$', 0),
    ('&', '&', 0),
    ('%', '%', 0),
    ('_', '_', 0),
    ('^', '^', 0),
    ('~', '~', 0),
    (r'\\', '\\\\\n', 0),
    ('[ ]', '[]', 1),
  ];

  @override
  Widget build(BuildContext context) => Material(
    color: background,
    child: SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        itemCount: _keys.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final (label, insert, back) = _keys[i];
          return OutlinedButton(
            onPressed: () => onInsert(insert, caretBack: back),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(44, 34),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(label, style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
          );
        },
      ),
    ),
  );
}
