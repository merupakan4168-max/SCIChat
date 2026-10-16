SCIChat Design System v2
Status: Arah visual dan interaksi untuk fase redesign.
Dokumen ini menerjemahkan Product Architecture v1.1 menjadi prinsip UI/UX yang dapat diterapkan secara konsisten di SCIChat.
Sumber kebenaran: Product Architecture v1.1 menentukan apa yang harus dilakukan produk. Dokumen ini menentukan bagaimana pengalaman tersebut harus terasa dan terlihat.

1. Karakter Desain
SCIChat harus terasa:
Editorial · Academic · Focused · Intelligent · Restrained
SCIChat bukan:

- generic AI chatbot;
- dashboard aplikasi;
- futuristic AI interface;
- social media feed;
- kumpulan kartu fitur;
- UI yang penuh dekorasi.
Research first. Interface second. Decoration last.

Visual harus membantu pengguna memahami di mana mereka berada, apa yang sedang dikerjakan, sumber yang digunakan, dan tindakan paling relevan berikutnya.
2. Prinsip Hierarki Visual
Setiap layar harus memiliki hierarchy yang jelas.
Primary information
        ↓
Supporting information
        ↓
Metadata
        ↓
Secondary actions
Aturan:

- Satu primary action per konteks.
- Secondary action tidak boleh bersaing dengan primary action.
- Metadata lebih tenang daripada konten utama.
- Decorative element tidak boleh lebih dominan daripada informasi.
- Whitespace digunakan untuk memisahkan hierarchy.

3. Research Workspace
Research adalah workspace utama SCIChat.
┌─────────────────────────────────┐
│ Research                        │
│                                 │
│ Context / Session               │
│                                 │
│ Conversation / Results          │
│                                 │
│ Paper Results                   │
│                                 │
│ Research Composer               │
└─────────────────────────────────┘

Research | Explore | Library | Settings
Research Workspace harus terasa seperti tempat melakukan pekerjaan riset, bukan sekadar halaman chat.
Research Composer
Input utama menggunakan pendekatan chat-first.
Composer menangani:

- pertanyaan riset;
- pencarian paper;
- follow-up question;
- analisis;
- research skills;
- paper context.
Tidak perlu search bar terpisah jika tidak ada kebutuhan produk yang jelas.

4. Navigation System
Primary navigation menggunakan:
Research | Explore | Library | Settings
Bottom navigation bersifat persistent pada level aplikasi.
Session History
Session History bukan primary navigation.
Session History dapat menggunakan secondary surface seperti drawer khusus history atau panel/sheet dari Research.
Tujuannya memberi akses ke penelitian sebelumnya tanpa membuat history menjadi tab utama.
2. Research Composer
Research Composer adalah komponen utama SCIChat.
Karakter:

- floating tetapi tidak terlalu “pill-like”;
- cukup besar untuk pertanyaan panjang;
- terasa seperti alat kerja, bukan chat bubble;
- mendukung attachment/context;
- memiliki primary send action yang jelas.
Placeholder:
Tanya tentang paper, cari topik, atau mulai pertanyaan riset…

Hindari placeholder generik seperti “Ask anything…”.
Composer States

1. Idle
2. Focused
3. With Active Paper Context
4. Sending
5. Disabled / Processing
6. Error recovery
7. Active Paper Context
Active Paper Context harus selalu dapat dipahami pengguna.
┌──────────────────────────────────┐
│ PAPER CONTEXT                    │
│ 📄 Judul paper yang aktif     ×  │
└──────────────────────────────────┘
Prinsip:

- Context tidak boleh aktif diam-diam.
- Context tidak boleh menghilang setelah satu jawaban.
- User dapat melihat paper yang sedang digunakan.
- User dapat mengganti atau menghapus context.
- Hanya satu paper untuk versi saat ini.
Context indicator harus terlihat, tenang, tidak mendominasi composer, dan cukup berbeda dari message biasa.

7. Paper Card
Paper Card harus menjawab:
1. Paper apa ini?
1. Mengapa mungkin relevan?
1. Apa yang dapat dilakukan selanjutnya?
Hierarchy:
TITLE
Authors · Year · Source

Short relevance / abstract excerpt

Primary action
Secondary actions
Aturan:

- Hindari button soup.
- Jangan membuat semua action menjadi button besar.
- Metadata lebih kecil dan tenang.
- Judul paper menjadi visual anchor.
- Primary action harus jelas.
Paper Card dapat muncul di Research Results, Explore, dan Library dengan hierarchy yang tetap konsisten.

