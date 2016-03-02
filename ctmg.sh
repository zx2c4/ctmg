#!/bin/bash

# Copyright (c) 2015 Jason A. Donenfeld <Jason@zx2c4.com>. All Rights Reserved.
# Copyright (c) 2014 Laurent Ghigonis <laurent@gouloum.fr>.
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

CT_FILE_SUFFIX=".ct"
CT_MAPPER_PREFIX="ct_"

trace() {
	echo "[#] $*"
	"$@"
}

die() {
	echo "[!] $*" >&2
	exit 1
}

yesno() {
	[[ -t 0 ]] || return 0
	local response
	read -r -p "$1 [y/N] " response
	[[ $response == [yY] ]] || exit 1
}

unwind() {
	[[ $keep_open -eq 1 ]] && return

	for i in {1..5}; do
		echo -e "$(cut -d ' ' -f 2 /proc/mounts)" | fgrep -wq "$mount_path" || break
		trace umount "$mount_path" && break
		trace sleep $i
	done
	
	for i in {1..5}; do
		trace cryptsetup luksClose "$mapper_name"
		[[ $? -eq 0 || $? -eq 4 ]] && break
		trace sleep $i
	done
	
	for i in {1..5}; do
		[[ ! -d $mount_path ]] && break
		trace rmdir "$mount_path" && break
		trace sleep $i
	done

	keep_open=1
	exit
}

initialize_container() {
	# container_dir  = /home/myuser/
	container_dir="$(readlink -f "$(dirname "$1")")"
	# container_path = /home/myuser/bla.ct
	container_path="$container_dir/$(basename "$1" "$CT_FILE_SUFFIX")$CT_FILE_SUFFIX"
	# mount_path     = /home/myuser/bla/
	mount_path="$(readlink -f "$container_dir/$(basename "$container_path" "$CT_FILE_SUFFIX")")"
	# mapper_name    = ct_home-myuser-bla
	mapper_name="$CT_MAPPER_PREFIX$(echo -n "${mount_path:1}" | tr -C '[:graph:]' '_' | tr '/' '-')"
	# mapper_path    = /dev/mapper/ct_home-myuser-bla
	mapper_path="/dev/mapper/$mapper_name"
	
	trap unwind INT TERM EXIT
}

cmd_usage() {
	cat <<-_EOF
	Usage: $PROGRAM [ new | delete | open | close | list ] [arguments...]
	  $PROGRAM new    container_path container_size[units_suffix]
	  $PROGRAM delete container_path
	  $PROGRAM open   container_path
	  $PROGRAM close  container_path
	  $PROGRAM list
	_EOF
}

cmd_new() {
	[[ $# -ne 2 ]] && die "Usage: $PROGRAM new container_path container_size[units_suffix]"
	initialize_container "$1"
	local container_size="$2"
	[[ -e $mapper_path ]] && { keep_open=1; die "$container_path is already open"; }
	[[ -e $container_path ]] && yesno "$container_path already exists. Are you sure you want to continue?"
	rm -f "$container_path"
	trace truncate -s "$container_size" "$container_path" || { trace rm -f "$container_path"; die "Could not create $container_path"; }
	trace cryptsetup --cipher aes-xts-plain64 --key-size 512 --hash sha512 --iter-time 5000 --batch-mode luksFormat "$container_path" || { trace rm -f "$container_path"; die "Could not create LUKS volume on $container_path"; }
	trace chown "${SUDO_UID:-$(id -u)}:${SUDO_GID:-$(id -g)}" "$container_path" || { trace rm -f "$container_path"; die "Could not set ownership of $container_path"; }
	trace cryptsetup luksOpen "$container_path" "$mapper_name" || { trace rm -f "$container_path"; die "Could not open LUKS volume at $container_path"; }
	trace mkfs.ext4 -q -E root_owner="${SUDO_UID:-$(id -u)}:${SUDO_GID:-$(id -g)}" "$mapper_path" || { trace rm -f "$container_path"; die "Could not format ext4 on the LUKS volume at $container_path"; }
	echo "[+] Created new encrypted container at $container_path"
}

cmd_open() {
	[[ $# -ne 1 ]] && die "Usage: $PROGRAM open container_path"
	initialize_container "$1"
	[[ -f $container_path ]] || { keep_open=1; die "$container_path does not exist or is not a regular file"; }
	[[ -e $mapper_path ]] && { keep_open=1; die "$container_path is already open"; }
	trace cryptsetup luksOpen "$container_path" "$mapper_name" || die "Could not open LUKS volume at $container_path"
	trace mkdir -p "$mount_path" || die "Could not create $mount_path directory"
	trace mount "$mapper_path" "$mount_path" || die "Could not mount $container_path to $mount_path"
	keep_open=1
	echo "[+] Opened $container_path at $mount_path"
}

cmd_close() {
	[[ $# -ne 1 ]] && die "Usage: $PROGRAM close container_path"
	initialize_container "$1"
	keep_open=1
	echo -e "$(cut -d ' ' -f 2 /proc/mounts)" | fgrep -wq "$mount_path" && { trace umount "$mount_path" || die "Could not unmount $mount_path"; }
	trace cryptsetup luksClose "$mapper_name"
	[[ $? -eq 0 || $? -eq 4 ]] || die "Could not close LUKS mapping $mapper_name"
	[[ -d $mount_path ]] && { trace rmdir "$mount_path" || echo "[-] Non-fatal: could not remove $mount_path directory" >&2; }
	echo "[+] Closed $container_path"
}

cmd_delete() {
	[[ $# -ne 1 ]] && die "Usage: $PROGRAM delete container_path"
	yesno "Are you sure you want to delete $1?"
	cmd_close "$@"
	rm "$container_path" || die "Could not delete $container_path"
	echo "[+] Deleted $container_path"
}

cmd_list() {
	[[ $# -ne 0 ]] && die "Usage: $PROGRAM list"
	local mount_points="$(sed -n "s:^/dev/mapper/${CT_MAPPER_PREFIX}[^ ]* \\([^ ]\\+\\).*:\\1:p" /proc/mounts)"
	[[ -n $mount_points ]] && echo -e "$mount_points" && return 0
	return 1
}

cmd_auto() {
	if [[ $# -eq 0 ]]; then
		cmd_list "$@" || cmd_usage
	elif [[ $# -eq 1 ]]; then
		initialize_container "$1"
		if [[ -e $mapper_path ]]; then
			cmd_close "$@"
		else
			cmd_open "$@"
		fi
	else
		cmd_usage "$@"
	fi
}


PROGRAM="$(basename "$0")"

[[ $UID != 0 ]] && exec sudo -p "$PROGRAM must be run as root. Please enter the password for %u to continue: " "$(readlink -f "$0")" "$@"

case "$1" in
	h|help|-h|--help) shift;	cmd_usage "$@" ;;
	n|new|create) shift;		cmd_new "$@" ;;
	d|del|delete) shift;		cmd_delete "$@" ;;
	c|close) shift;			cmd_close "$@" ;;
	l|list) shift;			cmd_list "$@" ;;
	o|open) shift;			cmd_open "$@" ;;
	*)				cmd_auto "$@" ;;
esac
exit 0
