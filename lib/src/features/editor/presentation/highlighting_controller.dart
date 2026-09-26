import 'package:flutter/material.dart';

import '../domain/latex_syntax.dart';
import 'syntax_palette.dart';

/// Pengendali teks yang mewarnai LaTeX sambil diketik.
///
/// Warna di editor bukan hiasan: yang paling sering menghabiskan waktu
/// penulis LaTeX adalah kesalahan yang terlihat begitu diwarnai — komentar
/// yang tanpa sengaja memakan satu baris perintah, `\begin` yang namanya
/// tidak sama dengan `\end`-nya, atau `$` yang tidak pernah ditutup.
class LatexHighlightingController extends TextEditingController {
  // Parameter bernama tidak boleh berawalan garis bawah, jadi bidangnya
  // diisi lewat daftar inisialisasi.
  LatexHighlightingController({SyntaxPalette palette = SyntaxPalette.calm, super.text})
    : _palette = palette; // ignore: prefer_initializing_formals

  /// Palet yang sedang dipakai; diganti lewat penyetelnya supaya layarnya
  /// ikut digambar ulang.
  SyntaxPalette _palette;

  SyntaxPalette get palette => _palette;

  set palette(SyntaxPalette value) {
    if (value.id == _palette.id) return;
    _palette = value;
    _cachedFor = null;
    notifyListeners();
  }

  /// Berkas yang lebih besar dari ini tidak diwarnai.
  ///
  /// Di atas beberapa ratus ribu huruf, memecah teks jadi ribuan potongan
  /// pada setiap ketukan tombol terasa sebagai lag. Teks polos yang cepat
  /// lebih berguna daripada teks berwarna yang tersendat.
  static const int maxLength = 200000;

  String? _cachedFor;
  List<SyntaxToken> _cachedTokens = const <SyntaxToken>[];

  List<SyntaxToken> _tokens(String source) {
    if (_cachedFor == source) return _cachedTokens;
    _cachedTokens = tokenizeLatex(source);
    _cachedFor = source;
    return _cachedTokens;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final source = value.text;
    if (_palette.id == SyntaxPalette.none.id || source.length > maxLength) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }

    final brightness = Theme.of(context).brightness;
    return TextSpan(
      style: style,
      children: <TextSpan>[
        for (final token in _tokens(source))
          TextSpan(
            text: source.substring(token.start, token.end),
            style: token.kind == SyntaxKind.text
                ? null
                : styleFor(token.kind, _palette, brightness),
          ),
      ],
    );
  }
}
