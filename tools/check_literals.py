#!/usr/bin/env python3
"""Umlauts in Pascal literals: the two rules that keep them intact.

Why this exists
---------------
Free Pascal decides the encoding of a string literal at COMPILE time, and the
decision depends both on the unit's source codepage and on the shape of the
expression the literal stands in. Two forms go wrong, silently:

  1. A unit whose source is UTF-8 but which does not say so. Its literals are
     read as the default ansi codepage and encoded a second time on the way
     into a RawUtf8, so 'Ü' arrives as 'Ã' plus an invisible control
     character. Ugly, and valid UTF-8, so nothing complains.

  2. A literal concatenated onto a variable with '+', in a unit that DOES
     declare {$codepage UTF8}. The compiler folds such an expression into its
     default ansi codepage, and 'ä' becomes the single byte E4 - which is not
     UTF-8 at all. A Cocoa control ends the process over one of those
     (stringWithUTF8String answers nil, insertText: raises, SIGABRT); GTK and
     Qt drop or replace the text instead, so on Linux and Windows the same
     defect is merely ugly. That is the reason to check mechanically rather
     than to wait for someone to notice.

Both are properties of the SOURCE, so both are checked there - no build
needed, and the answer is the same on every platform:

  rule 1: a file with a non-ASCII literal declares {$codepage UTF8}
  rule 2: a non-ASCII literal is never an operand of '+' next to anything
          that is not itself a literal - write FormatUtf8('... %', [x])

The optional binary pass confirms it on what was actually built: the UTF-8
bytes of every literal should be findable in the program. A literal the
compiler stored as UTF-16 is one it means to convert at run time, which is
form 2 above; the doubly encoded bytes of form 1 show up directly when the
compiler folded them.

Usage
-----
    python3 tools/check_literals.py               # src/ and, if built, bin/
    python3 tools/check_literals.py --no-binaries # source rules only
    python3 tools/check_literals.py -v            # list every literal checked

Exit code 1 when something was found, so a build script can stop on it.
"""

import argparse
import os
import re
import sys

SOURCE_SUFFIXES = ('.pas', '.lpr', '.inc')

# folders holding copies rather than the sources that are built
SKIP_DIRS = {'backup', 'lib', 'libeditor', 'libclient', '.git'}

DIRECTIVE = re.compile(r'\{\$codepage\s+utf8\s*\}', re.IGNORECASE)


def strip_pascal_comments(text):
    """The source with comments blanked, literals and line numbers intact.

    Pascal has three comment forms and one string form, and a comment opener
    inside a string is not a comment - the case a regular expression gets
    wrong - so this walks the text once.
    """
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "'":                                   # string literal
            out.append(c)
            i += 1
            while i < n:
                out.append(text[i])
                if text[i] == "'":                     # '' inside is an escape
                    i += 1
                    break
                if text[i] == '\n':                    # unterminated: give up
                    break
                i += 1
            continue
        if c == '{':                                   # { comment }
            while i < n and text[i] != '}':
                out.append('\n' if text[i] == '\n' else ' ')
                i += 1
            out.append(' ')
            i += 1
            continue
        if c == '(' and text[i + 1:i + 2] == '*':      # (* comment *)
            while i < n and text[i:i + 2] != '*)':
                out.append('\n' if text[i] == '\n' else ' ')
                i += 1
            out.append('  ')
            i += 2
            continue
        if c == '/' and text[i + 1:i + 2] == '/':      # // to end of line
            while i < n and text[i] != '\n':
                out.append(' ')
                i += 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)


# a string literal, an identifier (dotted), a number, or a single character
TOKEN = re.compile(r"'[^'\n]*'|[A-Za-z_][A-Za-z0-9_.]*|\d+|\S")


def tokenize(text):
    """(line, text) for every token, comments already gone."""
    result = []
    line = 1
    position = 0
    for match in TOKEN.finditer(text):
        line += text.count('\n', position, match.start())
        position = match.start()
        result.append((line, match.group(0)))
    return result


def is_literal(token):
    """A quoted literal, or a character constant like #13.

    A chain of pure constants is safe: the compiler folds those among
    themselves and keeps the UTF-8 - measured, and the reason a message split
    over #13#10 is not a finding.
    """
    return token.startswith("'") or token == '#' or token.isdigit()


def has_umlaut(token):
    return any(ord(ch) > 127 for ch in token)


def concat_partners(tokens, index):
    """What this literal is joined to with '+', looking both ways.

    A chain of literals is fine - the compiler folds those among themselves.
    Anything else in the chain (an identifier, a call, a closing bracket) is
    what makes the compiler pick its default ansi codepage for the result.
    """
    partners = []
    # to the left: ... x + 'lit'
    i = index - 1
    while i >= 1 and tokens[i][1] == '+':
        partners.append(tokens[i - 1])
        i -= 2
    # to the right: 'lit' + x ...
    i = index + 1
    while i + 1 < len(tokens) and tokens[i][1] == '+':
        partners.append(tokens[i + 1])
        i += 2
    return partners


