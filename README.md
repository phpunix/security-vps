# security-vps

Pengamanan awal untuk setiap VPS **Ubuntu/Debian baru** (atau habis reinstall)
yang diserahkan provider dengan akses `root` + SSH key. Satu script interaktif,
dijalankan sekali sebagai root sebelum VPS dipakai untuk proyek apa pun.

| Bagian | Hasil |
|---|---|
| User | user non-root pilihanmu (grup `sudo`), login hanya dengan SSH key |
| SSH | port pilihanmu, root login mati, password login mati, sesi "hantu" diputus ~3 menit |
| Firewall | UFW: tolak semua koneksi masuk kecuali port SSH (rate-limit) |
| Brute-force | fail2ban: jail `sshd`, `sshd-lambat` (serangan pelan), `recidive` (pelaku berulang, semua port), ban bertingkat |
| Lainnya | swap, update keamanan otomatis (layanan yang masih memakai library lama di-restart otomatis oleh `needrestart`), key root dinonaktifkan |

**Teruji** (VPS Hetzner dan BeroHost, dari awal sampai selesai,
`cek-keamanan.sh` 0 AWAS):

| OS | OpenSSH | Catatan |
|---|---|---|
| Ubuntu 24.04 | 9.6 | socket activation (`ssh.socket`), sudo klasik |
| Ubuntu 26.04 | 10.2 | socket activation, `sudo` = sudo-rs |
| Debian 13 | 10.0 | `ssh.service` biasa, UFW & fail2ban dipasang dari nol; image BeroHost menyalakan LLMNR/mDNS (port 5355), dimatikan otomatis di langkah 5 |

Versi terbaru (`AllowUsers`, `yes` jadi `no` di file SSH provider, override
cloud-init) teruji di BeroHost untuk ketiga OS di atas, Debian 13 juga
setelah reboot. Image BeroHost membawa `PermitRootLogin yes` dan
`PasswordAuthentication yes` dari provider; keduanya diubah jadi `no`. Di
Ubuntu 24.04 juga teruji: run ulang di atas setup versi lama (wajib lewat
transisi + uji login lagi) dan run ulang dengan user tambahan di `AllowUsers`
(dipertahankan). Zona waktu (langkah 1) teruji di Debian 13. Versi dengan
`needrestart`, daftar default, nama user/port wajib diketik, dan zona waktu
bebas teruji dari awal di Hetzner Debian 13 (0 AWAS), dan sebagai run ulang di
atas setup versi lama di BeroHost Debian 13 (0 AWAS). Pemeriksaan
`needrestart -b` di `cek-keamanan.sh` teruji di BeroHost Debian 13 dalam kondisi
bersih; kondisi kernel/layanan yang tertunda baru diuji dengan output
needrestart tiruan, dan belum diuji di Ubuntu.

Juga teruji (Hetzner, versi sebelumnya): uji login port baru yang gagal
(port 22 tetap bisa dipakai, tidak terkunci), menjalankan ulang dari kondisi
setengah jadi, reboot pasca-setup di ketiga OS, dan ban dari IP asing. Image
dengan user bawaan cloud (`ubuntu`/`admin`, mis. AWS/Oracle) belum diuji.

```
security-vps/
├── setup.sh               script utama (root, interaktif)
├── cek-keamanan.sh        audit keamanan, hanya membaca
├── files/
│   ├── 00-hardening.conf  -> /etc/ssh/sshd_config.d/
│   ├── jail.local         -> /etc/fail2ban/
│   ├── sshd-lambat.local  -> /etc/fail2ban/jail.d/
│   └── fail2ban.local     -> /etc/fail2ban/ (riwayat ban 30 hari)
└── CLAUDE.md              aturan kalau dikerjakan bersama Claude Code
```

Repo ini tidak berisi rahasia (tanpa key, IP, atau password), jadi aman dibuat
publik. Whitelist IP yang kamu pilih saat setup hanya tersimpan di VPS.

---

## 1. Sebelum mulai

- **Login root dengan SSH key** dari PC sudah bisa (`ssh root@IP-VPS`). Key ini
  yang nanti disalin ke user baru.
- **Firewall di panel provider** (kalau ada, mis. Hetzner Cloud Firewall):
  selama setup izinkan TCP **22 dan port baru** (yang akan kamu ketik di script).
- Tahu cara membuka **web console** (VNC/serial) di panel provider. Itu jalan
  darurat kalau SSH bermasalah, dan memakai **password root**: simpan, atau
  ganti saat script menawarkan.
- Jalankan **secepatnya** setelah VPS jadi: sebelum script mematikannya, root
  masih bisa dicoba lewat password oleh bot.

