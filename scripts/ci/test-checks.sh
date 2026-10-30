#!/usr/bin/env bash
# check-secrets.sh と check-pmda-access.sh の自己テスト。
#
# 一時ディレクトリに使い捨ての git リポジトリを作り、このリポジトリの .gitignore と
# scripts/ci/*.sh をコピーしたうえで(許可リストは空にする)、違反ファイルを追跡させて
# 検出できることを確かめる。作業中のリポジトリには何も書き込まない。
# 利用者の git 設定に左右されないよう、グローバル・システムの設定は読まない。
#
# 違反用の文字列は、このファイル自体が検査に引っかからないよう実行時に組み立てる。
#
# 使い方: bash scripts/ci/test-checks.sh
# 終了コード: 0 = 全件成功、1 = 失敗あり、2 = テストの準備に失敗

set -u

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid

repo_root=$(git rev-parse --show-toplevel) || exit 2
work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT
repo="$work/repo"

passed=0
failed=0

die() {
  echo "ERROR: テストの準備に失敗しました: $*" >&2
  exit 2
}

# 使い捨てリポジトリを作り直す
fresh_repo() {
  rm -rf "$repo" || die "rm"
  mkdir -p "$repo/scripts/ci" || die "mkdir"
  cp "$repo_root/.gitignore" "$repo/.gitignore" || die "cp .gitignore"
  cp "$repo_root"/scripts/ci/*.sh "$repo/scripts/ci/" || die "cp scripts"
  : >"$repo/scripts/ci/pmda-allowlist.txt" || die "allowlist"
  : >"$repo/scripts/ci/secrets-allowlist.txt" || die "allowlist"
  git -C "$repo" init -q -b main || die "git init"
  # 改行コード変換の警告で出力が埋もれないよう、使い捨てリポジトリでは変換しない
  git -C "$repo" config core.autocrlf false || die "git config"
  git -C "$repo" add -A || die "git add"
}

# 指定したファイルを作って強制的に追跡させる(.gitignore を無視して混入した状況を再現する)
track() {
  local path=$1 content=$2
  mkdir -p "$repo/$(dirname "$path")" || die "mkdir $path"
  printf '%s\n' "$content" >"$repo/$path" || die "write $path"
  git -C "$repo" add -f -- "$path" || die "git add $path"
}

# ASCII の文字列を UTF-16 LE で書き、追跡させる
track_utf16() {
  local path=$1 s=$2 i
  mkdir -p "$repo/$(dirname "$path")" || die "mkdir $path"
  {
    printf '\377\376'
    for ((i = 0; i < ${#s}; i++)); do printf '%s\0' "${s:i:1}"; done
    printf '\n\0'
  } >"$repo/$path" || die "write $path"
  git -C "$repo" add -f -- "$path" || die "git add $path"
}

allow() { # allow <pmda|secrets> <行>
  printf '%s\n' "$2" >>"$repo/scripts/ci/$1-allowlist.txt" || die "allowlist"
}

commit() {
  git -C "$repo" add -A || die "git add"
  git -C "$repo" commit -q -m "$1" || die "git commit"
}

record() { # record <成否> <説明>
  if [[ "$1" == ok ]]; then
    passed=$((passed + 1))
    echo "PASS: $2"
  else
    failed=$((failed + 1))
    echo "FAIL: $2"
    sed 's/^/    /' "$work/out.txt"
  fi
}

# expect <期待する終了コード> <説明> <スクリプト名> [引数...]
expect() {
  local want=$1 desc=$2 script=$3 got
  shift 3
  (cd "$repo" && bash "scripts/ci/$script" "$@" >"$work/out.txt" 2>&1)
  got=$?
  if [[ "$got" == "$want" ]]; then
    record ok "$desc"
  else
    echo "    (期待 $want、実際 $got)" >>"$work/out.txt"
    record ng "$desc"
  fi
}

# 直前の expect の出力に、値が含まれていないこと
expect_not_logged() {
  local value=$1 desc=$2
  if grep -qF -- "$value" "$work/out.txt"; then
    record ng "$desc"
  else
    record ok "$desc"
  fi
}

# 直前の expect の出力に、この行がそのまま含まれていること
expect_line() {
  local value=$1 desc=$2
  if grep -qxF -- "$value" "$work/out.txt"; then
    record ok "$desc"
  else
    record ng "$desc"
  fi
}

# 直前の expect の出力に、文字列が含まれていること
expect_logged() {
  local value=$1 desc=$2
  if grep -qF -- "$value" "$work/out.txt"; then
    record ok "$desc"
  else
    record ng "$desc"
  fi
}

# ---- 実行時に組み立てる違反用の文字列 --------------------------------------
pmda_domain="pmda"".go.jp"
pmda_url="https://www.$pmda_domain/PmdaSearch/"
pem_header="-----BEGIN RSA PRIVATE ""KEY-----"
pgp_header="-----BEGIN PGP PRIVATE ""KEY BLOCK-----"
google_key="AI""za$(printf 'A%.0s' {1..35})"
aws_key="AK""IA$(printf 'B%.0s' {1..16})"
github_token="gh""p_$(printf 'c%.0s' {1..36})"
github_pat="github_""pat_$(printf 'D%.0s' {1..30})"
slack_token="xo""xb-$(printf '1%.0s' {1..12})-abcdef"
sa_json="{ \"type\": \"service_""account\" }"
pw="store""Password"
kpw="key""Password"
secret_pw="Hunter2Secret"

# ---- 通常時 ---------------------------------------------------------------
fresh_repo
track "app/src/main/Foo.kt" "class Foo"
expect 0 "違反が無ければ check-secrets は成功する" check-secrets.sh
expect 0 "違反が無ければ check-pmda-access は成功する" check-pmda-access.sh

# ---- 終了コード 2 の経路 ---------------------------------------------------
mkdir -p "$work/notrepo"
for s in check-secrets.sh check-pmda-access.sh; do
  (cd "$work/notrepo" && GIT_CEILING_DIRECTORIES="$work" bash "$repo/scripts/ci/$s" >"$work/out.txt" 2>&1)
  if [[ $? == 2 ]]; then record ok "$s は git リポジトリの外では終了コード 2"; else record ng "$s は git リポジトリの外では終了コード 2"; fi
done
expect 2 "check-secrets は不明な引数で終了コード 2" check-secrets.sh --bogus
expect 2 "check-secrets は --commits の値が無いと終了コード 2" check-secrets.sh --commits
expect 2 "check-secrets は解決できない範囲で終了コード 2" check-secrets.sh --commits no-such-ref..HEAD
expect 2 "check-pmda-access は引数を受け付けず終了コード 2" check-pmda-access.sh --bogus

# ---- check-secrets: 禁止ファイル名(大文字小文字・接尾辞を含む) ------------
# 起動回数を減らすため1つのリポジトリにまとめて追跡させ、1件ずつ一覧に出ることを確かめる
# Windows では大文字小文字だけ違う名前が同じファイルになるため、別のディレクトリに置く
forbidden_names=(app/release.jks upload.keystore cert.p12 cert.pfx key.pem server.key AuthKey.p8
  keystore.properties app/google-services.json local.properties .env .env.production
  secrets.properties app/release/app-release.aab app-release.apk GoogleService-Info.plist
  RELEASE.JKS lib/Google-Services.json config/Keystore.Properties release.jks.bak
  keystore.properties.old "app/google-services (1).json" upload.keystore~ app/src/release.KeyStore)
fresh_repo
for name in "${forbidden_names[@]}"; do track "$name" "dummy"; done
expect 1 "禁止ファイル名を検出する" check-secrets.sh
for name in "${forbidden_names[@]}"; do
  expect_line "  $name" "禁止ファイル名 $name を検出する"
done

fresh_repo
for name in app/src/main/java/a/KeystoreHelper.kt app/src/main/java/a/PemParser.kt app/src/main/java/a/server.keys.kt; do
  track "$name" "class X"
done
expect 0 "紛らわしいが正当な名前(KeystoreHelper.kt、PemParser.kt、server.keys.kt)は通す" check-secrets.sh

# ---- check-secrets: .gitignore の設定が消えた場合 -----------------------------
fresh_repo
grep -vxF -e google-services.json -e '*.pfx' -e '*.p8' -e '*.key' -e GoogleService-Info.plist \
  "$repo/.gitignore" >"$work/gi" || die "grep"
mv "$work/gi" "$repo/.gitignore" || die "mv"
expect 1 ".gitignore から設定が消えたら検出する" check-secrets.sh
for p in google-services.json cert.pfx AuthKey.p8 server.key GoogleService-Info.plist; do
  expect_line "  $p" ".gitignore で $p が無視されなくなったら検出する"
done

# ---- check-secrets: 鍵らしい文字列 -------------------------------------------
cases=(
  "PEM 秘密鍵|$pem_header|$pem_header"
  "PGP 秘密鍵|$pgp_header|$pgp_header"
  "Google API キー|val k = \"$google_key\"|$google_key"
  "AWS アクセスキー|$aws_key|$aws_key"
  "GitHub トークン|token=$github_token|$github_token"
  "GitHub fine-grained トークン|token=$github_pat|$github_pat"
  "Slack トークン|hook=$slack_token|$slack_token"
  "サービスアカウント JSON|$sa_json|service_""account"
  "storePassword の直書き(Kotlin DSL)|    $pw = \"$secret_pw\"|$secret_pw"
  "keyPassword の直書き(Groovy)|    $kpw '$secret_pw'|$secret_pw"
)
fresh_repo
for i in "${!cases[@]}"; do
  IFS='|' read -r desc content value <<<"${cases[$i]}"
  track "app/src/main/res/raw/case$i.txt" "$content"
done
expect 1 "鍵らしい文字列を検出する" check-secrets.sh
for i in "${!cases[@]}"; do
  IFS='|' read -r desc content value <<<"${cases[$i]}"
  expect_line "  app/src/main/res/raw/case$i.txt:1" "$desc の文字列を検出する"
  expect_not_logged "$value" "$desc の値をログに出さない"
done

fresh_repo
track "app/build.gradle.kts" "$(printf '%s\n' "$pw = System.getenv(\"KEYSTORE_PASSWORD\")" "$pw = \"\$pwFromEnv\"" \
  "$kpw = \"\${props.key}\"" "$kpw = props[\"$kpw\"] ?: \"\"" "$pw = \"\"")"
expect 0 "環境変数・変数参照・空文字のパスワードは通す" check-secrets.sh

# ---- check-secrets: 許可リスト(まず検出され、許可すると除外される) ----------
fresh_repo
track "app/src/test/fixtures/dummy.txt" "$google_key"
expect 1 "許可前: テスト用ダミーの鍵文字列を検出する" check-secrets.sh
allow secrets "app/src/test/fixtures/dummy.txt  # 検査のテスト用ダミー"
expect 0 "許可後: secrets-allowlist に載せたファイルは除外する" check-secrets.sh
track "app/src/main/res/raw/other.txt" "$google_key"
expect 1 "許可リストがあっても他のファイルは検出する" check-secrets.sh

for bad in "app/src/test/fixtures/*.txt" "app/src/test/fixtures/" "app/src/test/fixtures" "app/src/test/fixtures/missing.txt"; do
  fresh_repo
  track "app/src/test/fixtures/dummy.txt" "x"
  allow secrets "$bad"
  expect 2 "secrets-allowlist の不正な行 '$bad' は終了コード 2" check-secrets.sh
done

# ---- check-secrets: binary / -diff 指定と UTF-16 によるすり抜け ----------------
fresh_repo
track ".gitattributes" "*.txt binary"
track "app/src/main/res/raw/config.txt" "$google_key"
expect 1 "binary 指定のファイルの鍵文字列も検出する" check-secrets.sh

fresh_repo
track "app/src/main/res/raw/k.txt" "x"
track_utf16 "tools/keys.ps1" "\$k = '$google_key'"
expect 1 "UTF-16 のファイルを検査できないものとして検出する(check-secrets)" check-secrets.sh
expect_logged "tools/keys.ps1" "検査できないファイルのパスを表示する"

# ---- check-pmda-access ---------------------------------------------------
pmda_paths=(batch/fetch.py app/src/test/java/LinkTest.kt scripts/probe.sh .github/workflows/x.yml
  build.gradle.kts README.md notes/x.md docs/x.kt app/docs/x.kt app/docs/x.md)
fresh_repo
for path in "${pmda_paths[@]}"; do track "$path" "url = \"$pmda_url\""; done
expect 1 "PMDA ドメインを検出する" check-pmda-access.sh
for path in "${pmda_paths[@]}"; do
  expect_line "  $path:1" "$path の PMDA ドメインを検出する(パス:行番号を表示する)"
done
expect_not_logged "PmdaSearch" "PMDA 検査は行の内容をログに出さない"

fresh_repo
track "batch/fetch.py" "URL = 'https://WWW.INFO.$(printf '%s' "$pmda_domain" | tr '[:lower:]' '[:upper:]')/go/pack/'"
expect 1 "大文字のドメインも検出する" check-pmda-access.sh

fresh_repo
track "notes/adr.md" "$pmda_url"
expect 1 "docs/ の外の文書は検出する" check-pmda-access.sh
fresh_repo
track "docs/adr/9999-x.md" "$pmda_url"
track "docs/README.md" "$pmda_url"
expect 0 "ルートの docs/ 配下の *.md は除外する" check-pmda-access.sh

# binary / -diff 指定と UTF-16 によるすり抜け
fresh_repo
track ".gitattributes" "batch/** -diff"
track "batch/fetch.py" "requests.get('$pmda_url')"
expect 1 "-diff 指定のファイルの PMDA ドメインも検出する" check-pmda-access.sh
fresh_repo
track ".gitattributes" "*.py binary"
track "batch/fetch.py" "requests.get('$pmda_url')"
expect 1 "binary 指定のファイルの PMDA ドメインも検出する" check-pmda-access.sh
fresh_repo
track_utf16 "tools/fetch.ps1" "Invoke-WebRequest $pmda_url"
expect 1 "UTF-16 のファイルを検査できないものとして検出する(check-pmda-access)" check-pmda-access.sh
fresh_repo
mkdir -p "$repo/app/src/main/res/drawable" && printf '\211PNG\r\n\032\n\0\0\0' >"$repo/app/src/main/res/drawable/a.png" || die "png"
mkdir -p "$repo/lib" && printf 'PK\003\004\0\0' >"$repo/lib/x.JAR" || die "jar"
git -C "$repo" add -A || die "git add"
expect 0 "既知の拡張子のバイナリは通す(check-pmda-access)" check-pmda-access.sh
expect 0 "既知の拡張子のバイナリは通す(check-secrets)" check-secrets.sh
printf 'x\0y' >"$repo/tools.bin" && git -C "$repo" add -A || die "bin"
expect 1 "未知の拡張子のバイナリは検出する" check-pmda-access.sh

# 許可リスト(まず検出され、許可すると除外される)
fresh_repo
track "app/src/main/assets/url-templates.json" "{\"l3\": \"$pmda_url\"}"
expect 1 "許可前: URL テンプレート定義を検出する" check-pmda-access.sh
allow pmda "app/src/main/assets/url-templates.json  # T05 の URL テンプレート"
expect 0 "許可後: 許可リストに載せたファイルは除外する(行末コメント付き)" check-pmda-access.sh
track "batch/fetch.py" "$pmda_url"
expect 1 "許可リストがあっても他のファイルは検出する" check-pmda-access.sh

fresh_repo
track "app/src/main/java/a/PmdaLinks.kt" "const val U = \"$pmda_url\""
expect 1 "許可前: Kotlin の URL 定義を検出する" check-pmda-access.sh
printf '%s\r\n' "app/src/main/java/a/PmdaLinks.kt" >>"$repo/scripts/ci/pmda-allowlist.txt"
expect 0 "許可後: CRLF 改行の許可リストを扱える" check-pmda-access.sh

# 許可リストの不正な行
bad_lines=(
  "app/src/main/assets/*.json|ワイルドカード"
  "app/src/main/**/url-templates.json|ワイルドカード **"
  "app/src/main/assets/url-template?.json|ワイルドカード ?"
  "app/src/main/assets/|/ で終わる行"
  "app/src/main/assets|ディレクトリ名だけの行"
  "app/src/main/assets/missing.json|一致しない行"
  "/app/src/main/assets/url-templates.json|/ で始まる行"
  "app/../app/src/main/assets/url-templates.json|.. を含む行"
  "batch/fetch.py|batch/"
  "scripts/probe.sh|scripts/"
  ".github/workflows/x.yml|.github/"
  "app/src/test/java/LinkTest.kt|src/test"
  "app/src/androidTest/java/LinkTest.kt|src/androidTest"
  "app/src/testDebug/java/LinkTest.kt|src/testDebug"
)
fresh_repo
for f in app/src/main/assets/url-templates.json batch/fetch.py scripts/probe.sh .github/workflows/x.yml \
  app/src/test/java/LinkTest.kt app/src/androidTest/java/LinkTest.kt app/src/testDebug/java/LinkTest.kt; do
  track "$f" "$pmda_url"
