Arsitektur Produk SCIChat v1.1
Status: Arah produk dikunci untuk fase redesign saat ini.
Dokumen ini mendefinisikan apa itu SCIChat, bagaimana alur kerja riset harus berjalan, serta keputusan produk mana yang masuk dan tidak masuk dalam scope saat ini.
Dokumen ini menjadi sumber acuan utama di level produk sebelum redesign UI dan implementasi.

1. Identitas Produk
SCIChat is a research-centric AI assistant.
SCIChat bukan terutama chatbot AI generik yang hanya diberi fitur akademik.
Produk harus help users move through a continuous research workflow:
Mencari → Memahami → Menganalisis → Menyimpan → Menggunakan
Interface harus therefore be designed around research work, not around the existence of a chat box.
2. Janji Utama Produk
SCIChat helps users move from:
pertanyaan riset → bukti yang relevan → pemahaman → analisis → riset tersimpan → hasil yang dapat digunakan
Produk harus reduce the friction between finding a paper and actually using its information.
3. Mental Model Berbasis Riset
SCIChat
   ↓
RESEARCH WORKSPACE
   ↓
Mencari → Memahami → Menganalisis → Menyimpan → Menggunakan
Chat is the primary interaction layer inside this workspace.
Chat is not a separate product destination whose purpose is simply to have conversations.
4. Peran Chat
Chat is used to:

- express research questions naturally;
- refine search intent;
- search academic literature;
- ask questions about papers;
- request summaries and explanations;
- run research skills such as review/gap/table;
- continue analysis after discovering evidence.
The existence of chat should never force users to leave the research context unnecessarily.

1. Tahapan Utama Riset
5.1 Mencari
Tujuan: discover relevant academic literature.
Kemampuan saat ini meliputi:

- natural-language search intent extraction;
- multi-source academic search;
- result deduplication;
- paper discovery;
- Explore/trending discovery.
5.2 Memahami
Tujuan: understand a paper or source.
Kemampuan meliputi:
- abstract and metadata;
- PDF reading;
- translation;
- AI summary;
- asking questions about a paper.
5.3 Menganalisis
Tujuan: derive insights across or within research material.
Kemampuan meliputi:
- /review;
- /gap;
- /table;
- deep search;
- trend visualization;
- AI-assisted analysis.
Multi-document analysis is a future direction, not a current requirement.
5.4 Menyimpan
Tujuan: retain useful research material.
Arah saat ini/ke depan:
- favorites/library;
- saved papers;
- research sessions;
- future collections/tags.
Library should gradually become an active research tool rather than a passive list of favorites.
5.5 Menggunakan
Tujuan: turn research into something usable.
Kemampuan saat ini meliputi:
- BibTeX;
- APA 7;
- Markdown export;
- PDF access.
Masa Depan direction may include richer citation and reference workflows.

1. Hierarki Fitur
Tier 1 — Inti
Fitur yang secara langsung mendukung alur riset utama:

- Riset / Chat
- Academic Search
- Paper Results
- Paper Detail
- Ask Paper / Tanya Paper
- AI Summary
- Library
- Citation / Export
Tier 2 — Pendukung
Fitur yang meningkatkan kedalaman riset:
- Explore
- Trending papers
- Deep Search
- Riset Skills
- Trend visualization
- PDF viewer
- Translation
Tier 3 — Masa Depan
Jangan memprioritaskan these during the current redesign:
- multi-paper comparison;
- advanced citation management;
- research projects;
- complex collections;
- full literature-review workspace;
- advanced collaboration.
Tier 3 should not be forced into the current architecture.

1. Struktur Navigasi Utama
Arah produk saat ini menggunakan bottom navigation sebagai navigasi utama di level aplikasi.
Secara konseptual:
Riset | Explore | Library | Pengaturan
Riset
Ruang kerja utama.
Contains the main research/search conversation and the resulting paper context.
Explore
Ruang untuk discovery: menjelajahi paper, kategori, dan tren.
Explore should not behave like a second generic home screen.
Library
Material riset yang disimpan.
Initially this can remain simple, but it should have a clear path toward search/filter/organization.
Pengaturan
Konfigurasi aplikasi serta pengaturan akun/model/provider.
Aturan navigasi
Do not hide the primary product areas behind a drawer when they deserve persistent navigation.
A drawer may still be used for aksi sekunder atau riwayat session if needed.
2. Riset Workspace
Riset is the primary product destination.
Workspace harus mendukung alur yang berkelanjutan:
Question
  ↓
