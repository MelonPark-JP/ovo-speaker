# OVO オフライン設定アプリ

このフォルダには2種類のOVO設定ツールがあります。

| ツール | 必要環境 | 特徴 |
|---|---|---|
| `dashboard.html`（`fetch_official_dashboard.sh`で取得する公式ダッシュボードのローカル保存版） | Chrome / Vivaldi / Edge / Brave 等のChromium系ブラウザ（Web MIDI対応） | 5バンドイコライザやPro専用設定まで含めたフル機能 |
| `ovo_cli.py`（コマンドラインツール） | Linuxの`amidi`コマンド（alsa-utils、追加インストール不要） | **Firefoxなどブラウザを使わず**、ターミナルから直接MIDIで設定変更 |

Firefoxは Web MIDI API に対応していないため `dashboard.html` は動作しません。その場合は `ovo_cli.py` を使ってください。

## 開発者向け: pre-commitフック

ベンダーファイルや秘密情報の誤コミットを防ぐため`.pre-commit-config.yaml`を用意しています。cloneしたら一度だけ以下を実行してください。

```
pip install pre-commit
pre-commit install
```

任意で、AIによるコードレビューCLI [open-code-review](https://github.com/alibaba/open-code-review)（`ocr`コマンド）も手動で使えます。pre-commitには組み込んでいません（コミットごとにLLM呼び出しが発生するコストを避けるため）。

```
ocr config provider   # 初回のみ、対話的にLLMプロバイダ/APIキーを設定
ocr review            # 作業中の変更をレビュー
```

## コマンドラインツール（ovo_cli.py）の使い方

ターミナルから対話メニューで使う場合:

```
python3 ovo_cli.py
```

スクリプトや`!`コマンドなど対話入力ができない環境からは、サブコマンドで一発実行できます（`python3 ovo_cli.py -h` で一覧表示）:

```
python3 ovo_cli.py status                 # 現在の設定を表示
python3 ovo_cli.py led-brightness 5       # LED輝度を5に設定
python3 ovo_cli.py local-volume on        # LOCAL VOLUMEをON
python3 ovo_cli.py lr-setting 2           # L/Rを「左のみ」に設定
```

OVOをデジタル入力モードでUSB接続した状態で実行すると、`amidi -l` でOVOのMIDIポートを自動検出します。対話メニューでは以下を設定できます。

- LOCAL VOLUME（ON/OFF・レベル）、ANALOG VOLUMEレベル
- AUTO GAIN、BASS BOOST、HIGH BOOST
- L/R SETTING（通常/反転/左のみ/右のみ）
- LOW POWER、PLAYER CONTROL
- LED輝度、LEDパターン
- イコライザ(PEQ)のON/OFF

**注意:** 5バンドイコライザの各バンド（ゲイン/周波数/Q）の数値編集やPro専用設定、コラボモデル固有設定は`ovo_cli.py`には含まれていません。これらが必要な場合は`dashboard.html`をChromium系ブラウザで使用してください。

---

# OVOダッシュボード（公式のローカル保存版）

JDSound社製USBデジタルスピーカー「OVO」の設定ページを、インターネット接続なしで使えるようにローカルに保存して使う仕組みです。

元になっているのは Musignal 株式会社が公開している公式サポートページ（OVOダッシュボード）です。
https://www.musignal.co.jp/products/ovo/dashboard.html

## これは何か

OVO本体とブラウザの通信は **Web MIDI API** を使ったローカル通信のみで行われており、サーバーへの問い合わせは一切発生しません。そのため公式ページのHTML/CSS/JSをそのままローカルに保存すれば、オフラインでも全く同じ設定操作ができます。

**注意:** `dashboard.html`/`dashboard.js`/`dashboard.css`/`assets/`はMusignal/JDSound社の著作物のため、このリポジトリには含まれていません（`.gitignore`で除外）。代わりに `fetch_official_dashboard.sh` を実行すると、公式サイトから取得した上でオフライン用に以下を調整します。

- Google Tag Manager（解析タグ）の読み込みを削除
- ヘッダーの「HOME / PRODUCTS / OVO」というサイト内ナビゲーション（オンラインの公式サイトへのリンク）を削除
- 「EQ設定を共有」ボタンとTwitter/Facebookへの共有機能を非表示化（SNS連携が前提のオンライン機能のため）
- 画像等のパスをルート相対から相対パスに変更（`file://`で開けるように）

設定そのものに関わる機能（音量・LED・5バンドイコライザ・L/R設定・Pro専用設定など）は元のまま変更していません。

## 必要環境

- **Web MIDI APIに対応したブラウザ**（Google Chrome、Microsoft Edge、Brave など Chromium系ブラウザ）
- Firefox・Safari は Web MIDI に対応していないため使用できません（公式ページの注意書きより。代わりに`ovo_cli.py`を使ってください）
- OVO本体を **デジタル入力モード** でUSB接続していること（アナログ入力モードではMIDI通信ができません）
- OVOのファームウェアはできるだけ最新の状態にしておくことを推奨します

## 使い方

1. `./fetch_official_dashboard.sh` を実行して公式ダッシュボードを取得・調整する
2. OVOをデジタル入力用のmicroB端子でPCにUSB接続する
3. `dashboard.html` をChrome等のブラウザでダブルクリックして開く
4. 「MIDIデバイスへのアクセスを許可しますか」のようなダイアログが出たら許可する
5. ページの「状態」欄が接続済みの表示になれば、音量・LED・イコライザ・L/R設定などをこれまでと同じ画面で変更できます

`file://` で開いた際にうまく動作しない場合は、このフォルダで以下を実行し、`http://localhost:8000/dashboard.html` を開く方法も試してください。

```
python3 -m http.server 8000
```

## 注意点

- `fetch_official_dashboard.sh`はMusignal公式サイトの現時点（2026年6月確認）のページ構造に合わせて作っています。同社がページ内容を更新した場合、スクリプトの調整(文字列置換)が効かなくなる可能性があります。
