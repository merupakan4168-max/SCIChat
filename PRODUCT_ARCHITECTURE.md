1. Research-Centric Mental Model
   SCIChat harus dipahami sebagai:
   Research Workspace
bukan:
AI Chatbot dengan fitur penelitian.
Struktur konseptualnya:
                       SCIChat
                          │
                 RESEARCH WORKSPACE
                          │
        ┌─────────────────┼─────────────────┐
        ↓                 ↓                 ↓
     MENCARI           MEMAHAMI        MENGANALISIS
        │                 │                 │
        └─────────────────┼─────────────────┘
                          ↓
                      MENYIMPAN
                          │
                          ↓
                     MENGGUNAKAN
Chat berada di dalam seluruh workflow tersebut.
Chat bukan tujuan akhir produk.
2. Peran Chat
Chat merupakan interaction layer utama SCIChat.
Chat digunakan untuk:

- memulai research
- menyempurnakan pertanyaan
- mencari paper
- bertanya tentang paper
- melakukan analisis
- meminta penjelasan
- melanjutkan konteks penelitian
  Namun chat tidak boleh membuat seluruh pengalaman terasa seperti chatbot biasa.
  Contoh workflow:
  Pertanyaan penelitian
    ↓
Chat memahami intent
        ↓
Pencarian paper
        ↓
Paper results
        ↓
Paper Detail
        ↓
Ask Paper
        ↓
Analisis
        ↓
Simpan / Cite / Export
Pengguna harus merasa sedang melanjutkan satu pekerjaan penelitian,
bukan berpindah-pindah antar fitur yang tidak berhubungan.

5. Lima Tahap Utama Research Workflow
5.1 MENCARI
Tujuan:
Membantu pengguna menemukan literatur yang relevan.
Fitur yang saat ini mendukung tahap ini:

- conversational search
- search intent extraction
- multi-source academic search
- deduplication
- trending papers
- Explore
- publication trends
  Sumber pencarian saat ini mencakup:
- arXiv
- Internet Archive
- OpenAlex
- CrossRef
  Prinsip:
  Search harus terasa seperti bagian dari research conversation,
  bukan sekadar mesin pencari terpisah.
5.2 MEMAHAMI
Tujuan:
Membantu pengguna memahami paper tanpa harus langsung membaca seluruh
dokumen dari awal sampai akhir.
Fitur yang saat ini mendukung tahap ini:
- Paper Detail
- abstract
- translated abstract
- AI summary
- figures
- PDF viewer
- Ask Paper
- PDF context
- ELI5
- LaTeX-aware responses
  Prinsip:
  Setelah menemukan paper, pengguna harus dapat memahami nilai dan isi
  paper tersebut tanpa kehilangan konteks penelitian sebelumnya.
5.3 MENGANALISIS
Tujuan:
Membantu pengguna bergerak dari memahami satu paper menuju memahami
pola dan hubungan dalam literatur.
Fitur yang saat ini mendukung tahap ini:
- Review
- Gap
- Table
- Deep Search
- publication trend visualization
- grounded AI analysis
  Fitur-fitur tersebut harus diposisikan sebagai research actions,
  bukan sebagai produk atau halaman terpisah.
  Jangan membuat UI yang hanya memamerkan daftar:
- Review
- Gap
  Table
  Deep Search
  ELI5
  ...
Sebaliknya, tampilkan kemampuan yang relevan berdasarkan konteks dan
tujuan pengguna.
5.4 MENYIMPAN
Tujuan:
Membantu pengguna mempertahankan paper dan konteks penelitian yang
masih berguna untuk digunakan kembali.
Fitur saat ini:
- Library
- Favorites
- conversation history
  Untuk versi saat ini, sistem penyimpanan tidak perlu dibuat terlalu kompleks.
  Fitur seperti:
- folders
- collections
- projects
- saved searches
  merupakan kemungkinan pengembangan berikutnya, bukan requirement saat ini.
  5.5 MENGGUNAKAN
  Tujuan:
  Membantu pengguna membawa hasil penelitian keluar dari SCIChat dan
  menggunakannya dalam pekerjaan nyata.
Fitur saat ini:
- BibTeX
- APA 7
- Markdown export
- conversation export/share
  Kemungkinan masa depan:
