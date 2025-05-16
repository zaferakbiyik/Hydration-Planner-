import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

// MARK: - Model
struct WaterEntry: Identifiable, Codable {
    var id: String = UUID().uuidString
    var date: Date
    var amount: Double
    var note: String
}

// MARK: - XML Serialization/Deserialization
class XMLManager {
    static let shared = XMLManager()
    
    private let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private let fileName = "waterEntries.xml"
    
    func saveEntries(_ entries: [WaterEntry]) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        
        do {
            let data = try encoder.encode(entries)
            let fileURL = documentsDirectory.appendingPathComponent(fileName)
            try data.write(to: fileURL)
        } catch {
            print("Error saving entries: \(error)")
        }
    }
    
    func loadEntries() -> [WaterEntry] {
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = PropertyListDecoder()
            return try decoder.decode([WaterEntry].self, from: data)
        } catch {
            print("Error loading entries: \(error)")
            return []
        }
    }
    
    func exportEntries(to url: URL) -> Bool {
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.copyItem(at: fileURL, to: url)
            return true
        } catch {
            print("Error exporting entries: \(error)")
            return false
        }
    }
}

// MARK: - Notification Service
class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    print("🔔 Bildirim izni verildi")
                    self.notificationStatus = .authorized
                    
                    // Kullanıcı arayüzü için bildirim kategorileri oluştur
                    self.setupNotificationCategories()
                } else if let error = error {
                    print("❌ Bildirim izni hatası: \(error)")
                    self.notificationStatus = .denied
                } else {
                    print("❌ Bildirim izni reddedildi")
                    self.notificationStatus = .denied
                }
            }
        }
    }
    
    // Bildirim kategorileri oluştur (daha etkileşimli bildirimler için)
    private func setupNotificationCategories() {
        // "İç" aksiyonu
        let drinkAction = UNNotificationAction(
            identifier: "DRINK_ACTION",
            title: "İçtim",
            options: .foreground
        )
        
        // "Ertele" aksiyonu
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_ACTION",
            title: "30 Dakika Ertele",
            options: .foreground
        )
        
        // Su içme kategorisi
        let waterCategory = UNNotificationCategory(
            identifier: "WATER_REMINDER",
            actions: [drinkAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Kategoriyi kaydet
        UNUserNotificationCenter.current().setNotificationCategories([waterCategory])
    }
    
    func checkAuthorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationStatus = settings.authorizationStatus
                print("🔔 Bildirim izin durumu: \(settings.authorizationStatus.rawValue)")
                print("🔔 Bildirim alertStyle: \(settings.alertStyle.rawValue)")
                print("🔔 Bildirim soundSetting: \(settings.soundSetting.rawValue)")
                completion(settings.authorizationStatus)
            }
        }
    }
    
    func scheduleNotification(at date: Date, amount: Double, completion: @escaping (Bool) -> Void) {
        // Bildirimlerin izin durumunu kontrol et
        checkAuthorizationStatus { status in
            if status == .authorized {
                let content = UNMutableNotificationContent()
                content.title = "Su İçme Zamanı!"
                content.body = "Hedefinize ulaşmak için \(Int(amount)) ml su içmeyi unutmayın."
                content.sound = UNNotificationSound.default
                content.badge = 1
                content.categoryIdentifier = "WATER_REMINDER"
                
                // Debug bilgisi
                print("🔔 Bildirim içeriği oluşturuldu")
                
                // Kullanıcının seçtiği tarihten saat ve dakika değerlerini al
                let calendar = Calendar.current
                var dateComponents = DateComponents()
                dateComponents.hour = calendar.component(.hour, from: date)
                dateComponents.minute = calendar.component(.minute, from: date)
                
                // Test amaçlı: Şu andan 10 saniye sonrası için test bildirimi
                let testTrigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
                
                // Normal tekrarlayan bildirim ayarı
                let dailyTrigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                
                // Benzersiz bildirim ID'si oluştur
                let identifier = "water-reminder-\(UUID().uuidString)"
                
                // TEST: İlk olarak test bildirimi gönder (10 saniye sonra)
                let testRequest = UNNotificationRequest(identifier: "test-\(identifier)", content: content, trigger: testTrigger)
                
                // Önce mevcut bildirimleri temizle
                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                
                UNUserNotificationCenter.current().add(testRequest) { error in
                    if let error = error {
                        print("❌ TEST bildirimi eklenirken hata: \(error)")
                        completion(false)
                    } else {
                        print("✅ TEST bildirimi 10 saniye sonra gönderilecek")
                        
                        // Asıl günlük tekrarlayan bildirimi ekle
                        let dailyRequest = UNNotificationRequest(identifier: identifier, content: content, trigger: dailyTrigger)
                        
                        UNUserNotificationCenter.current().add(dailyRequest) { error in
                            DispatchQueue.main.async {
                                if let error = error {
                                    print("❌ Bildirim planlama hatası: \(error)")
                                    completion(false)
                                } else {
                                    print("✅ Bildirim başarıyla planlandı: ID=\(identifier)")
                                    print("🕒 Bildirim zamanı: \(dateComponents.hour ?? 0):\(dateComponents.minute ?? 0)")
                                    
                                    // Tüm planlanmış bildirimleri debug için listele
                                    self.listAllScheduledNotifications()
                                    completion(true)
                                }
                            }
                        }
                    }
                }
            } else {
                print("❌ Bildirim izni yok. Mevcut durum: \(status.rawValue)")
                completion(false)
            }
        }
    }
    
    // Debug: Tüm planlanmış bildirimleri listele
    func listAllScheduledNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            print("📋 Planlanmış bildirimler (\(requests.count)):")
            for (index, request) in requests.enumerated() {
                print("  \(index+1). ID: \(request.identifier)")
                
                if let trigger = request.trigger as? UNCalendarNotificationTrigger {
                    print("     Tür: Takvim bazlı")
                    print("     Tetikleme zamanı: \(trigger.dateComponents)")
                    print("     Tekrarlıyor mu: \(trigger.repeats)")
                    
                    if let nextTriggerDate = trigger.nextTriggerDate() {
                        print("     Sonraki tetikleme: \(nextTriggerDate)")
                    }
                } else if let trigger = request.trigger as? UNTimeIntervalNotificationTrigger {
                    print("     Tür: Zaman aralığı")
                    print("     Aralık: \(trigger.timeInterval) saniye")
                    print("     Tekrarlıyor mu: \(trigger.repeats)")
                    
                    if let nextTriggerDate = trigger.nextTriggerDate() {
                        print("     Sonraki tetikleme: \(nextTriggerDate)")
                    }
                }
                
                print("     Başlık: \(request.content.title)")
                print("     Mesaj: \(request.content.body)")
                print("     Ses: \(request.content.sound != nil ? "Var" : "Yok")")
                print("     Rozet: \(request.content.badge ?? 0)")
                print("")
            }
        }
    }
    
    func getPendingNotifications(completion: @escaping ([UNNotificationRequest]) -> Void) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            DispatchQueue.main.async {
                completion(requests)
            }
        }
    }
    
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        print("🧹 Tüm bildirimler iptal edildi")
    }
    
    // Uygulama ön planda iken bildirimlerin gösterilmesi için
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}

