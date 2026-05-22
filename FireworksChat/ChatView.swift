import SwiftUI

struct ChatView: View {
    @StateObject private var vm = ChatViewModel()
    @State private var showingImagePicker = false
    @State private var showingSettings = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                messagesList
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
            .navigationTitle("Tima Ai")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { vm.clear() }) {
                        Image(systemName: "trash")
                    }
                    .disabled(vm.messages.isEmpty)
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: $vm.selectedImage)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(apiKey: $vm.apiKey, model: $vm.model, webSearchEnabled: $vm.webSearchEnabled)
            }
        }
        .navigationViewStyle(.stack)
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if vm.messages.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 40))
                                .foregroundColor(.orange)
                            Text("Спросите что-нибудь или прикрепите изображение")
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                        }
                        .padding(.top, 80)
                    }
                    ForEach(vm.messages) { msg in
                        MessageBubble(message: msg)
                            .id(msg.id)
                    }
                    if vm.isLoading {
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
        }
    }

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
                        .foregroundColor(.accentColor)
                }

                TextField("Сообщение", text: $vm.inputText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                Button(action: { vm.send() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(canSend ? .accentColor : .gray)
                }
                .disabled(!canSend)
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

struct MessageBubble: View {
    let message: ChatMessage

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
                if !message.text.isEmpty {
                    FormattedMessageView(text: message.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundColor(textColor)
                        .background(bubbleColor)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
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

struct SettingsView: View {
    @Binding var apiKey: String
    @Binding var model: String
    @Binding var webSearchEnabled: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Fireworks API") {
                    SecureField("API Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                Section("Модель") {
                    TextField("Model ID", text: $model)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    Text("По умолчанию: kimi-k2p6")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Section("Интернет") {
                    Toggle("Искать в интернете", isOn: $webSearchEnabled)
                    Text("Перед ответом приложение ищет свежий контекст через DuckDuckGo и Wikipedia, затем передает найденные ссылки модели.")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
