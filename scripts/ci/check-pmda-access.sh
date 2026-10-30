#!/usr/bin/env bash
# PMDA ドメインを含むコードの混入を検出する。
#
# PMDA は自動巡回を全面的に禁止している(docs/adr/0001、docs/adr/0004)。
# 変換ジョブ(batch/)・テスト・スクリプトなどから PMDA へアクセスするコードが
# 入らないよう、追跡されているファイルで PMDA のドメインを含む行を検出して失敗させる。
# サブドメイン(info. など)も対象。大文字小文字は区別しない。
# .gitattributes の binary / -diff 指定に関係なく全ファイルの中身を見る。
# grep で中身を検査できないファイル(UTF-16 など)とサブモジュールも失敗にする。
#
# 除外するのは次だけ:
#   - ルートの docs/ 配下の文書(*.md)。設計資料の URL の記載はアクセスではない
#   - scripts/ci/pmda-allowlist.txt に1行ずつ書かれたファイル(アプリの URL テンプレート定義など)
#
# git ls-files / git grep を使い、追跡されているファイルだけを見る。
# Linux(GitHub Actions)と Git Bash for Windows の両方で動く。
#
# 使い方: リポジトリ内の任意の場所で bash scripts/ci/check-pmda-access.sh
# 終了コード: 0 = 問題なし、1 = 検出あり、2 = 実行エラー(許可リストの不正を含む)

set -u

lib_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 2
# shellcheck source=lib.sh
source "$lib_dir/lib.sh" || exit 2

if (($# > 0)); then
  echo "ERROR: 引数は受け付けません: $*" >&2
  exit 2
fi

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "ERROR: git リポジトリの中で実行してください" >&2
  exit 2
}
cd "$repo_root" || exit 2

allowlist_file="scripts/ci/pmda-allowlist.txt"
load_allowlist "$allowlist_file" pmda
failed=0

# このスクリプト自体に一致しないよう、ドットを [.] で書いている
pattern='pmda[.]go[.]jp'

# --text: binary / -diff 指定のファイルも中身を見る / -i: 大文字小文字を区別しない / -n: 行番号
matches=$(git -c core.quotePath=false grep --text -i -n -E -e "$pattern" -- \
  . ":(exclude,top,glob)docs/**/*.md" "${ALLOW_EXCLUDES[@]}")
status=$?
if ((status > 1)); then
  echo "ERROR: git grep が失敗しました(終了コード $status)" >&2
  exit 2
fi

if [[ -n "$matches" ]]; then
  failed=1
  echo "NG: PMDA のドメインを含む行が見つかりました:"
  printf '%s\n' "$matches" | cut -d: -f1,2 | sed 's/^/  /'
  echo "  -> PMDA は自動巡回を禁止しています(docs/adr/0001、0004)。スクリプト・テスト・変換ジョブからアクセスしないでください"
  echo "  -> アプリの URL テンプレート定義など、アクセスしない正当なファイルなら $allowlist_file に実パスを追記し、PR でレビューを受けてください"
else
  echo "OK: PMDA のドメインを含む行はありません(docs/ の文書と許可リストを除く)"
fi

check_tree_shape || failed=1

if ((failed)); then
  echo "check-pmda-access: 失敗"
  exit 1
fi
echo "check-pmda-access: 成功"
exit 0
