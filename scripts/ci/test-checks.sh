#!/usr/bin/env bash
# check-secrets.sh と check-pmda-access.sh の自己テスト。
#
# 一時ディレクトリに使い捨ての git リポジトリを作り、このリポジトリの .gitignore と
# scripts/ci/ をコピーしたうえで、違反ファイルを追跡させて検出できることを確かめる。
# 作業中のリポジトリには何も書き込まない。
#
# 違反用の文字列は、このファイル自体が検査に引っかからないよう実行時に組み立てる。
#
# 使い方: bash scripts/ci/test-checks.sh
# 終了コード: 0 = 全件成功、1 = 失敗あり

set -u

repo_root=$(git rev-parse --show-toplevel) || exit 2
work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT

passed=0
failed=0

# 使い捨てリポジトリを作り直す
fresh_repo() {
  rm -rf "$work/repo"
  mkdir -p "$work/repo/scripts/ci"
  cp "$repo_root/.gitignore" "$work/repo/.gitignore"
  cp "$repo_root"/scripts/ci/*.sh "$repo_root"/scripts/ci/*.txt "$work/repo/scripts/ci/"
  git -C "$work/repo" init -q
  # 改行コード変換の警告で出力が埋もれないよう、使い捨てリポジトリでは変換しない
  git -C "$work/repo" config core.autocrlf false
  git -C "$work/repo" add -A
}

# 指定したファイルを作って強制的に追跡させる(.gitignore を無視して混入した状況を再現する)
track() {
  local path=$1 content=$2
  mkdir -p "$work/repo/$(dirname "$path")"
  printf '%s\n' "$content" >"$work/repo/$path"
  git -C "$work/repo" add -f -- "$path"
}

# expect <期待する終了コード> <説明> <スクリプト名>
expect() {
  local want=$1 desc=$2 script=$3 got
  (cd "$work/repo" && bash "scripts/ci/$script" >"$work/out.txt" 2>&1)
  got=$?
  if [[ "$got" == "$want" ]]; then
    passed=$((passed + 1))
    echo "PASS: $desc"
  else
    failed=$((failed + 1))
    echo "FAIL: $desc(期待 $want、実際 $got)"
    sed 's/^/    /' "$work/out.txt"
  fi
}

# ---- 実行時に組み立てる違反用の文字列 --------------------------------------
pmda_domain="pmda"".go.jp"
pem_header="-----BEGIN RSA PRIVATE ""KEY-----"
google_key="AI""za$(printf 'A%.0s' {1..35})"
aws_key="AK""IA$(printf 'B%.0s' {1..16})"
github_token="gh""p_$(printf 'c%.0s' {1..36})"

# ---- 通常時 ---------------------------------------------------------------
fresh_repo
track "app/src/main/Foo.kt" "class Foo"
expect 0 "違反が無ければ check-secrets は成功する" check-secrets.sh
expect 0 "違反が無ければ check-pmda-access は成功する" check-pmda-access.sh

# ---- check-secrets: 禁止ファイル名 -------------------------------------------
for name in app/release.jks upload.keystore cert.p12 key.pem keystore.properties \
  app/google-services.json local.properties .env .env.production secrets.properties \
  app/release/app-release.aab; do
  fresh_repo
  track "$name" "dummy"
  expect 1 "禁止ファイル名 $name を検出する" check-secrets.sh
done

# ---- check-secrets: .gitignore の設定が消えた場合 -----------------------------
fresh_repo
grep -v '^google-services\.json$' "$work/repo/.gitignore" >"$work/gi" && mv "$work/gi" "$work/repo/.gitignore"
expect 1 ".gitignore から google-services.json が消えたら検出する" check-secrets.sh

# ---- check-secrets: 鍵らしい文字列 -------------------------------------------
for case in "PEM 秘密鍵|$pem_header" "Google API キー|val k = \"$google_key\"" \
  "AWS アクセスキー|$aws_key" "GitHub トークン|token=$github_token" \
  "サービスアカウント JSON|{ \"type\": \"service_""account\" }"; do
  fresh_repo
  track "app/src/main/res/raw/config.txt" "${case#*|}"
  expect 1 "${case%%|*} の文字列を検出する" check-secrets.sh
done

fresh_repo
track "app/src/test/fixtures/dummy.txt" "$google_key"
printf '%s\n' "app/src/test/fixtures/dummy.txt" >>"$work/repo/scripts/ci/secrets-allowlist.txt"
expect 0 "secrets-allowlist に載せたファイルの文字列は除外する" check-secrets.sh

# ---- check-pmda-access ---------------------------------------------------
for path in batch/fetch.py app/src/test/java/LinkTest.kt scripts/probe.sh .github/workflows/x.yml build.gradle.kts; do
  fresh_repo
  track "$path" "url = \"https://www.$pmda_domain/PmdaSearch/\""
  expect 1 "$path の PMDA ドメインを検出する" check-pmda-access.sh
done

fresh_repo
track "batch/fetch.py" "URL = 'https://WWW.INFO.$(printf '%s' "$pmda_domain" | tr '[:lower:]' '[:upper:]')/go/pack/'"
expect 1 "大文字のドメインも検出する" check-pmda-access.sh

fresh_repo
track "docs/adr/9999-x.md" "https://www.$pmda_domain/"
expect 0 "docs/ 配下は除外する" check-pmda-access.sh

fresh_repo
track "app/src/main/assets/url-templates.json" "{\"l3\": \"https://www.$pmda_domain/PmdaSearch/\"}"
expect 1 "許可リストに無い URL テンプレート定義は検出する" check-pmda-access.sh
printf '%s\n' "app/src/main/assets/url-templates.json  # T05 の URL テンプレート" \
  >>"$work/repo/scripts/ci/pmda-allowlist.txt"
expect 0 "許可リストに載せたファイルは除外する(行末コメント付き)" check-pmda-access.sh
track "batch/fetch.py" "https://www.$pmda_domain/"
expect 1 "許可リストがあっても他のファイルは検出する" check-pmda-access.sh

fresh_repo
track "app/src/main/java/a/PmdaLinks.kt" "const val U = \"https://www.$pmda_domain/\""
printf '%s\r\n' "app/src/main/**/PmdaLinks.kt" >>"$work/repo/scripts/ci/pmda-allowlist.txt"
expect 0 "許可リストの glob と CRLF 改行を扱える" check-pmda-access.sh

echo
echo "test-checks: 成功 $passed 件、失敗 $failed 件"
((failed == 0))