// MARK: - Data Manager
class WaterDataManager: ObservableObject {
    static let shared = WaterDataManager()
    
    @Published var entries: [WaterEntry] = []
    @Published var searchKeyword: String = ""
    @Published var selectedDate: Date = Date()
    
    var filteredEntries: [WaterEntry] {
        if !searchKeyword.isEmpty {
            return entries.filter { $0.note.lowercased().contains(searchKeyword.lowercased()) }
        } else {
            let calendar = Calendar.current
            return entries.filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
        }
    }
    
    init() {
        loadEntries()
    }
    
    func loadEntries() {
        entries = XMLManager.shared.loadEntries().sorted(by: { $0.date > $1.date })
    }
    
    func saveEntries() {
        XMLManager.shared.saveEntries(entries)
    }
    
    func addEntry(_ entry: WaterEntry) {
        entries.append(entry)
        entries.sort(by: { $0.date > $1.date })
        saveEntries()
    }
    
    func updateEntry(_ entry: WaterEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
            saveEntries()
        }
    }
    
    func removeEntry(withId id: String) {
        entries.removeAll { $0.id == id }
        saveEntries()
    }
    
    func exportEntries(to url: URL) -> Bool {
        return XMLManager.shared.exportEntries(to: url)
    }
}

// MARK: - App
@main
struct WaterTrackerApp: App {
    @StateObject private var dataManager = WaterDataManager.shared
    
