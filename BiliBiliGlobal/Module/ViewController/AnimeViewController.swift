import SnapKit
import UIKit

final class AnimeViewController: UIViewController, BLTabBarContentVCProtocol, UICollectionViewDelegate {
    private enum Section: Int {
        case featured, shortcuts, watching, days, schedule, popular

        var title: String? {
            switch self {
            case .watching: return "Continue watching"
            case .days: return "Release schedule"
            case .popular: return "Popular anime"
            default: return nil
            }
        }
    }

    private enum Shortcut: String, CaseIterable {
        case categories = "Categories", schedule = "Schedule", free = "Free to watch", new = "New anime"
        var symbol: String {
            switch self {
            case .categories: return "square.grid.2x2.fill"
            case .schedule: return "calendar"
            case .free: return "play.rectangle.fill"
            case .new: return "sparkles.tv.fill"
            }
        }

        var color: UIColor {
            switch self {
            case .categories: return .systemOrange
            case .schedule: return .systemGreen
            case .free: return .systemPink
            case .new: return .systemCyan
            }
        }
    }

    private enum Item: Hashable {
        case card(Section, AnimeCard)
        case shortcut(Shortcut)
        case day(Int)
        case message(Section, String, retry: Bool)
    }

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let spinner = UIActivityIndicatorView(style: .large)
    private var loadTask: Task<Void, Never>?
    private var accountObserver: NSObjectProtocol?
    private var accountID: Int?
    private var featured: [AnimeCard] = []
    private var catalog: [AnimeCard] = []
    private var watching: [AnimeCard] = []
    private var days: [AnimeScheduleDay] = []
    private var selectedDay = 0
    private var failures = Set<Section>()
    private var lastLoaded: Date?
    private var requestedFocus: IndexPath?

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if let requestedFocus, let cell = collectionView.cellForItem(at: requestedFocus) { return [cell] }
        return super.preferredFocusEnvironments
    }

    deinit {
        loadTask?.cancel()
        if let accountObserver { NotificationCenter.default.removeObserver(accountObserver) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.035, green: 0.045, blue: 0.075, alpha: 1)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.contentInset = UIEdgeInsets(top: 30, left: 0, bottom: 70, right: 0)
        collectionView.remembersLastFocusedIndexPath = true
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { $0.edges.equalTo(view.safeAreaLayoutGuide) }
        configureDataSource()
        view.addSubview(spinner)
        spinner.snp.makeConstraints { $0.center.equalToSuperview() }
        accountID = AccountManager.shared.activeAccount?.profile.mid
        accountObserver = NotificationCenter.default.addObserver(forName: AccountManager.didUpdateNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            let accountID = AccountManager.shared.activeAccount?.profile.mid
            guard accountID != self.accountID else { return }
            self.accountID = accountID
            self.loadTask?.cancel()
            self.loadTask = nil
            self.featured = []
            self.catalog = []
            self.watching = []
            self.days = []
            self.lastLoaded = nil
            self.applySnapshot()
            self.reloadData()
        }
        reloadData()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Refresh progress when returning from an episode, without rebuilding the whole page.
        if let lastLoaded, loadTask == nil {
            if Date().timeIntervalSince(lastLoaded) > 60 * 60 { reloadData() }
            else { refreshWatching() }
        }
    }

    func reloadData() {
        guard loadTask == nil else { return }
        spinner.startAnimating()
        loadTask = Task { [weak self] in
            async let catalogResult = WebRequest.requestAnimeHome()
            async let scheduleResult = WebRequest.requestAnimeSchedule()
            async let watchingResult = WebRequest.requestAnimeContinueWatching()
            guard let self, !Task.isCancelled else { return }
            self.failures.removeAll()
            do {
                let home = try await catalogResult
                guard !Task.isCancelled else { return }
                self.featured = home.featured
                self.catalog = home.popular
            } catch {
                guard !Task.isCancelled else { return }
                self.failures.insert(.popular)
            }
            do {
                let days = try await scheduleResult
                guard !Task.isCancelled else { return }
                let previousDate = self.days.indices.contains(self.selectedDay) ? self.days[self.selectedDay].date : nil
                self.days = days
                self.selectedDay = days.firstIndex { $0.date == previousDate }
                    ?? days.firstIndex { $0.isToday } ?? 0
            } catch {
                guard !Task.isCancelled else { return }
                self.failures.insert(.schedule)
            }
            do {
                let watching = try await watchingResult
                guard !Task.isCancelled else { return }
                self.watching = watching
            } catch {
                guard !Task.isCancelled else { return }
                self.failures.insert(.watching)
            }
            guard !Task.isCancelled else { return }
            self.lastLoaded = Date()
            self.spinner.stopAnimating()
            self.applySnapshot()
            self.loadTask = nil
        }
    }

    private func refreshWatching() {
        loadTask = Task { [weak self] in
            let cards = try? await WebRequest.requestAnimeContinueWatching()
            guard let self, !Task.isCancelled else { return }
            if let cards {
                self.watching = cards
                self.failures.remove(.watching)
                self.applySnapshot()
            }
            self.loadTask = nil
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        if !featured.isEmpty {
            snapshot.appendSections([.featured])
            snapshot.appendItems(featured.map { .card(.featured, $0) })
        }
        snapshot.appendSections([.shortcuts, .watching, .days, .schedule, .popular])
        snapshot.appendItems(Shortcut.allCases.map(Item.shortcut), toSection: .shortcuts)
        snapshot.appendItems(watching.map { .card(.watching, $0) }, toSection: .watching)
        if watching.isEmpty || failures.contains(.watching) {
            snapshot.appendItems([.message(.watching, failures.contains(.watching)
                    ? "Couldn't refresh watch history. Select to retry."
                    : "Your Bilibili anime watch history will appear here. Pick up where you left off.",
                retry: failures.contains(.watching))], toSection: .watching)
        }
        snapshot.appendItems(days.indices.map(Item.day), toSection: .days)
        if days.indices.contains(selectedDay) {
            var seen = Set<Int>()
            let cards = days[selectedDay].cards.filter { seen.insert($0.seasonID).inserted }
            snapshot.appendItems(cards.map { .card(.schedule, $0) }, toSection: .schedule)
            if cards.isEmpty {
                snapshot.appendItems([.message(.schedule, "No releases scheduled for this day.", retry: false)], toSection: .schedule)
            }
        }
        if failures.contains(.schedule) || days.isEmpty {
            snapshot.appendItems([.message(.schedule, failures.contains(.schedule)
                    ? "Couldn't refresh the release schedule. Select to retry." : "No release schedule is available.",
                retry: failures.contains(.schedule))], toSection: .schedule)
        }
        let popular = catalog
        snapshot.appendItems(popular.map { .card(.popular, $0) }, toSection: .popular)
        if popular.isEmpty || failures.contains(.popular) {
            snapshot.appendItems([.message(.popular, failures.contains(.popular)
                    ? "Couldn't refresh anime. Select to retry." : "No anime is available right now.",
                retry: failures.contains(.popular))], toSection: .popular)
        }
        // Day cells keep their identity so focus stays in the date strip after selecting a day.
        snapshot.reconfigureItems(days.indices.map(Item.day).filter { dataSource.snapshot().itemIdentifiers.contains($0) })
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, _ in
            guard let self, let snapshot = self.dataSource?.snapshot(), snapshot.sectionIdentifiers.indices.contains(index) else { return nil }
            let section = snapshot.sectionIdentifiers[index]
            let height: CGFloat
            let width: NSCollectionLayoutDimension
            switch section {
            case .featured: height = 430; width = .fractionalWidth(0.88)
            case .shortcuts: height = 108; width = .fractionalWidth(0.25)
            case .days: height = 104; width = .fractionalWidth(1.0 / 7)
            default:
                let items = snapshot.itemIdentifiers(inSection: section)
                let messageOnly = !items.isEmpty && items.allSatisfy { if case .message = $0 { return true }; return false }
                height = messageOnly ? 130 : 370
                width = messageOnly ? .fractionalWidth(1) : .absolute(390)
            }
            let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
            let group: NSCollectionLayoutGroup
            if section == .shortcuts || section == .days {
                let gridItem = NSCollectionLayoutItem(layoutSize: .init(widthDimension: width, heightDimension: .fractionalHeight(1)))
                gridItem.contentInsets = .init(top: 0, leading: 8, bottom: 0, trailing: 8)
                group = .horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height)), subitems: [gridItem])
            } else {
                group = .horizontal(layoutSize: .init(widthDimension: width, heightDimension: .absolute(height)), subitems: [item])
            }
            let layout = NSCollectionLayoutSection(group: group)
            if section != .shortcuts && section != .days {
                layout.orthogonalScrollingBehavior = .continuousGroupLeadingBoundary
                layout.interGroupSpacing = 28
            }
            layout.contentInsets = .init(top: 20, leading: 70, bottom: 34, trailing: 70)
            if section.title != nil {
                let header = NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(48)),
                    elementKind: UICollectionView.elementKindSectionHeader, alignment: .top
                )
                layout.boundarySupplementaryItems = [header]
            }
            return layout
        }
    }

    private func configureDataSource() {
        let artwork = UICollectionView.CellRegistration<AnimeArtworkCell, Item> { cell, _, item in
            if case let .card(section, card) = item { cell.configure(card, featured: section == .featured) }
        }
        let text = UICollectionView.CellRegistration<AnimeMenuCell, Item> { [weak self] cell, _, item in
            switch item {
            case let .shortcut(shortcut):
                cell.configure(title: shortcut.rawValue, subtitle: nil, symbol: shortcut.symbol, color: shortcut.color)
            case let .day(index):
                guard let self, self.days.indices.contains(index) else { return }
                let day = self.days[index]
                cell.configure(title: day.isToday ? "Today · \(day.weekday)" : day.weekday,
                               subtitle: day.date, symbol: nil, color: .systemPink, selected: index == self.selectedDay)
            case let .message(_, message, retry):
                cell.configure(title: message, subtitle: nil, symbol: retry ? "arrow.clockwise" : nil, color: .systemPink)
            default: break
            }
        }
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collection, index, item in
            if case .card = item { return collection.dequeueConfiguredReusableCell(using: artwork, for: index, item: item) }
            return collection.dequeueConfiguredReusableCell(using: text, for: index, item: item)
        }
        let header = UICollectionView.SupplementaryRegistration<TitleSupplementaryView>(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] view, _, index in
            view.label.text = self?.dataSource.snapshot().sectionIdentifiers[index.section].title
            view.label.textColor = .white
        }
        dataSource.supplementaryViewProvider = { collection, _, index in
            collection.dequeueConfiguredReusableSupplementary(using: header, for: index)
        }
    }

    func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
        if case let .message(_, _, retry) = dataSource.itemIdentifier(for: indexPath) { return retry }
        return true
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case let .card(_, card):
            let detail = card.detailViewController()
            detail.modalPresentationStyle = .fullScreen
            present(detail, animated: true)
        case let .day(index):
            selectedDay = index
            applySnapshot()
        case .shortcut(.schedule):
            guard let section = dataSource.snapshot().indexOfSection(.days), !days.isEmpty else { reloadData(); return }
            let index = IndexPath(item: selectedDay, section: section)
            collectionView.scrollToItem(at: index, at: .centeredVertically, animated: false)
            collectionView.layoutIfNeeded()
            requestedFocus = index
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
            requestedFocus = nil
        case let .shortcut(shortcut):
            let controller: UIViewController
            if shortcut == .categories {
                controller = AnimeCategoriesViewController()
            } else {
                controller = AnimeCatalogViewController(order: shortcut == .new ? 0 : 3, freeOnly: shortcut == .free)
            }
            controller.modalPresentationStyle = .fullScreen
            present(controller, animated: true)
        case let .message(_, _, retry): if retry { reloadData() }
        }
    }
}

