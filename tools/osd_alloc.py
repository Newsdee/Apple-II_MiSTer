#!/usr/bin/env python3
"""osd_alloc.py - MiSTer OSD CONF_STR status-bit allocation decoder.

Takes a MiSTer CONF_STR (a .sv file that contains one, or a raw string) and
decodes every option's status-bit allocation. This removes the guesswork when
adding/moving an OSD option: run it before and after a change and diff.

The parser models the REAL current MiSTer OSD (verified against
Main_MiSTer_clean_disk_order/user_io.cpp: user_io_status_bits() and the
option-registration loop, plus menu.cpp):

  Header normalization (done for every option string):
    * leading 'H'/'D'/'h'/'d' + flag-char pairs are stripped (2 chars each);
    * a leading 'P<page>' (exactly 2 chars) is skipped.

  After normalization, the first char selects the option kind:
    'O'/'o'  : status option. If the next char is 'X' (ARM by-arm variant)
               it is skipped. Bit spec follows. Bank: 'o' = upper (+32).
    'R'/'T'  : toggle/reset ACTION (one bit only). Bank: 'R'/'T' = lower,
               'r'/'t' = upper (+32). Spec = the single char after the letter.
    'F'/'S'  : file-load / image-mount (no status bits).
    'J'/'C'  : joystick names / cheats (no status bits).
    'V'      : version string (no bits).
    'I'      : OSD info string (no bits).
    '-'      : separator.
    'P<page>' (alone) : page title / navigation entry (no bits).

  Bit spec (user_io_status_bits):
    * '[hi:lo]' or '[n]'  : ABSOLUTE status bit range; the bank letter is
      IGNORED. Valid: hi>lo, bits <= 127 (status register is 128 bits).
      e.g. 'P0o[27:26]' -> status[27:26] (lower bank!), 'P0O[67:64]' is legal.
    * char spec : first char = start bit, second char (optional) = end bit.
      Chars: '0'-'9' -> 0-9, 'A'-'V' -> 10-31 (nothing else is valid).
      If the second char is invalid the option is a single bit.
      Lower-bank bank adds 0, upper ('o') adds 32.
      Invalid: start/end > 127, or (two-char) end <= start, or > 8 bits.
      e.g. 'OQR' -> Q=26 (LSB), R=27 (MSB) -> status[27:26].

  The OSD prints "Invalid OSD option: <line>" to the console for specs that
  fail validation; this tool reports them as 'invalid'.

Usage:
  osd_alloc.py FILE.sv                 decode the CONF_STR in a .sv file
  osd_alloc.py --str '...{...}...'     decode a raw CONF_STR string
  osd_alloc.py FILE.sv --json          machine-readable output
  osd_alloc.py --diff A.sv B.sv        diff two allocations (added/removed/moved)
  osd_alloc.py FILE.sv --free          print free status bits (0-127)
  osd_alloc.py FILE.sv --find 63:62    check which option owns a bit range
"""

import sys
import re
import json


def char_to_bit(c):
    """Map a single OSD bit-spec char to its bit value, or None if invalid.

    Valid chars: '0'-'9' -> 0-9 and 'A'-'V' -> 10-31 only (user_io.cpp
    user_io_status_bits). Anything else is an invalid spec.
    """
    if '0' <= c <= '9':
        return int(c)
    if 'A' <= c <= 'V':
        return 10 + (ord(c) - ord('A'))
    return None


def extract_confstr_strings(text):
    """Return the list of quoted option strings from a CONF_STR block (or raw)."""
    m = re.search(r'CONF_STR\s*=\s*\{([^}]*)\}', text, re.DOTALL)
    block = m.group(1) if m else text
    return re.findall(r'"((?:[^"\\]|\\.)*)"', block)


