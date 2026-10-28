# プロジェクト共通ルール(全エージェント必読)

## 技術スタック
Kotlin / Jetpack Compose / Hilt / Room / Retrofit / Gradle Kotlin DSL(バージョンカタログ使用)

## 共有の記録場所
- 要件: docs/requirements/  設計判断: docs/adr/  テスト計画: docs/test-plans/
- 運用手順: docs/runbooks/  障害報告: docs/incidents/  リリースノート: docs/release-notes/
- 改善バックログ: docs/feedback/
- タスクの受け渡しは GitHub Issue / PR で行う

## 絶対禁止(全エージェント共通)
- 署名鍵(.jks/.keystore)、APIキー、google-services.json、keystore.properties のコミット
- main への直接 push
- 人間の承認なしの本番リリース、課金・ストア設定・署名鍵の変更

## 人間の承認ゲート
1. 要件・設計の確定 2. 重要変更(認証・課金・個人情報)のmainマージ 3. 本番リリース 4. ロールバック・緊急停止(軽微なものは事後報告可)

## ブランチ・コミット
- ブランチ: feature/<チケット番号>-<概要>、fix/<番号>-<概要>
- コミットは小さく、メッセージは「何を・なぜ」