    init() {
        NotificationService.shared.requestAuthorization()
        UNUserNotificationCenter.current().delegate = NotificationService.shared
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataManager)
        }
    }
}

// MARK: - Views
struct ContentView: View {
    @EnvironmentObject private var dataManager: WaterDataManager
    @State private var isAddViewPresented = false
    @State private var isExportViewPresented = false
    @State private var isReminderManagementPresented = false
    @State private var editingEntry: WaterEntry?
    
    var body: some View {
        NavigationView {
            VStack {
                // Search Bar
                SearchBar(text: $dataManager.searchKeyword)
                
                // Calendar
                DatePicker("Tarih Seçin", selection: $dataManager.selectedDate, displayedComponents: .date)
                    .datePickerStyle(GraphicalDatePickerStyle())
                    .padding()
                
                // Entry List
                List {
                    ForEach(dataManager.filteredEntries) { entry in
                        WaterEntryRow(entry: entry)
                            .onTapGesture {
                                editingEntry = entry
                            }
                    }
                    .onDelete(perform: deleteItems)
                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationTitle("Su Tüketimi")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button(action: {
                            isExportViewPresented = true
                        }) {
                            Label("Dışa Aktar", systemImage: "square.and.arrow.up")
                        }
                        
                        Button(action: {
                            isReminderManagementPresented = true
                        }) {
                            Label("Hatırlatıcıları Yönet", systemImage: "bell")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        isAddViewPresented = true
                    }) {
                        Label("Ekle", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddViewPresented) {
                AddEditView()
            }
            .sheet(item: $editingEntry) { entry in
                AddEditView(entry: entry)
            }
            .sheet(isPresented: $isReminderManagementPresented) {
                ReminderManagementView()
            }
            .fileExporter(
                isPresented: $isExportViewPresented,
                document: WaterTrackerDocument(),
                contentType: .xml,
                defaultFilename: "su_tuketimi"
            ) { result in
                switch result {
                case .success(let url):
                    print("Exported to \(url)")
                case .failure(let error):
                    print("Export failed: \(error)")
                }
            }
        }
    }
    
    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let entry = dataManager.filteredEntries[index]
            dataManager.removeEntry(withId: entry.id)
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            TextField("Notlarda ara...", text: $text)
                .padding(7)
                .padding(.horizontal, 25)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .overlay(
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 8)
                        
                        if !text.isEmpty {
                            Button(action: {
                                text = ""
                            }) {
                                Image(systemName: "multiply.circle.fill")
                                    .foregroundColor(.gray)
                                    .padding(.trailing, 8)
                            }
                        }
                    }
                )
                .padding(.horizontal, 10)
        }
        .padding(.top, 10)
    }
}

struct WaterEntryRow: View {
    let entry: WaterEntry
    
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                Text("\(Int(entry.amount)) ml")
                    .font(.headline)
                
                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            Text(entry.date, style: .time)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 5)
    }
}

struct AddEditView: View {
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var dataManager: WaterDataManager
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    @State private var date: Date
    @State private var amount: String = ""
    @State private var note: String = ""
    @State private var reminderEnabled: Bool = false
    @State private var reminderTime: Date = Date()
    
    private var isEditing: Bool
    private var entryId: String
    
    init(entry: WaterEntry? = nil) {
        let isEditing = entry != nil
        self._date = State(initialValue: entry?.date ?? Date())
        self._amount = State(initialValue: entry != nil ? "\(Int(entry!.amount))" : "")
        self._note = State(initialValue: entry?.note ?? "")
        self.isEditing = isEditing
        self.entryId = entry?.id ?? UUID().uuidString
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Tarih ve Saat")) {
                    DatePicker("", selection: $date)
                        .datePickerStyle(GraphicalDatePickerStyle())
                        .labelsHidden()
                }
                
                Section(header: Text("Miktar (ml)")) {
                    TextField("Örn: 250", text: $amount)
                        .keyboardType(.numberPad)
                }
                
                Section(header: Text("Not")) {
                    TextEditor(text: $note)
                        .frame(minHeight: 100)
                }
                
