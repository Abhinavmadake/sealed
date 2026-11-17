"""Builds the Sealed project report: python3 build_report.py, then print report.html to PDF."""
import base64
import html
import os
import re
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
CSS = open(os.path.join(HERE, 'paper.css')).read()


def img(name):
    path = os.path.join(HERE, 'figs', name)
    return 'data:image/jpeg;base64,' + base64.b64encode(open(path, 'rb').read()).decode()


DART_KW = set('''import library part as show hide class enum extends implements with mixin abstract final const var
late static void return if else for while do switch case default break continue try catch on finally throw rethrow
new this super null true false async await yield sealed base required get set factory operator is in typedef'''.split())
PY_KW = set('''import from as def class return if elif else for while try except finally raise with pass None True False
and or not in is lambda yield async await'''.split())


def highlight(src, lang):
    kw = DART_KW if lang == 'dart' else PY_KW
    comment = r'//[^\n]*' if lang == 'dart' else r'#[^\n]*'
    tok = re.compile(rf"""(?P<c>{comment})|(?P<s>r?'[^'\n]*'|r?"[^"\n]*")|(?P<w>[A-Za-z_]\w*)|(?P<o>[\s\S])""")
    out = []
    for m in tok.finditer(src):
        k, v = m.lastgroup, m.group()
        e = html.escape(v)
        cls = {'c': 'c', 's': 's'}.get(k)
        if k == 'w' and v in kw:
            cls = 'k'
        out.append(f'<span class="{cls}">{e}</span>' if cls else e)
    return ''.join(out)


def listing(num, caption, src, lang):
    lines = highlight(src.rstrip('\n'), lang).split('\n')
    body = '\n'.join(f'<span class="ln">{i:>3}</span>{line}' for i, line in enumerate(lines, 1))
    return f'<div class="listing"><div class="lcap"><b>Listing {num}.</b> {caption}</div><pre>{body}</pre></div>'


def find(rel, first, last):
    """The block from the line containing `first` to the next line containing `last`."""
    lines = open(os.path.join(ROOT, rel)).read().split('\n')
    a = next(i for i, l in enumerate(lines) if first in l)
    b = next(i for i in range(a, len(lines)) if last in lines[i])
    return '\n'.join(lines[a:b + 1])


def text(name):
    return html.escape(open(os.path.join(HERE, name)).read().rstrip())


def sec(num, title, body, pb=False):
    return f'<div class="sec{" pb" if pb else ""}">\n<h2><span class="n">{num}</span>{title}</h2>\n{body}\n</div>'


def sub(num, title):
    return f'<h3><span class="n">{num}</span>{title}</h3>'


def table(num, caption, head, rows, widths=None, split=False):
    ws = widths or [None] * len(head)
    th = ''.join(f'<th{f" style=\"width:{w}\"" if w else ""}>{h}</th>' for h, w in zip(head, ws))
    tr = ''.join('<tr>' + ''.join(f'<td>{c}</td>' for c in r) + '</tr>' for r in rows)
    return (f'<div class="tbl{" split" if split else ""}"><table><caption class="tcap"><b>Table {num}.</b> {caption}</caption>'
            f'<thead><tr>{th}</tr></thead><tbody>{tr}</tbody></table></div>')


def shots(num, caption, items):
    cells = ''.join(f'<div><img src="{img(f)}"><div class="sub">({chr(97 + i)}) {s}</div></div>' for i, (f, s) in enumerate(items))
    return f'<figure><div class="shots">{cells}</div><figcaption><b>Fig. {num}.</b> {caption}</figcaption></figure>'


def diagram(num, caption, svg):
    return f'<figure><div class="diagram">{svg}</div><figcaption><b>Fig. {num}.</b> {caption}</figcaption></figure>'


ARROW = '<defs><marker id="{id}" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0 L8,4 L0,8 z" fill="#333"/></marker></defs>'

ARCH = f"""<svg viewBox="0 0 640 250" xmlns="http://www.w3.org/2000/svg" font-family="Helvetica, Arial, sans-serif">
{ARROW.format(id='ar')}
<g font-size="10.5" fill="#111">
<rect x="10" y="20" width="250" height="210" rx="6" fill="#fff" stroke="#111" stroke-width="1.2"/>
<text x="24" y="40" font-weight="bold" font-size="11">Flutter client (Android, web)</text>
<rect x="24" y="52" width="222" height="26" rx="3" fill="#f1f1f1" stroke="#999" stroke-width=".6"/><text x="34" y="69">UI screens (Material 3)</text>
<rect x="24" y="84" width="222" height="26" rx="3" fill="#f1f1f1" stroke="#999" stroke-width=".6"/><text x="34" y="101">VaultService: lock state, auto-lock</text>
<rect x="24" y="116" width="106" height="44" rx="3" fill="#f1f1f1" stroke="#999" stroke-width=".6"/><text x="32" y="134">Crypto layer</text><text x="32" y="149" font-size="9" fill="#555">libsodium</text>
<rect x="140" y="116" width="106" height="44" rx="3" fill="#f1f1f1" stroke="#999" stroke-width=".6"/><text x="148" y="134">Sync engine</text><text x="148" y="149" font-size="9" fill="#555">three-way merge</text>
<rect x="24" y="166" width="106" height="44" rx="3" fill="#f1f1f1" stroke="#999" stroke-width=".6"/><text x="32" y="184">Local store</text><text x="32" y="199" font-size="9" fill="#555">sembast, ciphertext</text>
<rect x="140" y="166" width="106" height="44" rx="3" fill="#f1f1f1" stroke="#999" stroke-width=".6"/><text x="148" y="184">API client</text><text x="148" y="199" font-size="9" fill="#555">HTTPS, JSON</text>
<line x1="295" y1="10" x2="295" y2="240" stroke="#777" stroke-dasharray="4 3"/>
<text x="290" y="248" font-size="8.5" fill="#555" text-anchor="end">plaintext</text><text x="300" y="248" font-size="8.5" fill="#555">ciphertext only</text>
<rect x="330" y="50" width="160" height="150" rx="6" fill="#fff" stroke="#111" stroke-width="1.2"/>
<text x="344" y="70" font-weight="bold" font-size="11">FastAPI server</text>
<text x="344" y="92">auth, sessions</text><text x="344" y="110">items, sync</text><text x="344" y="128">sharing, revocation</text>
<text x="344" y="146">login lockout</text><text x="344" y="164">Alembic migrations</text>
<rect x="540" y="80" width="90" height="90" rx="6" fill="#fff" stroke="#111" stroke-width="1.2"/>
<text x="552" y="104" font-weight="bold" font-size="11">PostgreSQL</text>
<text x="552" y="124" font-size="9.5">users</text><text x="552" y="138" font-size="9.5">items, grants</text><text x="552" y="152" font-size="9.5">sessions</text>
<line x1="246" y1="188" x2="326" y2="125" stroke="#333" stroke-width="1.1" marker-end="url(#ar)"/>
<text x="300" y="176" font-size="9" fill="#555">REST /api/v1</text>
<line x1="490" y1="125" x2="536" y2="125" stroke="#333" stroke-width="1.1" marker-end="url(#ar)"/>
<text x="488" y="116" font-size="9" fill="#555">SQLAlchemy</text>
</g></svg>"""

