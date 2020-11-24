#! /bin/bash

version()
{
	cat <<- __EOF
	mcsvutil - minecraft server utilities
	version 0.1.0 2020-11-24
	2020, zawa-ch.
	__EOF
}

readonly EXECUTABLE_ACTIONS=("version" "usage" "help" "check" "mcversions" "mcdownload" "create" "status" "start" "stop" "command")

usage()
{
	cat <<- __EOF
	使用法: $0 <アクション> [...]
	使用可能なアクション: ${EXECUTABLE_ACTIONS[@]}
	__EOF
}

help()
{
	cat <<- __EOF
	  create      サーバープロファイルを作成する
	  status      サーバーの状態を問い合わせる
	  start       サーバーを起動する
	  stop        サーバーを停止する
	  command     サーバーにコマンドを送信する
	  mcversions  minecraftのバージョンのリストを出力する
	  mcdownload  minecraftサーバーをダウンロードする
	  check       このスクリプトの動作要件を満たしているかチェックする
	  version     現在のバージョンを表示して終了
	  usage       使用法を表示する
	  help        このヘルプを表示する

	各コマンドの詳細なヘルプは各コマンドに--helpオプションを付けてください。
	__EOF
}

## Const ------------------------------
readonly VERSION_MANIFEST_LOCATION='https://launchermeta.mojang.com/mc/game/version_manifest.json'
readonly RESPONCE_POSITIVE=0
readonly RESPONCE_NEGATIVE=1
readonly RESPONCE_ERROR=2
readonly DATA_VERSION=1
## ------------------------------------

action=""
if [[ $1 =~ -.* ]] || [ "$1" = "" ]; then
	action="none"
else
	for item in "${EXECUTABLE_ACTIONS[@]}"
	do
		if [ "$item" = "$1" ]; then
			action="$item"
			shift
		fi
	done
fi

echo_invalid_flag()
{
	echo "mcsvutil: [W] 無効なオプション $1 が指定されています" >&2
	echo "通常の引数として読み込ませる場合は先に -- を使用してください" >&2
}

declare -a args=()
while (( $# > 0 ))
do
	case $1 in
		--latest)
			if [ "$action" = "mcversions" ]; then
				latestflag="--latest"
			else
				echo_invalid_flag "$1"
			fi
			shift
			;;
		--no-release)
			if [ "$action" = "mcversions" ]; then
				noreleaseflag="--no-release"
			else
				echo_invalid_flag "$1"
			fi
			shift
			;;
		--snapshot)
			if [ "$action" = "mcversions" ]; then
				snapshotflag="--snapshot"
			else
				echo_invalid_flag "$1"
			fi
			shift
			;;
		--old-alpha)
			if [ "$action" = "mcversions" ]; then
				oldalphaflag="--old-alpha"
			else
				echo_invalid_flag "$1"
			fi
			shift
			;;
		--old-beta)
			if [ "$action" = "mcversions" ]; then
				oldbetaflag="--old-beta"
			else
				echo_invalid_flag "$1"
			fi
			shift
			;;
		--name)
			if [ "$action" = "create" ] || [ "$action" = "start" ] || [ "$action" = "stop" ] || [ "$action" = "command" ]; then
				shift
				nameflag="$1"
			else
				echo_invalid_flag "$1"
			fi
			shift
			;;
		--execute)
			if [ "$action" = "create" ] || [ "$action" = "start" ]; then
				shift
				executeflag="$1"
			else
				echo_invalid_flag "$1"
			fi
			shift
			;;
		--option)
			if [ "$action" = "create" ] || [ "$action" = "start" ]; then
				shift
				optionflag="$1"
			else
				echo_invalid_flag "$1"
			fi
			shift
			;;
		--args)
			if [ "$action" = "create" ] || [ "$action" = "start" ]; then
				shift
				argsflag="$1"
			else
				echo_invalid_flag "$1"
			fi
			shift
			;;
		--cwd)
			if [ "$action" = "create" ] || [ "$action" = "start" ]; then
				shift
				cwdflag="$1"
			else
				echo_invalid_flag "$1"
			fi
			shift
			;;
		--java)
			if [ "$action" = "create" ] || [ "$action" = "start" ]; then
				shift
				javaflag="$1"
			else
				echo_invalid_flag "$1"
			fi
			shift
			;;
		--owner)
			if [ "$action" = "create" ] || [ "$action" = "start" ] || [ "$action" = "stop" ] || [ "$action" = "command" ]; then
				shift
				ownerflag="$1"
			else
				echo_invalid_flag "$1"
			fi
			shift
			;;
		--help)
			helpflag='--help'
			shift
			;;
		--usage)
			usageflag='--usage'
			shift
			;;
		--version)
			versionflag='--version'
			shift
			;;
		--)
			shift
			break
			;;
		--*)
			echo_invalid_flag "$1"
			shift
			;;
		-*)
			if [[ "$1" =~ h ]]; then
				helpflag='-h'
			fi
			if [[ "$1" =~ n ]]; then
				if [ "$action" = "create" ] || [ "$action" = "start" ] || [ "$action" = "stop" ] || [ "$action" = "command" ]; then
					if [[ "$1" =~ n$ ]]; then
						shift
						nameflag="$1"
					else
						nameflag=''
					fi
				else
					echo_invalid_flag "$1"
				fi
			fi
			if [[ "$1" =~ e ]]; then
				if [ "$action" = "create" ] || [ "$action" = "start" ]; then
					if [[ "$1" =~ e$ ]]; then
						shift
						executeflag="$1"
					else
						executeflag=''
					fi
				else
					echo_invalid_flag "$1"
				fi
			fi
			if [[ "$1" =~ u ]]; then
				if [ "$action" = "create" ] || [ "$action" = "start" ] || [ "$action" = "stop" ] || [ "$action" = "command" ]; then
					if [[ "$1" =~ u$ ]]; then
						shift
						ownerflag="$1"
					else
						ownerflag=''
					fi
				else
					echo_invalid_flag "$1"
				fi
			fi
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