private final class AnimeCategoriesViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate {
    private var conditions: AnimeCatalogConditions?
    private var selections: [String: String] = [:]
    private var rows: [AnimeCatalogConditions.Filter] { conditions?.rows ?? [] }
    private var loadTask: Task<Void, Never>?
    private var loadError: String?
    private var menu: UICollectionView!
    private let resultsView = UIView()
    private let summaryLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private var catalog: AnimeCatalogViewController?

    override var preferredFocusEnvironments: [UIFocusEnvironment] { [menu] }

    deinit { loadTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.035, green: 0.045, blue: 0.075, alpha: 1)
        let title = UILabel()
        title.text = "Anime categories"
        title.font = .systemFont(ofSize: 42, weight: .semibold)
        title.textColor = .white
        view.addSubview(title)
        title.snp.makeConstraints { make in
            make.top.leading.equalTo(view.safeAreaLayoutGuide).offset(30)
        }
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 370, height: 100)
        layout.minimumLineSpacing = 16
        layout.sectionInset = UIEdgeInsets(top: 15, left: 20, bottom: 35, right: 20)
        menu = UICollectionView(frame: .zero, collectionViewLayout: layout)
        menu.backgroundColor = .clear
        menu.register(AnimeMenuCell.self, forCellWithReuseIdentifier: "filter")
        menu.dataSource = self
        menu.delegate = self
        view.addSubview(menu)
        menu.snp.makeConstraints { make in
            make.top.equalTo(title.snp.bottom).offset(20)
            make.leading.bottom.equalTo(view.safeAreaLayoutGuide)
            make.width.equalTo(410)
        }
        summaryLabel.font = .systemFont(ofSize: 25)
        summaryLabel.textColor = .lightGray
        summaryLabel.numberOfLines = 2
        view.addSubview(summaryLabel)
        summaryLabel.snp.makeConstraints { make in
            make.leading.equalTo(menu.snp.trailing).offset(30)
            make.trailing.equalTo(view.safeAreaLayoutGuide).inset(30)
            make.centerY.equalTo(title)
        }
        view.addSubview(resultsView)
        resultsView.snp.makeConstraints { make in
            make.leading.equalTo(menu.snp.trailing).offset(20)
            make.trailing.bottom.equalTo(view.safeAreaLayoutGuide)
            make.top.equalTo(menu)
        }
        view.addSubview(spinner)
        spinner.snp.makeConstraints { $0.center.equalTo(resultsView) }
        loadConditions()
    }

    private func loadConditions() {
        guard loadTask == nil else { return }
        loadError = nil
        menu.reloadData()
        spinner.startAnimating()
        loadTask = Task { [weak self] in
            do {
                let conditions = try await WebRequest.requestAnimeCatalogConditions()
                try Task.checkCancellation()
                guard let self else { return }
                guard !conditions.rows.isEmpty else { throw "No anime filters are available. Select to retry." }
                self.conditions = conditions
                self.selections = conditions.defaults
                self.menu.reloadData()
                self.showResults()
                self.setNeedsFocusUpdate()
                self.updateFocusIfNeeded()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.loadError = "Couldn't load categories. Select to retry."
                self.menu.reloadData()
                self.setNeedsFocusUpdate()
                self.updateFocusIfNeeded()
            }
            self?.spinner.stopAnimating()
            self?.loadTask = nil
        }
    }

    private func showResults() {
        guard let conditions else { return }
        var filters = selections
        filters["sort"] = conditions.order.first { $0.field == selections["order"] }?.sort ?? "0"
        let summary = rows.compactMap { row -> String? in
            guard row.field == "order" || selections[row.field] != conditions.defaults[row.field] else { return nil }
            return row.values.first { $0.keyword == selections[row.field] }?.name
        }.joined(separator: " · ")
        summaryLabel.text = summary
        catalog?.willMove(toParent: nil)
        catalog?.view.removeFromSuperview()
        catalog?.removeFromParent()
        let next = AnimeCatalogViewController(filters: filters)
        next.onFirstPage = { [weak self, weak next] empty in
            guard let self, self.catalog === next else { return }
            self.summaryLabel.text = empty ? "No anime matches these filters." : summary
        }
        catalog = next
        addChild(next)
        resultsView.addSubview(next.view)
        next.view.snp.makeConstraints { $0.edges.equalToSuperview() }
        next.didMove(toParent: self)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        rows.isEmpty ? 1 : rows.count + 1
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "filter", for: indexPath) as! AnimeMenuCell
        if rows.isEmpty {
            cell.configure(title: loadError ?? "Loading categories…", subtitle: nil, symbol: nil, color: .systemPink)
        } else if indexPath.item == rows.count {
            cell.configure(title: "Reset filters", subtitle: nil, symbol: "arrow.counterclockwise", color: .systemPink)
        } else {
            let row = rows[indexPath.item]
            let selected = row.values.first { $0.keyword == selections[row.field] }
            cell.configure(title: row.name, subtitle: selected?.name, symbol: nil, color: .systemPink)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
        !rows.isEmpty || loadError != nil
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard !rows.isEmpty else { loadConditions(); return }
        if indexPath.item == rows.count {
            selections = conditions?.defaults ?? [:]
            menu.reloadData()
            showResults()
            return
        }
        let row = rows[indexPath.item]
        let picker = UIAlertController(title: row.name, message: nil, preferredStyle: .actionSheet)
        for value in row.values {
            let title = (selections[row.field] == value.keyword ? "✓ " : "") + value.name
            picker.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self, self.selections[row.field] != value.keyword else { return }
                self.selections[row.field] = value.keyword
                self.menu.reloadItems(at: [indexPath])
                self.showResults()
            })
        }
        picker.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(picker, animated: true)
    }
}

private final class AnimeCatalogViewController: StandardVideoCollectionViewController<AnimeCard> {
    private let order: Int
    private let freeOnly: Bool
    private let filters: [String: String]
    var onFirstPage: ((Bool) -> Void)?
    private var hasMore = true

    init(order: Int = 3, freeOnly: Bool = false, filters: [String: String] = [:]) {
        self.order = order
        self.freeOnly = freeOnly
        self.filters = filters
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func setupCollectionView() {
        super.setupCollectionView()
        collectionVC.pageSize = 24
        collectionVC.styleOverride = .normal
    }

    override func request(page: Int) async throws -> [AnimeCard] {
        guard page == 1 || hasMore else { return [] }
        let response = try await WebRequest.requestAnimeCatalog(page: page, order: order, freeOnly: freeOnly, filters: filters)
        hasMore = response.has_next == 1
        if page == 1 { onFirstPage?(response.list.isEmpty) }
        return response.list.compactMap(\.card)
    }

    override func goDetail(with record: AnimeCard) {
        let detail = record.detailViewController()
        detail.modalPresentationStyle = .fullScreen
        present(detail, animated: true)
    }
}
