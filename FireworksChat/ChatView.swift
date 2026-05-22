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
            ZStack {
                CyberGridBackground()
                VStack(spacing: 0) {
                    messagesList
                    if let usage = vm.lastUsage {
                        usageBar(usage)
                    }
                    if let err = vm.errorMessage {
                        errorBar(err)
                    }
                    inputBar
                }
            }
            .navigationTitle(vm.currentConversation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(CyberTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingConversations = true }) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(CyberTheme.cyan)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(vm.currentConversation.title)
                        .font(CyberTheme.mono(15, weight: .semibold))
                        .foregroundStyle(CyberTheme.neonGradient)
                        .lineLimit(1)
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
                            .foregroundColor(CyberTheme.magenta)
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
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
        .accentColor(CyberTheme.cyan)
        .tint(CyberTheme.cyan)
    }

    private var canRegenerate: Bool {
        !vm.isLoading && vm.messages.contains(where: { $0.role == .assistant })
    }

    // MARK: - Status bars

    @ViewBuilder
    private func usageBar(_ usage: TokenUsage) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.caption2)
                .foregroundColor(CyberTheme.cyan)
            Text("PROMPT \(usage.prompt) · OUT \(usage.completion) · TOTAL \(usage.total)")
                .font(CyberTheme.mono(10, weight: .medium))
                .foregroundColor(CyberTheme.textSecondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(CyberTheme.surface.opacity(0.6))
        .overlay(Rectangle().frame(height: 1).foregroundColor(CyberTheme.cyan.opacity(0.3)), alignment: .top)
    }

    @ViewBuilder
    private func errorBar(_ err: String) -> some View {
        Text(err)
            .font(CyberTheme.mono(11))
            .foregroundColor(CyberTheme.magenta)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CyberTheme.magenta.opacity(0.08))
            .overlay(
                Rectangle()
                    .frame(width: 2)
                    .foregroundColor(CyberTheme.magenta),
                alignment: .leading
            )
    }

    // MARK: - Messages list

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
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
                        thinkingIndicator
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

    private var thinkingIndicator: some View {
        HStack(spacing: 8) {
            PulseDot(color: CyberTheme.cyan)
            PulseDot(color: CyberTheme.purple, delay: 0.2)
            PulseDot(color: CyberTheme.magenta, delay: 0.4)
            Text("PROCESSING…")
                .font(CyberTheme.mono(11, weight: .semibold))
                .foregroundColor(CyberTheme.textSecondary)
                .tracking(2)
            Spacer()
        }
        .padding(.horizontal)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bolt.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(CyberTheme.neonGradient)
                .shadow(color: CyberTheme.cyan.opacity(0.6), radius: 12)
            Text("TIMA AI")
                .font(CyberTheme.mono(28, weight: .bold))
                .foregroundStyle(CyberTheme.neonGradient)
                .tracking(6)
            Text("Спросите что-нибудь или прикрепите изображение")
                .font(CyberTheme.mono(12))
                .multilineTextAlignment(.center)
                .foregroundColor(CyberTheme.textSecondary)
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
                        .neonGlow(color: CyberTheme.cyan, radius: 4, cornerRadius: 8)
                    Spacer()
                    Button(action: { vm.selectedImage = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(CyberTheme.magenta)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 6)
            }
            HStack(alignment: .bottom, spacing: 10) {
                Button(action: { showingImagePicker = true }) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title2)
                        .foregroundColor(CyberTheme.cyan)
                        .shadow(color: CyberTheme.cyan.opacity(0.6), radius: 4)
                }
                .disabled(vm.isLoading)

                TextField("", text: $vm.inputText, axis: .vertical)
                    .placeholder(when: vm.inputText.isEmpty) {
                        Text("> Введите запрос...")
                            .font(CyberTheme.mono(14))
                            .foregroundColor(CyberTheme.textSecondary.opacity(0.5))
                    }
                    .font(CyberTheme.mono(14))
                    .foregroundColor(CyberTheme.textPrimary)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(CyberTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .neonGlow(color: CyberTheme.cyan.opacity(0.5), radius: 4, lineWidth: 1, cornerRadius: 18)

                if vm.isLoading {
                    Button(action: { vm.cancel() }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(CyberTheme.magenta)
                            .shadow(color: CyberTheme.magenta.opacity(0.8), radius: 8)
                    }
                } else {
                    Button(action: { vm.send() }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(canSend ? CyberTheme.neonGradient : LinearGradient(colors: [.gray, .gray], startPoint: .top, endPoint: .bottom))
                            .shadow(color: canSend ? CyberTheme.cyan.opacity(0.8) : .clear, radius: 8)
                    }
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(CyberTheme.background.opacity(0.95))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(CyberTheme.neonGradient)
                .opacity(0.6),
            alignment: .top
        )
    }

    private var canSend: Bool {
        !vm.isLoading &&
        (!vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.selectedImage != nil)
    }
}

// MARK: - Helpers

/// Pulsing colored dot used in the "thinking" indicator.
struct PulseDot: View {
    let color: Color
    var delay: Double = 0
    @State private var scale: CGFloat = 0.6

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(scale)
            .shadow(color: color.opacity(0.8), radius: 4)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever().delay(delay)) {
                    scale = 1.2
                }
            }
    }
}

