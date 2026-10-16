import '../models/models.dart';

String _formatDateTime(DateTime dt) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
  final d = dt.day.toString().padLeft(2, '0');
  final m = months[dt.month - 1];
  final y = dt.year;
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$d $m $y, $hh:$mm';
}

String _formatReference(ArxivPaper source) {
  final year = source.published.length >= 4 ? source.published.substring(0, 4) : '';
  final authorStr = source.authors.isNotEmpty ? source.authors.join(', ') : 'Penulis tidak tersedia';
  final title = source.title.replaceAll('\n', ' ').trim();
  
  final buffer = StringBuffer();
  buffer.write(authorStr);
  if (year.isNotEmpty) {
    buffer.write(' ($year)');
  }
  buffer.write('. $title.');
  
  if (source.absUrl.isNotEmpty) {
    if (source.doi == null || !source.absUrl.contains(source.doi!)) {
      buffer.write(' ${source.absUrl}');
    }
  }
  
  if (source.doi != null && source.doi!.isNotEmpty) {
    buffer.write(' DOI: ${source.doi}');
  }
  
  return buffer.toString();
}

String generateNoteExportText(ResearchNote note) {
  final buffer = StringBuffer();
  
  buffer.writeln('# Catatan Riset');
  buffer.writeln('**Disimpan pada:** ${_formatDateTime(note.savedAt)}');
  buffer.writeln();
  
  buffer.writeln(note.content);
  buffer.writeln();
  
  if (note.sources.isNotEmpty) {
    buffer.writeln('## Referensi');
    
    final uniqueSources = <String, ArxivPaper>{};
    for (final source in note.sources) {
      uniqueSources[source.id] = source;
    }
    
    int index = 1;
    for (final source in uniqueSources.values) {
      buffer.writeln('$index. ${_formatReference(source)}');
      index++;
    }
  }
  
  return buffer.toString().trim();
}

String generateNoteShareText(ResearchNote note) {
  final buffer = StringBuffer();
  
  buffer.writeln('CATATAN RISET');
  buffer.writeln('Disimpan pada: ${_formatDateTime(note.savedAt)}');
  buffer.writeln();
  
  // Membersihkan heading dan sintaks bold Markdown
  String cleanContent = note.content
      .replaceAll(RegExp(r'\*\*'), '')
      .replaceAll(RegExp(r'^#+\s+', multiLine: true), '');
      
  buffer.writeln(cleanContent);
  buffer.writeln();
  
  if (note.sources.isNotEmpty) {
    buffer.writeln('REFERENSI:');
    
    final uniqueSources = <String, ArxivPaper>{};
    for (final source in note.sources) {
      uniqueSources[source.id] = source;
    }
    
    int index = 1;
    for (final source in uniqueSources.values) {
      buffer.writeln('$index. ${_formatReference(source)}');
      index++;
    }
  }
  
  return buffer.toString().trim();
}
