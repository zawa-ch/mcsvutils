#! /bin/bash

: <<- __License
MIT License

Copyright (c) 2020,2021 zawa-ch.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
__License

version()
{
	cat <<- __EOF
	mcsvutils - Minecraft server commandline utilities
	version 0.4.0 2021-08-16
	Copyright 2020,2021 zawa-ch.
	__EOF
}

SUBCOMMANDS=("version" "usage" "help" "check" "profile" "server" "image" "spigot")

usage()
{
	cat <<- __EOF
	使用法: $0 <サブコマンド> ...
	使用可能なサブコマンド: ${SUBCOMMANDS[@]}
	__EOF
}

help()
{
	cat <<- __EOF
	  profile  サーバーインスタンスのプロファイルを管理する
	  server   サーバーインスタンスを管理する
	  image    Minecraftサーバーイメージを管理する
	  spigot   CraftBukkit/Spigotサーバーイメージを管理する
	  check    このスクリプトの動作要件を満たしているかチェックする
	  version  現在のバージョンを表示して終了
	  usage    使用法を表示する
	  help     このヘルプを表示する

	各コマンドの詳細なヘルプは各コマンドに--helpオプションを付けてください。

	すべてのサブコマンドに対し、次のオプションが使用できます。
	  --help | -h 各アクションのヘルプを表示する
	  --usage     各アクションの使用法を表示する
	  --          以降のオプションのパースを行わない
	__EOF
}

## Const -------------------------------
readonly VERSION_MANIFEST_LOCATION='https://launchermeta.mojang.com/mc/game/version_manifest.json'
readonly SPIGOT_BUILDTOOLS_LOCATION='https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar'
readonly RESPONCE_POSITIVE=0
readonly RESPONCE_NEGATIVE=1
readonly RESPONCE_ERROR=2
readonly DATA_VERSION=2
readonly REPO_VERSION=1
SCRIPT_LOCATION="$(dirname "$(readlink -f "$0")")" || {
	echo "mcsvutils: [E] スクリプトが置かれているディレクトリを検出できませんでした。" >&2
	exit $RESPONCE_ERROR
}
readonly SCRIPT_LOCATION
## -------------------------------------

## Variables ---------------------------
# 一時ディレクトリ設定
# 一時ディレクトリの場所を設定します。
# 通常は"/tmp"で問題ありません。
[ -z "$TEMP" ] && readonly TEMP="/tmp"
# Minecraftバージョン管理ディレクトリ設定
# Minecraftバージョンの管理を行うためのディレクトリを設定します。
[ -z "$MCSVUTILS_IMAGEREPOSITORY_LOCATION" ] && readonly MCSVUTILS_IMAGEREPOSITORY_LOCATION="$SCRIPT_LOCATION/versions"
## -------------------------------------

echo_invalid_flag()
{
	echo "mcsvutils: [W] 無効なオプション $1 が指定されています" >&2
	echo "通常の引数として読み込ませる場合は先に -- を使用してください" >&2
}

oncheckfail()
{
	cat >&2 <<- __EOF
	mcsvutils: [E] 動作要件のチェックに失敗しました。必要なパッケージがインストールされているか確認してください。
	    このスクリプトを実行するために必要なソフトウェアは以下のとおりです:
	    bash sudo wget curl jq screen
	__EOF
}

# エラー出力にログ出力
# $1..: echoする内容
echoerr()
{
	echo "$*" >&2
}

# 指定ユーザーでコマンドを実行
# $1: ユーザー
# $2..: コマンド
as_user()
{
	local user="$1"
	shift
	if [ "$(whoami)" = "$user" ]; then
		bash -c -- "$*"
	else
		sudo -sHu "$user" "$@"
	fi
}

# 指定ユーザーでスクリプトを実行
# $1: ユーザー
# note: 標準入力にコマンドを流すことでスクリプトを実行できる
as_user_script()
{
	local user="$1"
	if [ "$(whoami)" = "$user" ]; then
		bash
	else
		sudo -u "$user" -sH
	fi
}

# スクリプトの動作要件チェック
check()
{
	check_installed()
	{
		local result_out
		result_out="$(bash -c "$1 --version" 2>&1 >/dev/null)" || bash -c "$1 --help" >/dev/null 2>/dev/null || {
			local result=$?
			echo "$result_out" >&2
			return $result
		}
	}
	local RESULT=0
	check_installed sudo || RESULT=$RESPONCE_NEGATIVE
	check_installed wget || RESULT=$RESPONCE_NEGATIVE
	check_installed curl || RESULT=$RESPONCE_NEGATIVE
	check_installed jq || RESULT=$RESPONCE_NEGATIVE
	check_installed screen || RESULT=$RESPONCE_NEGATIVE
	return $RESULT
}

# Minecraftバージョンマニフェストファイルの取得
VERSION_MANIFEST=
fetch_mcversions() { VERSION_MANIFEST=$(curl -s "$VERSION_MANIFEST_LOCATION") || { echoerr "mcsvutils: [E] Minecraftバージョンマニフェストファイルのダウンロードに失敗しました"; return $RESPONCE_ERROR; } }

profile_data=""

# プロファイルデータを開く
# 指定されたプロファイルデータを開き、 profile_data 変数に格納する
# プロファイルデータの指定がなかった場合、標準入力から取得する
profile_open()
{
	[ $# -lt 1 ] && { profile_data="$(jq -c '.')"; return; }
	local profile_file="$1"
	[ -e "$profile_file" ] || { echoerr "mcsvutils: [E] 指定されたファイル $profile_file が見つかりません"; return $RESPONCE_ERROR; }
	profile_data="$(jq -c '.' "$profile_file")"
	return
}

profile_get_version() { { echo "$profile_data" | jq -r ".version | numbers"; } || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; } }
profile_get_servicename() { { echo "$profile_data" | jq -r ".servicename | strings"; } || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; } }
profile_get_imagetag() { { echo "$profile_data" | jq -r ".imagetag | strings"; } || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; } }
profile_get_executejar() { { echo "$profile_data" | jq -r ".executejar | strings"; } || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; } }
profile_get_options() { { echo "$profile_data" | jq -r ".options[]"; } || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; } }
profile_get_arguments() { { echo "$profile_data" | jq -r ".arguments[]"; } || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; } }
profile_get_cwd() { { echo "$profile_data" | jq -r ".cwd | strings"; } || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; } }
profile_get_jre() { { echo "$profile_data" | jq -r ".jre | strings"; } || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; } }
profile_get_owner() { { echo "$profile_data" | jq -r ".owner | strings"; } || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; } }
profile_check_integrity()
{
	local version; version="$(profile_get_version)" || return $RESPONCE_NEGATIVE
	[ "$version" != "$DATA_VERSION" ] && { echoerr "mcsvutils: [E] 対応していないプロファイルのバージョン($version)です"; return $RESPONCE_NEGATIVE; }
	local servicename; servicename="$(profile_get_servicename)" || return $RESPONCE_NEGATIVE
	[ -z "$servicename" ] && { echoerr "mcsvutils: [E] 必要な要素 servicename がありません"; return $RESPONCE_NEGATIVE; }
	local imagetag; imagetag="$(profile_get_imagetag)" || return $RESPONCE_NEGATIVE
	local executejar; executejar="$(profile_get_executejar)" || return $RESPONCE_NEGATIVE
	{ { [ -z "$imagetag" ] && [ -z "$executejar" ]; } || { [ -n "$imagetag" ] && [ -n "$executejar" ]; } } && { echoerr "mcsvutils: [E] imagetag と executejar の要素はどちらかひとつだけが存在する必要があります"; return $RESPONCE_ERROR; }
	return $RESPONCE_POSITIVE
}

