#!/usr/bin/env bash
# Pemeriksaan keamanan VPS - HANYA MEMBACA, tidak mengubah apa pun.
#
#   sudo -v && ./cek-keamanan.sh     # sebagai user biasa; bagian root pakai sudo -n
#
# Port SSH yang diharapkan dibaca dari /etc/ssh/sshd_config.d/00-hardening.conf
# (dipasang setup.sh); bisa ditimpa: PORT_SSH=2222 ./cek-keamanan.sh
#
# Kode keluar: 0 = semua OK, 1 = ada AWAS, 2 = bagian [root] dilewati (tanpa sudo),
# 3 = satu-satunya AWAS adalah "Perlu reboot" (pengamanan lengkap, tinggal reboot).
set -uo pipefail
# Output program dibaca script (sshd -T, ufw, fail2ban): paksa bahasa Inggris.
export LC_ALL=C.UTF-8

# Baris Port terakhir: saat transisi (22 + port baru) yang terakhir adalah port baru.
PORT_SSH=${PORT_SSH:-$(sed -nE 's/^Port[[:space:]]+([0-9]+).*/\1/p' /etc/ssh/sshd_config.d/00-hardening.conf 2>/dev/null | tail -1)}
PORT_SSH=${PORT_SSH:-2222}
N_OK=0; N_AWAS=0; DAFTAR_AWAS=()
ok()   { printf '  \033[32mOK\033[0m    %s\n' "$*"; N_OK=$((N_OK+1)); }
awas() { printf '  \033[33mAWAS\033[0m  %s\n' "$*"; N_AWAS=$((N_AWAS+1)); DAFTAR_AWAS+=("$*"); }
info() { printf '        %s\n' "$*"; }
judul(){ printf '\n== %s\n' "$*"; }

if sudo -n true 2>/dev/null; then ROOT=1; S="sudo -n"; else ROOT=0; S=""; fi
[ $ROOT = 1 ] || echo "(sudo -n tidak tersedia: bagian bertanda [root] dilewati. Jalankan sudo -v dulu.)"

judul "Sistem"
. /etc/os-release; info "$PRETTY_NAME, kernel $(uname -r), uptime $(uptime -p), zona waktu $(timedatectl show -p Timezone --value 2>/dev/null || echo '?')"
PERLU_REBOOT=0
if [ -f /var/run/reboot-required ]; then awas "Perlu reboot (update kernel/library)"; PERLU_REBOOT=1
else ok "Tidak perlu reboot"; fi

judul "SSH"
if [ $ROOT = 1 ]; then
    # clientalive*: sesi "hantu" (VPN ganti, PC sleep) diputus dalam ~3 menit.
    declare -A mau=([port]=$PORT_SSH [permitrootlogin]=no [passwordauthentication]=no
                    [kbdinteractiveauthentication]=no [pubkeyauthentication]=yes [permitemptypasswords]=no
                    [clientaliveinterval]=60 [clientalivecountmax]=3)
    efektif=$($S sshd -T 2>/dev/null)
    for k in port permitrootlogin passwordauthentication kbdinteractiveauthentication pubkeyauthentication \
             permitemptypasswords clientaliveinterval clientalivecountmax; do
        v=$(awk -v k="$k" '$1==k{print $2; exit}' <<<"$efektif")
        [ "$v" = "${mau[$k]}" ] && ok "$k $v" || awas "$k $v (harusnya ${mau[$k]})"
    done
    # AllowUsers/AllowGroups dari semua file digabung; sshd -T menulis satu
    # baris per entri. Salah satunya cukup untuk membatasi siapa yang boleh login.
    allow=$(sed -n 's/^allowusers //p' <<<"$efektif" | sort -u | paste -sd' ')
    allowg=$(sed -n 's/^allowgroups //p' <<<"$efektif" | sort -u | paste -sd' ')
    if [ -n "$allow" ]; then ok "allowusers $allow (hanya user ini yang boleh login SSH)"
    elif [ -n "$allowg" ]; then ok "allowgroups $allowg (hanya anggota grup ini yang boleh login SSH)"
    else awas "allowusers tidak diatur: semua user yang punya key bisa login SSH"; fi
    # Login password/root "yes" di file lain (mis. 50-cloud-init.conf, atau
    # "PermitRootLogin yes" dari provider): sekarang kalah oleh 00-hardening.conf
    # yang dibaca lebih dulu, tapi aktif lagi kalau file itu hilang, dan di dalam
    # blok Match langsung berlaku (tidak tampil di sshd -T).
    # Semua bentuk yang diterima sshd: "=" atau spasi, huruf besar/kecil, "yes"
    # berkutip, komentar di ujung baris.
    re='^[[:space:]]*(PasswordAuthentication|KbdInteractiveAuthentication|ChallengeResponseAuthentication|PermitRootLogin|PermitEmptyPasswords)([[:space:]]*=[[:space:]]*|[[:space:]]+)"?yes"?([[:space:]]+#.*)?[[:space:]]*$'
    pw_ya=$($S sh -c 'grep -HniE "$1" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null' _ "$re")
    if [ -z "$pw_ya" ]; then ok "Tidak ada login password/root 'yes' tersisa di file konfigurasi SSH"
    else
        awas "Login password/root masih 'yes' di file (aktif kalau 00-hardening.conf hilang, atau di blok Match):"
        sed 's/^/          /' <<<"$pw_ya"
        info "Perbaiki: ubah jadi 'no' (jalankan ulang setup), lalu: sudo sshd -t && sudo systemctl reload ssh"
    fi
