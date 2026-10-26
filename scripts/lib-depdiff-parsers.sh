#!/usr/bin/env bash
# Manifest parsers and the ADR name matcher for diff-dependencies.sh, sourced,
# never run. Kept apart so the script stays a readable flow and each format is
# one function.
#
# Contract of every depdiff_names_<format> function: the manifest's content on
# stdin; on success, its runtime dependency names on stdout, one per line, and
# status 0; on a shape the rules below do not cover, one line saying why — the
# line that broke it quoted — on stdout and status 1: the caller lists the
# manifest under `unparsed` and takes none of its names. A parser never
# guesses: an unknown shape is a refusal.
#
# Only bash, jq and POSIX awk (no gawk extension, no octal escape: the CI
# runner's awk is not gawk); a single quote reaches awk as the variable `sq`.

# shellcheck disable=SC2016 # the awk programs below are single-quoted on purpose

# Shared awk for the TOML manifests: trimming, the first key of a
# `key = value` line, a table header's name, and the bracket depth a value
# leaves open — strings and comments skipped, so a `]` inside a string or a
# header-looking line inside a multi-line value is never misread.
DEPDIFF_AWK_TOML='
  function fail(msg) { print FILE " line " NR ": " msg; bad = 1; exit 1 }
  function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
  function unquote(s) { s = trim(s); gsub("^[\"" sq "]|[\"" sq "]$", "", s); return s }
  function triples(s) { return gsub("\"\"\"|" sq sq sq, "&", s) }
  function tomlkey(t,   k, q) {
    q = substr(t, 1, 1)
    if (q == "\"" || q == sq) { k = substr(t, 2); return substr(k, 1, index(k, q) - 1) }
    k = t; sub(/[^A-Za-z0-9_-].*$/, "", k); return k
  }
  function header(t,   h) {
    h = substr(t, 2); sub(/^[[:space:]]+/, "", h)
    if (h !~ /\][[:space:]]*(#.*)?$/) fail("unclosed table header: " line)
    sub(/[[:space:]]*\][[:space:]]*(#.*)?$/, "", h); return h
  }
  function depth_of(s,   i, c, d, q) {
    d = 0; q = ""
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (q != "") { if (c == "\\" && q == "\"") i++; else if (c == q) q = ""; continue }
      if (c == "#") break
      if (c == "\"" || c == sq) q = c
      else if (c == "[" || c == "{") d++
      else if (c == "]" || c == "}") d--
    }
    return d
  }
  # nocomment: the text before a # that is not inside a string.
  function nocomment(s,   i, c, q) {
    q = ""
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (q != "") { if (c == "\\" && q == "\"") i++; else if (c == q) q = ""; continue }
      if (c == "#") return substr(s, 1, i - 1)
      if (c == "\"" || c == sq) q = c
    }
    return s
  }
  { line = $0; sub(/\r$/, "", line); t = trim(line) }
'

