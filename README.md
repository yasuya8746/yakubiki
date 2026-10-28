# Android App Project

AIエージェント協調で開発・運用するAndroidアプリ(Kotlin / Jetpack Compose)。

## 構成
- `.claude/agents/` : エージェント定義(8体)
- `docs/` : エージェント間の共有ドキュメント
- `app/` : アプリ本体(単一モジュールで開始。肥大化したら core/ feature/ に分割)
- `.github/` : CI/CD、Issue/PRテンプレート

## はじめかた
1. このフォルダで `git init`
2. Android Studio で `app/` 以下にプロジェクトを作成(パッケージ名は `com.example.myapp` を置換)
3. Claude Code をこのフォルダで起動し、`/agents` で定義が読み込まれていることを確認
4. 最初は planner → developer → reviewer の3体で運用を開始
