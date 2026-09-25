import 'package:flutter_test/flutter_test.dart';
import 'package:writepapertex/src/features/editor/domain/autocomplete.dart';
import 'package:writepapertex/src/features/editor/domain/latex_language.dart';

void main() {
  const auto = LatexAutocomplete();

  CompletionRequest at(String textWithCaret) {
    final offset = textWithCaret.indexOf('|');
    expect(offset, isNot(-1), reason: 'tandai posisi kursor dengan |');
    return auto.requestAt(textWithCaret.replaceFirst('|', ''), offset);
  }

  group('what the caret is in', () {
    test('a backslash starts a command', () {
      final r = at(r'Teks \sec|');
      expect(r.context, CompletionContext.command);
      expect(r.prefix, 'sec');
      // Replacement covers the backslash too.
      expect(r.replaceFrom, r'Teks '.length);
    });

    test('a bare backslash offers everything', () {
      final r = at(r'\|');
      expect(r.context, CompletionContext.command);
      expect(r.prefix, isEmpty);
      expect(auto.suggest(r).length, LatexLanguage.commands.length);
    });

    test(r'\begin{ and \end{ ask for an environment', () {
      expect(at(r'\begin{tab|').context, CompletionContext.environment);
      expect(at(r'\end{doc|').context, CompletionContext.environment);
    });

    test(r'\ref and friends ask for a label, \cite for a key', () {
      expect(at(r'\ref{fig|').context, CompletionContext.reference);
      expect(at(r'\eqref{eq|').context, CompletionContext.reference);
      expect(at(r'\cite{kar|').context, CompletionContext.citation);
      expect(at(r'\citep{kar|').context, CompletionContext.citation);
    });

    test('ordinary prose offers nothing', () {
      final r = at('Menulis kalimat biasa|');
      expect(r.context, CompletionContext.none);
      expect(auto.suggest(r), isEmpty);
    });

    test('a closed brace ends the argument', () {
      // The caret is past the closing brace, so this is prose again.
      expect(at(r'\ref{fig:a} lalu|').context, CompletionContext.none);
    });

    test('an argument wins over the command that owns it', () {
      // Inside \ref{ the backslash rule would otherwise offer commands.
      final r = at(r'\ref{s|');
      expect(r.context, CompletionContext.reference);
      expect(r.prefix, 's');
    });
  });

  group('ranking', () {
    test('a prefix match comes before a mere containment', () {
      // \ref starts with "ref"; \eqref only contains it.
      final labels = auto.suggest(at(r'\ref|')).map((c) => c.label).toList();
      expect(labels.first, r'\ref');
      expect(labels, contains(r'\eqref'));
      expect(labels.indexOf(r'\ref'), lessThan(labels.indexOf(r'\eqref')));
    });

    test('only what matches is offered', () {
      final labels = auto.suggest(at(r'\sub|')).map((c) => c.label).toList();
      expect(labels, <String>[r'\subsection', r'\subsubsection']);
    });

    test('case does not matter', () {
      expect(auto.suggest(at(r'\SEC|')).map((c) => c.label), contains(r'\section'));
    });

    test('a prefix that matches nothing yields nothing', () {
      expect(auto.suggest(at(r'\zzzz|')), isEmpty);
    });
  });

  group('project-specific completions', () {
    const withProject = LatexAutocomplete(
      labels: <String>['fig:overview', 'tab:hasil', 'eq:loss'],
      citationKeys: <String>['karisma2024', 'wijaya2023'],
    );

    test('labels found in the project are offered to \\ref', () {
      final text = r'\ref{tab';
      final r = withProject.requestAt(text, text.length);
      expect(withProject.suggest(r).map((c) => c.label), <String>['tab:hasil']);
    });

    test('bib keys are offered to \\cite', () {
      final text = r'\cite{kar';
      final r = withProject.requestAt(text, text.length);
      expect(withProject.suggest(r).map((c) => c.label), <String>['karisma2024']);
    });

    test('nothing is offered when the project has no labels yet', () {
      final text = r'\ref{';
      final r = auto.requestAt(text, text.length);
      expect(auto.suggest(r), isEmpty);
    });
  });

  group('scanning a project', () {
    test('labels are collected and de-duplicated', () {
      final labels = scanLabels(r'''
\section{Satu}\label{sec:satu}
\begin{figure}\label{fig:a}\end{figure}
\label{sec:satu}
''');
      expect(labels..sort(), <String>['fig:a', 'sec:satu']);
    });

    test('BibTeX keys are read from every entry type', () {
      final keys = scanCitationKeys('''
@article{karisma2024, title={A}}
@book { wijaya2023 , title={B}}
@inproceedings{lain2022,title={C}}
''');
      expect(keys..sort(), <String>['karisma2024', 'lain2022', 'wijaya2023']);
    });
  });

  group('environment expansion', () {
    test('puts the caret inside the body, not after \\end', () {
      final r = expandEnvironment('itemize');
      expect(r.text, '\\begin{itemize}\n  \\item \n\\end{itemize}');
      expect(r.caret, r.text.indexOf(r'\end') - 1);
      // Everything before the caret is the opening and the first item.
      expect(r.text.substring(0, r.caret), contains(r'\item'));
    });

    test('an unknown environment still gets a body to type into', () {
      final r = expandEnvironment('theorem');
      expect(r.text, '\\begin{theorem}\n  \n\\end{theorem}');
      expect(r.caret, greaterThan(r.text.indexOf('theorem')));
    });

    test('indentation is carried onto every line', () {
      final r = expandEnvironment('quote', indent: '    ');
      for (final line in r.text.split('\n')) {
        expect(line.startsWith('    '), isTrue, reason: 'baris tanpa indentasi: "$line"');
      }
    });
  });

  group('insertion', () {
    test('commands taking an argument park the caret inside the braces', () {
      final section = LatexLanguage.commands.firstWhere((c) => c.label == r'\section');
      expect(section.insert, r'\section{}');
      expect(section.cursorOffset, section.insert.length - 1);
    });

    test(r'\frac parks the caret in the first pair, not after the last', () {
      final frac = LatexLanguage.commands.firstWhere((c) => c.label == r'\frac');
      expect(frac.insert, r'\frac{}{}');
      expect(frac.cursorOffset, lessThan(frac.insert.length - 1));
      expect(frac.insert.substring(frac.cursorOffset!), r'}{}');
    });

    test('every command that inserts braces says where the caret goes', () {
      for (final c in LatexLanguage.commands) {
        if (!c.insert.contains('{}')) continue;
        expect(c.cursorOffset, isNotNull, reason: '${c.label} tidak menyebut posisi kursor');
        expect(c.cursorOffset, lessThanOrEqualTo(c.insert.length));
      }
    });
  });
}