- structured literature review output
- research notes
- citation manager integration
- writing assistance
  Fitur masa depan tidak boleh dianggap sebagai bagian dari scope
  implementasi saat ini.

6. Feature Hierarchy
   Tier 1 — Core
   Fitur yang mendefinisikan pengalaman utama SCIChat:
   - research conversation
   - paper search
   - search results
   - Paper Detail
   - Ask Paper
   - PDF reading
   - conversation history
     Tier 2 — Supporting
     Fitur yang memperkuat workflow:
   - ELI5
   - Deep Search
   - Review
   - Gap
   - Table
   - publication trends
   - Favorites
   - Library
   - citation tools
   - export
     Tier 3 — Future
     Kemungkinan pengembangan:
   - literature review workspace
   - collections
   - paper comparison
   - citation network
   - annotation
   - research notes
   - structured evidence extraction
   - writing assistance
   - external reference manager integrations
     Tier 3 bukan scope implementasi saat ini.
2. Information Architecture
   Struktur konseptual SCIChat:
   SCIChat
   │
   ├── Research
   │   ├── New Research
   │   └── Research History
   │
   ├── Explore
   │   ├── Topics
   │   └── Trending Papers
   │
   ├── Library
   │   └── Saved / Favorite Papers
   │
   └── Settings
Research merupakan pusat pengalaman.
Paper Detail dan PDF merupakan contextual destinations yang biasanya
diakses dari Research atau Library.
3. Navigation Principles
Navigation harus membantu pengguna memahami:
"Saya sedang berada di mana dalam pekerjaan penelitian saya?"
Bukan:
"Berapa banyak fitur yang dimiliki aplikasi ini?"
Prioritas konseptual:
4. Research
5. Explore
6. Library
7. Settings
   Jangan menjadikan setiap AI capability sebagai top-level navigation.
   Contohnya:
   JANGAN:
   Chat
   - Review
   - Gap
     Table
     ELI5
     Deep Search
   - PDF
     Library
     Explore
     ...
Lebih baik:
Research
Explore
Library
Settings
Kemampuan seperti Review, Gap, Table, dan ELI5 muncul secara kontekstual
dari research workflow.
8. Screen Responsibilities
Research / Chat
Tujuan:
Menjalankan dan melanjutkan pekerjaan penelitian.
Mencakup:

- research conversation
- AI responses
- search results
- paper cards
- research actions
- composer
- research context
  Paper Detail
  Tujuan:
  Membantu pengguna mengevaluasi dan memahami sebuah paper.
Informasi utama:
- title
- authors
- publication information
- source
- abstract
- translation
- figures
- AI summary
- citation
- PDF access
- Ask Paper
  Primary action:
  Memahami / bertanya tentang paper.
PDF Viewer
Tujuan:
Memberikan pengalaman membaca dokumen yang fokus.
PDF adalah supporting surface, bukan pusat seluruh produk.
Explore
Tujuan:
Membantu pengguna menemukan penelitian ketika mereka belum memiliki
pertanyaan yang spesifik.
Explore harus benar-benar interaktif.
Elemen yang terlihat sebagai actionable content tidak boleh menjadi
placeholder yang tidak dapat digunakan.
Library
Tujuan:
Memberikan akses kembali ke penelitian yang sengaja disimpan pengguna.
Untuk versi saat ini, Library boleh tetap sederhana.
Settings
Tujuan:
Mengatur preferensi aplikasi dan AI.
Settings harus tetap menjadi bagian sekunder dari pengalaman research.
 1. Paper Interaction Model
Paper dapat bergerak melalui lifecycle:
DISCOVERED
    ↓
OPENED
    ↓
UNDERSTOOD
    ↓
QUESTIONED
    ↓
SAVED
    ↓
CITED / USED
UI harus mendukung perpindahan antar state tersebut secara natural.
Contoh:
Search Result
     ↓
Paper Detail
     ↓
Ask Paper / PDF
     ↓
Save
     ↓
Citation
Pengguna tidak seharusnya dipaksa kembali ke awal workflow setelah setiap
aksi.
 2. Paper Card Principles
Paper Card merupakan komponen penting karena menjadi jembatan antara
discovery dan understanding.
Paper Card harus memiliki:

- hierarchy informasi yang jelas
- metadata penting
- relevance/context yang cukup
- satu primary action yang jelas
- secondary actions yang tidak mendominasi
  Hindari "button soup".
  Jangan membuat semua aksi memiliki visual prominence yang sama.

