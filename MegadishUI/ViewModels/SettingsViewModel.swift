import Foundation
import Combine

class SettingsViewModel: ObservableObject {
    // Access Point Settings
    @Published var accessPointName: String = "Megadish" {
        didSet { validateSettings() }
    }
    
    @Published var accessPointPassword: String = "test1234" {
        didSet { validateSettings() }
    }
    
    @Published var selectedChannel: Int = 8
    @Published var transmitPower: Int = 3
    
    // Device Information
    @Published var firmwareVersion: String = "1.0.0"
    @Published var deviceID: String = "MD-000000000000"
    
    // Saved Networks
    @Published var savedNetworks: [SavedNetwork] = []
    
    // UI State
    @Published var isLoading = false
    @Published var statusMessage = ""
    @Published var showAlert = false
    @Published var alertMessage = ""
    
    // Validation
    @Published var isApNameValid = true
    @Published var apNameError = ""
    @Published var isApPasswordValid = true
    @Published var apPasswordError = ""
    @Published var areSettingsValid = true
    
    // Available options
    let availableChannels = Array(1...11)
    let transmitPowerLevels = Array(0...4)
    let transmitPowerLabels = ["Lowest", "Low", "Medium", "High", "Highest"]
    
    private let wirelessService: WirelessService
    private var cancellables = Set<AnyCancellable>()
    
    struct SavedNetwork: Identifiable {
        let id = UUID()
        let ssid: String
        let lastConnected: Date
        
        var lastConnectedText: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: lastConnected)
        }
    }
    
    init(wirelessService: WirelessService) {
        self.wirelessService = wirelessService
        validateSettings()
    }
    
    // MARK: - Settings Validation
    
    private func validateSettings() {
        // Validate AP name
        if accessPointName.trimmingCharacters(in: .whitespaces).isEmpty {
            isApNameValid = false
            apNameError = "AP name cannot be empty"
        } else if accessPointName.count < 2 || accessPointName.count > 32 {
            isApNameValid = false
            apNameError = "AP name must be between 2 and 32 characters"
        } else if accessPointName.contains("|") || accessPointName.contains(";") {
            isApNameValid = false
            apNameError = "AP name cannot contain | or ; characters"
        } else {
            isApNameValid = true
            apNameError = ""
        }
        
        // Validate AP password
        if accessPointPassword.trimmingCharacters(in: .whitespaces).isEmpty {
            isApPasswordValid = false
            apPasswordError = "AP password cannot be empty"
        } else if accessPointPassword.count < 8 {
            isApPasswordValid = false
            apPasswordError = "AP password must be at least 8 characters"
        } else if accessPointPassword.contains("|") || accessPointPassword.contains(";") {
            isApPasswordValid = false
            apPasswordError = "AP password cannot contain | or ; characters"
        } else {
            isApPasswordValid = true
            apPasswordError = ""
        }
        
        // Overall validation
        areSettingsValid = isApNameValid && isApPasswordValid
    }
    
    // MARK: - Settings Management
    
    @MainActor
    func loadSettings() async {
        guard !isLoading else { return }
        
        isLoading = true
        statusMessage = "Loading settings from device..."
        
        do {
            let settings = try await wirelessService.readSettings()
            
            // Update UI properties
            accessPointName = settings.accessPointName
            accessPointPassword = settings.accessPointPassword
            selectedChannel = settings.wifiChannel
            transmitPower = settings.transmitPower
            firmwareVersion = settings.firmwareVersion
            deviceID = settings.deviceID
            
            statusMessage = "Settings loaded successfully"
            
            // Also load saved networks
            await loadSavedNetworks()
            
        } catch {
            statusMessage = "Failed to load settings"
            alertMessage = "Error loading settings: \(error.localizedDescription)"
            showAlert = true
        }
        
        isLoading = false
    }
    
    @MainActor
    func saveSettings() async {
        guard areSettingsValid && !isLoading else {
            if !areSettingsValid {
                alertMessage = "Please fix the validation errors before saving"
                showAlert = true
            }
            return
        }
        
        isLoading = true
        statusMessage = "Saving settings to device..."
        
        do {
            let settings = WirelessService.DeviceSettings(
                accessPointName: accessPointName.trimmingCharacters(in: .whitespaces),
                accessPointPassword: accessPointPassword.trimmingCharacters(in: .whitespaces),
                wifiChannel: selectedChannel,
                transmitPower: transmitPower,
                firmwareVersion: firmwareVersion,
                deviceID: deviceID
            )
            
            try await wirelessService.writeSettings(settings)
            
            statusMessage = "Settings saved successfully"
            alertMessage = "Settings saved successfully! The device will use these settings after restart."
            showAlert = true
            
        } catch {
            statusMessage = "Failed to save settings"
            alertMessage = "Error saving settings: \(error.localizedDescription)"
            showAlert = true
        }
        
        isLoading = false
    }
    
    @MainActor
    func loadSavedNetworks() async {
        guard !isLoading else { return }
        
        do {
            let networkNames = try await wirelessService.getSavedNetworks()
            
            // Convert to SavedNetwork objects with placeholder dates
            savedNetworks = networkNames.enumerated().map { index, ssid in
                SavedNetwork(
                    ssid: ssid,
                    lastConnected: Date().addingTimeInterval(-Double(index * 86400)) // Stagger dates
                )
            }
            
            print("Loaded \(savedNetworks.count) saved networks")
            
        } catch {
            print("Error loading saved networks: \(error.localizedDescription)")
            alertMessage = "Error loading saved networks: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    @MainActor
    func forgetNetwork(_ network: SavedNetwork) async {
        guard !isLoading else { return }
        
        isLoading = true
        statusMessage = "Forgetting network '\(network.ssid)'..."
        
        do {
            try await wirelessService.forgetNetwork(network.ssid)
            
            // Remove from local list
            savedNetworks.removeAll { $0.id == network.id }
            
            statusMessage = "Network forgotten successfully"
            
        } catch {
            statusMessage = "Failed to forget network"
            alertMessage = "Error forgetting network: \(error.localizedDescription)"
            showAlert = true
        }
        
        isLoading = false
    }
    
    // MARK: - Helper Methods
    
    func getTransmitPowerLabel(for power: Int) -> String {
        guard power >= 0 && power < transmitPowerLabels.count else {
            return "Unknown"
        }
        return transmitPowerLabels[power]
    }
    
    func resetToDefaults() {
        accessPointName = "Megadish"
        accessPointPassword = "test1234"
        selectedChannel = 8
        transmitPower = 3
    }
    
    var saveButtonTooltip: String {
        if areSettingsValid {
            return "Save settings to the device"
        } else {
            return "Please fix the validation errors before saving"
        }
    }
    
    var hasValidationErrors: Bool {
        return !areSettingsValid
    }
    
    var validationErrorMessages: [String] {
        var errors: [String] = []
        if !isApNameValid && !apNameError.isEmpty {
            errors.append("AP Name: \(apNameError)")
        }
        if !isApPasswordValid && !apPasswordError.isEmpty {
            errors.append("AP Password: \(apPasswordError)")
        }
        return errors
    }
}
