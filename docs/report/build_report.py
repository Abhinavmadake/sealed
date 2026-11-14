"""Builds the Sealed project report: python3 build_report.py, then print report.html to PDF."""
import base64
import html
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
CSS = open(os.path.join(HERE, 'house.css')).read() + r"""
.title-block { margin-bottom: 8px; }
.toc { columns: 2; column-gap: 28px; font-size: 9.6pt; margin: 4px 0 6px; }
.toc div { display: flex; gap: 10px; break-inside: avoid; padding: 2px 0; }
.toc b { font: bold 8.4pt Helvetica, Arial, sans-serif; color: var(--accent); width: 22px; }
.shots img { border-radius: 14px; }
.shots.four { grid-template-columns: repeat(4, 1.32in); justify-content: center; gap: 14px; }
.shots.three { grid-template-columns: repeat(3, 1.5in); }
.web img { width: 100%; border-radius: 6px; border: 1px solid #d9d7e3; display: block; }
.web { background: var(--figbg); border-radius: 6px; padding: 12px; }
.diagram { background: var(--figbg); border-radius: 6px; padding: 14px 10px; text-align: center; }
.diagram svg { width: 100%; height: auto; }
pre.out { font-size: 6.6pt; line-height: 1.38; }
.note { background: var(--wash); border-left: 3px solid var(--accent); padding: 9px 14px; margin: 8px 0 12px; font-size: 9.6pt; }
.note p { margin: 0; }
td.num, th.num { text-align: right; }
.two { display: grid; grid-template-columns: 1fr 1fr; gap: 18px; }
.pass { color: #1f8a4c; font-weight: bold; }
.sec h2, h3 { break-after: avoid; }
table tr:first-child, table tr:nth-child(2) { break-inside: avoid; break-after: avoid; }
.keep { break-inside: avoid; }
"""


def img(name):
    path = os.path.join(HERE, 'figs', name)
    return 'data:image/jpeg;base64,' + base64.b64encode(open(path, 'rb').read()).decode()


def c(s):
    return f'<code>{html.escape(s)}</code>'


DART_KW = set('''import library part as show hide class enum extends implements with mixin abstract final const var
late static void return if else for while do switch case default break continue try catch on finally throw rethrow
new this super null true false async await yield sealed base required get set factory operator is in typedef'''.split())
PY_KW = set('''import from as def class return if elif else for while try except finally raise with pass None True False
and or not in is lambda yield async await'''.split())
TYPES = set('''String int double bool num List Map Set Future Uint8List Float32List SecureKey KdfParams DerivedKeys
SodiumSumo Aead KeyPair Duration DateTime Object dynamic Session MergeResult Exception'''.split())


def highlight(src, lang):
    kw = DART_KW if lang == 'dart' else PY_KW
    comment = r'//[^\n]*' if lang == 'dart' else r'#[^\n]*'
    tok = re.compile(rf"""(?P<c>{comment})|(?P<s>r?'[^'\n]*'|r?"[^"\n]*")|(?P<n>\b\d+(?:\.\d+)?\b)|(?P<a>@\w+)|(?P<w>[A-Za-z_]\w*)|(?P<o>[\s\S])""")
    out = []
    for m in tok.finditer(src):
        k, v = m.lastgroup, m.group()
        e = html.escape(v)
        cls = {'c': 'c', 's': 's', 'n': 'n', 'a': 'f'}.get(k)
        if k == 'w':
            cls = 'k' if v in kw else ('t' if v in TYPES or (lang == 'dart' and v[:1].isupper()) else None)
        out.append(f'<span class="{cls}">{e}</span>' if cls else e)
    return ''.join(out)


def code(label, src, lang):
    lines = highlight(src.rstrip('\n'), lang).split('\n')
    body = '\n'.join(f'<span class="ln">{i:>3}</span>{line}' for i, line in enumerate(lines, 1))
    return f'<div class="code"><div class="clabel">{label}</div><pre>{body}</pre></div>'


def excerpt(rel, start, end):
    """Lines start..end (1-based, inclusive) of a project file."""
    lines = open(os.path.join(ROOT, rel)).read().split('\n')
    return '\n'.join(lines[start - 1:end])


def find(rel, first, last):
    """The block from the line containing `first` to the next line containing `last`."""
    lines = open(os.path.join(ROOT, rel)).read().split('\n')
    a = next(i for i, l in enumerate(lines) if first in l)
    b = next(i for i in range(a, len(lines)) if last in lines[i])
    return '\n'.join(lines[a:b + 1])


def phone(name, cap):
    return f'<div><img src="{img(name)}"><div class="cap">{cap}</div></div>'


def text(name):
    return html.escape(open(os.path.join(HERE, name)).read().rstrip())


def sec(num, title, body, pb=False):
    return f'<div class="sec{" pb" if pb else ""}"><div class="num">{num}</div><div>\n<h2>{title}</h2>\n{body}\n</div></div>'


