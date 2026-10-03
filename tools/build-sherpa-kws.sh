#!/usr/bin/env bash
# Rebuild the locally hosted English sherpa-onnx KWS assets. Requires an active
# Emscripten 4.0.23 environment and Python sentencepiece (0.2.1 used here).
set -euo pipefail
command -v emcc >/dev/null || { echo 'Source emsdk_env.sh (Emscripten 4.0.23) first.' >&2; exit 1; }
python3 -c 'import sentencepiece' || { echo 'Install sentencepiece for this Python first.' >&2; exit 1; }
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
out="$root/mobile-pwa/vendor/sherpa-onnx"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

git clone -q --depth 1 --branch v1.13.8 https://github.com/k2-fsa/sherpa-onnx.git "$tmp/sherpa"
url='https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01.tar.bz2'
curl -fL --retry 3 "$url" -o "$tmp/model.tar.bz2"
# The pinned publisher archive; fail if its contents change.
expected=f170013b4716e41b62b9bfd809687c207cef798ef9bc6534d524e17af9b6561a
actual=$(shasum -a 256 "$tmp/model.tar.bz2" | cut -d' ' -f1)
[[ "$actual" == "$expected" ]] || { echo "Model archive digest changed: $actual" >&2; exit 1; }
tar xjf "$tmp/model.tar.bz2" -C "$tmp"
model="$tmp/sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01"
assets="$tmp/sherpa/wasm/kws/assets"
for piece in encoder decoder joiner; do
  cp "$model/$piece-epoch-12-avg-2-chunk-16-left-64.int8.onnx" "$assets/$piece.onnx"
done
cp "$model/tokens.txt" "$model/bpe.model" "$assets/"

python3 - "$assets" "$out/keywords_raw.txt" "$tmp/keywords.txt" <<'PY'
import pathlib, sentencepiece, sys
assets, raw, dest = map(pathlib.Path, sys.argv[1:])
sp = sentencepiece.SentencePieceProcessor(model_file=str(assets / 'bpe.model'))
tokens = {line.split()[0] for line in (assets / 'tokens.txt').read_text().splitlines() if line.strip()}
output = []
for line in raw.read_text().splitlines():
    word, label = line.split()
    if label != '@' + word.lower() or word.lower() not in ('next', 'back', 'sleep'):
        raise SystemExit('Only NEXT/BACK/SLEEP with exact command labels are supported')
    pieces = sp.encode(word, out_type=str)
    if not pieces or not set(pieces) <= tokens:
        raise SystemExit(f'Unknown BPE pieces: {word}: {pieces}')
    output.append(' '.join([*pieces, label]))
if len(output) != 3:
    raise SystemExit('Expected exactly three command keywords')
dest.write_text('\n'.join(output) + '\n')
PY
# The upstream demo checks a Chinese model filename; use the pinned English
# assets and lower the initial WASM heap (growth remains enabled).
python3 - "$tmp/sherpa/wasm/kws/CMakeLists.txt" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
for before, after in [('assets/decoder-epoch-12-avg-2-chunk-16-left-64.onnx', 'assets/decoder.onnx'),
                      ('INITIAL_MEMORY=512MB', 'INITIAL_MEMORY=256MB')]:
    if before not in s:
        raise SystemExit('Unexpected upstream CMake configuration: ' + before)
    s = s.replace(before, after)
p.write_text(s)
PY
(cd "$tmp/sherpa" && bash build-wasm-simd-kws.sh)
built="$tmp/sherpa/build-wasm-simd-kws/install/bin/wasm"
for suffix in js wasm data; do
  test -s "$built/sherpa-onnx-wasm-kws-main.$suffix"
done
cmp "$built/sherpa-onnx-kws.js" "$out/sherpa-onnx-kws.js"
# Copy only after successful compilation, preserving the old deployable set on failure.
cp "$built/sherpa-onnx-wasm-kws-main."{js,wasm,data} "$out/"
cp "$tmp/keywords.txt" "$out/keywords.txt"
shasum -a 256 "$out"/sherpa-onnx-wasm-kws-main.{js,wasm,data} "$out/keywords.txt"
