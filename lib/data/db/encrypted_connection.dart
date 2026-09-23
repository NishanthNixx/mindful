import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

const dbFileName = 'mindfull.db';

/// Opens [file] with SQLCipher using a raw 256-bit key ([hexKey], 64 hex
/// chars). A raw key skips SQLCipher's PBKDF2 step, which is safe because the
/// key is random rather than derived from a password.
///
/// Throws on open if the key is wrong or SQLCipher isn't linked, so we never
/// silently fall back to writing plaintext.
QueryExecutor openEncryptedDatabase(File file, String hexKey) {
  assert(
    RegExp(r'^[0-9a-f]{64}$').hasMatch(hexKey),
    'expected 32-byte hex key',
  );
  return NativeDatabase.createInBackground(
    file,
    setup: (db) => applyCipherKey(db, hexKey),
  );
}

void applyCipherKey(Database db, String hexKey) {
  final version = db.select('PRAGMA cipher_version');
  if (version.isEmpty) {
    throw StateError(
      'SQLCipher is not available; refusing to open unencrypted.',
    );
  }
  db
    ..execute('''PRAGMA key = "x'$hexKey'"''')
    // Touch the schema so a wrong key fails here, not on first query.
    ..select('SELECT count(*) FROM sqlite_master');
}

Future<File> defaultDatabaseFile() async {
  final dir = await getApplicationSupportDirectory();
  return File(p.join(dir.path, dbFileName));
}