repository_is_exist() { [ -e "$MCSVUTILS_IMAGEREPOSITORY_LOCATION/repository.json" ]; }
repository_open() { jq -c '.' "$MCSVUTILS_IMAGEREPOSITORY_LOCATION/repository.json"; }
repository_get_version() { jq -r ".version | numbers" || return $RESPONCE_ERROR; }
repository_find_image_keys_fromname()
{
	local item=$1
	jq -c ".images | map_values(select(.name == \"$item\")) | keys"
}
repository_is_exist_image()
{
	local item=$1
	[ "$(jq -r ".images | has(\"$item\")")" == "true" ]
}
repository_get_image()
{
	local item=$1
	jq -c ".images.\"$item\""
}
repository_image_get_name() { jq -r ".name"; }
repository_image_get_path() { jq -r ".path"; }
repository_check_integrity()
{
	local data
	data="$(jq -c '.')" || { echoerr "mcsvutils: [E] イメージリポジトリのデータは有効なJSONではありません"; return $RESPONCE_NEGATIVE; }
	local version; version="$(echo "$data" | repository_get_version)" || { echoerr "mcsvutils: [E] イメージリポジトリのバージョンを読み取れませんでした"; return $RESPONCE_NEGATIVE; }
	[ "$version" -ne "$REPO_VERSION" ] && { echoerr "mcsvutils: [E] イメージリポジトリのバージョンの互換性がありません"; return $RESPONCE_NEGATIVE; }
	return $RESPONCE_POSITIVE
}

# Subcommands --------------------------
action_profile()
{
	# Usage/Help ---------------------------
	local SUBCOMMANDS=("help" "info" "create" "upgrade")
	usage()
	{
		cat <<- __EOF
		使用法: $0 profile <サブコマンド>
		使用可能なサブコマンド: ${SUBCOMMANDS[@]}
		__EOF
	}
	help()
	{
		cat <<- __EOF
		profile はMinecraftサーバーのプロファイルを管理します。

		使用可能なサブコマンドは以下のとおりです。

		  help     このヘルプを表示する
		  info     プロファイルの内容を表示する
		  create   プロファイルを作成する
		  upgrade  プロファイルを新しいフォーマットにする
		__EOF
	}

	# Subcommands --------------------------
	action_profile_info()
	{
		usage()
		{
			cat <<- __EOF
			使用法: $0 profile info <プロファイル>
			__EOF
		}
		help()
		{
			cat <<- __EOF
			profile info はMinecraftサーバーのプロファイルの情報を取得します。
			プロファイルにはプロファイルデータが記述されたファイルのパスを指定します。
			ファイルの指定がなかった場合は、標準入力から読み込まれます。
			__EOF
		}
		local args=()
		local helpflag=''
		local usageflag=''
		while (( $# > 0 ))
		do
			case $1 in
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--)	shift; break;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					shift
					;;
				*)
					args=("${args[@]}" "$1")
					shift
					;;
			esac
		done
		while (( $# > 0 ))
		do
			args=("${args[@]}" "$1")
			shift
		done

		[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
		[ -n "$usageflag" ] && { usage; return; }
		if [ ${#args[@]} -gt 0 ]; then profile_open "${args[0]}" || return; else profile_open || return; fi
		profile_check_integrity || { echoerr "mcsvutils: [E] 指定されたデータは正しいプロファイルデータではありません"; return $RESPONCE_ERROR; }
		echo "サービス名: $(profile_get_servicename)"
		[ -n "$(profile_get_owner)" ] && echo "サービス所有者: $(profile_get_owner)"
		[ -n "$(profile_get_cwd)" ] && echo "作業ディレクトリ: $(profile_get_cwd)"
		[ -n "$(profile_get_imagetag)" ] && echo "呼び出しイメージ: $(profile_get_imagetag)"
		[ -n "$(profile_get_executejar)" ] && echo "実行jarファイル: $(profile_get_executejar)"
		[ -n "$(profile_get_jre)" ] && echo "Java環境: $(profile_get_jre)"
		[ -n "$(profile_get_options)" ] && echo "Java呼び出しオプション: $(profile_get_options)"
		[ -n "$(profile_get_arguments)" ] && echo "デフォルト引数: $(profile_get_arguments)"
		return $RESPONCE_POSITIVE
	}
	action_profile_create()
	{
		usage()
		{
			cat <<- __EOF
			使用法:
			$0 profile create --name <名前> --image <バージョン> [オプション]
			$0 profile create --name <名前> --execute <jarファイル> [オプション]
			__EOF
		}
		help()
		{
			cat <<- __EOF
			profile create はMinecraftサーバーのプロファイルを作成します。

			--profile | -p
			    基となるプロファイルデータのファイルを指定します。
			--input | -i
			    基となるプロファイルデータを標準入力から取得します。
			--out | -o
			    出力先ファイル名を指定します。
			    指定がなかった場合は標準出力に書き出されます。
			--name | -n (必須)
			    インスタンスの名前を指定します。
			--image | -r
			    ここで指定された名前のイメージをリポジトリ中から検索して実行します。
			    --imageオプションまたは--executeオプションのどちらかを必ずひとつ指定する必要があります。
			    また、--executeオプションと同時に使用することはできません。
			--execute | -e
			    サーバーとして実行するjarファイルを指定します。
			    --imageオプションまたは--executeオプションのどちらかを必ずひとつ指定する必要があります。
			    また、--imageオプションと同時に使用することはできません。
			--owner | -u
			    実行時のユーザーを指定します。
			--cwd
			    実行時の作業ディレクトリを指定します。
			--java
			    javaの環境を指定します。
			    このオプションを指定するとインストールされているjavaとは異なるjavaを使用することができます。
			--option
			    実行時にjreに渡すオプションを指定します。
			    複数回呼び出された場合、呼び出された順に連結されます。
			--args
			    実行時にjarに渡されるデフォルトの引数を指定します。
			    複数回呼び出された場合、呼び出された順に連結されます。
			__EOF
		}
		local args=()
		local profileflag=''
		local inputflag=''
		local outflag=''
		local nameflag=''
		local imageflag=''
		local executeflag=''
		local ownerflag=''
		local cwdflag=''
		local javaflag=''
		local optionflag=()
		local argsflag=()
		local helpflag=''
		local usageflag=''
		while (( $# > 0 ))
		do
			case $1 in
				--profile)	shift; profileflag="$1"; shift;;
				--input)	shift; inputflag="$1"; shift;;
				--out)  	shift; outflag="$1"; shift;;
				--name) 	shift; nameflag="$1"; shift;;
				--image)	shift; imageflag="$1"; shift;;
				--execute)	shift; executeflag="$1"; shift;;
				--owner)	shift; ownerflag="$1"; shift;;
				--cwd)  	shift; cwdflag="$1"; shift;;
				--java) 	shift; javaflag="$1"; shift;;
				--option)	shift; optionflag+=("$1"); shift;;
				--args) 	shift; argsflag+=("$1"); shift;;
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--)	shift; break;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					local end_of_analyze=1
					[[ "$1" =~ i ]] && { inputflag='-i'; }
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					[ "$end_of_analyze" -ne 0 ] && [[ "$1" =~ p ]] && { if [[ "$1" =~ p$ ]]; then shift; profileflag="$1"; end_of_analyze=0; else profileflag=''; fi; }
					[ "$end_of_analyze" -ne 0 ] && [[ "$1" =~ o ]] && { if [[ "$1" =~ o$ ]]; then shift; outflag="$1"; end_of_analyze=0; else outflag=''; fi; }
					[ "$end_of_analyze" -ne 0 ] && [[ "$1" =~ n ]] && { if [[ "$1" =~ n$ ]]; then shift; nameflag="$1"; end_of_analyze=0; else nameflag=''; fi; }
					[ "$end_of_analyze" -ne 0 ] && [[ "$1" =~ r ]] && { if [[ "$1" =~ r$ ]]; then shift; imageflag="$1"; end_of_analyze=0; else imageflag=''; fi; }
					[ "$end_of_analyze" -ne 0 ] && [[ "$1" =~ e ]] && { if [[ "$1" =~ e$ ]]; then shift; executeflag="$1"; end_of_analyze=0; else executeflag=''; fi; }
					[ "$end_of_analyze" -ne 0 ] && [[ "$1" =~ u ]] && { if [[ "$1" =~ u$ ]]; then shift; ownerflag="$1"; end_of_analyze=0; else ownerflag=''; fi; }
					shift
					;;
				*)
					args=("${args[@]}" "$1")
					shift
					;;
			esac
		done
		while (( $# > 0 ))
		do
			args=("${args[@]}" "$1")
			shift
		done

		[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
		[ -n "$usageflag" ] && { usage; return; }
		local result="{}"
		[ -n "$profileflag" ] && [ -n "$inputflag" ] && { echoerr "mcsvutils: [E] --profileと--inputは同時に指定できません"; return $RESPONCE_ERROR; }
		[ -n "$profileflag" ] && { { profile_open "$profileflag" && profile_check_integrity && result="$profile_data"; } || return $RESPONCE_ERROR; }
		[ -n "$inputflag" ] && { { profile_open && profile_check_integrity && result="$profile_data"; } || return $RESPONCE_ERROR; }
		[ -z "$profileflag" ] && [ -z "$inputflag" ] && [ -z "$nameflag" ] && { echoerr "mcsvutils: [E] --nameは必須です"; return $RESPONCE_ERROR; }
		result=$(echo "$result" | jq -c --argjson version "$DATA_VERSION" '.version |= $version') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		[ -n "$nameflag" ] && { result=$(echo "$result" | jq -c --arg servicename "$nameflag" '.servicename |= $servicename') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; } }
		{ [ -z "$profileflag" ] && [ -z "$inputflag" ] && [ -z "$executeflag" ] && [ -z "$imageflag" ]; } && { echoerr "mcsvutils: [E] --executeまたは--imageは必須です"; return $RESPONCE_ERROR; }
		{ [ -z "$profileflag" ] && [ -z "$inputflag" ] && [ -n "$executeflag" ] && [ -n "$imageflag" ]; } && { echoerr "mcsvutils: [E] --executeと--imageは同時に指定できません"; return $RESPONCE_ERROR; }
		[ -n "$executeflag" ] && { result=$(echo "$result" | jq -c --arg executejar "$executeflag" '.executejar |= $executejar | .imagetag |= null' ) || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; } }
		[ -n "$imageflag" ] && { result=$(echo "$result" | jq -c --arg imagetag "$imageflag" '.imagetag |= $imagetag | .executejar |= null' ) || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; } }
		local options="[]"
		[ ${#optionflag[@]} -ne 0 ] && { for item in "${optionflag[@]}"; do options=$(echo "$options" | jq -c ". + [ \"$item\" ]"); done }
		result=$(echo "$result" | jq -c --argjson options "$options" '.options |= $options') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		local arguments="[]"
		[ ${#argsflag[@]} -ne 0 ] && { for item in "${argsflag[@]}"; do arguments=$(echo "$arguments" | jq -c ". + [ \"$item\" ]"); done }
		result=$(echo "$result" | jq -c --argjson arguments "$arguments" '.arguments |= $arguments') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		if [ -n "$cwdflag" ]; then
			result=$(echo "$result" | jq -c --arg cwd "$cwdflag" '.cwd |= $cwd') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		else
			result=$(echo "$result" | jq -c '.cwd |= null') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		fi
		if [ -n "$javaflag" ]; then
			result=$(echo "$result" | jq -c --arg jre "$javaflag" '.jre |= $jre') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		else
			result=$(echo "$result" | jq -c '.jre |= null') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		fi
		if [ -n "$ownerflag" ]; then
			result=$(echo "$result" | jq -c --arg owner "$ownerflag" '.owner |= $owner') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		else
			result=$(echo "$result" | jq -c '.owner |= null') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		fi
		profile_data="$result"
		if [ -n "$outflag" ]; then
			echo "$profile_data" > "$outflag"
		else
			echo "$profile_data"
		fi
	}
	action_profile_upgrade()
	{
		usage()
		{
			cat <<- __EOF
			使用法:
			$0 profile upgrade [オプション] [プロファイル]
			__EOF
		}
		help()
		{
			cat <<- __EOF
			profile upgrade はMinecraftサーバーのプロファイルのバージョンを最新にします。
			プロファイルにはプロファイルデータが記述されたファイルのパスを指定します。
			ファイルの指定がなかった場合は、標準入力から読み込まれます。

			--out | -o
			    出力先ファイル名を指定します。
			    指定がなかった場合は標準出力に書き出されます。
			__EOF
		}
		local args=()
		local outflag=''
		local helpflag=''
		local usageflag=''
		while (( $# > 0 ))
		do
			case $1 in
				--out)  	shift; outflag="$1"; shift;;
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--)	shift; break;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					[[ "$1" =~ o ]] && { if [[ "$1" =~ o$ ]]; then shift; outflag="$1"; else outflag=''; fi; }
					shift
					;;
				*)
					args=("${args[@]}" "$1")
					shift
					;;
			esac
		done
		while (( $# > 0 ))
		do
			args=("${args[@]}" "$1")
			shift
		done

		[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
		[ -n "$usageflag" ] && { usage; return; }

		if [ "${#args[@]}" -ge 1 ]
			then { profile_open "${args[0]}" || return $RESPONCE_ERROR; }
			else { profile_open || return $RESPONCE_ERROR; }
		fi
		local version=''
		local servicename=''
		local imagetag=''
		local executejar=''
		local owner=''
		local cwd=''
		local jre=''
		local options=''
		local arguments=''
		version="$(profile_get_version)" || return $RESPONCE_ERROR
		echoerr "mcsvutils: 読み込まれたプロファイルのバージョン: $version"
		case "$version" in
			"$DATA_VERSION") {
				if profile_check_integrity
					then echoerr "mcsvutils: [W] このプロファイルはすでに最新です。更新の必要はありません。"; return $RESPONCE_NEGATIVE;
					else return $RESPONCE_ERROR;
				fi
			};;
			"1") {
				servicename=$(echo "$profile_data" | jq -r ".name | strings") || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; }
				[ -z "$servicename" ] && { echoerr "mcsvutils: [E] .name要素が空であるか、正しい型ではありません"; return $RESPONCE_ERROR; }
				executejar=$(echo "$profile_data" | jq -r ".execute | strings") || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; }
				[ -z "$executejar" ] && { echoerr "mcsvutils: [E] .execute要素が空であるか、正しい型ではありません"; return $RESPONCE_ERROR; }
				owner=$(echo "$profile_data" | jq -r ".owner | strings") || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; }
				cwd=$(echo "$profile_data" | jq -r ".cwd | strings") || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; }
				jre=$(echo "$profile_data" | jq -r ".javapath | strings") || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; }
				options=$(echo "$profile_data" | jq -c ".options") || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; }
				arguments=$(echo "$profile_data" | jq -c ".args") || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; }
			};;
			*) {
				echoerr "mcsvutils: [E] サポートされていないバージョン $version が選択されました。"
				return $RESPONCE_ERROR
			};;
		esac

		local result="{}"
		result=$(echo "$result" | jq -c --argjson version "$DATA_VERSION" '.version |= $version') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		[ -z "$servicename" ] && { echoerr "mcsvutils: [E] サービス名が空です"; return $RESPONCE_ERROR; }
		result=$(echo "$result" | jq -c --arg servicename "$servicename" '.servicename |= $servicename') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		{ [ -z "$imagetag" ] && [ -z "$executejar" ]; } && { echoerr "mcsvutils: [E] executejarとimagetagがどちらも空です"; return $RESPONCE_ERROR; }
		{ [ -n "$imagetag" ] && [ -n "$executejar" ]; } && { echoerr "mcsvutils: [E] executejarとimagetagは同時に存在できません"; return $RESPONCE_ERROR; }
		[ -n "$imagetag" ] && { result=$(echo "$result" | jq -c --arg imagetag "$imagetag" '.imagetag |= $imagetag | .executejar |= null' ) || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; } }
		[ -n "$executejar" ] && { result=$(echo "$result" | jq -c --arg executejar "$executejar" '.executejar |= $executejar | .imagetag |= null' ) || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; } }
		if [ -n "$owner" ]; then
			result=$(echo "$result" | jq -c --arg owner "$owner" '.owner |= $owner') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		else
			result=$(echo "$result" | jq -c '.owner |= null') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		fi
		if [ -n "$cwd" ]; then
			result=$(echo "$result" | jq -c --arg cwd "$cwd" '.cwd |= $cwd') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		else
			result=$(echo "$result" | jq -c '.cwd |= null') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		fi
		if [ -n "$jre" ]; then
			result=$(echo "$result" | jq -c --arg jre "$jre" '.jre |= $jre') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		else
			result=$(echo "$result" | jq -c '.jre |= null') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		fi
		result=$(echo "$result" | jq -c --argjson options "$options" '.options |= $options') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		result=$(echo "$result" | jq -c --argjson arguments "$arguments" '.arguments |= $arguments') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		profile_data="$result"
		if [ -n "$outflag" ]; then
			echo "$profile_data" > "$outflag"
		else
			echo "$profile_data"
		fi
	}

	# Analyze arguments --------------------
	local subcommand=""
	if [[ $1 =~ -.* ]] || [ "$1" = "" ]; then
		subcommand="none"
		while (( $# > 0 ))
		do
			case $1 in
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					shift
					;;
				*)	break;;
			esac
		done
	else
		for item in "${SUBCOMMANDS[@]}"
		do
			[ "$item" == "$1" ] && {
				subcommand="$item"
				shift
				break
			}
		done
	fi
	[ -z "$subcommand" ] && { echoerr "mcsvutils: [E] 無効なサブコマンドを指定しました。"; usage >&2; return $RESPONCE_ERROR; }
	{ [ "$subcommand" == "help" ] || [ -n "$helpflag" ]; } && { version; echo; usage; echo; help; return; }
	[ -n "$usageflag" ] && { usage; return; }
	[ "$subcommand" == "none" ] && { echoerr "mcsvutils: [E] サブコマンドが指定されていません。"; echoerr "$0 profile help で詳細なヘルプを表示します。"; usage >&2; return $RESPONCE_ERROR; }
	"action_profile_$subcommand" "$@"
}