## 2. Pasang dan jalankan

Di sesi root VPS baru (`ssh root@IP-VPS`). **Sesi root ini jangan ditutup**
sampai script selesai.

**Dengan git** (Ubuntu biasanya sudah ada; Debian minimal kadang belum):

```bash
command -v git >/dev/null || apt-get -o DPkg::Lock::Timeout=300 install -y git
git clone https://github.com/phpunix/security-vps.git
cd security-vps
bash setup.sh --dry-run    # lihat alurnya dulu, tidak mengubah apa pun
bash setup.sh
```

**Tanpa git** (unduh arsip):

```bash
curl -fsSL https://github.com/phpunix/security-vps/archive/refs/heads/main.tar.gz | tar xz
mv security-vps-main security-vps && cd security-vps && bash setup.sh
```

(Versi arsip tidak bisa di-`git pull`; untuk update, unduh ulang atau pakai git.)

**Dari PC** (repo private, atau tanpa internet ke GitHub):

```bash
scp -r security-vps root@IP-VPS:/root/      # di PC
bash /root/security-vps/setup.sh            # di sesi root VPS
```

## 3. Alur script

Nama user dan port SSH wajib diketik (tanpa default, Enter kosong ditanya
ulang). Pertanyaan lain punya default; cukup tekan Enter untuk memakainya (di
log ditandai `(default)`):

| Pertanyaan | Default |
|---|---|
| Nama user non-root | tidak ada, **wajib diketik** |
| Port SSH | tidak ada, **wajib diketik** (1024-65535) |
| Swap | `4G` (`0` = tanpa swap; tidak ditanya kalau swap sudah ada) |
| Whitelist IP | IP yang sedang kamu pakai, **terdeteksi otomatis** dari sesi SSH yang menjalankan script (juga lewat `sudo`). Kalau tidak terdeteksi (mis. web console): tanpa whitelist. `-` = tanpa whitelist |
| Zona waktu | `Asia/Jakarta` (`-` = tidak diubah). Boleh diketik bebas: nama kota (`Makassar`, `new york`), `WIB`/`WITA`/`WIT`, `UTC`, selisih jam bulat (`GMT+7`, `UTC-5`), atau nama lengkap (`Asia/Singapore`); huruf besar/kecil bebas, isian yang tidak dikenal ditanya ulang |

Lalu:

| Langkah | Isi |
|---|---|
| 1 | Matikan login password SSH dulu (masih port 22, root tetap bisa dengan key), pasang zona waktu (sebelum layanan lain menulis log, supaya log memakai satu zona), tunggu apt bebas, update sistem, pasang `needrestart` dan (kalau perintah `last` belum ada, mis. Debian 13) `wtmpdb`. Kalau butuh reboot: reboot, login root, jalankan ulang |
| 2 | Buat user + password (untuk sudo), salin key root (tanpa opsi `command=` cloud-init; kalau key lebih dari satu, kamu memilih), tegakkan izin `~/.ssh` |
| 3 | **Uji login user di port 22** dari terminal baru di PC |
| 4 | Swap |
| 5 | UFW: port 22 (sementara) + port baru, rate-limit, whitelist opsional |
| 6 | Hardening SSH: listen di port 22 **dan** port baru (dua tahap); hanya user baru yang boleh login SSH (`AllowUsers`); `yes` untuk login password/root di file SSH lain (mis. `50-cloud-init.conf`, `PermitRootLogin yes` dari provider) jadi `no`, cloud-init dicegah menyalakan login password lagi |
| 7 | **Uji login user di port baru** dari terminal baru di PC |
| 8 | Konfigurasi akhir (hanya port baru), tutup port 22 |
| 9 | fail2ban + uji ban dan uji deteksi login gagal |
| 10 | **Konfirmasi**, lalu nonaktifkan key root |
| 11 | Update keamanan otomatis; `needrestart` me-restart otomatis layanan yang masih memakai library lama (di Debian diatur script; reboot untuk kernel tetap manual) |
| 12 | Verifikasi akhir dengan `cek-keamanan.sh` |

**Di langkah 3 dan 7** script berhenti dan meminta kamu menguji dari PC:

```bash
ssh -p PORT USER@IP-VPS          # (langkah 3: tanpa -p, port 22)
sudo true && echo SUDO OK
```

Biarkan sesi uji itu **terbuka**, lalu jawab `ya`. Jawaban saja tidak cukup:
script memeriksa log sistem bahwa user itu benar-benar login dengan key di
port yang diuji dan menjalankan `sudo true`. Uji "root harus ditolak"
(`ssh -p PORT root@IP-VPS`) cukup **sekali**: tiap percobaan dihitung
kegagalan oleh fail2ban.