echoerr()
{
	echo "$*" >&2
}

as_user()
{
	local user="$1"
	shift
	local command=("$@")
	if [ "$(whoami)" = "$user" ]; then
		bash -c "${command[@]}"
	else
		sudo -u "$user" -sH "${command[@]}"
	fi
}

as_user_script()
{
	local user="$1"
	if [ "$(whoami)" = "$user" ]; then
		bash
	else
		sudo -u "$user" -sH
	fi
}

check()
{
	check_installed()
	{
		bash -c "$1 --version" > /dev/null
	}
	local RESULT=0
	check_installed sudo
	RESULT=$(($? | RESULT))
	check_installed wget
	RESULT=$(($? | RESULT))
	check_installed curl
	RESULT=$(($? | RESULT))
	check_installed jq
	RESULT=$(($? | RESULT))
	check_installed screen
	RESULT=$(($? | RESULT))
	return $RESULT
}

fetch_mcversions()
{
	VERSION_MANIFEST=$(curl -s "$VERSION_MANIFEST_LOCATION")
	if ! [ $? ]; then
		echoerr "mcsvutil: [E] Minecraftバージョンマニフェストファイルのダウンロードに失敗しました"
	fi
}

dispatch_command()
{
	local profile_owner="$1"
	shift
	local profile_name="$1"
	shift
	as_user "$profile_owner" "screen -p 0 -S $profile_name -X eval 'stuff \"$*\"\015'"
}