def check_source(path, min_length, verbose):
    """The two source rules, for one file. Returns the number of findings."""
    with open(path, encoding='utf-8') as f:
        raw = f.read()
    text = strip_pascal_comments(raw)
    tokens = tokenize(text)
    interesting = [(i, line, token) for i, (line, token) in enumerate(tokens)
                   if is_literal(token) and has_umlaut(token)
                   and len(token) - 2 >= min_length]
    if not interesting:
        return 0, []
    findings = []
    # rule 1 - the file has to say that its source is UTF-8
    if not DIRECTIVE.search(raw):
        findings.append((interesting[0][1],
                         'the file has literals with umlauts but no '
                         '{$codepage UTF8} - they will be encoded twice'))
    # rule 2 - no non-ASCII literal glued to a variable
    for index, line, token in interesting:
        for _, partner in concat_partners(tokens, index):
            if not is_literal(partner):
                findings.append((line,
                    "'%s' is concatenated with '+' onto %s - the compiler "
                    "folds that into its default ansi codepage; use "
                    "FormatUtf8('... %%', [%s])"
                    % (token[1:-1][:40], partner, partner)))
                break
        if verbose and not findings:
            print('ok      %s:%d: %s' % (path, line, token[1:-1][:60]))
    return len(findings), findings


def read_binaries(folder):
    result = {}
    if not os.path.isdir(folder):
        return result
    for name in sorted(os.listdir(folder)):
        path = os.path.join(folder, name)
        if os.path.isfile(path) and os.access(path, os.X_OK):
            with open(path, 'rb') as f:
                result[name] = f.read()
    return result


def check_binaries(path, binaries, min_length, verbose):
    """What the built programs actually carry, for one file's literals."""
    findings = []
    for line, literal in source_literals(path, min_length):
        good = literal.encode('utf-8')
        double = good.decode('latin-1').encode('utf-8')
        wide = literal.encode('utf-16-le')
        for name, blob in binaries.items():
            if double in blob:
                findings.append((line, "'%s' is doubly encoded in %s"
                                 % (literal[:40], name)))
            elif good not in blob and wide in blob:
                findings.append((line,
                    "'%s' is stored as UTF-16 in %s: the compiler converts it "
                    "at run time, which is what a '+' concatenation does"
                    % (literal[:40], name)))
            elif verbose and good in blob:
                print('ok      %s:%d: %s (%s)'
                      % (path, line, literal[:50], name))
    return findings


def source_literals(path, min_length):
    with open(path, encoding='utf-8') as f:
        text = strip_pascal_comments(f.read())
    for number, line in enumerate(text.splitlines(), 1):
        for literal in re.findall(r"'([^'\n]*)'", line):
            if has_umlaut(literal) and len(literal) >= min_length:
                yield number, literal


def sources_of(folders):
    for folder in folders:
        for root, dirs, files in os.walk(folder):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            for name in sorted(files):
                if name.endswith(SOURCE_SUFFIXES):
                    yield os.path.join(root, name)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--src', action='append', default=None,
                    help='source folder to scan (default: src)')
    ap.add_argument('--bin', default='bin',
                    help='folder holding the built programs (default: bin)')
    ap.add_argument('--no-binaries', action='store_true',
                    help='source rules only, no build needed')
    ap.add_argument('--min-length', type=int, default=2,
                    help='ignore shorter literals (default: 2)')
    ap.add_argument('-v', '--verbose', action='store_true',
                    help='also list the literals that are intact')
    args = ap.parse_args()
    sources = args.src or ['src']

    binaries = {} if args.no_binaries else read_binaries(args.bin)
    if binaries:
        print('%d binaries: %s' % (len(binaries), ', '.join(binaries)))
    elif not args.no_binaries:
        print('nothing built in %s - source rules only' % args.bin)

    total = 0
    files = 0
    for path in sources_of(sources):
        count, findings = check_source(path, args.min_length, args.verbose)
        if binaries:
            findings = findings + check_binaries(
                path, binaries, args.min_length, args.verbose)
        if findings:
            files += 1
        for line, what in sorted(findings):
            total += 1
            print('FINDING %s:%d: %s' % (path, line, what))

    if total:
        print('%d finding(s) in %d file(s).' % (total, files))
    else:
        print('No findings: every literal with an umlaut is declared UTF-8 '
              'and none is glued to a variable with "+".')
    return 1 if total else 0


if __name__ == '__main__':
    sys.exit(main())
