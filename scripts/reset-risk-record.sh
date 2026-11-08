#!/system/bin/sh
# Only the tested official 11.3.1 build and known diagnostic-only records.
set -eu
fail() { echo "STOP: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || fail "Run in an Android root shell."
mode=${1:-check}
case "$mode" in check|reset|restore) ;; *) fail "Usage: sh $0 check|reset|restore [backup-directory]" ;; esac
pkg=com.android.bankabc
data=/data/user/0/$pkg
record=$data/envc.push
expected=cd6ed62253abb06a6ee05e7ce4ba062fcf08e6475c12a7daef4675d65e68b395
pm path --user 0 "$pkg" >/dev/null 2>&1 || fail "App not installed for owner."
dumpsys package "$pkg" | grep -q 'versionName=11.3.1$' || fail "Version is not 11.3.1."
apks=$(pm path --user 0 "$pkg")
[ "$(printf '%s\n' "$apks" | wc -l | tr -d ' ')" = 1 ] || fail "Split or unexpected package layout."
apk=${apks#package:}
[ -f "$apk" ] || fail "APK path unavailable."
actual=$(sha256sum "$apk" | cut -d ' ' -f 1)
[ "$actual" = "$expected" ] || fail "APK hash differs from tested build."
[ -d "$data" ] && [ ! -L "$data" ] || fail "Owner data unavailable or symlinked. Unlock phone first."
[ ! -L "$record" ] || fail "Record is a symbolic link."
check_record() {
    [ -f "$1" ] || fail "Not a regular record file."
    [ "$(wc -c < "$1" | tr -d ' ')" = 25 ] || fail "Unknown record length."
    value=$(cat "$1")
    case "$value" in
        2S5o50ox36zpDMQ09UzN0g==|DGyB3UCEp1zEYJLXnOMrwQ==|wjYx7Sc41HTg8QaTKvtwRw==|WlhlLoFPWBoufvvLGE0MOQ==) ;;
        *) fail "Unknown record content. Nothing changed." ;;
    esac
}
if [ -e "$record" ]; then
    flags=$(lsattr "$record" 2>/dev/null | cut -d ' ' -f 1) || fail "Cannot inspect file attributes."
    [ -n "$flags" ] || fail "File attributes unavailable."
    case "$flags" in *i*|*a*) fail "Immutable/append-only record. Nothing changed." ;; esac
    check_record "$record"
fi
if [ "$mode" = restore ]; then
    backup=${2:-}
    [ -n "$backup" ] || fail "Supply the exact backup directory printed by reset."
    case "$backup" in /data/local/tmp/abc1131-risk-backup-*) ;; *) fail "Unexpected backup path." ;; esac
    [ -d "$backup" ] && [ ! -L "$backup" ] || fail "Invalid backup directory."
    [ ! -L "$backup/envc.push" ] || fail "Backup is a symbolic link."
    check_record "$backup/envc.push"
    am force-stop --user 0 "$pkg"
    cat "$backup/envc.push" > "$record"
    chown "$(stat -c %u "$data"):$(stat -c %g "$data")" "$record"
    chmod 600 "$record"
    restorecon "$record"
    cmp -s "$backup/envc.push" "$record" || fail "Restore verification failed."
    echo "Original risk record restored. Other app files untouched."
    exit 0
fi
if [ ! -e "$record" ]; then
    echo "No risk record exists. Nothing to reset."
    exit 0
fi
echo "Matched tested APK and a known diagnostic record."
[ "$mode" = reset ] || { echo "Read-only check complete. No changes."; exit 0; }
umask 077
backup=/data/local/tmp/abc1131-risk-backup-$(date +%Y%m%d-%H%M%S)-$$
mkdir "$backup" || fail "Cannot create backup."
am force-stop --user 0 "$pkg"
# Re-check after stopping the process, before making the backup or writing.
check_record "$record"
cp -p "$record" "$backup/envc.push"
cmp -s "$record" "$backup/envc.push" || fail "Backup verification failed."
printf '%s\n' 'WlhlLoFPWBoufvvLGE0MOQ==' > "$record"
[ "$(cat "$record")" = 'WlhlLoFPWBoufvvLGE0MOQ==' ] || fail "Write verification failed. Backup: $backup"
echo "Risk record reset. Backup: $backup"
echo "Restore: sh $0 restore $backup"
echo "Launch the app normally. No account database was cleared or modified."