action_create()
{
	usage()
	{
		cat <<- __EOF
		使用法: $0 create --name <名前> --execute <jarファイル> [オプション] [保存先]
		指定可能なオプション: -n -e -u --name --execute --option --args --cwd --java --owner
		__EOF
	}
	help()
	{
		cat <<- __EOF
		createはMinecraftサーバーのプロファイルを作成します。

		  --name | -n (必須)
		    プロファイルの名前を指定します。
		    このプロファイルの名前はサービスの名前としても使用されます。
		  --execute | -e (必須)
		    サーバーとして実行するjarファイルを指定します。
		  --option
		    実行時にjavaに渡すオプションを指定します。
		  --args
		    実行時の引数を指定します。
		  --cwd
		    実行時の作業ディレクトリを指定します。
		  --java
		    javaの環境を指定します。
		    この引数を指定するとインストールされているjavaとは異なるjavaを使用することができます。
		  --owner | -u
		    実行時のユーザーを指定します。
		
		保存先には作成されたプロファイルの保存先を指定します。
		省略した場合は標準出力に書き出されます。
		__EOF
	}
	if [ "$helpflag" != "" ]; then
		version
		echo
		usage
		echo
		help
		return
	elif [ "$usageflag" != "" ]; then
		usage
		return
	fi
	local result
	if [ "$nameflag" = "" ]; then
		echoerr "mcsvutil: [E] --nameは必須です"
		return $RESPONCE_ERROR
	fi
	if [ "$executeflag" = "" ]; then
		echoerr "mcsvutil: [E] --executeは必須です"
		return $RESPONCE_ERROR
	fi
	result=$(echo "{}" | jq -c "{ version: $DATA_VERSION, name: \"$nameflag\", execute: \"$executeflag\" }")
	local options="[]"
	if [ "$optionflag" != "" ]; then
		for item in $optionflag
		do
			options=$(echo "$options" | jq -c ". + [ \"$item\" ]")
		done
	fi
	result=$(echo "$result" | jq -c "setpath( [\"options\"]; $options)")
	local options="[]"
	if [ "$argsflag" != "" ]; then
		for item in $argsflag
		do
			options=$(echo "$options" | jq -c ". + [ \"$item\" ]")
		done
	fi
	result=$(echo "$result" | jq -c "setpath( [\"args\"]; $options)")
	if [ "$cwdflag" != "" ]; then
		result=$(echo "$result" | jq -c "setpath( [\"cwd\"]; \"$cwdflag\")")
	else
		result=$(echo "$result" | jq -c "setpath( [\"cwd\"]; null)")
	fi
	if [ "$javaflag" != "" ]; then
		result=$(echo "$result" | jq -c "setpath( [\"javapath\"]; \"$javaflag\")")
	else
		result=$(echo "$result" | jq -c "setpath( [\"javapath\"]; null)")
	fi
	if [ "$ownerflag" != "" ]; then
		result=$(echo "$result" | jq -c "setpath( [\"owner\"]; \"$ownerflag\")")
	else
		result=$(echo "$result" | jq -c "setpath( [\"owner\"]; null)")
	fi
	if [ "${args[0]}" != "" ]; then
		echo "$result" > "${args[0]}"
	else
		echo "$result"
	fi
}

