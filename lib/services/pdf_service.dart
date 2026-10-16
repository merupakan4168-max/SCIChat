import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdf/pdf.dart';

String? _extractTextSync(List<int> bytes) {
  try {
    final document = PdfDocument(inputBytes: bytes);
    final extractor = PdfTextExtractor(document);
    final text = extractor.extractText();
    document.dispose();
    return text;
  } catch (e) {
    return null; // Don't print in isolate to avoid issues
  }
}

class PdfService {
  Future<String?> extractTextFromUrl(String url, {int maxChars = 40000}) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return extractTextFromBytes(response.bodyBytes, maxChars: maxChars);
      }
    } catch (e) {
      print('Failed to download PDF: $e');
    }
    return null;
  }

  Future<String?> extractTextFromBytes(List<int> bytes, {int maxChars = 40000}) async {
    try {
      final text = await compute(_extractTextSync, bytes);
      if (text == null) return null;
      
      // Limit text (default ~40,000 characters) to prevent overloading the LLM
      if (text.length > maxChars) {
        return '${text.substring(0, maxChars)}\n\n[TEXT TRUNCATED DUE TO LENGTH]';
      }
      return text;
    } catch (e) {
      print('Failed to extract PDF: $e');
    }
    return null;
  }
}
