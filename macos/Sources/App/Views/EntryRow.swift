import SwiftUI
import AppKit
import BypassCore

/// Строка списка исключений: иконка, адрес, копирование, редактирование (для доменов и IP), удаление.
struct EntryRow: View {
    @Environment(AppModel.self) private var model
    let entry: Entry

    @State private var editing = false
    @State private var text = ""
    @State private var error: String?
    @State private var copied = false
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                EntryIcon(entry: entry)
                if editing { editor } else { display }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: Обычный режим

    private var display: some View {
        Group {
            // Копирование и правка нужны только для адресов; у приложений доступно лишь удаление.
            if entry.kind == .host {
                HStack(spacing: 4) {
                    Text(entry.value).textSelection(.enabled)
                    Button(action: copy) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .foregroundStyle(copied ? Color.green : Color.secondary)
                    }
                    .buttonStyle(IconButtonStyle())
                    .help("Скопировать")
                }
                Spacer()
                Button(action: beginEdit) {
                    Image(systemName: "pencil").foregroundStyle(.secondary)
                }
                .buttonStyle(IconButtonStyle())
                .help("Изменить адрес")
            } else {
                Text(entry.value)
                Spacer()
            }
            Button { confirmingDelete = true } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .buttonStyle(IconButtonStyle())
            .help("Удалить")
        }
        .alert("Вы уверены, что хотите удалить \(entry.value)?", isPresented: $confirmingDelete) {
            Button("Удалить", role: .destructive) { model.remove(entry) }
            Button("Отмена", role: .cancel) {}
        }
    }

    // MARK: Редактирование

    private var editor: some View {
        Group {
            TextField("", text: $text, prompt: Text("example.com, 1.2.3.4 или 10.0.0.0/8"))
                .labelsHidden()
                .bordered(autofocus: true)
                .onSubmit(save)
                .onExitCommand(perform: cancel)
            Button(action: save) { Image(systemName: "checkmark").foregroundStyle(Color.green) }
                .buttonStyle(IconButtonStyle())
                .help("Сохранить")
            Button(action: cancel) { Image(systemName: "xmark").foregroundStyle(.secondary) }
                .buttonStyle(IconButtonStyle())
                .help("Отмена")
        }
    }

    // MARK: Действия

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.value, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2)) // на 20% быстрее прежних 1,5 с
            copied = false
        }
    }

    private func beginEdit() {
        text = entry.value
        error = nil
        editing = true
    }

    private func save() {
        if let message = model.updateHost(entry, to: text) {
            error = message
        } else {
            error = nil
            editing = false
        }
    }

    private func cancel() {
        error = nil
        editing = false
    }
}

/// Кнопка-иконка с подсветкой при наведении и нажатии.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        IconButtonContent(configuration: configuration)
    }

    private struct IconButtonContent: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.20 : (hovering ? 0.12 : 0)))
                )
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.1), value: hovering)
        }
    }
}
