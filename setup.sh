#!/usr/bin/env bash
# security-vps: pengamanan awal VPS baru secara interaktif, dijalankan
# sebagai ROOT. Teruji di Ubuntu 24.04, Ubuntu 26.04, Debian 13. Berhenti
# meminta konfirmasi di setiap titik yang bisa membuat kamu terkunci (lihat README.md).
#
#   git clone https://github.com/phpunix/security-vps.git   # di sesi root VPS baru
#   bash security-vps/setup.sh                              # sesi root JANGAN ditutup sampai selesai
#
# Nama user dan port SSH wajib diketik (tanpa default). Default lainnya (cukup
# Enter): swap 4G, whitelist = IP yang sedang kamu pakai (terdeteksi otomatis
# dari sesi SSH; tanpa whitelist kalau tidak terdeteksi), zona waktu Asia/Jakarta.
#
# Tiap aksi tampil berurutan: [>] judul, output perintah langsung, lalu status
# [✓] BERHASIL / [✗] GAGAL + lama eksekusi. Semua juga direkam di
# /root/security-vps-log/setup-TANGGAL-JAM.log (salinan untuk user: ~/security-vps-log/).
# Aman dijalankan ulang: langkah yang sudah beres dilewati.
# Lihat alurnya tanpa mengubah apa pun:  bash setup.sh --dry-run
set -Eeuo pipefail
# Output program dibaca script (mis. "Status: active" dari ufw), jadi paksa
# bahasa Inggris + UTF-8. Juga mencegah peringatan "Setting locale failed" dari
# perl/apt saat klien SSH mengirim locale yang tidak terpasang di VPS (LC_TIME=id_ID).
export LC_ALL=C.UTF-8
# "... | run ..." / "... | tulis ...": jalankan ujung pipa di shell ini, supaya
# keterangan gagal (GAGAL_DESC) tidak hilang di subshell.
shopt -s lastpipe