ARCH = """<svg viewBox="0 0 640 250" xmlns="http://www.w3.org/2000/svg" font-family="Helvetica, Arial, sans-serif">
<defs><marker id="ar" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0 L8,4 L0,8 z" fill="#5e5b72"/></marker></defs>
<g font-size="10.5" fill="#101018">
<rect x="10" y="20" width="250" height="210" rx="10" fill="#fff" stroke="#3b32c4" stroke-width="1.4"/>
<text x="24" y="40" font-weight="bold" fill="#3b32c4" font-size="11">FLUTTER APP (Android, Web)</text>
<rect x="24" y="52" width="222" height="26" rx="5" fill="#f0effb"/><text x="34" y="69">UI screens (Material 3, glass, stipple)</text>
<rect x="24" y="84" width="222" height="26" rx="5" fill="#f0effb"/><text x="34" y="101">VaultService: lock state, auto-lock</text>
<rect x="24" y="116" width="106" height="44" rx="5" fill="#f0effb"/><text x="32" y="134">Crypto layer</text><text x="32" y="149" font-size="9" fill="#5e5b72">libsodium</text>
<rect x="140" y="116" width="106" height="44" rx="5" fill="#f0effb"/><text x="148" y="134">Sync engine</text><text x="148" y="149" font-size="9" fill="#5e5b72">3-way merge</text>
<rect x="24" y="166" width="106" height="44" rx="5" fill="#f0effb"/><text x="32" y="184">Local store</text><text x="32" y="199" font-size="9" fill="#5e5b72">sembast, ciphertext</text>
<rect x="140" y="166" width="106" height="44" rx="5" fill="#f0effb"/><text x="148" y="184">API client</text><text x="148" y="199" font-size="9" fill="#5e5b72">HTTPS + JSON</text>
<rect x="330" y="50" width="160" height="150" rx="10" fill="#fff" stroke="#3b32c4" stroke-width="1.4"/>
<text x="344" y="70" font-weight="bold" fill="#3b32c4" font-size="11">FASTAPI SERVER</text>
<text x="344" y="92">auth, sessions</text><text x="344" y="110">items, sync</text><text x="344" y="128">sharing, revocation</text>
<text x="344" y="146">login lockout</text><text x="344" y="164">Alembic migrations</text>
<text x="344" y="186" font-size="9" fill="#5e5b72">stores ciphertext only</text>
<rect x="540" y="80" width="90" height="90" rx="10" fill="#fff" stroke="#3b32c4" stroke-width="1.4"/>
<text x="552" y="104" font-weight="bold" fill="#3b32c4" font-size="11">POSTGRES</text>
<text x="552" y="124" font-size="9.5">users</text><text x="552" y="138" font-size="9.5">items, grants</text><text x="552" y="152" font-size="9.5">sessions</text>
<line x1="246" y1="188" x2="326" y2="125" stroke="#5e5b72" stroke-width="1.3" marker-end="url(#ar)"/>
<text x="262" y="146" font-size="9" fill="#5e5b72">REST /api/v1</text>
<line x1="490" y1="125" x2="536" y2="125" stroke="#5e5b72" stroke-width="1.3" marker-end="url(#ar)"/>
<text x="488" y="116" font-size="9" fill="#5e5b72">SQLAlchemy</text>
</g></svg>"""

KEYS = """<svg viewBox="0 0 640 300" xmlns="http://www.w3.org/2000/svg" font-family="Helvetica, Arial, sans-serif">
<defs><marker id="k" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0 L8,4 L0,8 z" fill="#5e5b72"/></marker></defs>
<g font-size="10.5" fill="#101018">
<rect x="20" y="16" width="200" height="34" rx="6" fill="#f0effb" stroke="#3b32c4"/><text x="34" y="37">master password + salt</text>
<line x1="120" y1="50" x2="120" y2="78" stroke="#5e5b72" marker-end="url(#k)"/><text x="128" y="68" font-size="9" fill="#5e5b72">Argon2id (ops 3, 256 MiB)</text>
<rect x="20" y="80" width="200" height="34" rx="6" fill="#fff" stroke="#3b32c4"/><text x="34" y="101">master key (never stored or sent)</text>
<line x1="70" y1="114" x2="70" y2="146" stroke="#5e5b72" marker-end="url(#k)"/><line x1="170" y1="114" x2="170" y2="146" stroke="#5e5b72" marker-end="url(#k)"/>
<text x="20" y="134" font-size="9" fill="#5e5b72">KDF id 1</text><text x="178" y="134" font-size="9" fill="#5e5b72">KDF id 2</text>
<rect x="10" y="148" width="110" height="44" rx="6" fill="#fff" stroke="#9c99a8"/><text x="20" y="166">auth key</text><text x="20" y="182" font-size="9" fill="#5e5b72">server keeps its hash</text>
<rect x="130" y="148" width="100" height="44" rx="6" fill="#fff" stroke="#9c99a8"/><text x="140" y="166">wrap key</text><text x="140" y="182" font-size="9" fill="#5e5b72">encrypts account key</text>
<line x1="230" y1="170" x2="296" y2="170" stroke="#5e5b72" marker-end="url(#k)"/>
<rect x="300" y="146" width="150" height="48" rx="6" fill="#f0effb" stroke="#3b32c4"/><text x="312" y="166" font-weight="bold">account key</text><text x="312" y="182" font-size="9" fill="#5e5b72">random, fixed for life</text>
<line x1="375" y1="194" x2="330" y2="232" stroke="#5e5b72" marker-end="url(#k)"/><line x1="375" y1="194" x2="420" y2="232" stroke="#5e5b72" marker-end="url(#k)"/>
<line x1="450" y1="170" x2="506" y2="170" stroke="#5e5b72" marker-end="url(#k)"/>
<rect x="260" y="234" width="130" height="44" rx="6" fill="#fff" stroke="#9c99a8"/><text x="270" y="252">X25519 private key</text><text x="270" y="268" font-size="9" fill="#5e5b72">for sharing</text>
<rect x="400" y="234" width="120" height="44" rx="6" fill="#fff" stroke="#9c99a8"/><text x="410" y="252">item keys</text><text x="410" y="268" font-size="9" fill="#5e5b72">one per item</text>
<rect x="510" y="146" width="120" height="48" rx="6" fill="#fff" stroke="#9c99a8"/><text x="520" y="166">session token</text><text x="520" y="182" font-size="9" fill="#5e5b72">local store only</text>
<line x1="520" y1="256" x2="560" y2="256" stroke="#5e5b72" marker-end="url(#k)"/><text x="566" y="252">item JSON</text><text x="566" y="266" font-size="9" fill="#5e5b72">XChaCha20</text>
<rect x="300" y="16" width="200" height="34" rx="6" fill="#f0effb" stroke="#3b32c4"/><text x="312" y="37">recovery key (shown once)</text>
<line x1="400" y1="50" x2="400" y2="78" stroke="#5e5b72" marker-end="url(#k)"/>
<rect x="300" y="80" width="200" height="34" rx="6" fill="#fff" stroke="#9c99a8"/><text x="312" y="101">recovery auth + recovery wrap</text>
<line x1="400" y1="114" x2="380" y2="144" stroke="#5e5b72" marker-end="url(#k)"/><text x="410" y="134" font-size="9" fill="#5e5b72">second copy</text>
</g></svg>"""


