# 🔬 SCIChat — AI Research Assistant for Scientific Papers

**SCIChat** adalah aplikasi asisten riset ilmiah cerdas berbasis Flutter yang dirancang untuk membantu akademisi, peneliti, dan mahasiswa dalam mencari, menganalisis, dan mendiskusikan makalah akademik secara interaktif dengan kecerdasan buatan.

---

## ✨ Fitur Utama (Terverifikasi dalam Implementasi)

1. **🔍 Pencarian Makalah Akademik Multi-Sumber:**
   - Pencarian literatur terintegrasi melintasi **arXiv**, **Semantic Scholar**, **CrossRef**, **OpenAlex**, dan **Internet Archive**.
   - Dilengkapi filter kategori, pengaturan bidang pencarian (judul, abstrak, penulis), penyortiran tanggal/relevansi, serta deteksi trending papers.

2. **💬 Multi-Paper Context Chat:**
   - Menyematkan satu atau beberapa makalah sekaligus ke dalam sesi obrolan sebagai konteks acuan AI.
   - Sintesis jawaban berbasis bukti (*evidence-based synthesis*) dengan penanda sumber interaktif (*source pills*) dan saran pertanyaan lanjutan (*follow-up suggestions*).

3. **📄 Penampil PDF Terintegrasi (In-App PDF Viewer):**
   - Membaca dokumen PDF makalah ilmiah langsung di dalam aplikasi menggunakan mesin penampil PDF Syncfusion.
   - Ekstraksi teks untuk ringkasan cepat dan analisis dokumen.

4. **📐 Dukungan Rumus Matematika (LaTeX) & Markdown Ilmiah:**
   - Rendering rumus matematika (LaTeX / TeX syntax) secara presisi, baik format sebaris (*inline*) maupun blok (*block math*).
   - Dukungan penuh untuk format tabel, daftar pustaka, dan sintaksis Markdown akademik.

5. **💡 Fitur Bantu Penalaran Ilmiah:**
   - **Mode ELI5 (*Explain Like I'm 5*):** Menyederhanakan penjelasan konsep atau teorema yang rumit menjadi analogi yang mudah dipahami.
   - **Deep Search Intent:** Ekstraksi otomatis kata kunci dan intensi pencarian berbasis AI untuk hasil literatur yang lebih relevan.
   - **Manajemen Sesi & Favorit:** Mengelola riwayat percakapan riset dan menyimpan perpustakaan makalah favorit.

6. **🔒 Privasi & Penyimpanan Lokal:**
   - API Key, riwayat obrolan, catatan, dan preferensi pengguna disimpan sepenuhnya secara lokal di perangkat melalui penyimpanan aman (*SharedPreferences*).

7. **🎨 Desain Editorial & Tipografi Akademik:**
   - Antarmuka bertema editorial akademik dengan tipografi terkurasi (*Playfair Display*, *Source Serif 4*, dan *JetBrains Mono*).
   - Dukungan tema Gelap (*Midnight Slate*) dan Terang yang nyaman untuk membaca dokumen panjang.

---

## 🚀 Memulai Proyek

### Prasyarat
- [Flutter SDK](https://flutter.dev) (versi `>= 3.0.0 < 4.0.0`)
- Android Studio / VS Code dengan ekstensi Flutter & Dart
- Perangkat Android fisik atau Emulator

### Menjalankan Aplikasi
```bash
# 1. Unduh dependensi
flutter pub get

# 2. Jalankan aplikasi pada perangkat yang terhubung
flutter run
```

---

## 📚 Dokumentasi Arsitektur & Desain

Untuk mempelajari spesifikasi arsitektur produk dan panduan UI/UX secara mendalam, rujuk dokumen berikut:
- [Product Architecture v1.1](PRODUCT_ARCHITECTURE_v1.1.md)
- [Design System v2](DESIGN_SYSTEM_v2.md)