def parse_spec(spec, ex):
    """Parse a bit spec per user_io_status_bits().

    Returns (start, end) absolute bits, or None if the OSD would reject it.
    """
    if spec.startswith('['):
        mb = re.fullmatch(r'\[(\d+):(\d+)\]', spec)
        if mb:
            end, start = int(mb.group(1)), int(mb.group(2))
        else:
            mb = re.fullmatch(r'\[(\d+)\]', spec)
            if not mb:
                return None
            start = end = int(mb.group(1))
        if start > 127 or end > 127 or end <= start:
            return None
    else:
        v0 = char_to_bit(spec[0]) if spec else None
        if v0 is None:
            return None
        start = v0
        v1 = char_to_bit(spec[1]) if len(spec) > 1 else None
        if v1 is None:
            end = start  # single bit
        else:
            end = v1
        if ex:
            start += 32
            end += 32
        if start > 127 or end > 127:
            return None
        if v1 is not None and end <= start:
            return None  # two-char spec must be a real range
    if end - start > 8:  # max 8 bits per option
        return None
    return start, end


def decode_option(opt_str):
    """Decode one option string.

    Returns a dict with keys: kind, header, label, and (for bit-owning kinds)
    lo, hi, bits. Kinds: option, action, title, sep, file, media, joystick,
    cheats, version, info, invalid.
    """
    s = opt_str.strip().rstrip(';').strip()
    parts = [p.strip() for p in s.split(',')]
    header = parts[0]
    label = parts[1] if len(parts) > 1 else ''
    values = parts[2:] if len(parts) > 2 else []
    base = {'kind': None, 'header': header, 'label': label}

    # No comma at all: raw info strings etc. (e.g. "State 1 saved").
    if ',' not in opt_str:
        base['kind'] = 'info'
        return base

    p = header
    # Strip leading H/D/h/d flag pairs (2 chars each).
    while len(p) >= 3 and p[0] in 'HDhd':
        p = p[2:]
    # Skip the 'P<page>' prefix (exactly 2 chars).
    if p[0] == 'P':
        p = p[2:]

    if not p:
        base['kind'] = 'title'
        return base
    if p[0] == '-':
        base['kind'] = 'sep'
        return base
    if p[0] == 'P' and len(p) >= 2 and p[1].isdigit():
        # Page navigation / page title entry.
        base['kind'] = 'title'
        base['page'] = int(p[1])
        return base

    ex = False
    if p[0] in 'RTtr':
        ex = p[0].islower()
        spec = p[1:2]
        rng = parse_spec(spec, ex) if spec else None
        if rng is None or rng[0] != rng[1]:
            base['kind'] = 'invalid'
            base['note'] = 'toggle/reset action needs exactly one valid bit'
            return base
        base.update(kind='action', lo=rng[0], hi=rng[1], bits={rng[0]})
        return base

    if p[0] in 'Oo':
        ex = (p[0] == 'o')
        spec = p[2:] if len(p) > 1 and p[1] == 'X' else p[1:]
        rng = parse_spec(spec, ex) if spec else None
        if rng is None:
            base['kind'] = 'invalid'
            base['note'] = 'OSD would print "Invalid OSD option" for this spec'
            return base
        base.update(kind='option', lo=rng[0], hi=rng[1],
                    bits=set(range(rng[0], rng[1] + 1)),
                    bank='upper' if rng[0] >= 32 else 'lower',
                    values=values)
        return base

    if p[0] in 'FS':
        base['kind'] = 'media'  # file load / image mount: no status bits
        return base
    if p[0] in 'JC':
        base['kind'] = 'joystick' if p[0] in 'Jj' else 'cheats'
        return base
    if p[0] == 'V':
        base['kind'] = 'version'
        return base
    if p[0] == 'I':
        base['kind'] = 'info'
        return base

    base['kind'] = 'unknown'
    return base


def decode_all(strings):
    """Decode all option strings into a list of records."""
    out = []
    for st in strings:
        rec = decode_option(st)
        rec['raw'] = st
        out.append(rec)
    return out


BIT_KINDS = ('option', 'action')


def find_conflicts(records):
    """Return {bit: [labels]} for bits owned by more than one entry."""
    owner = {}
    for r in records:
        if r.get('kind') not in BIT_KINDS:
            continue
        for b in r['bits']:
            owner.setdefault(b, []).append(r['label'] or r['header'])
    return {b: labels for b, labels in sorted(owner.items()) if len(labels) > 1}


def free_bits(records, width=128):
    used = set()
    for r in records:
        if r.get('kind') in BIT_KINDS:
            used |= r['bits']
    return [b for b in range(width) if b not in used]


def format_bits(r):
    if r['lo'] == r['hi']:
        return 'status[%d]' % r['lo']
    return 'status[%d:%d]' % (r['hi'], r['lo'])