KEYS = f"""<svg viewBox="0 0 640 300" xmlns="http://www.w3.org/2000/svg" font-family="Helvetica, Arial, sans-serif">
{ARROW.format(id='k')}
<g font-size="10.5" fill="#111">
<rect x="20" y="16" width="200" height="34" rx="4" fill="#f1f1f1" stroke="#111"/><text x="34" y="37">master password + salt</text>
<line x1="120" y1="50" x2="120" y2="78" stroke="#333" marker-end="url(#k)"/><text x="128" y="68" font-size="9" fill="#555">Argon2id (ops 3, 256 MiB)</text>
<rect x="20" y="80" width="200" height="34" rx="4" fill="#fff" stroke="#111"/><text x="34" y="101">master key (never stored or sent)</text>
<line x1="70" y1="114" x2="70" y2="146" stroke="#333" marker-end="url(#k)"/><line x1="170" y1="114" x2="170" y2="146" stroke="#333" marker-end="url(#k)"/>
<text x="20" y="134" font-size="9" fill="#555">KDF id 1</text><text x="178" y="134" font-size="9" fill="#555">KDF id 2</text>
<rect x="10" y="148" width="110" height="44" rx="4" fill="#fff" stroke="#888"/><text x="20" y="166">auth key</text><text x="20" y="182" font-size="9" fill="#555">server keeps its hash</text>
<rect x="130" y="148" width="100" height="44" rx="4" fill="#fff" stroke="#888"/><text x="140" y="166">wrap key</text><text x="140" y="182" font-size="9" fill="#555">encrypts account key</text>
<line x1="230" y1="170" x2="296" y2="170" stroke="#333" marker-end="url(#k)"/>
<rect x="300" y="146" width="150" height="48" rx="4" fill="#f1f1f1" stroke="#111"/><text x="312" y="166" font-weight="bold">account key</text><text x="312" y="182" font-size="9" fill="#555">random, fixed for life</text>
<line x1="375" y1="194" x2="330" y2="232" stroke="#333" marker-end="url(#k)"/><line x1="375" y1="194" x2="420" y2="232" stroke="#333" marker-end="url(#k)"/>
<line x1="450" y1="170" x2="506" y2="170" stroke="#333" marker-end="url(#k)"/>
<rect x="260" y="234" width="130" height="44" rx="4" fill="#fff" stroke="#888"/><text x="270" y="252">X25519 private key</text><text x="270" y="268" font-size="9" fill="#555">for sharing</text>
<rect x="400" y="234" width="120" height="44" rx="4" fill="#fff" stroke="#888"/><text x="410" y="252">item keys</text><text x="410" y="268" font-size="9" fill="#555">one per item</text>
<rect x="510" y="146" width="120" height="48" rx="4" fill="#fff" stroke="#888"/><text x="520" y="166">session token</text><text x="520" y="182" font-size="9" fill="#555">local store only</text>
<line x1="520" y1="256" x2="560" y2="256" stroke="#333" marker-end="url(#k)"/><text x="566" y="252">item JSON</text><text x="566" y="266" font-size="9" fill="#555">XChaCha20</text>
<rect x="300" y="16" width="200" height="34" rx="4" fill="#f1f1f1" stroke="#111"/><text x="312" y="37">recovery key (shown once)</text>
<line x1="400" y1="50" x2="400" y2="78" stroke="#333" marker-end="url(#k)"/>
<rect x="300" y="80" width="200" height="34" rx="4" fill="#fff" stroke="#888"/><text x="312" y="101">recovery auth + recovery wrap</text>
<line x1="400" y1="114" x2="380" y2="144" stroke="#333" marker-end="url(#k)"/><text x="410" y="134" font-size="9" fill="#555">second copy</text>
</g></svg>"""


def use_case_svg():
    cases = ['Register and log in', 'Unlock (password or fingerprint)', 'Manage items', 'Synchronise devices',
             'Resolve a sync conflict', 'Share an item', 'Revoke a share', 'Change password or recover',
             'Generate a password', 'Check vault health', 'Manage signed-in devices']
    ys = [34 + 26 * i for i in range(len(cases))]
    out = ['<svg viewBox="0 0 640 330" xmlns="http://www.w3.org/2000/svg" font-family="Helvetica, Arial, sans-serif">',
           '<g font-size="10" fill="#111" stroke-linecap="round">',
           '<rect x="170" y="8" width="300" height="314" fill="none" stroke="#111" stroke-width="1.1"/>',
           '<text x="180" y="22" font-size="9.5" font-weight="bold">Sealed</text>']

    def actor(x, y, label):
        return (f'<circle cx="{x}" cy="{y - 22}" r="7" fill="#fff" stroke="#111"/>'
                f'<line x1="{x}" y1="{y - 15}" x2="{x}" y2="{y + 5}" stroke="#111"/>'
                f'<line x1="{x - 10}" y1="{y - 8}" x2="{x + 10}" y2="{y - 8}" stroke="#111"/>'
                f'<line x1="{x}" y1="{y + 5}" x2="{x - 8}" y2="{y + 18}" stroke="#111"/>'
                f'<line x1="{x}" y1="{y + 5}" x2="{x + 8}" y2="{y + 18}" stroke="#111"/>'
                f'<text x="{x}" y="{y + 32}" text-anchor="middle">{label}</text>')

    for y in ys:
        out.append(f'<line x1="72" y1="165" x2="210" y2="{y}" stroke="#666" stroke-width=".7"/>')
    for i in (5, 6):
        out.append(f'<line x1="568" y1="150" x2="430" y2="{ys[i]}" stroke="#666" stroke-width=".7"/>')
    out.append(f'<line x1="552" y1="262" x2="430" y2="{ys[9]}" stroke="#666" stroke-width=".7"/>')
    for y, c in zip(ys, cases):
        out.append(f'<ellipse cx="320" cy="{y}" rx="112" ry="11" fill="#fff" stroke="#111" stroke-width=".9"/>'
                   f'<text x="320" y="{y + 3.5}" text-anchor="middle">{c}</text>')
    out.append(actor(55, 170, 'User'))
    out.append(actor(585, 155, 'Other user'))
    out.append('<rect x="552" y="248" width="80" height="30" fill="#fff" stroke="#111"/>'
               '<text x="592" y="261" text-anchor="middle" font-size="8.5">«external»</text>'
               '<text x="592" y="273" text-anchor="middle" font-size="9">HIBP API</text>')
    out.append('</g></svg>')
    return ''.join(out)