action_server()
{
	# Usage/Help ---------------------------
	local SUBCOMMANDS=("help" "status" "start" "stop" "attach" "command")
	usage()
	{
		cat <<- __EOF
		使用法: $0 server <サブコマンド>
		使用可能なサブコマンド: ${SUBCOMMANDS[@]}
		__EOF
	}
	help()
	{
		cat <<- __EOF
		server はMinecraftサーバーのインスタンスを管理します。

		使用可能なサブコマンドは以下のとおりです。

		  help     このヘルプを表示する
		  status   インスタンスの状態を問い合わせる
		  start    インスタンスを開始する
		  stop     インスタンスを停止する
		  attach   インスタンスのコンソールにアタッチする
		  command  インスタンスにコマンドを送信する
		__EOF
	}

	# Minecraftコマンドを実行
	# $1: サーバー所有者
	# $2: サーバーのセッション名
	# $3..: 送信するコマンド
	dispatch_mccommand()
	{
		local owner="$1"
		shift
		local servicename="$1"
		shift
		as_user "$owner" "screen -p 0 -S $servicename -X eval 'stuff \"$*\"\015'"
	}

	# Subcommands --------------------------
	action_server_status()
	{
		usage()
		{
			cat <<- __EOF
			使用法:
			$0 server status -p <プロファイル> [オプション]
			$0 server status -n <名前> [オプション]
			__EOF
		}
		help()
		{
			cat <<- __EOF
			server status はMinecraftサーバーの状態を問い合わせます。
			コマンドの実行には名前、もしくはプロファイルのどちらかを指定する必要があります。
			いずれの指定もなかった場合は、標準入力からプロファイルを取得します。

			--profile | -p
			    インスタンスを実行するための情報を記したプロファイルの場所を指定します。
			    名前を指定していない場合のみ必須です。
			    名前を指定している場合はこのオプションを指定することはできません。
			--name | -n
			    インスタンスの名前を指定します。
			    プロファイルを指定しない場合のみ必須です。
			    プロファイルを指定している場合はこのオプションを指定することはできません。
			--owner | -u
			    実行時のユーザーを指定します。
			    このオプションを指定するとプロファイルの設定を上書きします。

			指定したMinecraftサーバーが起動している場合は $RESPONCE_POSITIVE 、起動していない場合は $RESPONCE_NEGATIVE が返されます。
			__EOF
		}
		local args=()
		local profileflag=''
		local nameflag=''
		local ownerflag=''
		local helpflag=''
		local usageflag=''
		while (( $# > 0 ))
		do
			case $1 in
				--profile) 	shift; profileflag="$1"; shift;;
				--name) 	shift; nameflag="$1"; shift;;
				--owner)	shift; ownerflag="$1"; shift;;
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--)	shift; break;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					local end_of_analyze=1
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					[ "$end_of_analyze" -ne 0 ] && [[ "$1" =~ p ]] && { if [[ "$1" =~ p$ ]]; then shift; profileflag="$1"; end_of_analyze=0; else profileflag=''; fi; }
					[ "$end_of_analyze" -ne 0 ] && [[ "$1" =~ n ]] && { if [[ "$1" =~ n$ ]]; then shift; nameflag="$1"; end_of_analyze=0; else nameflag=''; fi; }
					[ "$end_of_analyze" -ne 0 ] && [[ "$1" =~ u ]] && { if [[ "$1" =~ u$ ]]; then shift; ownerflag="$1"; end_of_analyze=0; else ownerflag=''; fi; }
					shift
					;;
				*)
					args=("${args[@]}" "$1")
					shift
					;;
			esac
		done
		while (( $# > 0 ))
		do
			args=("${args[@]}" "$1")
			shift
		done

		[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
		[ -n "$usageflag" ] && { usage; return; }
		local servicename=''
		local owner=''
		if [ -n "$nameflag" ]; then
			[ -n "$profileflag" ] && { echoerr "mcsvutils: [E] プロファイルを指定した場合、名前の指定は無効です"; return $RESPONCE_ERROR; }
			servicename=$nameflag
		else
			if [ -n "$profileflag" ]; then profile_open "$profileflag" || return; else profile_open || return; fi
			profile_check_integrity || { echoerr "mcsvutils: [E] プロファイルのロードに失敗したため、中止します"; return $RESPONCE_ERROR; }
			servicename="$(profile_get_servicename)" || return $RESPONCE_ERROR
			owner="$(profile_get_owner)" || return $RESPONCE_ERROR
		fi
		[ -z "$servicename" ] && { echoerr "mcsvctrl: [E] インスタンスの名前が指定されていません"; return $RESPONCE_ERROR; }
		[ -n "$ownerflag" ] && owner=$ownerflag
		[ -z "$owner" ] && owner="$(whoami)"
		if as_user "$owner" "screen -list \"$servicename\"" > /dev/null
		then
			echo "mcsvutils: ${servicename} は起動しています"
			return $RESPONCE_POSITIVE
		else
			echo "mcsvutils: ${servicename} は起動していません"
			return $RESPONCE_NEGATIVE
		fi
	}
	action_server_start()
	{
		usage()
		{
			cat <<- __EOF
			使用法:
			$0 server start -p <プロファイル> [オプション] [引数]
			$0 server start -n <名前> -r <バージョン> [オプション] [引数]
			$0 server start -n <名前> -e <jarファイル> [オプション] [引数]
			__EOF
		}
		help()
		{
			cat <<- __EOF
			server start はMinecraftサーバーのインスタンスを開始します。
			インスタンスの開始には名前とバージョン、もしくはプロファイルのどちらかを指定する必要があります。
			いずれの指定もなかった場合は、標準入力からプロファイルを取得します。

			--profile | -p
			    インスタンスを実行するための情報を記したプロファイルの場所を指定します。
			    名前・バージョンをともに指定していない場合のみ必須です。
			    名前・バージョンを指定している場合はこのオプションを指定することはできません。
			--name | -n
			    インスタンスの名前を指定します。
			    プロファイルを指定しない場合のみ必須です。
			    プロファイルを指定している場合はこのオプションを指定することはできません。
			--image | -r
			    ここで指定された名前のイメージをリポジトリ中から検索して実行します。
			    プロファイルを指定しない場合、--imageオプションまたは--executeオプションのどちらかを必ずひとつ指定する必要があります。
			    --executeオプションと同時に使用することはできません。
			    また、プロファイルを指定している場合はこのオプションを指定することはできません。
			--execute | -e
			    サーバーとして実行するjarファイルを指定します。
			    プロファイルを指定しない場合、--imageオプションまたは--executeオプションのどちらかを必ずひとつ指定する必要があります。
			    --imageオプションと同時に使用することはできません。
			    また、プロファイルを指定している場合はこのオプションを指定することはできません。
			--owner | -u
			    実行時のユーザーを指定します。
			    このオプションを指定するとプロファイルの設定を上書きします。
			--cwd
			    実行時の作業ディレクトリを指定します。
			    このオプションを指定するとプロファイルの設定を上書きします。
			--java
			    javaの環境を指定します。
			    この引数を指定するとインストールされているjavaとは異なるjavaを使用することができます。
			    このオプションを指定するとプロファイルの設定を上書きします。
			--option
			    実行時にjavaに渡すオプションを指定します。
			    このオプションを指定するとプロファイルの設定を上書きします。
			--attach | -a
			    インスタンスの開始時にコンソールにアタッチします。
			__EOF
		}
		local args=()
		local profileflag=''
		local nameflag=''
		local imageflag=''
		local executeflag=''
		local ownerflag=''
		local cwdflag=''
		local javaflag=''
		local optionflag=()
		local attachflag=''
		local helpflag=''
		local usageflag=''
		while (( $# > 0 ))
		do
			case $1 in
				--profile) 	shift; profileflag="$1"; shift;;
				--name) 	shift; nameflag="$1"; shift;;
				--image)	shift; imageflag="$1"; shift;;
				--execute)	shift; executeflag="$1"; shift;;
				--owner)	shift; ownerflag="$1"; shift;;
				--cwd)  	shift; cwdflag="$1"; shift;;
				--java) 	shift; javaflag="$1"; shift;;
				--option)	shift; optionflag+=("$1"); shift;;
				--attach)	attachflag='--attach'; shift;;
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--)	shift; break;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					local end_of_analyze=1
					[[ "$1" =~ a ]] && { attachflag='-a'; }
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					[ "$end_of_analyze" -ne 0 ] && [[ "$1" =~ p ]] && { if [[ "$1" =~ p$ ]]; then shift; profileflag="$1"; end_of_analyze=0; else profileflag=''; fi; }
					[ "$end_of_analyze" -ne 0 ] && [[ "$1" =~ n ]] && { if [[ "$1" =~ n$ ]]; then shift; nameflag="$1"; end_of_analyze=0; else nameflag=''; fi; }
					[ "$end_of_analyze" -ne 0 ] && [[ "$1" =~ r ]] && { if [[ "$1" =~ r$ ]]; then shift; imageflag="$1"; end_of_analyze=0; else imageflag=''; fi; }
					[ "$end_of_analyze" -ne 0 ] && [[ "$1" =~ e ]] && { if [[ "$1" =~ e$ ]]; then shift; executeflag="$1"; end_of_analyze=0; else executeflag=''; fi; }
					[ "$end_of_analyze" -ne 0 ] && [[ "$1" =~ u ]] && { if [[ "$1" =~ u$ ]]; then shift; ownerflag="$1"; end_of_analyze=0; else ownerflag=''; fi; }
					shift
					;;
				*)
					args=("${args[@]}" "$1")
					shift
					;;
			esac
		done
		while (( $# > 0 ))
		do
			args=("${args[@]}" "$1")
			shift
		done

		[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
		[ -n "$usageflag" ] && { usage; return; }
		local servicename=''
		local imagetag=''
		local executejar=''
		local options=()
		local arguments=()
		local cwd=''
		local jre=''
		local owner=''
		if [ -n "$nameflag" ] || [ -n "$imageflag" ] || [ -n "$executeflag" ]; then
			[ -n "$profileflag" ] && { echoerr "mcsvutils: [E] プロファイルを指定した場合、名前・バージョンおよびjarファイルの指定は無効です"; return $RESPONCE_ERROR; }
			servicename=$nameflag
			[ -n "$imageflag" ] && [ -n "$executeflag" ] && { echoerr "mcsvutils: [E] バージョンとjarファイルは同時に指定できません"; return $RESPONCE_ERROR; }
			[ -n "$imageflag" ] && imagetag=$imageflag
			[ -n "$executeflag" ] && executejar=$executeflag
		else
			if [ -n "$profileflag" ]; then profile_open "$profileflag" || return; else profile_open || return; fi
			profile_check_integrity || { echoerr "mcsvutils: [E] プロファイルのロードに失敗したため、中止します"; return $RESPONCE_ERROR; }
			servicename="$(profile_get_servicename)" || return $RESPONCE_ERROR
			imagetag="$(profile_get_imagetag)" || return $RESPONCE_ERROR
			executejar="$(profile_get_executejar)" || return $RESPONCE_ERROR
			for item in $(profile_get_options); do options+=("$item"); done
			for item in $(profile_get_arguments); do arguments+=("$item"); done
			cwd="$(profile_get_cwd)" || return $RESPONCE_ERROR
			jre="$(profile_get_jre)" || return $RESPONCE_ERROR
			owner="$(profile_get_owner)" || return $RESPONCE_ERROR
		fi
		[ -z "$servicename" ] && { echoerr "mcsvutils: [E] インスタンスの名前が指定されていません"; return $RESPONCE_ERROR; }
		[ -z "$imagetag" ] && [ -z "$executejar" ] && { echoerr "mcsvutils: [E] 実行するjarファイルが指定されていません"; return $RESPONCE_ERROR; }
		[ -n "$imagetag" ] && {
			local repository
			repository="$(repository_open)" || { echoerr "mcsvutils: [E] イメージリポジトリを開くことができませんでした"; return $RESPONCE_ERROR; }
			echo "$repository" | repository_check_integrity || { echoerr "mcsvutils: [E] イメージリポジトリを開くことができませんでした"; return $RESPONCE_ERROR; }
			local item
			if echo "$repository" | repository_is_exist_image "$imagetag"; then
				item="$imagetag"
			else
				local found_image
				found_image="$(echo "$repository" | repository_find_image_keys_fromname "$imagetag")"
				[ "$(echo "$found_image" | jq -r 'length')" -le 0 ] && { echoerr "mcsvutils: [E] 合致するイメージが見つかりませんでした"; return $RESPONCE_ERROR; }
				[ "$(echo "$found_image" | jq -r 'length')" -gt 1 ] && { echoerr "mcsvutils: [E] 合致するイメージが複数見つかりました、指定するためにはIDを指定してください"; return $RESPONCE_ERROR; }
				item="$(echo "$found_image" | jq -r '.[0]')"
			fi
			executejar="$(echo "$repository" | repository_get_image "${item:?}" | repository_image_get_path)"
		}
		[ "${#optionflag[@]}" -ne 0 ] && options=("${optionflag[@]}")
		[ "${#args[@]}" -ne 0 ] && arguments=("${args[@]}")
		[ -n "$cwdflag" ] && cwd=$cwdflag
		[ -n "$javaflag" ] && jre=$javaflag
		[ -n "$ownerflag" ] && owner=$ownerflag
		[ -z "$cwd" ] && cwd="./"
		[ -z "$jre" ] && jre="java"
		[ -z "$owner" ] && owner="$(whoami)"
		local invocations=()
		invocations=("${invocations[@]}" "$jre")
		[ "${#options[@]}" -ne 0 ] && invocations=("${invocations[@]}" "${options[@]}")
		invocations=("${invocations[@]}" "-jar" "$executejar")
		[ "${#arguments[@]}" -ne 0 ] && invocations=("${invocations[@]}" "${arguments[@]}")
		sudo -sHu "$owner" screen -list "$servicename" > /dev/null && { echo "mcsvutils: ${servicename} は起動済みです" >&2; return $RESPONCE_NEGATIVE; }
		if [ -z "$attachflag" ]; then
			echo "mcsvutils: $servicename を起動しています"
			(
				cd "$cwd" || { echo "mcsvutils: [E] $cwd に入れませんでした" >&2; return $RESPONCE_ERROR; }
				sudo -sHu "$owner" screen -dmS "$servicename" "${invocations[@]}"
			)
			sleep .5
			if sudo -sHu "$owner" screen -list "$servicename" > /dev/null; then
				echo "mcsvutils: ${servicename} が起動しました"
				return $RESPONCE_POSITIVE
			else
				echo "mcsvutils: [E] ${servicename} を起動できませんでした" >&2
				return $RESPONCE_ERROR
			fi
		else
			(
				cd "$cwd" || { echo "mcsvutils: [E] $cwd に入れませんでした" >&2; return $RESPONCE_ERROR; }
				sudo -sHu "$owner" screen -mS "$servicename" "${invocations[@]}"
			)
		fi
	}
	action_server_stop()
	{
		usage()
		{
			cat <<- __EOF
			使用法:
			$0 server stop -p <プロファイル> [オプション]
			$0 server stop -n <名前> [オプション]
			__EOF
		}
		help()
		{
			cat <<- __EOF
			server stop はMinecraftサーバーのインスタンスを停止します。
			インスタンスの停止には名前、もしくはプロファイルのどちらかを指定する必要があります。
			いずれの指定もなかった場合は、標準入力からプロファイルを取得します。

			--profile | -p
			    インスタンスを実行するための情報を記したプロファイルの場所を指定します。
			    名前を指定していない場合のみ必須です。
			    名前を指定している場合はこのオプションを指定することはできません。
			--name | -n
			    インスタンスの名前を指定します。
			    プロファイルを指定しない場合のみ必須です。
			    プロファイルを指定している場合はこのオプションを指定することはできません。
			--owner | -u
			    実行時のユーザーを指定します。
			    このオプションを指定するとプロファイルの設定を上書きします。
			__EOF
		}
		local args=()
		local profileflag=''
		local nameflag=''
		local ownerflag=''
		local helpflag=''
		local usageflag=''
		while (( $# > 0 ))
		do
			case $1 in
				--profile)	shift; profileflag="$1"; shift;;
				--name) 	shift; nameflag="$1"; shift;;
				--owner)	shift; ownerflag="$1"; shift;;
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--)	shift; break;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					local end_of_analyze=1
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					[ "$end_of_analyze" -ne 0 ] && [[ "$1" =~ p ]] && { if [[ "$1" =~ p$ ]]; then shift; profileflag="$1"; end_of_analyze=0; else profileflag=''; fi; }
					[ "$end_of_analyze" -ne 0 ] && [[ "$1" =~ n ]] && { if [[ "$1" =~ n$ ]]; then shift; nameflag="$1"; end_of_analyze=0; else nameflag=''; fi; }
					[ "$end_of_analyze" -ne 0 ] && [[ "$1" =~ u ]] && { if [[ "$1" =~ u$ ]]; then shift; ownerflag="$1"; end_of_analyze=0; else ownerflag=''; fi; }
					shift
					;;
				*)
					args=("${args[@]}" "$1")
					shift
					;;
			esac
		done
		while (( $# > 0 ))
		do
			args=("${args[@]}" "$1")
			shift
		done

		[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
		[ -n "$usageflag" ] && { usage; return; }
		local servicename=''
		local owner=''
		if [ -n "$nameflag" ]; then
			[ -n "$profileflag" ] && { echoerr "mcsvutils: [E] プロファイルを指定した場合、名前の指定は無効です"; return $RESPONCE_ERROR; }
			servicename=$nameflag
		else
			if [ -n "$profileflag" ]; then profile_open "$profileflag" || return; else profile_open || return; fi
			profile_check_integrity || { echoerr "mcsvutils: [E] プロファイルのロードに失敗したため、中止します"; return $RESPONCE_ERROR; }
			servicename="$(profile_get_servicename)" || return $RESPONCE_ERROR
			owner="$(profile_get_owner)" || return $RESPONCE_ERROR
		fi
		[ -z "$servicename" ] && { echoerr "mcsvctrl: [E] インスタンスの名前が指定されていません"; return $RESPONCE_ERROR; }
		[ -n "$ownerflag" ] && owner=$ownerflag
		[ -z "$owner" ] && owner="$(whoami)"
		as_user "$owner" "screen -list \"$servicename\"" > /dev/null || { echo "mcsvutils: ${servicename} は起動していません" >&2; return $RESPONCE_NEGATIVE; }
		echo "mcsvutils: ${servicename} を停止しています"
		dispatch_mccommand "$owner" "$servicename" stop
		as_user_script "$owner" <<- __EOF
		trap 'echo "mcsvutils: SIGINTを検出しました。処理は中断しますが、遅れてサービスが停止する可能性はあります…"; exit $RESPONCE_ERROR' 2
		while screen -list "$servicename" > /dev/null
		do
			sleep 1
		done
		__EOF
		if ! as_user "$owner" "screen -list \"$servicename\"" > /dev/null
		then
			echo "mcsvutils: ${servicename} が停止しました"
			return $RESPONCE_POSITIVE
		else
			echo "mcsvutils: [E] ${servicename} が停止しませんでした" >&2
			return $RESPONCE_ERROR
		fi
	}
	action_server_attach()
	{
		usage()
		{
			cat <<- __EOF
			使用法:
			$0 server attach -p <プロファイル> [オプション]
			$0 server attach -n <名前> [オプション]
			__EOF
		}
		help()
		{
			cat <<- __EOF
			server attach はMinecraftサーバーのコンソールに接続します。
			インスタンスのアタッチには名前、もしくはプロファイルのどちらかを指定する必要があります。
			いずれの指定もなかった場合は、標準入力からプロファイルを取得します。

			--profile | -p
			    インスタンスを実行するための情報を記したプロファイルの場所を指定します。
			    名前を指定していない場合のみ必須です。
			    名前を指定している場合はこのオプションを指定することはできません。
			--name | -n
			    インスタンスの名前を指定します。
			    プロファイルを指定しない場合のみ必須です。
			    プロファイルを指定している場合はこのオプションを指定することはできません。
			--owner | -u
			    実行時のユーザーを指定します。
			    このオプションを指定するとプロファイルの設定を上書きします。

			接続するコンソールはscreenで作成したコンソールです。
			そのため、コンソールの操作はscreenでのものと同じです。
			指定したMinecraftサーバーが起動していない場合は $RESPONCE_NEGATIVE が返されます。
			__EOF
		}
		local args=()
		local profileflag=''
		local nameflag=''
		local ownerflag=''
		local helpflag=''
		local usageflag=''
		while (( $# > 0 ))
		do
			case $1 in
				--profile)	shift; profileflag="$1"; shift;;
				--name) 	shift; nameflag="$1"; shift;;
				--owner)	shift; ownerflag="$1"; shift;;
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--)	shift; break;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					local end_of_analyze=1
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					[ "$end_of_analyze" -ne 0 ] && [[ "$1" =~ p ]] && { if [[ "$1" =~ p$ ]]; then shift; profileflag="$1"; end_of_analyze=0; else profileflag=''; fi; }
					[ "$end_of_analyze" -ne 0 ] && [[ "$1" =~ n ]] && { if [[ "$1" =~ n$ ]]; then shift; nameflag="$1"; end_of_analyze=0; else nameflag=''; fi; }
					[ "$end_of_analyze" -ne 0 ] && [[ "$1" =~ u ]] && { if [[ "$1" =~ u$ ]]; then shift; ownerflag="$1"; end_of_analyze=0; else ownerflag=''; fi; }
					shift
					;;
				*)
					args=("${args[@]}" "$1")
					shift
					;;
			esac
		done
		while (( $# > 0 ))
		do
			args=("${args[@]}" "$1")
			shift
		done

		[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
		[ -n "$usageflag" ] && { usage; return; }
		local servicename=''
		local owner=''
		if [ -n "$nameflag" ]; then
			[ -n "$profileflag" ] && { echoerr "mcsvutils: [E] プロファイルを指定した場合、名前の指定は無効です"; return $RESPONCE_ERROR; }
			servicename=$nameflag
		else
			if [ -n "$profileflag" ]; then profile_open "$profileflag" || return; else profile_open || return; fi
			profile_check_integrity || { echoerr "mcsvutils: [E] プロファイルのロードに失敗したため、中止します"; return $RESPONCE_ERROR; }
			servicename="$(profile_get_servicename)" || return $RESPONCE_ERROR
			owner="$(profile_get_owner)" || return $RESPONCE_ERROR
		fi
		[ -z "$servicename" ] && { echoerr "mcsvctrl: [E] インスタンスの名前が指定されていません"; return $RESPONCE_ERROR; }
		[ -n "$ownerflag" ] && owner=$ownerflag
		[ -z "$owner" ] && owner="$(whoami)"
		as_user "$owner" "screen -list \"$servicename\"" > /dev/null || { echo "mcsvutils: ${servicename} は起動していません"; return $RESPONCE_NEGATIVE; }
		as_user "$owner" "screen -r \"$servicename\""
	}
	action_server_command()
	{
		usage()
		{
			cat <<- __EOF
			使用法:
			$0 server command -p <プロファイル> [オプション] <コマンド>
			$0 server command -n <名前> [オプション] <コマンド>
			__EOF
		}
		help()
		{
			cat <<- __EOF
			server command はMinecraftサーバーにコマンドを送信します。
			インスタンスへのコマンド送信には名前、もしくはプロファイルのどちらかを指定する必要があります。
			いずれの指定もなかった場合は、標準入力からプロファイルを取得します。

			--profile | -p
			    インスタンスを実行するための情報を記したプロファイルの場所を指定します。
			    名前を指定していない場合のみ必須です。
			    名前を指定している場合はこのオプションを指定することはできません。
			--name | -n
			    インスタンスの名前を指定します。
			    プロファイルを指定しない場合のみ必須です。
			    プロファイルを指定している場合はこのオプションを指定することはできません。
			--owner | -u
			    実行時のユーザーを指定します。
			    このオプションを指定するとプロファイルの設定を上書きします。
			--cwd
			    実行時の作業ディレクトリを指定します。
			    このオプションを指定するとプロファイルの設定を上書きします。
			__EOF
		}
		local args=()
		local profileflag=''
		local nameflag=''
		local ownerflag=''
		local cwdflag=''
		local helpflag=''
		local usageflag=''
		while (( $# > 0 ))
		do
			case $1 in
				--profile)	shift; profileflag="$1"; shift;;
				--name) 	shift; nameflag="$1"; shift;;
				--owner)	shift; ownerflag="$1"; shift;;
				--cwd)  	shift; cwdflag="$1"; shift;;
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--)	shift; break;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					local end_of_analyze=1
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					[ "$end_of_analyze" -ne 0 ] && [[ "$1" =~ p ]] && { if [[ "$1" =~ p$ ]]; then shift; profileflag="$1"; end_of_analyze=0; else profileflag=''; fi; }
					[ "$end_of_analyze" -ne 0 ] && [[ "$1" =~ n ]] && { if [[ "$1" =~ n$ ]]; then shift; nameflag="$1"; end_of_analyze=0; else nameflag=''; fi; }
					[ "$end_of_analyze" -ne 0 ] && [[ "$1" =~ u ]] && { if [[ "$1" =~ u$ ]]; then shift; ownerflag="$1"; end_of_analyze=0; else ownerflag=''; fi; }
					shift
					;;
				*)
					args=("${args[@]}" "$1")
					shift
					;;
			esac
		done
		while (( $# > 0 ))
		do
			args=("${args[@]}" "$1")
			shift
		done

		[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
		[ -n "$usageflag" ] && { usage; return; }
		local servicename=''
		local cwd=''
		local owner=''
		if [ -n "$nameflag" ]; then
			[ -n "$profileflag" ] && { echoerr "mcsvutils: [E] プロファイルを指定した場合、名前の指定は無効です"; return $RESPONCE_ERROR; }
			servicename=$nameflag
		else
			if [ -n "$profileflag" ]; then profile_open "$profileflag" || return; else profile_open || return; fi
			profile_check_integrity || { echoerr "mcsvutils: [E] プロファイルのロードに失敗したため、中止します"; return $RESPONCE_ERROR; }
			servicename="$(profile_get_servicename)" || return $RESPONCE_ERROR
			owner="$(profile_get_owner)" || return $RESPONCE_ERROR
		fi
		[ -z "$servicename" ] && { echoerr "mcsvctrl: [E] インスタンスの名前が指定されていません"; return $RESPONCE_ERROR; }
		[ -n "$cwdflag" ] && cwd=$cwdflag
		[ -n "$ownerflag" ] && owner=$ownerflag
		[ -z "$cwd" ] && cwd="."
		[ -z "$owner" ] && owner="$(whoami)"
		send_command="${args[*]}"
		as_user "$owner" "screen -list \"$servicename\"" > /dev/null || { echo "mcsvutils: ${servicename} は起動していません"; return $RESPONCE_NEGATIVE; }
		local pre_log_length
		if [ "$cwd" != "" ]; then
			pre_log_length=$(as_user "$owner" "wc -l \"$cwd/logs/latest.log\"" | awk '{print $1}')
		fi
		echo "mcsvutils: ${servicename} にコマンドを送信しています..."
		echo "> $send_command"
		dispatch_mccommand "$owner" "$servicename" "$send_command"
		echo "mcsvutils: コマンドを送信しました"
		sleep .1
		echo "レスポンス:"
		as_user "$owner" "tail -n $(($(as_user "$owner" "wc -l \"$cwd/logs/latest.log\"" | awk '{print $1}') - pre_log_length)) \"$cwd/logs/latest.log\""
		return $RESPONCE_POSITIVE
	}

	# Analyze arguments --------------------
	local subcommand=""
	if [[ $1 =~ -.* ]] || [ "$1" = "" ]; then
		subcommand="none"
		while (( $# > 0 ))
		do
			case $1 in
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					shift
					;;
				*)	break;;
			esac
		done
	else
		for item in "${SUBCOMMANDS[@]}"
		do
			[ "$item" == "$1" ] && {
				subcommand="$item"
				shift
				break
			}
		done
	fi
	[ -z "$subcommand" ] && { echoerr "mcsvutils: [E] 無効なサブコマンドを指定しました。"; usage >&2; return $RESPONCE_ERROR; }
	{ [ "$subcommand" == "help" ] || [ -n "$helpflag" ]; } && { version; echo; usage; echo; help; return; }
	[ -n "$usageflag" ] && { usage; return; }
	[ "$subcommand" == "none" ] && { echoerr "mcsvutils: [E] サブコマンドが指定されていません。"; echoerr "$0 server help で詳細なヘルプを表示します。"; usage >&2; return $RESPONCE_ERROR; }
	"action_server_$subcommand" "$@"
}