action_status()
{
	usage()
	{
		cat <<- __EOF
		  status [オプション] <プロファイル>
		  status --name <名前> [オプション]
		指定可能なオプション: -n -u --name --owner
		__EOF
	}
	help()
	{
		cat <<- __EOF
		statusはMinecraftサーバーの状態を問い合わせます。
		プロファイルには$0 createで作成したプロファイルのパスを指定します。

		  --name | -n
		    プロファイルの名前を指定します。
		    プロファイルを指定しない場合のみ必須です。
		    プロファイルを指定している場合はこのオプションを指定することはできません。
		  --owner | -u
		    実行時のユーザーを指定します。
		    このオプションを指定するとプロファイルの設定を上書きします。
		
		指定したMinecraftサーバーが起動している場合は $RESPONCE_POSITIVE 、起動していない場合は $RESPONCE_NEGATIVE が返されます。
		__EOF
	}
	if [ "$helpflag" != "" ]; then
		version
		echo
		usage
		echo
		help
		return
	elif [ "$usageflag" != "" ]; then
		usage
		return
	fi
	local profile_name=""
	local profile_owner=""
	if [ ${#args[@]} -ne 0 ]; then
		local profile_file
		profile_file="${args[0]}"
		if [ "$nameflag" != "" ]; then
			echoerr "mcsvutil: [E] プロファイルを指定した場合、名前の指定は無効です"
			return $RESPONCE_ERROR
		fi
		if ! [ -e "$profile_file" ]; then
			echoerr "mcsvutil: [E] $profile_file というファイルが見つかりません"
			return $RESPONCE_ERROR
		fi
		profile_name=$(jq -r ".name | strings" "$profile_file")
		if ! [ $? ] || [ "$profile_name" = "" ]; then echoerr "mcsvutil: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; fi
		profile_owner=$(jq -r ".owner | strings" "$profile_file")
		if ! [ $? ]; then echoerr "mcsvutil: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; fi
	else
		if [ "$nameflag" = "" ]; then
			echoerr "mcsvutil: [E] プロファイルを指定していない場合、名前の指定は必須です"
			return $RESPONCE_ERROR
		fi
		profile_name=$nameflag
	fi
	if [ "$ownerflag" != "" ]; then
		profile_owner=$ownerflag
	fi
	if [ "$profile_owner" = "" ]; then
		profile_owner="$(whoami)"
	fi
	if as_user "$profile_owner" "screen -list \"$profile_name\"" > /dev/null
	then
		echo "mcsvutil: ${profile_name} は起動しています"
		return $RESPONCE_POSITIVE
	else
		echo "mcsvutil: ${profile_name} は起動していません"
		return $RESPONCE_NEGATIVE
	fi
}

action_start()
{
	usage()
	{
		cat <<- __EOF
		使用法:
		  start [オプション] <プロファイル>
		  start --name <名前> --execute <jarファイル> [オプション]
		指定可能なオプション: -n -e -u --name --execute --option --args --cwd --java --owner
		__EOF
	}
	help()
	{
		cat <<- __EOF
		startはMinecraftのサーバーを起動します。
		プロファイルには$0 createで作成したプロファイルのパスを指定します。

		  --name | -n
		    プロファイルの名前を指定します。
		    このプロファイルの名前はサービスの名前としても使用されます。
		    プロファイルを指定しない場合のみ必須です。
		    プロファイルを指定している場合はこのオプションを指定することはできません。
		  --execute | -e
		    サーバーとして実行するjarファイルを指定します。
		    プロファイルを指定しない場合のみ必須です。
		    プロファイルを指定している場合はこのオプションを指定することはできません。
		  --option
		    実行時にjavaに渡すオプションを指定します。
		    このオプションを指定するとプロファイルの設定を上書きします。
		  --args
		    実行時の引数を指定します。
		    このオプションを指定するとプロファイルの設定を上書きします。
		  --cwd
		    実行時の作業ディレクトリを指定します。
		    このオプションを指定するとプロファイルの設定を上書きします。
		  --java
		    javaの環境を指定します。
		    この引数を指定するとインストールされているjavaとは異なるjavaを使用することができます。
		    このオプションを指定するとプロファイルの設定を上書きします。
		  --owner | -u
		    実行時のユーザーを指定します。
		    このオプションを指定するとプロファイルの設定を上書きします。
		
		__EOF
	}
	if [ "$helpflag" != "" ]; then
		version
		echo
		usage
		echo
		help
		return
	elif [ "$usageflag" != "" ]; then
		usage
		return
	fi
	local profile_name=""
	local profile_execute=""
	local profile_options=()
	local profile_args=()
	local profile_cwd=""
	local profile_java=""
	local profile_owner=""
	if [ ${#args[@]} -ne 0 ]; then
		local profile_file
		profile_file="${args[0]}"
		if [ "$nameflag" != "" ] || [ "$executeflag" != "" ]; then
			echoerr "mcsvutil: [E] プロファイルを指定した場合、名前と実行ファイルの指定は無効です"
			return $RESPONCE_ERROR
		fi
		if ! [ -e "$profile_file" ]; then
			echoerr "mcsvutil: [E] $profile_file というファイルが見つかりません"
			return $RESPONCE_ERROR
		fi
		profile_name=$(jq -r ".name | strings" "$profile_file")
		if ! [ $? ] || [ "$profile_name" = "" ]; then echoerr "mcsvutil: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; fi
		profile_execute=$(jq -r ".execute | strings" "$profile_file")
		if ! [ $? ] || [ "$profile_execute" = "" ]; then echoerr "mcsvutil: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; fi
		for item in $(jq -r ".options[]" "$profile_file")
		do
			profile_options+=("$item")
		done
		for item in $(jq -r ".args[]" "$profile_file")
		do
			profile_args+=("$item")
		done
		profile_cwd=$(jq -r ".cwd | strings" "$profile_file")
		if ! [ $? ]; then echoerr "mcsvutil: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; fi
		profile_java=$(jq -r ".javapath | strings" "$profile_file")
		if ! [ $? ]; then echoerr "mcsvutil: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; fi
		profile_owner=$(jq -r ".owner | strings" "$profile_file")
		if ! [ $? ]; then echoerr "mcsvutil: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; fi
	else
		if [ "$nameflag" = "" ] || [ "$executeflag" = "" ]; then
			echoerr "mcsvutil: [E] プロファイルを指定していない場合、名前と実行ファイルの指定は必須です"
			return $RESPONCE_ERROR
		fi
		profile_name=$nameflag
		profile_execute=$executeflag
	fi
	if [ "$optionflag" != "" ]; then
		profile_options=("$optionflag")
	fi
	if [ "$argsflag" != "" ]; then
		profile_args=("$argsflag")
	fi
	if [ "$cwdflag" != "" ]; then
		profile_cwd=$cwdflag
	fi
	if [ "$javaflag" != "" ]; then
		profile_java=$javaflag
	fi
	if [ "$ownerflag" != "" ]; then
		profile_owner=$ownerflag
	fi
	if [ "$profile_cwd" = "" ]; then
		profile_cwd="./"
	fi
	if [ "$profile_java" = "" ]; then
		profile_java="java"
	fi
	if [ "$profile_owner" = "" ]; then
		profile_owner="$(whoami)"
	fi
	as_user_script "$profile_owner" <<- __EOF
	if screen -list $profile_name > /dev/null
	then
		echo "mcsvutil: ${profile_name} は起動済みです" >&2
		exit $RESPONCE_NEGATIVE
	fi
	echo "mcsvutil: $profile_name を起動しています"
	if ! cd "$profile_cwd"; then
		echo "mcsvutil: [E] $profile_cwd に入れませんでした" >&2
		exit $RESPONCE_ERROR
	fi
	invocations="$profile_java"
	if [ "${#profile_options[@]}" -ne 0 ]; then
		invocations="\$invocations ${profile_options[@]}"
	fi
	invocations="\$invocations -jar $profile_execute"
	if [ "${#profile_args[@]}" -ne 0 ]; then
		invocations="\$invocations ${profile_args[@]}"
	fi
	screen -h 1024 -dmS "$profile_name" \$invocations
	sleep 10
	if screen -list "$profile_name" > /dev/null
	then
		echo "mcsvutil: ${profile_name} が起動しました"
		exit $RESPONCE_POSITIVE
	else
		echo "mcsvutil: [E] ${profile_name} を起動できませんでした" >&2
		exit $RESPONCE_ERROR
	fi
	__EOF
	return $?
}

action_stop()
{
	usage()
	{
		cat <<- __EOF
		  stop [オプション] <プロファイル>
		  stop --name <名前> [オプション]
		指定可能なオプション: -n -u --name --owner
		__EOF
	}
	help()
	{
		cat <<- __EOF
		stopはMinecraftのサーバーを停止します。
		プロファイルには$0 createで作成したプロファイルのパスを指定します。

		  --name | -n
		    プロファイルの名前を指定します。
		    プロファイルを指定しない場合のみ必須です。
		    プロファイルを指定している場合はこのオプションを指定することはできません。
		  --owner | -u
		    実行時のユーザーを指定します。
		    このオプションを指定するとプロファイルの設定を上書きします。
		
		__EOF
	}
	if [ "$helpflag" != "" ]; then
		version
		echo
		usage
		echo
		help
		return
	elif [ "$usageflag" != "" ]; then
		usage
		return
	fi
	local profile_name=""
	local profile_owner=""
	if [ ${#args[@]} -ne 0 ]; then
		local profile_file
		profile_file="${args[0]}"
		if [ "$nameflag" != "" ]; then
			echoerr "mcsvutil: [E] プロファイルを指定した場合、名前の指定は無効です"
			return $RESPONCE_ERROR
		fi
		if ! [ -e "$profile_file" ]; then
			echoerr "mcsvutil: [E] $profile_file というファイルが見つかりません"
			return $RESPONCE_ERROR
		fi
		profile_name=$(jq -r ".name | strings" "$profile_file")
		if ! [ $? ] || [ "$profile_name" = "" ]; then echoerr "mcsvutil: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; fi
		profile_owner=$(jq -r ".owner | strings" "$profile_file")
		if ! [ $? ]; then echoerr "mcsvutil: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; fi
	else
		if [ "$nameflag" = "" ]; then
			echoerr "mcsvutil: [E] プロファイルを指定していない場合、名前の指定は必須です"
			return $RESPONCE_ERROR
		fi
		profile_name=$nameflag
	fi
	if [ "$ownerflag" != "" ]; then
		profile_owner=$ownerflag
	fi
	if [ "$profile_owner" = "" ]; then
		profile_owner="$(whoami)"
	fi
	if ! as_user "$profile_owner" "screen -list \"$profile_name\"" > /dev/null
	then
		echo "mcsvutil: ${profile_name} は起動していません" >&2
		return $RESPONCE_NEGATIVE
	fi
	echo "mcsvutil: ${profile_name} を停止しています"
	dispatch_command "$profile_owner" "$profile_name" stop
	sleep 5
	if ! as_user "$profile_owner" "screen -list \"$profile_name\"" > /dev/null
	then
		echo "mcsvutil: ${profile_name} が停止しました"
		return $RESPONCE_POSITIVE
	else
		echo "mcsvutil: [E] ${profile_name} が停止しませんでした" >&2
		return $RESPONCE_ERROR
	fi
}

action_command()
{
	usage()
	{
		cat <<- __EOF
		  command [オプション] <プロファイル> <コマンド>
		  command --name <名前> [オプション] <コマンド>
		指定可能なオプション: -n -u --name --owner
		__EOF
	}
	help()
	{
		cat <<- __EOF
		commandはMinecraftサーバーにコマンドを送信します。
		プロファイルには$0 createで作成したプロファイルのパスを指定します。

		  --name | -n
		    プロファイルの名前を指定します。
		    プロファイルを指定しない場合のみ必須です。
		    プロファイルを指定している場合はこのオプションを指定することはできません。
		  --owner | -u
		    実行時のユーザーを指定します。
		    このオプションを指定するとプロファイルの設定を上書きします。
		
		__EOF
	}
	if [ "$helpflag" != "" ]; then
		version
		echo
		usage
		echo
		help
		return
	elif [ "$usageflag" != "" ]; then
		usage
		return
	fi
	local profile_name=""
	local profile_cwd=""
	local profile_owner=""
	local send_command
	if [ "$nameflag" = "" ]; then
		local profile_file
		profile_file="${args[0]}"
		if ! [ -e "$profile_file" ]; then
			echoerr "mcsvutil: [E] $profile_file というファイルが見つかりません"
			return $RESPONCE_ERROR
		fi
		profile_name=$(jq -r ".name | strings" "$profile_file")
		if ! [ $? ] || [ "$profile_name" = "" ]; then echoerr "mcsvutil: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; fi
		profile_cwd=$(jq -r ".cwd | strings" "$profile_file")
		if ! [ $? ]; then echoerr "mcsvutil: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; fi
		if [ "$profile_cwd" = "" ]; then profile_cwd="./"; fi
		profile_owner=$(jq -r ".owner | strings" "$profile_file")
		if ! [ $? ]; then echoerr "mcsvutil: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; fi
		for index in $(seq 1 $((${#args[@]} - 1)) )
		do
			send_command="$send_command${args[$index]} "
		done
	else
		profile_name=$nameflag
		send_command="${args[*]}"
	fi
	if [ "$ownerflag" != "" ]; then
		profile_owner=$ownerflag
	fi
	if [ "$profile_owner" = "" ]; then
		profile_owner="$(whoami)"
	fi
	if ! as_user "$profile_owner" "screen -list \"$profile_name\"" > /dev/null
	then
		echo "mcsvutil: ${profile_name} は起動していません" >&2
		return $RESPONCE_NEGATIVE
	fi
	local pre_log_length
	if [ "$profile_cwd" != "" ]; then
		pre_log_length=$(as_user "$profile_owner" "wc -l \"$profile_cwd/logs/latest.log\"" | awk '{print $1}')
	fi
	echo "mcsvutil: ${profile_name} にコマンドを送信しています..."
	echo "> $send_command"
	dispatch_command "$profile_owner" "$profile_name" "$send_command"
	echo "mcsvutil: コマンドを送信しました"
	sleep .1
	echo "レスポンス:"
	as_user "$profile_owner" "tail -n $(($(as_user "$profile_owner" "wc -l \"$profile_cwd/logs/latest.log\"" | awk '{print $1}') - pre_log_length)) \"$profile_cwd/logs/latest.log\""
	return $RESPONCE_POSITIVE
}

action_mcversions()
{
	usage()
	{
		cat <<- __EOF
		使用法: $0 mcversions [オプション] [クエリ]
		指定可能なオプション: --latest --no-release --snapshot --old-alpha --old-beta
		__EOF
	}
	help()
	{
		cat <<- __EOF
		mcversionsはMinecraftサーバーのバージョン一覧を出力します。
		
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
	if [ "$helpflag" != "" ]; then
		version
		echo
		usage
		echo
		help
		return
	elif [ "$usageflag" != "" ]; then
		usage
		return
	fi
	if ! check; then
		echoerr "mcsvutil: [E] 動作要件のチェックに失敗しました"
		echoerr "必要なパッケージがインストールされているか確認してください"
	fi
	if ! check; then
		echoerr "mcsvutil: [E] 動作要件のチェックに失敗しました"
		echoerr "必要なパッケージがインストールされているか確認してください"
	fi
	if ! fetch_mcversions; then
		return $RESPONCE_ERROR
	fi
	if [ "$latestflag" != "" ]; then
		echo "$VERSION_MANIFEST" | jq -r '.latest.release'
		if [ "$snapshotflag" != "" ]; then
			echo "$VERSION_MANIFEST" | jq -r '.latest.snapshot'
		fi
	else
		local select_types="false"
		if [ "$noreleaseflag" = "" ]; then
			select_types="$select_types or .type == \"release\""
		fi
		if [ "$snapshotflag" != "" ]; then
			select_types="$select_types or .type == \"snapshot\""
		fi
		if [ "$oldbetaflag" != "" ]; then
			select_types="$select_types or .type == \"old_beta\""
		fi
		if [ "$oldalphaflag" != "" ]; then
			select_types="$select_types or .type == \"old_alpha\""
		fi
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
		else
			echoerr "mcsvutil: 対象となるバージョンが存在しません"
			return $RESPONCE_NEGATIVE
		fi
	fi
}

action_mcdownload()
{
	usage()
	{
		cat <<- __EOF
		使用法: $0 mcdownload <バージョン> [保存先]
		__EOF
	}
	help()
	{
		cat <<- __EOF
		mcdownloadはMinecraftサーバーのjarをダウンロードします。
		<バージョン>に指定可能なものは$0 mcversionsで確認可能です。
		__EOF
	}
	if [ "$helpflag" != "" ]; then
		version
		echo
		usage
		echo
		help
		return
	elif [ "$usageflag" != "" ]; then
		usage
		return
	fi
	if ! check; then
		echoerr "mcsvutil: [E] 動作要件のチェックに失敗しました"
		echoerr "必要なパッケージがインストールされているか確認してください"
	fi
	fetch_mcversions
	if [ ${#args[@]} -lt 1 ]; then
		echoerr "mcsvutil: [E] ダウンロードするMinecraftのバージョンを指定する必要があります"
		return $RESPONCE_ERROR
	fi
	local selected_version
	selected_version="$(echo "$VERSION_MANIFEST" | jq ".versions[] | select( .id == \"${args[0]}\" )")"
	if [ "$selected_version" = "" ]; then
		echoerr "mcsvutil: 指定されたバージョンは見つかりませんでした"
		return $RESPONCE_NEGATIVE
	fi
	echo "mcsvutil: ${args[0]} のカタログをダウンロードしています..."
	selected_version=$(curl "$(echo "$selected_version" | jq -r '.url')")
	if ! [ $? ]; then
		echoerr "mcsvutil: [E] カタログのダウンロードに失敗しました"
		return $RESPONCE_ERROR
	fi
	local dl_data
	local dl_sha1
	dl_data=$(echo "$selected_version" | jq -r '.downloads.server.url')
	dl_sha1=$(echo "$selected_version" | jq -r '.downloads.server.sha1')
	local destination
	if [ "${args[1]}" != "" ]; then
		destination="${args[1]}"
	else
		destination="$(basename "$dl_data")"
	fi
	echo "mcsvutil: データをダウンロードしています..."
	if ! wget "$dl_data" -O "$destination"; then
		echoerr "mcsvutil: [E] データのダウンロードに失敗しました"
		return $RESPONCE_ERROR
	fi
	if [ "$(sha1sum "$destination" | awk '{print $1}')" = "$dl_sha1" ]; then
		echo "mcsvutil: データのダウンロードが完了しました"
		return
	else
		echoerr "mcsvutil: [W] データのダウンロードが完了しましたが、チェックサムが一致しませんでした"
		return $RESPONCE_ERROR
	fi
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
	if [ "$helpflag" != "" ]; then
		version
		echo
		usage
		echo
		help
		return
	elif [ "$usageflag" != "" ]; then
		usage
		return
	fi
	if check ;then
		echo "mcsvutil: チェックに成功しました。"
		return $RESPONCE_POSITIVE
	else
		echo "mcsvutil: チェックに失敗しました。"
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
		echoerr "mcsvutil: [E] アクションが指定されていません。"
		usage >&2
		return $RESPONCE_ERROR
	fi
}

if [ "$action" != "" ]; then
	"action_$action"
	exit $?
else
	echoerr "mcsvutil: [E] 無効なアクションを指定しました。"
	usage >&2
	return $RESPONCE_ERROR
fi