#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
mkdir -p .build/module-cache
swiftc -module-cache-path "$PWD/.build/module-cache" \
    Sources/PerpetualCalendar/NoteTextEditor.swift \
    Sources/PerpetualCalendar/NoteMarkdown.swift \
    Tests/NoteEditorChecks/NoteCaretChecks.swift \
    -o "$PWD/.build/NoteEditorChecks"
.build/NoteEditorChecks
