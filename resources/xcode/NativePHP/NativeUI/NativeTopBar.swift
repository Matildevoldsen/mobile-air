import SwiftUI
import UIKit

/// iOS-style Top Navigation Bar using native UINavigationBar
struct NativeTopBar: UIViewRepresentable {
    @ObservedObject var uiState = NativeUIState.shared
    let onNavigate: (String) -> Void

    func makeUIView(context: Context) -> UINavigationBar {
        let navigationBar = UINavigationBar()

        // Configure appearance
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear

        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.isTranslucent = true
        navigationBar.backgroundColor = .clear

        // Create navigation item
        let navItem = UINavigationItem()
        navigationBar.items = [navItem]

        // Set coordinator as delegate
        navigationBar.delegate = context.coordinator

        // Ensure layout margins respect safe area for button positioning
        // The bar background will extend full width, but buttons will be inset
        if #available(iOS 11.0, *) {
            navigationBar.insetsLayoutMarginsFromSafeArea = true
        }

        return navigationBar
    }

    func updateUIView(_ navigationBar: UINavigationBar, context: Context) {
        guard let topBarData = uiState.topBarData,
              let navItem = navigationBar.items?.first else { return }

        let resolvedTextColor = topBarData.textColor.flatMap { UIColor(hex: $0) } ?? UIColor.label

        // Update title
        if let subtitle = topBarData.subtitle {
            // Create attributed title with subtitle
            let titleLabel = UILabel()
            titleLabel.numberOfLines = 2
            titleLabel.textAlignment = .center

            let titleText = NSMutableAttributedString()
            titleText.append(NSAttributedString(
                string: topBarData.title + "\n",
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .headline),
                    .foregroundColor: resolvedTextColor
                ]
            ))
            titleText.append(NSAttributedString(
                string: subtitle,
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline),
                    .foregroundColor: resolvedTextColor.withAlphaComponent(0.7)
                ]
            ))

            titleLabel.attributedText = titleText
            titleLabel.sizeToFit()
            navItem.titleView = titleLabel
        } else {
            navItem.titleView = nil
            navItem.title = topBarData.title
        }

        // Update left bar button (navigation icon)
        if topBarData.showNavigationIcon == true {
            let button = UIBarButtonItem(
                image: UIImage(systemName: "line.3.horizontal"),
                style: .plain,
                target: context.coordinator,
                action: #selector(Coordinator.menuTapped)
            )
            navItem.leftBarButtonItem = button
        } else {
            navItem.leftBarButtonItem = nil
        }

        // Update right bar buttons (actions)
        if let actions = topBarData.children, !actions.isEmpty {
            var barButtonItems: [UIBarButtonItem] = []

            for action in actions {
                let image = !action.data.icon.isEmpty ? UIImage(systemName: getIconForName(action.data.icon)) : nil
                context.coordinator.actionUrls[action.data.id] = action.data.url

                if action.data.showLabel == true && !action.data.label.isEmpty {
                    let button = UIButton(type: .system)
                    var configuration = UIButton.Configuration.plain()
                    configuration.title = action.data.label
                    configuration.image = image
                    configuration.imagePlacement = .leading
                    configuration.imagePadding = image == nil ? 0 : 6
                    configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 4)
                    configuration.baseForegroundColor = resolvedTextColor
                    button.configuration = configuration
                    button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
                    button.titleLabel?.lineBreakMode = .byTruncatingTail
                    button.accessibilityLabel = action.data.label
                    button.accessibilityIdentifier = action.data.id
                    button.addTarget(
                        context.coordinator,
                        action: #selector(Coordinator.actionButtonTapped(_:)),
                        for: .touchUpInside
                    )
                    barButtonItems.append(UIBarButtonItem(customView: button))
                    continue
                }

                let button: UIBarButtonItem
                if let image {
                    button = UIBarButtonItem(
                        image: image,
                        style: .plain,
                        target: context.coordinator,
                        action: #selector(Coordinator.actionTapped(_:))
                    )
                } else {
                    button = UIBarButtonItem(
                        title: action.data.label,
                        style: .plain,
                        target: context.coordinator,
                        action: #selector(Coordinator.actionTapped(_:))
                    )
                }

                button.accessibilityLabel = action.data.label
                button.accessibilityIdentifier = action.data.id
                barButtonItems.append(button)
            }

            navItem.rightBarButtonItems = barButtonItems
        } else {
            navItem.rightBarButtonItems = nil
        }

        // Update appearance with custom colors
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.shadowColor = .clear

        if let bgColorHex = topBarData.backgroundColor,
           let bgColor = UIColor(hex: bgColorHex) {
            appearance.backgroundColor = bgColor
        } else {
            appearance.backgroundColor = .clear
        }

        if let textColorHex = topBarData.textColor,
           let textColor = UIColor(hex: textColorHex) {
            appearance.titleTextAttributes = [.foregroundColor: textColor]
            appearance.largeTitleTextAttributes = [.foregroundColor: textColor]
            // Also set the button tint color to match
            navigationBar.tintColor = textColor
        } else {
            // Reset to default if no color specified
            navigationBar.tintColor = nil
        }

        // Apply appearance
        navigationBar.isTranslucent = true
        navigationBar.backgroundColor = .clear
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(uiState: uiState, onNavigate: onNavigate)
    }

    class Coordinator: NSObject, UINavigationBarDelegate {
        let uiState: NativeUIState
        let onNavigate: (String) -> Void
        var actionUrls: [String: String] = [:]

        init(uiState: NativeUIState, onNavigate: @escaping (String) -> Void) {
            self.uiState = uiState
            self.onNavigate = onNavigate
        }

        @objc func menuTapped() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

            if uiState.hasSideNav() {
                withAnimation(.easeInOut(duration: 0.3)) {
                    uiState.openSidebar()
                }

                return
            }

            onNavigate("/native/open-sidebar")
        }

        @objc func actionTapped(_ sender: UIBarButtonItem) {
            guard let actionId = sender.accessibilityIdentifier,
                  let url = actionUrls[actionId] else {
                return
            }

            // Navigate to the URL using the proper navigation callback
            onNavigate(url)
        }

        @objc func actionButtonTapped(_ sender: UIButton) {
            guard let actionId = sender.accessibilityIdentifier,
                  let url = actionUrls[actionId] else {
                return
            }

            onNavigate(url)
        }
    }
}