action_image()
{
	# Usage/Help ---------------------------
	local SUBCOMMANDS=("help" "list" "info" "pull" "add" "remove" "update" "find" "get")
	usage()
	{
		cat <<- __EOF
		使用法: $0 image <サブコマンド>
		使用可能なサブコマンド: ${SUBCOMMANDS[@]}
		__EOF
	}
	help()
	{
		cat <<- __EOF
		image はMinecraftサーバーの実行ファイルイメージを管理します。

		使用可能なサブコマンドは以下のとおりです。

		  help    このヘルプを表示する
		  list    イメージリポジトリ内のイメージ一覧取得
		  info    イメージリポジトリ内のイメージ情報取得
		  pull    Minecraftサーバーイメージをイメージリポジトリに追加
		  add     イメージリポジトリにイメージ追加
		  remove  イメージリポジトリ内のイメージ削除
		  update  イメージリポジトリの更新
		  find    Miecraftサーバーイメージのバージョン一覧取得
		  get     Miecraftサーバーイメージの取得
		__EOF
	}

	repository_save() { local result; result="$(jq '.')" && echo "$result" > "$MCSVUTILS_IMAGEREPOSITORY_LOCATION/repository.json"; }
	repository_new()
	{
		local repository='{}'
		repository="$(echo "$repository" | jq -c --argjson version "$REPO_VERSION" '. |= { $version }')" || return
		repository="$(echo "$repository" | jq -c '.image |= { }')" || return
		mkdir -p "$MCSVUTILS_IMAGEREPOSITORY_LOCATION"
		echo "$repository" | repository_save
	}

	# Subcommands --------------------------
	action_image_list()
	{
		usage()
		{
			cat <<- __EOF
			使用法: $0 image list [オプション] [クエリ]
			__EOF
		}
		help()
		{
			cat <<- __EOF
			image list はローカルリポジトリ内に含まれるMinecraftサーバーイメージ一覧を出力します。

			クエリに正規表現を用いて結果を絞り込むことができます。
			__EOF
		}
		local args=()
		local helpflag=''
		local usageflag=''
		while (( $# > 0 ))
		do
			case $1 in
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--)	shift; break;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					shift
					;;
				*)
					args=("${args[@]}" "$1")
					shift
					;;
			esac
		done
		while (( $# > 0 ))
		do
			args=("${args[@]}" "$1")
			shift
		done

		[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
		[ -n "$usageflag" ] && { usage; return; }

		repository_is_exist || { echoerr "mcsvutils: 対象となるイメージが存在しません"; return $RESPONCE_NEGATIVE; }
		local repository
		repository="$(repository_open)"
		echo "$repository" | repository_check_integrity || return $RESPONCE_ERROR
		local query_text
		if [ ${#args[@]} -ne 0 ]; then
			query_text="false"
			for search_query in "${args[@]}"
			do
				query_text="$query_text or test( \"$search_query\" )"
			done
		else
			query_text="true"
		fi
		local result
		mapfile -t result < <(echo "$repository" | jq -r ".images[].name | select( $query_text )")
		if [ ${#result[@]} -ne 0 ]; then
			for item in "${result[@]}"
			do
				echo "$item"
			done
			return $RESPONCE_POSITIVE
		else
			echoerr "mcsvutils: 対象となるイメージが存在しません"
			return $RESPONCE_NEGATIVE
		fi
	}
	action_image_info()
	{
		usage()
		{
			cat <<- __EOF
			使用法: $0 image info <イメージ>
			__EOF
		}
		help()
		{
			cat <<- __EOF
			image info はローカルリポジトリ内に含まれるMinecraftサーバーイメージの情報を出力します。
			__EOF
		}
		local args=()
		local helpflag=''
		local usageflag=''
		while (( $# > 0 ))
		do
			case $1 in
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--)	shift; break;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					shift
					;;
				*)
					args=("${args[@]}" "$1")
					shift
					;;
			esac
		done
		while (( $# > 0 ))
		do
			args=("${args[@]}" "$1")
			shift
		done

		[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
		[ -n "$usageflag" ] && { usage; return; }

		[ ${#args[@]} -lt 1 ] && { echoerr "mcsvutils: [E] イメージを指定してください"; return $RESPONCE_ERROR; }
		[ ${#args[@]} -gt 1 ] && { echoerr "mcsvutils: [E] 引数が多すぎます"; return $RESPONCE_ERROR; }

		repository_is_exist || { echoerr "mcsvutils: 対象となるイメージが存在しません"; return $RESPONCE_NEGATIVE; }
		local repository
		repository="$(repository_open)"
		echo "$repository" | repository_check_integrity || return $RESPONCE_ERROR

		local found=1

		echo "$repository" | repository_is_exist_image "${args[0]}" && {
			found=0
			echoerr "mcsvutils: 一致するID"
			echo "ID: ${args[0]}"
			local image
			image="$(echo "$repository" | repository_get_image "${args[0]}")"
			echo "  名前: $(echo "$image" | repository_image_get_name)"
			echo "  jarファイルのパス: $(echo "$image" | repository_image_get_path)"
		}

		local result_image
		result_image="$(echo "$repository" | repository_find_image_keys_fromname "${args[0]}")"
		local result_image_count
		result_image_count="$(echo "$result_image" | jq -r 'length')"
		[ "$result_image_count" -gt 0 ] && {
			found=0
			echoerr "mcsvutils: 一致する名前 (${result_image_count}件の項目)"
			for item in $(echo "$result_image" | jq -r '.[]')
			do
				echo "ID: $item"
				local image
				image="$(echo "$repository" | repository_get_image "$item")"
				echo "  名前: $(echo "$image" | repository_image_get_name)"
				echo "  jarファイルのパス: $(echo "$image" | repository_image_get_path)"
			done
		}

		if [ $found ]; then
			return $RESPONCE_POSITIVE
		else
			echoerr "mcsvutils: 対象となるイメージが存在しません"
			return $RESPONCE_NEGATIVE
		fi
	}
	action_image_pull()
	{
		usage()
		{
			cat <<- __EOF
			使用法:
			$0 image pull [オプション] <バージョン>
			$0 image pull [オプション] --latest
			__EOF
		}
		help()
		{
			cat <<- __EOF
			image pull はMinecraftサーバーイメージをダウンロードし、リポジトリに追加します。

			  --name | -n
			    リポジトリに登録する際の名前を指定します。
			  --latest
			    最新のリリースビルドをカタログから検出し、選択します。
			    このオプションが指定されている場合、バージョンの指定は無効です。
			__EOF
		}
		local args=()
		local nameflag=''
		local latestflag=''
		local helpflag=''
		local usageflag=''
		while (( $# > 0 ))
		do
			case $1 in
				--name) 	shift; nameflag="$1"; shift;;
				--latest)	latestflag='--latest'; shift;;
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--)	shift; break;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					local end_of_analyze=1
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					[ "$end_of_analyze" -ne 0 ] && [[ "$1" =~ n ]] && { if [[ "$1" =~ n$ ]]; then shift; nameflag="$1"; end_of_analyze=0; else nameflag=''; fi; }
					shift
					;;
				*)
					args=("${args[@]}" "$1")
					shift
					;;
			esac
		done
		while (( $# > 0 ))
		do
			args=("${args[@]}" "$1")
			shift
		done

		[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
		[ -n "$usageflag" ] && { usage; return; }

		fetch_mcversions || return

		local selected_version
		if [ -n "$latestflag" ]; then
			[ ${#args[@]} -ge 1 ] && { echoerr "mcsvutils: [W] --latestフラグが付いているため、バージョンの指定は無効です"; }
			local latest
			latest="$(echo "$VERSION_MANIFEST" | jq -r '.latest.release')"
			echo "mcsvutils: 最新のバージョン $latest が選択されました"
			selected_version="$(echo "$VERSION_MANIFEST" | jq -c ".versions[] | select( .id == \"$latest\" )")"
		else
			[ ${#args[@]} -lt 1 ] && { echoerr "mcsvutils: [E] ダウンロードするMinecraftのバージョンを指定する必要があります"; return $RESPONCE_ERROR; }
			selected_version="$(echo "$VERSION_MANIFEST" | jq -c ".versions[] | select( .id == \"${args[0]}\" )")"
		fi
		[ -z "$selected_version" ] && { echoerr "mcsvutils: 指定されたバージョンは見つかりませんでした"; return $RESPONCE_ERROR; }
		echo "mcsvutils: $(echo "$selected_version" | jq -r '.id') のカタログをダウンロードしています..."
		selected_version=$(curl "$(echo "$selected_version" | jq -r '.url')") || { echoerr "mcsvutils: [E] カタログのダウンロードに失敗しました"; return $RESPONCE_ERROR; }
		local dl_data
		local dl_sha1
		dl_data=$(echo "$selected_version" | jq -r '.downloads.server.url')
		dl_sha1=$(echo "$selected_version" | jq -r '.downloads.server.sha1')
		local destination
		destination="$(basename "$dl_data")"

		local work_dir
		work_dir="$TEMP/mcsvutils-$(cat /proc/sys/kernel/random/uuid)"
		(
			mkdir -p "$work_dir" || { echoerr "mcsvutils: [E] 作業用ディレクトリを作成できませんでした"; return $RESPONCE_ERROR; }
			cd "$work_dir" || { echoerr "mcsvutils: [E] 作業用ディレクトリに入れませんでした"; return $RESPONCE_ERROR; }
			echo "mcsvutils: データをダウンロードしています..."
			wget "$dl_data" -O "$destination" || { echoerr "mcsvutils: [E] データのダウンロードに失敗しました"; return $RESPONCE_ERROR; }
			if [ "$(sha1sum "$destination" | awk '{print $1}')" = "$dl_sha1" ]; then
				echo "mcsvutils: データのダウンロードが完了しました"
				return $RESPONCE_POSITIVE
			else
				echoerr "mcsvutils: [W] データのダウンロードが完了しましたが、チェックサムが一致しませんでした"
				return $RESPONCE_ERROR
			fi
		) || return

		local repository
		repository_is_exist || repository_new || { echoerr "mcsvutils: [E] リポジトリの作成に失敗しました"; return $RESPONCE_ERROR; }
		repository="$(repository_open)"
		echo "$repository" | repository_check_integrity || { echoerr "mcsvutils: [E] リポジトリを正しく読み込めませんでした"; return $RESPONCE_ERROR; }

		local id
		while :
		do
			id="$(cat /proc/sys/kernel/random/uuid)"
			echo "$repository" | repository_is_exist_image "$id" || break
		done

		(
			cd "$work_dir" || { echoerr "mcsvutils: [E] 作業用ディレクトリに入れませんでした"; return $RESPONCE_ERROR; }
			mkdir -p "$MCSVUTILS_IMAGEREPOSITORY_LOCATION/$id"
			cp -n "$destination" "$MCSVUTILS_IMAGEREPOSITORY_LOCATION/$id/" || { echoerr "mcsvutils: [E] ファイルのコピーに失敗しました。"; rm -rf "${MCSVUTILS_IMAGEREPOSITORY_LOCATION:?}/${id:?}"; return $RESPONCE_ERROR; }
		) || return
		rm -rf "${work_dir:?}"

		local jar_path
		jar_path="$MCSVUTILS_IMAGEREPOSITORY_LOCATION/$id/$(basename "$destination")"
		[ -z "$nameflag" ] && nameflag="${args[0]}"
		repository="$(echo "$repository" | jq --argjson data "{ \"name\": \"$nameflag\", \"path\": \"$jar_path\" }" ".images.\"$id\" |= \$data")" || { [ -e "${MCSVUTILS_IMAGEREPOSITORY_LOCATION:?}/${id:?}" ] && rm -rf "${MCSVUTILS_IMAGEREPOSITORY_LOCATION:?}/${id:?}"; return $RESPONCE_ERROR; }
		echo "$repository" | repository_save || return $RESPONCE_ERROR
		echoerr "mcsvutils: 操作は成功しました"
		echo "ID: $id"
		echo "名前: $nameflag"
		echo "jarファイルのパス: $jar_path"
		return $RESPONCE_POSITIVE
	}
	action_image_add()
	{
		usage()
		{
			cat <<- __EOF
			使用法: $0 image add [オプション] <Minecraftサーバーイメージjar>
			__EOF
		}
		help()
		{
			cat <<- __EOF
			image add はローカルリポジトリ内にMinecraftサーバーイメージを追加します。

			  --name | -n
			    イメージの名前を指定します。
			  --copy
			    --copy, --link, --nocopyでサーバーイメージの扱いを変更します。
			    管理ディレクトリにファイルをコピーします。(デフォルト)
			  --link | l
			    --copy, --link, --nocopyでサーバーイメージの扱いを変更します。
			    管理ディレクトリにハードリンクを作成します。
			  --no-copy
			    --copy, --link, --nocopyでサーバーイメージの扱いを変更します。
			    コピーを行わず、指定されたパスを登録します。(非推奨)
			__EOF
		}
		local args=()
		local nameflag=''
		local copyflag=''
		local linkflag=''
		local nocopyflag=''
		local helpflag=''
		local usageflag=''
		while (( $# > 0 ))
		do
			case $1 in
				--name) 	shift; nameflag="$1"; shift;;
				--copy) 	copyflag="--copy"; shift;;
				--link) 	linkflag="--link"; shift;;
				--no-copy)	nocopyflag="--no-copy"; shift;;
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--)	shift; break;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					local end_of_analyze=1
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					[[ "$1" =~ l ]] && { linkflag='-l'; }
					[ "$end_of_analyze" -ne 0 ] && [[ "$1" =~ n ]] && { if [[ "$1" =~ n$ ]]; then shift; nameflag="$1"; end_of_analyze=0; else nameflag=''; fi; }
					shift
					;;
				*)
					args=("${args[@]}" "$1")
					shift
					;;
			esac
		done
		while (( $# > 0 ))
		do
			args=("${args[@]}" "$1")
			shift
		done

		[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
		[ -n "$usageflag" ] && { usage; return; }

		[ ${#args[@]} -lt 1 ] && { echoerr "mcsvutils: [E] ファイルを指定してください"; return $RESPONCE_ERROR; }
		[ ${#args[@]} -gt 1 ] && { echoerr "mcsvutils: [E] 引数が多すぎます"; return $RESPONCE_ERROR; }
		{ [ -n "$copyflag" ] && [ -n "$linkflag" ]; } && { echoerr "mcsvutils: [E] --copy と --link は同時に指定できません"; return $RESPONCE_ERROR; }
		{ [ -n "$linkflag" ] && [ -n "$nocopyflag" ]; } && { echoerr "mcsvutils: [E] --linkflag と --no-copy は同時に指定できません"; return $RESPONCE_ERROR; }
		{ [ -n "$nocopyflag" ] && [ -n "$copyflag" ]; } && { echoerr "mcsvutils: [E] --copy と --no-copy は同時に指定できません"; return $RESPONCE_ERROR; }

		[ -e "${args[0]}" ] || { echoerr "mcsvutils: [E] ${args[0]} が見つかりません"; return $RESPONCE_ERROR; }
		[ -f "${args[0]}" ] || { echoerr "mcsvutils: [E] ${args[0]} はファイルではありません"; return $RESPONCE_ERROR; }

		local repository
		repository_is_exist || repository_new || { echoerr "mcsvutils: [E] リポジトリの作成に失敗しました"; return $RESPONCE_ERROR; }
		repository="$(repository_open)"
		echo "$repository" | repository_check_integrity || { echoerr "mcsvutils: [E] リポジトリを正しく読み込めませんでした"; return $RESPONCE_ERROR; }

		local id
		while :
		do
			id="$(cat /proc/sys/kernel/random/uuid)"
			echo "$repository" | repository_is_exist_image "$id" || break
		done

		local jar_path
		if [ -n "$linkflag" ]; then
			mkdir -p "$MCSVUTILS_IMAGEREPOSITORY_LOCATION/$id"
			ln "${args[0]}" "$MCSVUTILS_IMAGEREPOSITORY_LOCATION/$id/" || { echoerr "mcsvutils: [E] ファイルのリンク作成に失敗しました。"; rm -rf "${MCSVUTILS_IMAGEREPOSITORY_LOCATION:?}/${id:?}"; return $RESPONCE_ERROR; }
			jar_path="$MCSVUTILS_IMAGEREPOSITORY_LOCATION/$id/$(basename "${args[0]}")"
		elif [ -n "$nocopyflag" ]; then
			jar_path="$(cd "$(dirname "${args[0]}")" || return $RESPONCE_ERROR; pwd)/${args[0]}" || { echoerr "mcsvutils: [E] ファイルの取得に失敗しました。"; return $RESPONCE_ERROR; }
		else
			mkdir -p "$MCSVUTILS_IMAGEREPOSITORY_LOCATION/$id"
			cp -n "${args[0]}" "$MCSVUTILS_IMAGEREPOSITORY_LOCATION/$id/" || { echoerr "mcsvutils: [E] ファイルのコピーに失敗しました。"; rm -rf "${MCSVUTILS_IMAGEREPOSITORY_LOCATION:?}/${id:?}"; return $RESPONCE_ERROR; }
			jar_path="$MCSVUTILS_IMAGEREPOSITORY_LOCATION/$id/$(basename "${args[0]}")"
		fi

		repository="$(echo "$repository" | jq --argjson data "{ \"name\": \"$nameflag\", \"path\": \"$jar_path\" }" ".images.\"$id\" |= \$data")" || { [ -e "${MCSVUTILS_IMAGEREPOSITORY_LOCATION:?}/${id:?}" ] && rm -rf "${MCSVUTILS_IMAGEREPOSITORY_LOCATION:?}/${id:?}"; return $RESPONCE_ERROR; }
		echo "$repository" | repository_save || return $RESPONCE_ERROR
		echoerr "mcsvutils: 操作は成功しました"
		echo "ID: $id"
		echo "名前: $nameflag"
		echo "jarファイルのパス: $jar_path"
		return $RESPONCE_POSITIVE
	}
	action_image_remove()
	{
		usage()
		{
			cat <<- __EOF
			使用法: $0 image remove [オプション] <クエリ>
			__EOF
		}
		help()
		{
			cat <<- __EOF
			image remove はローカルリポジトリ内からMinecraftサーバーイメージを削除します。
			削除する対象をクエリで指定します。

			  --id | -i
			    クエリがID指定であることをマークします。
			  --name | -n
			    クエリが名前指定であることをマークします。
			  --quiet | -q
			    削除される項目が複数ある場合でも、確認を行わず削除します。
			  --no-delete
			    管理ディレクトリからのデータの削除を行わず、リポジトリ上の項目の更新のみを行います。(非推奨)
			__EOF
		}
		local args=()
		local idflag=''
		local nameflag=''
		local quietflag=''
		local nocopyflag=''
		local helpflag=''
		local usageflag=''
		while (( $# > 0 ))
		do
			case $1 in
				--id)       	idflag="--id"; shift;;
				--name)     	nameflag="--name"; shift;;
				--quiet)    	quietflag="--quiet"; shift;;
				--no-delete)	nodeleteflag="--no-delete"; shift;;
				--help)     	helpflag='--help'; shift;;
				--usage)    	usageflag='--usage'; shift;;
				--)	shift; break;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					[[ "$1" =~ i ]] && { idflag='-i'; }
					[[ "$1" =~ n ]] && { nameflag='-n'; }
					[[ "$1" =~ q ]] && { quietflag='-q'; }
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					shift
					;;
				*)
					args=("${args[@]}" "$1")
					shift
					;;
			esac
		done
		while (( $# > 0 ))
		do
			args=("${args[@]}" "$1")
			shift
		done

		[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
		[ -n "$usageflag" ] && { usage; return; }

		[ ${#args[@]} -lt 1 ] && { echoerr "mcsvutils: [E] イメージを指定してください"; return $RESPONCE_ERROR; }
		[ ${#args[@]} -gt 1 ] && { echoerr "mcsvutils: [E] 引数が多すぎます"; return $RESPONCE_ERROR; }

		repository_is_exist || { echoerr "mcsvutils: 対象となるイメージが存在しません"; return $RESPONCE_NEGATIVE; }
		local repository
		repository="$(repository_open)"
		echo "$repository" | repository_check_integrity || return $RESPONCE_ERROR

		local target="[]"
		local found_id=1
		{ [ -n "$idflag" ] || { [ -z "$idflag" ] && [ -z "$nameflag" ]; } } && {
			echo "$repository" | repository_is_exist_image "${args[0]}" && {
				found_id=0
				target="[\"${args[0]}\"]"
			}
		}
		local found_name=1
		{ [ -n "$nameflag" ] || { [ -z "$idflag" ] && [ -z "$nameflag" ]; } } && {
			local images_fromname
			images_fromname="$(echo "$repository" | repository_find_image_keys_fromname "${args[0]}")"
			[ "$(echo "$images_fromname" | jq -r 'length')" -gt 0 ] && {
				found_name=0
				target="$(echo "$target" | jq -c --argjson found_image "$images_fromname" '. + $found_image | unique')"
			}
		}

		[ $found_id -eq 0 ] && [ $found_name -eq 0 ] && echoerr "mcsvutils: [W] IDと名前の両方に一致する項目があります。どちらか一方の項目を選択するには --id または --name オプションを付けてください。"
		[ $found_id -eq 0 ] || [ $found_name -eq 0 ] || { echoerr "mcsvutils: 対象となるイメージが存在しません"; return $RESPONCE_NEGATIVE; }
		[ -z "$quietflag" ] && [ "$(echo "$target" | jq -r 'length')" -gt 1 ]
		local ask_delete=$?
		for item in $(echo "$target" | jq -r '.[]')
		do
			local image
			image="$(echo "$repository" | repository_get_image "$item")"
			[ $ask_delete -eq 0 ] && {
				local ans
				echo -n "$item: $(echo "$image" | repository_image_get_name) ($(echo "$image" | repository_image_get_path)) を削除しますか[y/N]: "
				read -r ans
				[ "$ans" != "y" ] && continue
			}
			[ -z "$nodeleteflag" ] && {
				[ -e "${MCSVUTILS_IMAGEREPOSITORY_LOCATION:?}/${item:?}" ] && { rm -rf "${MCSVUTILS_IMAGEREPOSITORY_LOCATION:?}/${item:?}" || { echoerr "$item のデータを削除できませんでした"; continue; } }
			}
			repository="$(echo "$repository" | jq -c "del(.images.\"$item\")")" || { echoerr "mcsvutils: [E] リポジトリの更新に失敗しました"; return $RESPONCE_ERROR; }
		done
		echo "$repository" | repository_save || { echoerr "mcsvutils: [E] リポジトリの保存に失敗しました"; return $RESPONCE_ERROR; }
		return $RESPONCE_POSITIVE
	}
	action_image_update()
	{
		usage()
		{
			cat <<- __EOF
			使用法: $0 image update [オプション]
			__EOF
		}
		help()
		{
			cat <<- __EOF
			image update はローカルリポジトリのデータを更新します。

			  --no-delete
			    管理ディレクトリからのデータの削除を行わず、リポジトリ上の項目の更新のみを行います。(非推奨)
			__EOF
		}
		local args=()
		local nocopyflag=''
		local helpflag=''
		local usageflag=''
		while (( $# > 0 ))
		do
			case $1 in
				--no-delete)	nodeleteflag="--no-delete"; shift;;
				--help)     	helpflag='--help'; shift;;
				--usage)    	usageflag='--usage'; shift;;
				--)	shift; break;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					shift
					;;
				*)
					args=("${args[@]}" "$1")
					shift
					;;
			esac
		done
		while (( $# > 0 ))
		do
			args=("${args[@]}" "$1")
			shift
		done

		[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
		[ -n "$usageflag" ] && { usage; return; }

		local repository
		repository_is_exist || repository_new || { echoerr "mcsvutils: [E] リポジトリの作成に失敗しました"; return $RESPONCE_ERROR; }
		repository="$(repository_open)" || { echoerr "mcsvutils: [E] イメージリポジトリのデータは有効なJSONではありません"; return $RESPONCE_ERROR; }
		local version
		version="$(echo "$repository" | repository_get_version)" || { echoerr "mcsvutils: [E] イメージリポジトリのバージョンを読み取れませんでした"; return $RESPONCE_ERROR; }
		case "$version" in
			"$REPO_VERSION") :;;
			*) echoerr "mcsvutils: [E] サポートされないイメージリポジトリのバージョン($version)です"; return $RESPONCE_ERROR;;
		esac

		echoerr "mcsvutils: 存在しないイメージを指定しているエントリを削除しています"
		local image_list
		mapfile -t image_list < <(echo "$repository" | jq -r '.images | keys | .[]')
		for item in "${image_list[@]}"
		do
			local path
			path="$(echo "$repository" | repository_get_image "$item" | repository_image_get_path)"
			[ -e "$path" ] || {
				local name
				name="$(echo "$repository" | repository_get_image "$item" | repository_image_get_name)"
				repository="$(echo "$repository" | jq -c "del(.images.\"$item\")")"
				echo "$item: $name ($path) をリポジトリから削除しました"
			}
		done
		echo "$repository" | repository_save

		[ -z "$nodeleteflag" ] &&
		{
			echoerr "mcsvutils: 管理ディレクトリ内の参照されないファイルを削除しています"
			for item in "${MCSVUTILS_IMAGEREPOSITORY_LOCATION:?}"/*/
			do
				[ -e "$item" ] || break
				local id=${item#"${MCSVUTILS_IMAGEREPOSITORY_LOCATION:?}/"}
				id=${id%/}
				echo "$repository" | repository_is_exist_image "$id" || {
					rm -rf "${item:?}"
					echo "$item を削除しました"
				}
			done
		}
	}
	action_image_find()
	{
		usage()
		{
			cat <<- __EOF
			使用法: $0 image find [オプション] [クエリ]
			__EOF
		}
		help()
		{
			cat <<- __EOF
			image find はMinecraftサーバーのバージョン一覧を出力します。

			--latest
			    最新のバージョンを表示する
			--no-release
			    releaseタグの付いたバージョンを除外する
			--snapshot
			    snapshotタグの付いたバージョンをリストに含める
			--old-alpha
			    old_alphaタグの付いたバージョンをリストに含める
			--old-beta
			    old_betaタグの付いたバージョンをリストに含める

			クエリに正規表現を用いて結果を絞り込むことができます。
			__EOF
		}
		local args=()
		local latestflag=''
		local no_releaseflag=''
		local snapshotflag=''
		local old_alphaflag=''
		local old_betaflag=''
		local helpflag=''
		local usageflag=''
		while (( $# > 0 ))
		do
			case $1 in
				--latest)   	latestflag="--latest"; shift;;
				--no-release)	no_releaseflag="--no-release"; shift;;
				--snapshot) 	snapshotflag="--snapshot"; shift;;
				--old-alpha) 	old_alphaflag="--old-alpha"; shift;;
				--old-beta) 	old_betaflag="--old-beta"; shift;;
				--help)     	helpflag='--help'; shift;;
				--usage)    	usageflag='--usage'; shift;;
				--)	shift; break;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					shift
					;;
				*)
					args=("${args[@]}" "$1")
					shift
					;;
			esac
		done
		while (( $# > 0 ))
		do
			args=("${args[@]}" "$1")
			shift
		done

		[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
		[ -n "$usageflag" ] && { usage; return; }

		check || { oncheckfail; return $RESPONCE_ERROR; }
		fetch_mcversions || return $?
		if [ -n "$latestflag" ]; then
			if [ -z "$snapshotflag" ]; then
				echo "$VERSION_MANIFEST" | jq -r '.latest.release'
			else
				echo "$VERSION_MANIFEST" | jq -r '.latest.snapshot'
			fi
		else
			local select_types="false"
			[ -z "$no_releaseflag" ] && select_types="$select_types or .type == \"release\""
			[ -n "$snapshotflag" ] && select_types="$select_types or .type == \"snapshot\""
			[ -n "$old_betaflag" ] && select_types="$select_types or .type == \"old_beta\""
			[ -n "$old_alphaflag" ] &&  select_types="$select_types or .type == \"old_alpha\""
			local select_ids
			if [ ${#args[@]} -ne 0 ]; then
				select_ids="false"
				for search_query in "${args[@]}"
				do
					select_ids="$select_ids or test( \"$search_query\" )"
				done
			else
				select_ids="true"
			fi
			local result
			mapfile -t result < <(echo "$VERSION_MANIFEST" | jq -r ".versions[] | select( $select_types ) | .id | select( $select_ids )")
			if [ ${#result[@]} -ne 0 ]; then
				for item in "${result[@]}"
				do
					echo "$item"
				done
				return $RESPONCE_POSITIVE
			else
				echoerr "mcsvutils: 対象となるバージョンが存在しません"
				return $RESPONCE_NEGATIVE
			fi
		fi
	}
	action_image_get()
	{
		usage()
		{
			cat <<- __EOF
			使用法:
			$0 image get [-o [保存先]] <バージョン>
			$0 image get [-o [保存先]] --latest
			__EOF
		}
		help()
		{
			cat <<- __EOF
			image get はMinecraftサーバーのjarをダウンロードします。
			<バージョン>に指定可能なものは $0 image find で確認可能です。

			--out | -o
				出力先ファイル名を指定します。
				指定がなかった場合は規定の名前で書き出されます。
			--latest
				最新のリリースビルドをカタログから検出し、選択します。
				このオプションが指定されている場合、バージョンの指定は無効です。
			__EOF
		}
		local args=()
		local outflag=''
		local latestflag=''
		local helpflag=''
		local usageflag=''
		while (( $# > 0 ))
		do
			case $1 in
				--out)  	shift; outflag="$1"; shift;;
				--latest)	latestflag="--latest"; shift;;
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--)	shift; break;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					[[ "$1" =~ o ]] && { if [[ "$1" =~ o$ ]]; then shift; outflag="$1"; else outflag=''; fi; }
					shift
					;;
				*)
					args=("${args[@]}" "$1")
					shift
					;;
			esac
		done
		while (( $# > 0 ))
		do
			args=("${args[@]}" "$1")
			shift
		done

		[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
		[ -n "$usageflag" ] && { usage; return; }

		check || { oncheckfail; return $RESPONCE_ERROR; }
		fetch_mcversions || return

		local selected_version
		if [ -n "$latestflag" ]; then
			[ ${#args[@]} -ge 1 ] && { echoerr "mcsvutils: [W] --latestフラグが付いているため、バージョンの指定は無効です"; }
			local latest
			latest="$(echo "$VERSION_MANIFEST" | jq -r '.latest.release')"
			echo "mcsvutils: 最新のバージョン $latest が選択されました"
			selected_version="$(echo "$VERSION_MANIFEST" | jq -c ".versions[] | select( .id == \"$latest\" )")"
		else
			[ ${#args[@]} -lt 1 ] && { echoerr "mcsvutils: [E] ダウンロードするMinecraftのバージョンを指定する必要があります"; return $RESPONCE_ERROR; }
			selected_version="$(echo "$VERSION_MANIFEST" | jq -c ".versions[] | select( .id == \"${args[0]}\" )")"
		fi
		[ -z "$selected_version" ] && { echoerr "mcsvutils: 指定されたバージョンは見つかりませんでした"; return $RESPONCE_ERROR; }
		echo "mcsvutils: $(echo "$selected_version" | jq -r '.id') のカタログをダウンロードしています..."
		selected_version=$(curl "$(echo "$selected_version" | jq -r '.url')") || { echoerr "mcsvutils: [E] カタログのダウンロードに失敗しました"; return $RESPONCE_ERROR; }
		local dl_data
		local dl_sha1
		dl_data=$(echo "$selected_version" | jq -r '.downloads.server.url')
		dl_sha1=$(echo "$selected_version" | jq -r '.downloads.server.sha1')
		local destination
		if [ -n "$outflag" ]
			then destination="$outflag"
			else destination="$(basename "$dl_data")"
		fi
		echo "mcsvutils: データをダウンロードしています..."
		wget "$dl_data" -O "$destination" || { echoerr "mcsvutils: [E] データのダウンロードに失敗しました"; return $RESPONCE_ERROR; }
		if [ "$(sha1sum "$destination" | awk '{print $1}')" = "$dl_sha1" ]; then
			echo "mcsvutils: データのダウンロードが完了しました"
			return $RESPONCE_POSITIVE
		else
			echoerr "mcsvutils: [W] データのダウンロードが完了しましたが、チェックサムが一致しませんでした"
			return $RESPONCE_ERROR
		fi
	}

	# Analyze arguments --------------------
	local subcommand=""
	if [[ $1 =~ -.* ]] || [ "$1" = "" ]; then
		subcommand="none"
		while (( $# > 0 ))
		do
			case $1 in
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					shift
					;;
				*)	break;;
			esac
		done
	else
		for item in "${SUBCOMMANDS[@]}"
		do
			[ "$item" == "$1" ] && {
				subcommand="$item"
				shift
				break
			}
		done
	fi
	[ -z "$subcommand" ] && { echoerr "mcsvutils: [E] 無効なサブコマンドを指定しました。"; usage >&2; return $RESPONCE_ERROR; }
	{ [ "$subcommand" == "help" ] || [ -n "$helpflag" ]; } && { version; echo; usage; echo; help; return; }
	[ -n "$usageflag" ] && { usage; return; }
	[ "$subcommand" == "none" ] && { echoerr "mcsvutils: [E] サブコマンドが指定されていません。"; echoerr "$0 image help で詳細なヘルプを表示します。"; usage >&2; return $RESPONCE_ERROR; }
	"action_image_$subcommand" "$@"
}

action_spigot()
{
	# Usage/Help ---------------------------
	local SUBCOMMANDS=("help" "build")
	usage()
	{
		cat <<- __EOF
		使用法: $0 spigot <サブコマンド>
		使用可能なサブコマンド: ${SUBCOMMANDS[@]}
		__EOF
	}
	help()
	{
		cat <<- __EOF
		spigot はCraftBukkit/Spigotサーバーの実行ファイルイメージを管理します。

		使用可能なサブコマンドは以下のとおりです。

		  help   このヘルプを表示する
		  build  BuildTools.jarを使用したサーバーイメージのビルド
		__EOF
	}

	# Subcommands --------------------------
	action_spigot_build()
	{
		usage()
		{
			cat <<- __EOF
			使用法: $0 spigot build [-o [保存先]] <バージョン>
			__EOF
		}
		help()
		{
			cat <<- __EOF
			spigot build はSpigotサーバーのビルドツールをダウンロードし、Minecraftサーバーからビルドします。
			<バージョン>に指定可能なものは https://www.spigotmc.org/wiki/buildtools/#versions を確認してください。

			--out | -o
			    出力先を指定します。
			    指定がなかった場合は規定の名前で書き出されます。
			__EOF
		}
		local args=()
		local outflag=''
		local latestflag=''
		local javaflag=''
		local helpflag=''
		local usageflag=''
		while (( $# > 0 ))
		do
			case $1 in
				--out)  	shift; outflag="$1"; shift;;
				--latest)	latestflag="--latest"; shift;;
				--java) 	shift; javaflag="$1"; shift;;
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--)	shift; break;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					[[ "$1" =~ o ]] && { if [[ "$1" =~ o$ ]]; then shift; outflag="$1"; else outflag=''; fi; }
					shift
					;;
				*)
					args=("${args[@]}" "$1")
					shift
					;;
			esac
		done
		while (( $# > 0 ))
		do
			args=("${args[@]}" "$1")
			shift
		done

		[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
		[ -n "$usageflag" ] && { usage; return; }

		check || { oncheckfail; return $RESPONCE_ERROR; }
		local invocations=()
		if [ -n "$javaflag" ]
			then invocations=("$javaflag")
			else invocations=("java")
		fi
		invocations=("${invocations[@]}" "-jar" "BuildTools.jar")
		if [ -z "$latestflag" ]; then
			[ ${#args[@]} -lt 1 ] && { echoerr "mcsvutils: [E] ビルドするMinecraftのバージョンを指定する必要があります"; return $RESPONCE_ERROR; }
			invocations=("${invocations[@]}" "--rev" "${args[0]}")
		fi
		local work_dir
		work_dir="$TEMP/mcsvutils-$(cat /proc/sys/kernel/random/uuid)"
		(
			mkdir -p "$work_dir" || { echoerr "mcsvutils: [E] 作業用ディレクトリを作成できませんでした"; return $RESPONCE_ERROR; }
			cd "$work_dir" || { echoerr "mcsvutils: [E] 作業用ディレクトリに入れませんでした"; return $RESPONCE_ERROR; }
			wget "$SPIGOT_BUILDTOOLS_LOCATION" || { echoerr "mcsvutils: [E] BuildTools.jar のダウンロードに失敗しました"; return $RESPONCE_ERROR; }
			"${invocations[@]}" || return
			tail BuildTools.log.txt | grep "Success! Everything completed successfully. Copying final .jar files now." >/dev/null 2>&1 || return
		) || { echoerr "mcsvutils: [E] Spigotサーバーのビルドに失敗しました。詳細はログを確認してください。"; return $RESPONCE_ERROR; }
		local resultjar
		resultjar="$(tail "$work_dir/BuildTools.log.txt" | grep -- "- Saved as .*\\.jar" | sed -e 's/ *- Saved as //g')"
		local destination="./"
		[ -n "$outflag" ] && destination="$outflag"
		if [ -e "${work_dir}/$(basename "$resultjar")" ]; then
			mv "${work_dir}/$(basename "$resultjar")" "$destination" || { echoerr "[E] jarファイルの移動に失敗しました。"; return $RESPONCE_ERROR; }
			rm -rf "$work_dir"
			return $RESPONCE_POSITIVE
		else
			echoerr "[W] jarファイルの自動探索に失敗しました。ファイルは移動されません。"
			return $RESPONCE_NEGATIVE
		fi
	}

	# Analyze arguments --------------------
	local subcommand=""
	if [[ $1 =~ -.* ]] || [ "$1" = "" ]; then
		subcommand="none"
		while (( $# > 0 ))
		do
			case $1 in
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					shift
					;;
				*)	break;;
			esac
		done
	else
		for item in "${SUBCOMMANDS[@]}"
		do
			[ "$item" == "$1" ] && {
				subcommand="$item"
				shift
				break
			}
		done
	fi
	[ -z "$subcommand" ] && { echoerr "mcsvutils: [E] 無効なサブコマンドを指定しました。"; usage >&2; return $RESPONCE_ERROR; }
	{ [ "$subcommand" == "help" ] || [ -n "$helpflag" ]; } && { version; echo; usage; echo; help; return; }
	[ -n "$usageflag" ] && { usage; return; }
	[ "$subcommand" == "none" ] && { echoerr "mcsvutils: [E] サブコマンドが指定されていません。"; echoerr "$0 spigot help で詳細なヘルプを表示します。"; usage >&2; return $RESPONCE_ERROR; }
	"action_spigot_$subcommand" "$@"
}

action_check()
{
	usage()
	{
		cat <<- __EOF
		使用法: $0 check
		__EOF
	}
	help()
	{
		cat <<- __EOF
		checkはこのスクリプトの動作要件のチェックを行います。
		チェックに成功した場合 $RESPONCE_POSITIVE 、失敗した場合は $RESPONCE_NEGATIVE を返します。
		checkに失敗した場合は必要なパッケージが不足していないか確認してください。
		__EOF
	}
	local helpflag=''
	local usageflag=''
	local args=()
	while (( $# > 0 ))
	do
		case $1 in
			--help) 	helpflag='--help'; shift;;
			--usage)	usageflag='--usage'; shift;;
			--)	shift; break;;
			--*)	echo_invalid_flag "$1"; shift;;
			-*)
				[[ "$1" =~ h ]] && { helpflag='-h'; }
				shift
				;;
			*)
				args=("${args[@]}" "$1")
				shift
				;;
		esac
	done
	while (( $# > 0 ))
	do
		args=("${args[@]}" "$1")
		shift
	done

	[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
	[ -n "$usageflag" ] && { usage; return; }
	if check ;then
		echo "mcsvutils: チェックに成功しました。"
		return $RESPONCE_POSITIVE
	else
		echo "mcsvutils: チェックに失敗しました。"
		return $RESPONCE_NEGATIVE
	fi
}

action_version()
{
	version
	return $RESPONCE_POSITIVE
}

action_usage()
{
	usage
	return $RESPONCE_POSITIVE
}

action_help()
{
	version
	echo
	usage
	echo
	help
	return $RESPONCE_POSITIVE
}

action_none()
{
	if [ "$helpflag" != "" ]; then
		action_help
		return $?
	elif [ "$usageflag" != "" ]; then
		action_usage
		return $?
	elif [ "$versionflag" != "" ]; then
		action_version
		return $?
	else
		echoerr "mcsvutils: [E] アクションが指定されていません。"
		usage >&2
		return $RESPONCE_ERROR
	fi
}

# Analyze arguments --------------------
subcommand=""
if [[ $1 =~ -.* ]] || [ "$1" = "" ]; then
	subcommand="none"
	while (( $# > 0 ))
	do
		case $1 in
			--help) 	helpflag='--help'; shift;;
			--usage)	usageflag='--usage'; shift;;
			--version)	versionflag='--version'; shift;;
			--*)	echo_invalid_flag "$1"; shift;;
			-*)
				[[ "$1" =~ h ]] && { helpflag='-h'; }
				[[ "$1" =~ v ]] && { versionflag='-v'; }
				shift
				;;
			*)	break;;
		esac
	done
else
	for item in "${SUBCOMMANDS[@]}"
	do
		[ "$item" == "$1" ] && {
			subcommand="$item"
			shift
			break
		}
	done
fi

if [ -n "$subcommand" ]
	then "action_$subcommand" "$@"; exit $?
	else echoerr "mcsvutils: [E] 無効なアクションを指定しました。"; usage >&2; exit $RESPONCE_ERROR
fi
