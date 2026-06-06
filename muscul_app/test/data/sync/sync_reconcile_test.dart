import 'package:flutter_test/flutter_test.dart';
import 'package:reps/data/sync/sync_service.dart';

/// Unit tests for the deletion set-difference at the heart of the
/// "deleted template exercise comes back after reopen" fix.
///
/// When a template is saved, the local DB has already dropped the rows the
/// user removed. [SyncService.staleCloudIds] decides which rows still on the
/// cloud must be deleted so the next pull can't resurrect them.
void main() {
  group('SyncService.staleCloudIds', () {
    test('returns cloud ids that no longer exist locally', () {
      final stale = SyncService.staleCloudIds(
        localIds: ['a', 'c'],
        cloudIds: ['a', 'b', 'c', 'd'],
      );
      expect(stale, ['b', 'd']);
    });

    test('returns everything when the local list is empty (all removed)', () {
      final stale = SyncService.staleCloudIds(
        localIds: const [],
        cloudIds: ['a', 'b'],
      );
      expect(stale, ['a', 'b']);
    });

    test('returns nothing when local still has every cloud row', () {
      final stale = SyncService.staleCloudIds(
        localIds: ['a', 'b', 'c'],
        cloudIds: ['a', 'b'],
      );
      expect(stale, isEmpty);
    });

    test('ignores brand-new local rows not yet on the cloud', () {
      final stale = SyncService.staleCloudIds(
        localIds: ['a', 'new'],
        cloudIds: ['a'],
      );
      expect(stale, isEmpty);
    });
  });
}
