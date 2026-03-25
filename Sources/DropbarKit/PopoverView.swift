import SwiftUI

class DropbarViewModel: ObservableObject {
    @Published var items: [MenuBarItem] = []
    @Published var hiddenIDs: Set<CGWindowID> = []

    func toggleHidden(_ item: MenuBarItem) {
        if hiddenIDs.contains(item.id) {
            hiddenIDs.remove(item.id)
        } else {
            hiddenIDs.insert(item.id)
        }
    }

    var hiddenItems: [MenuBarItem] {
        items.filter { hiddenIDs.contains($0.id) }
            .sorted { $0.frame.origin.x < $1.frame.origin.x }
    }

    var visibleItems: [MenuBarItem] {
        items.filter { !hiddenIDs.contains($0.id) }
            .sorted { $0.frame.origin.x < $1.frame.origin.x }
    }
}

struct DropbarContentView: View {
    @ObservedObject var viewModel: DropbarViewModel
    let onItemClicked: (MenuBarItem) -> Void

    @State private var hoveredID: CGWindowID?

    var body: some View {
        if viewModel.items.isEmpty {
            Text("No menu bar items found.")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        } else {
            HStack(spacing: 0) {
                ForEach(viewModel.hiddenItems) { item in
                    itemButton(item, isHidden: true)
                }

                if !viewModel.hiddenItems.isEmpty {
                    divider
                }

                ForEach(viewModel.visibleItems) { item in
                    itemButton(item, isHidden: false)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .animation(.easeInOut(duration: 0.15), value: viewModel.hiddenIDs)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.2))
            .frame(width: 1, height: NSStatusBar.system.thickness - 4)
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func itemButton(_ item: MenuBarItem, isHidden: Bool) -> some View {
        Button {
            if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
                viewModel.toggleHidden(item)
            } else {
                onItemClicked(item)
            }
        } label: {
            Group {
                if let image = item.image {
                    Image(nsImage: image)
                        .interpolation(.high)
                } else {
                    Image(systemName: "questionmark.square")
                        .font(.system(size: 16))
                        .frame(width: 24, height: NSStatusBar.system.thickness)
                }
            }
            .opacity(isHidden ? 0.4 : 1.0)
            .padding(.horizontal, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hoveredID == item.id ? Color.primary.opacity(0.1) : .clear)
            )
        }
        .buttonStyle(.plain)
        .help(isHidden ? "⌥+click to show" : "⌥+click to hide")
        .onHover { hovering in
            hoveredID = hovering ? item.id : nil
        }
    }
}
