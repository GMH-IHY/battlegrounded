"""Catches two kinds of comparison Studio's type checker rejects but other tools don't:

  * a value narrowed to one string by `if x == "A"` compared with another string inside that branch
    (even after a call that changed it): "Type "Returning" cannot be compared with "Hip""
  * a module's object compared with == / ~= (`active[x] == self`, `other ~= self`): "Types Fighter
    and Fighter cannot be compared ... they do not have the same metatable". Use rawequal, or
    compare a plain field such as `.character`.
"""
import os
import re

SRC = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "src")
OPEN = re.compile(r'^(\s*)(?:if|elseif) (.+?) then\s*(?:--.*)?$')
SELF_COMPARE = re.compile(r'[=~]= self\b(?![.:])|\bself [=~]= ')


def luau_files():
    for dirpath, _, files in os.walk(SRC):
        for f in files:
            if f.endswith(".luau"):
                yield os.path.join(dirpath, f)


def narrowed_compares(path):
    lines = open(path, encoding="utf-8").read().split("\n")
    found = []
    for i, line in enumerate(lines):
        m = OPEN.match(line)
        if not m or " or " in m.group(2):
            continue
        indent = m.group(1)
        narrowed = re.findall(r'([\w.:\[\]"]+) == "(\w+)"', m.group(2))
        j = i + 1
        while narrowed and j < len(lines):
            text = lines[j]
            if text.startswith(indent) and not text.startswith(indent + "\t") and re.match(r"(elseif|else|end)\b", text.strip()):
                break
            for expr, value in narrowed:
                for m2 in re.finditer(re.escape(expr) + r'\s*[=~]= "(\w+)"', text):
                    if m2.group(1) != value:
                        found.append(f"{os.path.relpath(path, SRC)}:{j + 1}: {expr} is {value!r} here, compared with {m2.group(1)!r}")
            j += 1
    return found


def test_no_compares_of_narrowed_strings():
    found = [f for path in luau_files() for f in narrowed_compares(path)]
    assert not found, "\n".join(found)


def test_no_object_compares():
    found = []
    for path in luau_files():
        for n, line in enumerate(open(path, encoding="utf-8"), 1):
            code = line.split("--", 1)[0]
            if SELF_COMPARE.search(code):
                found.append(f"{os.path.relpath(path, SRC)}:{n}: {line.strip()}")
    assert not found, "use rawequal(a, b) or compare .character:\n" + "\n".join(found)