def render(records):
    lines = []
    for r in records:
        k = r['kind']
        if k in BIT_KINDS:
            if k == 'option':
                nv = len(r.get('values', []))
                nb = r['hi'] - r['lo'] + 1
                flag = '' if nv <= (1 << nb) else '  <-- %d values need >%d bits' % (nv, nb)
                bank = r.get('bank', '?')
                lines.append('  %-8s %-14s %-8s %s%s' %
                             (r['header'], format_bits(r), bank, r['label'], flag))
            else:
                lines.append('  %-8s %-14s %-8s %s (toggle/reset action)' %
                             (r['header'], format_bits(r), '-', r['label']))
        elif k == 'title':
            lines.append('  page %s: %s' % (r.get('page', '?'), r['label']))
        elif k == 'sep':
            lines.append('  ---')
        elif k == 'invalid':
            lines.append('  ! %-8s %-14s %s  <-- %s' %
                         (r['header'], r['label'], r['raw'], r.get('note', '')))
        else:
            lines.append('  %-8s %-14s %s (%s, no bits)' %
                         (r['header'], r['label'], r['raw'], k))
    return '\n'.join(lines)


def load_records(path_or_str, as_str=False):
    text = path_or_str if as_str else open(path_or_str, 'r', encoding='utf-8',
                                           errors='replace').read()
    return decode_all(extract_confstr_strings(text))


def main(argv):
    args = argv[1:]
    as_str = False
    as_json = False
    show_free = False
    find_range = None
    diff = False

    positional = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == '--str':
            as_str = True
        elif a == '--json':
            as_json = True
        elif a == '--free':
            show_free = True
        elif a == '--find':
            i += 1
            find_range = args[i]
        elif a == '--diff':
            diff = True
        else:
            positional.append(a)
        i += 1

    if diff:
        if len(positional) < 2:
            print('usage: osd_alloc.py --diff A.sv B.sv', file=sys.stderr)
            return 2
        ra = load_records(positional[0])
        rb = load_records(positional[1])
        ma = {r['header']: r for r in ra if r.get('kind') in BIT_KINDS}
        mb = {r['header']: r for r in rb if r.get('kind') in BIT_KINDS}
        for h in sorted(set(ma) | set(mb)):
            if h not in ma:
                print('  + %s  %s  (added)' % (h, format_bits(mb[h])))
            elif h not in mb:
                print('  - %s  %s  (removed)' % (h, format_bits(ma[h])))
            elif ma[h]['bits'] != mb[h]['bits']:
                print('  ~ %s  %s -> %s  (moved)' %
                      (h, format_bits(ma[h]), format_bits(mb[h])))
        c = find_conflicts(rb)
        if c:
            print('  CONFLICTS in B:')
            for b, labels in c.items():
                print('    bit %d: %s' % (b, ' vs '.join(labels)))
        else:
            print('  no bit conflicts in B')
        return 0

    if len(positional) < 1:
        print(__doc__)
        return 2
    records = load_records(positional[0], as_str=as_str)

    if as_json:
        print(json.dumps(records, indent=2, sort_keys=True))
        return 0

    print(render(records))
    conflicts = find_conflicts(records)
    if conflicts:
        print('\nCONFLICTS:')
        for b, labels in conflicts.items():
            print('  bit %d: %s' % (b, ' vs '.join(labels)))
    else:
        print('\nno bit conflicts')

    if show_free or find_range is None:
        fb = free_bits(records)
        print('free bits (%d): %s' %
              (len(fb), ' '.join(str(b) for b in fb) if fb else '(none)'))

    if find_range is not None:
        m = re.fullmatch(r'(\d+)(?::(\d+))?', find_range.strip())
        if not m:
            print('bad --find range: %s' % find_range, file=sys.stderr)
            return 2
        hi = int(m.group(1))
        lo = int(m.group(2)) if m.group(2) else hi
        want = set(range(lo, hi + 1))
        owners = []
        for r in records:
            if r.get('kind') in BIT_KINDS and (r['bits'] & want):
                owners.append('%s (%s)' % (r['header'], format_bits(r)))
        print('bits %s owned by: %s' %
              (find_range, ', '.join(owners) if owners else 'FREE'))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
