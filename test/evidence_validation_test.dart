import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/providers/scichat_provider.dart';

void main() {
  group('Evidence Validation Tests (Phase 6C-2.1)', () {
    late SciChatProvider provider;

    setUp(() {
      provider = SciChatProvider();
    });

    test('Valid scientific abstract is classified as usable (abstractOnly)', () {
      expect(provider.isAbstractValid('This paper introduces a novel method for deep learning optimization...'), isTrue);
    });

    test('Empty or whitespace abstract is rejected (noUsableText)', () {
      expect(provider.isAbstractValid(''), isFalse);
      expect(provider.isAbstractValid('   \n  '), isFalse);
    });

    test('Placeholder "Tidak ada abstrak yang tersedia..." is rejected (noUsableText)', () {
      expect(provider.isAbstractValid('Tidak ada abstrak yang tersedia untuk makalah OpenAlex ini.'), isFalse);
      expect(provider.isAbstractValid('Tidak ada abstrak.'), isFalse);
      expect(provider.isAbstractValid('Abstrak tidak tersedia'), isFalse);
    });

    test('Variations of capitalization and whitespace placeholders are safely rejected (noUsableText)', () {
      expect(provider.isAbstractValid('  Tidak Ada Abstrak Yang Tersedia  '), isFalse);
      expect(provider.isAbstractValid('No abstract available.'), isFalse);
      expect(provider.isAbstractValid('N/A'), isFalse);
      expect(provider.isAbstractValid('None'), isFalse);
      expect(provider.isAbstractValid('abstract'), isFalse);
    });

    test('Short but valid scientific abstract is accepted (abstractOnly)', () {
      expect(provider.isAbstractValid('We propose a new model.'), isTrue);
    });
  });

  group('Text Validation Tests (Phase 6C-3)', () {
    late SciChatProvider provider;

    setUp(() {
      provider = SciChatProvider();
    });

    test('Valid long extracted text is usable', () {
      final text = 'Abstract. We introduce a new framework for modeling natural language... ' * 10;
      expect(provider.isTextUsable(text), isTrue);
    });

    test('Empty or null text is rejected', () {
      expect(provider.isTextUsable(null), isFalse);
      expect(provider.isTextUsable('   \n  '), isFalse);
    });

    test('Text that is extremely short (< 20 chars) is rejected', () {
      expect(provider.isTextUsable('Too short'), isFalse);
    });

    test('Short but valid text (>= 20 chars) is accepted', () {
      expect(provider.isTextUsable('This is a short text, but not a full paper.'), isTrue);
    });

    test('Common PDF error messages are rejected even if long', () {
      final errorText1 = 'There was an error opening this document. Please check your connection and try again.' * 5;
      final errorText2 = 'This PDF is encrypted and password protected. Enter password to view.' * 5;
      final errorText3 = '403 Forbidden. Access Denied.' * 10;

      expect(provider.isTextUsable(errorText1), isFalse);
      expect(provider.isTextUsable(errorText2), isFalse);
      expect(provider.isTextUsable(errorText3), isFalse);
    });
  });
}
