import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/utils/pdf_chunker.dart';

void main() {
  group('Phase 4D.9 Fix A: Multi-line Section Heading Detection in PdfChunker', () {
    test('1. Detects multi-line numbered headings: 2.\\n \\nRELATED WORKS', () {
      const text = '''
Melaka, Malaysia
Email: ycwong@utem.edu.my

1.
INTRODUCTION

Cardiac arrhythmias refer to the impairment of electrical impulses.
ECG classification is crucial for early detection.

2.
RELATED WORKS

With a continuous input signal such as ECG, discretization is common.
DWT has been shown to be effective in feature extraction.
''';

      final chunks = PdfChunker.chunkText(text);
      expect(chunks, isNotEmpty);

      final introChunks = chunks.where((c) => c.sectionTitle == 'Introduction').toList();
      final relatedChunks = chunks.where((c) => c.sectionTitle == 'Related Work').toList();

      expect(introChunks, isNotEmpty, reason: '1. INTRODUCTION must be recognized');
      expect(relatedChunks, isNotEmpty, reason: '2. RELATED WORKS must be recognized');
      expect(relatedChunks.first.text, contains('With a continuous input signal'));
    });

    test('2. Detects multi-line compound headings: 3.\\n \\nRESEARCH \\nMETHOD', () {
      const text = '''
1.
INTRODUCTION
Introductory text on biomedical signal processing.

2.
RELATED WORKS
Related literature on neuromorphic computing.

3.
RESEARCH 
METHOD

This work aims to propose a digital design for implementation of neuromorphic computing on an FPGA.
An SNN algorithm is developed for ECG classification.
The MIT-BIH arrhythmia database (MITDB) contains 48 records.
''';

      final chunks = PdfChunker.chunkText(text);
      final methodChunks = chunks.where((c) => c.sectionTitle == 'Methodology').toList();

      expect(methodChunks, isNotEmpty, reason: '3. RESEARCH \\nMETHOD must map to Methodology');
      expect(methodChunks.first.text, contains('48 records'));
    });

    test('3. Detects multi-line subsections: 2.1.\\n \\nDiscrete wavelet transform', () {
      const text = '''
2.
RELATED WORKS

2.1.
Discrete wavelet transform

With a continuous input signal such as ECG, it is common practice to discretize it before processing.
''';

      final chunks = PdfChunker.chunkText(text);
      final subChunks = chunks.where((c) => c.sectionTitle == '2.1 Discrete wavelet transform').toList();

      expect(subChunks, isNotEmpty, reason: '2.1 Discrete wavelet transform must be detected as subsection');
      expect(subChunks.first.text, contains('discretize it before processing'));
    });

    test('4. Detects Materials and Methods variations', () {
      const text = '''
1.
INTRODUCTION
Background content.

MATERIALS AND METHODS
The experimental setup uses 500 samples collected from lab subjects.

4.
RESULTS
The final accuracy is 98.2%.
''';

      final chunks = PdfChunker.chunkText(text);
      final methodChunks = chunks.where((c) => c.sectionTitle == 'Methodology').toList();
      final resultsChunks = chunks.where((c) => c.sectionTitle == 'Results').toList();

      expect(methodChunks, isNotEmpty, reason: 'MATERIALS AND METHODS must map to Methodology');
      expect(resultsChunks, isNotEmpty, reason: '4. RESULTS must map to Results');
    });

    test('5. Safety: Ordinary numbered lists, equations, and decimals are NOT treated as headings', () {
      const text = '''
1. INTRODUCTION
We study arrhythmia classification.
There are three main steps:
1. We collect the data from MIT-BIH.
2. We filter the signal with DWT.
3. We classify spikes using SNN.
The constant pi is approximately 3.14159.
The model achieved 4.5 times faster inference.
''';

      final chunks = PdfChunker.chunkText(text);
      expect(chunks.length, equals(1));
      expect(chunks.first.sectionTitle, equals('Introduction'));
      expect(chunks.first.text, contains('3. We classify spikes'));
    });
  });
}
