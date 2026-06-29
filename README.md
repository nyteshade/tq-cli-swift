# tq — TOON Query & Mutation Tool

[![Swift 6.0+](https://img.shields.io/badge/swift-6.0+-orange.svg)](https://swift.org)
[![TOON spec v3.2+](https://img.shields.io/badge/spec-v3.2+-fef3c0?labelColor=1b1b1f)](https://github.com/toon-format/spec)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)

A command-line processor for [TOON](https://github.com/toon-format/spec) (Token-Oriented Object Notation) and JSON, inspired by [jq](https://jqlang.github.io/jq/) and [yq](https://github.com/mikefarah/yq).

`tq` reads TOON or JSON from stdin or files and can **query** (jq‑like path expressions), **mutate** (set, add, delete, merge), and **convert** between formats. Mutations can edit files in place with `-i`.

## Installation

### Homebrew

```bash
brew tap YOUR_USERNAME/tq
brew install tq
```

### From source

```bash
git clone https://github.com/YOUR_USERNAME/tq.git
cd tq
swift build -c release
cp .build/release/tq /usr/local/bin/
```

## Quick Start

```bash
# Query
echo 'users[2]{id,name}:
  1,Alice
  2,Bob' | tq .users[0].name
# → Alice

# Convert to JSON
tq -j .users data.toon

# Edit a file in place
tq -i set .name "Brielle" data.toon

# Append to an array
tq -i add .tags "new-tag" data.toon
```

---

## Usage

### Query mode

```bash
tq [options] <expression> [file...]
```

Evaluates a path expression and outputs the matching value(s).

### Mutation mode

```bash
tq set  [options] <path> <value>  [file]
tq add  [options] <path> <value>  [file]
tq del  [options] <path>          [file]
tq merge [options] <source>       [file]
```

Applies a mutation and outputs the full modified document.  Use `-i` to write the result back to the input file instead of stdout.  Mutations compose via pipes.

### Options

| Flag | Description |
|------|-------------|
| `-j`, `--json-output` | Output as JSON instead of TOON |
| `-r`, `--raw-output` | Output raw strings (no quotes or formatting) |
| `-c`, `--compact-output` | Compact output (no pretty‑printing) |
| `-i`, `--in-place` | Edit the file in place |
| `--color` | Force colorized output (even when piped) |
| `--no-color` | Disable colorized output |
| `--json <value>` | Inline JSON value (for `set` / `add` / `merge`) |
| `--toon <value>` | Inline TOON value (for `set` / `add` / `merge`) |
| `-h`, `--help` | Show help |
| `-V`, `--version` | Show version |

If no file is given, `tq` reads from **stdin**.  Input format (TOON or JSON) is auto‑detected.

### Syntax highlighting

`tq` colorizes TOON and JSON output when writing to a terminal. Keys, strings,
numbers, booleans, `null`, and structural punctuation each get a distinct color.
Coloring is **TTY‑aware**: it's automatically disabled when output is piped or
redirected, so downstream tools never see ANSI escape codes.

- Use `--color` to force colors on (e.g. when piping into a pager like `less -R`).
- Use `--no-color`, or set the [`NO_COLOR`](https://no-color.org) environment
  variable, to turn coloring off.
- Raw string output (`-r`) is always emitted verbatim, without color.

### Path expressions (jq‑like)

| Expression | Description |
|------------|-------------|
| `.` | Identity — pass through unchanged |
| `.key` | Access an object field |
| `.key1.key2` | Nested field access |
| `.[0]` | Array index (0‑based; negative counts from end) |
| `.[]` | Array iterator — expand each element |
| `.[start:end]` | Array slice (either bound may be omitted) |

Paths chain freely: `.users[0].name`, `.[-1]`, `.config.database.host`.

### Mutation commands

| Command | Description |
|---------|-------------|
| `set <path> <value>` | Set a value. Auto‑creates intermediate objects/arrays. |
| `add <path> <value>` | Append to an array. Creates the array if it doesn't exist. |
| `del <path>` | Delete a key or array element. No‑op if the path doesn't exist. |
| `merge <source>` | Deep‑merge another document. Objects merge recursively; scalars and arrays are replaced. |

**Value sources** — `set` and `add` accept values three ways:

| Style | Example |
|-------|---------|
| Literal | `"hello"`, `42`, `true`, `null`, `3.14` — auto‑detected |
| Inline JSON | `--json '{"id":1,"name":"Ada"}'` |
| Inline TOON | `--toon 'a: 1\nb: 2'` |

**Merge sources** — `merge` accepts:

| Style | Example |
|-------|---------|
| File path | `tq merge extra.toon data.toon` |
| stdin | `echo '{"x":1}' \| tq merge - data.toon` |
| Inline JSON | `tq merge --json '{"b":2}' data.toon` |
| Inline TOON | `tq merge --toon 'b: 2' data.toon` |

---

## Examples

### Querying

```bash
# Extract a field
echo 'name: Ada
age: 36' | tq .name
# → Ada

# Nested field
echo 'user:
  name: Ada
  age: 36' | tq .user.name
# → Ada

# Array index (negative = from end)
echo 'tags[3]: alpha,beta,gamma' | tq .tags[-1]
# → gamma

# Slice
echo '[5]: a,b,c,d,e' | tq '.[0:3]'
# → [3]: a,b,c

# TOON → JSON
tq -j .users data.toon

# JSON input (auto‑detected)
echo '{"users":[{"id":1}]}' | tq .users[0].id
# → 1

# Raw output (no quotes around strings)
tq -r .name data.toon
```

### Setting values

```bash
# Add a field (stdout)
echo 'name: Ada' | tq set .age 36
# → name: Ada
#   age: 36

# Edit a file in place
tq -i set .name "Brielle" data.toon

# Auto‑create nested objects
echo '{}' | tq set .user.name Alice
# → user.name: Alice

# Booleans and null (auto‑detected)
tq -i set .active true data.toon
tq -i set .email null data.toon

# Structured value via inline JSON
echo 'items:' | tq set .items[0] --json '{"id":1,"name":"Widget"}'
# → items[1]{id,name}:
#     1,Widget

# Extend an array beyond its current length (gaps become null)
echo '[]' | tq set '.[2]' third
# → [3]: null,null,third
```

### Adding to arrays

```bash
# Append a primitive
echo 'tags[2]: alpha,beta' | tq add .tags gamma
# → tags[3]: alpha,beta,gamma

# Append an object to a tabular array
tq -i add .users --json '{"id":3,"name":"Cal"}' data.toon
# users[3]{id,name}:
#   1,Ada
#   2,Bob
#   3,Cal

# First add auto‑creates the array
echo 'name: Ada' | tq add .tags coding
# → name: Ada
#   tags[1]: coding
```

### Deleting

```bash
# Remove a key
tq -i del .age data.toon

# Remove an array element
echo '[3]: a,b,c' | tq del '.[1]'
# → [2]: a,c

# Deleting a non‑existent key is a no‑op
echo 'a: 1' | tq del .b
# → a: 1
```

### Merging

```bash
# Merge with inline JSON
echo 'a: 1' | tq merge --json '{"b":2}'
# → a: 1
#   b: 2

# Deep merge (objects merge recursively)
echo 'user:
  name: Ada' | tq merge --json '{"user":{"age":36}}'
# → user:
#     age: 36
#     name: Ada

# Merge from a file
tq -i merge extra.toon data.toon

# Merge from stdin
echo '{"new":"field"}' | tq merge - data.toon
```

### Chaining

```bash
# Pipe mutations together, then query
cat data.toon | tq set .count 10 | tq del .temp | tq .users

# Build a document from scratch
echo '{}' \
  | tq set .name "Ada" \
  | tq add .tags coding \
  | tq add .tags math \
  | tq -j .
# → {"name":"Ada","tags":["coding","math"]}
```

### Working with tabular arrays

```bash
# Create a tabular array
tq -i set .users --json '[{"id":1,"name":"Ada"},{"id":2,"name":"Bob"}]' data.toon
# → users[2]{id,name}:
#     1,Ada
#     2,Bob

# Add a row
tq -i add .users --json '{"id":3,"name":"Cal"}' data.toon
# → users[3]{id,name}:
#     1,Ada
#     2,Bob
#     3,Cal

# Edit a field in a specific row
tq -i set .users[0].name "Adaline" data.toon
# Adding a non‑uniform field expands the array to list format

# Delete a row
tq -i del .users[-1] data.toon
```

---

## TOON Format Reference

TOON is a line‑oriented, indentation‑based encoding of the JSON data model, designed for LLM prompts.  It reduces token usage by **30–60%** compared to JSON.

```toon
# Object
name: Ada
age: 36
active: true
email: null

# Primitive array
tags[3]: coding,maths,logic

# Tabular array (uniform objects)
users[2]{id,name,role}:
  1,Alice,admin
  2,Bob,user

# Nested objects
address:
  street: 1 Math Lane
  city: London

# Expanded list array
orders[2]:
  - id: 101
    amount: 49.99
  - id: 102
    amount: 12.50
```

> 📘 **[Full TOON specification](https://github.com/toon-format/spec)** — grammar, encoding rules, conformance requirements, and test fixtures.

---

## Architecture

```
Sources/tq/
├── main.swift          # CLI entry point
├── TOONNode.swift      # Generic Codable tree type (JSON/TOON interchange)
├── Query.swift         # jq-like path expression parser & evaluator
├── Mutation.swift       # set / add / del / merge tree operations
└── TqCommand.swift      # Argument parsing, I/O, format auto-detection, output
```

- **Parsing**: TOON input is decoded via the official [`toon-format/toon-swift`](https://github.com/toon-format/toon-swift) library (spec v3.0+).
- **Tree representation**: `TOONNode` — a `Codable` enum that transparently bridges TOON ↔ JSON.
- **Format detection**: Input is classified as JSON or TOON by inspecting structural markers (braces, array headers, etc.).
- **Mutations are functional**: `set` / `add` / `del` / `merge` return new trees; the original is never mutated in place.

## Dependencies

- **Swift 6.0+** (macOS 13+, Linux)
- [toon-format/toon-swift](https://github.com/toon-format/toon-swift) — Official Swift TOON encoder/decoder (v0.4.0+)

## License

MIT
