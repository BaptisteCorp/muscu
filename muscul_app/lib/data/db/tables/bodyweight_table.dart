import 'package:drift/drift.dart';

@DataClassName('BodyweightEntryEntity')
class BodyweightEntries extends Table {
  /// Date stored as 'YYYY-MM-DD' to enforce one entry per day.
  TextColumn get date => text()();
  RealColumn get weightKg => real()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {date};
}
