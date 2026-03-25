import SwiftUI

struct PopoverView: View {
    let items: [MenuBarItem]
    let onItemClicked: (MenuBarItem) -> Void

    var body: some View {
        Group {
            if items.isEmpty {
                Text("No hidden items")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                HStack(spacing: 2) {
                    ForEach(items) { item in
                        Button(action: { onItemClicked(item) }) {
                            if let image = item.image {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 22)
                            } else {
                                Image(systemName: "questionmark.square")
                                    .frame(height: 22)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(item.ownerName)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .cornerRadius(4)
                    }
                }
            }
        }
        .padding(6)
    }
}
