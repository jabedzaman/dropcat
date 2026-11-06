import SwiftUI

struct TransferBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.transfers.isEmpty {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Text("Transfers").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if model.transfers.contains(where: { $0.state != .running }) {
                        Button("Clear") { model.clearFinishedTransfers() }.buttonStyle(.plain).font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 10).padding(.top, 6)
                ScrollView {
                    VStack(spacing: 6) { ForEach(model.transfers.prefix(6)) { t in TransferRow(item: t, onDismiss: { model.dismiss(t) }) } }.padding(10)
                }.frame(maxHeight: 140)
            }.background(.bar)
        }
    }
}

struct TransferRow: View {
    let item: TransferItem
    let onDismiss: () -> Void
    var body: some View {
        HStack {
            Image(systemName: item.isUpload ? "arrow.up.circle" : "arrow.down.circle")
            Text(item.name).lineLimit(1).frame(width: 200, alignment: .leading)
            ProgressView(value: item.progress).tint(item.state == .failed ? .red : .accentColor)
            Text(item.detail).font(.caption).foregroundStyle(.secondary).frame(width: 140, alignment: .trailing).lineLimit(1)
            Button(action: onDismiss) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.plain)
                .help(item.state == .running ? "Cancel transfer" : "Remove from list")
        }
    }
}
