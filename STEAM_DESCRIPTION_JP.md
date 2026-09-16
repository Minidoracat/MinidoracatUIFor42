[h1]🎨 Minidoracat UI Library for B42[/h1]
[h3]By Minidoracat[/h3]

[hr][/hr]

[h2]✨ これは何？[/h2]
Minidoracat シリーズ MOD 共用の UI ライブラリです。テーマカラーパレット（ダーク／ライト）、角丸ウィンドウスキン、共用モノクロアイコン、フローティングボタン、トースト通知などの共用コンポーネントを提供します。

この MOD は[b]それ自体ではゲーム内容を一切追加しません[/b]。他の MOD が利用する基盤ライブラリであり、実際の効果は依存する MOD 次第です。

[h2]👥 誰が必要？[/h2]
[list]
[*] 他の MOD が必須アイテム（Required Items）に指定している場合のみ購読してください
[*] 依存する MOD がなければ無効のままで構いません
[/list]

[h2]🧰 提供機能（MOD 開発者向け）[/h2]
[list]
[*] [b]テーマシステム[/b]：トークン化パレット、ダーク／ライト両対応、MOD ごとに上書き可能
[*] [b]角丸スキン[/b]：エンジンネイティブ 9-slice 描画、テクスチャ欠損時は直角描画へ安全にフォールバック
[*] [b]共用ウィジェット[/b]：フローティングボタン（ドラッグ＋位置記憶）、トースト通知（MOD 間で共有スタック）
[*] [b]共用描画パーツ[/b]：依存 MOD の操作ロジックを置き換えずに組み合わせられる、ステートレスなピル・トグル・スライダー外観。テクスチャ欠損時も基本形状へ安全にフォールバックします
[*] [b]共用アイコン[/b]：20 種のモノクロ線画アイコン（サイドバー、フォルダ、ドキュメント、開閉、検索、レイヤー、ピン、地球、ロック、閉じる、位置特定、コピーなど）＋13 種の塗りつぶしシルエット（家、ドクロ、足跡、ハンドル、鶏／牛／豚／羊／鹿／ウサギ／アライグマ／ネズミ／七面鳥）。配色に合わせて着色され、アイコン素材が無い場合は呼び出し側が文字表示へフォールバックします
[*] [b]仮想リスト[/b]：大量の表（取引・オークション系 UI）は可視行のみ生成
[*] [b]バージョン管理 API[/b]：依存 MOD が必要な API リビジョンを宣言でき、更新で壊れません
[/list]

[h2]⚠️ ロード順[/h2]
この MOD は[b]依存するすべての MOD より前[/b]に読み込む必要があります（MOD リストで上に配置）。

[h2]🖥️ マルチプレイ／専用サーバー[/h2]
サーバー ini の両方に追加してください：
[list]
[*] [b]Mods=[/b] MinidoracatUIFor42
[*] [b]WorkshopItems=[/b] 3789836701
[/list]

[h2]🔗 MOD シリーズ[/h2]
[list]
[*] [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3763913359]Minidoracat MiniMap for B42[/url]
[*] [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3789836823]Minidoracat Notice Board for B42[/url]
[/list]

[h2]📋 MOD 情報[/h2]
[list]
[*] [b]Workshop ID:[/b] 3789836701
[*] [b]Mod ID:[/b] MinidoracatUIFor42
[*] [b]対応バージョン:[/b] Build 42.20.1+
[*] [b]シングル / マルチ:[/b] 両対応
[/list]

[h2]💬 フィードバック[/h2]
[list]
[*] [url=https://discord.gg/Gur2V67]Discord コミュニティ[/url]
[/list]

[h2]☕ 作者を応援[/h2]
役に立ったら、このページに 👍 と GitHub に ⭐ をお願いします。より多くのプレイヤーに届きやすくなります。
この MOD は今後もずっと無料で、ソースコードは GitHub で公開しています。気に入ったらコーヒーを一杯おごってください。支援はサーバーと MOD 開発に使います。
[url=https://ko-fi.com/minidoracat][img]https://raw.githubusercontent.com/Minidoracat/workshop-resources/refs/heads/main/badges/badge_kofi.png[/img][/url] [url=https://github.com/Minidoracat/MinidoracatUIFor42][img]https://raw.githubusercontent.com/Minidoracat/workshop-resources/refs/heads/main/badges/badge_github.png[/img][/url]

[b]#Minidoracat[/b]