**Kalau uji port baru gagal** (biasanya firewall panel belum membuka port
itu): jawab `tidak`. Port 22 tetap bisa dipakai (`ssh USER@IP-VPS`); perbaiki
penyebabnya lalu jalankan ulang script dengan **port yang sama**.

Pengaman lain:

- Setiap perubahan SSH divalidasi (`sshd -t`, nilai efektif `sshd -T`, port
  benar-benar listen). Gagal -> konfigurasi dikembalikan, script berhenti.
  Rollback tidak pernah menghapus hardening.
- Status tiap aksi tampil `[✓] BERHASIL` / `[✗] GAGAL`; kalau berhenti, alasannya
  ditulis di baris `BERHENTI`.
- Menjalankan ulang aman: langkah yang sudah beres dilewati. Mengganti port
  atau user utama setelah setup selesai ditolak (bisa mengunci); user yang
  kamu tambahkan sendiri di baris `AllowUsers` dipertahankan. Kalau
  `00-hardening.conf` berbeda dari versi script ini (versi lama, atau diubah
  tangan), run ulang lewat transisi + uji login langkah 7 lagi.
- **User bawaan cloud** (`ubuntu`/`debian`/`admin`, dibuat sebagian provider
  dengan key-mu dan sering dengan sudo tanpa password): mulai langkah 6
  `AllowUsers` menolak login SSH mereka; script menyebutkannya di langkah 0.
  Sudo tanpa password (`NOPASSWD`) miliknya tidak diubah script:
  `cek-keamanan.sh` menandainya `AWAS` beserta cara memperbaikinya.
  - Fitur "SSH lewat browser" provider yang login dengan user bawaan (mis. EC2
    Instance Connect, SSH-in-browser GCP) ikut tertutup. Console VNC/serial
    tidak terpengaruh karena tidak lewat SSH.
  - Hapus sesi tersimpan di klien (MobaXterm, Dolphin, VS Code, rsync) yang
    masih memakai root atau user bawaan: tiap percobaannya dihitung login
    gagal dan bisa membuat IP-mu ke-ban.
- **Login password/root di file provider:** `PasswordAuthentication yes` di
  `50-cloud-init.conf`, atau `PermitRootLogin yes` yang ditambahkan provider
  di `sshd_config`, sebenarnya sudah kalah oleh `00-hardening.conf`, tapi
  aktif lagi kalau file itu hilang, dan di dalam blok `Match` tetap berlaku
  (tidak terlihat di `sshd -T`). Script mengubahnya jadi `no` dan memasang
  `ssh_pwauth: false` untuk cloud-init, supaya tidak ditulis ulang saat
  cloud-init menganggap VPS sebagai instance baru.
- **Whitelist IP (opsional):** IP yang sedang kamu pakai bisa dibebaskan dari
  rate-limit UFW dan ban fail2ban, berguna untuk SFTP dari file manager
  (Dolphin dsb.) yang membuka banyak koneksi sekaligus. IP VPN biasanya dipakai
  bersama banyak orang; mereka ikut lolos (login tetap wajib key). Ketik `-`
  kalau tidak mau.

## 4. Setelah selesai

```bash
ssh -p PORT USER@IP-VPS
cat ~/security-vps-log/*.log                     # log semua run, tanpa sudo
sudo reboot                                    # lalu login lagi:
cd ~/security-vps && sudo -v && ./cek-keamanan.sh; echo "EXIT=$?"
```

Hasil harus `0 AWAS` (`EXIT=0`). Repo ikut disalin ke `~/security-vps` (milik
user), dan log tiap run tersimpan di `/root/security-vps-log/` + salinannya di
`~/security-vps-log/`.

Lalu:

- **Firewall panel provider:** hapus aturan port 22, sisakan hanya TCP port
  SSH baru (IPv4 + IPv6). Firewall panel memblok sebelum paket sampai ke VPS,
  jadi tetap melindungi walau UFW bermasalah; pakai bersama UFW + fail2ban.
  Jangan batasi sumbernya ke IP VPN (IP berganti -> terkunci). Kalau suatu saat
  ganti port SSH, ubah di panel **dulu**.
