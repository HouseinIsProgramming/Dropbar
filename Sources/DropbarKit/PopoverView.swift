import SwiftUI

struct DropbarContentView: View {
    let items: [MenuBarItem]
    let onItemClicked: (MenuBarItem) -> Void

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
                ForEach(items) { item in
                    itemButton(item)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func itemButton(_ item: MenuBarItem) -> some View {
        Button {
            onItemClicked(item)
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
            .padding(.horizontal, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hoveredID == item.id ? Color.primary.opacity(0.1) : .clear)
            )
        }
        .buttonStyle(.plain)
        .help(item.ownerName)
        .onHover { hovering in
            hoveredID = hovering ? item.id : nil
        }
    }
}
