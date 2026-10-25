"""Index decrypted GG device specs (golisp) into one JSON file.

Usage: python -I scripts/edevice_index.py <plain-dir> <out.json>

<plain-dir> holds the `.lisp` files `decrypt_edevice.py` writes. Nothing from the corpus is embedded here;
the output stays outside the repo (the corpus is SteelSeries property). Per device: PID, include chain,
structs (ordered fields, constants evaluated where the tiny evaluator below can) and apis (transport and
chunk size per chunk op). Values the evaluator cannot reduce are kept as source text.
"""

import json
import re
import sys
from pathlib import Path

TOKEN = re.compile(
    r'\s+|;[^\n]*|"(?:\\.|[^"\\])*"|,@|[()\[\]{}\'`,]|[^\s()\[\]{}\'`,;"]+'
)
TRANSPORTS = {"HIDFEATURE", "HIDIO", "HIDCONFIG", "SSFWFIZZ", "HID", "SSE"}
CHUNK_OPS = {"chunk", "write-chunk", "read-chunk"}


class Sym(str):
    pass


def parse(text):
    tokens = [t for t in TOKEN.findall(text) if t.strip() and not t.startswith(";")]
    pos = 0

    def form():
        nonlocal pos
        tok = tokens[pos]
        pos += 1
        if tok in ("(", "[", "{"):
            close = {"(": ")", "[": "]", "{": "}"}[tok]
            items = [] if tok == "(" else [Sym({"[": "#bytes", "{": "#frame"}[tok])]
            while tokens[pos] != close:
                items.append(form())
            pos += 1
            return items
        if tok in ("'", "`", ",", ",@"):
            return [
                Sym(
                    {"'": "quote", "`": "quasiquote", ",": "unquote", ",@": "unquote"}[
                        tok
                    ]
                ),
                form(),
            ]
        if tok.startswith('"'):
            return tok[1:-1]
        try:
            return int(tok, 0)
        except ValueError:
            return Sym(tok)

    forms = []
    while pos < len(tokens):
        forms.append(form())
    return forms


def text_of(x):
    if isinstance(x, list):
        return "(" + " ".join(text_of(i) for i in x) + ")"
    return str(x) if not isinstance(x, str) or isinstance(x, Sym) else json.dumps(x)


class Unknown(Exception):
    pass


def evaluate(x, env, depth=0):
    if depth > 60:
        raise Unknown
    ev = lambda y: evaluate(y, env, depth + 1)
    if isinstance(x, int) or (isinstance(x, str) and not isinstance(x, Sym)):
        return x
    if isinstance(x, Sym):
        if x in ("#t", "#f"):
            return x == "#t"
        if x in env.get("__vals", {}):
            return ev(env["__vals"][x])
        raise Unknown
    if not x:
        raise Unknown
    head, args = x[0], x[1:]
    if head == "#bytes":
        return [ev(a) for a in args]
    if head == "quote":
        return args[0]
    if head == "lambda":
        return ("lambda", args[0], args[1:], env)
    ops = {
        "+": lambda *a: sum(a),
        "*": lambda a, b: a * b,
        "-": lambda a, b=None: -a if b is None else a - b,
        "/": lambda a, b: a // b,
        "%": lambda a, b: a % b,
        "pred": lambda a: a - 1,
        "succ": lambda a: a + 1,
        "==": lambda a, b: a == b,
        "!=": lambda a, b: a != b,
        "<": lambda a, b: a < b,
        "<=": lambda a, b: a <= b,
        "length": len,
        "bytearray->list": list,
        "list": lambda *a: list(a),
        "take": lambda n, l: l[:n],
        "member": lambda a, l: a in l,
        "not": lambda a: not a,
    }
    if head == "and":
        return all(ev(a) for a in args)
    if head == "if":
        return ev(args[1]) if ev(args[0]) else (ev(args[2]) if len(args) > 2 else None)
    if head == "sort":  # `(sort list <)`; every comparator in the corpus is `<`
        return sorted(ev(args[0]))
    if head in ("filter", "map"):
        fn, seq = ev(args[0]), ev(args[1])
        call = lambda v: apply(fn, [v], depth)
        return (
            [v for v in seq if call(v)] if head == "filter" else [call(v) for v in seq]
        )
    if head in ops:
        return ops[head](*[ev(a) for a in args])
    if isinstance(head, Sym) and head in env.get("__funcs", {}) and not args:
        return ev(env["__funcs"][head])
    raise Unknown


def apply(fn, values, depth):
    if callable(fn):
        return fn(*values)
    if isinstance(fn, tuple) and fn[0] == "lambda":
        _, params, body, env = fn
        local = dict(env)
        local["__vals"] = {**env.get("__vals", {}), **dict(zip(params, values))}
        result = None
        for b in body:
            result = evaluate(b, local, depth + 1)
        return result
    raise Unknown


def try_eval(x, env):
    try:
        return evaluate(x, env)
    except (Unknown, TypeError, ValueError, IndexError, KeyError, RecursionError):
        return text_of(x)


