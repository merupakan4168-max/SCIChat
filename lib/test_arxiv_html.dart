import 'package:http/http.dart' as http;

void main() async {
  final shortId = "2410.10539"; 
  final url = Uri.parse('https://ar5iv.org/html/$shortId');
  final res = await http.get(url);
  
  print("Status: ${res.statusCode}");
  if (res.statusCode == 200) {
    final body = res.body;
    final exp = RegExp(r'<img[^>]+src="([^">]+)"');
    final matches = exp.allMatches(body);
    int count = 0;
    for (final m in matches) {
      final src = m.group(1);
      if (src != null && !src.contains('mathjax') && !src.contains('arxiv-logo')) {
        print("Found image: $src");
        count++;
      }
    }
    print("Total images: $count");
  }
}