extension View {
    /// Adds a placeholder view shown only when `shouldShow` is true.
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0).padding(.leading, 14)
            self
        }
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
                        .neonGlow(color: glowColor, radius: 6, cornerRadius: 12)
                }
                if !message.text.isEmpty || isStreaming {
                    HStack(alignment: .bottom, spacing: 2) {
                        FormattedMessageView(text: message.text)
                            .foregroundColor(CyberTheme.textPrimary)
                        if isStreaming {
                            BlinkingCursor(color: CyberTheme.cyan)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .neonGlow(color: glowColor.opacity(0.7), radius: 6, lineWidth: 1, cornerRadius: 16)
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

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.role == .user {
            CyberTheme.userBubbleGradient
        } else {
            CyberTheme.assistantBubbleGradient
        }
    }

    private var glowColor: Color {
        message.role == .user ? CyberTheme.magenta : CyberTheme.cyan
    }
}

struct BlinkingCursor: View {
    let color: Color
    @State private var visible = true

    var body: some View {
        Text("▍")
            .foregroundColor(color)
            .shadow(color: color.opacity(0.8), radius: 4)
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
            ZStack {
                CyberGridBackground()
                List {
                    ForEach(vm.conversations) { conv in
                        Button {
                            vm.selectConversation(conv.id)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conv.title)
                                    .font(CyberTheme.mono(14, weight: .semibold))
                                    .foregroundColor(conv.id == vm.currentConversationID ? CyberTheme.cyan : CyberTheme.textPrimary)
                                    .lineLimit(1)
                                Text(formatDate(conv.updatedAt))
                                    .font(CyberTheme.mono(10))
                                    .foregroundColor(CyberTheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(
                            (conv.id == vm.currentConversationID
                                ? CyberTheme.surfaceAlt
                                : CyberTheme.surface).opacity(0.7)
                        )
                        .swipeActions {
                            Button(role: .destructive) {
                                vm.deleteConversation(conv.id)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            .navigationTitle("ЧАТЫ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(CyberTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Готово") { dismiss() }
                        .foregroundColor(CyberTheme.cyan)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        vm.newConversation()
                        dismiss()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .foregroundColor(CyberTheme.magenta)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
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
            ZStack {
                CyberGridBackground()
                Form {
                    Section {
                        SecureField("API Key", text: $vm.apiKey)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .font(CyberTheme.mono(13))
                        TextField("Endpoint URL", text: $vm.endpointURL)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .keyboardType(.URL)
                            .font(CyberTheme.mono(13))
                    } header: {
                        Text("API").foregroundColor(CyberTheme.cyan)
                    } footer: {
                        Text("По умолчанию: Fireworks. Можно указать любой OpenAI-совместимый эндпоинт.")
                            .foregroundColor(CyberTheme.textSecondary)
                    }
                    .listRowBackground(CyberTheme.surface.opacity(0.8))

                    Section {
                        TextField("Model ID", text: $vm.model)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .font(CyberTheme.mono(13))
                    } header: {
                        Text("МОДЕЛЬ").foregroundColor(CyberTheme.magenta)
                    } footer: {
                        Text("По умолчанию: kimi-k2p6")
                            .foregroundColor(CyberTheme.textSecondary)
                    }
                    .listRowBackground(CyberTheme.surface.opacity(0.8))

                    Section {
                        TextEditor(text: $vm.systemPrompt)
                            .frame(minHeight: 80)
                            .font(CyberTheme.mono(13))
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                    } header: {
                        Text("СИСТЕМНЫЙ ПРОМПТ").foregroundColor(CyberTheme.cyan)
                    } footer: {
                        Text("Задаёт характер ассистента. Применяется к каждому запросу.")
                            .foregroundColor(CyberTheme.textSecondary)
                    }
                    .listRowBackground(CyberTheme.surface.opacity(0.8))

                    Section {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text(String(format: "%.2f", vm.temperature))
                                .font(CyberTheme.mono(12))
                                .foregroundColor(CyberTheme.cyan)
                        }
                        Slider(value: $vm.temperature, in: 0...2, step: 0.05)
                            .tint(CyberTheme.cyan)

                        HStack {
                            Text("Max tokens")
                            Spacer()
                            Text("\(vm.maxTokens)")
                                .font(CyberTheme.mono(12))
                                .foregroundColor(CyberTheme.magenta)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(vm.maxTokens) },
                                set: { vm.maxTokens = Int($0) }
                            ),
                            in: 256...8192,
                            step: 128
                        )
                        .tint(CyberTheme.magenta)
                    } header: {
                        Text("ПАРАМЕТРЫ ГЕНЕРАЦИИ").foregroundColor(CyberTheme.magenta)
                    }
                    .listRowBackground(CyberTheme.surface.opacity(0.8))

                    Section {
                        Toggle("Искать в интернете", isOn: $vm.webSearchEnabled)
                            .tint(CyberTheme.cyan)
                    } header: {
                        Text("ИНТЕРНЕТ").foregroundColor(CyberTheme.cyan)
                    } footer: {
                        Text("Перед ответом ищется свежий контекст через DuckDuckGo и Wikipedia.")
                            .foregroundColor(CyberTheme.textSecondary)
                    }
                    .listRowBackground(CyberTheme.surface.opacity(0.8))

                    Section {
                        Toggle("Виброотклик", isOn: $vm.hapticsEnabled)
                            .tint(CyberTheme.magenta)
                    } header: {
                        Text("ИНТЕРФЕЙС").foregroundColor(CyberTheme.magenta)
                    }
                    .listRowBackground(CyberTheme.surface.opacity(0.8))

                    Section {
                        Link("Получить API-ключ Fireworks",
                             destination: URL(string: "https://fireworks.ai/account/api-keys")!)
                            .foregroundColor(CyberTheme.cyan)
                    }
                    .listRowBackground(CyberTheme.surface.opacity(0.8))
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            .navigationTitle("НАСТРОЙКИ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(CyberTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                        .foregroundColor(CyberTheme.cyan)
                }
            }
        }
        .preferredColorScheme(.dark)
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