Search
  ↓
Results
  ↓
Paper
  ↓
Understand
  ↓
Ask / Analyze
  ↓
Save / Cite / Use
Perpindahan antar tahap harus mempertahankan konteks riset yang berguna.
3. Riset Session vs Paper
Research session merepresentasikan rangkaian pertanyaan atau penyelidikan yang sedang dilakukan pengguna.
Paper adalah sumber/bukti yang ditemukan selama proses riset tersebut.
Keduanya berkaitan, tetapi tidak boleh diperlakukan sebagai konsep yang sama.
Untuk implementasi saat ini:

- sessions can continue to exist as chat/research history;
- papers can be opened independently;
- Paper Detail can temporarily establish an active paper context;
- a more formal research-project model is future scope.

 1. Paper Detail
Paper Detail adalah destinasi riset yang kontekstual, bukan halaman metadata yang menjadi jalan buntu.
It should provide:

- title;
- authors;
- publication metadata;
- abstract;
- PDF access when available;
- translation where supported;
- citation actions;
- save/favorite;
- AI actions.
Aksi AI Utama
Paper Detail must provide clear entry points for:
Rangkum dengan AI
and
Tanya Paper
These actions should allow the user to continue research without having to manually return to chat and rediscover the paper.

1. Siklus Paper
A paper can move through:
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
Not every paper must pass through every state.
The lifecycle is a product mental model, not a mandatory database state machine.
2. Prinsip Paper Card
Paper cards should answer quickly:
3. What is this paper?
4. Why might it matter?
5. What can I do next?
Cards should have one clear primary action.
Hindari button soup.
Secondary actions should appear progressively or contextually.
6. Ask Paper / Tanya Paper
Ask Paper / Tanya Paper means the AI is operating with a specific paper as research context.
When activated from Paper Detail, the selected paper becomes the Active Paper Context.
The user must be able to understand that the AI is currently answering with this paper as context.
The context must never be silently applied.
7. Aturan Active Paper Context
For the current product:
Hanya satu Active Paper Context yang didukung dalam satu waktu.
When a user chooses:

- Tanya Paper, or
- Rangkum dengan AI
the selected paper becomes active context.
UI harus mengomunikasikan konteks ini dengan cukup jelas agar pengguna memahami:
“AI sedang menggunakan paper ini sebagai konteks.”

The user should have an explicit way to remove or change the active context.
After a single answer, the context should not silently disappear.
Multi-paper context is deferred until there is a clear product need.
15. Model Interaksi AI
AI should feel like a research assistant, not an opaque chatbot.
The system should communicate meaningful states such as:

- thinking;
- searching;
- reading/analyzing;
- ready;
- error.
Statuses should reflect actual work where possible.
Masa Depan direction:
- streaming responses;
- richer progress feedback;
- structured research actions.

 1. Riset Context Visibility
Whenever AI uses external research context, the UI should make the context understandable.
Examples:

- active paper indicator;
- search/source indicator;
- source references;
- explicit paper context.
Hindari silent context switching.

 1. Empty State
Empty states should explain what the user can accomplish.
Primary tone:
Riset bermula dari sebuah pertanyaan.

The empty state should encourage a research action rather than merely saying there are no messages.
18. Loading & Menunggu
Waiting states should communicate what SCIChat is actually doing.
Prefer semantic progress over generic loading indicators.
Example:
Mencari paper…
Membaca sumber…
Menganalisis…
Do not use decorative animation that communicates no useful information.
19. Penanganan Error
Errors should answer three questions:

1. What failed?
2. Why might it have failed?
3. What can the user do next?
Whenever recovery is possible, provide an explicit retry or alternative action.
Hindari exposing raw technical errors as the primary user-facing message.
4. Explore
Explore is a discovery space, not a replacement for Riset.
Its role can include:

- categories;
- trending papers;
- curated discovery;
- topic exploration.
Explore cards should be functional.
A paper discovered in Explore must be able to enter the normal paper lifecycle:
Explore → Paper Detail → Understand → Ask/Save/Use

 1. Library
