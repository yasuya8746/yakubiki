#!/usr/bin/env bash
# 秘密情報の混入を検出する。
#
# 検査:
#   1. 追跡されているファイルに、署名鍵・設定ファイルなど「コミットしてはならない名前」が無いか
#      (大文字小文字を区別せず、release.jks.bak や google-services (1).json のような接尾辞付きも対象)
#   2. 上記の名前が .gitignore で無視される設定になっているか(設定が消されていないか)
#   3. 追跡されているファイルに、鍵らしい文字列が無いか
#      (.gitattributes の binary / -diff 指定に関係なく全ファイルを見る)
#   4. サブモジュールや、grep で中身を検査できないファイル(UTF-16 など)が無いか
#   5. --commits <範囲> を付けたとき: 範囲内の各コミットで追加されたファイル名と行に、1 と 3 を当てる
#      (PR の途中のコミットで入れて、後のコミットで消した秘密情報を見つけるため)
#
# git ls-files / git grep / git log を使い、追跡されているファイルだけを見る。
# Linux(GitHub Actions)と Git Bash for Windows の両方で動く。
#
# 使い方: bash scripts/ci/check-secrets.sh [--commits <base>..<head>]
# 終了コード: 0 = 問題なし、1 = 検出あり、2 = 実行エラー(許可リストの不正を含む)
#
# 検出したときは、値をログに残さないようパスと行番号だけを表示する。
# 文字列パターン(3)の誤検出を除外するときは scripts/ci/secrets-allowlist.txt に追記する
# (追記は PR でレビューを受けること)。ファイル名の検査(1)に除外は無い。

set -u

lib_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 2
# shellcheck source=lib.sh
source "$lib_dir/lib.sh" || exit 2

commit_range=""
while (($# > 0)); do
  case "$1" in
    --commits)
      [[ $# -ge 2 && -n "$2" ]] || {
        echo "ERROR: --commits には範囲(例: origin/main..HEAD)を指定してください" >&2
        exit 2
      }
      commit_range=$2
      shift 2
      ;;
    *)
      echo "ERROR: 不明な引数です: $1" >&2
      echo "使い方: bash scripts/ci/check-secrets.sh [--commits <base>..<head>]" >&2
      exit 2
      ;;
  esac
done

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "ERROR: git リポジトリの中で実行してください" >&2
  exit 2
}
cd "$repo_root" || exit 2

if [[ -n "$commit_range" ]] && ! git rev-list --quiet "$commit_range" -- >/dev/null 2>&1; then
  echo "ERROR: コミットの範囲を解決できません: $commit_range(CI では fetch-depth: 0 が必要です)" >&2
  exit 2
fi

allowlist_file="scripts/ci/secrets-allowlist.txt"
load_allowlist "$allowlist_file" secrets
failed=0

# ---- 1. コミットしてはならないファイル名 ----------------------------------
# basename を小文字にしてから、bash の case パターンで照合する。
# 拡張子の後ろに英数字以外が続くもの(.bak、" (1)"、~ など)も対象にする。
is_forbidden_name() {
  local name=${1,,}
  local tail='[!a-z0-9]*'
  local ext
  for ext in jks keystore p12 pfx pem key p8 apk aab; do
    # shellcheck disable=SC2053
    if [[ "$name" == *."$ext" || "$name" == *."$ext"$tail ]]; then
      return 0
    fi
  done
  case "$name" in
    *keystore*.properties | *keystore*.properties$tail) return 0 ;;
    *secrets*.properties | *secrets*.properties$tail) return 0 ;;
    local.properties | local.properties$tail) return 0 ;;
    *google-services*.json | *google-services*.json$tail) return 0 ;;
    googleservice-info*.plist | googleservice-info*.plist$tail) return 0 ;;
    .env | .env.* | .env$tail) return 0 ;;
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
  printf '  %s\n' "${forbidden_hits[@]}"
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
  "cert.pfx"
  "key.pem"
  "server.key"
  "AuthKey.p8"
  "keystore.properties"
  "secrets.properties"
  "local.properties"
  "app/google-services.json"
  "google-services.json"
  "GoogleService-Info.plist"
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
  printf '  %s\n' "${not_ignored[@]}"
else
  echo "OK: 秘密情報のファイル名は .gitignore で無視されます"
fi

