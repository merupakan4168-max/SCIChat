# SCIChat — Asisten Riset Ilmiah Berbasis AI

SCIChat adalah aplikasi asisten riset ilmiah berbasis Flutter yang dirancang untuk membantu peneliti, mahasiswa, akademisi, dan pembaca literatur ilmiah dalam menemukan, membaca, memahami, serta menganalisis makalah akademik.

Aplikasi ini mengintegrasikan pencarian literatur dari berbagai sumber, pembacaan dokumen PDF, percakapan AI berbasis konteks makalah, dan pengelolaan referensi dalam satu alur kerja. SCIChat bertujuan membantu pengguna memahami literatur ilmiah secara lebih terstruktur, membandingkan informasi dari beberapa makalah, serta menyusun pemahaman awal terhadap topik penelitian.

SCIChat dikembangkan dengan fokus pada keterbacaan dokumen akademik, integritas referensi, ketahanan percakapan, dan pengalaman membaca yang mendukung sesi penelitian jangka panjang.

## Daftar Isi

- [Fitur Utama](#fitur-utama)
- [Sumber Literatur Ilmiah](#sumber-literatur-ilmiah)
- [Teknologi dan Arsitektur](#teknologi-dan-arsitektur)
- [Privasi dan Penyimpanan Data](#privasi-dan-penyimpanan-data)
- [Persyaratan Sistem](#persyaratan-sistem)
- [Instalasi dan Menjalankan Aplikasi](#instalasi-dan-menjalankan-aplikasi)
- [Pengujian](#pengujian)
- [Dokumentasi Proyek](#dokumentasi-proyek)
- [Batasan dan Catatan Penggunaan](#batasan-dan-catatan-penggunaan)
- [Pengembangan Selanjutnya](#pengembangan-selanjutnya)

## Fitur Utama

### 1. Pencarian Literatur Akademik Multi-Sumber

SCIChat menyediakan mekanisme pencarian literatur yang mengintegrasikan beberapa sumber publikasi ilmiah dan metadata akademik.

Fitur pencarian dirancang untuk membantu pengguna menemukan makalah berdasarkan kebutuhan penelitian, kemudian meninjau informasi bibliografi dan ketersediaan dokumen yang relevan.

Kemampuan pencarian meliputi:

- Pencarian lintas sumber literatur akademik.
- Filter kategori atau bidang penelitian.
- Pemilihan bidang pencarian, seperti judul, abstrak, dan penulis.
- Pengurutan hasil berdasarkan tanggal atau relevansi.
- Dukungan untuk menemukan makalah yang sedang mendapatkan perhatian atau menunjukkan tren berdasarkan mekanisme yang tersedia dalam aplikasi.
- Pengumpulan metadata makalah untuk mendukung proses peninjauan literatur.

Penggabungan beberapa sumber membantu memperluas cakupan pencarian. Namun, kelengkapan metadata, jumlah hasil, dan ketersediaan dokumen tetap bergantung pada sumber masing-masing.

### 2. Percakapan AI dengan Konteks Beberapa Makalah

SCIChat mendukung percakapan AI yang menggunakan satu atau beberapa makalah sebagai konteks penelitian.

Pengguna dapat menyematkan makalah yang relevan ke dalam sesi percakapan, kemudian mengajukan pertanyaan berdasarkan kumpulan dokumen tersebut. Pendekatan ini membantu pengguna mengeksplorasi hubungan antara beberapa penelitian tanpa harus membaca setiap dokumen secara terpisah pada setiap pertanyaan.

Fitur percakapan meliputi:

- Penambahan satu atau beberapa makalah sebagai konteks sesi.
- Penyusunan jawaban berdasarkan konteks penelitian yang tersedia.
- Sintesis informasi dari beberapa sumber.
- Penanda sumber interaktif untuk membantu menelusuri referensi yang mendukung jawaban.
- Saran pertanyaan lanjutan untuk memperdalam eksplorasi topik.
- Pengelolaan sesi percakapan agar konteks penelitian dapat dipisahkan berdasarkan kebutuhan.

SCIChat juga memiliki mekanisme untuk menjaga pemisahan konteks antarsesi dan menangani ketahanan aliran respons AI. Tujuannya adalah mengurangi risiko respons dari sesi sebelumnya memengaruhi sesi yang sedang aktif.

Jawaban AI tetap perlu diperiksa terhadap makalah aslinya, terutama untuk klaim ilmiah, angka eksperimen, persamaan, dan kesimpulan penelitian.

### 3. Penampil PDF dan Ekstraksi Teks

SCIChat menyediakan kemampuan membaca dokumen PDF makalah ilmiah langsung melalui aplikasi.

Integrasi penampil PDF berbasis Syncfusion membantu pengguna membuka dokumen tanpa harus selalu berpindah ke aplikasi lain. Selain membaca dokumen, SCIChat juga menyediakan ekstraksi teks untuk mendukung analisis dan pemanfaatan isi makalah dalam percakapan AI.

Kemampuan yang tersedia meliputi:

- Pembacaan dokumen PDF di dalam aplikasi.
- Ekstraksi teks dari dokumen untuk kebutuhan analisis.
- Pemanfaatan teks dokumen sebagai bagian dari konteks penelitian.
- Pembatasan ukuran unduhan PDF hingga 25 MiB pada layanan ekstraksi yang telah diterapkan.
- Validasi awal format dokumen dan penanganan berkas yang tidak valid.
- Penanganan kesalahan unduhan dan ekstraksi agar kegagalan dokumen tidak langsung menyebabkan aplikasi berhenti.

Pembatasan ukuran unduhan diterapkan untuk mengurangi risiko penggunaan memori yang berlebihan. Dokumen yang melebihi batas atau tidak dapat diproses mungkin tidak tersedia untuk ekstraksi.

### 4. Rendering Matematika dan Markdown Ilmiah

Makalah akademik sering memuat persamaan, tabel, daftar, notasi ilmiah, dan referensi yang memerlukan penyajian terstruktur.

SCIChat mendukung tampilan konten berbasis Markdown dan notasi matematika LaTeX agar jawaban AI lebih mudah dibaca dalam konteks akademik.

Kemampuan ini mencakup:

- Rendering persamaan matematika sebaris (*inline math*).
- Rendering persamaan matematika berbentuk blok (*block math*).
- Penyajian teks terstruktur melalui Markdown.
- Dukungan terhadap tabel dan daftar.
- Penyajian konten akademik yang memuat notasi, kutipan, dan referensi.

Kualitas tampilan tetap bergantung pada sintaksis sumber, format respons, serta kemampuan komponen rendering yang digunakan.

### 5. Fitur Pendukung Penalaran dan Eksplorasi Ilmiah

SCIChat menyediakan fitur yang membantu pengguna mengeksplorasi konsep, menyusun pertanyaan, dan memahami literatur dengan pendekatan yang lebih sesuai dengan kebutuhan penelitian.

#### Mode ELI5

Mode *Explain Like I'm 5* membantu menyederhanakan penjelasan konsep yang rumit menggunakan bahasa yang lebih mudah dipahami. Fitur ini berguna sebagai titik awal untuk memahami istilah teknis, teori, atau konsep baru sebelum mempelajarinya secara lebih mendalam.

Penyederhanaan tidak dimaksudkan untuk menggantikan definisi formal, pembuktian matematis, atau penjelasan asli dari peneliti.

#### Deep Search Intent

Fitur Deep Search Intent membantu mengidentifikasi kata kunci dan maksud pencarian agar eksplorasi literatur lebih terarah.

Tujuannya adalah membantu pengguna bergerak dari pertanyaan penelitian yang masih umum menuju pencarian yang lebih spesifik dan relevan.

#### Manajemen Sesi Percakapan

Pengguna dapat mengelola sesi percakapan berdasarkan topik atau kebutuhan penelitian. Pemisahan sesi membantu menjaga konteks pertanyaan dan makalah yang digunakan pada setiap percakapan.

#### Perpustakaan Favorit

Makalah yang dianggap penting dapat disimpan sebagai favorit agar lebih mudah ditemukan kembali ketika pengguna melanjutkan penelitian.

### 6. Pengelolaan Referensi dan Integritas Metadata

Kualitas penelitian tidak hanya bergantung pada jawaban yang dihasilkan, tetapi juga pada ketepatan sumber yang mendasarinya.

SCIChat memiliki mekanisme penanganan metadata referensi untuk membantu menjaga konsistensi informasi bibliografi dari berbagai sumber.

Area yang ditangani mencakup:

- Pengolahan metadata judul, penulis, tahun, dan DOI.
- Normalisasi identitas makalah tertentu, termasuk pengenal arXiv.
- Penanganan konflik metadata ketika informasi dari sumber berbeda tidak sepenuhnya konsisten.
- Penyaringan tautan sumber yang tidak sesuai dengan jenis konten yang diharapkan.
- Dukungan terhadap format referensi seperti APA dan BibTeX.
- Penanganan informasi bibliografi yang tidak lengkap agar tidak secara otomatis dianggap valid.

Metadata yang diperoleh dari layanan eksternal tetap dapat mengandung kesalahan atau kekurangan. Pengguna disarankan memeriksa DOI, judul, nama penulis, tahun terbit, dan informasi publikasi sebelum menggunakan referensi dalam karya akademik.

### 7. Antarmuka Editorial untuk Membaca Literatur

SCIChat menggunakan pendekatan desain editorial yang ditujukan untuk pengalaman membaca dokumen akademik dan percakapan yang panjang.

Sistem tipografi yang direncanakan atau digunakan dalam antarmuka mencakup:

- Playfair Display untuk karakter visual editorial.
- Source Serif 4 untuk pengalaman membaca teks panjang.
- JetBrains Mono untuk elemen yang membutuhkan tampilan monospasi, seperti kode atau notasi tertentu.

Aplikasi menyediakan tema terang dan tema gelap, termasuk pendekatan tema gelap bernama *Midnight Slate*.

Desain ini ditujukan untuk menjaga hierarki informasi, membedakan konten utama dari metadata, dan meningkatkan keterbacaan selama sesi penelitian.

## Sumber Literatur Ilmiah

SCIChat mengintegrasikan sumber berikut untuk pencarian atau pengambilan metadata literatur:

| Sumber | Peran umum |
|---|---|
| [arXiv](https://arxiv.org) | Repositori naskah ilmiah, terutama pada bidang sains, matematika, komputasi, dan bidang terkait. |
| [Semantic Scholar](https://www.semanticscholar.org) | Layanan pencarian literatur dan metadata penelitian ilmiah. |
| [Crossref](https://www.crossref.org) | Metadata publikasi akademik dan pengenal DOI. |
| [OpenAlex](https://openalex.org) | Katalog terbuka untuk karya ilmiah, penulis, institusi, dan hubungan antarpenelitian. |
| [Internet Archive](https://archive.org) | Sumber metadata dan dokumen digital yang tersedia melalui layanan arsip. |

Cakupan pencarian dan jenis data yang tersedia berbeda pada setiap penyedia. Kegagalan atau pembatasan akses pada salah satu sumber dapat memengaruhi hasil dari sumber tersebut, dan tidak semua sumber menyediakan PDF yang dapat diunduh.

## Teknologi dan Arsitektur

### Teknologi Utama

SCIChat dikembangkan menggunakan teknologi berikut:

- **Flutter dan Dart** untuk pengembangan aplikasi.
- **Syncfusion Flutter PDF** untuk pemrosesan atau penampilan dokumen PDF sesuai komponen yang digunakan.
- **SharedPreferences** untuk penyimpanan preferensi dan data lokal tertentu.
- **Layanan API literatur ilmiah** untuk pencarian dan pengambilan metadata.
- **Layanan AI yang kompatibel dengan API percakapan** untuk menghasilkan respons berdasarkan pertanyaan dan konteks penelitian.

Versi dependency aktual mengikuti konfigurasi proyek dan lockfile. Pembaruan paket sebaiknya dilakukan secara terencana serta diikuti pengujian regresi.

### Gambaran Arsitektur

Secara konseptual, alur kerja SCIChat terdiri dari beberapa bagian:

1. **Antarmuka pengguna** menerima pertanyaan, menampilkan hasil pencarian, mengelola sesi, dan menyajikan dokumen.
2. **Layanan pencarian** menghubungkan aplikasi dengan penyedia literatur dan mengolah hasil yang diterima.
3. **Pengolahan metadata** menormalkan informasi makalah dan membantu menjaga konsistensi referensi.
4. **Manajemen konteks** menghubungkan makalah yang dipilih dengan sesi percakapan yang relevan.
5. **Layanan AI** mengirimkan permintaan dan memproses respons untuk ditampilkan kepada pengguna.
6. **Layanan PDF** menangani pengambilan dan ekstraksi teks dokumen sesuai batasan yang diterapkan.
7. **Penyimpanan lokal** mempertahankan data aplikasi tertentu, seperti sesi, favorit, dan preferensi.

Gambaran ini menjelaskan pembagian tanggung jawab secara umum. Detail implementasi dan hubungan antarkomponen dapat dipelajari melalui kode sumber serta dokumentasi arsitektur proyek.

## Privasi dan Penyimpanan Data

SCIChat dirancang untuk menyimpan data aplikasi tertentu secara lokal di perangkat, termasuk riwayat percakapan, catatan, favorit, preferensi, dan konfigurasi API key sesuai implementasi masing-masing fitur.

Namun, penyimpanan lokal tidak berarti seluruh pemrosesan berlangsung secara luring.

Beberapa fungsi memerlukan koneksi jaringan, antara lain:

- Pencarian metadata dari layanan literatur eksternal.
- Pengunduhan PDF dari repositori atau penyedia dokumen.
- Pengiriman pertanyaan ke layanan AI eksternal.
- Pengambilan informasi tambahan dari penyedia yang terintegrasi.

Jika pengguna memasukkan API key untuk layanan eksternal, kredensial tersebut digunakan sesuai konfigurasi layanan terkait. Pengguna perlu memahami kebijakan privasi, ketentuan penggunaan, dan mekanisme penagihan dari penyedia API yang dipilih.

**Catatan keamanan:** SharedPreferences merupakan mekanisme penyimpanan key-value lokal, tetapi tidak dengan sendirinya menjamin enkripsi untuk setiap nilai yang disimpan. Karena itu, API key yang disimpan secara lokal harus diperlakukan sebagai informasi sensitif. Jangan membagikan ekspor konfigurasi, log, atau berkas aplikasi yang mungkin mengandung kredensial.

Pengguna juga sebaiknya tidak mengirimkan dokumen rahasia, data pribadi, atau materi penelitian yang dibatasi ke layanan eksternal tanpa memastikan bahwa penggunaannya sesuai dengan kebijakan institusi dan penyedia layanan.

## Persyaratan Sistem

Sebelum menjalankan SCIChat, siapkan lingkungan pengembangan berikut:

- Flutter SDK yang kompatibel dengan dependency proyek.
- Dart SDK yang disertakan dengan versi Flutter yang digunakan.
- Android Studio atau Visual Studio Code dengan ekstensi Flutter dan Dart.
- Android SDK yang sesuai untuk target build Android.
- Emulator Android atau perangkat fisik untuk pengujian aplikasi Android.
- Koneksi internet untuk fitur pencarian literatur, pengunduhan dokumen, dan layanan AI eksternal.

Rentang versi SDK yang benar-benar didukung sebaiknya mengacu pada konfigurasi proyek saat ini, termasuk `pubspec.yaml`, lockfile, serta konfigurasi build.

## Instalasi dan Menjalankan Aplikasi

### 1. Ambil Kode Sumber

Klon repositori SCIChat:

```bash
git clone https://github.com/merupakan4168-max/SCIChat.git
cd SCIChat
```

### 2. Pasang Dependency

Jalankan perintah berikut dari direktori proyek:

```bash
flutter pub get
```

Perintah ini mengunduh dan menyelesaikan dependency sesuai konfigurasi proyek.

### 3. Periksa Lingkungan Flutter

Pastikan Flutter dan Android SDK terdeteksi dengan benar:

```bash
flutter doctor
```

Selesaikan masalah konfigurasi yang dilaporkan sebelum menjalankan build Android.

### 4. Periksa Perangkat yang Tersedia

```bash
flutter devices
```

Pastikan emulator atau perangkat target muncul dalam daftar.

### 5. Jalankan Aplikasi

```bash
flutter run
```

Jika terdapat lebih dari satu perangkat, pilih perangkat yang sesuai melalui opsi perangkat Flutter.

### 6. Konfigurasi Layanan AI

Jika fitur percakapan AI memerlukan API key, masukkan kredensial melalui mekanisme konfigurasi yang tersedia di aplikasi. Pastikan menggunakan endpoint dan API key yang sesuai dengan penyedia layanan yang dipilih.

Jangan menaruh kredensial pribadi secara langsung ke dalam repositori publik.

## Pengujian

SCIChat menggunakan pengujian otomatis untuk memeriksa fungsi dan mencegah regresi pada perubahan kode.

Jalankan seluruh test suite dengan:

```bash
flutter test
```

Untuk memeriksa kualitas statis kode:

```bash
flutter analyze
```

Hasil analyzer perlu dibaca berdasarkan kategori error, warning, dan info. Exit code yang bukan nol harus diperiksa untuk memahami temuan yang dilaporkan, bukan langsung dianggap sebagai kegagalan kompilasi.

Untuk membangun APK debug Android:

```bash
flutter build apk --debug
```

Untuk menjalankan aplikasi pada perangkat Android, gunakan emulator atau perangkat fisik yang telah dikonfigurasi dengan benar.

Keberhasilan unit test dan build tidak menggantikan pengujian pada perangkat nyata. Interaksi sistem seperti berbagi berkas, akses jaringan, pembacaan dokumen, dan perilaku lifecycle perlu diuji sesuai target platform sebelum rilis.

## Dokumentasi Proyek

Dokumentasi tambahan tersedia atau direncanakan dalam berkas berikut:

- [Product Architecture v1.1](PRODUCT_ARCHITECTURE_v1.1.md) — gambaran arsitektur produk, komponen utama, dan alur kerja aplikasi.
- [Design System v2](DESIGN_SYSTEM_v2.md) — panduan sistem desain, tipografi, warna, komponen antarmuka, dan prinsip pengalaman pengguna.

Tautan tersebut mengasumsikan bahwa kedua berkas berada pada lokasi yang sesuai di repositori. Jika struktur direktori berubah, perbarui tautan agar tetap dapat diakses.

## Batasan dan Catatan Penggunaan

SCIChat merupakan alat bantu penelitian, bukan pengganti penilaian ilmiah atau proses verifikasi sumber.

Beberapa hal yang perlu diperhatikan:

- Hasil pencarian bergantung pada cakupan, ketersediaan, dan kebijakan akses sumber eksternal.
- Metadata dari layanan berbeda dapat tidak lengkap atau tidak konsisten.
- PDF tertentu mungkin tidak tersedia, tidak dapat diakses, atau tidak dapat diekstrak.
- Jawaban AI dapat mengandung kekeliruan, penyederhanaan berlebihan, atau interpretasi yang tidak sepenuhnya sesuai dengan makalah.
- Penanda sumber membantu penelusuran, tetapi klaim penting tetap perlu dibandingkan dengan isi sumber asli.
- Fitur berbasis layanan eksternal memerlukan jaringan dan tunduk pada ketersediaan layanan tersebut.
- Penggunaan API AI dapat mengikuti batas penggunaan, kebijakan, dan biaya dari penyedia masing-masing.

Untuk penggunaan akademik, verifikasi kutipan, DOI, data eksperimen, persamaan, dan kesimpulan terhadap publikasi aslinya sebelum memasukkannya ke dalam karya ilmiah.

## Pengembangan Selanjutnya

Area pengembangan yang dapat dipertimbangkan untuk meningkatkan SCIChat meliputi:

- Pengujian integrasi pada perangkat Android nyata.
- Peningkatan pemantauan dan penanganan kegagalan sumber pencarian eksternal.
- Perluasan cakupan pengujian untuk dokumen PDF dengan format dan ukuran yang beragam.
- Peningkatan konsistensi metadata dan validasi referensi lintas sumber.
- Evaluasi performa, ukuran aplikasi, dan penggunaan memori.
- Penguatan pengelolaan kredensial serta transparansi penggunaan layanan eksternal.
- Penyempurnaan dokumentasi instalasi, konfigurasi, pengujian, dan rilis.

Setiap pengembangan perlu melalui validasi dan pengujian regresi untuk memastikan bahwa peningkatan baru tidak merusak fitur yang telah tersedia.

## Lisensi

Informasi lisensi proyek perlu mengikuti berkas lisensi resmi yang tersedia di repositori. Jika lisensi belum ditentukan, jangan mengasumsikan bahwa kode sumber dapat digunakan, dimodifikasi, atau didistribusikan ulang tanpa batasan.

---

SCIChat dikembangkan untuk mendukung alur kerja penelitian yang lebih terstruktur melalui integrasi pencarian literatur, pembacaan dokumen, manajemen konteks, dan bantuan AI. Tujuan akhirnya adalah membantu pengguna mengeksplorasi literatur ilmiah secara lebih efisien dengan tetap mengutamakan pemeriksaan sumber, ketepatan referensi, dan tanggung jawab akademik.