Library is the user's retained research material.
Scope saat ini dapat tetap sederhana:

- saved/favorite papers;
- paper access;
- citation actions.
Masa Depan scope:
- library search;
- filters;
- tags;
- collections;
- bulk citation/export.
Jangan memperkenalkan complex collection architecture before the underlying storage model is ready.

 1. Arah Literature Review
SCIChat already has research skills such as:

- /review;
- /gap;
- /table.
These should remain part of the research capability layer.
However, a full dedicated literature-review workspace is future scope.
The current product should first make the basic research loop continuous and coherent.

 1. Prinsip Produk
23.1 Riset over Chat
Optimize for completing research work, not maximizing chat interaction.
23.2 Konteks lebih penting daripada kenyamanan sesaat
Preserve useful research context between actions.
23.3 Progressive Disclosure
Show the right action at the right moment.
23.4 Satu Aksi Utama yang Jelas
Hindari interfaces where every element competes for attention.
23.5 Bukti Harus Tetap Dekat
Papers, sources, citations, and AI interpretation should remain connected.
23.6 Fungsional sebelum dekoratif
A visually impressive feature that does not improve research workflow is low priority.
 2. Arah Produk Anti-AI-Slop
SCIChat should avoid feeling like a generic AI app.
Hindari:

- generic chatbot clone layouts;
- excessive gradients;
- decorative AI sparkle;
- dashboard-like feature grids;
- excessive pills;
- excessive rounded cards;
- excessive shadows;
- meaningless animation;
- feature overload;
- “AI” labels everywhere without functional meaning.
Produk harus feel:
editorial, academic, focused, intentional, and useful.

1. Prioritas Produk Saat Ini
Priority for the redesign:
1. Navigation clarity
1. Riset workspace
1. Riset/chat continuity
1. Paper result hierarchy
1. Paper Detail
1. Ask Paper / Tanya Paper + AI Summary bridge
1. Active Paper Context visibility
1. Explore functionality
1. Library clarity
1. AI waiting/error states
1. Consistent interaction and motion
Do not expand the feature surface before these foundations are coherent.
1. Current vs Masa Depan
Current / redesign now

- Riset workspace
- Bottom navigation direction
- Academic search
- Paper results
- Paper Detail
- Ask Paper / Tanya Paper
- AI Summary
- Active Paper Context
- Explore
- Library
- Citation/export
- Existing research skills
Masa Depan
- Multi-paper context
- Multi-paper comparison
- Riset projects
- Advanced collections
- Advanced citation manager
- Full literature-review workspace
- Collaboration

1. Aturan Implementasi
1. Do not redesign individual screens in isolation.
1. Implement navigation and context rules before polishing visual details.
1. Do not add a feature merely because another AI research app has it.
1. Preserve working research capabilities while improving their workflow.
1. Prefer small, testable changes over a full rewrite.
1. Hindari introducing complex persistence requirements for future features prematurely.
1. Keep the architecture compatible with the existing Flutter implementation where practical.
1. When a product decision is still open, do not silently invent one during implementation.
1. Keputusan Produk yang Masih Terbuka
The following remain intentionally open:

- exact bottom-navigation visual treatment;
- whether Riset uses a dedicated search field, chat-first input, or a hybrid;
- how research sessions should appear within Riset;
- Library organization depth;
- Explore personalization;
- multi-paper analysis model;
- research projects;
- paper comparison;
- advanced citation management.
These decisions should be resolved only when enough product evidence exists.

1. Definisi Keberhasilan
Redesign dianggap berhasil jika pengguna dapat secara alami:
1. Start with a research question.
1. Find relevant papers.
1. Open a paper.
1. Understand the paper.
1. Ask the AI about that paper.
1. Continue analysis without losing context.
1. Save useful papers.
1. Cite or export useful research.
Pengguna harus merasa bahwa semua ini adalah bagian dari satu alur kerja riset, bukan fitur-fitur yang terpisah.
1. Prinsip Produk Final
SCIChat adalah research workspace yang didukung oleh AI.
Chat adalah cara pengguna berinteraksi dengan sistem.
Riset is what the user is actually trying to accomplish.
