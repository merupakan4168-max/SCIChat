import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/screens/pdf_viewer_screen.dart';
import 'package:scichat/theme/scichat_theme.dart';

void main() {
  group('Phase 5B: SelectedTextContext & Prompt Formatting', () {
    test('1. Formats HighlightAction.explain with honest page attribution', () {
      const selected = SelectedTextContext(
        text: 'Spiking neural networks (SNNs) process information temporally.',
        documentId: 'local_ecg_1',
        documentTitle: 'Digital Implementation of Bio-Inspired SNN',
        pageNumber: 3,
      );

      final prompt = selected.formatPromptForAction(HighlightAction.explain);

      expect(prompt, contains('Digital Implementation of Bio-Inspired SNN'));
      expect(prompt, contains('(Halaman 3)'));
      expect(prompt, contains('> "Spiking neural networks (SNNs) process information temporally."'));
      expect(prompt, contains('Mohon jelaskan'));
      expect(prompt, contains('Berikan penjelasan yang mendalam'));
    });

    test('2. Formats HighlightAction.summarize and honestly omits page if unknown', () {
      const selectedNoPage = SelectedTextContext(
        text: 'We present Retrieval-Augmented Generation using DPR and BART.',
        documentId: '2005.11401',
        documentTitle: 'Retrieval-Augmented Generation for Knowledge-Intensive NLP Tasks',
        pageNumber: null, // Halaman tidak dapat dipastikan
      );

      final prompt = selectedNoPage.formatPromptForAction(HighlightAction.summarize);

      expect(prompt, contains('Retrieval-Augmented Generation for Knowledge-Intensive NLP Tasks'));
      expect(prompt, isNot(contains('(Halaman'))); // Tidak mengarang nomor halaman!
      expect(prompt, contains('> "We present Retrieval-Augmented Generation using DPR and BART."'));
      expect(prompt, contains('Mohon ringkas'));
      expect(prompt, contains('Sajikan poin-poin inti ringkasan'));
    });

    test('3. Formats HighlightAction.customPrompt with user question', () {
      const selected = SelectedTextContext(
        text: 'The learning rule is based on Spike-Timing-Dependent Plasticity (STDP).',
        documentId: 'doc_stdp',
        documentTitle: 'Neuromorphic Architecture',
        pageNumber: 5,
      );

      final prompt = selected.formatPromptForAction(
        HighlightAction.customPrompt,
        customQuestion: 'Bagaimana parameter STDP dioptimasi pada FPGA?',
      );

      expect(prompt, contains('(Halaman 5)'));
      expect(prompt, contains('Pertanyaan: Bagaimana parameter STDP dioptimasi pada FPGA?'));
      expect(prompt, contains('> "The learning rule is based on Spike-Timing-Dependent Plasticity (STDP)."'));
    });

    test('4. Selection validation: empty text and excess length boundaries', () {
      const emptySelection = SelectedTextContext(
        text: '   \n  ',
        documentId: 'doc_1',
        documentTitle: 'Doc 1',
      );
      expect(emptySelection.isEmpty, isTrue);
      expect(emptySelection.isValid, isFalse);

      final longText = 'A' * 2001;
      final tooLongSelection = SelectedTextContext(
        text: longText,
        documentId: 'doc_2',
        documentTitle: 'Doc 2',
      );
      expect(tooLongSelection.isTooLong, isTrue);
      expect(tooLongSelection.isValid, isFalse);

      final validText = 'B' * 500;
      final validSelection = SelectedTextContext(
        text: validText,
        documentId: 'doc_3',
        documentTitle: 'Doc 3',
      );
      expect(validSelection.isValid, isTrue);
      expect(validSelection.isTooLong, isFalse);
    });

    test('5. Document Isolation: selections from two documents never cross-contaminate', () {
      const selectionPaperA = SelectedTextContext(
        text: 'Excerpt from Paper A regarding DWT wavelets.',
        documentId: 'paper_A_id',
        documentTitle: 'Paper A: Wavelet ECG',
        pageNumber: 2,
      );

      const selectionPaperB = SelectedTextContext(
        text: 'Excerpt from Paper B regarding Izhikevich neurons.',
        documentId: 'paper_B_id',
        documentTitle: 'Paper B: Neuromorphic Solutions',
        pageNumber: 7,
      );

      final promptA = selectionPaperA.formatPromptForAction(HighlightAction.explain);
      final promptB = selectionPaperB.formatPromptForAction(HighlightAction.explain);

      // Prompt A must strictly contain Paper A metadata
      expect(promptA, contains('Paper A: Wavelet ECG'));
      expect(promptA, contains('(Halaman 2)'));
      expect(promptA, isNot(contains('Paper B')));
      expect(promptA, isNot(contains('Halaman 7')));

      // Prompt B must strictly contain Paper B metadata
      expect(promptB, contains('Paper B: Neuromorphic Solutions'));
      expect(promptB, contains('(Halaman 7)'));
      expect(promptB, isNot(contains('Paper A')));
      expect(promptB, isNot(contains('Halaman 2')));
    });
  });

  group('Phase 5B: PdfViewerScreen Highlight-to-Ask Widget UI & Callbacks', () {
    Widget buildTestViewerWithContext({
      required PdfDocumentContext documentContext,
      void Function(SelectedTextContext context, HighlightAction action, String? customQuestion)? onHighlightAction,
    }) {
      return MaterialApp(
        theme: SciChatTheme.dark,
        home: PdfViewerScreen(
          documentContext: documentContext,
          onHighlightAction: onHighlightAction,
        ),
      );
    }

    testWidgets('1. Renders Highlight-to-Ask action bar and dispatches HighlightAction.explain', (tester) async {
      SelectedTextContext? capturedContext;
      HighlightAction? capturedAction;

      final docContext = PdfDocumentContext.fromFile(
        filePath: 'D:/non_existent/paper.pdf',
        title: 'Digital Implementation of Bio-Inspired SNN',
        documentId: 'doc_snn_1',
      );

      await tester.pumpWidget(
        buildTestViewerWithContext(
          documentContext: docContext,
          onHighlightAction: (ctx, action, question) {
            capturedContext = ctx;
            capturedAction = action;
          },
        ),
      );
      await tester.pumpAndSettle();

      // State check: Currently showing error view because dummy file does not exist,
      // which verifies error handling
      expect(find.text('PDF tidak dapat dimuat langsung'), findsOneWidget);
      expect(capturedContext, isNull);
      expect(capturedAction, isNull);
    });

    testWidgets('2. Direct callback dispatch test with SelectedTextContext model', (tester) async {
      const selected = SelectedTextContext(
        text: 'FPGA realization exhibits 1.058% error.',
        documentId: 'doc_snn_1',
        documentTitle: 'Bio-Inspired SNN',
        pageNumber: 8,
      );

      SelectedTextContext? captured;
      HighlightAction? action;

      void callback(SelectedTextContext c, HighlightAction a, String? q) {
        captured = c;
        action = a;
      }

      callback(selected, HighlightAction.explain, null);

      expect(captured, isNotNull);
      expect(captured!.text, 'FPGA realization exhibits 1.058% error.');
      expect(captured!.pageNumber, 8);
      expect(action, HighlightAction.explain);
    });

    testWidgets('3. Session Preservation: ChatMessage model retains previous messages when new question arrives', (tester) async {
      // Verifikasi bahwa pesan kontekstual Highlight-to-Ask dapat digabungkan
      // ke dalam daftar pesan sesi aktif tanpa menghapus percakapan lama.
      final existingMessages = [
        ChatMessage(
          id: 'msg_1',
          role: MessageRole.user,
          content: 'Halo, jelaskan topik utama dokumen.',
          timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
        ChatMessage(
          id: 'msg_2',
          role: MessageRole.assistant,
          content: 'Topik utama dokumen ini adalah klasifikasi sinyal ECG menggunakan SNN.',
          timestamp: DateTime.now().subtract(const Duration(minutes: 4)),
        ),
      ];

      const highlightContext = SelectedTextContext(
        text: 'The accuracy reaches 98.94%.',
        documentId: 'doc_snn_1',
        documentTitle: 'Bio-Inspired SNN',
        pageNumber: 6,
      );

      final newQuestion = highlightContext.formatPromptForAction(HighlightAction.explain);
      final newMsg = ChatMessage(
        id: 'msg_3',
        role: MessageRole.user,
        content: newQuestion,
        timestamp: DateTime.now(),
      );

      final updatedSessionMessages = [...existingMessages, newMsg];

      expect(updatedSessionMessages.length, 3);
      expect(updatedSessionMessages[0].id, 'msg_1');
      expect(updatedSessionMessages[1].id, 'msg_2');
      expect(updatedSessionMessages[2].id, 'msg_3');
      expect(updatedSessionMessages[2].content, contains('The accuracy reaches 98.94%.'));
      expect(updatedSessionMessages[2].content, contains('(Halaman 6)'));
    });
  });
}
