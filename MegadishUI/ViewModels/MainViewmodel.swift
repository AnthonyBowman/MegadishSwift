import CoreBluetooth
import Foundation

class MainViewModel: ObservableObject {
    @Published var bluetoothDevices: [CBPeripheral] = []
    @Published var wifiNetworks: [WirelessService.ScannedNetwork] = []
    @Published var isBluetoothConnected = false
    @Published var isWifiConnected = false
    @Published var statusMessage = "Ready"
    
    private let wirelessService = WirelessService()
    private var connectedPeripheral: CBPeripheral?
    
    init() {
        setupCallbacks()
    }
    
    private func setupCallbacks() {
        wirelessService.onDeviceDiscovered = { [weak self] peripheral, advertisementData in
            DispatchQueue.main.async {
                if !(self?.bluetoothDevices.contains(where: { $0.identifier == peripheral.identifier }) ?? true) {
                    self?.bluetoothDevices.append(peripheral)
                }
            }
        }
        
        wirelessService.onConnectionStatusChanged = { [weak self] isConnected in
            DispatchQueue.main.async {
                self?.isBluetoothConnected = isConnected
                self?.statusMessage = isConnected ? "Connected to device" : "Disconnected"
            }
        }
        
        wirelessService.onWifiNetworksUpdated = { [weak self] networks in
            DispatchQueue.main.async {
                self?.wifiNetworks = networks
                self?.statusMessage = "Found \(networks.count) networks"
            }
        }
        
        wirelessService.onWifiStatusChanged = { [weak self] status in
            DispatchQueue.main.async {
                self?.statusMessage = "WiFi Status: \(status)"
                self?.isWifiConnected = status.contains("Connected")
            }
        }
    }
    
    // Add to MainViewModel if needed
    func shutdownAndDisconnect() {
        wirelessService.shutdownBluetooth()
    }
    
    func startBluetoothScan() {
        statusMessage = "Scanning for Megadish devices..."
        bluetoothDevices.removeAll()
        wirelessService.startScanning()
    }
    
    func stopBluetoothScan() {
        wirelessService.stopScanning()
    }
    
    func connectToBluetoothDevice(_ peripheral: CBPeripheral) {
        statusMessage = "Connecting to \(peripheral.name ?? "device")..."
        wirelessService.connect(to: peripheral)
        connectedPeripheral = peripheral
    }
    
    func disconnectBluetoothDevice() {
        wirelessService.disconnect()
        connectedPeripheral = nil
        wifiNetworks.removeAll()
    }
    
    func scanForWiFiNetworks() {
        statusMessage = "Scanning for WiFi networks..."
        wifiNetworks.removeAll()
        wirelessService.scanForWiFiNetworks()
    }
    
    func connectToWiFi(network: WirelessService.ScannedNetwork, password: String) {
        statusMessage = "Connecting to \(network.ssid)..."
        
        Task {
            do {
                let connected = try await wirelessService.connect(to: network.ssid, password: password)
                await MainActor.run {
                    if connected {
                        self.statusMessage = "Successfully connected to \(network.ssid)"
                        self.isWifiConnected = true
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
        }
    }

    
    func disconnectWiFi(shutdownAP: Bool = false) {
        wirelessService.disconnectWiFi(shutdownAP: shutdownAP)
        statusMessage = shutdownAP ? "AP shutdown and WiFi disconnected" : "WiFi disconnected"
    }
}

