# WritePaperTeX

A LaTeX editor that runs on an Android tablet, and on Linux and Windows.
Companion to [ReadPaper](https://github.com/situkangsayur/readpaper): one
reads papers, this one writes them.

> **Early.** Today the only part that works end to end is compilation on
> Linux. The editor, the project browser and the tablet layout are being
> built; Android cannot compile anything yet, for the reason below.

## The awkward part, stated up front

Android has no TeX Live. There is no `pdflatex` to call, and a full TeX Live
is several gigabytes — it cannot be shipped inside an APK.

So there are two engines behind one interface:

| Engine | Platform | State |
|---|---|---|
| `latexmk` + XeLaTeX | Linux, Windows, macOS | **Works.** Uses the TeX Live already installed |
| [Tectonic](https://tectonic-typesetting.github.io/) | Android | **Not yet.** A complete TeX engine rewritten in Rust, self-contained, fetching packages on demand |

Tectonic is the plan for Android for three reasons that happen to coincide:
it is the only complete TeX engine realistic to bundle into a mobile app, it
is written in **Rust**, and there is precedent for building it for Android
with `cargo-ndk`.

What is *not* proven yet is cross-compiling it to `aarch64-linux-android` and
what that does to the APK size. Until it is, the Android build cannot
compile. See [docs/keputusan-teknis.md](docs/keputusan-teknis.md).

## Planned

- LaTeX editor with syntax highlighting and autocomplete, including `\ref`
  and `\cite` keys read from the project itself
- Create a project from a template, or open an existing folder
- Compile to PDF, with errors shown next to the line that caused them
- PDF preview beside the editor, keeping its scroll position across rebuilds
- Load a project from GitHub, commit and push
- **Table tooling** — a visual editor, CSV import, `booktabs` by default.
  Tables are the worst part of LaTeX to write by hand, and far worse on a
  tablet
- An extra key row for `\ { } $ &`, which Android keyboards bury

## Building

```bash
flutter pub get
flutter analyze
flutter test          # compilation tests skip when TeX Live is absent
flutter run -d linux
```

Linux needs a TeX Live:

```bash
sudo apt install texlive-xetex latexmk
```

## Licence

Free software under the **GNU Affero General Public License, version 3 or
later** ([LICENSE](LICENSE)). Use it, change it, sell it — but whoever
receives a copy, including over a network, has the right to the source under
the same terms.

Contributions are taken under the same licence, signed off with
`git commit -s` (Developer Certificate of Origin). No CLA.