else
    info "[root] sshd -T dilewati"
fi
dengar=$(ss -tlnH | awk '{print $4}' | grep -E ":(22|$PORT_SSH)$" | sort -u | paste -sd' ')
info "Socket SSH listen: ${dengar:-tidak ada}"
ss -tlnH | awk '{print $4}' | grep -qE ":$PORT_SSH$" && ok "Port $PORT_SSH listen" || awas "Port $PORT_SSH TIDAK listen"
if [ "$PORT_SSH" != 22 ]; then
    ss -tlnH | awk '{print $4}' | grep -qE ":22$" && awas "Port 22 masih listen" || ok "Port 22 tertutup"
fi

judul "Akun"
uid0=$(awk -F: '$3==0{print $1}' /etc/passwd | paste -sd' ')
[ "$uid0" = root ] && ok "Hanya root ber-UID 0" || awas "Akun UID 0: $uid0"
info "Akun dengan shell login: $(awk -F: '$7!~/(nologin|false|sync)$/{print $1}' /etc/passwd | paste -sd' ')"
info "Anggota grup sudo: $(getent group sudo | cut -d: -f4)"
if [ $ROOT = 1 ]; then
    kosong=$($S awk -F: '$2==""{print $1}' /etc/shadow | paste -sd' ')
    [ -z "$kosong" ] && ok "Tidak ada akun berpassword kosong" || awas "Password kosong: $kosong"
    # sudo tanpa password untuk selain root: siapa pun yang masuk ke akun itu
    # (mis. user default cloud "ubuntu"/"debian") langsung jadi root.
    # /etc/sudoers-rs: sudo-rs (default Ubuntu 26.04) membacanya lebih dulu dari
    # /etc/sudoers kalau file itu ada, jadi ikut diperiksa.
    np=$($S sh -c 'grep -HvE "^[[:space:]]*(#|$)" /etc/sudoers-rs /etc/sudoers /etc/sudoers.d/* 2>/dev/null' \
        | grep 'NOPASSWD' | grep -vE ':[[:space:]]*(root[[:space:]]|Defaults)')
    if [ -z "$np" ]; then ok "Tidak ada sudo tanpa password selain root"
    else
        awas "Ada sudo tanpa password (NOPASSWD) selain root:"
        sed 's/^/          /' <<<"$np"
        info "Perbaiki: hapus baris itu dengan  sudo visudo -f FILE  (FILE = nama sebelum ':')."
        info "User bawaan cloud (ubuntu/debian/admin) yang tidak kamu pakai: setelah login user-mu"
        info "+ sudo terbukti, hapus juga usernya:  sudo deluser --remove-home NAMA"
    fi
fi

# cek_izin PATH USER JENIS: StrictModes sshd menolak key kalau home, ~/.ssh,
# atau authorized_keys bisa ditulis orang lain atau bukan milik user.
cek_izin() {
    local st m o
    st=$($S stat -c '%a %U' "$1" 2>/dev/null) || { awas "$1 tidak bisa diperiksa"; return; }
    read -r m o <<<"$st"
    case $3 in
        home) [[ $o == "$2" || $o == root ]] && (( (8#$m & 8#022) == 0 )) \
                  && ok "$1 $m $o (tidak bisa ditulis orang lain)" \
                  || awas "$1 $m $o (harusnya milik $2, tanpa izin tulis group/orang lain)";;
        ssh)  [[ $o == "$2" && $m == 700 ]] && ok "$1 700 $o" || awas "$1 $m $o (harusnya 700 milik $2)";;
        ak)   [[ $o == "$2" && $m == 600 ]] && ok "$1 600 $o" || awas "$1 $m $o (harusnya 600 milik $2)";;
    esac
}