DRY=0; [ "${1:-}" = --dry-run ] && DRY=1
REPO=$(cd "$(dirname "$0")" && pwd)
SSHD_CONF=/etc/ssh/sshd_config.d/00-hardening.conf
RK=/root/.ssh/authorized_keys
export DEBIAN_FRONTEND=noninteractive
# needrestart (Ubuntu) bisa menunggu jawaban saat upgrade: restart layanan otomatis.
# apt-listchanges/ucf: jangan tampilkan pager, pertahankan config lama (mis. sshd_config).
export NEEDRESTART_MODE=a APT_LISTCHANGES_FRONTEND=none UCF_FORCE_CONFFOLD=1
# Lock::Timeout: tunggu kalau dpkg sedang dipakai unattended-upgrades/cloud-init.
# (Lock::Timeout bawaan Ubuntu hanya untuk perintah "apt", bukan "apt-get".)
APT=(apt-get -y -o DPkg::Lock::Timeout=300 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
# Log tiap run: /root/security-vps-log/ (salinan untuk user: ~/security-vps-log/).
LOG_DIR=/root/security-vps-log
if [ $DRY = 1 ]; then LOG=${TMPDIR:-/tmp}/security-vps-dry-run-$(date +%Y%m%d-%H%M%S).log
else LOG=$LOG_DIR/setup-$(date +%Y%m%d-%H%M%S).log; fi
GAGAL_DESC=""

H_=$'\033[1m' HIJ=$'\033[32m' MER=$'\033[31m' KUN=$'\033[33m' RED=$'\033[2m' N_=$'\033[0m'
catat()  { printf '%s\n' "$*" >>"$LOG"; }
langkah(){ printf '\n%s== %s%s\n' "$H_" "$*" "$N_"; catat "" "== $*"; }
info()   { printf '    %s\n' "$*"; catat "    $*"; }
ok()     { printf '  %s[✓]%s %s\n' "$HIJ" "$N_" "$*"; catat "  [OK] $*"; }
awas()   { printf '  %s[!]%s %s\n' "$KUN" "$N_" "$*"; catat "  [AWAS] $*"; }
gagal()  { GAGAL_DESC="$*"; exit 1; }

# run [-t] [-o] "keterangan" perintah...
#   -t  interaktif (passwd): langsung ke terminal tanpa awalan "│" dan tidak
#       direkam, karena prompt tanpa baris baru tidak akan tampil lewat pipa
#   -o  opsional: kalau gagal hanya [!] DILEWATI, script jalan terus
# Tampilan berurutan, tanpa ditimpa: [>] judul, output perintah langsung
# (awalan "│", juga masuk log), lalu baris status + lama eksekusi.
run() {
    local tty=0 opsional=0 desc out rc label mulai lama n
    while [[ ${1:-} == -[to] ]]; do
        case $1 in -t) tty=1;; -o) opsional=1;; esac; shift
    done
    # CMD_LABEL=... run ...  mengganti perintah yang ditampilkan (mis. isi file panjang).
    desc=$1; shift; label=${CMD_LABEL:-$*}; GAGAL_DESC=""
    catat "  \$ $label"
    if [ $DRY = 1 ]; then
        printf '  %s[-] DRY-RUN %s%s %s(%s)%s\n' "$RED" "$N_" "$desc" "$RED" "$label" "$N_"; return 0
    fi
    printf '  %s[>]%s %s %s(%s)%s\n' "$H_" "$N_" "$desc" "$RED" "$label" "$N_"
    mulai=$SECONDS
    if [ $tty = 1 ]; then
        if "$@"; then rc=0; else rc=$?; fi
    else
        out=$(mktemp)
        if "$@" 2>&1 | tee -a "$LOG" "$out" | sed -u 's/^/      │ /'; then rc=0; else rc=${PIPESTATUS[0]}; fi
    fi
    lama=$((SECONDS - mulai))
    if [ $rc = 0 ]; then
        printf '  %s[✓] BERHASIL%s %s %s(%s dtk)%s\n' "$HIJ" "$N_" "$desc" "$RED" "$lama" "$N_"
        catat "  [BERHASIL] $desc ($lama dtk)"
        [ $tty = 1 ] || rm -f "$out"
        return 0
    fi
    if [ $opsional = 1 ]; then
        printf '  %s[!] DILEWATI%s %s (exit %s, tidak wajib)\n' "$KUN" "$N_" "$desc" "$rc"
        catat "  [DILEWATI] $desc (exit $rc)"
        [ $tty = 1 ] || rm -f "$out"
        return 0
    fi
    printf '  %s[✗] GAGAL%s %s (exit %s, %s dtk)\n' "$MER" "$N_" "$desc" "$rc" "$lama"
    catat "  [GAGAL] $desc (exit $rc)"
    if [ $tty = 0 ]; then
        # Output sudah tampil di atas; ulangi ekornya kalau panjang (mis. apt).
        n=$(wc -l <"$out")
        if [ "$n" -gt 10 ]; then
            printf '      Keterangan (output terakhir):\n'; tail -n 10 "$out" | sed 's/^/      │ /'
        elif [ "$n" = 0 ]; then
            printf '      Keterangan: perintah tidak mengeluarkan pesan\n'
        fi
        rm -f "$out"
    fi
    GAGAL_DESC="$desc gagal - lihat keterangan di atas."
    return $rc
}
# tunggu "keterangan" DETIK perintah...: cek tiap detik sampai berhasil atau
# batas waktu habis. Untuk layanan yang butuh waktu siap setelah restart.
# fail2ban yang baru dipasang membaca riwayat journal ke belakang, termasuk uji
# login root pemilik di langkah 7 ("ROOT LOGIN REFUSED", 2 kegagalan per uji).
# Ban dari aksi nftables juga memutus sesi yang sedang terbuka di port itu.
# Bebaskan IP yang dipakai untuk setup ini kalau ikut ter-ban.
bebaskan_ip_sendiri() {
    [ $DRY = 0 ] && [ -n "${KLIEN:-}" ] || return 0
    local j daftar
    for j in sshd sshd-lambat recidive; do
        daftar=$(fail2ban-client status "$j" 2>/dev/null | sed -n 's/.*Banned IP list:\s*//p')
        if tr ' ' '\n' <<<"$daftar" | grep -qxF -- "$KLIEN"; then
            awas "IP-mu $KLIEN ter-ban di jail $j (kemungkinan dari uji login root); dibebaskan."
            run "Bebaskan $KLIEN dari jail $j" fail2ban-client set "$j" unbanip "$KLIEN"
        fi
    done
}
tunggu() {
    local desc=$1 maks=$2 i; shift 2
    catat "  \$ tunggu maks $maks dtk: $*"
    if [ $DRY = 1 ]; then
        printf '  %s[-] DRY-RUN %s%s %s(maks %s dtk)%s\n' "$RED" "$N_" "$desc" "$RED" "$maks" "$N_"; return 0
    fi
    printf '  %s[>]%s %s %s(cek tiap detik, maks %s dtk)%s\n' "$H_" "$N_" "$desc" "$RED" "$maks" "$N_"
    for ((i = 0; i <= maks; i++)); do
        if "$@" &>/dev/null; then
            printf '  %s[✓] BERHASIL%s %s %s(%s dtk)%s\n' "$HIJ" "$N_" "$desc" "$RED" "$i" "$N_"
            catat "  [BERHASIL] $desc ($i dtk)"; return 0
        fi
        [ "$i" -lt "$maks" ] && sleep 1
    done
    printf '  %s[✗] GAGAL%s %s (belum siap setelah %s dtk)\n' "$MER" "$N_" "$desc" "$maks"
    catat "  [GAGAL] $desc (belum siap setelah $maks dtk)"
    GAGAL_DESC="$desc: belum siap setelah $maks detik."
    return 1
}
# tulis "keterangan" FILE MODE  (isi dari stdin)
tulis() {
    local isi; isi=$(cat)
    # Di luar dry-run baris log "$ tulis FILE" dicatat oleh run (CMD_LABEL).
    if [ $DRY = 1 ]; then
        catat "  \$ tulis $2"
        printf '  %s[-] DRY-RUN %s%s %s(%s)%s\n' "$RED" "$N_" "$1" "$RED" "$2" "$N_"
        sed 's/^/      │ /' <<<"$isi"; return 0
    fi
    CMD_LABEL="tulis $2" run "$1" bash -c 'printf "%s\n" "$1" >"$2" && chmod "$3" "$2"' _ "$isi" "$2" "$3"
}
# tanya_wajib VAR "pertanyaan"  -> tanpa default: jawaban kosong ditanya ulang
tanya_wajib(){
    local j
    while :; do
        read -r -p "    $2: " j; catat "    $2 -> $j"
        [ -n "$j" ] && break
        awas "Wajib diketik (tidak ada default)."
    done
    printf -v "$1" '%s' "$j"
}
# tanya VAR "pertanyaan" default  (Enter = default; di log ditandai "(default)")
tanya()  {
    local j d=""; read -r -p "    $2 [$3]: " j; printf -v "$1" '%s' "${j:-$3}"
    [ -n "$j" ] || d=" (default)"; catat "    $2 -> ${!1}$d"
}
# yakin "pertanyaan" y|n  -> sukses kalau jawabannya ya
yakin()  {
    local j p=y/N; [ "$2" = y ] && p=Y/n
    read -r -p "    $1 [$p]: " j; catat "    $1 -> ${j:-$2}"; [[ ${j:-$2} =~ ^[yY] ]]
}
# Untuk titik rawan terkunci: harus mengetik "ya" atau "tidak" (huruf besar/kecil
# bebas). Enter kosong atau jawaban lain ("yes", salah ketik) ditanya ulang,
# bukan dianggap gagal.
ketik_ya(){
    local j
    while :; do
        read -r -p "    $1 Ketik YA atau TIDAK: " j; catat "    $1 -> $j"
        case "${j,,}" in
            ya) return 0;;
            tidak) return 1;;
            *) awas "Jawaban '$j' tidak dikenali; ketik YA atau TIDAK.";;
        esac
    done
}
# terbukti_login USER PORT SEJAK: ada login USER dengan key sejak SEJAK yang
# koneksinya MASIH TERBUKA ke PORT. Log sshd (LogLevel INFO) tidak mencatat port
# server, jadi IP:port klien dari log dicocokkan dengan koneksi aktif di ss.
terbukti_login() {
    local u=$1 p=$2 sejak=$3 ip cp aktif
    aktif=$(ss -tnH state established "( sport = :$p )" | awk '{print $4}')
    while read -r ip cp; do
        [ -n "$cp" ] || continue
        [[ $ip == *:* ]] && ip="[$ip]"
        grep -qxF -- "$ip:$cp" <<<"$aktif" && return 0
    done < <(journalctl -u ssh --since "$sejak" --no-pager -o cat 2>/dev/null \
             | sed -nE "s/^Accepted publickey for $u from ([0-9a-fA-F.:]+) port ([0-9]+) .*/\1 \2/p")
    return 1
}
# deteksi_sesi: isi SESI_USER (yang login lewat SSH: root, atau user di balik
# sudo), KLIEN (IP pemilik), SESI_CPORT (port klien) dan IP (IP VPS untuk
# instruksi). Sumber utama SSH_CONNECTION; kalau kosong (lewat sudo/sudo -i,
# tmux, screen) dicari sesi SSH SESI_USER yang masih terbuka: login di journal
# (boot ini) yang IP:port kliennya masih ada sebagai koneksi aktif di ss.
deteksi_sesi() {
    local cip cport sip aktif ip p ipb lokal
    SESI_USER=${SUDO_USER:-root}; SESI_SUMBER=""
    read -r cip cport sip _ <<<"${SSH_CONNECTION:-}"
    if [ -z "${cport:-}" ]; then
        aktif=$(ss -tnH state established 2>/dev/null | awk '{print $3, $4}')
        while read -r ip p; do
            [ -n "$p" ] || continue
            ipb=$ip; [[ $ip == *:* ]] && ipb="[$ip]"
            lokal=$(awk -v peer="$ipb:$p" '$2 == peer {print $1; exit}' <<<"$aktif")
            [ -n "$lokal" ] || continue
            # Ambil yang terakhir (login paling baru yang masih terbuka).
            cip=$ip; cport=$p; sip=${lokal%:*}; sip=${sip#[}; sip=${sip%]}
            SESI_SUMBER="dari sesi SSH $SESI_USER yang masih terbuka"
        done < <(journalctl -b -u ssh --no-pager -o cat 2>/dev/null \
                 | sed -nE "s/^Accepted \S+ for $SESI_USER from ([0-9a-fA-F.:]+) port ([0-9]+) .*/\1 \2/p")
    fi
    KLIEN=${cip:-}; SESI_CPORT=${cport:-}; IP=${sip:-IP-VPS}
}
# terbukti_sudo USER SEJAK: USER menjalankan "sudo true" sejak SEJAK (tercatat
# di journal; "sudo -v" tidak meninggalkan baris COMMAND yang bisa dicocokkan).
terbukti_sudo() {
    journalctl -t sudo --since "$2" --no-pager -o cat 2>/dev/null \
        | grep -E "^\s*$1 : .*USER=root ; COMMAND=(/usr)?/bin/true$" >/dev/null
}
# konfirmasi_login "pertanyaan" PORT SEJAK: jawaban YA saja tidak cukup; login
# dan sudo harus terbukti dari log sistem. Kalau belum, tanya ulang.
konfirmasi_login() {
    local p=$2 sejak=$3 kurang
    while :; do
        ketik_ya "$1" || return 1
        [ $DRY = 0 ] || return 0
        kurang=""
        terbukti_login "$USERNAME" "$p" "$sejak" || kurang+=" login $USERNAME dengan key di port $p yang masih terbuka;"
        terbukti_sudo "$USERNAME" "$sejak" || kurang+=" 'sudo true' oleh $USERNAME;"
        if [ -z "$kurang" ]; then
            ok "Terbukti dari log sistem: $USERNAME login dengan key di port $p dan sudo berhasil"; return 0
        fi
        awas "Belum terbukti dari log sistem:${kurang%;}."
        info "Login sebagai $USERNAME (bukan root), biarkan sesi uji itu TERBUKA, jalankan 'sudo true', lalu jawab lagi."
    done
}
# grep tanpa -q: dengan pipefail, -q bisa memicu SIGPIPE di sisi kiri pipa.
dengar() { ss -tlnH | awk '{print $4}' | grep -E ":$1$" >/dev/null; }
aturan22(){ ufw status 2>/dev/null | grep -E '^(22(/tcp)?|OpenSSH) ' >/dev/null; }
# Di VPS baru unattended-upgrades/cloud-init sering sedang memakai apt di menit
# pertama. Cek lock-nya langsung (lslocks, util-linux), bukan nama proses: proses
# "unattended-upgrade-shutdown" selalu hidup dan namanya mirip pemakai apt.
apt_bebas(){
    ! lslocks -n -o PATH 2>/dev/null \
        | grep -E '^/var/lib/dpkg/lock(-frontend)?$|^/var/lib/apt/lists/lock$|^/var/cache/apt/archives/lock$' >/dev/null
}
# kunci_saja <FILE: dari tiap baris authorized_keys ambil mulai tipe key
# ("ssh-ed25519 AAAA... komentar"), buang opsi di depannya. Baris kosong,
# komentar, dan baris tanpa key yang valid dilewati, termasuk key yang terlihat
# benar tapi tidak bisa dibaca ssh-keygen (mis. terpotong). Baris terakhir tanpa
# newline tetap dibaca (awk).
kunci_saja() {
    local k
    awk '{ for (i = 1; i < NF; i++)
             if ($i ~ /^(ssh-(ed25519|rsa|dss)|ecdsa-sha2-nistp(256|384|521)|sk-(ssh-ed25519|ecdsa-sha2-nistp256)@openssh\.com)$/ \
                 && $(i + 1) ~ /^AAAA[A-Za-z0-9+\/]+=*$/) {
                 s = $i; for (j = i + 1; j <= NF; j++) s = s " " $j; print s; next
             } }' | while IFS= read -r k; do
        if ssh-keygen -lf <(printf '%s\n' "$k") >/dev/null 2>&1; then printf '%s\n' "$k"; fi
    done
}
# sidik "KEY": fingerprint satu key ("256 SHA256:... komentar (ED25519)").
sidik() { ssh-keygen -lf <(printf '%s\n' "$1") 2>/dev/null || echo "(fingerprint tidak terbaca)"; }
# pilih_kunci "DAFTAR": 1 key -> dipakai langsung; 2+ key -> tampilkan
# fingerprint + komentar bernomor, pemilik memilih (mis. "1 3" atau "semua").
# Tampilan & pertanyaan ke stderr, karena hasil (key terpilih) dikirim lewat stdout.
pilih_kunci() {
    local daftar=$1 n i k j pilih=""
    n=$(grep -c . <<<"$daftar")
    if [ "$n" -le 1 ]; then printf '%s\n' "$daftar"; return 0; fi
    {
        awas "Root punya $n key. Bisa ada key milik provider; hanya yang dipilih disalin ke $USERNAME:"
        i=0
        while IFS= read -r k; do
            i=$((i + 1))
            printf '      %s) %s\n' "$i" "$(sidik "$k")"
        done <<<"$daftar"
    } >&2
    while :; do
        read -r -p "    Nomor key yang disalin (mis. 1 atau 1 3; 'semua'): " j; catat "    pilih key -> $j"
        if [ "${j,,}" = semua ]; then pilih=$(seq "$n"); break; fi
        pilih=$(tr -s ' ,' '\n' <<<"$j" | grep -E '^[0-9]+$' | sort -un || true)
        if [ -n "$pilih" ] && [ "$(tr ' ,' '\n\n' <<<"$j" | grep -c .)" = "$(grep -c . <<<"$pilih")" ] \
           && [ "$(tail -1 <<<"$pilih")" -le "$n" ] && [ "$(head -1 <<<"$pilih")" -ge 1 ]; then break; fi
        awas "Pilihan '$j' tidak valid; ketik nomor 1-$n (dipisah spasi) atau 'semua'." >&2
    done
    awk 'NR == FNR { p[$1]; next } (FNR in p)' <(printf '%s\n' "$pilih") <(printf '%s\n' "$daftar")
    info "Key terpilih: $(paste -sd' ' <<<"$pilih")" >&2
}
# tambah_baris "keterangan" FILE BARIS: tambahkan newline dulu kalau file tidak
# diakhiri newline. Tanpa ini baris baru menempel ke baris terakhir, mis. merusak
# entri root di /etc/fstab (VPS gagal boot) atau key lama di authorized_keys.
tambah_baris() {
    CMD_LABEL="tambah baris ke $2" run "$1" bash -c \
        '[ ! -s "$1" ] || [ -z "$(tail -c 1 "$1")" ] || printf "\n" >>"$1"; printf "%s\n" "$2" >>"$1"' _ "$2" "$3"
}

