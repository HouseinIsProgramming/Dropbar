import SwiftUI

struct PopoverView: View {
    let items: [MenuBarItem]
    let onItemClicked: (MenuBarItem) -> Void

    @State private var hoveredID: CGWindowID?

    private var menuBarHeight: CGFloat {
        NSStatusBar.system.thickness
    }

    var body: some View {
        Group {
            if items.isEmpty {
                Text("No hidden items.\nCMD+drag menu bar icons left of │ to hide them.")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 220)
            } else {
                HStack(spacing: 0) {
                    ForEach(items) { item in
                        itemButton(item)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func itemButton(_ item: MenuBarItem) -> some View {
        Button {
            onItemClicked(item)
        } label: {
            Group {
                if let image = item.image {
                    // Render at the image's natural point size (= menu bar size).
                    // The NSImage was created with size = pixels / scaleFactor,
                    // so it already has the correct dimensions.
                    Image(nsImage: image)
                        .interpolation(.high)
                } else {
                    Image(systemName: "questionmark.square")
                        .font(.system(size: 16))
                        .frame(width: 24, height: menuBarHeight)
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