# A PEP 508 requirement's name: cut at the first of `<>=!~;[ (@`, lower-cased,
# because pip compares names case-insensitively; "" when what is left is not
# a distribution name.
DEPDIFF_AWK_PYNAME='
  function pyname(r,   n) {
    n = r; sub(/^[[:space:]]+/, "", n)
    gsub(/\[/, "(", n)
    sub(/[<>=!~;(@[:space:]].*$/, "", n)
    n = tolower(n)
    if (n !~ /^[a-z0-9]([a-z0-9._-]*[a-z0-9])?$/) return ""
    return n
  }
'

# The names a JSON manifest lists, one per output line, refused whole when one
# holds a control character: a tab or a newline inside a key would split into
# forged fields or names once the caller reads the list line by line.
DEPDIFF_JQ_PLAIN='
  def depdiff_plain($m):
    if any(.[]; test("[\u0000-\u001f]")) then error($m + ": a dependency name holds a control character")
    else .[] end;
'

# package.json: keys of dependencies and optionalDependencies — what an install
# without --dev pulls in. devDependencies and peerDependencies are left out:
# the first never ships, the second is the consumer's choice.
depdiff_names_npm() {
  jq -r -s "$DEPDIFF_JQ_PLAIN"'
    if length != 1 or (.[0] | type) != "object" then error("package.json is not one JSON object")
    else [(.[0].dependencies // {}), (.[0].optionalDependencies // {})]
      | if all(type == "object") then add | keys | depdiff_plain("package.json")
        else error("package.json: dependencies or optionalDependencies is not an object") end
    end' 2>&1
}

# composer.json: keys of require. Platform requirements — php, ext-*, lib-*,
# composer-*-api — are the only names without a vendor/ prefix, so a key with
# no slash is never a package. require-dev never reaches production.
depdiff_names_composer() {
  jq -r -s "$DEPDIFF_JQ_PLAIN"'
    if length != 1 or (.[0] | type) != "object" then error("composer.json is not one JSON object")
    else (.[0].require // {})
      | if type == "object" then keys | depdiff_plain("composer.json") | select(contains("/"))
        else error("composer.json: require is not an object") end
    end' 2>&1
}

# go.mod: `require <module> <version>` lines and `require ( … )` blocks. A line
# marked `// indirect` is a transitive requirement Go records for the build
# list, not a choice the project made.
depdiff_names_go() {
  awk '
    function fail(msg) { print "go.mod line " NR ": " msg; bad = 1; exit 1 }
    function take(t,   f, n, mod) {
      if (t ~ /\/\/[[:space:]]*indirect[[:space:]]*(;.*)?$/) return
      sub(/[[:space:]]*\/\/.*$/, "", t)
      n = split(t, f, /[[:space:]]+/)
      if (n != 2) fail("not <module> <version>: " line)
      mod = f[1]; gsub(/^["`]|["`]$/, "", mod)
      if (mod == "") fail("empty module path: " line)
      names[mod] = 1
    }
    { line = $0; sub(/\r$/, "", line); t = line; sub(/^[[:space:]]+/, "", t); sub(/[[:space:]]+$/, "", t) }
    inblock {
      if (t ~ /^\)/) { inblock = 0; next }
      if (t == "" || t ~ /^\/\//) next
      take(t); next
    }
    t ~ /^require[[:space:]]*\([[:space:]]*(\/\/.*)?$/ { inblock = 1; opened = NR; next }
    t ~ /^require[[:space:]]/ { sub(/^require[[:space:]]+/, "", t); take(t); next }
    END {
      if (bad) exit 1
      if (inblock) { print "go.mod line " opened ": the require block opened here is never closed"; exit 1 }
      for (m in names) print m
    }'
}

# Cargo.toml: keys of [dependencies] and [target.<cfg>.dependencies], in both
# the `name = "1"` and the `name = { … }` form — the inline table may span
# lines, as TOML allows for the arrays inside it — and the
# [dependencies.<name>] table form. A dependency renamed with
# `package = "<crate>"` is reported by its crate, the name a registry and an
# ADR know it by. [dev-dependencies], [build-dependencies] and their target
# variants never reach the built artifact's dependency list.
depdiff_names_cargo() {
  awk -v sq="'" -v FILE=Cargo.toml "$DEPDIFF_AWK_TOML"'
    # bare: v with every character inside a string turned to "_", the quotes
    # kept, so a key is looked for only where a key can be and its position
    # still points into v.
    function bare(v,   i, c, q, out) {
      q = ""; out = ""
      for (i = 1; i <= length(v); i++) {
        c = substr(v, i, 1)
        if (q != "") {
          if (c == "\\" && q == "\"") { out = out "__"; i++; continue }
          if (c == q) q = ""; else c = "_"
        } else if (c == "\"" || c == sq) q = c
        out = out c
      }
      return out
    }
    # pkgof: the crate a `package = "…"` key inside an inline table names, or "".
    function pkgof(v,   r, q) {
      if (!match(bare(v), "(^|[{,[:space:]])package[[:space:]]*=[[:space:]]*[\"" sq "]")) return ""
      r = substr(v, RSTART + RLENGTH); q = substr(v, RSTART + RLENGTH - 1, 1)
      if (index(r, q) <= 1) return ""
      return substr(r, 1, index(r, q) - 1)
    }
    function take(k, v,   p) { p = pkgof(v); names[p != "" ? p : k] = 1 }
    # An inline table still open: its lines are part of one value.
    pend {
      pv = pv " " nocomment(t); pd += depth_of(t)
      if (triples(t) % 2 == 1) fail("multi-line string inside an inline table: " line)
      if (pd <= 0) { pend = 0; take(pk, pv) }
      next
    }
    # A multi-line string is opaque: nothing inside it is a header or a key.
    inml { if (triples(t) % 2 == 1) inml = 0; next }
    t ~ /^\[\[/ { indeps = 0; tbl = ""; next }
    t ~ /^\[/ {
      h = header(t)
      indeps = (h == "dependencies" || h ~ /^target\..+\.dependencies$/)
      tbl = ""
      if (h ~ /^dependencies\./ || h ~ /^target\..+\.dependencies\./) {
        n = h; sub(/^.*dependencies\./, "", n); n = unquote(n)
        if (n == "" || n ~ /\./) fail("unreadable dependency table: " line)
        names[n] = 1; tbl = n
      }
      next
    }
    # Inside a [dependencies.<name>] table, `package` renames it to its crate.
    tbl != "" && tomlkey(t) == "package" && t ~ /=/ {
      v = t; sub(/^[^=]*=[[:space:]]*/, "", v); sub(/[[:space:]]*#.*$/, "", v)
      p = unquote(v)
      if (p == "") fail("unreadable package key: " line)
      delete names[tbl]; names[p] = 1; next
    }
    !indeps { if (triples(t) % 2 == 1) inml = 1; next }
    t == "" || t ~ /^#/ { next }
    {
      k = tomlkey(t)
      if (k == "" || t !~ /=[[:space:]]*[^[:space:]]/) fail("not a key = value line: " line)
      v = t; sub(/^[^=]*=[[:space:]]*/, "", v)
      if (triples(v) % 2 == 1) fail("multi-line string as a dependency value: " line)
      d = depth_of(v)
      if (d < 0) fail("a bracket closed that was never opened: " line)
      if (d > 0) { pend = 1; pk = k; pv = nocomment(v); pd = d; pnr = NR; pline = line; next }
      take(k, nocomment(v))
    }
    END {
      if (bad) exit 1
      if (pend) { print FILE " line " pnr ": an inline table opened here is never closed: " pline; exit 1 }
      for (n in names) print n
    }'
}

# pyproject.toml: the strings of the [project] `dependencies = [ … ]` array, on
# one line or many, and the keys of [tool.poetry.dependencies] except python
# (the interpreter, not a package). [project.optional-dependencies] and the
# poetry dev groups are extras and dev tooling, never installed by default.
depdiff_names_pyproject() {
  awk -v sq="'" -v FILE=pyproject.toml "$DEPDIFF_AWK_TOML$DEPDIFF_AWK_PYNAME"'
    function addreq(r,   n) {
      n = pyname(r)
      if (n == "") fail("unreadable requirement \"" r "\": " line)
      names[n] = 1
    }
    # collect: the requirement strings at depth 1 of the dependencies array;
    # the array may span lines, a string may not (TOML basic strings do not).
    function collect(s,   i, c, q, cur) {
      q = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q != "") {
          if (c == "\\" && q == "\"") { cur = cur substr(s, i + 1, 1); i++; continue }
          if (c == q) { q = ""; if (adepth == 1) addreq(cur); continue }
          cur = cur c; continue
        }
        if (c == "#") return
        if (c == "\"" || c == sq) {
          if (substr(s, i, 3) == c c c) fail("multi-line string in the dependencies array: " line)
          q = c; cur = ""; continue
        }
        if (c == "[") adepth++
        else if (c == "{") fail("a table inside the dependencies array: " line)
        else if (c == "]") {
          adepth--
          if (adepth == 0) {
            inarr = 0
            if (trim(substr(s, i + 1)) !~ /^(#.*)?$/) fail("text after the dependencies array: " line)
            return
          }
        }
      }
      if (q != "") fail("string not closed on its line: " line)
    }
    inml { if (triples(t) % 2 == 1) inml = 0; next }
    inarr { collect(t); next }
    pend > 0 { pend += depth_of(t); next }
    t == "" || t ~ /^#/ { next }
    t ~ /^\[\[/ { sect = ""; next }
    t ~ /^\[/ { sect = header(t); next }
    {
      k = tomlkey(t)
      watched = (sect == "project" || sect == "tool.poetry.dependencies")
      if (k == "" || t !~ /=/) { if (watched) fail("not a key = value line: " line); next }
      v = t; sub(/^[^=]*=[[:space:]]*/, "", v)
      if (sect == "project" && k == "dependencies") {
        if (v !~ /^\[/) fail("[project] dependencies is not an array: " line)
        inarr = 1; adepth = 0; opened = NR; openline = line
        collect(v); next
      }
      if (sect == "tool.poetry.dependencies" && tolower(k) != "python") names[tolower(k)] = 1
      if (triples(v) % 2 == 1) { inml = 1; next }
      d = depth_of(v)
      if (d > 0) { pend = d; pendnr = NR; pendline = line }
    }
    END {
      if (bad) exit 1
      if (inarr) { print FILE " line " opened ": the dependencies array is never closed: " openline; exit 1 }
      if (pend > 0) { print FILE " line " pendnr ": a value opened here is never closed: " pendline; exit 1 }
      if (inml) { print FILE ": a multi-line string is never closed"; exit 1 }
      for (n in names) print n
    }'
}

# requirements.txt: one requirement per line. Options (-r, -e, -c, --index-url
# …), URLs, VCS links and local paths are not names a registry resolves, so
# they are skipped; a named direct reference (`name @ url`) keeps its name.
depdiff_names_requirements() {
  awk -v sq="'" "$DEPDIFF_AWK_PYNAME"'
    function fail(msg) { print "requirements.txt line " NR ": " msg; bad = 1; exit 1 }
    { line = $0; sub(/\r$/, "", line) }
    line ~ /\\$/ { cont = cont substr(line, 1, length(line) - 1); next }
    {
      t = cont line; cont = ""
      sub(/(^|[[:space:]])#.*$/, "", t); sub(/^[[:space:]]+/, "", t); sub(/[[:space:]]+$/, "", t)
      if (t == "" || t ~ /^-/) next
      named = (t ~ /^[A-Za-z0-9][A-Za-z0-9._-]*[[:space:]]*(\[[^]]*\])?[[:space:]]*@/)
      if (!named && (t ~ /:\/\// || t ~ /^(git|hg|svn|bzr)\+/ || t ~ /^[.\/~]/ || t ~ /\.(whl|zip|tgz|tar\.gz|tar\.bz2)$/)) next
      n = pyname(t)
      if (n == "") fail("not a requirement: " line)
      names[n] = 1
    }
    END {
      if (bad) exit 1
      for (n in names) print n
    }'
}

# Gemfile: `gem "name"` lines, except inside a `group … do` block whose groups
# are all :development or :test, or with an inline `group:`/`groups:` option
# naming only those — `bundle install --without development test` skips them.
# A gem in :production, or in any other group, ships. Every `do`, `if`,
# `unless`, `case`, `begin`, `def` opens a block that `end` closes, so a group
# is known to end where its block does.
depdiff_names_gemfile() {
  awk -v sq="'" '
    function fail(msg) { print "Gemfile line " NR ": " msg; bad = 1; exit 1 }
    function devonly(s,   n, p, i, cnt) {
      gsub(/[][()]/, " ", s)
      n = split(s, p, /[[:space:],]+/)
      cnt = 0
      for (i = 1; i <= n; i++) {
        if (p[i] == "") continue
        sub(/^:/, "", p[i]); gsub("[\"" sq "]", "", p[i])
        if (p[i] != "development" && p[i] != "test") return 0
        cnt++
      }
      return cnt > 0
    }
    function push_block(isdev) { depth++; dev[depth] = isdev; devdepth += isdev; opened[depth] = NR }
    # semicolon: is there a ; outside a string literal on the line?
    function semicolon(s,   i, c, q) {
      q = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q != "") { if (c == "\\") i++; else if (c == q) q = ""; continue }
        if (c == "\"" || c == sq) q = c
        else if (c == ";") return 1
      }
      return 0
    }
    {
      line = $0; sub(/\r$/, "", line); t = line; sub(/^[[:space:]]+/, "", t)
      if (t ~ /^#/) next
      sub(/[[:space:]]+#.*$/, "", t); sub(/[[:space:]]+$/, "", t)
      # Two statements on one line would be read as the first alone: refused.
      if (semicolon(t)) fail("more than one statement on a line: " line)
      # A trailing comma continues the call on the next line — a group header
      # or a gem option list split across lines is still one statement.
      if (t ~ /,$/) { cont = cont t " "; if (!contnr) contnr = NR; t = "" }
      else if (cont != "" && t != "") { t = cont t; cont = ""; contnr = 0 }
    }
    t == "" { next }
    t ~ /^end([[:space:];.]|$)/ {
      if (depth == 0) fail("end without an open block: " line)
      devdepth -= dev[depth]; depth--; next
    }
    t ~ /^group([[:space:]]|\()/ && t ~ /[[:space:]]do([[:space:]]*\|[^|]*\|)?$/ {
      g = t; sub(/^group[[:space:]]*/, "", g); sub(/[[:space:]]*do([[:space:]]*\|[^|]*\|)?$/, "", g)
      gsub(/[a-z_]+:[[:space:]]*[a-z_]+/, "", g)
      push_block(devonly(g)); next
    }
    t ~ /^gem([[:space:]]|\()/ {
      r = t; sub(/^gem[[:space:]]*\(?[[:space:]]*/, "", r)
      q = substr(r, 1, 1)
      if (q != "\"" && q != sq) fail("a gem with no literal name: " line)
      name = substr(r, 2)
      if (index(name, q) <= 1) fail("unreadable gem name: " line)
      name = substr(name, 1, index(name, q) - 1)
      inline = 0
      if (match(r, /(groups?:|:groups?[[:space:]]*=>)[[:space:]]*/)) {
        g = substr(r, RSTART + RLENGTH)
        if (g ~ /^\[/) g = substr(g, 1, index(g, "]")); else sub(/,.*$/, "", g)
        inline = devonly(g)
      }
      if (devdepth == 0 && !inline) names[name] = 1
      next
    }
    t ~ /^(if|unless|case|begin|while|until|def|class|module)([[:space:](]|$)/ && t !~ /[[:space:];]end$/ { push_block(0); next }
    t ~ /[[:space:]]do([[:space:]]*\|[^|]*\|)?$/ { push_block(0); next }
    END {
      if (bad) exit 1
      if (depth > 0) { print "Gemfile line " opened[depth] ": a block opened here is never closed"; exit 1 }
      if (cont != "") { print "Gemfile line " contnr ": a statement continued here never ends"; exit 1 }
      for (n in names) print n
    }'
}

# depdiff_covering <names-file> — of the names in the file (one per line), those the ADR text on
# stdin names whole, case-insensitive. A name is matched literally with
# index(), never turned into a regex: it is input. Whole means no name
# character [A-Za-z0-9_./@-] touches it on either side, so react-dom does not
# cover react, nor @scope/pkg-extra @scope/pkg, nor @scope/pkg a bare pkg; a
# period followed by a non-name character ends a sentence and still counts.
depdiff_covering() {
  LC_ALL=C awk '
    function namechar(c) { return c != "" && c ~ "[A-Za-z0-9_./@-]" }
    FNR == NR { list[++n] = $0; next }
    { text = text "\n" $0 }
    END {
      text = tolower(text) "\n"
      for (i = 1; i <= n; i++) {
        w = tolower(list[i]); if (w == "") continue
        off = 0; rest = text
        while ((p = index(rest, w)) > 0) {
          at = off + p; stop = at + length(w)
          before = substr(text, at - 1, 1); after = substr(text, stop, 1)
          if (!namechar(before) && (!namechar(after) || (after == "." && !namechar(substr(text, stop + 1, 1))))) {
            print list[i]; break
          }
          off = at; rest = substr(text, off + 1)
        }
      }
    }' "$1" -
}
