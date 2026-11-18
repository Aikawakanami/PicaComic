import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:sqlite3/sqlite3.dart';

import 'sqlite_test_support.dart';

void main() {
  configureTestSqlite();

  test('history cover repair preserves progress and checks source and old URL',
      () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    db.execute('''CREATE TABLE history (
      target TEXT PRIMARY KEY, title TEXT, subtitle TEXT, cover TEXT,
      time INT, type INT, ep INT, page INT, readEpisode TEXT, max_page INT)''');
    db.execute('''INSERT INTO history VALUES
      ('same-id', 'Title', 'Author', 'stale.jpg', 1000, 0, 2, 15, '1,2', 34)''');
    final manager = HistoryManager.forTesting(db);
    final original = manager.findSync('same-id')!;
    final before = original.toMap();
    final changes = <String>[];
    manager.coverChanges.addListener(() {
      changes.add(manager.coverChanges.value!.url);
    });

    manager.updateCover(
        History.fromMap({...before, 'type': HistoryType.jmComic.value}),
        'wrong-source.jpg');
    manager.updateCover(original, 'working.jpg');
    manager.updateCover(History.fromMap(before), 'late-result.jpg');
    manager.updateCover(
        History.fromMap({...before, 'target': 'missing'}), 'missing-row.jpg');

    expect(changes, ['working.jpg']);
    expect(
        manager.getAll().single.toMap(), {...before, 'cover': 'working.jpg'});
    expect(original.cover, 'working.jpg');
  });
}