- **Klien SSH di PC** (`~/.ssh/config`):

  ```
  Host nama-vps-bebas
      HostName IP-VPS
      User USER
      Port PORT
      IdentityFile ~/.ssh/id_ed25519
      IdentitiesOnly yes
      AddKeysToAgent yes
  ```

  Nama `Host` bebas; login cukup `ssh nama-vps-bebas`. Tanpa config:
  `ssh -p PORT -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes USER@IP-VPS`.
  `~/.ssh/id_ed25519` adalah nama default OpenSSH; ganti kalau key privat di
  PC-mu bernama lain. `IdentitiesOnly` membuat ssh hanya menawarkan key itu:
  terlalu banyak key di agent berakhir "Too many authentication failures", yang
  dihitung login gagal oleh fail2ban.

  Hapus sesi `root` lama di klien SSH-mu: percobaan login root yang terus
  ditolak bisa membuat IP-mu sendiri ke-ban.
- Aplikasi web sebaiknya listen di `127.0.0.1` dan diakses lewat tunnel SSH
  (`ssh -L 8080:127.0.0.1:8080 nama-vps-bebas`), supaya tidak perlu membuka port lain.

## 5. Pemeriksaan rutin dan update

```bash
cd ~/security-vps && sudo -v && ./cek-keamanan.sh   # mis. sebulan sekali
sudo fail2ban-client status sshd
sudo grep -E ' Ban | Unban ' /var/log/fail2ban.log | tail -20
last -n 10 -a                                          # kalau tidak ada: sudo apt install wtmpdb
```

Perhatikan "Login 7 hari terakhir": semua login harus memakai key-mu, dari IP
yang kamu kenali.

`cek-keamanan.sh` memeriksa: root/password login mati (juga tidak ada `yes`
tersisa di file SSH lain), `AllowUsers` (atau `AllowGroups`), keepalive, izin key,
sudo tanpa password hanya untuk root, aturan UFW (hanya port SSH), port 22
tertutup, port yang terbuka ke luar, jail fail2ban aktif dengan port yang benar
dan **deteksinya terbukti**, riwayat ban bertingkat, update, serta kernel dan
layanan yang masih memakai versi lama (`needrestart -b`, hanya membaca).
Percobaan login gagal dihitung per koneksi, tanpa uji dari localhost. Kode
keluar: `0` semua OK, `1` ada AWAS, `2` bagian root dilewati (lupa `sudo -v`),
`3` AWAS hanya soal reboot (kernel baru, atau layanan yang masih memakai
library lama).

Memperbarui script di VPS yang sudah di-setup:

```bash
cd ~/security-vps && git pull
sudo bash setup.sh        # opsional; jawab port yang SAMA, langkah yang beres dilewati
```

## 6. Kalau terjadi masalah

| Masalah | Penyelesaian (lewat web console provider kalau SSH tidak bisa) |
|---|---|
| Port baru tidak bisa dihubungi | Cek firewall panel provider dulu (port diizinkan?), lalu `sudo ss -tlnp`, `sudo ufw status` |
| Terkunci, SSH tidak bisa | Console sebagai root: `ufw allow 22/tcp`, `sed -i 's/^Port .*/Port 22/' /etc/ssh/sshd_config.d/00-hardening.conf`, lalu Ubuntu `systemctl daemon-reload && systemctl restart ssh.socket` / Debian `systemctl restart ssh`. **Jangan** hapus `00-hardening.conf` (default provider bisa berarti root + password aktif lagi) |
| IP sendiri ke-ban | `sudo fail2ban-client unban IP-KAMU`; alasannya: `sudo grep IP-KAMU /var/log/fail2ban.log` |
| `sshd -t` error | Jangan restart apa pun; perbaiki file yang disebut di pesan error |
| Lupa password sudo user | Console provider sebagai root: `passwd USER` |
| User baru (mis. `deploy`) ditolak SSH padahal key benar | `AllowUsers`: tambahkan namanya di baris `AllowUsers` di `/etc/ssh/sshd_config.d/00-hardening.conf`, lalu `sudo sshd -t && sudo systemctl reload ssh`. Log: `User deploy ... not listed in AllowUsers`. Run ulang `setup.sh` mempertahankan user tambahan ini |
| `AWAS` sudo tanpa password (`NOPASSWD`) | Biasanya user bawaan cloud di `/etc/sudoers.d/90-cloud-init-users`. Hapus barisnya: `sudo visudo -f FILE`; user yang tidak dipakai: `sudo deluser --remove-home NAMA` (setelah login user-mu + sudo terbukti) |
| Script berhenti di tengah | Baca baris `BERHENTI` dan log (`/root/security-vps-log/`), perbaiki, jalankan ulang |
| `AWAS` perlu reboot / layanan masih memakai library lama | `sudo needrestart -r a` me-restart layanan yang aman di-restart; sisanya (mis. `dbus`, `systemd-logind`) dan kernel baru: `sudo reboot`, lalu jalankan `cek-keamanan.sh` lagi |