judul "Kunci SSH (authorized_keys)"
for h in /home/*; do
    u=$(basename "$h"); f="$h/.ssh/authorized_keys"
    $S test -e "$f" || continue
    $S ssh-keygen -lf "$f" 2>/dev/null | sed "s|^|        $u: |"
    # Nama persis atau USER@host. Pola wildcard (ops*) tidak dinilai.
    if [ -n "${allow:-}" ] && [[ $allow != *[*?]* ]] \
       && ! awk -v u="$u" '{for (i = 1; i <= NF; i++) if ($i == u || index($i, u "@") == 1) f = 1} END {exit !f}' <<<"$allow"; then
        info "$u: tidak ada di AllowUsers, jadi key di atas tidak bisa dipakai login SSH"
    fi
    cek_izin "$h" "$u" home
    cek_izin "$h/.ssh" "$u" ssh
    cek_izin "$f" "$u" ak
done
if [ $ROOT = 1 ]; then
    if $S test -s /root/.ssh/authorized_keys; then
        awas "root masih punya authorized_keys (login root memang mati, tapi sebaiknya dinonaktifkan)"
    else ok "root tidak punya authorized_keys"; fi
fi

judul "Firewall (UFW) [root]"
if [ $ROOT = 1 ]; then
    st=$($S ufw status verbose 2>/dev/null)
    grep -q "Status: active" <<<"$st" && ok "UFW aktif" || awas "UFW TIDAK aktif"
    grep -q "Default: deny (incoming)" <<<"$st" && ok "Default tolak koneksi masuk" || awas "Default incoming bukan deny"
    grep -E "^$PORT_SSH/tcp +LIMIT IN +Anywhere " <<<"$st" >/dev/null \
        && ok "$PORT_SSH/tcp LIMIT dari mana saja (IPv4)" || awas "Tidak ada aturan '$PORT_SSH/tcp LIMIT IN Anywhere' (IPv4)"
    if grep -q '^IPV6=yes' /etc/default/ufw 2>/dev/null; then
        grep -E "^$PORT_SSH/tcp \(v6\) +LIMIT IN +Anywhere \(v6\)" <<<"$st" >/dev/null \
            && ok "$PORT_SSH/tcp LIMIT dari mana saja (IPv6)" || awas "Tidak ada aturan '$PORT_SSH/tcp (v6) LIMIT' (IPv6)"
    fi
    if [ "$PORT_SSH" != 22 ]; then
        grep -E '^(22(/tcp)?|OpenSSH)( \(v6\))? ' <<<"$st" >/dev/null \
            && awas "Aturan port 22/OpenSSH masih ada di UFW" || ok "Tidak ada aturan port 22 di UFW"
    fi
    # Whitelist (ALLOW dari IP tertentu di atas LIMIT) disengaja pemilik: info, bukan AWAS.
    wl=$(grep -E "^$PORT_SSH/tcp( \(v6\))? +ALLOW IN " <<<"$st" \
        | awk '{for (i = 1; i < NF; i++) if ($i == "IN") { print $(i+1); break }}' | grep -v '^Anywhere' | paste -sd' ')
    [ -z "$wl" ] || info "Whitelist UFW (tanpa rate-limit): $wl"
    # Aturan yang membuka port selain SSH. Port tanpa program yang listen tidak
    # terlihat di "Port yang terbuka ke luar", jadi aturan seperti "allow 8080"
    # atau "Anywhere ALLOW IN <ip>" (semua port) baru ketahuan di sini.
    aturan=$(sed -n '/^--/,$p' <<<"$st" | tail -n +2 | grep -E ' (ALLOW|LIMIT)( IN| FWD)? ' || true)
    ekstra=$(awk -v p="$PORT_SSH/tcp" '$1 != p' <<<"$aturan")
    if [ -z "$ekstra" ]; then ok "UFW hanya membuka port SSH $PORT_SSH"
    else
        awas "UFW membuka selain port SSH (pastikan memang perlu):"
        sed 's/^/          /' <<<"$ekstra"
    fi
    sed -n '/^--/,$p' <<<"$st" | tail -n +2 | grep -v '^$' | sed 's/^/        /'
fi

judul "Port yang terbuka ke luar"
publik=$(ss -tulnH | awk '{print $5}' | grep -vE '^(127\.|\[::1\]|::1)' | grep -vE '%lo:' | sort -u)
# Socket UDP QUIC milik cloudflared.service (Cloudflare Tunnel): klien yang
# terhubung KELUAR ke Cloudflare dengan port acak, bukan layanan; koneksi masuk
# tetap ditolak UFW. Hanya PID utama service itu yang dikenali: cloudflared lain
# (tunnel liar, sering dipakai sebagai backdoor) tetap AWAS.
cfd=""; n_cfd=0
cf_pid=$(systemctl show -p MainPID --value cloudflared 2>/dev/null)
if [ $ROOT = 1 ] && [ -n "$cf_pid" ] && [ "$cf_pid" != 0 ]; then
    cfd=$($S ss -ulnpH 2>/dev/null | awk -v pid="pid=$cf_pid," 'index($0, pid) {print $4}' | sort -u)
fi
for p in $publik; do
    if [ -n "$cfd" ] && grep -qxF -- "$p" <<<"$cfd"; then n_cfd=$((n_cfd + 1)); continue; fi
    # 68 (DHCPv4) / 546 (DHCPv6): klien DHCP systemd-networkd di VPS ber-IP dinamis,
    # bukan layanan; koneksi masuk tetap diblokir UFW.
    case "$p" in
        *:"$PORT_SSH") ok "$p (SSH)";;
        *:68|*:546)    ok "$p (klien DHCP, bukan layanan)";;
        *:5355|*:5353) awas "$p terbuka ke luar - LLMNR/mDNS systemd-resolved, tidak perlu di VPS (jalankan ulang setup.sh, atau LLMNR=no + MulticastDNS=no di /etc/systemd/resolved.conf.d/)";;
        *)             awas "$p terbuka ke luar - pastikan memang perlu";;
    esac
done
[ $n_cfd = 0 ] || ok "$n_cfd socket UDP cloudflared.service (Cloudflare Tunnel, koneksi keluar; bukan layanan)"

judul "fail2ban [root]"
if [ $ROOT = 1 ]; then
    systemctl is-active -q fail2ban && ok "fail2ban aktif" || awas "fail2ban TIDAK aktif"
    aktif=$($S fail2ban-client status 2>/dev/null | sed -n 's/.*Jail list:\s*//p' | tr -d ',')
    # Port dibaca dari aksi jail yang sedang berjalan, bukan dari file konfigurasi.
    declare -A port_jail=([sshd]=$PORT_SSH [sshd-lambat]=$PORT_SSH [recidive]=0:65535)
    for j in sshd sshd-lambat recidive; do
        if ! tr ' ' '\n' <<<"$aktif" | grep -qx "$j"; then awas "jail $j TIDAK aktif"; continue; fi
        aksi=$($S fail2ban-client get "$j" actions 2>/dev/null | tail -n +2 | tr ',' '\n' | sed 's/^ *//' | head -1)
        p=$($S fail2ban-client get "$j" action "$aksi" port 2>/dev/null)
        [ "$p" = "${port_jail[$j]}" ] && ok "jail $j aktif, aksi $aksi, port $p" \
            || awas "jail $j aktif, tapi port aksinya '${p:-?}' (harusnya ${port_jail[$j]})"
    done
    for j in $aktif; do
        ig=$($S fail2ban-client get "$j" ignoreip 2>/dev/null | tail -n +2 | sed 's/^[|`]- *//' \
            | grep -vxE '127\.0\.0\.0/8|::1' | paste -sd' ')
        [ -z "$ig" ] || info "$j: whitelist (tidak pernah di-ban): $ig"
        b=$($S fail2ban-client status "$j" | awk -F'\t' '/Currently banned/{print $2}')
        t=$($S fail2ban-client status "$j" | awk -F'\t' '/Total banned/{print $2}')
        info "$j: diblokir sekarang $b, total $t"
    done
    # Jail "aktif" belum tentu mendeteksi: OpenSSH >= 9.8 menulis kegagalan login
    # lewat "sshd-session", yang tidak dikenali journalmatch/filter versi lama.
    # Versi SERVER (paket openssh-server, mis. "1:9.6p1-3ubuntu13"), bukan klien
    # "ssh -V" yang bisa berbeda; "ssh -V" hanya cadangan.
    versi=$(dpkg-query -W -f='${Version}' openssh-server 2>/dev/null | sed -nE 's/^([0-9]+:)?([0-9]+)\.([0-9]+).*/\2 \3/p')
    [ -n "$versi" ] || versi=$(ssh -V 2>&1 | sed -nE 's/^OpenSSH_([0-9]+)\.([0-9]+).*/\1 \2/p')
    read -r mayor minor <<<"${versi:-0 0}"
    if (( mayor > 9 || (mayor == 9 && minor >= 8) )); then
        $S fail2ban-client get sshd journalmatch 2>/dev/null | grep -q '_COMM=sshd-session' \
            && ok "journalmatch sshd mengenali sshd-session (OpenSSH $mayor.$minor)" \
            || awas "OpenSSH $mayor.$minor menulis log lewat sshd-session, tapi journalmatch jail sshd tidak memuatnya"
    fi
    # Bukti deteksi dari log: login gagal TERAKHIR di journal harus tercatat jail
    # sshd sebagai "Found IP - waktu-yang-sama" (atau "Ignore IP" untuk IP
    # whitelist). Dicocokkan per kejadian, bukan dihitung, supaya baris lama atau
    # arsip .gz tidak memberi OK palsu setelah deteksi rusak (mis. upgrade
    # OpenSSH). Dilewati: localhost (uji dari setup), kejadian < 1 menit
    # (belum sempat diproses), dan sebelum jangkauan fail2ban. Saat pertama
    # start, fail2ban juga membaca journal sejauh findtime ke belakang, jadi
    # jangkauannya mulai dari baris log pertama dikurangi findtime jail sshd.
    f2blog=$($S sh -c 'zcat -f /var/log/fail2ban.log*' 2>/dev/null)
    awal=$(grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8}' <<<"$f2blog" | sort | head -1)
    ft=$($S fail2ban-client get sshd findtime 2>/dev/null | tail -1 | tr -dc '0-9')
    # fail2ban.log memakai jam lokal saat baris ditulis: setelah zona waktu
    # diganti (mis. UTC -> WIB), baris lama masih jam UTC. Untuk awal jangkauan
    # dipakai tafsiran yang paling lambat, supaya jangkauan tidak melebar ke
    # sebelum fail2ban terpasang.
    if [ -n "$awal" ]; then
        e=$(date -d "$awal" +%s); eu=$(date -d "$awal UTC" +%s)
        (( eu > e )) && e=$eu
        awal=$(date -d "@$((e - ${ft:-0}))" '+%F %T')
    fi
    batas=$(date -d '-7 days' '+%F %T')
    [[ -n $awal && $awal > $batas ]] && batas=$awal
    # "User X from IP not allowed because not listed in AllowUsers": user yang ada
    # tapi tidak diizinkan (paling sering root dari bot); barisnya tanpa "port".
    akhir=$($S journalctl -u ssh --since "$batas" --until -1min --no-pager -o short-iso 2>/dev/null \
        | grep -E 'Invalid user|Failed (password|keyboard-interactive)|not allowed because' \
        | grep -E ' from [0-9a-fA-F.:]+ (port |not allowed)' \
        | grep -vE ' from (127\.0\.0\.1|::1) ' | tail -1)
    if [ -z "$akhir" ]; then
        info "Deteksi jail sshd belum bisa dibuktikan: belum ada login gagal (selain localhost) sejak $batas"
    else
        ip=$(sed -nE 's/.* from ([0-9a-fA-F.:]+) (port|not allowed) .*/\1/p' <<<"$akhir")
        iso=$(awk '{print $1}' <<<"$akhir")
        t=$(date -d "$iso" '+%F %T'); tu=$(TZ=UTC date -d "$iso" '+%F %T')
        # Cocokkan dengan jam lokal sekarang ATAU jam UTC (baris dari sebelum
        # zona waktu diganti).
        tercatat() {
            grep -F "[sshd] Found $ip - $1" <<<"$f2blog" >/dev/null \
            || awk -v t="$1" -v s="[sshd] Ignore $ip " 'substr($0, 1, 19) >= t && index($0, s)' <<<"$f2blog" | grep . >/dev/null
        }
        if tercatat "$t" || tercatat "$tu"; then
            ok "Deteksi jail sshd bekerja: login gagal terakhir ($ip, $t) tercatat fail2ban"
        else
            awas "Login gagal terakhir ($ip, $t) TIDAK tercatat jail sshd - deteksi rusak?"
        fi
    fi
    # "port = ssh" berarti 22: ban tidak menutup port SSH yang asli.
    $S grep -hE "^\s*port\s*=\s*ssh\s*$" /etc/fail2ban/jail.local /etc/fail2ban/jail.d/*.local 2>/dev/null \
        | grep -q . && awas "Ada jail dengan 'port = ssh' (=22), harusnya $PORT_SSH" || ok "Port jail tidak memakai default 22"
    # Ban bertingkat butuh riwayat ban: kalau database dibersihkan lebih cepat dari
    # ban terpanjang, penyerang yang kembali mulai lagi dari ban pertama.
    purge=$($S fail2ban-client get dbpurgeage 2>/dev/null | tail -1 | tr -dc '0-9')
    maks=$($S fail2ban-client get sshd bantime.maxtime 2>/dev/null | tail -1 | tr -dc '0-9')
    if [ -n "$purge" ] && [ -n "$maks" ]; then
        [ "$purge" -ge "$maks" ] \
            && ok "dbpurgeage $((purge / 86400)) hari >= ban terpanjang $((maks / 86400)) hari (ban bertingkat efektif)" \
            || awas "dbpurgeage $((purge / 86400)) hari < ban terpanjang $((maks / 86400)) hari: riwayat ban hilang, ban bertingkat mulai dari awal lagi"
    fi
fi

judul "Login 7 hari terakhir [root]"
if [ $ROOT = 1 ]; then
    j=$($S journalctl -u ssh --since -7d --no-pager -o cat 2>/dev/null)
    info "Login sukses per user/IP/key:"
    grep -oE 'Accepted publickey for \S+ from \S+ port [0-9]+ ssh2: \S+ \S+' <<<"$j" \
        | awk '{print $4, $6, $NF}' | sort | uniq -c | sed 's/^/          /'
    grep -q 'Accepted password' <<<"$j" && awas "Ada login dengan PASSWORD!" || ok "Tidak ada login dengan password"
    info "Percobaan gagal/invalid: $(grep -cE 'Invalid user|Failed |Connection closed by (authenticating|invalid) user' <<<"$j")"
fi
# Ubuntu 26.04 dan Debian 13: "last" tidak lagi ada di util-linux; penggantinya
# paket wtmpdb (perintah "wtmpdb last").
info "Riwayat login terakhir:"
if command -v last >/dev/null; then
    last -n 5 -a 2>/dev/null | grep -v '^$' | sed 's/^/          /'
elif command -v wtmpdb >/dev/null; then
    wtmpdb last 2>/dev/null | grep -v '^$' | head -n 5 | sed 's/^/          /'
else
    info "  (perintah last tidak ada; pasang dengan: sudo apt install wtmpdb. Login di atas tetap dari journal)"
fi

judul "Update"
# Simulasi upgrade, bukan "apt list --upgradable": Ubuntu menunda sebagian update
# secara bertahap (phased updates). Paket itu tampil di daftar tapi memang belum
# boleh dipasang, sehingga sebelumnya memberi AWAS palsu.
sim=$(apt-get -s dist-upgrade 2>/dev/null)
n=$(grep -c '^Inst ' <<<"$sim")
tunda=$(sed -n '/deferred due to phasing:/,/^[^ ]/{/^ /p}' <<<"$sim" | wc -w)
[ "$n" = 0 ] && ok "Tidak ada paket menunggu update" || awas "$n paket bisa di-update (sudo apt upgrade)"
[ "$tunda" = 0 ] || info "$tunda paket ditunda bertahap oleh Ubuntu (phased update) - normal, akan terpasang otomatis"
systemctl is-active -q unattended-upgrades && ok "unattended-upgrades aktif (update keamanan otomatis)" || awas "unattended-upgrades tidak aktif"

judul "Port yang dipesan (ip_local_reserved_ports)"
info "$(cat /proc/sys/net/ipv4/ip_local_reserved_ports 2>/dev/null || echo -)"

judul "Ringkasan"
info "Hasil: $N_OK OK, $N_AWAS AWAS"
for a in "${DAFTAR_AWAS[@]}"; do info "  - AWAS: $a"; done
echo
[ $ROOT = 1 ] || { info "Bagian [root] dilewati: hasil belum lengkap."; exit 2; }
[ "$N_AWAS" = 0 ] && exit 0
[ "$N_AWAS" = 1 ] && [ $PERLU_REBOOT = 1 ] && { info "Satu-satunya AWAS: perlu reboot (sudo reboot)."; exit 3; }
exit 1
