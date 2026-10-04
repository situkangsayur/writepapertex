# WritePaperTeX

A LaTeX editor that runs on an Android tablet, and on Linux and Windows.
Companion to [ReadPaper](https://github.com/situkangsayur/readpaper): one
reads papers, this one writes them.

> **Early, but usable.** Android compiles on the device itself through
> Tectonic, with no network needed for the first compile; Linux compiles with
> the installed TeX Live. Projects can be cloned from git, committed and
> pushed back from the tablet. See [docs/fitur.md](docs/fitur.md).

## The awkward part, stated up front

Android has no TeX Live. There is no `pdflatex` to call, and a full TeX Live
is several gigabytes — it cannot be shipped inside an APK.

So there are two engines behind one interface:

| Engine | Platform | State |
|---|---|---|
| `latexmk` + XeLaTeX | Linux, Windows, macOS | **Works.** Uses the TeX Live already installed |
| [Tectonic](https://tectonic-typesetting.github.io/) | Android | **Works.** A complete TeX engine in Rust, built into the APK together with a bundle of TeX packages; anything missing is fetched once on demand |

Tectonic was chosen for Android for three reasons that happen to coincide:
it is the only complete TeX engine realistic to bundle into a mobile app, it
is written in **Rust**, and there is precedent for building it for Android
with `cargo-ndk`.

It is cross-compiled to `aarch64-linux-android` by
`scripts/build-tectonic-android.sh` and called from Dart over FFI; the APK is
about 89 MB as a result. Git on Android goes through libgit2 in the same
library. See [docs/keputusan-teknis.md](docs/keputusan-teknis.md) and
[docs/panduan-teknis.md](docs/panduan-teknis.md).

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

## Dokumentasi

In Indonesian, like the app's interface.

- [docs/fitur.md](docs/fitur.md) — what it can do, and its known limits
- [docs/panduan-pengguna.md](docs/panduan-pengguna.md) — user guide: projects,
  writing, quick vs full compile, git, troubleshooting
- [docs/panduan-teknis.md](docs/panduan-teknis.md) — developer guide: building
  the Tectonic engine and package bundle, the FFI contract, measuring on a
  device, releasing
- [docs/tech-stack.md](docs/tech-stack.md) — what it is built from and how it
  is put together
- [docs/keputusan-teknis.md](docs/keputusan-teknis.md) — technical decisions
  and why
- [docs/backlog.md](docs/backlog.md) — what is done and what is not

## Licence

Free software under the **GNU Affero General Public License, version 3 or
later** ([LICENSE](LICENSE)). Use it, change it, sell it — but whoever
receives a copy, including over a network, has the right to the source under
the same terms.

Contributions are taken under the same licence, signed off with
`git commit -s` (Developer Certificate of Origin). No CLA.
