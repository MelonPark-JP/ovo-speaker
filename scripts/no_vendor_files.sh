#!/usr/bin/env bash
# Musignal/JDSound社のベンダーファイル（dashboard.html/js/css, assets/）が
# 誤ってコミットされるのを防ぐためのpre-commitフック用チェックスクリプト。
set -euo pipefail

matches=$(git diff --cached --name-only | grep -E '^(dashboard\.(html|js|css)$|assets/)' || true)

if [ -n "$matches" ]; then
  echo "コミットをブロックしました。以下はMusignal/JDSound社の著作物であり、公開リポジトリにコミットしないでください:"
  echo "$matches"
  echo "(.gitignoreで除外されています。fetch_official_dashboard.shで取得したローカル専用ファイルです)"
  exit 1
fi