def er_svg():
    def entity(x, y, w, name, cols):
        h = 20 + 13 * len(cols) + 6
        parts = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#fff" stroke="#111" stroke-width="1.1"/>',
                 f'<rect x="{x}" y="{y}" width="{w}" height="20" fill="#e9e9e9" stroke="#111" stroke-width="1.1"/>',
                 f'<text x="{x + 8}" y="{y + 14}" font-weight="bold">{name}</text>']
        for i, (col, key) in enumerate(cols):
            ty = y + 33 + 13 * i
            parts.append(f'<text x="{x + 8}" y="{ty}" font-size="9" fill="#555">{key}</text>'
                         f'<text x="{x + 34}" y="{ty}"{" font-weight=\"bold\"" if key == "PK" else ""}>{col}</text>')
        return ''.join(parts)

    out = ['<svg viewBox="0 0 640 300" xmlns="http://www.w3.org/2000/svg" font-family="Helvetica, Arial, sans-serif">',
           '<g font-size="9.5" fill="#111">']
    out.append(entity(225, 10, 190, 'users', [('id', 'PK'), ('email', 'UQ'), ('auth_hash', ''), ('kdf_salt, kdf_ops, kdf_mem', ''),
                                              ('wrapped_account_key', ''), ('public_key', ''), ('wrapped_private_key', ''),
                                              ('recovery_auth_hash', ''), ('recovery_wrapped_key', '')]))
    out.append(entity(10, 10, 170, 'sessions', [('id', 'PK'), ('user_id', 'FK'), ('token_hash', 'UQ'), ('device_name', ''),
                                                ('last_seen_at', ''), ('expires_at', '')]))
    out.append(entity(460, 10, 170, 'items', [('id', 'PK'), ('owner_id', 'FK'), ('blob', ''), ('revision', ''), ('deleted_at', '')]))
    out.append(entity(460, 135, 170, 'grants', [('item_id', 'PK, FK'), ('user_id', 'PK, FK'), ('granted_by', 'FK'), ('wrapped_key', ''),
                                                ('key_kind', ''), ('permission', ''), ('revision', ''), ('revoked_at', '')]))
    out.append(entity(10, 175, 170, 'login_attempts', [('email', 'PK'), ('failures', ''), ('locked_until', '')]))
    out.append(entity(225, 215, 190, 'sync_counter', [('id', 'PK'), ('value', '')]))

    def rel(x1, y1, x2, y2, a, b, ax, ay, bx, by):
        return (f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="#333" stroke-width="1"/>'
                f'<text x="{ax}" y="{ay}" font-size="9">{a}</text><text x="{bx}" y="{by}" font-size="9">{b}</text>')

    out.append(rel(180, 56, 225, 56, 'N', '1', 184, 52, 216, 52))
    out.append(rel(460, 56, 415, 56, 'N', '1', 450, 52, 418, 52))
    out.append(rel(545, 92, 545, 135, '1', 'N', 549, 104, 549, 130))
    out.append(rel(460, 190, 415, 150, 'N', '1', 448, 196, 419, 148))
    out.append('</g></svg>')
    return ''.join(out)


def index(doc, pages):
    """The index page: every section and subsection with its page number."""
    rows = []
    for level, num, title in re.findall(r'<h([23])>(?:<span class="n">([^<]+)</span>)?([^<]+)</h[23]>', doc):
        page = pages.get(f'{num} {title}'.strip(), '00')
        rows.append(f'<div class="ix l{level}"><span class="no">{num}</span><span class="t">{title}</span>'
                    f'<span class="dots"></span><span class="pg">{page}</span></div>')
    return '<div class="index"><h2 class="ixh">Index</h2>' + ''.join(rows) + '</div>'