# salin_log: salinan log untuk user baru (~/security-vps-log/, izin 600), supaya
# bisa dibaca tanpa sudo setelah login root mati. Ditulis dengan hak user itu
# sendiri (runuser), bukan root: kalau ~/security-vps-log diganti symlink ke
# folder sistem, root tidak ikut menaruh file di sana. Dilewati kalau user
# belum ada (script berhenti sebelum langkah 2) atau dry-run. Log run
# sebelumnya yang belum tersalin (mis. run yang berhenti untuk reboot setelah
# upgrade, sebelum user dibuat) ikut disalin.
LOG_USER=""
salin_log() {
    [ $DRY = 0 ] && [ -n "${USERNAME:-}" ] && [ -n "${H:-}" ] && [ -d "$H" ] && id "$USERNAME" &>/dev/null || return 0
    local d="$H/security-vps-log" f
    runuser -u "$USERNAME" -- sh -c 'cd / && mkdir -p "$1" && chmod 700 "$1"' _ "$d" 2>/dev/null || return 0
    for f in "$LOG_DIR"/setup-*.log; do
        [ -f "$f" ] || continue
        # Log run ini selalu disalin ulang (isinya bertambah); log lama hanya sekali.
        [ "$f" = "$LOG" ] || [ ! -e "$d/${f##*/}" ] || continue
        runuser -u "$USERNAME" -- sh -c 'cd / && umask 077 && cat >"$1" && chmod 600 "$1"' _ "$d/${f##*/}" <"$f" 2>/dev/null || continue
        [ "$f" != "$LOG" ] || LOG_USER="$d/${f##*/}"
    done
}
# Dijalankan saat script keluar (berhasil atau berhenti): pesan BERHENTI, lalu salin log.
berhenti() {
    local rc=$?
    if [ $rc != 0 ]; then
        printf '\n%s[✗] BERHENTI:%s %s\n' "$MER" "$N_" "${GAGAL_DESC:-perintah gagal (exit $rc)}"
        catat "[BERHENTI] ${GAGAL_DESC:-exit $rc}"
    fi
    salin_log || true
    if [ $rc != 0 ]; then
        printf '    Log lengkap : %s\n' "$LOG"
        [ -z "$LOG_USER" ] || printf '    Salinan log : %s (bisa dibaca %s tanpa sudo)\n' "$LOG_USER" "$USERNAME"
        printf '    Jangan tutup %s; perbaiki penyebabnya lalu jalankan ulang script.\n' "${SESI_INI:-sesi root ini}"
    elif [ -n "$LOG_USER" ]; then
        printf '    Salinan log : %s (bisa dibaca %s tanpa sudo: cat ~/security-vps-log/%s)\n' \
            "$LOG_USER" "$USERNAME" "${LOG##*/}"
    fi
}
# Kegagalan run/tulis sudah dijelaskan run sendiri; selain itu catat baris dan perintahnya.
# ($BASH_COMMAND tetap "return $rc" setelah run gagal, juga di sisi pemanggil.)
trap '[[ ${FUNCNAME[0]:-} == run || $BASH_COMMAND == return\ * || $BASH_COMMAND == run\ * || $BASH_COMMAND == CMD_LABEL=* ]] \
      || GAGAL_DESC="perintah gagal di baris $LINENO: $BASH_COMMAND"' ERR
trap berhenti EXIT

# Ubuntu 22.10+ memakai socket activation: port diatur ssh.socket, dan
# daemon-reload membuat generator membaca Port baru. Debian memakai ssh.service.
terapkan_ssh() {
    if systemctl is-enabled -q ssh.socket 2>/dev/null || systemctl is-active -q ssh.socket 2>/dev/null; then
        run "Muat ulang unit systemd (generator membaca Port dari konfigurasi)" systemctl daemon-reload
        run "Restart ssh.socket (terapkan port sesuai konfigurasi)" systemctl restart ssh.socket
        run -o "Restart ssh.service" systemctl restart ssh.service
    else
        run "Restart layanan SSH" systemctl restart ssh
    fi
}

# ---------------------------------------------------------------------------
[ $DRY = 1 ] || install -d -m 700 "$LOG_DIR"
: >"$LOG"; chmod 600 "$LOG"
catat "security-vps setup.sh $(date '+%F %T')"
langkah "0. Pemeriksaan awal"
if [ $DRY = 1 ]; then
    awas "MODE --dry-run: tidak ada yang diubah, perintah hanya ditampilkan"
else
    [ "$(id -u)" = 0 ] || gagal "Jalankan sebagai root (login root, lalu: bash $0)"
fi
info "Log: $LOG"

. /etc/os-release
case "${ID:-}" in
    ubuntu|debian) ok "Sistem operasi: $PRETTY_NAME";;
    *) gagal "Hanya untuk Ubuntu/Debian (terdeteksi: ${PRETTY_NAME:-tidak diketahui})";;
esac
for f in files/00-hardening.conf files/jail.local files/sshd-lambat.local files/fail2ban.local cek-keamanan.sh; do
    [ -f "$REPO/$f" ] || gagal "File repo tidak ada: $REPO/$f"
done
ok "File repo lengkap ($REPO)"
grep -E '^\s*Include\s+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config >/dev/null \
    || gagal "/etc/ssh/sshd_config tidak memuat 'Include /etc/ssh/sshd_config.d/*.conf'"
ok "sshd_config membaca sshd_config.d/"

# Key root disalin ke user baru, jadi harus ada (kecuali sudah dinonaktifkan di run sebelumnya).
if [ -s "$RK" ]; then
    # Fingerprint dari key yang sudah dibersihkan (kunci_saja), bukan file
    # mentah: satu baris rusak membuat ssh-keygen -lf gagal dan script berhenti
    # tanpa penjelasan.
    KUNCI_RK=$(kunci_saja <"$RK")
    n_valid=$(grep -c . <<<"$KUNCI_RK" || true)
    n_baris=$(grep -cvE '^[[:space:]]*(#|$)' "$RK" || true)
    if [ "$n_valid" -gt 0 ]; then
        RK_ADA=1; ok "Key root ditemukan ($n_valid):"
        while IFS= read -r k; do printf '      │ %s\n' "$(sidik "$k")"; done <<<"$KUNCI_RK"
    else
        RK_ADA=0; awas "$RK tidak berisi key SSH yang valid"
    fi
    [ "$n_baris" -le "$n_valid" ] || awas "$((n_baris - n_valid)) baris di $RK bukan key yang valid (rusak/terpotong); dilewati."
elif [ $DRY = 1 ]; then
    RK_ADA=1; info "(dry-run: $RK tidak bisa dibaca, dianggap ada)"
else
    RK_ADA=0; info "root tidak punya authorized_keys (mungkin sudah dinonaktifkan di run sebelumnya)"
fi

deteksi_sesi
# Run ulang setelah setup berjalan lewat sudo dari sesi user (login SSH root sudah mati).
SESI_INI="sesi $SESI_USER ini"
if [ -n "$KLIEN" ]; then
    info "Sesi ini: $SESI_USER dari $KLIEN ke $IP${SESI_SUMBER:+ ($SESI_SUMBER)}"
else
    info "Sesi SSH yang menjalankan script ini tidak terdeteksi (mis. web console); IP diisi manual."
fi
# IP privat = VPS di belakang NAT: instruksi perlu IP publik dari panel provider.
[[ $IP =~ ^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.) ]] \
    && awas "IP $IP adalah IP privat (NAT); di instruksi login, ganti dengan IP publik dari panel provider."

# Nilai default (Enter). Whitelist: IP sesi SSH yang menjalankan script,
# terdeteksi otomatis oleh deteksi_sesi (SSH_CONNECTION, atau journal kalau
# lewat sudo); tanpa whitelist kalau tidak terdeteksi (mis. web console).
# Nama user dan port SSH sengaja tanpa default: wajib diketik pemilik.
DEF_SWAP=4G DEF_ZONA=Asia/Jakarta DEF_WL=${KLIEN:--}
info "Nama user dan port SSH wajib diketik. Nilai default lainnya (cukup tekan Enter):"
info "  swap        $DEF_SWAP (tidak ditanya kalau swap sudah ada)"
if [ -n "$KLIEN" ]; then
    info "  whitelist   $KLIEN (IP yang sedang kamu pakai, terdeteksi otomatis)"
else
    info "  whitelist   tidak ada (IP-mu tidak terdeteksi)"
fi
info "  zona waktu  $DEF_ZONA"
tanya_wajib USERNAME "Nama user non-root (wajib diketik)"
[[ $USERNAME =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && [ "$USERNAME" != root ] || gagal "Nama user tidak valid: $USERNAME"
H=$(getent passwd "$USERNAME" | cut -d: -f6 || true); H=${H:-/home/$USERNAME}
AK=$H/.ssh/authorized_keys
if [ $RK_ADA = 0 ] && [ $DRY = 0 ] && [ ! -s "$AK" ]; then
    gagal "Tidak ada key SSH: $RK maupun $AK kosong. Tambahkan key di panel provider dulu."
fi
# ALLOW: isi AllowUsers. Run ulang mempertahankan daftar dari run sebelumnya,
# termasuk user yang ditambahkan pemilik (mis. deploy), asalkan $USERNAME ada
# di dalamnya. Tanpa $USERNAME berarti ganti user: tidak didukung, karena
# AllowUsers baru langsung menolak user lama begitu diterapkan.
ALLOW=$USERNAME
# diizinkan USER: USER ada di ALLOW (nama persis, atau USER@host). Tanpa pipe
# (grep -q + pipefail bisa gagal karena SIGPIPE) dan tanpa glob (pola "ops*").
diizinkan() {
    local e; local -a d; read -ra d <<<"$ALLOW"
    for e in "${d[@]}"; do [[ $e == "$1" || $e == "$1"@* ]] && return 0; done
    return 1
}
if [ -f "$SSHD_CONF" ]; then
    lama_allow=$(sed -n 's/^AllowUsers[[:space:]]\+//p' "$SSHD_CONF" | tr -s ' \t' '\n' | awk 'NF && !s[$0]++' | paste -sd' ' || true)
    if [ -n "$lama_allow" ]; then
        # Disalin ke sed (KONF): hanya karakter pola AllowUsers yang wajar.
        read -ra entri <<<"$lama_allow"
        for e in "${entri[@]}"; do
            [[ $e =~ ^!?[A-Za-z0-9._*?-]+(@[A-Za-z0-9.:/*?_-]+)?$ ]] \
                || gagal "AllowUsers di $SSHD_CONF berisi entri yang tidak dikenali: $e. Perbaiki manual lalu jalankan ulang."
        done
        ALLOW=$lama_allow
        diizinkan "$USERNAME" \
            || gagal "SSH sudah dibatasi untuk $lama_allow (AllowUsers di $SSHD_CONF), tanpa $USERNAME. Jalankan ulang dengan user itu, atau tambahkan $USERNAME di baris AllowUsers."
        [ "$ALLOW" = "$USERNAME" ] || info "AllowUsers dari run sebelumnya dipertahankan: $ALLOW"
    fi
fi
# User lain yang punya key (mis. user bawaan cloud "ubuntu"/"debian"/"admin")
# ditolak SSH mulai langkah 6. Sudo tanpa password miliknya tidak diubah script;
# cek-keamanan.sh di langkah 12 menandainya beserta cara memperbaikinya.
LAIN=""
while IFS=: read -r n _ _ _ _ h _; do
    if [ "$n" != root ] && [ -s "$h/.ssh/authorized_keys" ] && ! diizinkan "$n"; then LAIN+=" $n"; fi
done < <(getent passwd)
if [ -n "$LAIN" ]; then
    info "User lain dengan key SSH:$LAIN. Mulai langkah 6 hanya $ALLOW yang boleh login SSH"
    info "(AllowUsers); sesi yang sedang terbuka tidak terputus. Setelah itu masuk sebagai $USERNAME."
fi

tanya_wajib PORT "Port SSH baru, 1024-65535 (wajib diketik)"
[[ $PORT =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1024 ] && [ "$PORT" -le 65535 ] || gagal "Port tidak valid: $PORT"
# Ganti port saat run ulang tidak didukung: transisi memakai port 22 sebagai
# jalan kembali, padahal setelah setup selesai 22 sudah ditutup dan port lama
# langsung berhenti listen. Tolak di sini, sebelum ada yang diubah.
if [ -f "$SSHD_CONF" ]; then
    lama_port=$(sed -nE 's/^Port[[:space:]]+([0-9]+).*/\1/p' "$SSHD_CONF" | grep -vxE "22|$PORT" | paste -sd' ' || true)
    [ -z "$lama_port" ] || gagal "SSH sudah memakai port $lama_port dari run sebelumnya. Mengganti port lewat script ini belum didukung (bisa mengunci). Jalankan ulang dengan port $lama_port."
