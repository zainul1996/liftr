import Foundation
import LIFTRCore
import SQLite3

/// Structured data lives in SQLite; sensor arrays remain in separate immutable files.
final class SQLiteRecordingIndex {
  private var database: OpaquePointer?
  private var transient: sqlite3_destructor_type {
    unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  }
  init(url: URL) throws {
    guard
      sqlite3_open_v2(
        url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil
      ) == SQLITE_OK
    else {
      let message =
        database.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open recording database"
      if let database { sqlite3_close(database) }
      database = nil
      throw IndexError.database(message)
    }
    do {
      let version = try statement("PRAGMA user_version") { statement in
        guard sqlite3_step(statement) == SQLITE_ROW else { throw failure() }
        return Int(sqlite3_column_int(statement, 0))
      }
      guard version <= 1 else { throw IndexError.unsupportedSchema(version) }
      sqlite3_busy_timeout(database, 2_000)
      try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON;")
      try execute(
        """
        CREATE TABLE IF NOT EXISTS recording_metadata (
          id TEXT PRIMARY KEY, session_id TEXT NOT NULL, exercise_id TEXT,
          started_at REAL NOT NULL, metadata BLOB NOT NULL
        );
        CREATE TABLE IF NOT EXISTS transfer_acknowledgements (
          recording_id TEXT PRIMARY KEY, acknowledged_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS recording_reviews (
          recording_id TEXT NOT NULL, review_id TEXT NOT NULL, reviewed_at REAL NOT NULL,
          exercise_id TEXT NOT NULL, actual_reps INTEGER, weight_kg REAL,
          PRIMARY KEY(recording_id, review_id)
        );
        CREATE TABLE IF NOT EXISTS recording_deletions (recording_id TEXT PRIMARY KEY);
        CREATE TABLE IF NOT EXISTS completed_migrations (name TEXT PRIMARY KEY);
        PRAGMA user_version=1;
        """)
    } catch {
      sqlite3_close(database)
      database = nil
      throw error
    }
  }
  deinit { if let database { sqlite3_close(database) } }
  private func execute(_ sql: String) throws {
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
  }
  private func failure() -> IndexError {
    let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Database unavailable"
    let code = sqlite3_errcode(database)
    return (code == SQLITE_CORRUPT || code == SQLITE_NOTADB)
      ? .corruptDatabase(message) : .database(message)
  }
  private func statement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw failure()
    }
    defer { sqlite3_finalize(statement) }
    return try body(statement)
  }
  private func bind(_ value: String?, to index: Int32, in statement: OpaquePointer) throws {
    let status =
      value.map { sqlite3_bind_text(statement, index, $0, -1, transient) }
      ?? sqlite3_bind_null(statement, index)
    guard status == SQLITE_OK else { throw failure() }
  }
  private func step(_ statement: OpaquePointer) throws {
    guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
  }
  private func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
    sqlite3_column_text(statement, column).map { String(cString: $0) }
  }
  private func transaction(_ operation: () throws -> Void) throws {
    try execute("BEGIN IMMEDIATE")
    do {
      try operation()
      try execute("COMMIT")
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }
  func metadata(id: UUID) throws -> RecordingMetadata? {
    try statement("SELECT metadata FROM recording_metadata WHERE id=?") { statement in
      try bind(id.uuidString, to: 1, in: statement)
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { return nil }
      guard status == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else {
        throw failure()
      }
      let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
      return try RecordingJSON.decoder().decode(RecordingMetadata.self, from: data)
    }
  }
  func saveMetadata(_ metadata: RecordingMetadata) throws {
    let data = try RecordingJSON.encoder().encode(metadata)
    try transaction {
      try statement(
        "INSERT OR REPLACE INTO recording_metadata(id,session_id,exercise_id,started_at,metadata) VALUES(?,?,?,?,?)"
      ) { statement in
        try bind(metadata.id.uuidString, to: 1, in: statement)
        try bind(metadata.sessionID.uuidString, to: 2, in: statement)
        try bind(metadata.exerciseID, to: 3, in: statement)
        sqlite3_bind_double(statement, 4, metadata.startedAt.timeIntervalSince1970)
        let result = data.withUnsafeBytes {
          sqlite3_bind_blob(statement, 5, $0.baseAddress, Int32(data.count), transient)
        }
        guard result == SQLITE_OK else { throw failure() }
        try step(statement)
      }
      try statement("DELETE FROM recording_deletions WHERE recording_id=?") { statement in
        try bind(metadata.id.uuidString, to: 1, in: statement)
        try step(statement)
      }
    }
  }
  func deletionCommitted(id: UUID) throws -> Bool {
    try statement("SELECT 1 FROM recording_deletions WHERE recording_id=?") { statement in
      try bind(id.uuidString, to: 1, in: statement)
      let result = sqlite3_step(statement)
      if result == SQLITE_ROW { return true }
      guard result == SQLITE_DONE else { throw failure() }
      return false
    }
  }
  func delete(id: UUID, stageFiles: () throws -> Void = {}) throws {
    try transaction {
      for table in ["recording_metadata", "recording_reviews", "transfer_acknowledgements"] {
        let column = table == "recording_metadata" ? "id" : "recording_id"
        try statement("DELETE FROM \(table) WHERE \(column)=?") { statement in
          try bind(id.uuidString, to: 1, in: statement)
          try step(statement)
        }
      }
      try statement("INSERT OR IGNORE INTO recording_deletions(recording_id) VALUES(?)") {
        statement in
        try bind(id.uuidString, to: 1, in: statement)
        try step(statement)
      }
      try stageFiles()
    }
  }
  func acknowledgedIDs() throws -> Set<UUID> {
    try statement("SELECT recording_id FROM transfer_acknowledgements") { statement in
      var result = Set<UUID>()
      while true {
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return result }
        guard status == SQLITE_ROW else { throw failure() }
        if let value = text(statement, 0), let id = UUID(uuidString: value) { result.insert(id) }
      }
    }
  }
  func acknowledge(id: UUID) throws {
    try statement(
      "INSERT OR IGNORE INTO transfer_acknowledgements(recording_id,acknowledged_at) VALUES(?,?)"
    ) { statement in
      try bind(id.uuidString, to: 1, in: statement)
      sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
      try step(statement)
    }
  }
  func reviews() throws -> [String: [RecordingReview]] {
    try statement(
      "SELECT recording_id,review_id,reviewed_at,exercise_id,actual_reps,weight_kg FROM recording_reviews ORDER BY rowid"
    ) { statement in
      var result: [String: [RecordingReview]] = [:]
      while true {
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return result }
        guard status == SQLITE_ROW, let recordingID = text(statement, 0),
          let rawID = text(statement, 1), let id = UUID(uuidString: rawID),
          let exercise = text(statement, 3)
        else { throw failure() }
        let reps =
          sqlite3_column_type(statement, 4) == SQLITE_NULL
          ? nil : Int(sqlite3_column_int64(statement, 4))
        let weight =
          sqlite3_column_type(statement, 5) == SQLITE_NULL
          ? nil : sqlite3_column_double(statement, 5)
        result[recordingID, default: []].append(
          .init(
            id: id, reviewedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
            exerciseID: exercise, actualReps: reps, weightKG: weight))
      }
    }
  }
  private func insert(_ review: RecordingReview, recordingID: String) throws {
    try statement(
      "INSERT INTO recording_reviews(recording_id,review_id,reviewed_at,exercise_id,actual_reps,weight_kg) VALUES(?,?,?,?,?,?)"
    ) { statement in
      try bind(recordingID, to: 1, in: statement)
      try bind(review.id.uuidString, to: 2, in: statement)
      sqlite3_bind_double(statement, 3, review.reviewedAt.timeIntervalSince1970)
      try bind(review.exerciseID, to: 4, in: statement)
      if let reps = review.actualReps {
        sqlite3_bind_int64(statement, 5, Int64(reps))
      } else {
        sqlite3_bind_null(statement, 5)
      }
      if let weight = review.weightKG {
        sqlite3_bind_double(statement, 6, weight)
      } else {
        sqlite3_bind_null(statement, 6)
      }
      try step(statement)
    }
  }
  func appendReview(recordingID: UUID, review: RecordingReview) throws -> [RecordingReview] {
    try transaction { try insert(review, recordingID: recordingID.uuidString) }
    return try reviews()[recordingID.uuidString] ?? []
  }
  func replaceReviews(recordingID: UUID, with reviews: [RecordingReview]) throws {
    try transaction {
      try statement("DELETE FROM recording_reviews WHERE recording_id=?") { statement in
        try bind(recordingID.uuidString, to: 1, in: statement)
        try step(statement)
      }
      for review in reviews { try insert(review, recordingID: recordingID.uuidString) }
    }
  }
  func hasMigration(_ name: String) throws -> Bool {
    try statement("SELECT 1 FROM completed_migrations WHERE name=?") { statement in
      try bind(name, to: 1, in: statement)
      let status = sqlite3_step(statement)
      if status == SQLITE_ROW { return true }
      if status == SQLITE_DONE { return false }
      throw failure()
    }
  }
  private func markMigration(_ name: String) throws {
    try statement("INSERT INTO completed_migrations(name) VALUES(?)") { statement in
      try bind(name, to: 1, in: statement)
      try step(statement)
    }
  }
  func migrateAcknowledgements(_ ids: Set<UUID>) throws {
    guard try !hasMigration("acknowledgements-json-v1") else { return }
    try transaction {
      for id in ids { try acknowledge(id: id) }
      try markMigration("acknowledgements-json-v1")
    }
  }
  func migrateReviews(_ reviews: [String: [RecordingReview]]) throws {
    guard try !hasMigration("reviews-json-v1") else { return }
    try transaction {
      for (id, history) in reviews {
        guard let normalized = UUID(uuidString: id) else { throw IndexError.invalidLegacyData }
        for review in history { try insert(review, recordingID: normalized.uuidString) }
      }
      try markMigration("reviews-json-v1")
    }
  }
  enum IndexError: Error {
    case database(String)
    case invalidLegacyData
    case unsupportedSchema(Int)
    case corruptDatabase(String)
  }
}
