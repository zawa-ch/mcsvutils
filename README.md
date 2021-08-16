# mcsvutils

Minecraft server commandline utilities

mcsvutilsはMinecraftサーバーの管理を行うためのコマンドラインユーティリティです。

## 概要

mcsvutils (Minecraft server utilities) は、Minecraftサーバーの実行イメージ、インスタンスを管理するためのスクリプトです。  

主な機能は以下のとおりです。

- Minecraftサーバー インスタンスの管理
    - サーバーインスタンスの起動・停止
    - サーバーインスタンスへのコマンド送信
    - サーバーインスタンスの起動確認
    - サーバーインスタンスのコンソールへのアタッチ
    - サーバーインスタンスのプロファイル化
- Minecraftサーバー 実行イメージの管理
    - サーバー実行イメージのダウンロード
    - サーバー実行イメージの内部リポジトリへの登録
    - 内部リポジトリに登録された実行イメージを使用したサーバインスタンスの起動
    - Spigot/CraftBukkitサーバーのビルド(試験的)

## 依存パッケージ

- bash
- sudo
- wget
- curl
- jq
- screen