1. Ask Paper
   Ask Paper merupakan kemampuan penting dalam research workflow.
   Ketika sebuah paper atau PDF menjadi active context, pengguna harus dapat
   memahami dengan jelas:
   "Pertanyaan saya berikutnya akan dijawab menggunakan konteks paper ini."
Aktivasi context tidak boleh silent.
UI harus memberikan feedback ketika:

- paper menjadi active context
- PDF ditambahkan sebagai context
- context dilepas

1. AI Interaction Model
   AI harus memberikan feedback yang mencerminkan pekerjaan sebenarnya.
   Contoh progression:
   Memahami pertanyaan
   ↓
Mencari literatur
        ↓
Menemukan paper
        ↓
Menganalisis hasil
        ↓
Menyusun jawaban
        ↓
Jawaban
Status harus bermakna.
Hindari:

- loading tanpa konteks
- fake progress
- animasi panjang hanya untuk menyembunyikan latency
  Jika memungkinkan secara teknis, streaming response harus menjadi arah
  pengembangan untuk meningkatkan perceived responsiveness.

1. Research Context
   Context adalah bagian penting dari research-centric experience.
   Pengguna harus dapat mengetahui apakah AI sedang menggunakan:
   - percakapan
   - paper tertentu
   - PDF
   - hasil pencarian
   - konteks lain
     Context harus terlihat ketika relevan.
     Prinsip:
     User should understand what the AI knows and what it is currently
     using.
2. Empty States
   Empty state harus membantu pengguna memulai penelitian.
   Konsep yang sudah ada:
   "Riset bermula dari sebuah pertanyaan."
Konsep ini dapat dipertahankan sebagai identitas produk.
Suggestion questions harus:

- relevan
- berubah secara berkala
- dapat langsung digunakan
- tidak terasa seperti generic AI prompt
  Suggestion adalah invitation untuk memulai research, bukan dekorasi.

1. Loading & Waiting
   Bedakan:
   Actual progress
   Contoh:
   - searching sources
   - extracting PDF
   - processing document
   - analyzing results
     dengan:
     Visual feedback
     Contoh:
   - shimmer
   - fade
   - typing cursor
   - subtle entrance animation
     Visual feedback tidak boleh berpura-pura bahwa proses tertentu sedang
     terjadi jika sebenarnya tidak terjadi.
2. Error Handling
Error harus menjelaskan:
3. apa yang gagal
4. apakah pekerjaan pengguna aman
5. apa yang dapat dilakukan selanjutnya
   Hindari pesan generik seperti:
   "Something went wrong."
Contoh:
Search gagal:
jelaskan bahwa pencarian gagal dan berikan retry.
PDF gagal:
jelaskan bahwa dokumen tidak tersedia dan berikan alternatif jika ada.
AI request gagal:
pertahankan conversation dan berikan opsi retry.
6. Literature Review Direction
SCIChat memiliki potensi untuk berkembang menjadi literature-review
workspace yang lebih lengkap.
Namun versi saat ini tidak boleh berpura-pura sebagai sistem literature
review end-to-end.
Literature review yang benar-benar lengkap kemungkinan membutuhkan:

- search strategy
- screening
- inclusion/exclusion
- evidence extraction
- paper comparison
- synthesis
- citation organization
- structured review output
  Untuk saat ini fokus utama tetap:
  Mencari
   ↓
  Memahami
   ↓
  Menganalisis
   ↓
  Menyimpan
   ↓
  Menggunakan
Arah literature review akan dievaluasi setelah workflow inti sudah matang.
 1. Product Principles
19.1 Research over Chat
SCIChat bukan chatbot dengan fitur akademik.
SCIChat adalah research workspace dengan conversational AI sebagai
interaction layer utama.
19.2 Conversation as Continuity
Conversation menjaga kesinambungan research workflow.
19.3 Evidence Close
AI harus tetap dekat dengan evidence yang mendukung jawabannya.
19.4 Progressive Disclosure
Jangan menampilkan seluruh kemampuan AI sekaligus.
Tampilkan capability ketika relevan dengan pekerjaan pengguna.
19.5 User Control
Pengguna harus memahami:

- context yang digunakan
- aksi yang dilakukan
- hasil yang diberikan
  19.6 Calm Intelligence
  SCIChat harus terasa pintar tanpa terasa berisik.
  Hindari:
- terlalu banyak animation
- terlalu banyak badge
- terlalu banyak notification
- terlalu banyak visual emphasis
  19.7 Research Continuity
  Perpindahan antara:
- chat
- search
- paper
- PDF
- analysis
- library
  harus terasa seperti melanjutkan satu research task.
  19.8 Don't Overbuild
  Jangan menambahkan fitur hanya karena fitur tersebut populer di aplikasi AI
  lain.
  Setiap fitur harus mendukung research job yang nyata.
 1. Anti-AI-Slop Product Direction
SCIChat tidak boleh berubah menjadi:

- generic chatbot clone
- dashboard AI
- kumpulan gradient cards
- kumpulan fitur AI dalam bentuk tombol
- glassmorphism template
- generic SaaS template
- "3 cards + 3 buttons" layout
  Hindari:
- excessive gradients
- excessive pills
- excessive rounded containers
- excessive shadows
- decorative AI sparkle icons
- meaningless animation
- redundant actions
  Prioritaskan:
- typography
- hierarchy
- whitespace
- editorial composition
- contextual controls
- meaningful interaction
- restrained motion
  Prinsip utama:
  Jangan mendesain berdasarkan apa yang biasanya dibuat AI.
  Desain berdasarkan apa yang paling masuk akal untuk pekerjaan penelitian
  pengguna SCIChat.

21. Current Product Priority
Prioritas saat ini bukan menambah banyak fitur.
Prioritasnya adalah membuat kemampuan yang sudah ada terasa seperti satu
produk yang koheren.
Urutan prioritas:
1. navigation clarity
1. research/chat experience
1. paper result hierarchy
1. Paper Detail experience
1. Ask Paper context feedback
1. AI waiting experience
1. Explore interaction
1. Library experience
1. cross-screen consistency
1. motion and interaction polish
1. Current vs Future
Current
Fokus pada kemampuan yang sudah tersedia:

- conversational research
- paper search
- multi-source search
- Paper Detail
- PDF
- Ask Paper
- research skills
- trends
- Library
- Favorites
- citation
- export
  Future
  Potensi pengembangan:
- collections
- literature review workspace
- paper comparison
- citation network
- annotation
- structured evidence extraction
- research projects
- writing assistance
- reference manager integration
  Future features tidak boleh masuk implementasi hanya berdasarkan asumsi.

23. Implementation Rules
Sebelum mengubah UI/UX secara signifikan:
1. Baca PRODUCT_ARCHITECTURE.md.
1. Baca DESIGN_SYSTEM.md.
1. Periksa implementasi yang sudah ada.
1. Pertahankan pola yang sudah bekerja dengan baik.
1. Jangan melakukan refactor yang tidak berhubungan.
1. Jangan menambahkan product capability tanpa keputusan product.
1. Jangan mengubah navigation tanpa mempertimbangkan research workflow.
1. Jangan mengubah visual hanya demi terlihat "lebih modern".
1. Pastikan perubahan mendukung workflow penelitian.
1. Jika terdapat konflik antara implementasi dan dokumen ini, identifikasi
     konflik tersebut terlebih dahulu.
1. Open Product Decisions
Beberapa keputusan sengaja belum dikunci:

- bottom navigation vs drawer vs hybrid
- hubungan Research dengan research sessions
- evolusi Library menjadi Collections
- kedalaman literature-review workflow
- research project/workspace
- paper comparison
- citation/reference management
- external reference manager integration
  Keputusan tersebut harus dibuat berdasarkan kebutuhan pengguna dan workflow,
  bukan mengikuti pola aplikasi AI lain.
 1. Definition of Success
SCIChat berhasil jika pengguna dapat:

- datang dengan pertanyaan penelitian
- menemukan paper yang relevan
- memahami paper dengan lebih cepat
- bertanya menggunakan konteks evidence yang tepat
- menganalisis literatur
- menyimpan penelitian yang berguna
- menggunakan hasilnya melalui citation atau export
  dengan perpindahan yang terasa natural antara setiap tahap.
  Tujuan akhirnya:
  SCIChat harus terasa seperti satu continuous research workflow,
  bukan kumpulan fitur AI yang kebetulan berada dalam satu aplikasi.
