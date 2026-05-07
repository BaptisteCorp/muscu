import 'package:drift/drift.dart';

import '../../domain/models/bodyweight_entry.dart';
import '../db/database.dart';

abstract class BodyweightRepository {
  Stream<List<BodyweightEntry>> watchAll();
  Future<BodyweightEntry?> getForDate(String date);
  Future<void> upsert(BodyweightEntry entry);
  Future<void> delete(String date);
}

class LocalBodyweightRepository implements BodyweightRepository {
  final AppDatabase db;
  LocalBodyweightRepository(this.db);

  BodyweightEntry _fromRow(BodyweightEntryEntity row) => BodyweightEntry(
        date: row.date,
        weightKg: row.weightKg,
        note: row.note,
        updatedAt: row.updatedAt,
      );

  @override
  Stream<List<BodyweightEntry>> watchAll() {
    final q = db.select(db.bodyweightEntries)
      ..orderBy([(t) => OrderingTerm.asc(t.date)]);
    return q.watch().map((rows) => rows.map(_fromRow).toList());
  }

  @override
  Future<BodyweightEntry?> getForDate(String date) async {
    final row = await (db.select(db.bodyweightEntries)
          ..where((t) => t.date.equals(date)))
        .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<void> upsert(BodyweightEntry entry) async {
    await db.into(db.bodyweightEntries).insertOnConflictUpdate(
          BodyweightEntriesCompanion.insert(
            date: entry.date,
            weightKg: entry.weightKg,
            note: Value(entry.note),
            updatedAt: entry.updatedAt,
          ),
        );
  }

  @override
  Future<void> delete(String date) async {
    await (db.delete(db.bodyweightEntries)..where((t) => t.date.equals(date)))
        .go();
  }
}
