import CoreBluetooth
import Foundation

class MainViewModel: ObservableObject {
    @Published var bluetoothDevices: [CBPeripheral] = []
    @Published var wifiNetworks: [WirelessService.ScannedNetwork] = []
    @Published var isBluetoothConnected = false
    @Published var isWifiConnected = false
    @Published var statusMessage = "Ready to scan for devices"
    @Published var connectedNetworkName = ""
    
    // UI State
    @Published var showingPasswordPrompt = false
    @Published var showingSettings = false
    @Published var isScanning = false
    
    // Password entry
    @Published var wifiPassword = ""
    @Published var selectedWiFiNetwork: WirelessService.ScannedNetwork?
    
    // Settings
    @Published var settingsViewModel: SettingsViewModel?
    
    private let wirelessService = WirelessService()
    private var connectedPeripheral: CBPeripheral?
    
    // Last connected device persistence
    @Published var lastConnectedDeviceId: String?
    @Published var lastConnectedDeviceName: String?
    
    init() {
        setupCallbacks()
        loadLastConnectedDevice()
    }
    
    private func setupCallbacks() {
        wirelessService.onDeviceDiscovered = { [weak self] peripheral, advertisementData in
            DispatchQueue.main.async {
                // Avoid duplicates
                if !(self?.bluetoothDevices.contains(where: { $0.identifier == peripheral.identifier }) ?? true) {
                    self?.bluetoothDevices.append(peripheral)
                    
                    // Check if this is our last connected device
                    if let lastId = self?.lastConnectedDeviceId,
                       peripheral.identifier.uuidString == lastId {
                        self?.statusMessage = "Found last connected device: \(peripheral.name ?? "Megadish Device")"
                    }
                }
            }
        }
        
        wirelessService.onConnectionStatusChanged = { [weak self] isConnected in
            DispatchQueue.main.async {
                self?.isBluetoothConnected = isConnected
                
                if isConnected {
                    self?.statusMessage = "Connected! Scan for WiFi networks"
                    // Initialize settings view model when connected
                    if let service = self?.wirelessService {
                        self?.settingsViewModel = SettingsViewModel(wirelessService: service)
                    }
                } else {
                    self?.statusMessage = "Disconnected"
                    self?.settingsViewModel = nil
                    self?.isWifiConnected = false
                    self?.connectedNetworkName = ""
                    self?.wifiNetworks.removeAll()
                }
            }
        }
        
        wirelessService.onWifiNetworksUpdated = { [weak self] networks in
            DispatchQueue.main.async {
                self?.wifiNetworks = networks.sorted { $0.signalStrength > $1.signalStrength }
                self?.statusMessage = networks.isEmpty ? "No networks found" : "Found \(networks.count) networks"
            }
        }
        
        wirelessService.onWifiStatusChanged = { [weak self] status in
            DispatchQueue.main.async {
                self?.statusMessage = "WiFi Status: \(status)"
                
                if status.contains("Connected") {
                    self?.isWifiConnected = true
                    // Extract network name from status if possible
                    if let network = self?.selectedWiFiNetwork {
                        self?.connectedNetworkName = network.ssid
                    }
                } else {
                    self?.isWifiConnected = false
                    self?.connectedNetworkName = ""
                }
            }
        }
    }
    
    // MARK: - Device Persistence
    
    private func loadLastConnectedDevice() {
        lastConnectedDeviceId = UserDefaults.standard.string(forKey: "LastConnectedDeviceId")
        lastConnectedDeviceName = UserDefaults.standard.string(forKey: "LastConnectedDeviceName")
    }
    
    private func saveLastConnectedDevice(_ peripheral: CBPeripheral) {
        let deviceId = peripheral.identifier.uuidString
        let deviceName = peripheral.name ?? "Megadish Device"
        
        UserDefaults.standard.set(deviceId, forKey: "LastConnectedDeviceId")
        UserDefaults.standard.set(deviceName, forKey: "LastConnectedDeviceName")
        
        lastConnectedDeviceId = deviceId
        lastConnectedDeviceName = deviceName
    }
    
    // MARK: - Bluetooth Methods
    
