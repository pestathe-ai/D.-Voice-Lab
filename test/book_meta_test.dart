import 'package:d_voce/core/book.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('il segno annota quando è stato spostato e sopravvive al salvataggio', () {
    final b = BookMeta(
      id: 'x', title: 't', author: '', format: 'pdf', lang: 'it',
      addedAt: DateTime(2026), chapterCount: 3, totalChars: 100,
    );
    expect(b.positionAt, 0);
    b.setPosition(1, 5, at: 1000);
    expect(b.positionAt, 1000);
    b.setPosition(1, 5, at: 2000); // stesso punto: l'ora non cambia
    expect(b.positionAt, 1000);
    final copy = BookMeta.fromJson(b.toJson());
    expect((copy.chapter, copy.chunk, copy.positionAt), (1, 5, 1000));
  });
}
