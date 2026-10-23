import '../models/models.dart';

/// Kategori pengelompokan riwayat percakapan riset berbasis waktu kalender lokal.
enum HistoryTimeGroup {
  today('Hari Ini'),
  yesterday('Kemarin'),
  last7Days('7 Hari Terakhir'),
  older('Lebih Lama');

  final String label;
  const HistoryTimeGroup(this.label);
}

/// Struktur wadah grup sesi riwayat beserta label kelompoknya.
class GroupedHistorySessions {
  final HistoryTimeGroup group;
  final List<ChatSession> sessions;

  const GroupedHistorySessions({
    required this.group,
    required this.sessions,
  });
}

/// Fungsi murni untuk mengelompokkan sesi riwayat riset berdasarkan waktu kalender lokal.
///
/// Aturan:
/// 1. Sesi dalam setiap kelompok selalu diurutkan dari terbaru ke terlama (`updatedAt` descending).
/// 2. Hari Ini: Tanggal kalender lokal sama dengan [now] (atau lebih baru jika terdapat perbedaan clock).
/// 3. Kemarin: Tanggal kalender lokal tepat 1 hari kalender sebelum [now].
/// 4. 7 Hari Terakhir: Tanggal kalender lokal 2 sampai 7 hari kalender sebelum [now].
/// 5. Lebih Lama: Lebih dari 7 hari kalender sebelum [now].
/// 6. Kelompok yang tidak memiliki sesi TIDAK dimasukkan ke dalam daftar hasil (tidak merender header kosong).
List<GroupedHistorySessions> groupChatSessionsByTime(
  List<ChatSession> sessions, {
  DateTime? now,
}) {
  if (sessions.isEmpty) return const [];

  final referenceTime = now ?? DateTime.now();
  final todayMidnight =
      DateTime(referenceTime.year, referenceTime.month, referenceTime.day);
  final yesterdayMidnight =
      DateTime(referenceTime.year, referenceTime.month, referenceTime.day - 1);
  final sevenDaysAgoMidnight =
      DateTime(referenceTime.year, referenceTime.month, referenceTime.day - 7);

  final todaySessions = <ChatSession>[];
  final yesterdaySessions = <ChatSession>[];
  final last7DaysSessions = <ChatSession>[];
  final olderSessions = <ChatSession>[];

  // Urutkan sesi dari updatedAt terbaru ke terlama
  final sortedSessions = List<ChatSession>.from(sessions)
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  for (final session in sortedSessions) {
    final sessionMidnight = DateTime(
      session.updatedAt.year,
      session.updatedAt.month,
      session.updatedAt.day,
    );

    if (sessionMidnight == todayMidnight ||
        sessionMidnight.isAfter(todayMidnight)) {
      todaySessions.add(session);
    } else if (sessionMidnight == yesterdayMidnight) {
      yesterdaySessions.add(session);
    } else if (sessionMidnight.isAtSameMomentAs(sevenDaysAgoMidnight) ||
        sessionMidnight.isAfter(sevenDaysAgoMidnight)) {
      last7DaysSessions.add(session);
    } else {
      olderSessions.add(session);
    }
  }

  final result = <GroupedHistorySessions>[];
  if (todaySessions.isNotEmpty) {
    result.add(GroupedHistorySessions(
      group: HistoryTimeGroup.today,
      sessions: todaySessions,
    ));
  }
  if (yesterdaySessions.isNotEmpty) {
    result.add(GroupedHistorySessions(
      group: HistoryTimeGroup.yesterday,
      sessions: yesterdaySessions,
    ));
  }
  if (last7DaysSessions.isNotEmpty) {
    result.add(GroupedHistorySessions(
      group: HistoryTimeGroup.last7Days,
      sessions: last7DaysSessions,
    ));
  }
  if (olderSessions.isNotEmpty) {
    result.add(GroupedHistorySessions(
      group: HistoryTimeGroup.older,
      sessions: olderSessions,
    ));
  }

  return result;
}
