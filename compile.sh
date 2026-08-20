#!/bin/sh
# Whether the submission is still valid Python that imports.
#
# Nothing beyond the standard library is installed in this image, so validity
# is what python itself decides: every .py file in the checkout compiles, and
# consumer.py imports and still defines a Consumer. Importing is the half that
# matters most here — a syntax error is rare in a patch, and a name that does
# not exist or a module this image does not have is not.
#
# Compiled in memory rather than with compileall: /work belongs to root and is
# the thing being examined, and a __pycache__ written beside the submission
# would be a change to it. The image sets PYTHONDONTWRITEBYTECODE for the same
# reason, and the import below relies on it.
set -eu
mkdir -p "${TMPDIR:-/build/tmp}"
[ -f /work/consumer.py ] || { echo "the submission has no consumer.py at its root"; exit 2; }

W=/build/viva-compile
rm -rf "$W"; mkdir -p "$W"

cat > "$W/check.py" <<'PY'
import pathlib
import sys

broken = 0
for path in sorted(pathlib.Path("/work").rglob("*.py")):
    if ".git" in path.parts:
        continue
    try:
        compile(path.read_text(encoding="utf-8", errors="replace"), str(path), "exec")
    except SyntaxError as e:
        print(f"{e.filename}:{e.lineno}: {e.msg}")
        broken += 1
if broken:
    raise SystemExit(1)

sys.path.insert(0, "/work")
try:
    import consumer
except Exception as e:  # noqa: BLE001
    print(f"consumer.py does not import: {type(e).__name__}: {e}")
    raise SystemExit(1)

if not isinstance(getattr(consumer, "Consumer", None), type):
    print("consumer.py imports, but defines no Consumer class")
    raise SystemExit(1)

print("every .py file compiles; consumer.py imports and defines Consumer")
PY

python3 "$W/check.py" 2>&1
