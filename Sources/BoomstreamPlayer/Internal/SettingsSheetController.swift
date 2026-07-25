#if canImport(UIKit)
import UIKit

/// Unified settings sheet presented from the gear button when `showSettingsMenu` is enabled.
/// Shows Speed, Quality (when variants are available), and Audio (when multiple tracks exist)
/// sections in a native iOS sheet. Internal; not part of the public SDK surface.
@MainActor
final class SettingsSheetController: UIViewController {

    // MARK: - Data model

    struct Section {
        let title: String
        let items: [Row]
    }

    struct Row {
        let title: String
        let isSelected: Bool
        let action: () -> Void
    }

    // MARK: - Properties

    private let sheetTitle: String
    private let sections: [Section]
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    // MARK: - Init

    init(title: String, sections: [Section]) {
        self.sheetTitle = title
        self.sections = sections
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = sheetTitle

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }
}

// MARK: - UITableViewDataSource

extension SettingsSheetController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].items.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let row = sections[indexPath.section].items[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = row.title
        cell.contentConfiguration = config
        cell.accessoryType = row.isSelected ? .checkmark : .none
        return cell
    }
}

// MARK: - UITableViewDelegate

extension SettingsSheetController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = sections[indexPath.section].items[indexPath.row]
        row.action()
        dismiss(animated: true)
    }
}
#endif