def build():
    def named(f):
        names = {re.sub(r'.*/(test|integration_test)/', '', l.strip()) for l in open(os.path.join(HERE, f))}
        return len({n for n in names if ': ' in n and not re.search(r'setUpAll|tearDownAll', n)})

    d_count = named('devtest.txt')
    h_count = int(re.search(r'\+(\d+): All tests passed', open(os.path.join(HERE, 'hosttest_raw.txt')).read()).group(1))
    p_count = sum(1 for l in open(os.path.join(HERE, 'pytest.txt')) if 'PASSED' in l)

    crypto_core = find('app/lib/core/crypto/sealed_crypto.dart', 'Future<DerivedKeys> deriveFromPassword', 'return DerivedKeys(authBytes, wrap);') + '\n  }'
    seal = find('app/lib/core/crypto/sealed_crypto.dart', 'Uint8List seal(SecureKey key', '  }\n') if False else find('app/lib/core/crypto/sealed_crypto.dart', 'Uint8List seal(SecureKey key', 'return Uint8List.fromList([blobVersion')
    merge = find('app/lib/core/sync/merge.dart', 'MergeResult threeWayMerge(', 'return MergeResult(merged, conflicts);') + '\n}'
    revisions = open(os.path.join(ROOT, 'server/app/revisions.py')).read()
    put_item = find('server/app/routers/items.py', '@router.put("/{item_id}"', 'return view_for(db, item, grant)')

    body = []
    body.append(f"""
<div class="title-block">
<div class="eyebrow">Cross Platform Application Development &nbsp;·&nbsp; <b>Mini Project Report</b></div>
<h1>Sealed: A Zero-Knowledge<br>Password Manager</h1>
<p class="lede">A cross-platform password manager built with Flutter, FastAPI and PostgreSQL, in which every password is
encrypted on the user's device before it is synced, so the server, and anyone who steals its database, only ever holds ciphertext.</p>
<div class="meta">
  <div><div class="k">Name</div><div class="v">Abhinav Madake</div></div>
  <div><div class="k">Roll No.</div><div class="v">231070028</div></div>
  <div><div class="k">Date</div><div class="v">14 November 2026</div></div>
  <div><div class="k">Stack</div><div class="v">Flutter 3.44 · FastAPI · PostgreSQL 17</div></div>
</div>
</div>
<div class="toc">
<div><b>01</b>Abstract</div><div><b>02</b>Introduction</div><div><b>03</b>Objectives and Scope</div>
<div><b>04</b>Tools and Technologies</div><div><b>05</b>System Architecture</div><div><b>06</b>Security Design</div>
<div><b>07</b>Database Design</div><div><b>08</b>API Design</div><div><b>09</b>Implementation</div>
<div><b>10</b>User Interface</div><div><b>11</b>Testing</div><div><b>12</b>Results and Discussion</div>
<div><b>13</b>Limitations and Future Work</div><div><b>14</b>Conclusion</div><div><b>A</b>Selected Source Code</div>
<div><b>B</b>Running the Project</div>
</div>
""")

    body.append(sec('01', 'Abstract', f"""
<div class="aim"><p>Password managers concentrate every secret a person has in one place, which makes their servers attractive
targets. <b>Sealed</b> removes that risk by design: the master password never leaves the device, all items are encrypted with
libsodium (Argon2id, XChaCha20-Poly1305, X25519) before upload, and the server stores and syncs opaque ciphertext. On top of
that guarantee the app offers what a daily-use manager needs: multi-device sync with offline editing and field-level conflict
resolution, sharing with other users and revocation with key rotation, password change without re-encryption, a recovery key,
a password generator, breach and strength checks, remote sign-out and fingerprint unlock. The client is a single Flutter
codebase running on Android and the web; the backend is a FastAPI service over PostgreSQL. The project comprises about 6,700
lines of Dart and 950 lines of Python and passes {p_count + h_count + d_count} automated tests.</p></div>
"""))

    body.append(sec('02', 'Introduction', """
<h3>Problem</h3>
<p>Users reuse weak passwords because strong, unique ones are impossible to remember. Password managers solve this, but a
conventional design that encrypts data on the server, or holds the keys there, turns the server into a single point of
failure: a database leak, a malicious insider or a compelled disclosure exposes every user's credentials.</p>
<h3>Zero-knowledge approach</h3>
<p>In a <i>zero-knowledge</i> design the server is untrusted for confidentiality. All keys are derived or generated on the
client, and the server only receives material it cannot use to decrypt: a hash of an authentication key, encrypted key
blobs, and encrypted item blobs. The server still provides useful services, namely accounts, sessions, sync ordering, sharing
metadata and rate limiting, but a complete dump of its database reveals no password.</p>
<h3>Why cross-platform</h3>
<p>A password manager is only useful if it is available everywhere. Flutter lets one Dart codebase target Android and the
browser, with the cryptographic core shared through the <code>sodium</code> package, which wraps native libsodium on mobile and
its WebAssembly build on the web.</p>
"""))

    body.append(sec('03', 'Objectives and Scope', """
<h3>Objectives</h3>
<ol class="steps">
<li><b>Confidentiality by construction.</b> The server must never hold a key or plaintext that can decrypt a user's vault.</li>
<li><b>Practical multi-device use.</b> Sync across devices, keep working offline, and merge concurrent edits safely.</li>
<li><b>Collaboration.</b> Share an item with another user, read-only or editable, and revoke access with key rotation.</li>
<li><b>Account lifecycle.</b> Change the master password cheaply, recover with a one-time recovery key, sign out remote devices.</li>
<li><b>Password hygiene.</b> Generate strong passwords and passphrases, and flag weak, reused and breached ones.</li>
<li><b>A polished, fast UI</b> on phones and desktop browsers.</li>
</ol>
<h3>In scope</h3>
<p>Register, log in, lock and offline unlock; logins and secure notes; sync with conflict handling; sharing and revocation;
password change; recovery key; generator; vault health; device list; auto-lock and clipboard clearing; fingerprint unlock on Android.</p>
<h3>Out of scope</h3>
<p>Android autofill service and a browser extension (both need platform-native code), file attachments, organisations,
e-mail verification and two-factor login. iOS and macOS share the same code but were not built, because Xcode is not configured on the development machine.</p>
"""))

    body.append(sec('04', 'Tools and Technologies', """
<table>
<tr><th style="width:24%">Component</th><th style="width:28%">Version</th><th>Purpose</th></tr>
<tr><td class="k">Flutter / Dart</td><td>3.44.8 / 3.12.2</td><td>Single UI codebase for Android and web</td></tr>
<tr><td class="k">sodium</td><td>4.0.4 (libsodium 1.0.21)</td><td>Argon2id, BLAKE2b KDF, XChaCha20-Poly1305, X25519 <code>crypto_box</code></td></tr>
<tr><td class="k">sembast, sembast_web</td><td>3.10, 2.4</td><td>Local document store (files on Android, IndexedDB on web)</td></tr>
<tr><td class="k">provider, http, uuid</td><td>6.1, 1.6, 4.6</td><td>State management, REST client, client-side item IDs</td></tr>
<tr><td class="k">flutter_secure_storage, local_auth</td><td>11.2, 3.0</td><td>Android Keystore copy of the account key behind a fingerprint</td></tr>
<tr><td class="k">FastAPI, Uvicorn</td><td>0.121, 0.38</td><td>REST API server</td></tr>
<tr><td class="k">SQLAlchemy, Alembic</td><td>2.0, 1.17</td><td>ORM and schema migrations</td></tr>
<tr><td class="k">PostgreSQL</td><td>17.11</td><td>Database</td></tr>
<tr><td class="k">argon2-cffi, pydantic</td><td>25.1, 2.14</td><td>Server-side hashing of auth keys; request validation</td></tr>
<tr><td class="k">pytest, flutter_test, integration_test</td><td>8.4, SDK</td><td>Server, host and on-device tests</td></tr>
<tr><td class="k">Android emulator</td><td>Pixel, API 36, 1080 × 2400</td><td>Test device; Chrome for the web build</td></tr>
<tr><td class="k">Tailscale Funnel</td><td>1.104</td><td>Fixed public HTTPS address for the phone demo</td></tr>
</table>
"""))

    body.append(sec('05', 'System Architecture', f"""
<figure><div class="diagram">{ARCH}</div>
<figcaption><b>Figure 1.</b> Components. Everything to the left of the network boundary sees plaintext; everything to the right sees only ciphertext.</figcaption></figure>
<p>The client is layered so that cryptography and sync are independent of the UI. <code>VaultService</code> owns the unlocked
state and the session; screens observe it through <code>provider</code>. The <b>crypto layer</b> wraps libsodium behind a small
API (derive, seal, open, wrap, box). The <b>local store</b> persists only ciphertext and harmless metadata, which is what makes
offline unlock possible. The <b>sync engine</b> pulls changes since a revision cursor, then pushes a queue of offline changes,
rebasing them on conflicts.</p>
<table>
<tr><th style="width:26%">Client module</th><th>Responsibility</th></tr>
<tr><td class="k">core/crypto</td><td>Key derivation, AEAD sealing, key wrapping, X25519 sharing, recovery key encoding, fingerprints</td></tr>
<tr><td class="k">core/store</td><td>sembast store for the account record, remote item copies, pending changes and pinned contact keys</td></tr>
<tr><td class="k">core/sync</td><td>Sync engine, field-level three-way merge, repository combining server copies with pending edits</td></tr>
<tr><td class="k">core/api</td><td>Typed REST client, conflict and offline exceptions</td></tr>
<tr><td class="k">core/health</td><td>Entropy-based strength estimate with common-password and pattern checks, Have I Been Pwned range check, generator</td></tr>
<tr><td class="k">core/biometric</td><td>Keystore-protected copy of the account key for fingerprint unlock</td></tr>
<tr><td class="k">services</td><td>Vault session (lock state, auto-lock, sync scheduling), auth flows, sharing</td></tr>
<tr><td class="k">ui</td><td>Screens, theme, glass and stipple widgets</td></tr>
</table>
"""))

    body.append(sec('06', 'Security Design', f"""
<figure><div class="diagram">{KEYS}</div>
<figcaption><b>Figure 2.</b> Key hierarchy. Only the boxes reached through an arrow from the master password or recovery key are secret; the server stores the auth-key hash and the encrypted outputs.</figcaption></figure>
<h3>Primitives</h3>
<table>
<tr><th style="width:28%">Purpose</th><th style="width:30%">Primitive</th><th>Parameters</th></tr>
<tr><td class="k">Password stretching</td><td>Argon2id</td><td>ops 3, 256 MiB, 16-byte random salt; client refuses anything below ops 3, 64 MiB</td></tr>
<tr><td class="k">Subkeys</td><td>BLAKE2b KDF</td><td>context <code>sealedv1</code>, id 1 auth, id 2 wrap</td></tr>
<tr><td class="k">Encryption</td><td>XChaCha20-Poly1305</td><td>random 24-byte nonce, label bound as associated data</td></tr>
<tr><td class="k">Sharing</td><td>X25519 <code>crypto_box</code></td><td>authenticated sender, recipient public key from the server</td></tr>
<tr><td class="k">Server-side auth hash</td><td>Argon2id (argon2-cffi)</td><td>t 2, 19 MiB, per-hash salt</td></tr>
</table>
<p>Every ciphertext uses one format: <code>version (1 byte) ‖ nonce (24) ‖ ciphertext + tag (16)</code>. Item JSON is padded to
256-byte blocks, so every item in the demo vault is exactly 297 bytes on the server whatever it contains.</p>
<h3>Design decisions</h3>
<ul>
<li><b>Separate auth and wrap keys.</b> The server needs proof of the password but must not be able to decrypt, so one derived value cannot do both jobs. The server hashes the auth key again with Argon2id, so a leaked hash cannot be replayed as a login.</li>
<li><b>An account key between password and items.</b> Changing the master password re-wraps a single 32-byte key, so it costs the same for an empty vault and a full one.</li>
<li><b>One key per item.</b> Sharing hands over that item's key and nothing else.</li>
<li><b>Labels as associated data.</b> Each blob is bound to its purpose and item ID (for example <code>sealed.item.v1:&lt;id&gt;</code>), so the server cannot swap ciphertexts between items or roles without decryption failing.</li>
<li><b><code>crypto_box</code>, not sealed boxes.</b> A sealed box is anonymous, so the server could forge a shared item; <code>crypto_box</code> proves which user wrapped the key.</li>
<li><b>Key fingerprints and pinning.</b> The server distributes public keys and could substitute its own. The app shows a 30-digit fingerprint both people can compare, and pins the key on first share; a later change blocks sharing with a warning.</li>
<li><b>KDF floor on the client.</b> A malicious server cannot weaken Argon2 by advertising low parameters during login.</li>
<li><b>Enumeration resistance.</b> Pre-login returns a stable fake salt for unknown e-mails, and failed logins lock the e-mail for 15 minutes after five attempts.</li>
</ul>
"""))

    body.append(sec('07', 'Database Design', """
<table>
<tr><th style="width:18%">Table</th><th style="width:44%">Key columns</th><th>Notes</th></tr>
<tr><td class="k">users</td><td>email, auth_hash, kdf_salt, kdf_ops, kdf_mem, wrapped_account_key, public_key, wrapped_private_key, recovery_auth_hash, recovery_wrapped_key</td><td>Only hashes and encrypted keys</td></tr>
<tr><td class="k">sessions</td><td>user_id, token_hash, device_name, last_seen_at, expires_at</td><td>SHA-256 of the bearer token; 30-day expiry</td></tr>
<tr><td class="k">items</td><td>id (client UUID), owner_id, blob, revision, deleted_at</td><td>Tombstones keep deletions syncable</td></tr>
<tr><td class="k">grants</td><td>item_id, user_id, granted_by, wrapped_key, key_kind (self / box), permission (owner / write / read), revision, revoked_at</td><td>One row per person with access; the owner has a <i>self</i> grant</td></tr>
<tr><td class="k">login_attempts</td><td>email, failures, locked_until</td><td>Rate limiting</td></tr>
<tr><td class="k">sync_counter</td><td>value</td><td>Single row, global revision counter</td></tr>
</table>
<div class="note"><p><b>Why a locked counter row instead of a sequence.</b> Postgres sequence values are handed out before commit,
so a client could read revision 11 while revision 10 is still uncommitted and then skip 10 forever. Incrementing one row
inside the writing transaction holds its lock until commit, so revisions become visible in order and a cursor never skips a
change. The throughput cost is irrelevant at this scale.</p></div>
"""))

    body.append(sec('08', 'API Design', """
<p>All endpoints are under <code>/api/v1</code>, take and return JSON, and carry binary values as base64. Authenticated calls
send <code>Authorization: Bearer &lt;token&gt;</code>.</p>
<table>
<tr><th style="width:36%">Method and path</th><th>Purpose</th></tr>
<tr><td class="k">POST /auth/prelogin</td><td>Salt and KDF parameters for an e-mail (fake but stable for unknown e-mails)</td></tr>
<tr><td class="k">POST /auth/register</td><td>Create an account from client-generated material</td></tr>
<tr><td class="k">POST /auth/login</td><td>Verify the auth key, return a session token and wrapped keys</td></tr>
<tr><td class="k">POST /auth/logout</td><td>End this session</td></tr>
<tr><td class="k">POST /auth/change-password</td><td>Replace salt, auth hash and wrapped account key; end other sessions</td></tr>
<tr><td class="k">POST /auth/recover/start, /finish</td><td>Verify the recovery auth key, return the recovery-wrapped account key, set a new password</td></tr>
<tr><td class="k">GET /sessions, DELETE /sessions/{id}</td><td>List signed-in devices, sign one out</td></tr>
<tr><td class="k">GET /sync?since=N</td><td>Everything changed since revision N, including tombstones and revoked grants</td></tr>
<tr><td class="k">PUT /items/{id}</td><td>Create, or update with <code>base_revision</code>; <code>409</code> with the current version when stale</td></tr>
<tr><td class="k">DELETE /items/{id}</td><td>Tombstone an item (owner only)</td></tr>
<tr><td class="k">GET /users/lookup?email=</td><td>Public key for sharing</td></tr>
<tr><td class="k">GET, POST /items/{id}/grants</td><td>List and add shares</td></tr>
<tr><td class="k">POST /items/{id}/revoke</td><td>Remove a user and rotate the item key for everyone else, in one transaction</td></tr>
</table>
"""))

    body.append(sec('09', 'Implementation', """
<h3>Registration and unlock</h3>
<ol class="steps">
<li><b>Register.</b> The app generates a random account key, an X25519 key pair and a 32-byte recovery key; derives the auth and wrap keys from the master password; wraps the account key twice (password and recovery) and the private key once; and uploads only the auth key and the wrapped material.</li>
<li><b>Log in on a new device.</b> Pre-login returns the salt and parameters; the client derives the keys, proves the auth key, receives the wrapped keys and unwraps them locally.</li>
<li><b>Unlock.</b> The wrapped keys are cached in the local store, so unlock is a purely local Argon2id derivation that works offline. A wrong password simply fails the AEAD check.</li>
<li><b>Auto-lock.</b> After a chosen idle time, or when the app has been in the background that long, the keys are wiped from memory and the vault locks.</li>
</ol>
<h3>Sync and conflict resolution</h3>
<p>Edits are applied to a local <i>pending</i> queue, encrypted under the account key, so the app works offline. Each pending
change keeps the version it was based on. On sync the engine first pulls everything since its cursor, then pushes the queue.
A push with a stale base revision gets <code>409 Conflict</code> with the current server version; the engine decrypts both
sides and runs a field-level <b>three-way merge</b> against the base. Fields changed on only one side merge automatically;
fields changed differently on both sides are marked as conflicts and shown to the user, who picks a side per field. A deletion
on another device turns unsynced local edits into a new item rather than losing them.</p>
<h3>Sharing and revocation</h3>
<p>To share, the owner looks up the recipient's public key, compares fingerprints, and uploads the item key boxed with
<code>crypto_box</code> from the owner's private key to the recipient's public key. Read or write permission is enforced by the
server. Revoking generates a <b>new item key</b>, re-encrypts the item, re-wraps the key for every remaining person and
removes the revoked grant, all in one server transaction, so future changes stay private from the revoked user.</p>
<h3>Password change and recovery</h3>
<p>Because items are protected by the account key, a password change only derives new keys, re-wraps the account key and
replaces the auth hash; the server then ends every other session. Recovery uses the second, recovery-wrapped copy of the
account key, after which the user sets a new master password.</p>
<h3>Fingerprint unlock</h3>
<p>When enabled, a copy of the account key is stored with <code>flutter_secure_storage</code> under an AES key in the Android
Keystore that requires a strong biometric for every use and is invalidated when fingerprints change. The master password is
never stored, and signing in on a new device still requires it.</p>
<h3>Password hygiene</h3>
<p>The generator produces random passwords (configurable classes, look-alike avoidance) and EFF-wordlist passphrases, both with
an entropy readout. Vault health scores weak and reused passwords locally and checks breaches with the Have I Been Pwned range
API: only the first five characters of each SHA-1 hash leave the device.</p>
<h3>Interface and performance</h3>
<p>The UI is dark-only, built on three custom layers: topographic contour lines generated with marching squares over fractal
noise, a stippled padlock drawn as a point cloud that gathers from a ring outside the screen, and frosted "liquid glass"
surfaces for toolbars, lists and dialogs. Flutter's Impeller renderer keeps no raster cache, so static art is drawn once into
images, the point cloud is laid out on a background isolate, and all glass rows on a page share one backdrop blur through a
<code>BackdropGroup</code>. Section 12 gives the measured effect.</p>
""", pb=True))

    body.append(sec('10', 'User Interface', f"""
<figure><div class="shots four">
{phone('welcome.jpg', 'a · Welcome')}
{phone('register.jpg', 'b · Create account')}
{phone('recovery.jpg', 'c · Recovery key')}
{phone('unlock.jpg', 'd · Locked')}
</div><figcaption><b>Figure 3.</b> Onboarding. (a) Welcome screen with the stippled lock over contour lines; it stretches when dragged while the background stays still. (b) Sign-up with a live strength meter. (c) The recovery key, shown once and required to be acknowledged. (d) The lock screen; unlock works offline.</figcaption></figure>

<figure><div class="shots four">
{phone('vault.jpg', 'a · Vault')}
{phone('new.jpg', 'b · New item')}
{phone('search.jpg', 'c · Search')}
{phone('menu.jpg', 'd · Menu')}
</div><figcaption><b>Figure 4.</b> Home. (a) Items on grouped glass rows with filter tabs that also respond to sideways swipes. (b) The New dialog. (c) The toolbar capsule expanded into a search field. (d) The capsule morphed into the menu.</figcaption></figure>

<figure><div class="shots four">
{phone('detail.jpg', 'a · Item')}
{phone('edit.jpg', 'b · Edit')}
{phone('share.jpg', 'c · Share')}
{phone('empty.jpg', 'd · Empty vault')}
</div><figcaption><b>Figure 5.</b> Items. (a) Detail with copy buttons and strength bar; copied secrets are cleared from the clipboard after 30 seconds. (b) Editing with the generator button. (c) Sharing: the recipient's security fingerprint and permission choice. (d) A new, empty vault.</figcaption></figure>

<figure><div class="shots four">
{phone('conflict_banner.jpg', 'a · Conflict found')}
{phone('conflict.jpg', 'b · Resolve')}
{phone('health.jpg', 'c · Vault health')}
{phone('gen.jpg', 'd · Generator')}
</div><figcaption><b>Figure 6.</b> (a) After an offline edit on the phone and a concurrent edit from another client, sync reports a conflict. (b) Only the username needs a choice; the website change was merged automatically. (c) Breach, weak and reused passwords. (d) The password generator.</figcaption></figure>

<figure><div class="shots four">
{phone('gen2.jpg', 'a · Passphrase')}
{phone('settings.jpg', 'b · Settings')}
{phone('devices.jpg', 'c · Devices')}
{phone('changepw.jpg', 'd · Change password')}
</div><figcaption><b>Figure 7.</b> (a) Passphrase mode. (b) Settings grouped into Account, Security and About, including the security fingerprint, auto-lock and clipboard timers. (c) Signed-in devices with remote sign-out. (d) Master password change.</figcaption></figure>

<figure><div class="web"><img src="{img('web_welcome.jpg')}"></div>
<figcaption><b>Figure 8.</b> The same code running as a web app in Chrome, using a two-column layout above 900 px.</figcaption></figure>
<figure><div class="web"><img src="{img('web_vault.jpg')}"></div>
<figcaption><b>Figure 9.</b> The vault on the web, with the list in a centred column and the same glass toolbar.</figcaption></figure>
""", pb=True))

    body.append(sec('11', 'Testing', f"""
<table>
<tr><th style="width:28%">Suite</th><th style="width:34%">Runs against</th><th class="num">Tests</th><th class="num">Result</th></tr>
<tr><td class="k">Server (pytest)</td><td>FastAPI app on a real Postgres test database</td><td class="num">{p_count}</td><td class="num pass">all pass</td></tr>
<tr><td class="k">App host tests</td><td>Dart VM, no native code</td><td class="num">{h_count}</td><td class="num pass">all pass</td></tr>
<tr><td class="k">App device tests</td><td>Android emulator, real libsodium, live server</td><td class="num">{d_count}</td><td class="num pass">all pass</td></tr>
<tr><td class="k">Total</td><td></td><td class="num"><b>{p_count + h_count + d_count}</b></td><td></td></tr>
</table>
<p>The server suite covers registration, login, lockout, enumeration resistance, sessions, password change, recovery, item
create, update and conflict, deletion, the sync cursor, sharing permissions and revocation with rotation. Host tests cover the
three-way merge, the local store and the health checks. Device tests exercise the real cryptography (round trips, tamper
detection, wrong keys, the KDF floor, sharing between two users, recovery, base32) and full sync scenarios against the running
server, including offline edits, conflicts and revocation.</p>
<h3>Database inspection</h3>
<p>After the UI walk-through, the database was queried directly to confirm that it holds no readable secrets:</p>
<pre class="out">{text('db.txt')}</pre>
<p>Users have only an Argon2id hash and 73-byte wrapped keys (1 + 24 + 32 + 16 bytes). Every item is 297 bytes whatever it
contains, and a search for an item title finds nothing. The shared GitHub item has an owner <i>self</i> grant and a
<i>box</i> grant for bob.</p>
<h3>Manual test results</h3>
<table>
<tr><th style="width:5%">#</th><th style="width:42%">Scenario</th><th style="width:42%">Observed</th><th>Result</th></tr>
<tr><td>1</td><td>Register, save recovery key, open vault</td><td>Key shown once; vault opens empty (Fig. 3, 5d)</td><td class="ok">Pass</td></tr>
<tr><td>2</td><td>Lock, then unlock with the network off</td><td>Unlocks locally; changes queue with a badge</td><td class="ok">Pass</td></tr>
<tr><td>3</td><td>Concurrent edits on two devices</td><td>Website merged, username offered as a choice (Fig. 6a, 6b)</td><td class="ok">Pass</td></tr>
<tr><td>4</td><td>Share with edit rights, edit as recipient</td><td>Recipient's change appears for the owner</td><td class="ok">Pass</td></tr>
<tr><td>5</td><td>Revoke a share</td><td>Recipient's vault no longer lists the item; owner still reads it</td><td class="ok">Pass</td></tr>
<tr><td>6</td><td>Change master password</td><td>Old password rejected, other sessions ended, new one unlocks</td><td class="ok">Pass</td></tr>
<tr><td>7</td><td>Recover with the recovery key</td><td>Vault restored with all items</td><td class="ok">Pass</td></tr>
<tr><td>8</td><td>Sign out another device</td><td>Its token returns 401; the app shows a re-sign-in banner</td><td class="ok">Pass</td></tr>
<tr><td>9</td><td>Breach check on <code>password123</code></td><td>Reported as seen 2,266,677 times (Fig. 6c)</td><td class="ok">Pass</td></tr>
<tr><td>10</td><td>Fingerprint unlock, then cancel</td><td>Unlocks by fingerprint; cancel falls back to the password</td><td class="ok">Pass</td></tr>
<tr><td>11</td><td>Web build in Chrome, phone over a public HTTPS tunnel</td><td>Sign-in and sync work on both</td><td class="ok">Pass</td></tr>
</table>
""", pb=True))

    body.append(sec('12', 'Results and Discussion', """
<p>All objectives in section 3 were met and every feature was verified on the Android emulator, on a physical Android phone
through a public HTTPS address, and in Chrome. The zero-knowledge property holds in practice: the database contains only
hashes, wrapped keys and fixed-size ciphertext.</p>
<h3>Rendering performance</h3>
<p>The first version of the animated welcome screen stuttered. Frame timings measured on the emulator with host GPU rendering
showed why: Impeller redrew thousands of contour segments, the grain and about 80,000 dots on every frame. After caching
static art as images, laying out the point cloud off the UI thread, freezing the settled lock and removing live blur over moving
content, the results were:</p>
<table>
<tr><th style="width:44%">Measure (welcome animation, 3 runs)</th><th class="num">Before</th><th class="num">After</th></tr>
<tr><td class="k">Frame rate</td><td class="num">about 30 fps</td><td class="num">60 fps</td></tr>
<tr><td class="k">Frames over 20 ms</td><td class="num">98 %</td><td class="num">1 to 2 per run</td></tr>
<tr><td class="k">GPU raster time per frame (median)</td><td class="num">36 ms</td><td class="num">16.5 ms</td></tr>
</table>
<p>Across unlock, eight tab swipes, the morphing menu and search, 891 frames were recorded with a median raster time of 3.4 ms,
helped by the shared backdrop blur for glass list rows.</p>
<h3>Cost of key derivation</h3>
<p>Argon2id with 256 MiB takes about one second on the emulator; this is deliberate, as it is what makes offline guessing of
the master password expensive. Password change costs two derivations regardless of vault size, because only the account key is
re-wrapped.</p>
"""))

    body.append(sec('13', 'Limitations and Future Work', """
<h3>Known limitations</h3>
<ul>
<li>Metadata is visible to the server: e-mail addresses, timestamps, item counts and sizes, and who shares with whom.</li>
<li>The server could replay an older version of an item (rollback); clients do not yet detect this.</li>
<li>A revoked user keeps anything already seen; rotation protects only future changes.</li>
<li>Read-only sharing is enforced by the server, not cryptographically.</li>
<li>A compromised device or modified client defeats any client-side scheme.</li>
<li>Forgetting both the master password and the recovery key loses the vault; that is the price of zero knowledge.</li>
<li>Dart cannot reliably wipe strings, so decrypted text may linger in memory until collected.</li>
<li>With fingerprint unlock enabled, the device's Keystore becomes part of the trust base.</li>
</ul>
<h3>Future work</h3>
<ul>
<li>Android autofill service and a browser extension.</li>
<li>Signed, versioned vault manifests to detect rollback.</li>
<li>TOTP codes, file attachments and organisations.</li>
<li>iOS and macOS builds; a production deployment with HTTPS and a release signing key.</li>
</ul>
"""))

    body.append(sec('14', 'Conclusion', """
<p>Sealed shows that a password manager can be both genuinely zero-knowledge and pleasant to use. Careful key hierarchy design,
with separate auth and wrap keys, an account key in the middle and a key per item, makes password changes cheap and sharing
precise, while binding every ciphertext to its purpose stops a hostile server from rearranging data. A revision counter that
respects commit order and a field-level three-way merge make offline editing on several devices safe.</p>
<p>Flutter allowed one codebase to deliver the same encrypted vault on Android and in the browser, from the libsodium core up to
a custom visual design, and its measured performance after optimisation is a steady 60 frames per second. The backend stays
small and auditable because it never needs to understand the data it stores.</p>
<h3>References</h3>
<ol class="steps">
<li>libsodium documentation, Password hashing, Key derivation, AEAD and Public-key authenticated encryption. doc.libsodium.org</li>
<li>A. Biryukov, D. Dinu, D. Khovratovich. <i>Argon2: the memory-hard function for password hashing.</i> RFC 9106, 2021.</li>
<li>Bitwarden Security Whitepaper; 1Password Security Design. Reference designs for client-side vault encryption.</li>
<li>Have I Been Pwned, Pwned Passwords range API (k-anonymity). haveibeenpwned.com/API/v3</li>
<li>Flutter documentation: Impeller rendering engine; BackdropFilter and BackdropGroup. docs.flutter.dev</li>
<li>FastAPI, SQLAlchemy 2.0 and PostgreSQL 17 documentation.</li>
<li>EFF Large Wordlist for passphrases. eff.org/dice</li>
</ol>
"""))

    body.append(sec('A', 'Selected Source Code', f"""
<p>The complete source (about 9,400 lines including tests) is in the project repository. These excerpts show the parts that
carry the security and sync guarantees.</p>
{code('app/lib/core/crypto/sealed_crypto.dart · deriving the auth and wrap keys', crypto_core, 'dart')}
{code('app/lib/core/crypto/sealed_crypto.dart · sealing a blob', seal, 'dart')}
{code('app/lib/core/sync/merge.dart · field-level three-way merge', merge, 'dart')}
{code('server/app/revisions.py · commit-ordered revisions', revisions, 'python')}
{code('server/app/routers/items.py · optimistic concurrency on update', put_item, 'python')}
""", pb=True))

    body.append(sec('B', 'Running the Project', """
<pre>
# server: Python 3.13 and PostgreSQL 17
cd server
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
/opt/homebrew/opt/postgresql@17/bin/createdb sealed
./run_dev.sh                         # migrates and serves on http://127.0.0.1:8000

# app: Flutter 3.44
cd app
flutter pub get
flutter run                          # Android emulator
flutter run -d chrome                # web

# tests
cd server && .venv/bin/pytest        # 41 tests, needs database sealed_test
cd app && tool/test.sh               # host tests, then device tests on an emulator

# phone demo: website and API on one origin, published over HTTPS
cd server && .venv/bin/uvicorn --app-dir ../tools demo_server:app --port 8000
tailscale funnel --bg 8000
</pre>
<div class="foot"><span>Cross Platform Application Development · Mini Project · Sealed</span><span>Abhinav Madake · 231070028</span></div>
"""))

    doc = f'<!doctype html><html><head><meta charset="utf-8"><title>Sealed Project Report</title><style>{CSS}</style></head><body>\n' + '\n'.join(body) + '\n</body></html>'
    open(os.path.join(HERE, 'report.html'), 'w').write(doc)
    print('report.html', len(doc) // 1024, 'KB')


if __name__ == '__main__':
    build()
