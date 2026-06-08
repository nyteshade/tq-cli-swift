# tq — TOON Query & Mutation Tool

[![Swift 6.0+](https://img.shields.io/badge/swift-6.0+-orange.svg)](https://swift.org)
[![TOON spec v3.2+](https://img.shields.io/badge/spec-v3.2+-fef3c0?labelColor=1b1b1f)](https://github.com/toon-format/spec)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)

A command-line processor for [TOON](https://github.com/toon-format/spec) (Token-Oriented Object Notation) and JSON, inspired by [jq](https://jqlang.github.io/jq/) and [yq](https://github.com/mikefarah/yq).

`tq` reads TOON or JSON from stdin or files, and can **query** (extract values with jq‑like path expressions), **mutate** (set, delete, merge fields), and **convert** between formats.

## Installation

### Homebrew

```bash
brew tap YOUR_USERNAME/tq
brew install tq
```

### Manual (from source)

```bash
git clone https://github.com/YOUR_USERNAME/tq.git
cd tq
swift build -c release
cp .build/release/tq /usr/local/bin/
```

### Binary download

Grab the latest `tq` binary from [GitHub Releases](https://github.com/YOUR_USERNAME/tq/releases) and place it in your `$PATH`.

## Quick Start

```bash
# Query a TOON document
echo 'users[2]{id,name}:
  1,Alice
  2,Bob' | tq .users[0].name
# → Alice

# Convert TOON to JSON
echo 'users[2]{id,name}:
  1,Alice
  2,Bob' | tq -j .users
# → [{"id":1,"name":"Alice"},{"id":2,"name":"Bob"}]
```

## Usage

### Query mode

```bash
tq [options] <expression> [file...]
```

Evaluates a path expression against the input document and outputs the matching value(s).

### Mutation mode

```bash
tq set  [options] <path> <value>  [file]
tq del  [options] <path>          [file]
tq merge [options] <source>       [file]
```

Applies a mutation to the input document and outputs the entire modified document. Mutations are composable via pipes.

### Options

| Flag | Description |
|------|-------------|
| `-j`, `--json-output` | Output as JSON instead of TOON |
| `-r`, `--raw-output` | Output raw strings without quotes or formatting |
| `-c`, `--compact-output` | Compact output (no pretty‑printing) |
| `--json <value>` | Supply an inline JSON value (for `set` / `merge`) |
| `--toon <value>` | Supply an inline TOON value (for `set` / `merge`) |
| `-h`, `--help` | Show help |
| `-V`, `--version` | Show version |

If no file is given, `tq` reads from **stdin**. Input format (TOON or JSON) is auto‑detected.

### Path expression syntax (jq‑like)

| Expression | Description |
|------------|-------------|
| `.` | Identity — pass through unchanged |
| `.key` | Access an object field |
| `.key1.key2` | Nested field access |
| `.[0]` | Array index (0‑based; negative counts from end) |
| `.[]` | Array iterator — expand each element |
| `.[start:end]` | Array slice (either bound may be omitted) |

Path expressions can be chained: `.users[0].name`, `.[1:3]`, `.config.database.host`.

---

## Examples

### Querying

```bash
# Extract a field
echo 'name: Ada
age: 36' | tq .name
# → Ada

# Nested field access
echo 'user:
  name: Ada
  age: 36' | tq .user.name
# → Ada

# Array index (negative = from end)
echo 'tags[3]: alpha,beta,gamma' | tq .tags[-1]
# → gamma

# Slice an array
echo '[5]: a,b,c,d,e' | tq '.[0:3]'
# → [3]: a,b,c

# Convert to JSON
tq -j .users data.toon

# Process JSON input (auto‑detected)
echo '{"users":[{"id":1}]}' | tq .users[0].id
# → 1

# Raw output (no quotes around strings)
tq -r .name data.toon
```

### Setting values

```bash
# Add a field
echo 'name: Ada' | tq set .age 36
# → name: Ada
#   age: 36

# Auto‑create nested objects
echo '{}' | tq set .user.name Alice
# → user.name: Alice

# Set booleans and null
echo 'a: 1' | tq set .active true
echo 'a: 1' | tq set .email null

# Set a structured value via inline JSON
echo 'items:' | tq set .items[0] --json '{"id":1,"name":"Widget"}'
# → items[1]{id,name}:
#     1,Widget

# Extend an array beyond its current length (gaps become null)
echo '[]' | tq set '.[2]' third
# → [3]: null,null,third

# Set via inline TOON
echo '{}' | tq set .nested --toon 'a: 1
b: 2'
```

### Deleting values

```bash
# Remove a key
echo 'name: Ada
age: 36' | tq del .age
# → name: Ada

# Remove an array element
echo '[3]: a,b,c' | tq del '.[1]'
# → [2]: a,c

# Deleting a non‑existent key is a no‑op
echo 'a: 1' | tq del .b
# → a: 1
```

### Merging documents

```bash
# Merge with inline JSON
echo 'a: 1' | tq merge --json '{"b":2}'
# → a: 1
#   b: 2

# Deep merge (objects merge recursively, scalars are replaced)
echo 'user:
  name: Ada' | tq merge --json '{"user":{"age":36}}'
# → user:
#     age: 36
#     name: Ada

# Merge from a file
tq merge extra.toon data.toon

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
  | tq set .age 36 \
  | tq set .tags --json '["coding","math"]' \
  | tq -j .
# → {"age":36,"name":"Ada","tags":["coding","math"]}
```

---

## TOON Format Reference

TOON is a line‑oriented, indentation‑based encoding of the JSON data model, designed for LLM prompts. It reduces token usage by **30–60%** compared to JSON.

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
├── Mutation.swift      # Set / delete / merge operations on the tree
└── TqCommand.swift     # Argument parsing, I/O, format auto-detection, output
```

- **Parsing**: TOON input is decoded via the official [`toon-format/toon-swift`](https://github.com/toon-format/toon-swift) library (spec v3.0+).
- **Tree representation**: `TOONNode` — a `Codable` enum that transparently bridges TOON ↔ JSON.
- **Format detection**: Input is classified as JSON or TOON by inspecting structural markers (braces, array headers, etc.).
- **Mutations are functional**: `set`/`del`/`merge` return new trees; the original is never mutated in place.

## Dependencies

- **Swift 6.0+** (macOS 13+, Linux)
- [toon-format/toon-swift](https://github.com/toon-format/toon-swift) — Official Swift TOON encoder/decoder (v0.4.0+)

## License

MIT
