import SwiftUI

struct DropbarContentView: View {
    let items: [MenuBarItem]
    let hiddenCount: Int
    let onItemClicked: (MenuBarItem) -> Void
    let onItemOptionClicked: (Int) -> Void

    @State private var hoveredID: CGWindowID?

    var body: some View {
        if items.isEmpty {
            Text("No menu bar items found.")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        } else {
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    // Insert divider between hidden and visible groups
                    if index == hiddenCount && hiddenCount > 0 {
                        divider
                    }

                    itemButton(item, index: index, isHidden: index < hiddenCount)
                }

                // Divider at the end if everything is hidden
                if hiddenCount == items.count && hiddenCount > 0 {
                    divider
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.2))
            .frame(width: 1, height: NSStatusBar.system.thickness - 4)
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func itemButton(_ item: MenuBarItem, index: Int, isHidden: Bool) -> some View {
        Button {
            if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
                onItemOptionClicked(index)
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
            .opacity(isHidden ? 0.45 : 1.0)
            .padding(.horizontal, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hoveredID == item.id ? Color.primary.opacity(0.1) : .clear)
            )
        }
        .buttonStyle(.plain)
        .help(isHidden ? "\(item.ownerName) (⌥ click to show)" : "\(item.ownerName) (⌥ click to hide)")
        .onHover { hovering in
            hoveredID = hovering ? item.id : nil
        }
    }
}