class Scope:
    def __init__(self, files):
        self.files = files
        self.funcs, self.vals, self.structs, self.apis, self.includes = (
            {},
            {},
            {},
            {},
            [],
        )

    @property
    def env(self):
        return {"__funcs": self.funcs, "__vals": self.vals}

    def run(self, forms, seen=()):
        for f in forms:
            if not isinstance(f, list) or not f:
                continue
            head = f[0]
            if head == "define" and len(f) >= 3:
                if isinstance(f[1], list) and len(f[1]) == 1:
                    self.funcs[f[1][0]] = f[-1]
                elif isinstance(f[1], Sym):
                    self.vals[f[1]] = f[2]
            elif head == "include" and isinstance(f[1], str) and f[1] not in seen:
                self.includes.append(f[1])
                self.run(self.files.get(f[1], []), seen + (f[1],))
            elif head == "includable":
                self.run(f[1:], seen)
            elif head in ("struct", "template") and isinstance(f[1], Sym):
                self.structs[f[1]] = f
            elif head == "api" and isinstance(f[1], Sym):
                self.apis[f[1]] = f
            elif head == "derived-api" and len(f) == 3:
                self.apis[f[1]] = self.apis.get(f[2], f)
            elif head in ("if", "when", "begin"):
                self.run([g for g in f[1:] if isinstance(g, list)], seen)

    def field(self, f):
        out = {"name": f[1], "type": text_of(f[2]) if len(f) > 2 else None}
        for mod in f[3:]:
            if isinstance(mod, list) and mod and isinstance(mod[0], Sym):
                key = str(mod[0])
                vals = [try_eval(m, self.env) for m in mod[1:]]
                out[key] = vals[0] if len(vals) == 1 else vals
            elif isinstance(mod, Sym):
                out.setdefault("flags", []).append(str(mod))
        return out

    def struct(self, form):
        fields, sections = [], {}
        for part in form[2:]:
            if not isinstance(part, list) or not part:
                continue
            if part[0] == "field":
                fields.append(self.field(part))
            elif part[0] == "fields-from-struct":
                fields.append({"fields_from": part[1]})
            elif part[0] in ("outgoing", "incoming"):
                sections[part[0]] = [
                    self.field(p)
                    for p in part[1:]
                    if isinstance(p, list) and p[0] == "field"
                ]
        return {"fields": fields, **sections}

    def chunks(self, form, out):
        if isinstance(form, list):
            if (
                len(form) >= 3
                and isinstance(form[0], Sym)
                and form[0] in CHUNK_OPS
                and isinstance(form[1], Sym)
                and form[1] in TRANSPORTS
            ):
                out.append(
                    {
                        "op": form[0],
                        "transport": form[1],
                        "size": try_eval(form[2], self.env),
                    }
                )
            for part in form:
                self.chunks(part, out)
        return out


def steelseries_literals(form, context):
    """Every `0x1038PPPP` integer in a form, with the name of the innermost define around it."""
    if isinstance(form, int) and form >> 16 == 0x1038:
        yield context, form
    elif isinstance(form, list):
        if len(form) >= 3 and form[0] == "define":
            target = form[1][0] if isinstance(form[1], list) and form[1] else form[1]
            context = str(target).removesuffix("-id")
        for part in form:
            yield from steelseries_literals(part, context)


def device_blocks(forms):
    return [
        f
        for f in forms
        if isinstance(f, list) and f and f[0] == "device" and len(f) > 1
    ]


def main(plain, out):
    files = {
        p.stem: parse(p.read_text(encoding="utf-8", errors="replace"))
        for p in sorted(plain.glob("*.lisp"))
    }
    # `(define <name> 0x1038PPPP)` anywhere in the corpus (`-id`, `_id`, `-pid`, bare names); device blocks may
    # name ids from other files.
    ids = {
        f[1]: (stem, f[2])
        for stem, forms in files.items()
        for f in forms
        if isinstance(f, list)
        and len(f) == 3
        and f[0] == "define"
        and isinstance(f[1], Sym)
        and isinstance(f[2], int)
        and f[2] >> 16 == 0x1038
    }
    by_pid = {}
    for stem, forms in files.items():
        for name, value in steelseries_literals(forms, stem):
            by_pid.setdefault(
                value & 0xFFFF, {"pid": value & 0xFFFF, "name": name, "file": stem}
            )
    pids = sorted(by_pid.values(), key=lambda p: p["pid"])
    devices = []
    for stem, forms in files.items():
        for block in device_blocks(forms):
            scope = Scope(files)
            scope.run(
                [g for g in forms if isinstance(g, list) and g and g[0] == "define"]
            )
            scope.run(block[2:])
            # `(device a-id ...)` or `(device '(a-id b-id) ...)`
            named = (
                block[1][1]
                if isinstance(block[1], list) and block[1][:1] == ["quote"]
                else [block[1]]
            )
            values = [ids[s][1] if s in ids else s for s in named]
            devices.append(
                {
                    "file": stem,
                    "id_symbols": [str(s) for s in named],
                    "pids": [v & 0xFFFF for v in values if isinstance(v, int)],
                    "includes": scope.includes,
                    "structs": {k: scope.struct(v) for k, v in scope.structs.items()},
                    "apis": {k: scope.chunks(v, []) for k, v in scope.apis.items()},
                }
            )
    out.write_text(
        json.dumps({"pids": pids, "devices": devices}, indent=1, default=str),
        encoding="utf-8",
    )
    unique = {p["pid"] for p in pids} | {p for d in devices for p in d["pids"]}
    print(
        f"{len(files)} files, {len(pids)} PID literals, {len(devices)} device blocks, {len(unique)} PIDs -> {out}"
    )


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(Path(sys.argv[1]), Path(sys.argv[2]))
