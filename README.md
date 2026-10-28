# Android App Project

AIエージェント協調で開発・運用するAndroidアプリ(Kotlin / Jetpack Compose)。

## 構成
- `.claude/agents/` : エージェント定義(8体)
- `docs/` : エージェント間の共有ドキュメント
- `app/` : アプリ本体(単一モジュールで開始。肥大化したら core/ feature/ に分割)
- `.github/` : CI/CD、Issue/PRテンプレート

## はじめかた
1. このフォルダで `git init`
2. JDK 17 と Android SDK を用意し、`./gradlew assembleDebug` でビルドする
   - `gradle/wrapper/gradle-wrapper.jar` が無い場合は、Gradle 8.14.3 をインストールして `gradle wrapper --gradle-version 8.14.3` を一度実行する
   - パッケージ名(namespace / applicationId)は `gradle.properties` の `yakubiki.applicationId` で管理する(現在は仮の `com.example.drugsearch`)。変えるときは `app/src/main/java` 以下の Kotlin パッケージも合わせて変える
3. Claude Code をこのフォルダで起動し、`/agents` で定義が読み込まれていることを確認
4. 最初は planner → developer → reviewer の3体で運用を開始
