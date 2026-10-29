#!/usr/bin/env bash
# PMDA ドメインを含むコードの混入を検出する。
#
# PMDA は自動巡回を全面的に禁止している(docs/adr/0001、docs/adr/0004)。
# 変換ジョブ(batch/)・テスト・スクリプトなどから PMDA へアクセスするコードが
# 入らないよう、追跡されているテキストファイルで PMDA のドメインを含む行を検出して失敗させる。
# サブドメイン(info. など)も対象。大文字小文字は区別しない。
#
# 除外するのは次だけ:
#   - docs/ 配下(設計資料。URL の記載はアクセスではない)
#   - scripts/ci/pmda-allowlist.txt に書かれたパス(アプリの URL テンプレート定義など)
#
# git ls-files / git grep を使い、追跡されているファイルだけを見る。
# Linux(GitHub Actions)と Git Bash for Windows の両方で動く。
#
# 使い方: リポジトリ内の任意の場所で bash scripts/ci/check-pmda-access.sh
# 終了コード: 0 = 問題なし、1 = 検出あり、2 = 実行エラー

set -u

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "ERROR: git リポジトリの中で実行してください" >&2
  exit 2
}
cd "$repo_root" || exit 2

allowlist_file="scripts/ci/pmda-allowlist.txt"

# このスクリプト自体に一致しないよう、ドットを [.] で書いている
pattern='pmda[.]go[.]jp'

pathspecs=("." ":(exclude)docs/")
if [[ -f "$allowlist_file" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    line=${line%%#*}
    line=$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [[ -z "$line" ]] && continue
    pathspecs+=(":(exclude,glob)$line")
  done <"$allowlist_file"
fi

# -I: バイナリを除外 / -i: 大文字小文字を区別しない / -E: 拡張正規表現 / -n: 行番号
matches=$(git -c core.quotePath=false grep -I -i -n -E -e "$pattern" -- "${pathspecs[@]}")
status=$?
if ((status > 1)); then
  echo "ERROR: git grep が失敗しました(終了コード $status)" >&2
  exit 2
fi

if [[ -n "$matches" ]]; then
  echo "NG: PMDA のドメインを含む行が見つかりました:"
  printf '%s\n' "$matches" | sed 's/^/  /'
  echo "  -> PMDA は自動巡回を禁止しています(docs/adr/0001、0004)。スクリプト・テスト・変換ジョブからアクセスしないでください"
  echo "  -> アプリの URL テンプレート定義など、アクセスしない正当な箇所なら $allowlist_file に追記し、PR でレビューを受けてください"
  echo "check-pmda-access: 失敗"
  exit 1
fi

echo "OK: PMDA のドメインを含む行はありません(docs/ と許可リストを除く)"
echo "check-pmda-access: 成功"
exit 0
