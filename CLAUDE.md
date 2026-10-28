# Panduan Agen - security-vps

Script pengamanan awal VPS Ubuntu/Debian baru (`setup.sh`, dijalankan pemilik
sebagai root) dan audit `cek-keamanan.sh` (hanya membaca). Lihat `README.md`.

## Aturan anti-terkunci

- Agen **tidak** menjalankan `setup.sh` tanpa `--dry-run`: script mengubah SSH
  dan firewall, butuh root, dan uji login dari luar hanya bisa dilakukan pemilik.
- Kalau mengubah script, pertahankan:
  - pindah port **dua tahap** (port 22 + port baru dulu; konfigurasi akhir dan
    penutupan port 22 hanya setelah login lewat port baru terbukti),
  - `sshd -t` sebelum menerapkan, verifikasi `sshd -T` dan `ss` sesudahnya,
  - rollback **tidak pernah** menghapus `00-hardening.conf` dan tidak pernah
    mengaktifkan lagi `PasswordAuthentication` atau `PermitRootLogin`,
  - key root baru dinonaktifkan setelah login user + sudo terbukti,
  - `AllowUsers` hanya di konfigurasi transisi (langkah 6) dan akhir, tidak di
    konfigurasi awal/rollback (`KONF_AWAL`); karena `AllowUsers` dari beberapa
    file digabung, `sshd -T | grep ^allowusers` harus persis isi baris
    `AllowUsers` di `00-hardening.conf` (user tambahan pemilik dipertahankan),
  - `sshd -T` tidak menampilkan blok `Match`: semua `yes` untuk login
    berbasis password dan `PermitRootLogin`/`PermitEmptyPasswords` di file SSH
    lain diubah jadi `no` (hanya ke arah lebih ketat), dan `cek-keamanan.sh`
    menandai yang tersisa,
  - transisi + uji login hanya boleh dilompati kalau `00-hardening.conf` **sama
    persis** dengan konfigurasi akhir; jangan dilonggarkan (langkah 3/7
    dilewati saat port 22 tutup, langkah 10 hanya bertanya),
  - Ubuntu memakai socket activation (`daemon-reload` + restart `ssh.socket`),
    Debian `systemctl restart ssh`.
- Uji perubahan dengan `bash -n` dan `--dry-run`; sebutkan apa yang belum diuji
  di VPS sungguhan (tabel "Teruji" di README).
- Jangan mengubah firewall di panel provider atas nama pemilik.
- Jangan membuat, menebak, atau menyimpan password atas nama pemilik.

## Konvensi

- Komunikasi dalam bahasa Indonesia.
- Git: jangan commit kecuali diminta, jangan push, jangan menambah remote.
- Repo ini untuk publik (GitHub): jangan menulis data pemilik (IP, nama user,
  port SSH asli, hostname) di file maupun pesan commit. Pakai placeholder
  (`USER`, `PORT`, `IP-VPS`) di dokumen dan nilai contoh di template
  (`namauser`, `2222`; nilainya selalu diganti `setup.sh`).
- Pembuat commit selalu `phpunix <phpunix@users.noreply.github.com>`. Kalau
  identitas git belum diatur: `git -c user.name=phpunix -c
  user.email=phpunix@users.noreply.github.com commit ...`. Jangan pakai email
  login Claude Code atau tebakan git dari hostname (`user@hostname`): metadata
  commit ikut publik saat di-push.
