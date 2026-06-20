#!/usr/bin/env bash
# Musignal公式サイトからOVOダッシュボード(dashboard.html/js/css)と画像アセットを取得し、
# オフラインのローカルファイルとして開けるように調整するスクリプト。
#
# 取得するファイルはMusignal/JDSound社の著作物のため、このリポジトリには含めず、
# 必要な人が自分でこのスクリプトを実行して取得する方式にしている。
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p assets/img/common

BASE="https://www.musignal.co.jp"
UA="Mozilla/5.0"

curl -sL -A "$UA" -o dashboard.html "$BASE/products/ovo/dashboard.html"
curl -sL -A "$UA" -o dashboard.js   "$BASE/products/ovo/dashboard.js"
curl -sL -A "$UA" -o dashboard.css  "$BASE/products/ovo/dashboard.css"
curl -sL -A "$UA" -o assets/img/common/favicon.png       "$BASE/assets/img/common/favicon.png"
curl -sL -A "$UA" -o assets/img/common/cancel.svg         "$BASE/assets/img/common/cancel.svg"
curl -sL -A "$UA" -o assets/img/common/logo_facebook.png  "$BASE/assets/img/common/logo_facebook.png"
curl -sL -A "$UA" -o assets/img/common/logo_twitter.png   "$BASE/assets/img/common/logo_twitter.png"
curl -sL -A "$UA" -o assets/img/common/thumb.png          "$BASE/assets/img/common/thumb.png"

# オフライン/ローカル利用向けの調整:
# - Google Tag Manager(解析タグ)の読み込みを削除
# - ヘッダーのサイト内ナビゲーション(HOME/PRODUCTS/OVO)を削除（オンライン専用リンクのため）
# - 「EQ設定を共有」ボタン(Twitter/Facebook共有)を非表示化（SNS連携前提のオンライン機能のため）
# - 画像等のパスをルート相対から相対パスに変更（file://で開けるように）
python3 - <<'PYEOF'
import re

with open("dashboard.html", encoding="utf-8") as f:
    html = f.read()

html = html.replace(
    '<link rel="icon" type="image/png" href="/assets/img/common/favicon.png">'
    '<link rel="apple-touch-icon" href="/assets/img/common/favicon.png">'
    '<meta name="description" content="JDSound社のスピーカー「OVO」の設定をWebから更新できるページです。株式会社ミューシグナルが提供します。">'
    '<meta property="og:title" content="OVOダッシュボード - 株式会社ミューシグナル">'
    '<meta property="og:description" content="JDSound社のスピーカー「OVO」の設定をWebから更新できるページです。株式会社ミューシグナルが提供します。">'
    '<script async src="https://www.googletagmanager.com/gtag/js?id=G-GNQMXPSJ1S"></script>'
    '<script>function gtag(){dataLayer.push(arguments)}window.dataLayer=window.dataLayer||[],gtag("js",new Date),gtag("config","G-GNQMXPSJ1S")</script>'
    '<style>nav.breadcrumb{margin:3px 8px;color:#777;font-family:sans-serif;font-size:80%}span.chevron{padding:0 5px;color:#ccc}</style>',

    '<link rel="icon" type="image/png" href="assets/img/common/favicon.png">'
    '<link rel="apple-touch-icon" href="assets/img/common/favicon.png">'
    '<meta name="description" content="JDSound社のスピーカー「OVO」の設定をオフラインで更新できるページです（musignal公式ダッシュボードのローカル保存版）。">'
    '<style>#peq_open_url_field{display:none}</style>',
)

html = html.replace(
    '<header><nav class="breadcrumb">'
    '<a href="/">HOME</a> <span class="chevron">&rsaquo;</span> '
    '<a href="/products/">PRODUCTS</a> <span class="chevron">&rsaquo;</span> '
    '<a href="/products/ovo/">OVO</a> <span class="chevron">&rsaquo;</span> '
    'ダッシュボード</nav></header><div class="main-contents">',

    '<div class="main-contents">',
)

html = html.replace("/assets/img/common/", "assets/img/common/")

with open("dashboard.html", "w", encoding="utf-8") as f:
    f.write(html)

with open("dashboard.css", encoding="utf-8") as f:
    css = f.read()
css = css.replace("url(/assets/img/common/thumb.png)", "url(assets/img/common/thumb.png)")
with open("dashboard.css", "w", encoding="utf-8") as f:
    f.write(css)

print("dashboard.html / dashboard.css をオフライン用に調整しました。")
PYEOF

echo "完了しました。dashboard.html をChromium系ブラウザ（Chrome/Vivaldi/Edge/Brave）で開いてください。"