fi
# Port yang sudah dipakai SSH sendiri (run ulang) bukan bentrok. Dicek dari
# konfigurasi, bukan nama proses: dengan socket activation listener tampil
# sebagai "systemd", dan tanpa root (dry-run) ss tidak menampilkan nama proses.
port_ssh=$( { sshd -T 2>/dev/null | awk '$1 == "port" {print $2}'
              sed -nE 's/^Port[[:space:]]+([0-9]+).*/\1/p' "$SSHD_CONF" 2>/dev/null; } || true)
if grep -qx -- "$PORT" <<<"$port_ssh"; then
    ok "Port $PORT sudah dipakai SSH sendiri (run sebelumnya)"
else
    lain=$(ss -tlnpH "( sport = :$PORT )" 2>/dev/null || true)
    [ -z "$lain" ] || gagal "Port $PORT sudah dipakai program lain: $lain"
fi

SWAP_ADA=0
if swapon --show --noheadings | grep . >/dev/null; then
    SWAP=0; SWAP_ADA=1; info "Swap sudah ada, langkah swap dilewati"
else
    tanya SWAP "Ukuran swap, misalnya 2G/4G (0 = tanpa swap)" "$DEF_SWAP"
    [[ $SWAP =~ ^(0|[1-9][0-9]*[MG])$ ]] || gagal "Ukuran swap tidak valid: $SWAP"
fi

