import SwiftUI
import UIKit
import TouchDynamics

/// UITableView with reusable cells, a nested horizontal UICollectionView and a
/// UIButton, all attached with `TouchDynamics.attach(to:)`.
struct UIKitDemo: View {
    @EnvironmentObject private var tuning: TuningStore

    var body: some View {
        NavigationStack {
            UIKitDemoController(configuration: tuning.configuration)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("UIKit")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct UIKitDemoController: UIViewControllerRepresentable {
    let configuration: TouchDynamicsConfiguration

    func makeUIViewController(context: Context) -> UIKitTableController {
        UIKitTableController(configuration: configuration)
    }

    func updateUIViewController(_ controller: UIKitTableController, context: Context) {
        controller.configuration = configuration
    }
}

final class UIKitTableController: UITableViewController {
    var configuration: TouchDynamicsConfiguration {
        didSet { tableView.reloadData() }
    }
    private let comments = Comment.samples

    init(configuration: TouchDynamicsConfiguration) {
        self.configuration = configuration
        super.init(style: .plain)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(CommentCell.self, forCellReuseIdentifier: "comment")
        tableView.register(CarouselCell.self, forCellReuseIdentifier: "carousel")
        tableView.register(ButtonCell.self, forCellReuseIdentifier: "button")
        tableView.separatorInset = .zero
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { comments.count + 2 }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.row == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "button", for: indexPath) as! ButtonCell
            TouchDynamics.attach(to: cell.button, configuration: configuration)
            return cell
        }
        if indexPath.row == 1 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "carousel", for: indexPath) as! CarouselCell
            cell.configuration = configuration
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "comment", for: indexPath) as! CommentCell
        cell.configure(with: comments[indexPath.row - 2])
        TouchDynamics.attach(to: cell, configuration: configuration)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

final class CommentCell: UITableViewCell {
    private let author = UILabel()
    private let body = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        author.font = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
        body.font = .preferredFont(forTextStyle: .subheadline)
        body.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [author, body])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(with comment: Comment) {
        author.text = "\(comment.author) · \(comment.minutesAgo)m"
        body.text = comment.text
    }
}

final class ButtonCell: UITableViewCell {
    let button = UIButton(type: .system)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        var config = UIButton.Configuration.filled()
        config.title = "UIButton with TouchDynamics"
        config.cornerStyle = .large
        button.configuration = config
        button.addAction(UIAction { [weak button] _ in
            var c = button?.configuration
            c?.title = "Fired at \(Date().formatted(date: .omitted, time: .standard))"
            button?.configuration = c
        }, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            button.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            button.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            button.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

/// A horizontal collection view inside the table: nested scrolling.
final class CarouselCell: UITableViewCell, UICollectionViewDataSource {
    var configuration: TouchDynamicsConfiguration = .default {
        didSet { collectionView.reloadData() }
    }
    private let collectionView: UICollectionView

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 140, height: 100)
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        collectionView.register(TileCell.self, forCellWithReuseIdentifier: "tile")
        collectionView.dataSource = self
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.backgroundColor = .clear
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            collectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            collectionView.heightAnchor.constraint(equalToConstant: 100),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { 12 }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "tile", for: indexPath) as! TileCell
        cell.label.text = "Tile \(indexPath.item + 1)"
        TouchDynamics.attach(to: cell, configuration: configuration)
        return cell
    }
}

final class TileCell: UICollectionViewCell {
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 14
        contentView.layer.cornerCurve = .continuous
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        label.font = .preferredFont(forTextStyle: .headline)
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
