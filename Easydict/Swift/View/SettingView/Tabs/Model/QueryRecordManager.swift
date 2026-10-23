//
//  QueryRecordManager.swift
//  Easydict
//
//  Created by Copilot on 2025/11/19.
//  Copyright © 2025 izual. All rights reserved.
//

import AppKit
import Defaults
import Foundation

// MARK: - QueryRecordManager

/// Manages query record operations for favorites and history.
///
/// Records are kept in memory after the first load and written to defaults on a background
/// queue, so each query avoids decoding and re-encoding the whole history on the main thread.
@objc
class QueryRecordManager: NSObject {
    // MARK: Lifecycle

    override init() {
        super.init()

        // `queue: nil` delivers synchronously on the posting (main) thread, so queued writes
        // are saved before the process exits.
        self.terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.flush()
        }
    }

    // MARK: Internal

    /// Defines the record category stored in defaults.
    @objc
    enum RecordType: Int {
        case favorites
        case history

        // MARK: Internal

        /// Returns the defaults key for the record type.
        var storageKey: Defaults.Key<[QueryRecord]> {
            switch self {
            case .favorites:
                return Defaults.Keys.favorites
            case .history:
                return Defaults.Keys.queryHistory
            }
        }

        /// Provides the maximum number of records allowed for the type.
        var maxCount: Int? {
            switch self {
            case .favorites:
                return nil
            case .history:
                return QueryRecordManager.maxHistoryCount
            }
        }

        /// Determines how duplicates should be handled for the record type.
        var deduplicationPolicy: DeduplicationPolicy {
            switch self {
            case .favorites:
                return .skipIfExists
            case .history:
                return .moveToFront
            }
        }
    }

    /// Describes how to handle duplicate query texts when adding records.
    enum DeduplicationPolicy {
        case skipIfExists
        case moveToFront
    }

    /// Shared instance used by the app.
    @objc static let shared = QueryRecordManager()

    /// Adds a query record to the specified category.
    @objc
    func addRecord(
        queryText: String,
        fromLanguage: Language,
        toLanguage: Language,
        to type: RecordType
    ) {
        addRecord(
            queryText: queryText,
            fromLanguage: fromLanguage,
            toLanguage: toLanguage,
            translatedResult: nil,
            to: type
        )
    }

    /// Adds a query record with an optional translated result to the specified category.
    @objc
    func addRecord(
        queryText: String,
        fromLanguage: Language,
        toLanguage: Language,
        translatedResult: String?,
        to type: RecordType
    ) {
        updateRecords(for: type) { records in
            let record = makeRecord(
                queryText: queryText,
                fromLanguage: fromLanguage,
                toLanguage: toLanguage,
                translatedResult: translatedResult
            )

            switch type.deduplicationPolicy {
            case .skipIfExists:
                guard !records.contains(where: { $0.queryText == queryText }) else {
                    return false
                }
            case .moveToFront:
                records.removeAll { $0.queryText == queryText }
            }

            records.insert(record, at: 0)

            if let maxCount = type.maxCount, records.count > maxCount {
                records = Array(records.prefix(maxCount))
            }

            return true
        }
    }

    /// Updates the translated result of an existing record matched by query text.
    @objc
    func updateTranslatedResult(
        _ translatedResult: String,
        forQueryText queryText: String,
        in type: RecordType
    ) {
        updateRecords(for: type) { records in
            guard let index = records.firstIndex(where: { $0.queryText == queryText }) else {
                return false
            }
            records[index].translatedResult = translatedResult
            return true
        }
    }

    /// Removes a record by ID from the specified category.
    func removeRecord(id: UUID, from type: RecordType) {
        updateRecords(for: type) { records in
            let originalCount = records.count
            records.removeAll { $0.id == id }
            return records.count != originalCount
        }
    }

    /// Returns all records for the specified category.
    func getAllRecords(for type: RecordType) -> [QueryRecord] {
        loadRecords(for: type)
    }

    /// Clears all records for the specified category.
    func clearAllRecords(for type: RecordType) {
        saveRecords([], for: type)
    }

    /// Checks whether the given query text exists in the specified category.
    @objc
    func containsRecord(queryText: String, in type: RecordType) -> Bool {
        loadRecords(for: type).contains { $0.queryText == queryText }
    }

    /// Blocks until all queued record writes have been saved to defaults.
    ///
    /// Runs automatically when the app terminates.
    func flush() {
        persistQueue.sync {}
    }

    /// Drops the in-memory records and any unsaved writes, so the next access reloads from defaults.
    ///
    /// Call after the stored records change outside this manager, such as a full defaults reset.
    func discardCachedRecords() {
        lock.withLock {
            cachedRecords.removeAll()
            pendingTypes.removeAll()
        }
    }

    // MARK: Private

    /// Maximum number of history records to keep.
    private static let maxHistoryCount = 1000

    /// Guards `cachedRecords` and `pendingTypes`, which are shared with `persistQueue`.
    private let lock = NSLock()

    /// Serializes defaults writes off the main thread.
    private let persistQueue = DispatchQueue(label: "com.izual.Easydict.query-record-manager", qos: .utility)

    /// In-memory records per type, loaded from defaults on first access.
    private var cachedRecords: [RecordType: [QueryRecord]] = [:]

    /// Types whose in-memory records have a queued, not yet started, write.
    private var pendingTypes = Set<RecordType>()

    private var terminationObserver: NSObjectProtocol?

    /// Returns all records stored for the specified type.
    private func loadRecords(for type: RecordType) -> [QueryRecord] {
        lock.withLock { cachedRecordsLocked(for: type) }
    }

    /// Saves the records for the specified type.
    private func saveRecords(_ records: [QueryRecord], for type: RecordType) {
        lock.withLock { cachedRecords[type] = records }
        schedulePersist(for: type)
    }

    /// Updates records for the specified type and saves when modified.
    private func updateRecords(for type: RecordType, mutate: (inout [QueryRecord]) -> Bool) {
        let didChange: Bool = lock.withLock {
            var records = cachedRecordsLocked(for: type)
            guard mutate(&records) else {
                return false
            }
            cachedRecords[type] = records
            return true
        }
        if didChange {
            schedulePersist(for: type)
        }
    }

    /// Returns the in-memory records, loading them from defaults on first access. Caller must hold `lock`.
    private func cachedRecordsLocked(for type: RecordType) -> [QueryRecord] {
        if let records = cachedRecords[type] {
            return records
        }
        let records = Defaults[type.storageKey]
        cachedRecords[type] = records
        return records
    }

    /// Queues a defaults write for the specified type, coalescing changes made before it runs.
    private func schedulePersist(for type: RecordType) {
        let isNewRequest = lock.withLock { pendingTypes.insert(type).inserted }
        guard isNewRequest else {
            return
        }
        // The app supports sudden termination, which skips `willTerminate`; keep the process
        // alive until the queued write lands.
        ProcessInfo.processInfo.disableSuddenTermination()
        persistQueue.async { [weak self] in
            self?.persistPendingRecords(for: type)
            ProcessInfo.processInfo.enableSuddenTermination()
        }
    }

    /// Writes the latest in-memory records for the specified type. Runs on `persistQueue`.
    private func persistPendingRecords(for type: RecordType) {
        let records: [QueryRecord]? = lock.withLock {
            guard pendingTypes.remove(type) != nil else {
                return nil
            }
            return cachedRecords[type]
        }
        if let records {
            Defaults[type.storageKey] = records
        }
    }

    /// Creates a query record from the provided values.
    private func makeRecord(
        queryText: String,
        fromLanguage: Language,
        toLanguage: Language,
        translatedResult: String?
    )
        -> QueryRecord {
        QueryRecord(
            queryText: queryText,
            queryFromLanguage: fromLanguage,
            queryToLanguage: toLanguage,
            translatedResult: translatedResult
        )
    }
}
