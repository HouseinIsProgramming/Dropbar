import SwiftUI

struct PopoverView: View {
    let items: [MenuBarItem]
    let onItemClicked: (MenuBarItem) -> Void

    @State private var hoveredID: CGWindowID?

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
                .padding(4)
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
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 18)
                } else {
                    Image(systemName: "questionmark.square")
                        .font(.system(size: 14))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
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
