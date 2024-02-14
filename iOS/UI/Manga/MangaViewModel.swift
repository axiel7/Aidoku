//
//  MangaViewModel.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/1/23.
//

import Foundation

@MainActor
class MangaViewModel {

    var chapterList: [Chapter] = []
    var readingHistory: [String: (page: Int, date: Int)] = [:] // chapterId: (page, date)
    var downloadProgress: [String: Float] = [:] // chapterId: progress

    var sortMethod: ChapterSortOption = .sourceOrder
    var sortAscending: Bool = false
    var filters: [ChapterFilterOption] = []
    var langFilter: String?

    func loadChapterList(manga: Manga) async {
        let inLibrary = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.hasLibraryManga(sourceId: manga.sourceId, mangaId: manga.id, context: context)
        }

        if inLibrary {
            // load from db
            chapterList = await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.getChapters(
                    sourceId: manga.sourceId,
                    mangaId: manga.id,
                    context: context
                ).map {
                    $0.toChapter()
                }
            }
        } else {
            // load from source
            guard let source = SourceManager.shared.source(for: manga.sourceId) else { return }
            chapterList = (try? await source.getChapterList(manga: manga)) ?? []
        }

        await filterChapterList(manga: manga)
    }

    func loadHistory(manga: Manga) async {
        readingHistory = await CoreDataManager.shared.getReadingHistory(sourceId: manga.sourceId, mangaId: manga.id)
    }

    func removeHistory(for chapters: [Chapter]) {
        for chapter in chapters {
            readingHistory.removeValue(forKey: chapter.id)
        }
    }

    func addHistory(for chapters: [Chapter], date: Date = Date()) {
        for chapter in chapters {
            readingHistory[chapter.id] = (-1, Int(date.timeIntervalSince1970))
        }
    }

    func sortChapters(method: ChapterSortOption? = nil, ascending: Bool? = nil) {
        let method = method ?? sortMethod
        let ascending = ascending ?? sortAscending
        sortMethod = method
        sortAscending = ascending
        switch method {
        case .sourceOrder:
            if ascending {
                chapterList.sort { $0.sourceOrder > $1.sourceOrder }
            } else {
                chapterList.sort { $0.sourceOrder < $1.sourceOrder }
            }
        case .chapter:
            if ascending {
                chapterList.sort { $0.chapterNum ?? 0 > $1.chapterNum ?? 0 }
            } else {
                chapterList.sort { $0.chapterNum ?? 0 < $1.chapterNum ?? 0 }
            }
        case .uploadDate:
            let now = Date()
            if ascending {
                chapterList.sort { $0.dateUploaded ?? now > $1.dateUploaded ?? now }
            } else {
                chapterList.sort { $0.dateUploaded ?? now < $1.dateUploaded ?? now }
            }
        }
    }

    func filterChapterList(manga: Manga) async {
        filterChaptersByLanguage(manga: manga)

        for filter in filters {
            switch filter.type {
            case .downloaded:
                chapterList = chapterList.filter {
                    let downloaded = !DownloadManager.shared.isChapterDownloaded(chapter: $0)
                    return filter.exclude ? downloaded : !downloaded
                }
            case .unread:
                await CoreDataManager.shared.container.performBackgroundTask { context in
                    self.chapterList = self.chapterList.filter {
                        let hasHistory = CoreDataManager.shared.hasHistory(
                            sourceId: $0.sourceId,
                            mangaId: $0.mangaId,
                            chapterId: $0.id,
                            context: context
                        )
                        return filter.exclude ? hasHistory : !hasHistory
                    }
                }
            }
        }
    }

    private func filterChaptersByLanguage(manga: Manga) {
        if let langFilter {
            chapterList = chapterList.filter { $0.lang == langFilter }
        }
    }

    func languageFilterChanged(_ newValue: String?, manga: Manga) async {
        langFilter = newValue
        await loadChapterList(manga: manga)
        await saveFilters(manga: manga)
        NotificationCenter.default.post(name: NSNotification.Name("updateHistory"), object: nil)
    }

    func generageChapterFlags() -> Int {
        var flags: Int = 0
        if sortAscending {
            flags |= ChapterFlagMask.sortAscending
        }
        flags |= sortMethod.rawValue << 1
        for filter in filters {
            switch filter.type {
            case .downloaded:
                flags |= ChapterFlagMask.downloadFilterEnabled
                if filter.exclude {
                    flags |= ChapterFlagMask.downloadFilterExcluded
                }
            case .unread:
                flags |= ChapterFlagMask.unreadFilterEnabled
                if filter.exclude {
                    flags |= ChapterFlagMask.unreadFilterExcluded
                }
            }
        }
        return flags
    }

    func saveFilters(manga: Manga) async {
        manga.chapterFlags = generageChapterFlags()
        manga.langFilter = langFilter
        await CoreDataManager.shared.updateMangaDetails(manga: manga)
    }

    func getSourceDefaultLanguages(sourceId: String) -> [String] {
        guard let source = SourceManager.shared.source(for: sourceId) else { return [] }
        return source.getDefaultLanguages()
    }

    enum ChapterResult {
        case none
        case allRead
        case chapter(Chapter)
    }

    // returns first chapter not completed, or falls back to top chapter
    func getNextChapter() -> ChapterResult {
        guard !chapterList.isEmpty else { return .none }
        // get first chapter not completed
        let chapter = getOrderedChapterList().reversed().first(where: { readingHistory[$0.id]?.page ?? 0 != -1 })
        if let chapter = chapter {
            return .chapter(chapter)
        }
        // get last read chapter (doesn't work if all chapters were marked read at the same time)
//        let id = viewModel.readingHistory.max { a, b in a.value.date < b.value.date }?.key
//        let lastRead: Chapter
//        if let id = id, let match = viewModel.chapterList.first(where: { $0.id == id }) {
//            lastRead = match
//        } else {
//            lastRead = viewModel.chapterList.last!
//        }
        return .allRead
    }

    func getOrderedChapterList() -> [Chapter] {
        (sortAscending && sortMethod == .sourceOrder) || (!sortAscending && sortMethod != .sourceOrder)
            ? chapterList.reversed()
            : chapterList
    }
}