done
for b in "${bad_lines[@]}"; do
  IFS='|' read -r line desc <<<"$b"
  printf '%s\n' "$line" >"$repo/scripts/ci/pmda-allowlist.txt" || die "allowlist"
  expect 2 "pmda-allowlist の不正な行($desc)は終了コード 2" check-pmda-access.sh
done

# ---- サブモジュール -------------------------------------------------------
fresh_repo
git -C "$repo" update-index --add --cacheinfo "160000,$(printf '1%.0s' {1..40}),vendor/sub" || die "gitlink"
expect 1 "gitlink を検出する(check-pmda-access)" check-pmda-access.sh
expect 1 "gitlink を検出する(check-secrets)" check-secrets.sh
fresh_repo
track ".gitmodules" "[submodule \"x\"]"
expect 1 ".gitmodules を検出する" check-pmda-access.sh

# ---- check-secrets --commits: PR 途中のコミット ------------------------------
fresh_repo
track "app/src/main/Foo.kt" "class Foo"
commit "base"
git -C "$repo" checkout -q -b feature || die "checkout"
track "app/src/main/res/raw/config.txt" "val k = \"$google_key\""
commit "add key"
git -C "$repo" rm -q -- "app/src/main/res/raw/config.txt" || die "git rm"
commit "remove key"
expect 0 "途中で消した鍵は、ツリーだけの検査では見つからない" check-secrets.sh
expect 1 "途中のコミットで追加して消した鍵を --commits で検出する" check-secrets.sh --commits main..HEAD
expect_not_logged "$google_key" "履歴の検査でも値をログに出さない"
expect_logged "app/src/main/res/raw/config.txt:1" "履歴の検査はパス:行番号を表示する"

fresh_repo
commit "base"
git -C "$repo" checkout -q -b feature || die "checkout"
track "app/release.jks" "dummy"
commit "add jks"
git -C "$repo" rm -q -- "app/release.jks" || die "git rm"
commit "remove jks"
expect 1 "途中のコミットで追加して消した禁止ファイルを --commits で検出する" check-secrets.sh --commits main..HEAD

fresh_repo
commit "base"
git -C "$repo" checkout -q -b feature || die "checkout"
track_utf16 "tools/k.ps1" "\$k = '$google_key'"
commit "add utf16 key"
git -C "$repo" rm -q -- "tools/k.ps1" || die "git rm"
commit "remove"
expect 1 "途中のコミットの UTF-16 の鍵も --commits で検出する" check-secrets.sh --commits main..HEAD

fresh_repo
commit "base"
git -C "$repo" checkout -q -b feature || die "checkout"
track "app/src/main/Bar.kt" "class Bar"
track "app/src/main/Baz.kt" "+++ b/looks-like-a-header"
commit "clean change"
expect 0 "問題の無いコミット範囲は --commits でも成功する" check-secrets.sh --commits main..HEAD

echo
echo "test-checks: 成功 $passed 件、失敗 $failed 件"
((failed == 0))
