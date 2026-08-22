#!/usr/bin/env python3
"""Validate a review-findings array against .claude/references/finding-schema.json.

Turns the FINDING contract from prose into a gate with an exit code.

    echo '[]' | python3 scripts/validate-findings.py            # smoke test
    python3 scripts/validate-findings.py report.json
    python3 scripts/validate-findings.py --id FILE LINE LOCUS        # compute a finding id

Exit: 0 valid, 1 invalid, 2 internal error.
"""
import json, sys, os, hashlib, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMA = os.path.join(ROOT, ".claude", "references", "finding-schema.json")

def finding_id(file, line, locus, lens=None):
    # lens is deliberately NOT in the identity: the same defect found by two
    # lenses must dedup to one finding. (Codex review, PR #140.)
    return hashlib.sha1(f"{file}:{line}:{locus}".encode()).hexdigest()

def validate(data, schema):
    errs = []
    if not isinstance(data, list):
        return ["top level must be an ARRAY of findings, not an object "
                "(reports are arrays, not {\"findings\": [...]} wrappers)"]
    req = schema["required"]; props = schema["properties"]; seen = {}
    for i, f in enumerate(data):
        w = f"findings[{i}]"
        if not isinstance(f, dict):
            errs.append(f"{w}: not an object"); continue
        for k in req:
            if k not in f: errs.append(f"{w}: missing required field '{k}'")
        for k in f:
            if k not in props: errs.append(f"{w}: unknown field '{k}' (additionalProperties: false)")
        for k, v in f.items():
            spec = props.get(k)
            if not spec: continue
            if "enum" in spec and v not in spec["enum"]:
                errs.append(f"{w}.{k}: {v!r} not in {spec['enum']}")
            t = spec.get("type")
            # NB: isinstance(True, int) is True in Python; JSON Schema treats
            # boolean and integer as distinct types. (Codex, PR #140 round 2.)
            if t == "integer" and (isinstance(v, bool) or not isinstance(v, int)): errs.append(f"{w}.{k}: must be integer (boolean is not)")
            if t == "string" and not isinstance(v, str): errs.append(f"{w}.{k}: must be string")
            if t == "boolean" and not isinstance(v, bool): errs.append(f"{w}.{k}: must be boolean")
            if "pattern" in spec and isinstance(v, str) and not re.fullmatch(spec["pattern"], v):
                errs.append(f"{w}.{k}: {v!r} does not match {spec['pattern']}")
            if "minimum" in spec and isinstance(v, int) and not isinstance(v, bool) and v < spec["minimum"]:
                errs.append(f"{w}.{k}: below minimum {spec['minimum']}")
        # id must be reproducible from its own coordinates. Guard on type:
        # a non-string id already failed the type check above, and slicing or
        # hashing it here would crash the validator instead of reporting
        # (Codex, PR #140 round 3).
        if isinstance(f.get("id"), str):
            if all(k in f for k in ("file", "line", "locus")):
                want = finding_id(f["file"], f["line"], f["locus"])
                if f["id"] != want:
                    errs.append(f"{w}.id: {f['id'][:12]}… != sha1(file:line:locus) {want[:12]}…")
            if f["id"] in seen: errs.append(f"{w}.id: duplicate of findings[{seen[f['id']]}]")
            seen[f["id"]] = i
    return errs

def main():
    a = sys.argv[1:]
    if a and a[0] == "--id":
        if len(a) not in (4, 5):
            print("usage: --id FILE LINE LOCUS", file=sys.stderr); return 2
        print(finding_id(a[1], a[2], a[3])); return 0
    try:
        schema = json.load(open(SCHEMA))
    except Exception as e:
        print(f"validate-findings: cannot read schema: {e}", file=sys.stderr); return 2
    try:
        raw = open(a[0]).read() if a else sys.stdin.read()
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"validate-findings: invalid JSON: {e}", file=sys.stderr); return 1
    except Exception as e:
        print(f"validate-findings: cannot read input: {e}", file=sys.stderr); return 2
    errs = validate(data, schema)
    if errs:
        print(f"validate-findings: {len(errs)} error(s)")
        for e in errs: print(f"  {e}")
        return 1
    print(f"validate-findings: OK ({len(data)} finding(s))")
    return 0

if __name__ == "__main__":
    sys.exit(main())
