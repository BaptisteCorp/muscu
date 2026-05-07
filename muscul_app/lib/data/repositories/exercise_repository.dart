import 'package:drift/drift.dart';

import '../../domain/models/exercise.dart';
import '../db/database.dart';
import 'mappers.dart';

abstract class ExerciseRepository {
  Stream<List<Exercise>> watchAll({bool includeDeleted = false});
  Future<List<Exercise>> getAll({bool includeDeleted = false});
  Future<Exercise?> getById(String id);
  Future<void> upsert(Exercise exercise);
  Future<void> softDelete(String id);
}

class LocalExerciseRepository implements ExerciseRepository {
  final AppDatabase db;
  LocalExerciseRepository(this.db);

  @override
  Stream<List<Exercise>> watchAll({bool includeDeleted = false}) {
    final query = db.select(db.exercises);
    if (!includeDeleted) {
      query.where((tbl) => tbl.deletedAt.isNull());
    }
    query.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return query.watch().map((rows) => rows.map(exerciseFromRow).toList());
  }

  @override
  Future<List<Exercise>> getAll({bool includeDeleted = false}) async {
    final query = db.select(db.exercises);
    if (!includeDeleted) {
      query.where((tbl) => tbl.deletedAt.isNull());
    }
    query.orderBy([(t) => OrderingTerm.asc(t.name)]);
    final rows = await query.get();
    return rows.map(exerciseFromRow).toList();
  }

  @override
  Future<Exercise?> getById(String id) async {
    final row = await (db.select(db.exercises)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : exerciseFromRow(row);
  }

  @override
  Future<void> upsert(Exercise exercise) async {
    await db
        .into(db.exercises)
        .insertOnConflictUpdate(exerciseToCompanion(exercise));
  }

  @override
  Future<void> softDelete(String id) async {
    await (db.update(db.exercises)..where((t) => t.id.equals(id))).write(
      ExercisesCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
  }
}
