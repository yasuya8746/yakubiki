#!/usr/bin/env bash
# check-secrets.sh と check-pmda-access.sh が共通で使う関数。直接は実行しない(source して使う)。
# Linux(GitHub Actions)と Git Bash for Windows の bash 4.4 以降で動く。

# 中身がバイナリでも正当とみなす拡張子(小文字)。
# ここに無い拡張子のファイルが、git にバイナリと判定される中身(NUL を含む、UTF-16 など)を持つと失敗させる。
# grep で中身を検査できないファイルを通さないため。追加は PR でレビューを受けること。
KNOWN_BINARY_EXTENSIONS=" png jpg jpeg gif webp ico bmp jar aar so ttf otf woff woff2 zip gz pdf mp3 mp4 ogg wav "

# 検査の対象から外せない領域(PMDA 用の許可リストで使う)
# 変換ジョブ・スクリプト・CI・テストコードは、PMDA へアクセスしうるため許可しない。
is_protected_area() {
  local p=$1
  case "$p" in
    batch | batch/* | scripts | scripts/* | .github | .github/*) return 0 ;;
  esac
  case "/$p" in
    */src/test | */src/test/* | */src/test[A-Za-z]* | */src/androidTest | */src/androidTest*) return 0 ;;
  esac
  return 1
}

# load_allowlist <ファイル> <pmda|secrets>
# 許可リストを読み、git pathspec の除外指定を配列 ALLOW_EXCLUDES に入れる。
# 広く除外できてしまう書き方は、終了コード 2 でスクリプトを終える。
#   - ワイルドカード(* ? [)を含む行
#   - / で終わる行、ディレクトリに一致する行
#   - 追跡されているファイルに一致しない行
#   - ルートからの相対パスでない行(/ で始まる、. や .. を含む)
#   - pmda のとき: batch/ scripts/ .github/ src/test* src/androidTest* に一致する行
ALLOW_EXCLUDES=()
load_allowlist() {
  local file=$1 mode=$2 raw line n=0 errors=0
  local -a hits
  ALLOW_EXCLUDES=()
  [[ -f "$file" ]] || return 0
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    n=$((n + 1))
    line=${raw%$'\r'}
    line=${line%%#*}
    line=$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [[ -z "$line" ]] && continue

    local reason=""
    if [[ "$line" == *[\*\?\[]* ]]; then
      reason="ワイルドカードは使えません。ファイルの実パスを1行ずつ書いてください"
    elif [[ "$line" == */ ]]; then
      reason="ディレクトリは指定できません。ファイルの実パスを書いてください"
    elif [[ "$line" == /* || "/$line/" == */./* || "/$line/" == */../* ]]; then
      reason="リポジトリのルートからの相対パスで書いてください(/ . .. は使えません)"
    elif [[ "$mode" == pmda ]] && is_protected_area "$line"; then
      reason="batch/ scripts/ .github/ とテストコード(src/test、src/androidTest)は許可できません"
    else
      mapfile -d '' hits < <(git ls-files -z -- ":(top,literal)$line")
      if ((${#hits[@]} == 0)); then
        reason="追跡されているファイルに一致しません(削除・移動したなら行を消してください)"
      elif ((${#hits[@]} > 1)) || [[ "${hits[0]}" != "$line" ]]; then
        reason="ディレクトリに一致します。ファイルの実パスを書いてください"
      fi
    fi

    if [[ -n "$reason" ]]; then
      echo "ERROR: $file:$n: $line -> $reason" >&2
      errors=$((errors + 1))
    else
      ALLOW_EXCLUDES+=(":(exclude,top,literal)$line")
    fi
  done <"$file"

  if ((errors > 0)); then
    echo "ERROR: 許可リスト $file に不正な行があります(PR でレビューを受けて直してください)" >&2
    exit 2
  fi
}

# check_tree_shape
# grep で中身を検査できない追跡ファイルを検出する。問題があれば 1 を返す。
#   - サブモジュール(.gitmodules、gitlink)。中身がこのリポジトリの検査対象にならないため
#   - 既知の拡張子以外で、中身がバイナリと判定されるファイル(UTF-16 のテキストを含む)
# 判定は index の中身による(.gitattributes の binary / -diff の指定には左右されない)。
check_tree_shape() {
  local rec info path name ext bad=0
  local -a gitlinks=() unknown=()

  while IFS= read -r -d '' rec; do
    path=${rec#*$'\t'}
    if [[ "${rec%% *}" == 160000 ]]; then
      gitlinks+=("$path")
    elif [[ "${path##*/}" == .gitmodules ]]; then
      gitlinks+=("$path")
    fi
  done < <(git ls-files -s -z)

  while IFS= read -r -d '' rec; do
    info=${rec%%$'\t'*}
    path=${rec#*$'\t'}
    [[ "$info" == i/-text* ]] || continue
    name=${path##*/}
    ext=""
    [[ "$name" == *.* ]] && ext=${name##*.}
    ext=${ext,,}
    if [[ -z "$ext" || "$KNOWN_BINARY_EXTENSIONS" != *" $ext "* ]]; then
      unknown+=("$path")
    fi
  done < <(git ls-files --eol -z)

  if ((${#gitlinks[@]} > 0)); then
    bad=1
    echo "NG: サブモジュールは使えません(中身を検査できないため):"
    printf '  %s\n' "${gitlinks[@]}"
  fi
  if ((${#unknown[@]} > 0)); then
    bad=1
    echo "NG: 中身がバイナリと判定され、grep で検査できないファイルがあります(UTF-16 のテキストを含む):"
    printf '  %s\n' "${unknown[@]}"
    echo "  -> テキストなら UTF-8 で保存し直してください。正当なバイナリなら scripts/ci/lib.sh の KNOWN_BINARY_EXTENSIONS に拡張子を足してください(PR でレビュー)"
  fi
  if ((bad == 0)); then
    echo "OK: サブモジュールと検査できないバイナリはありません"
  fi
  return "$bad"
}
