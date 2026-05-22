import SwiftUI
import UIKit

struct ChatView: View {
    @StateObject private var vm = ChatViewModel()
    @State private var showingImagePicker = false
    @State private var showingSettings = false
    @State private var showingConversations = false
    @State private var showingShare = false
    @State private var shareItems: [Any] = []
    @State private var editingMessageID: UUID?
    @State private var editingText: String = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                messagesList
                if let usage = vm.lastUsage {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle").font(.caption2)
                        Text("Токены: prompt \(usage.prompt) · ответ \(usage.completion) · всего \(usage.total)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .background(Color(.secondarySystemBackground).opacity(0.5))
                }
                if let err = vm.errorMessage {
                    Text(err)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                }
                inputBar
            }
            .navigationTitle(vm.currentConversation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingConversations = true }) {
                        Image(systemName: "line.3.horizontal")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            vm.newConversation()
                        } label: {
                            Label("Новый чат", systemImage: "square.and.pencil")
                        }
                        Button {
                            shareItems = [vm.exportCurrentAsMarkdown()]
                            showingShare = true
                        } label: {
                            Label("Экспорт в Markdown", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            vm.regenerateLast()
                        } label: {
                            Label("Перегенерировать ответ", systemImage: "arrow.clockwise")
                        }
                        .disabled(!canRegenerate)
                        Button(role: .destructive) {
                            vm.clearCurrent()
                        } label: {
                            Label("Очистить чат", systemImage: "trash")
                        }
                        .disabled(vm.messages.isEmpty)
                        Divider()
                        Button {
                            showingSettings = true
                        } label: {
                            Label("Настройки", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: $vm.selectedImage)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(vm: vm)
            }
            .sheet(isPresented: $showingConversations) {
                ConversationListView(vm: vm)
            }
            .sheet(isPresented: $showingShare) {
                ShareSheet(items: shareItems)
            }
            .accentColor(accentColor)
        }
        .navigationViewStyle(.stack)
        .accentColor(accentColor)
    }

    private var accentColor: Color {
        AccentPalette.color(for: vm.accentColorName)
    }

    private var canRegenerate: Bool {
        !vm.isLoading && vm.messages.contains(where: { $0.role == .assistant })
    }

    // MARK: - Messages list

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if vm.messages.isEmpty {
                        emptyState
                    }
                    ForEach(vm.messages) { msg in
                        MessageBubble(
                            message: msg,
                            isStreaming: vm.isLoading && msg.id == vm.messages.last?.id && msg.role == .assistant,
                            onCopy: {
                                UIPasteboard.general.string = msg.text
                                vm.triggerHaptic(.light)
                            },
                            onRegenerate: msg.id == vm.messages.last?.id && msg.role == .assistant
                                ? { vm.regenerateLast() } : nil,
                            onEdit: msg.role == .user
                                ? {
                                    editingMessageID = msg.id
                                    editingText = msg.text
                                } : nil
                        )
                        .id(msg.id)
                    }
                    if vm.isLoading && (vm.messages.last?.role != .assistant || (vm.messages.last?.text.isEmpty ?? true)) {
                        HStack {
                            ProgressView()
                            Text("Думаю…").foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: vm.messages.count) { _ in
                if let last = vm.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: vm.messages.last?.text) { _ in
                if let last = vm.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .alert("Изменить сообщение", isPresented: Binding(
                get: { editingMessageID != nil },
                set: { if !$0 { editingMessageID = nil } }
            )) {
                TextField("Текст", text: $editingText, axis: .vertical)
                Button("Отмена", role: .cancel) {
                    editingMessageID = nil
                }
                Button("Перегенерировать") {
                    applyEdit()
                }
            } message: {
                Text("Текст вашего сообщения будет обновлён, и ассистент сгенерирует ответ заново.")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(accentColor)
            Text("Спросите что-нибудь или прикрепите изображение")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
        .padding(.top, 80)
    }

    private func applyEdit() {
        guard let id = editingMessageID else { return }
        let text = editingText
        editingMessageID = nil
        vm.editAndResend(messageID: id, newText: text)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 6) {
            if let img = vm.selectedImage {
                HStack {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Spacer()
                    Button(action: { vm.selectedImage = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 6)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button(action: { showingImagePicker = true }) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title2)
                        .foregroundColor(accentColor)
                }
                .disabled(vm.isLoading)

                TextField("Сообщение", text: $vm.inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                if vm.isLoading {
                    Button(action: { vm.cancel() }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.red)
                    }
                } else {
                    Button(action: { vm.send() }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(canSend ? accentColor : .gray)
                    }
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    private var canSend: Bool {
        !vm.isLoading &&
        (!vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.selectedImage != nil)
    }
}

// MARK: - Message bubble

struct MessageBubble: View {
    let message: ChatMessage
    let isStreaming: Bool
    let onCopy: () -> Void
    let onRegenerate: (() -> Void)?
    let onEdit: (() -> Void)?

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if let img = message.image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                if !message.text.isEmpty || isStreaming {
                    HStack(alignment: .bottom, spacing: 2) {
                        FormattedMessageView(text: message.text)
                            .foregroundColor(textColor)
                        if isStreaming {
                            BlinkingCursor(color: textColor)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bubbleColor)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .contextMenu {
                        Button {
                            onCopy()
                        } label: {
                            Label("Копировать", systemImage: "doc.on.doc")
                        }
                        if let onRegenerate {
                            Button {
                                onRegenerate()
                            } label: {
                                Label("Перегенерировать", systemImage: "arrow.clockwise")
                            }
                        }
                        if let onEdit {
                            Button {
                                onEdit()
                            } label: {
                                Label("Изменить", systemImage: "pencil")
                            }
                        }
                    }
                }
            }
            if message.role != .user { Spacer(minLength: 20) }
        }
        .padding(.horizontal)
    }

    private var bubbleColor: Color {
        message.role == .user ? Color.accentColor : Color(.secondarySystemBackground)
    }

    private var textColor: Color {
        message.role == .user ? .white : .primary
    }
}

struct BlinkingCursor: View {
    let color: Color
    @State private var visible = true

    var body: some View {
        Text("▍")
            .foregroundColor(color)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever()) {
                    visible.toggle()
                }
            }
    }
}

