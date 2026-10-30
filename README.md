# Android App Project

AIエージェント協調で開発・運用するAndroidアプリ(Kotlin / Jetpack Compose)。

## 構成
- `.claude/agents/` : エージェント定義(8体)
- `docs/` : エージェント間の共有ドキュメント
- `app/` : アプリ本体(単一モジュールで開始。肥大化したら core/ feature/ に分割)
- `.github/` : CI/CD、Issue/PRテンプレート

## はじめかた
1. このフォルダで `git init`
2. Android Studio(同梱 JDK と Android SDK)を用意し、`./gradlew assembleDebug` でビルドする
   - コマンドラインでは `JAVA_HOME` を Android Studio の `jbr` に向ける。Gradle は Wrapper(9.8.1)が自動で取得する
   - `local.properties` の `sdk.dir` はエスケープが必要(例: `sdk.dir=C\:\\Users\\<ユーザー>\\AppData\\Local\\Android\\Sdk`)
   - パッケージ名(namespace / applicationId)は `gradle.properties` の `yakubiki.applicationId` で管理する(現在は仮の `com.example.drugsearch`)。変えるときは `app/src/main/java` 以下の Kotlin パッケージも合わせて変える
3. Claude Code をこのフォルダで起動し、`/agents` で定義が読み込まれていることを確認
4. 最初は planner → developer → reviewer の3体で運用を開始

## CI の検査
PR と main への push で `.github/workflows/ci.yml` のジョブ `build` が動き、次の順に実行する。検査は `scripts/ci/` のスクリプトで、Git Bash でもローカルで同じものを実行できる。

1. Gradle Wrapper の検証(`gradle/actions/wrapper-validation`)
2. `bash scripts/ci/test-checks.sh` : 下の2つの検査が違反を検出できることを、使い捨てのリポジトリで確かめる
3. `bash scripts/ci/check-secrets.sh` : 署名鍵・`google-services.json`・`keystore.properties`・`.env` など(大文字小文字・`.bak` などの接尾辞を問わない)の追跡、`.gitignore` の設定漏れ、鍵らしい文字列(PEM / PGP 秘密鍵、Google API キー、署名パスワードの直書きなど)を検出する
   - PR では `--commits origin/main..HEAD` を付け、途中のコミットで追加して後で消したものも検出する
4. `bash scripts/ci/check-pmda-access.sh` : PMDA のドメインを含む行を検出する(PMDA は自動巡回を禁止。ADR-0001、0004)。ルートの `docs/` 配下の `*.md` と、`scripts/ci/pmda-allowlist.txt` に書いたファイルだけ除外する
5. `./gradlew lintDebug` / `testDebugUnitTest` / `assembleDebug`

3 と 4 は 2 が失敗しても実行する。どちらも、サブモジュールと、grep で中身を検査できないファイル(既知の拡張子以外のバイナリ、UTF-16 のテキスト)を失敗にする。

許可リスト(`scripts/ci/pmda-allowlist.txt`、`scripts/ci/secrets-allowlist.txt`)にはファイルの実パスを1行ずつ書き、追記は PR で reviewer のレビューを受ける。ワイルドカード・ディレクトリ・存在しないパスを書くと検査は終了コード 2 で失敗する。

検査は文字列の一致による。文字列の連結や Base64 化などで組み立てた URL・鍵は検出できないため、レビューでも確認する。
