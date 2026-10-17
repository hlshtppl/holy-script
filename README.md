# Roblox Route Tools

Panel UI untuk Roblox Studio: record dan replay gerakan karakter,
simpan checkpoint buatan sendiri, dan teleport berurutan.
Dibuat sebagai proyek belajar Luau untuk game buatan sendiri.

![Screenshot](docs/screenshot.png)

## Fitur
- Record gerakan karakter (posisi dan lompatan) lalu replay otomatis
- Checkpoint di sisi server, tersimpan per pemain, respawn di checkpoint terakhir
- Tandai checkpoint manual, lalu Play CP untuk teleport sesuai urutan
- Panel UI yang bisa digeser

## Instalasi (di Roblox Studio)
1. Di Workspace, buat Folder bernama `Checkpoints`, isi Part bernama
   `1`, `2`, `3`, dst (centang Anchored).
2. Buat `Script` di `ServerScriptService`, isi dari
   `src/ServerScriptService/Checkpoints.server.lua`.
3. Buat `LocalScript` di `StarterPlayer > StarterPlayerScripts`, isi dari
   `src/StarterPlayerScripts/RouteTools.client.lua`.
4. Tekan F5 untuk tes.

## Cara pakai
| Tombol | Fungsi |
|---|---|
| Record / Stop Record | Rekam gerakan karakter |
| Replay | Jalankan ulang rekaman |
| Teleport Checkpoint | Teleport ke checkpoint server terakhir |
| Mulai/Selesai Simpan CP | Mode tandai checkpoint manual |
| Tandai CP | Simpan posisi saat ini |
| Play CP | Teleport berurutan ke semua checkpoint tersimpan |

## Batasan
- Rekaman dan checkpoint manual masih di memori (hilang saat sesi berakhir)
- Replay berbasis `Humanoid:MoveTo`, jadi presisi lompatan terbatas

## Rencana
- [ ] Simpan permanen dengan DataStore
- [ ] Daftar checkpoint dan undo

## Catatan
Hanya untuk dipakai di game buatan sendiri di Roblox Studio.

## Lisensi
MIT