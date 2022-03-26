//
//  BackupManager.swift
//  Aidoku
//
//  Created by Skitty on 2/26/22.
//

import Foundation

class BackupManager {

    static let shared = BackupManager()

    static let directory = FileManager.default.documentDirectory.appendingPathComponent("Backups", isDirectory: true)

    static var backupUrls: [URL] {
        Self.directory.contentsByDateAdded
    }

    static var backups: [Backup] {
        Self.backupUrls.compactMap { Backup.load(from: $0) }
    }

    func save(backup: Backup, url: URL? = nil) {
        Self.directory.createDirctory()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let json = try? encoder.encode(backup) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            if let url = url {
                try? json.write(to: url)
            } else {
                let path = Self.directory.appendingPathComponent("aidoku_\(dateFormatter.string(from: backup.date)).json")
                try? json.write(to: path)
            }
            NotificationCenter.default.post(name: Notification.Name("updateBackupList"), object: nil)
        }
    }

    func saveNewBackup() {
        save(backup: createBackup())
    }

    func importBackup(from url: URL) {
        Self.directory.createDirctory()
        var targetLocation = Self.directory.appendingPathComponent(url.lastPathComponent)
        while targetLocation.exists {
            targetLocation = targetLocation.deletingLastPathComponent().appendingPathComponent(
                targetLocation.deletingPathExtension().lastPathComponent.appending("_1")
            ).appendingPathExtension(url.pathExtension)
        }
        try? FileManager.default.moveItem(at: url, to: targetLocation)
        NotificationCenter.default.post(name: Notification.Name("updateBackupList"), object: nil)
    }

    func createBackup() -> Backup {
        let library = (try? DataManager.shared.getLibraryObjects())?.map {
            BackupLibraryManga(libraryObject: $0)
        } ?? []
        let history = (try? DataManager.shared.getReadHistory())?.map {
            BackupHistory(historyObject: $0)
        } ?? []
        let manga = (try? DataManager.shared.getMangaObjects())?.map {
            BackupManga(mangaObject: $0)
        } ?? []
        let chapters = (try? DataManager.shared.getChapterObjects())?.map {
            BackupChapter(chapterObject: $0)
        } ?? []
        let sources = (try? DataManager.shared.getSourceObjects())?.compactMap {
            $0.id
        } ?? []

        return Backup(
            library: library,
            history: history,
            manga: manga,
            chapters: chapters,
            sources: sources,
            date: Date(),
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        )
    }

    func renameBackup(url: URL, name: String?) {
        guard var backup = Backup.load(from: url) else { return }
        backup.name = name?.isEmpty ?? true ? nil : name
        save(backup: backup, url: url)
    }

    func removeBackup(url: URL) {
        try? FileManager.default.removeItem(at: url)
        NotificationCenter.default.post(name: Notification.Name("updateBackupList"), object: nil)
    }

    func restore(from backup: Backup) {
        // this should probably do some more checks before running, idk

        if backup.history != nil {
            DataManager.shared.clearHistory()
            backup.history?.forEach {
                _ = $0.toObject(context: DataManager.shared.container.viewContext)
            }
        }

        if backup.manga != nil {
            DataManager.shared.clearManga()
            backup.manga?.forEach {
                _ = $0.toObject(context: DataManager.shared.container.viewContext)
            }
        }

        if backup.library != nil {
            DataManager.shared.clearLibrary()
            backup.library?.forEach {
                let libraryObject = $0.toObject(context: DataManager.shared.container.viewContext)
                if let manga = DataManager.shared.getMangaObject(withId: $0.mangaId, sourceId: $0.sourceId) {
                    libraryObject.manga = manga
                }
            }
        }

        if backup.chapters != nil {
            DataManager.shared.clearChapters()
            backup.chapters?.forEach {
                let chapter = $0.toObject(context: DataManager.shared.container.viewContext)
                chapter.manga = DataManager.shared.getMangaObject(withId: $0.mangaId, sourceId: $0.sourceId)
            }
        }

        _ = DataManager.shared.save()

        DataManager.shared.loadLibrary()
    }
}