                Section {
                    Toggle("Hatırlatıcı Ekle", isOn: $reminderEnabled)
                    
                    if reminderEnabled {
                        DatePicker("Hatırlatma Zamanı", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    }
                }
                
                Section {
                    Button(action: saveEntry) {
                        HStack {
                            Spacer()
                            Text(isEditing ? "Güncelle" : "Kaydet")
                                .foregroundColor(.white)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.blue)
                    .disabled(amount.isEmpty)
                }
            }
            .navigationTitle(isEditing ? "Düzenle" : "Yeni Kayıt")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("İptal") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("Tamam"))
                )
            }
            .onAppear {
                // Bildirimlerin izin durumunu kontrol et
                NotificationService.shared.checkAuthorizationStatus { status in
                    if status != .authorized {
                        alertTitle = "Bildirim İzni"
                        alertMessage = "Hatırlatıcılar için bildirim izinlerini etkinleştirmeniz gerekiyor. Lütfen ayarlardan izin verin."
                        showAlert = true
                    }
                }
            }
        }
    }
    
    private func saveEntry() {
        guard let amountValue = Double(amount) else { return }
        
        let entry = WaterEntry(
            id: entryId,
            date: date,
            amount: amountValue,
            note: note
        )
        
        if isEditing {
            dataManager.updateEntry(entry)
        } else {
            dataManager.addEntry(entry)
        }
        
        if reminderEnabled {
            NotificationService.shared.scheduleNotification(at: reminderTime, amount: amountValue) { success in
                if success {
                    alertTitle = "Hatırlatıcı Eklendi"
                    alertMessage = "Her gün \(reminderTime.formatted(date: .omitted, time: .shortened)) saatinde \(Int(amountValue)) ml su içmeniz için hatırlatılacak."
                } else {
                    alertTitle = "Hatırlatıcı Eklenemedi"
                    alertMessage = "Hatırlatıcı eklenirken bir sorun oluştu. Lütfen bildirim izinlerini kontrol edin."
                }
                showAlert = true
            }
        }
        
        presentationMode.wrappedValue.dismiss()
    }
}

// MARK: - Hatırlatıcı Yönetim Görünümü
struct ReminderManagementView: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var pendingNotifications: [UNNotificationRequest] = []
    @State private var isLoading = true
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Yükleniyor...")
                } else if pendingNotifications.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("Ayarlanmış Hatırlatıcı Yok")
                            .font(.headline)
                        Text("Yeni bir hatırlatıcı eklemek için su tüketimi eklerken 'Hatırlatıcı Ekle' seçeneğini kullanabilirsiniz.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(pendingNotifications, id: \.identifier) { notification in
                            let trigger = notification.trigger as? UNCalendarNotificationTrigger
                            let components = trigger?.dateComponents
                            let time = formatTime(hour: components?.hour, minute: components?.minute)
                            let body = notification.content.body
                            
                            VStack(alignment: .leading, spacing: 5) {
                                Text("⏰ Her gün \(time)")
                                    .font(.headline)
                                Text(body)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 5)
                        }
                        .onDelete(perform: deleteNotification)
                    }
                }
            }
            .navigationTitle("Hatırlatıcılar")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Kapat") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        NotificationService.shared.cancelAllNotifications()
                        alertTitle = "Hatırlatıcılar Temizlendi"
                        alertMessage = "Tüm hatırlatıcılar başarıyla silindi."
                        showAlert = true
                        loadNotifications()
                    }) {
                        Text("Tümünü Temizle")
                    }
                    .disabled(pendingNotifications.isEmpty)
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("Tamam"))
                )
            }
            .onAppear {
                loadNotifications()
            }
        }
    }
    
    private func loadNotifications() {
        isLoading = true
        NotificationService.shared.getPendingNotifications { notifications in
            pendingNotifications = notifications
            isLoading = false
        }
    }
    
    private func deleteNotification(at offsets: IndexSet) {
        for index in offsets {
            let notification = pendingNotifications[index]
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notification.identifier])
            print("Notification with ID \(notification.identifier) removed")
        }
        loadNotifications()
    }
    
    private func formatTime(hour: Int?, minute: Int?) -> String {
        let hourValue = hour ?? 0
        let minuteValue = minute ?? 0
        return String(format: "%02d:%02d", hourValue, minuteValue)
    }
}

// MARK: - Export Document
struct WaterTrackerDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.xml] }

    init() {}
    
    init(configuration: ReadConfiguration) throws {}
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("waterEntries.xml")
        return try FileWrapper(url: fileURL)
    }
}

// MARK: - UTType Extension
extension UTType {
    static let xml = UTType(exportedAs: "public.xml")
}