8. Paper Detail
Paper Detail adalah contextual research destination, bukan sekadar halaman metadata.
Hierarchy:
Paper identity
      ↓
Abstract / understanding
      ↓
AI actions
      ↓
PDF / source
      ↓
Citation / save
Primary AI Actions
Rangkum dengan AI
Tanya Paper
Keduanya harus mudah ditemukan dan tidak disembunyikan di overflow menu jika relevan untuk memahami paper.
Secondary actions:

- Save/Favorite
- Open PDF/source
- Translation
- Copy citation
Secondary actions tidak boleh mengalahkan dua AI actions tersebut.

9. Explore
Explore adalah discovery space.
Explore
   ↓
Topic / Category
   ↓
Paper Discovery
   ↓
Paper Detail
   ↓
Normal Research Workflow
Explore bukan dashboard berisi banyak feature cards.
Paper yang ditemukan harus dapat masuk ke workflow Research normal.
2. Library
Library adalah tempat menyimpan material riset.
Untuk versi saat ini:

- saved papers;
- Paper Detail;
- citation actions.
Visual:
- fokus pada daftar paper;
- minimalkan dekorasi;
- prioritaskan scanning;
- gunakan metadata ringkas.
Jangan membuat folder/tag UI kompleks sebelum fitur tersebut benar-benar menjadi bagian produk.
 1. Typography
Typography tetap menjadi identitas utama SCIChat.
Display
Playfair Display
Untuk hero, section heading besar, empty state, dan editorial emphasis.
Reading / Body
Source Serif 4
Untuk paper summaries, long-form content, AI answers, dan reading-oriented content.
Metadata / Technical
JetBrains Mono
Terbatas untuk technical metadata, identifiers, dates, dan compact data.
UI Labels
Sans-serif dapat digunakan bila diperlukan untuk button labels, navigation labels, dan compact controls.
 2. Color System
Pertahankan arah visual v1.
Surfaces

- surface0 — #050505
- surface1 — #111111
- surface2 — #1C1C1E
- surface3 — #2C2C2E
Accent
- accent — #7E84FA
- accentDim — #5A61D9
Text
- textPrimary — #F0F0F0
- textSecondary — #A0A0A5
- textMuted — #707075
Color digunakan untuk hierarchy dan state, bukan dekorasi.
 1. Surfaces, Cards & Containers
Gunakan container secara selektif.
Hindari:

- semua elemen menjadi card;
- card di dalam card;
- shadow berlebihan;
- border pada semua elemen;
- radius yang sama untuk semua komponen.
Paper Cards
- flat;
- subtle border;
- low elevation;
- generous internal spacing.
Gunakan radius berdasarkan fungsi. Jangan menjadikan satu radius sebagai default universal.
 1. Buttons & Actions
Primary Action
Tindakan paling penting pada konteks tersebut.
Secondary Action
Tindakan pendukung.
Tertiary Action
Tindakan yang tidak perlu mengambil perhatian.
Jangan membuat setiap action terlihat seperti primary button.

Interaction state harus jelas tanpa bergantung pada ripple Material default.
15. AI States
AI state harus informatif.
Siap
↓
Mencari paper…
↓
Membaca sumber…
↓
Menganalisis…
↓
Jawaban
Gunakan status yang menjelaskan pekerjaan sebenarnya jika informasi tersedia.
Hindari spinner tanpa konteks, animasi AI dekoratif, fake progress, atau status yang tidak sesuai proses.
16. Error & Recovery
Error UI harus menjelaskan:

1. Apa yang gagal.
2. Apa kemungkinan penyebabnya.
3. Apa yang dapat dilakukan user.
Contoh:
Pencarian gagal

Sumber akademik tidak dapat diakses saat ini.

[ Coba lagi ]
Jangan menjadikan raw exception sebagai pesan utama user.
17. Empty States
Empty state harus membantu user memulai pekerjaan.
Riset bermula dari sebuah pertanyaan.

Supporting text:
Cari paper, tanyakan topik, atau mulai dari pertanyaan penelitianmu.

CTA harus relevan dengan konteks. Empty state bukan tempat memamerkan banyak fitur.
18. Motion
Motion harus menjelaskan perubahan.
Gunakan fade, subtle slide, scale ringan, dan state transition.
Durasi umum: 150–300ms
Kurva:

- easeOutCubic
- easeOutExpo
Motion harus membantu orientation, feedback, continuity, atau hierarchy.
Jangan menganimasikan elemen hanya karena bisa.
 1. Haptics
Haptic feedback digunakan secara selektif untuk interaksi penting seperti:

- send;
- save/favorite;
- perubahan context;
- action utama tertentu.
Jangan memberikan haptic pada setiap tap.
 1. Accessibility
Minimum:

- target interaksi sekitar 44×44;
- contrast cukup;
- teks utama mudah dibaca;
- hierarchy tidak hanya bergantung pada warna;
- status AI tidak hanya disampaikan melalui animasi.
Reading width harus nyaman untuk konten panjang.
 1. Responsive & Reading Layout
Paper dan AI content membutuhkan reading width yang nyaman.
Pada layar lebar:

- jangan biarkan teks memenuhi seluruh viewport;
- gunakan max reading width;
- manfaatkan whitespace.
Pada layar kecil:
- prioritaskan content;
- kurangi secondary metadata;
- pertahankan primary actions.
 1. Anti-AI-Slop Rules
Hindari:

- excessive gradients;
- neon glow;
- decorative AI sparkle;
- excessive glassmorphism;
- dashboard feature grids;
- terlalu banyak pills;
- terlalu banyak rounded cards;
- excessive shadows;
- random decorative shapes;
- meaningless animation;
- button soup;
- label “AI” di mana-mana tanpa fungsi.
Anti-slop bukan berarti desain harus kasar.
Target:
Clean + intentional + functional + restrained.
 1. Visual Decision Test
Sebelum menambahkan elemen UI, tanyakan:
Apakah ini membantu hierarchy?
Jika tidak, pertanyakan kembali.
Apakah ini membantu research workflow?
Jika tidak, kemungkinan tidak diperlukan.
Apakah elemen ini masih berguna jika efek dekoratifnya dihilangkan?
Jika iya, hierarchy/layout kemungkinan sudah cukup kuat.
Apakah user tahu apa yang harus dilakukan berikutnya?
Jika tidak, perbaiki hierarchy sebelum menambah dekorasi.
 2. Component Consistency
Komponen harus konsisten dalam:

- hierarchy;
- typography;
- spacing;
- interaction;
- state;
- semantics.
Namun konsistensi tidak berarti semua komponen harus identik. Perbedaan visual boleh digunakan untuk menunjukkan perbedaan fungsi.

25. Implementation Guidance
Redesign tidak dilakukan sebagai rewrite seluruh aplikasi.
Urutan implementasi:
1. Navigation Shell
        ↓
1. Research Workspace
        ↓
1. Research Composer
        ↓
1. Paper Card / Results
        ↓
1. Paper Detail
        ↓
1. Active Paper Context
        ↓
1. Explore
        ↓
1. Library
        ↓
1. Error / Loading / Empty States
        ↓
1. Motion & Polish
Setiap tahap harus mempertahankan fitur riset yang sudah bekerja.
Jangan mengubah backend hanya untuk mencapai perubahan visual jika tidak diperlukan.
1. Anti-Overdesign Rule
Jika terdapat pilihan antara:
lebih banyak efek
vs
hierarchy lebih jelas
→ pilih hierarchy.
Jika terdapat pilihan antara:
lebih banyak komponen
vs
alur lebih sederhana
→ pilih alur lebih sederhana.
Jika terdapat pilihan antara:
lebih banyak fitur di layar
vs
fokus pada pekerjaan user
→ pilih fokus.
Jika desain terlihat “AI-generated” karena terlalu banyak efek atau pola generik:
→ sederhanakan.
1. Definition of Good UI
UI SCIChat dianggap berhasil jika user dapat dengan cepat memahami:
1. Saya sedang berada di mana?
1. Saya sedang mengerjakan riset apa?
1. Paper apa yang sedang saya lihat?
1. Apakah AI sedang menggunakan paper tertentu sebagai context?
1. Apa yang bisa saya lakukan selanjutnya?
1. Bagaimana saya kembali ke material riset sebelumnya?
Jika jawaban terhadap pertanyaan tersebut tidak jelas, masalahnya kemungkinan berada pada hierarchy atau navigation, bukan kurangnya dekorasi.
1. Final Design Principle
SCIChat harus terasa seperti alat riset yang sengaja dirancang, bukan chatbot yang dihias menjadi aplikasi riset.

Research first.
Hierarchy first.
Function first.
Decoration last.