// MARK: - Conversation list

struct ConversationListView: View {
    @ObservedObject var vm: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(vm.conversations) { conv in
                    Button {
                        vm.selectConversation(conv.id)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(conv.title)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Text(formatDate(conv.updatedAt))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            vm.deleteConversation(conv.id)
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Чаты")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Готово") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        vm.newConversation()
                        dismiss()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var vm: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("API") {
                    SecureField("API Key", text: $vm.apiKey)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    TextField("Endpoint URL", text: $vm.endpointURL)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                    Text("По умолчанию: Fireworks. Можно указать любой OpenAI-совместимый эндпоинт (например, локальный OmniRoute).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Модель") {
                    TextField("Model ID", text: $vm.model)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    Text("По умолчанию: kimi-k2p6")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Системный промпт") {
                    TextEditor(text: $vm.systemPrompt)
                        .frame(minHeight: 80)
                    Text("Задаёт характер ассистента. Применяется к каждому запросу.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Параметры генерации") {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(String(format: "%.2f", vm.temperature))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $vm.temperature, in: 0...2, step: 0.05)

                    HStack {
                        Text("Max tokens")
                        Spacer()
                        Text("\(vm.maxTokens)")
                            .foregroundColor(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(vm.maxTokens) },
                            set: { vm.maxTokens = Int($0) }
                        ),
                        in: 256...8192,
                        step: 128
                    )
                }

                Section("Интернет") {
                    Toggle("Искать в интернете", isOn: $vm.webSearchEnabled)
                    Text("Перед ответом приложение ищет свежий контекст через DuckDuckGo и Wikipedia.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Интерфейс") {
                    Toggle("Виброотклик", isOn: $vm.hapticsEnabled)
                    Picker("Акцентный цвет", selection: $vm.accentColorName) {
                        ForEach(AccentPalette.all, id: \.name) { item in
                            HStack {
                                Circle().fill(item.color).frame(width: 14, height: 14)
                                Text(item.label)
                            }
                            .tag(item.name)
                        }
                    }
                }

                Section {
                    Link("Получить API-ключ Fireworks",
                         destination: URL(string: "https://fireworks.ai/account/api-keys")!)
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Accent palette

enum AccentPalette {
    struct Item {
        let name: String
        let label: String
        let color: Color
    }

    static let all: [Item] = [
        Item(name: "orange", label: "Оранжевый", color: .orange),
        Item(name: "blue", label: "Синий", color: .blue),
        Item(name: "purple", label: "Фиолетовый", color: .purple),
        Item(name: "green", label: "Зелёный", color: .green),
        Item(name: "pink", label: "Розовый", color: .pink),
        Item(name: "red", label: "Красный", color: .red)
    ]

    static func color(for name: String) -> Color {
        all.first(where: { $0.name == name })?.color ?? .orange
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