    func startBluetoothScan() {
        guard !isScanning else { return }
        
        isScanning = true
        statusMessage = "Scanning for Megadish devices..."
        bluetoothDevices.removeAll()
        wirelessService.startScanning()
        
        // Stop scanning after 30 seconds (increased from 10)
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.stopBluetoothScan()
        }
    }
    
    func stopBluetoothScan() {
        guard isScanning else { return }
        
        isScanning = false
        wirelessService.stopScanning()
        
        if bluetoothDevices.isEmpty {
            statusMessage = "No Megadish devices found"
        } else {
            statusMessage = "Select a device to connect"
            
            // Add a brief delay to allow cleanup before connections
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if self?.bluetoothDevices.isEmpty == false {
                    self?.statusMessage = "Ready to connect - select a device"
                }
            }
        }
    }
    
    func connectToBluetoothDevice(_ peripheral: CBPeripheral) {
        statusMessage = "Connecting to \(peripheral.name ?? "device")..."
        
        // Stop scanning first to avoid conflicts
        if isScanning {
            print("🛑 Stopping scan before connection...")
            stopBluetoothScan()
            
            // Wait a moment for scan cleanup before connecting
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                print("🔗 Proceeding with connection after scan cleanup...")
                self?.wirelessService.connect(to: peripheral)
                self?.connectedPeripheral = peripheral
                
                // Save this as the last connected device
                self?.saveLastConnectedDevice(peripheral)
            }
        } else {
            print("🔗 Connecting immediately (scan already stopped)...")
            wirelessService.connect(to: peripheral)
            connectedPeripheral = peripheral
            
            // Save this as the last connected device
            saveLastConnectedDevice(peripheral)
        }
    }
    
    func disconnectBluetoothDevice() {
        wirelessService.disconnect()
        connectedPeripheral = nil
        wifiNetworks.removeAll()
        selectedWiFiNetwork = nil
        wifiPassword = ""
        showingPasswordPrompt = false
        showingSettings = false
    }
    
    // MARK: - WiFi Methods
    
    func scanForWiFiNetworks() {
        guard isBluetoothConnected else { return }
        
        statusMessage = "Scanning for WiFi networks..."
        wifiNetworks.removeAll()
        wirelessService.scanForWiFiNetworks()
    }
    
    func selectWiFiNetwork(_ network: WirelessService.ScannedNetwork) {
        selectedWiFiNetwork = network
        wifiPassword = ""
        showingPasswordPrompt = true
    }
    
    func connectToWiFi() {
        guard let network = selectedWiFiNetwork else { return }
        
        statusMessage = "Connecting to \(network.ssid)..."
        showingPasswordPrompt = false
        
        Task {
            do {
                let connected = try await wirelessService.connect(to: network.ssid, password: wifiPassword)
                await MainActor.run {
                    if connected {
                        self.statusMessage = "Successfully connected to \(network.ssid)"
                        self.isWifiConnected = true
                        self.connectedNetworkName = network.ssid
                    } else {
                        self.statusMessage = "Failed to connect to \(network.ssid)"
                        self.isWifiConnected = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "Error connecting to WiFi: \(error.localizedDescription)"
                    self.isWifiConnected = false
                }
            }
            
            await MainActor.run {
                self.selectedWiFiNetwork = nil
                self.wifiPassword = ""
            }
        }
    }
    
    func cancelWiFiPrompt() {
        showingPasswordPrompt = false
        selectedWiFiNetwork = nil
        wifiPassword = ""
    }
    
    // MARK: - Settings Methods
    
    func openSettings() {
        guard isBluetoothConnected else {
            statusMessage = "Please connect to a Megadish device first"
            return
        }
        
        showingSettings = true
    }
    
    func closeSettings() {
        showingSettings = false
    }
    
    // MARK: - Complete Flow
    
    func shutdownAndDisconnect() {
        // Send shutdown command to the device if connected
        if isBluetoothConnected {
            wirelessService.shutdownBluetooth()
            statusMessage = "Sending shutdown command..."
            
            // Reset state after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.resetToStart()
            }
        } else {
            resetToStart()
        }
    }
    
    func resetToStart() {
        // Clean up resources
        disconnectBluetoothDevice()
        
        // Reset state
        isBluetoothConnected = false
        isWifiConnected = false
        connectedNetworkName = ""
        
        // Clear collections
        bluetoothDevices.removeAll()
        wifiNetworks.removeAll()
        
        // Clear selections
        selectedWiFiNetwork = nil
        wifiPassword = ""
        
        // Reset UI state
        showingPasswordPrompt = false
        showingSettings = false
        isScanning = false
        
        // Reset status
        statusMessage = "Ready to scan for devices"
    }
    
    // MARK: - Helper Methods
    
    var showBluetoothDevices: Bool {
        return !isBluetoothConnected
    }
    
    var showWiFiNetworks: Bool {
        return isBluetoothConnected && !isWifiConnected
    }
    
    var showCompletion: Bool {
        return isBluetoothConnected && isWifiConnected
    }
    
    func getSignalStrengthBars(for strength: Int) -> Int {
        if strength >= -50 { return 4 }
        if strength >= -60 { return 3 }
        if strength >= -70 { return 2 }
        if strength >= -80 { return 1 }
        return 0
    }
    
    func getSignalStrengthIcon(for strength: Int) -> String {
        let bars = getSignalStrengthBars(for: strength)
        switch bars {
        case 4: return "wifi"
        case 3: return "wifi"
        case 2: return "wifi"
        case 1: return "wifi"
        default: return "wifi.slash"
        }
    }
    
    var isLastConnectedDeviceAvailable: Bool {
        guard let lastId = lastConnectedDeviceId else { return false }
        return bluetoothDevices.contains { $0.identifier.uuidString == lastId }
    }
    
    var lastConnectedDevice: CBPeripheral? {
        guard let lastId = lastConnectedDeviceId else { return nil }
        return bluetoothDevices.first { $0.identifier.uuidString == lastId }
    }
}