# ---- 3. 鍵らしい文字列 ----------------------------------------------------
# このスクリプト自体に一致しないよう、リテラルの一部を [] で囲んでいる。
patterns=(
  '-----BEGIN ([A-Z0-9]+ )*PRIVATE KE[Y]-----'                         # PEM 形式の秘密鍵(RSA / EC / OPENSSH / ENCRYPTED など)
  '-----BEGIN PGP PRIVATE KE[Y] BLOCK-----'                            # PGP 秘密鍵
  'AI[z]a[0-9A-Za-z_-]{35}'                                             # Google API キー
  '"type"[[:space:]]*:[[:space:]]*"service_accoun[t]"'                  # Google サービスアカウント JSON
  'AKI[A][0-9A-Z]{16}'                                                  # AWS アクセスキー ID
  'gh[pousr]_[A-Za-z0-9]{36}'                                           # GitHub トークン
  'github_pa[t]_[A-Za-z0-9_]{22,}'                                      # GitHub fine-grained トークン
  'xox[baprs]-[A-Za-z0-9-]{10,}'                                        # Slack トークン
  # 署名パスワードの直書き(store・key の Password に、文字列リテラルを代入しているもの)。
  # 値に $ を含むもの(環境変数・変数参照)と空文字は対象外。
  '([Ss]tore|[Kk]ey)Passwor[d]([[:space:]]*[=:][[:space:]]*|[[:space:]]+)["'"'"'][^"'"'"'$]+["'"'"']'
)
grep_args=()
for pat in "${patterns[@]}"; do
  grep_args+=(-e "$pat")
done

# --text: .gitattributes で binary / -diff を付けたファイルも中身を見る / -n: 行番号
matches=$(git -c core.quotePath=false grep --text -n -E "${grep_args[@]}" -- . "${ALLOW_EXCLUDES[@]}")
status=$?
if ((status > 1)); then
  echo "ERROR: git grep が失敗しました(終了コード $status)" >&2
  exit 2
fi

if [[ -n "$matches" ]]; then
  failed=1
  echo "NG: 鍵らしい文字列が見つかりました(値は表示しません):"
  printf '%s\n' "$matches" | cut -d: -f1,2 | sed 's/^/  /'
  echo "  -> 本物の鍵なら無効化・再発行し、履歴から除去してください。誤検出なら $allowlist_file に追記してください"
else
  echo "OK: 鍵らしい文字列は見つかりません"
fi

# ---- 4. サブモジュール・検査できないバイナリ ------------------------------
check_tree_shape || failed=1

# ---- 5. コミット範囲の履歴 ------------------------------------------------
if [[ -n "$commit_range" ]]; then
  # 5a. 範囲内で追加されたファイル名
  history_names=()
  while IFS= read -r -d '' path; do
    [[ -z "$path" ]] && continue
    if is_forbidden_name "${path##*/}"; then
      history_names+=("$path")
    fi
  done < <(git -c core.quotePath=false log --no-merges --no-renames --diff-filter=A --name-only -z --format= "$commit_range" --)

  # 5b. 範囲内の各コミットで追加された行。「コミット:パス:行番号<TAB>行」に直してから照合し、位置だけを出す。
  # NUL を取り除くことで、UTF-16 で書かれた行も ASCII の部分は照合できる。
  history_lines=$(
    git -c core.quotePath=false log --no-merges --no-renames --no-color --no-ext-diff --no-textconv \
      --text -p -U0 --format='@@COMMIT %H' "$commit_range" -- . "${ALLOW_EXCLUDES[@]}" |
      tr -d '\000' |
      awk '
        /^@@COMMIT / { commit = substr($2, 1, 12); hdr = 0; next }
        /^diff --git / { hdr = 1; next }
        hdr && /^\+\+\+ / { file = substr($0, 5); sub(/^b\//, "", file); sub(/\t$/, "", file); next }
        /^@@ / { hdr = 0; n = $3; sub(/^\+/, "", n); sub(/,.*/, "", n); line = n + 0; next }
        !hdr && /^\+/ { print commit ":" file ":" line "\t" substr($0, 2); line++ }
      ' |
      grep -a -E "${grep_args[@]}" |
      cut -f1
  )

  if ((${#history_names[@]} > 0)) || [[ -n "$history_lines" ]]; then
    failed=1
    echo "NG: コミット範囲 $commit_range の途中のコミットに秘密情報が含まれます(値は表示しません):"
    for p in "${history_names[@]}"; do
      echo "  追加された禁止ファイル: $p"
    done
    if [[ -n "$history_lines" ]]; then
      printf '%s\n' "$history_lines" | sed 's/^/  鍵らしい文字列 /'
    fi
    echo "  -> 後のコミットで消しても履歴に残ります。鍵を無効化・再発行し、該当コミットを書き換えてから push し直してください"
  else
    echo "OK: コミット範囲 $commit_range の追加内容に秘密情報はありません"
  fi
fi

if ((failed)); then
  echo "check-secrets: 失敗"
  exit 1
fi
echo "check-secrets: 成功"
exit 0