# Whitelist opsional: SFTP dari file manager (mis. Dolphin) membuka banyak
# koneksi paralel dan kena "limit" UFW (6 koneksi baru / 30 detik).
info "Whitelist IP: IP ini lolos dari rate-limit UFW dan tidak pernah di-ban fail2ban."
info "  Hati-hati: IP VPN biasanya dipakai bersama banyak orang; mereka ikut lolos"
info "  (login tetap wajib key). IP yang sedang kamu pakai (terdeteksi otomatis): ${KLIEN:-tidak terdeteksi}"
tanya WL "IP yang di-whitelist (- = tidak ada)" "$DEF_WL"
[ "$WL" = - ] && WL=""
if [ -n "$WL" ]; then
    if [[ $WL =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
        for o in "${BASH_REMATCH[@]:1}"; do [ "$o" -le 255 ] || gagal "IP tidak valid: $WL"; done
    elif ! [[ $WL =~ ^[0-9a-fA-F:]+$ && $WL == *:* ]]; then
        gagal "IP tidak valid: $WL (satu alamat IPv4/IPv6, atau - untuk tidak ada)"
    fi
fi

# Zona waktu: jam di log (journal, fail2ban, nginx) dan jadwal cron/timer.
# Boleh diketik bebas: nama lengkap (Asia/Jakarta, huruf besar/kecil bebas),
# nama kota (makassar, "new york"), WIB/WITA/WIT, UTC/GMT, atau selisih jam
# bulat (GMT+7, UTC+7, +7, +07:00). "-" = biarkan seperti sekarang.
daftar_zona() {
    local d
    d=$(timedatectl list-timezones 2>/dev/null || true)
    # Tanpa timedatectl/dbus: daftar dari tzdata (Z = zona, L = nama alias).
    [ -n "$d" ] || d=$(awk '$1 == "Z" {print $2} $1 == "L" {print $3}' /usr/share/zoneinfo/tzdata.zi 2>/dev/null || true)
    printf '%s\n' "$d"
}
# zona_calon INPUT: cetak zona yang cocok (0, 1, atau beberapa baris).
zona_calon() {
    local x u s j daftar kota
    read -r x <<<"$1"; x=${x// /_}; u=${x^^}
    case $u in
        WIB) echo Asia/Jakarta; return 0;;
        WITA) echo Asia/Makassar; return 0;;
        WIT) echo Asia/Jayapura; return 0;;
        UTC|GMT) echo Etc/UTC; return 0;;
    esac
    # Selisih jam bulat -> Etc/GMT-N. Tanda di nama Etc/GMT dibalik (aturan
    # POSIX): Etc/GMT-7 = UTC+7. Selisih tidak bulat (+05:30): pakai nama kota.
    if [[ ${u//_/} =~ ^(UTC|GMT)?([+-])([0-9]{1,2})(:?00)?$ ]]; then
        s=${BASH_REMATCH[2]}; j=$((10#${BASH_REMATCH[3]}))
        if [ "$j" = 0 ]; then echo Etc/UTC
        elif [ "$s" = + ] && [ -f "/usr/share/zoneinfo/Etc/GMT-$j" ]; then echo "Etc/GMT-$j"
        elif [ "$s" = - ] && [ -f "/usr/share/zoneinfo/Etc/GMT+$j" ]; then echo "Etc/GMT+$j"
        fi
        return 0
    fi
    daftar=$(daftar_zona)
    # Nama kota: cocokkan bagian terakhir (Asia/Makassar -> makassar).
    if [[ $x != */* ]]; then
        kota=$(awk -F/ -v x="${x,,}" 'NF > 1 && tolower($NF) == x' <<<"$daftar")
        if [ -n "$kota" ]; then printf '%s\n' "$kota"; return 0; fi
    fi
    awk -v x="${x,,}" 'tolower($0) == x' <<<"$daftar"
}
ZONA_LAMA=$(timedatectl show -p Timezone --value 2>/dev/null || true)
while :; do
    tanya ZONA "Zona waktu: kota, WIB/WITA/WIT, UTC, GMT+7 (- = tetap ${ZONA_LAMA:-seperti sekarang})" "$DEF_ZONA"
    if [ "$ZONA" = - ]; then ZONA=$ZONA_LAMA; break; fi
    calon=$(zona_calon "$ZONA")
    case $(awk 'NF {n++} END {print n + 0}' <<<"$calon") in
        1) ZONA=$calon; break;;
        0) awas "Zona waktu tidak dikenal: $ZONA (contoh: Jakarta, WIB/WITA/WIT, UTC, GMT+7, Asia/Singapore; kota yang tidak ada di daftar, mis. Surabaya: pakai WIB/WITA/WIT)";;
        *) awas "\"$ZONA\" cocok dengan beberapa zona: $(paste -sd' ' <<<"$calon"). Ketik salah satu.";;
    esac
done
if [ -n "$ZONA" ]; then
    [[ $ZONA =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$ ]] && [ -f "/usr/share/zoneinfo/$ZONA" ] \
        || gagal "Zona waktu tidak dikenal: $ZONA"
    info "Zona waktu $ZONA: jam di sana sekarang $(TZ=$ZONA date '+%H:%M %Z, UTC%:z')"
fi

echo
SWAP_KET=$SWAP; [ $SWAP_ADA = 0 ] || SWAP_KET="sudah ada"
info "Ringkasan: user $USERNAME, SSH port $PORT, swap $SWAP_KET, IP $IP, whitelist ${WL:-tidak ada}, zona waktu ${ZONA:-tidak diubah}"
info "Sebelum lanjut, pastikan:"
info " - $SESI_INI TETAP TERBUKA sampai script selesai"
info " - firewall/security group di panel provider (kalau ada) mengizinkan TCP $PORT"
info " - kamu tahu cara membuka web console (VNC/serial) provider untuk keadaan darurat"
yakin "Lanjut?" y || exit 0

# --- Konfigurasi & fungsi SSH (dipakai langkah 1, 6, 7, 8) -------------------
# KONF_AWAL : port 22 tetap, tanpa password, root hanya dengan key. Dipasang di
#             awal langkah 1 dan menjadi tujuan rollback. Rollback TIDAK PERNAH
#             menghapus hardening: tanpa file ini berlaku default provider, mis.
#             50-cloud-init.conf "PasswordAuthentication yes" + root ber-password.
#             Tanpa AllowUsers: $USERNAME belum ada di langkah 1, dan saat
#             rollback pemilik mungkin perlu masuk lagi lewat root/user bawaan.
# KONF_TRANSISI : Port 22 + Port $PORT, root mati, AllowUsers $ALLOW (langkah 6-7;
#             login $USERNAME sudah terbukti di langkah 3).
# KONF      : konfigurasi akhir, hanya Port $PORT (langkah 8).
ALLOW_SED=${ALLOW//\//\\/}   # "/" dari CIDR (user@10.0.0.0/8) adalah pemisah sed
KONF=$(sed -e "s/^Port .*/Port $PORT/" -e "s/^AllowUsers .*/AllowUsers $ALLOW_SED/" "$REPO/files/00-hardening.conf")
KONF_TRANSISI=$(sed -e "s/^Port .*/# SEMENTARA (security-vps): Port 22 dihapus setelah login port $PORT dikonfirmasi.\nPort 22\nPort $PORT/" \
    -e "s/^AllowUsers .*/AllowUsers $ALLOW_SED/" "$REPO/files/00-hardening.conf")
KONF_AWAL=$(sed -e "s/^Port .*/# AWAL (security-vps): login password mati; root masih boleh dengan key sampai langkah 6.\nPort 22/" \
    -e "s/^PermitRootLogin .*/PermitRootLogin prohibit-password/" \
    -e "s/^AllowUsers .*/# AllowUsers $USERNAME dipasang mulai langkah 6./" "$REPO/files/00-hardening.conf")
SSH_ADA=0; SSH_LAMA=""

kembalikan_ssh() {
    if [ $SSH_ADA = 1 ]; then tulis "Kembalikan konfigurasi SSH sebelumnya" "$SSHD_CONF" 644 <<<"$SSH_LAMA"
    else run "Hapus konfigurasi SSH baru" rm -f "$SSHD_CONF"; fi
}
# pasang_ssh "keterangan" ISI PORT...: tulis $SSHD_CONF kalau berbeda, sshd -t,
# terapkan, lalu tunggu SEMUA port listen. Gagal di mana pun -> isi sebelumnya
# dikembalikan dan script berhenti.
pasang_ssh() {
    local desc=$1 isi=$2 p perlu=0; shift 2
    SSH_ADA=0; SSH_LAMA=""
    if [ -f "$SSHD_CONF" ]; then SSH_ADA=1; SSH_LAMA=$(cat "$SSHD_CONF"); fi
    if [ $SSH_ADA = 1 ] && [ "$SSH_LAMA" = "$isi" ]; then
        ok "$SSHD_CONF sudah sesuai"
    else
        perlu=1
        # Cadangkan hanya konfigurasi yang bukan buatan script ini.
        if [ $SSH_ADA = 1 ] && [ "$SSH_LAMA" != "$KONF" ] && [ "$SSH_LAMA" != "$KONF_TRANSISI" ] \
           && [ "$SSH_LAMA" != "$KONF_AWAL" ]; then
            run "Cadangkan konfigurasi SSH lama" cp -p "$SSHD_CONF" "/root/00-hardening.conf.bak-$(date +%Y%m%d%H%M%S)"
        fi
        tulis "$desc" "$SSHD_CONF" 644 <<<"$isi"
    fi
    if ! run "Validasi konfigurasi SSH (sshd -t)" sshd -t; then
        kembalikan_ssh
        gagal "sshd -t error; konfigurasi dikembalikan, SSH tidak di-restart. Lihat keterangan di atas."
    fi
    for p; do dengar "$p" || perlu=1; done
    [ $perlu = 0 ] || terapkan_ssh
    [ $DRY = 0 ] || return 0
    for p; do
        if ! tunggu "Tunggu sshd listen di port $p" 10 dengar "$p"; then
            awas "Port $p tidak listen. Mengembalikan konfigurasi SSH..."
            kembalikan_ssh
            terapkan_ssh
            gagal "Port $p tidak listen; konfigurasi SSH dikembalikan. Cek: journalctl -u ssh -n 30"
        fi
    done
}
# pastikan_ssh "opsi nilai[|nilai-setara]"...: nilai EFEKTIF (sshd -T) harus
# salah satu nilai itu. Bisa beda kalau file lain dibaca lebih dulu, mis. opsi
# di sshd_config di atas baris Include. Nilai setara perlu karena nama di
# sshd -T berubah antar versi/build: PermitRootLogin prohibit-password tampil
# sebagai "without-password" (OpenSSH 9.x, juga 10.0 di Debian 13) atau
# "prohibit-password" (OpenSSH 10.2 di Ubuntu 26.04).
pastikan_ssh() {
    [ $DRY = 0 ] || return 0
    local efektif pasangan opsi nilai beda=""
    efektif=$(sshd -T 2>/dev/null)
    for pasangan; do
        opsi=${pasangan%% *}; nilai=${pasangan#* }
        grep -qxE -- "$opsi ($nilai)" <<<"$efektif" || beda+=" $opsi"
    done
    if [ -z "$beda" ]; then
        ok "Pengaturan SSH efektif sesuai: $(for o in "$@"; do grep -m1 "^${o%% *} " <<<"$efektif"; done | paste -sd, | sed 's/,/, /g')"
        return 0
    fi
    for pasangan in $beda; do
        awas "$pasangan efektif: $(grep -m1 "^$pasangan " <<<"$efektif" || echo '?'). Ditetapkan di:"
        grep -rniE "^\s*$pasangan\s" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ | sed 's/^/      │ /' | tee -a "$LOG" || true
    done
    gagal "Pengaturan SSH efektif tidak sesuai (${beda# }); ada file lain yang menimpanya. Perbaiki file di atas lalu jalankan ulang."
}
# AllowUsers dari beberapa file DIGABUNG (bukan nilai pertama yang menang) dan
# sshd -T menulis satu baris per entri, jadi pastikan_ssh tidak cukup: file lain
# (mis. dari provider) bisa menambah user bawaan cloud. Isinya harus persis
# $ALLOW, yaitu hanya dari $SSHD_CONF.
pastikan_allowusers() {
    [ $DRY = 0 ] || return 0
    local au mau
    au=$(sshd -T 2>/dev/null | sed -n 's/^allowusers //p' | tr ' ' '\n' | awk 'NF' | sort -u | paste -sd' ')
    mau=$(tr ' ' '\n' <<<"$ALLOW" | sort -u | paste -sd' ')
    if [ "$au" = "$mau" ]; then ok "Hanya $ALLOW yang boleh login SSH (AllowUsers)"; return 0; fi
    awas "AllowUsers efektif: ${au:-tidak ada (semua user boleh login)}. Ditetapkan di:"
    grep -rniE '^\s*AllowUsers\s' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ | sed 's/^/      │ /' | tee -a "$LOG" || true
    gagal "AllowUsers harus persis: $ALLOW (hanya dari $SSHD_CONF). Perbaiki file di atas lalu jalankan ulang."
}
tampil_ssh() {
    [ $DRY = 0 ] || return 0
    CMD_LABEL="sshd -T" run "Pengaturan SSH efektif" bash -c \
        "sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|kbdinteractiveauthentication|clientaliveinterval) '"
}
tidak_dengar() { ! dengar "$1"; }
# Bagaimana sesi ini (root langsung, atau user di balik sudo) login: dari journal,
# dicocokkan dengan IP + port klien hasil deteksi_sesi.
cara_login() {
    [ -n "${SESI_CPORT:-}" ] || return 0
    journalctl -b -u ssh --no-pager -o cat 2>/dev/null \
        | grep -F "for $SESI_USER from $KLIEN port $SESI_CPORT " \
        | sed -nE "s/^Accepted (\S+) for $SESI_USER .*/\1/p" | tail -1
}

# ---------------------------------------------------------------------------
langkah "1. Tutup login password SSH, zona waktu, lalu update sistem"
# Upgrade bisa makan beberapa menit; selama itu default provider (root + password)
# masih terbuka untuk bot. Tutup dulu, tetap di port 22: root tetap bisa login
# dengan key, jadi aman asalkan sesi ini memang masuk dengan key.
if [ -f "$SSHD_CONF" ] && [ "$(cat "$SSHD_CONF")" != "$KONF_AWAL" ]; then
    ok "Hardening SSH sudah terpasang di run sebelumnya; langkah ini dilewati"
elif [ $DRY = 0 ] && ! dengar 22; then
    gagal "sshd tidak listen di port 22. Script ini mengasumsikan SSH bawaan di port 22."
else
    CARA=$(cara_login || true)
    case "$CARA" in
        publickey) ok "Sesi ini ($SESI_USER) masuk dengan SSH key";;
        "") awas "Tidak bisa memastikan cara login sesi ini dari journal"
            yakin "Sesi ini login memakai SSH key (bukan password)?" n \
                || gagal "Tambahkan SSH key di panel provider dulu, login ulang dengan key, lalu jalankan ulang.";;
        *)  gagal "Sesi ini ($SESI_USER) login dengan '$CARA', bukan key. Mematikan login password bisa mengunci: tambahkan key dulu.";;
    esac
    pasang_ssh "Pasang $SSHD_CONF awal (port 22, tanpa password, root hanya dengan key)" "$KONF_AWAL" 22
    pastikan_ssh "passwordauthentication no" "kbdinteractiveauthentication no" "permitrootlogin without-password|prohibit-password"
fi

# Zona waktu sebelum update dan sebelum fail2ban (langkah 9) menulis log, supaya
# log baru memakai satu zona. Baris log lama tetap di zona sebelumnya
# (cek-keamanan.sh menanganinya).
if [ -n "$ZONA" ] && [ "$ZONA" != "$ZONA_LAMA" ]; then
    run "Zona waktu $ZONA" timedatectl set-timezone "$ZONA"
elif [ -n "$ZONA" ]; then
    ok "Zona waktu sudah $ZONA"
fi

tunggu "Tunggu apt/dpkg tidak sedang dipakai (unattended-upgrades/cloud-init)" 600 apt_bebas \
    || gagal "apt/dpkg masih dipakai proses lain setelah 10 menit; cek: ps aux | grep -E 'apt|dpkg'"
CMD_LABEL="apt-get update" run "Update daftar paket" "${APT[@]}" update
CMD_LABEL="apt-get full-upgrade" run "Upgrade semua paket (bisa beberapa menit)" "${APT[@]}" full-upgrade
# needrestart: restart layanan yang masih memakai library lama setelah update
# (diatur di langkah 11). Debian 13 dan Ubuntu 26.04 tidak lagi memasang "last"
# lewat util-linux: penggantinya wtmpdb, login-nya dicatat libpam-wtmpdb.
PAKET=(sudo ufw unattended-upgrades needrestart)
if ! command -v last >/dev/null; then
    for p in wtmpdb libpam-wtmpdb; do
        if apt-cache show "$p" >/dev/null 2>&1; then PAKET+=("$p"); fi
    done
fi
CMD_LABEL="apt-get install ${PAKET[*]}" run "Install ${PAKET[*]}" "${APT[@]}" install "${PAKET[@]}"
if [ -f /var/run/reboot-required ]; then
    awas "Update butuh reboot."
    if yakin "Reboot sekarang? Setelah login root lagi, jalankan ulang script ini" y; then
        run "Reboot" reboot; exit 0
    fi
    info "Lanjut tanpa reboot; reboot setelah script selesai."
fi

# ---------------------------------------------------------------------------
langkah "2. User $USERNAME"
info "Password root dipakai untuk web console darurat (login SSH root nanti mati)."
if yakin "Ganti password root sekarang?" y; then
    until run -t "Ganti password root" passwd; do awas "Coba lagi"; done
fi
if id "$USERNAME" &>/dev/null; then
    ok "User $USERNAME sudah ada"
else
    run "Buat user $USERNAME" useradd -m -s /bin/bash "$USERNAME"
fi
# Status "P" = punya password yang bisa dipakai; tanpa itu sudo tidak jalan.
if [ "$(passwd -S "$USERNAME" 2>/dev/null | awk '{print $2}' || true)" != P ]; then
    info "Isi password $USERNAME: dipakai untuk sudo, BUKAN untuk login SSH"
    until run -t "Password $USERNAME" passwd "$USERNAME"; do awas "Coba lagi"; done
fi
run "Masukkan $USERNAME ke grup sudo" usermod -aG sudo "$USERNAME"

run "Buat $H/.ssh" install -d -m 700 -o "$USERNAME" -g "$USERNAME" "$H/.ssh"
if [ -s "$RK" ]; then
    # Buang opsi di depan key (mis. cloud-init: command="echo 'Please login as
    # the user ubuntu';exit 142" ssh-ed25519 ...): disalin apa adanya, login
    # user hanya menjalankan perintah itu lalu langsung keluar.
    KUNCI_ROOT=$(kunci_saja <"$RK")
    [ -n "$KUNCI_ROOT" ] || gagal "Tidak ada key SSH yang valid di $RK"
    # Hanya baris yang BERISI key tapi tidak diawali tipe key (= ada opsi di depan);
    # baris rusak/sampah sudah dilaporkan di langkah 0.
    if grep -E '[[:space:]](ssh-(ed25519|rsa|dss)|ecdsa-sha2-nistp[0-9]+|sk-[a-z0-9-]+@openssh\.com)[[:space:]]+AAAA' "$RK" \
       | grep -vE '^[[:space:]]*(#|ssh-|ecdsa-|sk-)' >/dev/null; then
        awas "Sebagian key root diawali opsi (mis. command= dari cloud-init); yang disalin hanya key-nya."
    fi
    # Lebih dari satu key: bisa ada key milik provider (fitur panel/support).
    # Disalin ke user sudo berarti pemiliknya ikut bisa masuk; pemilik memilih.
    KUNCI_ROOT=$(pilih_kunci "$KUNCI_ROOT")
fi
if [ -s "$RK" ] && [ ! -s "$AK" ]; then
    tulis "Salin key root ke $USERNAME (tanpa opsi)" "$AK" 600 <<<"$KUNCI_ROOT"
elif [ -s "$RK" ]; then
    # Tambahkan key root yang belum ada, tanpa menghapus key milik user.
    while IFS= read -r k; do
        grep -qxF -- "$k" "$AK" || tambah_baris "Tambah key root ke $AK" "$AK" "$k"
    done <<<"$KUNCI_ROOT"
    ok "Key $USERNAME sudah memuat semua key root"
elif [ $DRY = 1 ]; then
    run "Salin key root ke $USERNAME" install -m 600 -o "$USERNAME" -g "$USERNAME" "$RK" "$AK"
fi
# StrictModes sshd diam-diam menolak key kalau home/.ssh/authorized_keys bisa
# ditulis orang lain atau bukan milik user. Tegakkan izinnya, juga untuk user
# dan key yang sudah ada sebelumnya (tee -a di atas tidak mengubah izin).
run "Pemilik $H/.ssh ke $USERNAME" chown -R "$USERNAME:$USERNAME" "$H/.ssh"
run "Izin $H/.ssh 700" chmod 700 "$H/.ssh"
run "Izin $AK 600" chmod 600 "$AK"
run "Home $H tidak bisa ditulis group/orang lain" chmod go-w "$H"
[ $DRY = 1 ] || run "Izin dan pemilik" stat -c '%a %U:%G %n' "$H" "$H/.ssh" "$AK"
[ $DRY = 1 ] || run "Fingerprint key $USERNAME" ssh-keygen -lf "$AK"

# ---------------------------------------------------------------------------
langkah "3. Uji login $USERNAME (masih port 22)"
if dengar 22; then
    SEJAK=$(date '+%F %T')
    info "Di PC, buka TERMINAL/SESI BARU ($SESI_INI tetap terbuka) sebagai $USERNAME, BUKAN root:"
    info "    ssh $USERNAME@$IP"
    info "    sudo true && echo SUDO OK"
    info "Biarkan sesi uji itu terbuka sampai kamu menjawab: script memeriksa login & sudo-nya di log sistem."
    konfirmasi_login "Login $USERNAME dengan key DAN sudo berhasil?" 22 "$SEJAK" \
        || gagal "Uji login $USERNAME di port 22 belum berhasil; perbaiki dulu."
else
    info "SSH sudah tidak di port 22 (run sebelumnya); uji login dilakukan di langkah 7"
fi

# ---------------------------------------------------------------------------
langkah "4. Swap"
if [ "$SWAP" = 0 ]; then
    info "Dilewati"
else
    run "Buat /swapfile $SWAP" fallocate -l "$SWAP" /swapfile
    run "Izin /swapfile 600" chmod 600 /swapfile
    run "Format swap" mkswap /swapfile
    run "Aktifkan swap" swapon /swapfile
    grep -E '^/swapfile ' /etc/fstab >/dev/null \
        || tambah_baris "Daftarkan swap di /etc/fstab" /etc/fstab '/swapfile none swap sw 0 0'
fi

# ---------------------------------------------------------------------------
langkah "5. Firewall UFW"
run "Default tolak koneksi masuk" ufw default deny incoming
run "Default izinkan koneksi keluar" ufw default allow outgoing
# Port 22 dibuka sementara supaya sesi yang ada tidak putus; tidak ditambahkan
# lagi kalau SSH sudah pindah (run ulang setelah langkah 8).
if dengar 22; then
    run "Buka sementara 22/tcp (rate-limit)" ufw limit 22/tcp comment 'SSH lama - dihapus di langkah 8'
fi
run "Buka $PORT/tcp (rate-limit)" ufw limit "$PORT/tcp" comment 'SSH'
if [ -n "$WL" ]; then
    # prepend: di atas aturan limit (v4 atau v6), jadi koneksi dari IP ini tidak dihitung.
    run "Whitelist $WL di port $PORT (tanpa rate-limit)" \
        ufw prepend allow proto tcp from "$WL" to any port "$PORT" comment 'Whitelist IP pemilik (tanpa limit)'
fi
# LLMNR (5355) dan mDNS (5353) dari systemd-resolved: listen di semua alamat,
# tidak dibutuhkan di VPS, dan LLMNR dikenal rawan spoofing. Sebagian image
# (mis. Debian 13 BeroHost) menyalakannya; Ubuntu mematikannya. Dimatikan hanya
# kalau memang listen.
if systemctl is-active -q systemd-resolved 2>/dev/null \
   && ss -tulnH 2>/dev/null | awk '{print $5}' | grep -E ':(5355|5353)$' >/dev/null; then
    run "Buat /etc/systemd/resolved.conf.d" install -d -m 755 /etc/systemd/resolved.conf.d
    tulis "Matikan LLMNR & mDNS di systemd-resolved" /etc/systemd/resolved.conf.d/00-tanpa-llmnr.conf 644 <<'EOF'
# Dari security-vps: LLMNR/mDNS tidak dibutuhkan di VPS (port 5355/5353).
[Resolve]
LLMNR=no
MulticastDNS=no
EOF
    run "Restart systemd-resolved" systemctl restart systemd-resolved
    tunggu "Tunggu port 5355/5353 berhenti listen" 10 bash -c \
        "! ss -tulnH | awk '{print \$5}' | grep -E ':(5355|5353)\$' >/dev/null" \
        || awas "LLMNR/mDNS masih listen; cek: resolvectl status"
fi
run "Aktifkan UFW" ufw --force enable
run "Status UFW" ufw status verbose

# ---------------------------------------------------------------------------
langkah "6. Hardening SSH + buka port $PORT (port 22 tetap aktif sementara)"
# Port di rentang port acak koneksi keluar (biasanya 32768-60999) bisa
# keduluan dipakai koneksi keluar: pesan dulu. Satu file bersama untuk semua port.
read -r LO HI </proc/sys/net/ipv4/ip_local_port_range
if [ "$PORT" -ge "$LO" ] && [ "$PORT" -le "$HI" ]; then
    F=/etc/sysctl.d/90-reserved-ports.conf
    LAMA=$(sed -n 's/^net.ipv4.ip_local_reserved_ports *= *//p' "$F" 2>/dev/null || true)
    BARU=$(printf '%s,%s' "$LAMA" "$PORT" | tr ',' '\n' | grep -E '^[0-9]+(-[0-9]+)?$' | sort -t- -k1,1n -k2,2n -u | paste -sd,)
    if [ "$LAMA" != "$BARU" ]; then
        tulis "Pesan port $PORT di $F" "$F" 644 <<<"net.ipv4.ip_local_reserved_ports = $BARU"
        run "Terapkan sysctl" sysctl -q --system
    fi
    info "Port dipesan: $(cat /proc/sys/net/ipv4/ip_local_reserved_ports)"
else
    info "Port $PORT di luar rentang port acak $LO-$HI: tidak perlu dipesan"
fi

# Login password atau root yang masih "yes" di file lain: 50-cloud-init.conf
# (cloud-init, kalau provider menyetel ssh_pwauth: true) atau tambahan provider
# di sshd_config (mis. "PermitRootLogin yes"). Sekarang kalah oleh $SSHD_CONF
# yang dibaca lebih dulu, tapi aktif lagi kalau file itu hilang, dan di dalam
# blok Match nilainya menimpa pengaturan global. Hanya yes -> no, jadi tidak
# bisa mengunci: login root sudah mati sejak langkah ini, dan rollback
# (KONF_AWAL, root dengan key) tetap menang karena $SSHD_CONF dibaca lebih dulu.
# Semua bentuk yang diterima sshd: "=" atau spasi, huruf besar/kecil, "yes"
# berkutip, komentar di ujung baris. Grup 1 = kunci + pemisah, 4 = sisa baris.
PW_KUNCI='^([[:space:]]*(PasswordAuthentication|KbdInteractiveAuthentication|ChallengeResponseAuthentication|PermitRootLogin|PermitEmptyPasswords)([[:space:]]*=[[:space:]]*|[[:space:]]+))'
PW_SISA='(([[:space:]]+#.*)?[[:space:]]*)$'
PW_YA="${PW_KUNCI}\"?yes\"?${PW_SISA}"
PW_UBAH=0
for f in /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf; do
    [ -f "$f" ] && [ "$f" != "$SSHD_CONF" ] || continue
    if grep -qiE "$PW_YA" "$f" 2>/dev/null; then
        grep -niE "$PW_YA" "$f" | while IFS= read -r l; do info "$f:$l"; done
        CMD_LABEL="sed -i 's/yes/no/' $f" run "Ubah 'yes' jadi 'no' (login password/root) di $f" \
            sed -i -E "s/$PW_YA/\1no\4/I" "$f"
        PW_UBAH=1
    fi
done
# cloud-init menulis ulang 50-cloud-init.conf dari ssh_pwauth saat menganggap
# VPS instance baru (mis. setelah migrasi dari panel); false membuatnya "no".
# Reset password dari panel tidak terpengaruh (ssh_pwauth hanya mengatur sshd).
CLOUD_PW=/etc/cloud/cloud.cfg.d/99-ssh-tanpa-password.cfg
if [ -d /etc/cloud/cloud.cfg.d ]; then
    ISI_CLOUD_PW='# Dari security-vps: login password SSH tetap mati walaupun cloud-init
# menulis ulang /etc/ssh/sshd_config.d/50-cloud-init.conf (instance baru).
ssh_pwauth: false'
    if [ "$(cat "$CLOUD_PW" 2>/dev/null)" = "$ISI_CLOUD_PW" ]; then
        ok "cloud-init tidak akan menyalakan login password SSH ($CLOUD_PW)"
    else
        tulis "Cegah cloud-init menyalakan lagi login password SSH" "$CLOUD_PW" 644 <<<"$ISI_CLOUD_PW"
    fi
    # File cloud.cfg.d lain yang dibaca belakangan bisa menimpa: cek nilai gabungannya.
    if [ $DRY = 0 ]; then
        pw=$(python3 -c 'from cloudinit.stages import Init; i = Init(); i.read_cfg(); print(i.cfg.get("ssh_pwauth"))' 2>/dev/null || true)
        case $pw in
            False) ok "Nilai gabungan cloud-init: ssh_pwauth false";;
            "")    info "Nilai gabungan ssh_pwauth cloud-init tidak bisa dibaca; cek: grep -rn ssh_pwauth /etc/cloud/";;
            *)     awas "Nilai gabungan ssh_pwauth cloud-init: $pw (file lain di /etc/cloud/cloud.cfg.d menimpa $CLOUD_PW)";;
        esac
    fi
fi

# Transisi dua tahap supaya tidak terkunci: di sini dipasang Port 22 DAN
# Port $PORT, jadi port 22 tetap listen sebagai jalan kembali untuk $USERNAME
# (login root sudah mati sejak sini). Konfigurasi akhir (hanya $PORT) baru
# dipasang di langkah 8, setelah login lewat port baru dikonfirmasi.
# Lompat langsung ke konfigurasi akhir HANYA kalau isinya sama persis: itu
# berarti login dengan konfigurasi ini sudah terbukti di run sebelumnya. Isi
# lain (versi script lama tanpa AllowUsers, file buatan tangan) lewat transisi
# + uji login langkah 7, karena langkah 3 dan 7 dilewati kalau port 22 sudah
# tutup, dan langkah 10 hanya bertanya. sshd sempat listen di 22, tapi tanpa
# aturan UFW 22 port itu tidak terbuka ke luar.
if [ $DRY = 0 ] && [ "$(cat "$SSHD_CONF" 2>/dev/null)" = "$KONF" ] && ! aturan22; then
    ok "Konfigurasi SSH akhir (hanya port $PORT) sudah terpasang di run sebelumnya"
    pasang_ssh "Pasang konfigurasi SSH akhir (hanya Port $PORT)" "$KONF" "$PORT"
else
    pasang_ssh "Pasang $SSHD_CONF sementara (Port 22 + Port $PORT)" "$KONF_TRANSISI" 22 "$PORT"
    [ $DRY = 1 ] || ok "sshd listen di port 22 (sementara) dan $PORT"
fi
pastikan_ssh "permitrootlogin no" "passwordauthentication no" "kbdinteractiveauthentication no"
pastikan_allowusers
# pasang_ssh tidak me-restart kalau konfigurasinya sudah sesuai: muat ulang
# supaya perubahan "yes" -> "no" di blok Match ikut berlaku. sshd -t sudah lolos.
[ $PW_UBAH = 0 ] || run "Muat ulang sshd (perubahan 'yes' jadi 'no' di file lain)" systemctl try-reload-or-restart ssh
tampil_ssh

# ---------------------------------------------------------------------------
langkah "7. Uji login lewat port $PORT"
if [ $DRY = 0 ] && ! aturan22 && ! dengar 22; then
    ok "Port 22 sudah ditutup di run sebelumnya; uji login dilewati"
else
    SEJAK=$(date '+%F %T')
    info "Di PC, buka SESI BARU lagi ($SESI_INI tetap terbuka):"
    info "    ssh -p $PORT $USERNAME@$IP     # harus BERHASIL, lalu: sudo true && echo SUDO OK"
    info "    ssh -p $PORT root@$IP          # harus DITOLAK (Permission denied) - cukup SEKALI:"
    info "      tiap percobaan root dihitung kegagalan oleh fail2ban (5 = IP-mu ke-ban 1 jam)."
    info "Biarkan sesi $USERNAME itu terbuka sampai kamu menjawab: script memeriksanya di log sistem."
    info "Kalau gagal konek: cek firewall panel provider untuk TCP $PORT."
    if ! konfirmasi_login "Login $USERNAME lewat port $PORT DAN sudo berhasil?" "$PORT" "$SEJAK"; then
        # Klaim "port 22 masih bisa dipakai" diverifikasi dulu, bukan diasumsikan.
        if [ $DRY = 1 ] || { dengar 22 && aturan22; }; then
            info "Port 22 TETAP terbuka: sshd masih listen di 22 dan aturan UFW 22 masih ada."
            info "Login $USERNAME lewat port 22 tetap bisa (login root sudah mati):"
            info "    ssh $USERNAME@$IP"
            gagal "Uji login port $PORT belum berhasil. Perbaiki penyebabnya (mis. firewall panel untuk TCP $PORT), lalu jalankan ulang script."
        fi
        awas "PERHATIAN: port 22 TIDAK bisa dipakai (sshd tidak listen di 22 atau aturan UFW 22 hilang)."
        awas "JANGAN tutup $SESI_INI."
        # Bukan kembali ke default provider (bisa root + password aktif lagi):
        # tetap tanpa password, port 22, root boleh login lagi dengan key.
        if yakin "Kembalikan SSH ke port 22 (tetap tanpa password; root bisa login lagi dengan key)?" y; then
            aturan22 || run "Buka 22/tcp (rate-limit)" ufw limit 22/tcp comment 'SSH lama - dihapus di langkah 8'
            pasang_ssh "Pasang konfigurasi darurat (port 22, tanpa password)" "$KONF_AWAL" 22
            pastikan_ssh "passwordauthentication no" "kbdinteractiveauthentication no"
            info "Login darurat: ssh $USERNAME@$IP  atau  ssh root@$IP (dengan key)."
        fi
        gagal "Uji login port $PORT belum berhasil."
    fi
    # Uji root bersifat pelengkap: penolakan hanya dilaporkan, tidak menghentikan.
    if [ $DRY = 0 ]; then
        if journalctl -u ssh --since "$SEJAK" --no-pager -o cat 2>/dev/null \
               | grep -E 'ROOT LOGIN REFUSED|authenticating user root |User root from .* not listed in AllowUsers' >/dev/null; then
            ok "Uji root terbukti ditolak (tercatat di log sistem)"
        else
            info "Uji 'ssh -p $PORT root@...' tidak terlihat di log (tidak wajib; root login sudah mati, lihat sshd -T)."
        fi
    fi

    # -----------------------------------------------------------------------
    langkah "8. Pindah penuh ke port $PORT dan tutup port 22"
    pasang_ssh "Pasang konfigurasi SSH akhir (hanya Port $PORT)" "$KONF" "$PORT"
    pastikan_allowusers
    if [ $DRY = 0 ] && ! tunggu "Tunggu sshd berhenti listen di port 22" 10 tidak_dengar 22; then
        awas "Port 22 masih listen. Ada 'Port 22' lain di konfigurasi (aturan UFW 22 tetap dihapus):"
        grep -rnE '^\s*Port\s' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ | sed 's/^/      │ /' || true
    fi
    tampil_ssh
    if ufw status 2>/dev/null | grep -E '^22/tcp +LIMIT' >/dev/null || [ $DRY = 1 ]; then
        run "Hapus aturan 22/tcp" ufw delete limit 22/tcp
    fi
    if aturan22; then awas "Masih ada aturan port 22/OpenSSH lain; hapus manual: ufw status numbered, ufw delete N"
    else ok "Tidak ada aturan port 22 tersisa"; fi
    run "Status UFW" ufw status verbose
fi

# ---------------------------------------------------------------------------
langkah "9. fail2ban"
run "Buat /etc/fail2ban/jail.d" install -d -m 755 /etc/fail2ban/jail.d
sed "s/^\(port *= *\)[0-9]*/\1$PORT/" "$REPO/files/jail.local" \
    | tulis "Pasang jail.local (port $PORT)" /etc/fail2ban/jail.local 644
sed "s/^\(port *= *\)[0-9]*/\1$PORT/" "$REPO/files/sshd-lambat.local" \
    | tulis "Pasang sshd-lambat.local (port $PORT)" /etc/fail2ban/jail.d/sshd-lambat.local 644
tulis "Pasang fail2ban.local (riwayat ban 30 hari untuk ban bertingkat)" /etc/fail2ban/fail2ban.local 644 \
    <"$REPO/files/fail2ban.local"
if [ "$ID" = debian ]; then
    # Debian minimal tanpa rsyslog tidak punya /var/log/auth.log: baca sshd dari
    # journal, dan ban lewat nftables seperti default Ubuntu.
    tulis "Pasang 00-debian.local (journal + nftables)" /etc/fail2ban/jail.d/00-debian.local 644 <<'EOF'
# Dari security-vps: samakan dengan default Ubuntu 24.04.
[DEFAULT]
banaction = nftables
banaction_allports = nftables[type=allports]

[sshd]
backend = systemd
EOF
fi
if [ -n "$WL" ]; then
    # Dibaca terakhir ("zz-") sehingga menimpa ignoreip per jail di sshd-lambat.local.
    tulis "Whitelist $WL di fail2ban (ketiga jail)" /etc/fail2ban/jail.d/zz-whitelist.local 644 <<EOF
# Dari security-vps: $WL tidak pernah di-ban (dipilih pemilik saat setup).
# Cabut: hapus file ini lalu systemctl reload fail2ban, dan
#        ufw delete allow proto tcp from $WL to any port $PORT
[sshd]
ignoreip = 127.0.0.1/8 ::1 $WL

[sshd-lambat]
ignoreip = 127.0.0.1/8 ::1 $WL

[recidive]
ignoreip = 127.0.0.1/8 ::1 $WL
EOF
fi
CMD_LABEL="apt-get install fail2ban python3-systemd nftables" run "Install fail2ban, python3-systemd, nftables" "${APT[@]}" install fail2ban python3-systemd nftables
run "Validasi konfigurasi fail2ban" fail2ban-client -t
run "Aktifkan fail2ban saat boot" systemctl enable fail2ban
run "Restart fail2ban" systemctl restart fail2ban
if [ $DRY = 0 ]; then
    tunggu "Tunggu fail2ban siap menerima perintah" 15 fail2ban-client ping || gagal "fail2ban tidak merespons; cek: journalctl -u fail2ban -n 30"
    bebaskan_ip_sendiri
    run "Daftar jail" fail2ban-client status
    # Uji ban/unban dengan IP dokumentasi (bukan IP sungguhan).
    run "Uji ban 192.0.2.1" fail2ban-client set sshd banip 192.0.2.1
    if nft list ruleset | grep 192.0.2.1 >/dev/null; then ok "192.0.2.1 terblokir di nftables"
    else awas "Uji ban: 192.0.2.1 tidak muncul di nftables"; fi
    run "Uji unban 192.0.2.1" fail2ban-client set sshd unbanip 192.0.2.1

    # Uji DETEKSI end-to-end (uji ban di atas hanya membuktikan aksinya): satu
    # login gagal dari 127.0.0.1 dengan user acak. 127.0.0.1 ada di ignoreip jadi
    # tidak di-ban, tapi fail2ban mencatat "[jail] Ignore 127.0.0.1" kalau rantai
    # journal -> journalmatch -> filter bekerja. Penting untuk OpenSSH >= 9.8,
    # yang menulis log lewat proses sshd-session.
    N0=$(grep -c '' /var/log/fail2ban.log 2>/dev/null || true)
    # Exit 255 saja ambigu (ssh juga 255 kalau koneksi gagal total), jadi
    # "Permission denied" harus muncul: bukti sshd benar-benar menolak login.
    CMD_LABEL="ssh -p $PORT uji-f2b-ACAK@127.0.0.1" run "Login gagal uji dari 127.0.0.1 (user acak, harus ditolak)" bash -c \
        'o=$(timeout 15 ssh -p "$1" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                 -o PreferredAuthentications=none -o ConnectTimeout=5 "uji-f2b-$RANDOM@127.0.0.1" true 2>&1)
         rc=$?; printf "%s\n" "$o"
         [ "$rc" = 255 ] && grep -q "Permission denied" <<<"$o" && exit 0
         echo "sshd di port $1 tidak bisa dihubungi atau tidak menolak seperti seharusnya (exit $rc)"; exit 1' _ "$PORT"
    terdeteksi() { tail -n +"$((${N0:-0} + 1))" /var/log/fail2ban.log | grep -E "\[$1\] (Found|Ignore) 127\.0\.0\.1" >/dev/null; }
    for j in sshd sshd-lambat; do
        tunggu "Jail $j mendeteksi login gagal itu" 15 terdeteksi "$j" \
            || gagal "Jail $j tidak mendeteksi login gagal: jail aktif tapi tidak akan pernah mem-ban.
    Cek: fail2ban-client get $j journalmatch; journalctl -u ssh -n 5 -o verbose | grep -E '_COMM|SYSLOG_IDENTIFIER'
    Catatan: SSH sudah di konfigurasi akhir (port $PORT). Langkah 10-12 (nonaktifkan key root,
    update otomatis, verifikasi akhir) BELUM dijalankan; jalankan ulang script setelah diperbaiki."
    done
fi

# ---------------------------------------------------------------------------
langkah "10. Nonaktifkan key root"
if [ $RK_ADA = 1 ]; then
    info "Login root via SSH sudah ditolak; key root dinonaktifkan sebagai lapisan cadangan."
    info "Setelah ini jalan darurat hanya web console provider (password root)."
    if ketik_ya "Login $USERNAME + sudo lewat port $PORT sudah terbukti berhasil?"; then
        run "Nonaktifkan key root" mv "$RK" "$RK.disabled-$(date +%Y%m%d)"
    else
        awas "Dilewati; jalankan ulang script nanti untuk langkah ini"
    fi
else
    ok "root sudah tanpa authorized_keys"
fi

# ---------------------------------------------------------------------------
langkah "11. Update keamanan otomatis"
if [ ! -f /etc/apt/apt.conf.d/20auto-upgrades ]; then
    tulis "Pasang 20auto-upgrades" /etc/apt/apt.conf.d/20auto-upgrades 644 <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
elif [ "$(grep -c '"1"' /etc/apt/apt.conf.d/20auto-upgrades || true)" -lt 2 ]; then
    awas "/etc/apt/apt.conf.d/20auto-upgrades ada tapi tidak bernilai \"1\"; cek isinya"
else
    ok "20auto-upgrades sudah aktif"
fi
run "Aktifkan unattended-upgrades" systemctl enable --now unattended-upgrades
# needrestart: setelah update otomatis (mis. libssl), layanan yang masih memakai
# library lama di-restart. Ubuntu sudah begitu (hook apt "-m u"); Debian tanpa
# terminal hanya mendaftar. Docker dkk. tetap dikecualikan needrestart.conf.
# Reboot untuk kernel tetap manual (cek-keamanan.sh: "Perlu reboot").
NR_CONF=/etc/needrestart/conf.d/90-restart-otomatis.conf
if grep -qs -- '-m u' /etc/apt/apt.conf.d/99needrestart; then
    ok "needrestart me-restart layanan otomatis setelah update (mode Ubuntu)"
else
    ISI_NR=$(cat <<'EOF'
# Dari security-vps: setelah update, restart otomatis layanan yang masih
# memakai library lama (bawaan Debian tanpa terminal: hanya mendaftar).
$nrconf{restart} = 'a';
# Info kernel baru cukup teks, tanpa dialog; reboot tetap manual.
$nrconf{kernelhints} = -1;
EOF
)
    if [ "$(cat "$NR_CONF" 2>/dev/null)" = "$ISI_NR" ]; then
        ok "needrestart me-restart layanan otomatis setelah update ($NR_CONF)"
    else
        tulis "needrestart: restart layanan otomatis setelah update" "$NR_CONF" 644 <<<"$ISI_NR"
    fi
fi

# ---------------------------------------------------------------------------
langkah "12. Verifikasi akhir"
bebaskan_ip_sendiri
DEST=$H/${REPO##*/}
if [ "$REPO" != "$DEST" ] && [ ! -e "$DEST" ]; then
    run "Salin repo ke $DEST" cp -a "$REPO" "$DEST"
    run "Ubah pemilik $DEST ke $USERNAME" chown -R "$USERNAME:$USERNAME" "$DEST"
fi
# cek-keamanan.sh memeriksa satu per satu: root login & password mati, port,
# keepalive, aturan UFW (port baru LIMIT v4/v6, tanpa aturan 22), port 22
# tertutup, dan jail sshd/sshd-lambat/recidive aktif dengan port yang benar.
# Kode keluar 0 = semua OK, 1 = ada AWAS, 3 = AWAS hanya soal reboot (kernel
# baru, atau layanan seperti dbus yang masih memakai library lama dari upgrade
# langkah 1). Kode 3 tidak menggagalkan setup: pengamanannya sudah lengkap,
# tinggal reboot. Kode keluar dicatat ke file: run menjalankan perintah di
# ujung kiri pipa (subshell), jadi variabel tidak sampai ke sini.
RC_CEK=$(mktemp)
if ! CMD_LABEL="env PORT_SSH=$PORT bash $REPO/cek-keamanan.sh" run "Verifikasi akhir (cek-keamanan.sh)" bash -c \
        'PORT_SSH="$1" bash "$2"; rc=$?; echo "$rc" >"$3"; [ "$rc" = 3 ] && { echo "(AWAS hanya soal reboot)"; exit 0; }; exit "$rc"' \
        _ "$PORT" "$REPO/cek-keamanan.sh" "$RC_CEK"; then
    rm -f "$RC_CEK"
    gagal "Verifikasi akhir menemukan AWAS (daftar di bagian Ringkasan di atas). Setup belum dinyatakan beres."
fi
RC_AKHIR=$(cat "$RC_CEK"); rm -f "$RC_CEK"
if [ "$RC_AKHIR" = 3 ]; then
    ok "Verifikasi akhir: semua pemeriksaan keamanan OK"
    awas "Update kernel/library butuh REBOOT. Setelah login $USERNAME: sudo reboot, lalu login lagi dan jalankan"
    info "    cd ~/${REPO##*/} && sudo -v && ./cek-keamanan.sh"
else
    [ $DRY = 1 ] || ok "Verifikasi akhir: semua pemeriksaan OK"
fi

echo
# Path key privat di PC pemilik tidak terlihat dari sini: contoh memakai nama
# default OpenSSH untuk key ed25519. IdentitiesOnly: hanya key itu yang
# ditawarkan; tanpa itu ssh mencoba semua key di agent, dan terlalu banyak key
# berakhir "Too many authentication failures" (dihitung fail2ban).
KEY_PC='~/.ssh/id_ed25519'
ok "Selesai. Mulai sekarang login: ssh -p $PORT -i $KEY_PC -o IdentitiesOnly=yes $USERNAME@$IP"
info "Log lengkap: $LOG"
info "${SESI_INI^} boleh ditutup. Contoh ~/.ssh/config di PC (nama Host bebas, lalu cukup: ssh nama-vps-bebas):"
info "    Host nama-vps-bebas"
info "        HostName $IP"
info "        User $USERNAME"
info "        Port $PORT"
info "        IdentityFile $KEY_PC"
info "        IdentitiesOnly yes"
info "        AddKeysToAgent yes"
info "Ganti $KEY_PC dengan path key privat di PC-mu kalau namanya lain (mis. ~/.ssh/id_rsa)."
# Sesi tersimpan dengan user yang kini ditolak (root, user bawaan cloud) yang
# menyambung ulang otomatis cepat mencapai maxretry fail2ban: IP-mu ke-ban, dan
# recidive memblokir semua port, termasuk login $USERNAME.
DITOLAK=root${LAIN// /, }
info "Hapus atau ubah sesi tersimpan di klien SSH/SFTP-mu (MobaXterm, Dolphin, VS Code, rsync)"
info "yang masih memakai user $DITOLAK: tiap percobaannya dihitung login gagal oleh"
info "fail2ban dan bisa membuat IP-mu ke-ban."
