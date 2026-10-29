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
PR と main への push で `.github/workflows/ci.yml` のジョブ `build` が動き、次を順に実行する。

1. Gradle Wrapper の検証(`gradle/actions/wrapper-validation`)
2. リポジトリ検査(`scripts/ci/`。Git Bash でもローカルで同じものを実行できる)
   - `bash scripts/ci/check-secrets.sh` : 署名鍵・`google-services.json`・`keystore.properties`・`.env` などの追跡、`.gitignore` の設定漏れ、鍵らしい文字列(PEM 秘密鍵、Google API キーなど)を検出する
   - `bash scripts/ci/check-pmda-access.sh` : PMDA のドメインを含む行を検出する(PMDA は自動巡回を禁止。ADR-0001、0004)。`docs/` と `scripts/ci/pmda-allowlist.txt` に書いたファイルだけ除外する
   - `bash scripts/ci/test-checks.sh` : 上の2つが違反を検出できることを、使い捨てのリポジトリで確かめる
3. `./gradlew lintDebug` / `testDebugUnitTest` / `assembleDebug`

許可リスト(`scripts/ci/pmda-allowlist.txt`、`scripts/ci/secrets-allowlist.txt`)への追記は、PR で reviewer のレビューを受ける。
