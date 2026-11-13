import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_app/core/sync/merge.dart';
import 'package:sealed_app/models/vault_item.dart';

void main() {
  const fields = VaultItem.mergeFields;
  final base = {'title': 'Mail', 'username': 'a', 'password': 'one', 'notes': '', 'modified': '2026-01-01T00:00:00Z'};

  test('changes to different fields merge cleanly', () {
    final mine = {...base, 'password': 'two', 'modified': '2026-01-02T00:00:00Z'};
    final theirs = {...base, 'notes': 'hi', 'modified': '2026-01-03T00:00:00Z'};
    final r = threeWayMerge(base, mine, theirs, fields: fields);
    expect(r.clean, isTrue);
    expect(r.merged['password'], 'two');
    expect(r.merged['notes'], 'hi');
    expect(r.merged['modified'], '2026-01-03T00:00:00Z');
  });

  test('the same change on both sides is not a conflict', () {
    final mine = {...base, 'password': 'two'};
    final r = threeWayMerge(base, mine, {...mine}, fields: fields);
    expect(r.clean, isTrue);
    expect(r.merged['password'], 'two');
  });

  test('different changes to one field conflict and keep mine for now', () {
    final r = threeWayMerge(base, {...base, 'password': 'two'}, {...base, 'password': 'three', 'title': 'Gmail'},
        fields: fields);
    expect(r.conflicts, ['password']);
    expect(r.merged['password'], 'two');
    expect(r.merged['title'], 'Gmail');
  });

  test('without a base every difference is a conflict', () {
    final r = threeWayMerge(null, {...base, 'password': 'x'}, base, fields: fields);
    expect(r.conflicts, ['password']);
    expect(threeWayMerge(null, base, {...base}, fields: fields).clean, isTrue);
  });

  test('a field added on one side is kept', () {
    final r = threeWayMerge(base, {...base, 'url': 'mail.example'}, base, fields: fields);
    expect(r.clean, isTrue);
    expect(r.merged['url'], 'mail.example');
  });

  test('vault items survive a JSON round trip', () {
    final item = VaultItem(
      id: 'x',
      type: ItemType.note,
      title: 'T',
      notes: 'N',
      favorite: true,
      modifiedAt: DateTime.utc(2026, 11, 7, 12),
    );
    final back = VaultItem.fromJson('x', item.toJson());
    expect(back.toJson(), item.toJson());
    expect(VaultItem.fromJson('y', {}).type, ItemType.login);
  });
}