def build(pages=None):
    def named(f):
        names = {re.sub(r'.*/(test|integration_test)/', '', l.strip()) for l in open(os.path.join(HERE, f))}
        return len({n for n in names if ': ' in n and not re.search(r'setUpAll|tearDownAll', n)})

    d_count = named('devtest.txt')
    h_count = int(re.search(r'\+(\d+): All tests passed', open(os.path.join(HERE, 'hosttest_raw.txt')).read()).group(1))
    p_count = sum(1 for l in open(os.path.join(HERE, 'pytest.txt')) if 'PASSED' in l)
    total = p_count + h_count + d_count

    derive = find('app/lib/core/crypto/sealed_crypto.dart', 'Future<DerivedKeys> deriveFromPassword', 'return DerivedKeys(authBytes, wrap);') + '\n  }'
    seal = find('app/lib/core/crypto/sealed_crypto.dart', 'Uint8List seal(SecureKey key', 'return Uint8List.fromList([blobVersion') + '\n  }'
    merge = find('app/lib/core/sync/merge.dart', 'MergeResult threeWayMerge(', 'return MergeResult(merged, conflicts);') + '\n}'
    revisions = open(os.path.join(ROOT, 'server/app/revisions.py')).read()
    put_item = find('server/app/routers/items.py', '@router.put("/{item_id}"', 'return view_for(db, item, grant)')

    b = []
    b.append("""
<div class="titlepage">
<div class="kicker">Cross Platform Application Development</div>
<div class="kind">Mini Project Report</div>
<hr>
<h1>Sealed</h1>
<div class="subtitle">A Zero-Knowledge Password Manager<br>for Android and the Web</div>
<hr>
<div class="by">Submitted by</div>
<div class="author">Abhinav Madake</div>
<div class="affil">Roll No. 231070028</div>
<div class="stack">Flutter &middot; FastAPI &middot; PostgreSQL</div>
<div class="date">18 November 2026</div>
</div>
""")

    b.append(sec('1', 'Introduction', f"""
<p>Passwords remain the most common way to authenticate on the web, and the average person now holds credentials for well over
a hundred services. Because strong, unique passwords cannot be memorised at that scale, users fall back on short or reused ones,
and a single leaked password then opens several accounts. Password managers address this by generating a strong password for
every service and remembering it on the user's behalf, which makes them one of the most effective security tools available to
ordinary users.</p>
<p>A password manager is also a single, high-value target. A conventional cloud service that can read its users' vaults, or
holds the keys to them, places every user's credentials one database breach, one malicious insider or one compelled disclosure
away from exposure. The alternative is a <i>zero-knowledge</i> design, in which the server is not trusted with confidentiality
at all: every key is derived or generated on the user's device, and the server stores and synchronises only data it cannot
decrypt.</p>
<p>This report presents <b>Sealed</b>, a zero-knowledge password manager built as the mini project for the Cross Platform
Application Development course. A single Flutter codebase delivers the client on Android and in the browser, and a FastAPI
service backed by PostgreSQL provides accounts, synchronisation and sharing. All cryptography uses libsodium. The main
contributions are:</p>
<ul>
<li>a key hierarchy that separates authentication from encryption, so the server can verify a password without being able to
decrypt anything, and that makes password changes independent of vault size;</li>
<li>multi-device synchronisation with offline editing, built on a commit-ordered revision counter and a field-level three-way
merge performed on the client;</li>
<li>item sharing based on authenticated public-key encryption, with revocation that rotates the item key in a single
transaction;</li>
<li>a polished cross-platform interface, verified on an Android emulator, a physical phone and Chrome, together with {total}
automated tests.</li>
</ul>
<p>Section 2 states the problem precisely and Section 3 outlines the proposed solution. Sections 4 to 6 set out the objectives,
scope and requirements. Sections 7 to 10 describe the technology stack, architecture, database and core logic, and Section 11
covers deployment and verification.</p>
"""))

    b.append(sec('2', 'Problem Statement', """
<p>The task is to design and implement a cross-platform password manager that satisfies two requirements at once. First, the
server, its operators and anyone who obtains a complete copy of its database must be unable to recover any stored secret.
Second, the user must keep the conveniences expected of a cloud-backed manager: access from several devices, use without a
network connection, sharing with other people, changing the master password and recovering a forgotten one.</p>
<p>These requirements are in tension. The server must authenticate users without ever learning their password. It must order and
synchronise edits made concurrently on different devices, although it cannot read them. Sharing must give a second person access
without the server holding a usable key, and withdrawing access must protect future changes. Changing the master password should
not require re-encrypting the whole vault, and recovery must be possible without key escrow, which would defeat the purpose.</p>
<p>The adversary considered is the server side: an attacker who steals the database, an operator who reads it, or a server that
actively misbehaves, for example by substituting public keys, swapping ciphertexts between records or advertising weak key
derivation parameters. A compromised client device is outside the threat model, since no client-side scheme can defend against
malware that observes the unlocked vault.</p>
"""))

    b.append(sec('3', 'Proposed Solution', f"""
<p>Sealed moves every cryptographic operation to the client. The master password is stretched with Argon2id on the device into a
master key, from which two independent subkeys are derived: an <i>auth key</i>, which the server stores only as a further Argon2id
hash and uses to authenticate the user, and a <i>wrap key</i>, which never leaves the device. The wrap key encrypts a random
<i>account key</i>, which in turn protects one random key per item and the user's X25519 private key. The server therefore receives
a hash, encrypted keys and encrypted items, and nothing it can use to decrypt them.</p>
<p>Synchronisation is built around a global revision number that the server assigns in commit order. Each device pulls every change
newer than its cursor and pushes a queue of local edits, each tagged with the revision it was based on. When an edit is stale, the
server rejects it with the current version, and the client decrypts both sides and merges them field by field, asking the user only
about fields that were changed differently on both devices. Sharing wraps an item key for another user with authenticated public-key
encryption, and revocation re-encrypts the item under a new key. A recovery key, generated at registration and shown once, wraps a
second copy of the account key.</p>
<p>Around this core the client offers the features of a daily-use manager: logins and secure notes, search and favourites, a
password and passphrase generator, a vault health report with breach checking, a list of signed-in devices with remote sign-out,
automatic locking, clipboard clearing and fingerprint unlock on Android. The interface is dark, with topographic contour lines,
frosted glass surfaces and a padlock rendered by a fragment shader as fine grain lit by a beam of light (Fig. 1).</p>
{shots(1, 'Main screens of the Android client. (a) Welcome screen. (b) Lock screen; unlocking is a local operation and works offline. (c) The vault, with filter tabs and grouped item rows. (d) An item with copy actions and a strength indicator.',
       [('welcome.jpg', 'Welcome'), ('unlock.jpg', 'Locked'), ('vault.jpg', 'Vault'), ('detail.jpg', 'Item')])}
"""))

    b.append(sec('4', 'Objectives', """
<ol class="obj">
<li><b class="id">O1</b><span><b>Confidentiality by construction.</b> The server must never hold a key or plaintext capable of
decrypting a user's vault, and a full database dump must reveal no password.</span></li>
<li><b class="id">O2</b><span><b>Practical multi-device use.</b> Synchronise vaults across devices, keep the vault usable offline and
merge concurrent edits without losing data.</span></li>
<li><b class="id">O3</b><span><b>Controlled collaboration.</b> Share an item with another user with read or write permission, and revoke
access so that later changes stay private.</span></li>
<li><b class="id">O4</b><span><b>Complete account lifecycle.</b> Change the master password at a cost independent of vault size,
recover access with a one-time recovery key, and sign out lost devices remotely.</span></li>
<li><b class="id">O5</b><span><b>Password hygiene.</b> Generate strong passwords and passphrases and identify weak, reused and breached
ones without disclosing them.</span></li>
<li><b class="id">O6</b><span><b>One codebase, several platforms.</b> Deliver the same encrypted vault and a consistent, responsive
interface on Android and the web from a single Flutter project.</span></li>
</ol>
"""))

    b.append(sec('5', 'Scope', """
<h3><span class="n">5.1</span>In Scope</h3>
<p>Registration, login, locking and offline unlocking; logins and secure notes with search, filters and favourites; synchronisation
with conflict resolution; sharing and revocation; master password change; recovery key; password generator; vault health with breach
checking; device list with remote sign-out; automatic locking and clipboard clearing; and fingerprint unlock on Android. The client
targets Android and the web; the server targets any host that runs Python and PostgreSQL.</p>
<h3><span class="n">5.2</span>Out of Scope</h3>
<p>An Android autofill service and a browser extension, both of which require substantial platform-specific code; file attachments;
organisations and shared collections; e-mail verification and two-factor login; and iOS and macOS builds. The last share the same
code but were not built, because Xcode is not configured on the development machine.</p>
<h3><span class="n">5.3</span>Limitations</h3>
<ul>
<li>Metadata remains visible to the server: e-mail addresses, timestamps, item counts and sizes, and who shares with whom.</li>
<li>The server could replay an older version of an item; clients do not yet detect such a rollback.</li>
<li>A revoked user keeps whatever was already decrypted; key rotation protects only future changes.</li>
<li>Read-only sharing is enforced by the server rather than cryptographically.</li>
<li>Forgetting both the master password and the recovery key loses the vault, which is the price of zero knowledge.</li>
<li>Dart cannot reliably wipe strings, so decrypted text may remain in memory until it is garbage-collected.</li>
</ul>
"""))

    uc_rows = [
        ['UC-1', 'Register', 'User', 'Create an account; all keys are generated on the device and the recovery key is shown once.'],
        ['UC-2', 'Log in on a device', 'User', 'Prove knowledge of the master password and download the wrapped keys.'],
        ['UC-3', 'Unlock the vault', 'User', 'Decrypt the local vault with the master password or a fingerprint, with or without a network.'],
        ['UC-4', 'Manage items', 'User', 'Add, view, edit, favourite, search and delete logins and secure notes.'],
        ['UC-5', 'Synchronise devices', 'User', 'Exchange encrypted changes with the server; offline edits are queued and sent later.'],
        ['UC-6', 'Resolve a sync conflict', 'User', 'Choose a value for each field that was edited differently on two devices.'],
        ['UC-7', 'Share an item', 'User, other user', 'Grant read or write access after comparing security fingerprints.'],
        ['UC-8', 'Revoke a share', 'User, other user', 'Withdraw access; the item is re-encrypted under a new key.'],
        ['UC-9', 'Change password or recover', 'User', 'Replace the master password, or regain access with the recovery key.'],
        ['UC-10', 'Generate a password', 'User', 'Create a random password or a passphrase with an entropy estimate.'],
        ['UC-11', 'Check vault health', 'User, HIBP', 'List weak, reused and breached passwords and compute a health score.'],
        ['UC-12', 'Manage devices', 'User', 'List signed-in devices and sign one out remotely.'],
    ]
    fr_rows = [
        ['FR-1', 'The system shall register a user from an e-mail address and master password, generating the account key, X25519 key pair and recovery key on the device.'],
        ['FR-2', 'The system shall authenticate a user with a key derived from the master password and issue a session token valid for 30 days.'],
        ['FR-3', 'The client shall unlock the vault locally without a network connection and reject a wrong password by failed authenticated decryption.'],
        ['FR-4', 'The client shall lock on request and automatically after a configurable idle period of 1, 5 or 15 minutes or 1 hour.'],
        ['FR-5', 'The client shall store logins (title, username, password, website, notes) and secure notes, with favourites, search and type filters.'],
        ['FR-6', 'The client shall queue changes made offline and synchronise them by pulling changes since a cursor and pushing the queue.'],
        ['FR-7', 'The server shall reject stale updates with the current version, and the client shall merge them field by field, asking the user only about true conflicts.'],
        ['FR-8', 'The system shall share an item with another user with read or write permission and show both users a key fingerprint to compare.'],
        ['FR-9', 'The system shall revoke a share and rotate the item key for all remaining users in a single transaction.'],
        ['FR-10', 'The system shall change the master password without re-encrypting items and end all other sessions.'],
        ['FR-11', 'The system shall restore access with the recovery key and require a new master password.'],
        ['FR-12', 'The client shall generate passwords with selectable character classes and length, and passphrases from the EFF wordlist.'],
        ['FR-13', 'The client shall report weak, reused and breached passwords, checking breaches with the k-anonymous Have I Been Pwned range API.'],
        ['FR-14', 'The system shall list a user\'s signed-in devices and allow any of them to be signed out remotely.'],
        ['FR-15', 'The client shall clear copied secrets from the clipboard after a configurable delay of 15, 30 or 60 seconds.'],
        ['FR-16', 'The Android client shall optionally unlock with a fingerprint, keeping the account key in the Android Keystore.'],
    ]
    nfr_rows = [
        ['NFR-1', 'Confidentiality', 'The server and its database never hold plaintext or a key able to decrypt it.', 'Client-side libsodium; the server stores hashes and ciphertext only (Section 9.3).'],
        ['NFR-2', 'Integrity', 'Tampering with, or swapping, stored ciphertext is detected.', 'AEAD with the record\'s purpose and identifier bound as associated data.'],
        ['NFR-3', 'Guessing resistance', 'Offline guessing is expensive and online guessing is throttled.', 'Argon2id with 256 MiB; a client-side parameter floor; lockout after five failures.'],
        ['NFR-4', 'Availability', 'The vault remains usable without a network.', 'Encrypted local store and a queue of pending changes.'],
        ['NFR-5', 'Consistency', 'No update is lost or skipped during synchronisation.', 'Commit-ordered revisions and optimistic concurrency control.'],
        ['NFR-6', 'Privacy', 'Little is disclosed to third parties or through sizes.', 'Only a five-character hash prefix reaches HIBP; item plaintext padded to 256-byte blocks.'],
        ['NFR-7', 'Portability', 'One codebase serves Android and the web.', 'Flutter; libsodium native on Android and WebAssembly in the browser.'],
        ['NFR-8', 'Performance', 'Unlocking takes about a second and the interface stays smooth.', 'Tuned Argon2id cost; static artwork rendered once and cached as images.'],
        ['NFR-9', 'Usability', 'The interface is consistent and accessible.', 'Material 3 components with semantic labels for screen readers.'],
        ['NFR-10', 'Maintainability', 'Behaviour is protected by automated tests.', f'{total} tests across server, host and on-device suites (Section 11.5).'],
    ]
    b.append(sec('6', 'Requirements', f"""
<p>The requirements below were derived from the objectives in Section 4. Use cases describe the interactions between the system and
its actors; functional requirements state what the system must do, and non-functional requirements state the qualities it must have.</p>
{sub('6.1', 'Use Cases')}
<p>Three actors interact with Sealed: the <i>user</i> who owns a vault, the <i>other user</i> with whom an item is shared, and the
external Have I Been Pwned (HIBP) service used for breach checks. The server is part of the system and not an actor. Fig. 2 shows the
use cases and Table 1 summarises them.</p>
{diagram(2, 'Use case diagram of Sealed.', use_case_svg())}
{table(1, 'Use cases.', ['ID', 'Use case', 'Actors', 'Description'], uc_rows, ['8%', '24%', '15%', None], split=True)}
{sub('6.2', 'Functional Requirements')}
{table(2, 'Functional requirements.', ['ID', 'Requirement'], fr_rows, ['8%', None], split=True)}
<div class="keep">{sub('6.3', 'Non-functional Requirements')}
{table(3, 'Non-functional requirements and how they are met.', ['ID', 'Attribute', 'Requirement', 'Realisation'], nfr_rows, ['8%', '15%', '36%', None])}</div>
"""))

    tech_rows = [
        ['Client framework', 'Flutter 3.44.8, Dart 3.12.2', 'Single UI codebase for Android and the web'],
        ['Cryptography', 'sodium 4.0.4 (libsodium 1.0.21)', 'Argon2id, BLAKE2b KDF, XChaCha20-Poly1305, X25519 <code>crypto_box</code>'],
        ['Local storage', 'sembast 3.10, sembast_web 2.4', 'Document store on files (Android) and IndexedDB (web)'],
        ['Client libraries', 'provider 6.1, http 1.6, uuid 4.6', 'State management, REST client, client-side item identifiers'],
        ['Biometrics', 'flutter_secure_storage 11.2, local_auth 3.0', 'Keystore-protected account key behind a fingerprint'],
        ['Server framework', 'FastAPI 0.121, Uvicorn 0.38', 'REST API and ASGI server'],
        ['Persistence', 'SQLAlchemy 2.0, Alembic 1.17', 'ORM and schema migrations'],
        ['Database', 'PostgreSQL 17.11', 'Relational storage of accounts, items and grants'],
        ['Server security', 'argon2-cffi 25.1, pydantic 2.14', 'Hashing of auth keys; request validation'],
        ['Testing', 'pytest 8.4, flutter_test, integration_test', 'Server, host and on-device tests'],
        ['Hosting (demo)', 'Tailscale Funnel 1.104', 'Fixed public HTTPS address for the phone demonstration'],
    ]
    b.append(sec('7', 'Technology Stack', f"""
{table(4, 'Technology stack.', ['Layer', 'Technology and version', 'Purpose'], tech_rows, ['18%', '34%', None])}
<p><b>Flutter</b> was chosen because a password manager is only useful if it is available wherever the user is, and Flutter compiles
one Dart codebase to native Android code and to the web. The <b>sodium</b> package exposes the same libsodium API on both targets,
wrapping the native library on Android and its WebAssembly build in the browser, so the cryptographic core is shared rather than
reimplemented. libsodium itself was preferred to lower-level libraries because it offers misuse-resistant, well-reviewed
constructions with safe defaults.</p>
<p>On the server, <b>FastAPI</b> provides typed request validation and automatic interactive documentation with very little code, which
keeps the backend small and easy to audit; it never needs to understand the data it stores. <b>PostgreSQL</b> supplies the
transactional guarantees on which revision ordering and atomic key rotation depend.</p>
"""))

    api_rows = [
        ['POST /auth/prelogin', 'Salt and key derivation parameters for an e-mail address (stable but fake for unknown addresses)'],
        ['POST /auth/register', 'Create an account from material generated on the client'],
        ['POST /auth/login, /auth/logout', 'Verify the auth key and return a session token and wrapped keys; end a session'],
        ['POST /auth/change-password', 'Replace the salt, auth hash and wrapped account key; end other sessions'],
        ['POST /auth/recover/start, /finish', 'Verify the recovery auth key, return the recovery-wrapped account key, set a new password'],
        ['GET /sessions, DELETE /sessions/{id}', 'List signed-in devices; sign one out'],
        ['GET /sync?since=N', 'Every change after revision N, including deletions and revoked grants'],
        ['PUT /items/{id}', 'Create, or update with <code>base_revision</code>; responds 409 with the current version when stale'],
        ['DELETE /items/{id}', 'Mark an item as deleted (owner only)'],
        ['GET /users/lookup?email=', 'Public key of another user, for sharing'],
        ['GET, POST /items/{id}/grants', 'List and add shares'],
        ['POST /items/{id}/revoke', 'Remove a user and rotate the item key for everyone else, in one transaction'],
    ]
    module_rows = [
        ['core/crypto', 'Key derivation, authenticated encryption, key wrapping, X25519 sharing, recovery key encoding, fingerprints'],
        ['core/store', 'Local store for the account record, server copies of items, pending changes and pinned contact keys'],
        ['core/sync', 'Sync engine, field-level three-way merge, repository combining server copies with pending edits'],
        ['core/api', 'Typed REST client with conflict and offline exceptions'],
        ['core/health', 'Strength estimation, breach range check, password and passphrase generator'],
        ['core/biometric', 'Keystore-protected copy of the account key for fingerprint unlock'],
        ['services', 'Vault session (lock state, auto-lock, sync scheduling), authentication flows, sharing'],
        ['ui', 'Screens, theme and custom widgets (contour background, glass surfaces, shader-rendered lock)'],
    ]
    b.append(sec('8', 'System Architecture', f"""
<p>Sealed follows a client-server architecture in which the trust boundary coincides with the network boundary (Fig. 3). Everything
on the client side may handle plaintext; everything on the server side handles only hashes and ciphertext. The client is a layered
Flutter application and the server is a stateless REST service in front of PostgreSQL.</p>
{diagram(3, 'System architecture. The dashed line is both the network boundary and the trust boundary.', ARCH)}
{sub('8.1', 'Client')}
<p>The client is organised so that cryptography and synchronisation are independent of the user interface (Table 5).
<code>VaultService</code> owns the session and the unlocked keys, and screens observe it through <code>provider</code>. The local store
persists only ciphertext and non-sensitive metadata, which is what allows the vault to be unlocked offline. The sync engine runs
when the vault is unlocked, after every change and on request.</p>
{table(5, 'Client modules.', ['Module', 'Responsibility'], module_rows, ['18%', None])}
{sub('8.2', 'Server and API')}
<p>The server exposes a versioned REST API under <code>/api/v1</code> (Table 6). Requests and responses are JSON, binary values are
base64-encoded, and authenticated requests carry a bearer token whose SHA-256 hash is stored in the <code>sessions</code> table. Each
router handles one concern: authentication, sessions, items, synchronisation or sharing. Interactive documentation is generated at
<code>/docs</code>.</p>
{table(6, 'REST API endpoints.', ['Method and path', 'Purpose'], api_rows, ['36%', None])}
"""))

    schema_rows = [
        ['users', 'id, email, auth_hash, kdf_salt, kdf_ops, kdf_mem, wrapped_account_key, public_key, wrapped_private_key, recovery_auth_hash, recovery_wrapped_key', 'Only hashes and encrypted keys'],
        ['sessions', 'id, user_id, token_hash, device_name, last_seen_at, expires_at', 'SHA-256 of the bearer token; 30-day expiry'],
        ['items', 'id (client UUID), owner_id, blob, revision, deleted_at', 'Deleted items kept as tombstones so deletions synchronise'],
        ['grants', 'item_id, user_id, granted_by, wrapped_key, key_kind, permission, revision, revoked_at', 'One row per person with access, including the owner'],
        ['login_attempts', 'email, failures, locked_until', 'Rate limiting of failed logins'],
        ['sync_counter', 'id, value', 'Single row holding the global revision counter'],
    ]
    b.append(sec('9', 'Database Design', f"""
<p>The schema has six tables (Fig. 4, Table 7) and is created by a single Alembic migration. Primary keys are UUIDs; item identifiers
are generated by the client, which lets an item be created offline and synchronised later without renumbering.</p>
{diagram(4, 'Entity-relationship diagram. PK, FK and UQ mark primary keys, foreign keys and unique columns.', er_svg())}
{table(7, 'Tables and their columns.', ['Table', 'Columns', 'Notes'], schema_rows, ['15%', '52%', None])}
{sub('9.1', 'Access Control through Grants')}
<p>Access to an item is described entirely by its rows in <code>grants</code>. The owner holds a grant of kind <i>self</i>, in which
the item key is wrapped with the owner's account key; every other user holds a grant of kind <i>box</i>, in which the item key is
encrypted to that user's public key. The <code>permission</code> column records owner, write or read access. A revoked grant is kept
with <code>revoked_at</code> set, so the revocation itself reaches the affected user through synchronisation.</p>
{sub('9.2', 'Commit-ordered Revisions')}
<p>Every change to an item or grant receives a revision number, and clients synchronise by asking for everything newer than the last
revision they have seen. A PostgreSQL sequence is unsuitable for this, because sequence values are allocated before commit: a client
could read revision 11 while revision 10 is still uncommitted and then skip revision 10 forever. Sealed instead increments the single
row in <code>sync_counter</code> inside the writing transaction. The row lock is held until commit, so revisions become visible in
order and a cursor never skips a change; the cost in throughput is negligible at this scale.</p>
{sub('9.3', 'Verification of Stored Data')}
<p>After exercising every feature, the database was queried directly to confirm that it contains no readable secrets (Listing 1).
Users have only an Argon2id hash and 73-byte wrapped keys (1 + 24 + 32 + 16 bytes). Every item is exactly 297 bytes whatever it
contains, and a search for an item title finds nothing. The shared item has a <i>self</i> grant for its owner and a <i>box</i> grant
for the recipient.</p>
<div class="listing"><div class="lcap"><b>Listing 1.</b> Direct inspection of the development database after the walk-through.</div><pre class="out">{text('db.txt')}</pre></div>
"""))

    prim_rows = [
        ['Password stretching', 'Argon2id', 'ops 3, 256 MiB, 16-byte random salt; the client refuses parameters below ops 3, 64 MiB'],
        ['Subkey derivation', 'BLAKE2b KDF', 'context <code>sealedv1</code>; id 1 auth key, id 2 wrap key'],
        ['Encryption', 'XChaCha20-Poly1305', 'random 24-byte nonce; purpose label bound as associated data'],
        ['Sharing', 'X25519 <code>crypto_box</code>', 'authenticated sender; recipient key fetched from the server and pinned'],
        ['Server-side auth hash', 'Argon2id (argon2-cffi)', 't 2, 19 MiB, per-hash salt'],
    ]
    b.append(sec('10', 'Core Logic', f"""
{sub('10.1', 'Key Hierarchy and Primitives')}
<p>Fig. 5 shows how every key is obtained, and Table 8 lists the primitives. The master key is never stored or transmitted. The
auth key and wrap key are derived from it with different identifiers, so the value the server sees cannot be used to decrypt; the
server additionally hashes the auth key with Argon2id, so a stolen hash cannot be replayed as a login. Every ciphertext has the
same layout, <code>version (1 byte) || nonce (24) || ciphertext + tag (16)</code>, and item plaintext is padded to 256-byte blocks
before encryption so that sizes reveal little.</p>
{diagram(5, 'Key hierarchy. Boxes reached from the master password or the recovery key are secret; the server stores the auth-key hash and the encrypted outputs.', KEYS)}
{table(8, 'Cryptographic primitives.', ['Purpose', 'Primitive', 'Parameters'], prim_rows, ['22%', '24%', None])}
<p>Each blob is bound to its purpose and record through the associated data, for example <code>sealed.item.v1:&lt;id&gt;</code>, so a
server that moves a ciphertext to another item or role causes decryption to fail. Sharing uses <code>crypto_box</code> rather than an
anonymous sealed box, so a recipient can verify which user wrapped the key and the server cannot forge a shared item. Because the
server distributes public keys and could substitute its own, the app shows a 30-digit fingerprint that both people can compare and pins
the key on first use; a later change blocks sharing with a warning. Listings 2 and 3 show key derivation and sealing.</p>
{listing(2, 'Deriving the auth and wrap keys (<code>app/lib/core/crypto/sealed_crypto.dart</code>).', derive, 'dart')}
{listing(3, 'Sealing a blob with a purpose label as associated data.', seal, 'dart')}
{sub('10.2', 'Registration, Login and Unlock')}
<p>At registration the client generates a random account key, an X25519 key pair and a 32-byte recovery key; derives the auth and wrap
keys from the master password; wraps the account key twice, under the wrap key and under a key derived from the recovery key; wraps
the private key under the account key; and uploads only the auth key and the wrapped material. Logging in on a new device begins with a
pre-login request for the salt and parameters, after which the client derives the keys, proves the auth key and unwraps the downloaded
keys locally. The wrapped keys are then cached, so later unlocks are a purely local Argon2id derivation that works offline, and a wrong
password simply fails authenticated decryption. After the chosen idle time, or after that long in the background, the keys are wiped
from memory and the vault locks.</p>
{sub('10.3', 'Synchronisation and Conflict Resolution')}
<p>Edits are applied to a local queue of pending changes, encrypted under the account key, and each change records the server revision it
was based on. A sync first pulls everything after the device's cursor, then pushes the queue. The server applies an update only if its
<code>base_revision</code> matches the stored revision (Listing 6); otherwise it responds with <code>409 Conflict</code> and the current
version. The client then decrypts the base, local and remote versions and runs the field-level three-way merge in Listing 4: a field
changed on one side only takes that side's value, a field changed identically on both sides is accepted, and a field changed differently
on both sides is reported as a conflict for the user to settle. A deletion on another device turns unsynced local edits into a new item
rather than discarding them. Listing 5 shows how the server assigns revisions in commit order.</p>
{listing(4, 'Field-level three-way merge (<code>app/lib/core/sync/merge.dart</code>).', merge, 'dart')}
{listing(5, 'Commit-ordered revision numbers (<code>server/app/revisions.py</code>).', revisions, 'python')}
{listing(6, 'Optimistic concurrency on item update (<code>server/app/routers/items.py</code>).', put_item, 'python')}
{sub('10.4', 'Sharing and Revocation')}
<p>To share an item, the owner looks up the recipient's public key, compares fingerprints, and uploads the item key encrypted with
<code>crypto_box</code> from the owner's private key to the recipient's public key, together with the chosen permission. The recipient's
next sync delivers the grant, and the item appears in the recipient's vault. Revocation generates a new item key, re-encrypts the item,
re-wraps the new key for every remaining user and marks the revoked grant, all within one server transaction, so later changes are not
readable by the revoked user.</p>
{sub('10.5', 'Password Change, Recovery and Fingerprint Unlock')}
<p>Because items are protected by the account key rather than by the password directly, a password change derives new keys, re-wraps the
32-byte account key and replaces the auth hash; its cost is the same for an empty vault and a full one, and the server ends every other
session. Recovery verifies the recovery auth key, returns the recovery-wrapped copy of the account key and requires a new master password.
When fingerprint unlock is enabled on Android, a copy of the account key is stored under an AES key in the Android Keystore that demands a
strong biometric for every use and is invalidated when the enrolled fingerprints change. The master password itself is never stored.</p>
{sub('10.6', 'Password Generator and Vault Health')}
<p>The generator produces random passwords from selectable character classes, optionally avoiding look-alike characters, and passphrases
drawn from the EFF large wordlist, each with an entropy estimate. Vault health flags weak passwords using an entropy estimate with
common-password and pattern checks, flags passwords reused across items, and checks breaches with the Have I Been Pwned range API, to which
only the first five hexadecimal characters of each password's SHA-1 hash are sent. The health score is the percentage of logins that are
neither weak, reused nor breached, with each login counted once however many problems it has.</p>
{shots(6, 'Core features in use. (a) Sharing: the recipient\'s security fingerprint and the permission choice. (b) Resolving a conflict after concurrent edits on two devices; only the username needs a decision. (c) Vault health. (d) The password generator.',
       [('share.jpg', 'Share'), ('conflict.jpg', 'Conflict'), ('health.jpg', 'Vault health'), ('gen.jpg', 'Generator')])}
"""))

    cfg_rows = [
        ['<code>SEALED_DATABASE_URL</code>', '<code>postgresql+psycopg:///sealed</code>', 'Database connection string'],
        ['<code>SEALED_SERVER_SECRET</code>', 'development value', 'Key for the stable fake salts returned by pre-login for unknown e-mails; must be set in production'],
        ['<code>SEALED_SESSION_DAYS</code>', '30', 'Session lifetime'],
        ['<code>SEALED_MAX_FAILURES</code>, <code>SEALED_LOCKOUT_MINUTES</code>', '5, 15', 'Login lockout policy'],
        ['<code>SEALED_MIN_KDF_OPS</code>, <code>SEALED_MIN_KDF_MEM</code>', '3, 64 MiB', 'Weakest key derivation parameters accepted at registration'],
        ['<code>SEALED_MAX_BLOB_BYTES</code>', '64 KiB', 'Largest accepted ciphertext'],
        ['<code>SEALED_CORS_ORIGINS</code>', '<code>*</code>', 'Origins allowed to call the API from a browser'],
    ]
    test_rows = [
        ['Server (pytest)', 'FastAPI application on a real PostgreSQL test database', str(p_count)],
        ['Client, host', 'Dart VM: merge, local store, health checks', str(h_count)],
        ['Client, device', 'Android emulator with real libsodium against the live server', str(d_count)],
        ['<b>Total</b>', '', f'<b>{total}</b>'],
    ]
    manual_rows = [
        ['Register, save the recovery key, open the vault', 'Key shown once; empty vault opens', 'Pass'],
        ['Lock, then unlock with the network disabled', 'Unlocks locally; changes are queued', 'Pass'],
        ['Concurrent edits on two devices', 'Website merged automatically; username offered as a choice', 'Pass'],
        ['Share with write permission, edit as the recipient', 'Recipient\'s change appears for the owner', 'Pass'],
        ['Revoke a share', 'Item disappears for the recipient; owner still reads it', 'Pass'],
        ['Change the master password', 'Old password rejected, other sessions ended', 'Pass'],
        ['Recover with the recovery key', 'Vault restored with all items', 'Pass'],
        ['Sign out another device', 'Its token is rejected with 401; the app asks it to sign in again', 'Pass'],
        ['Breach check on <code>password123</code>', 'Reported as seen 2,266,677 times', 'Pass'],
        ['Fingerprint unlock, then cancel the prompt', 'Unlocks by fingerprint; cancelling falls back to the password', 'Pass'],
        ['Web build in Chrome; phone over the public HTTPS address', 'Sign-in and synchronisation work on both', 'Pass'],
    ]
    b.append(sec('11', 'Deployment Details', f"""
{sub('11.1', 'Server')}
<p>The server requires Python 3.13 and PostgreSQL 17. Dependencies are installed into a virtual environment, the schema is created by
Alembic, and the application is served by Uvicorn. The script <code>server/run_dev.sh</code> performs these steps: it starts PostgreSQL
if necessary, applies migrations and serves the API on port 8000. Configuration is read from environment variables with the prefix
<code>SEALED_</code> or from a <code>server/.env</code> file (Table 9).</p>
{table(9, 'Server configuration.', ['Variable', 'Default', 'Meaning'], cfg_rows, ['34%', '22%', None])}
{sub('11.2', 'Web Client')}
<p>The web client is compiled with <code>flutter build web</code> after the libsodium WebAssembly script has been fetched once with
<code>dart run sodium:update_web --sumo</code>. The build contains the compiled fragment shader for the padlock and runs in any modern
browser. When it is served from the same origin as the API, it uses that origin automatically; when opened from <code>localhost</code>,
it talks to <code>http://localhost:8000</code>.</p>
{sub('11.3', 'Android Client')}
<p>The Android application is built with <code>flutter build apk --release</code>. Its default server address is the public demo address
described below, and a different server can be chosen at build time with <code>--dart-define=SEALED_SERVER=&lt;url&gt;</code>, for example
<code>http://10.0.2.2:8000</code> for the emulator. The release build is currently signed with the debug key; a production release would
need a dedicated signing key.</p>
{sub('11.4', 'Demonstration Deployment')}
<p>For the demonstration, a small wrapper, <code>tools/demo_server.py</code>, mounts the built web application next to the API, so a single
process on port 8000 serves both from one origin. The port is published over HTTPS with Tailscale Funnel at a fixed public address, which a physical
phone and any browser can reach. Fig. 7 shows the web client
on a desktop browser, where the welcome screen switches to a two-column layout above 900 pixels. Listing 7 gives the complete sequence of
commands.</p>
<figure><div class="web"><img src="{img('web_welcome.jpg')}"></div><figcaption><b>Fig. 7.</b> The web client in a desktop browser, built from the same code as the Android application.</figcaption></figure>
<div class="listing"><div class="lcap"><b>Listing 7.</b> Building, testing and deploying Sealed.</div><pre>
# server: Python 3.13, PostgreSQL 17
cd server
python3 -m venv .venv &amp;&amp; .venv/bin/pip install -r requirements.txt
createdb sealed
./run_dev.sh                                # migrate and serve the API on :8000

# clients: Flutter 3.44
cd app &amp;&amp; flutter pub get
NIX_SKIP_SODIUM_BUILD_HOOKS=1 dart run sodium:update_web --sumo
flutter build web --release                 # web client in app/build/web
flutter build apk --release                 # Android client

# demonstration: web client and API on one origin, published over HTTPS
cd server &amp;&amp; .venv/bin/uvicorn --app-dir ../tools demo_server:app --port 8000
tailscale funnel --bg 8000

# tests
cd server &amp;&amp; .venv/bin/pytest               # needs a database named sealed_test
cd app &amp;&amp; tool/test.sh                      # host tests, then device tests on an emulator
</pre></div>
{sub('11.5', 'Verification')}
<p>Three automated suites protect the system (Table 10). The server suite covers registration, login, lockout, enumeration resistance,
sessions, password change, recovery, item creation, update and conflict, deletion, the sync cursor, sharing permissions and revocation
with key rotation. Host tests cover the three-way merge, the local store and the health checks. Device tests exercise the real
cryptography, including round trips, tamper detection, wrong keys, the parameter floor, sharing between two users and recovery, and full
synchronisation scenarios against the running server. Each feature was also exercised by hand on the Android emulator, on a physical phone
through the public address and in Chrome (Table 11).</p>
{table(10, 'Automated test suites; all tests pass.', ['Suite', 'Runs against', 'Tests'], test_rows, ['20%', None, '10%'])}
{table(11, 'Manual test scenarios.', ['Scenario', 'Observed result', 'Result'], manual_rows, ['42%', None, '8%'], split=True)}
"""))

    b.append("""
<div class="sec">
<h2>References</h2>
<ol class="refs">
<li>F. Denis et al. <i>libsodium documentation: password hashing, key derivation, AEAD and public-key authenticated encryption.</i> doc.libsodium.org.</li>
<li>A. Biryukov, D. Dinu, D. Khovratovich, S. Josefsson. <i>Argon2 Memory-Hard Function for Password Hashing and Proof-of-Work Applications.</i> RFC 9106, 2021.</li>
<li>Bitwarden Inc. <i>Bitwarden Security Whitepaper.</i> bitwarden.com.</li>
<li>AgileBits Inc. <i>1Password Security Design.</i> 1password.com.</li>
<li>T. Hunt. <i>Pwned Passwords range API (k-anonymity).</i> haveibeenpwned.com/API/v3.</li>
<li>Google. <i>Flutter documentation: Impeller rendering engine and fragment shaders.</i> docs.flutter.dev.</li>
<li>S. Ramírez. <i>FastAPI documentation.</i> fastapi.tiangolo.com; SQLAlchemy 2.0 and PostgreSQL 17 documentation.</li>
<li>Electronic Frontier Foundation. <i>EFF large wordlist for passphrases.</i> eff.org/dice.</li>
</ol>
</div>
""")

    content = '\n'.join(b[1:])
    b.insert(1, index(content, pages or {}))
    doc = (f'<!doctype html><html><head><meta charset="utf-8"><title>Sealed: A Zero-Knowledge Password Manager</title>'
           f'<style>{CSS}</style></head><body>\n' + '\n'.join(b) + '\n</body></html>')
    open(os.path.join(HERE, 'report.html'), 'w').write(doc)
    return content


CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'


def print_pdf(out):
    with tempfile.TemporaryDirectory() as profile:
        subprocess.run([CHROME, '--headless=new', '--disable-gpu', '--no-pdf-header-footer', f'--user-data-dir={profile}',
                        f'--print-to-pdf={out}', 'file://' + os.path.join(HERE, 'report.html')],
                       check=True, capture_output=True)


def heading_pages(pdf, content):
    """Finds the page each heading landed on, searching from page 3 in document order."""
    norm = lambda s: re.sub(r'[^a-z0-9]', '', s.lower())
    text = subprocess.run(['pdftotext', '-layout', pdf, '-'], check=True, capture_output=True, text=True).stdout
    page_lines = [[norm(l) for l in p.split('\n')] for p in text.split('\f')]
    pages, at = {}, 2
    for num, title in re.findall(r'<h[23]>(?:<span class="n">([^<]+)</span>)?([^<]+)</h[23]>', content):
        key = norm(num + title)
        hit = next((i for i in range(at, len(page_lines)) if key in page_lines[i]), None)
        if hit is None:
            raise SystemExit(f'heading not found in PDF: {num} {title}')
        pages[f'{num} {title}'.strip()] = str(hit + 1)
        at = hit
    return pages


if __name__ == '__main__':
    pdf = os.path.join(HERE, 'report.pdf')
    content = build()
    print_pdf(pdf)
    build(heading_pages(pdf, content))
    print_pdf(pdf)
    print('report.pdf written')
