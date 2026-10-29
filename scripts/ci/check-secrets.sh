#!/usr/bin/env bash
# 秘密情報の混入を検出する。
#
# 検査は3つ:
#   1. 追跡されているファイルに、署名鍵・設定ファイルなど「コミットしてはならない名前」が無いか
#   2. 上記の名前が .gitignore で無視される設定になっているか(設定が消されていないか)
#   3. 追跡されているテキストファイルに、鍵らしい文字列が無いか
#
# git ls-files / git grep を使い、追跡されているファイルだけを見る。
# Linux(GitHub Actions)と Git Bash for Windows の両方で動く。
#
# 使い方: リポジトリ内の任意の場所で bash scripts/ci/check-secrets.sh
# 終了コード: 0 = 問題なし、1 = 検出あり、2 = 実行エラー
#
# 文字列パターンの誤検出を除外するときは scripts/ci/secrets-allowlist.txt に追記する
# (追記は PR でレビューを受けること)。ファイル名の検査(1)に除外は無い。

set -u

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "ERROR: git リポジトリの中で実行してください" >&2
  exit 2
}
cd "$repo_root" || exit 2

script_dir="scripts/ci"
allowlist_file="$script_dir/secrets-allowlist.txt"
failed=0

# ---- 1. コミットしてはならないファイル名 ----------------------------------
# basename に対して bash の case パターンで照合する。
is_forbidden_name() {
  local name=$1
  case "$name" in
    *.jks | *.keystore | *.p12 | *.pfx | *.pem | *.key | *.p8) return 0 ;;
    keystore.properties | secrets.properties | local.properties) return 0 ;;
    google-services.json | GoogleService-Info.plist) return 0 ;;
    .env | .env.*) return 0 ;;
    *.apk | *.aab) return 0 ;; # 署名済み成果物
  esac
  return 1
}

forbidden_hits=()
while IFS= read -r -d '' path; do
  if is_forbidden_name "${path##*/}"; then
    forbidden_hits+=("$path")
  fi
done < <(git ls-files -z)

if ((${#forbidden_hits[@]} > 0)); then
  failed=1
  echo "NG: コミットしてはならないファイルが追跡されています:"
  for p in "${forbidden_hits[@]}"; do
    echo "  $p"
  done
  echo "  -> git rm --cached <path> で追跡を外し、鍵やキーが漏れた場合は無効化・再発行してください"
else
  echo "OK: 禁止ファイル名は追跡されていません"
fi

# ---- 2. .gitignore の設定が残っているか -----------------------------------
# 代表的な置き場所で、無視されることを確かめる(ファイルを作らずに判定する)。
must_be_ignored=(
  "release.jks"
  "app/release.jks"
  "upload.keystore"
  "app/upload.keystore"
  "cert.p12"
  "key.pem"
  "keystore.properties"
  "secrets.properties"
  "local.properties"
  "app/google-services.json"
  "google-services.json"
  ".env"
  ".env.local"
  "app/release/app-release.aab"
  "app-release.apk"
)
not_ignored=()
for p in "${must_be_ignored[@]}"; do
  if ! git check-ignore -q --no-index -- "$p"; then
    not_ignored+=("$p")
  fi
done

if ((${#not_ignored[@]} > 0)); then
  failed=1
  echo "NG: 次のパスが .gitignore で無視されません(設定を戻してください):"
  for p in "${not_ignored[@]}"; do
    echo "  $p"
  done
else
  echo "OK: 秘密情報のファイル名は .gitignore で無視されます"
fi

# ---- 3. 鍵らしい文字列 ----------------------------------------------------
# このスクリプト自体に一致しないよう、リテラルの一部を [] で囲んでいる。
patterns=(
  '-----BEGIN ([A-Z0-9]+ )*PRIVATE KE[Y]-----'      # PEM 形式の秘密鍵(RSA / EC / OPENSSH / ENCRYPTED など)
  'AI[z]a[0-9A-Za-z_-]{35}'                          # Google API キー
  '"type"[[:space:]]*:[[:space:]]*"service_accoun[t]"' # Google サービスアカウント JSON
  'AKI[A][0-9A-Z]{16}'                               # AWS アクセスキー ID
  'gh[pousr]_[A-Za-z0-9]{36}'                        # GitHub トークン
  'github_pa[t]_[A-Za-z0-9_]{22,}'                   # GitHub fine-grained トークン
  'xox[baprs]-[A-Za-z0-9-]{10,}'                     # Slack トークン
)

# 許可リスト(git pathspec の glob)を除外指定に変換する
pathspecs=(".")
if [[ -f "$allowlist_file" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    line=${line%%#*}
    line=$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [[ -z "$line" ]] && continue
    pathspecs+=(":(exclude,glob)$line")
  done <"$allowlist_file"
fi

grep_args=()
for pat in "${patterns[@]}"; do
  grep_args+=(-e "$pat")
done

# -I: バイナリを除外 / -E: 拡張正規表現 / -n: 行番号
matches=$(git -c core.quotePath=false grep -I -n -E "${grep_args[@]}" -- "${pathspecs[@]}")
status=$?
if ((status > 1)); then
  echo "ERROR: git grep が失敗しました(終了コード $status)" >&2
  exit 2
fi

if [[ -n "$matches" ]]; then
  failed=1
  echo "NG: 鍵らしい文字列が見つかりました(値は表示しません):"
  # 鍵そのものをログに残さないよう、パスと行番号だけを出す
  printf '%s\n' "$matches" | cut -d: -f1,2 | sed 's/^/  /'
  echo "  -> 本物の鍵なら無効化・再発行し、履歴から除去してください。誤検出なら $allowlist_file に追記してください"
else
  echo "OK: 鍵らしい文字列は見つかりません"
fi

if ((failed)); then
  echo "check-secrets: 失敗"
  exit 1
fi
echo "check-secrets: 成功"
exit 0
