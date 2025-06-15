import CoreBluetooth
import Foundation

class WirelessService: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    // Service UUID (original correct byte order)
    static let MD_SERVICE_UUID = CBUUID(string: "00da7f56-0bd2-45aa-264e-2af9617e0b94")
     
    // Characteristic UUIDs (original correct byte order)
    // Replace your current UUID definitions with these uppercase versions:

    static let OUTPUT_DATA_CHAR_UUID = CBUUID(string: "8243C534-0F25-A287-6D4C-ADA73E6E409E")
    static let INPUT_COMMAND_CHAR_UUID = CBUUID(string: "8343C534-0F25-A287-6D4C-ADA73E6E409F")
    static let INPUT_DATA_CHAR_UUID = CBUUID(string: "8443C534-0F25-A287-6D4C-ADA73E6E40A0")
    static let OUTPUT_COMMAND_CHAR_UUID = CBUUID(string: "8543C534-0F25-A287-6D4C-ADA73E6E40A1")
  
    
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    
    // Characteristic references
    private var outputDataCharacteristic: CBCharacteristic?
    private var inputCommandCharacteristic: CBCharacteristic?
    private var inputDataCharacteristic: CBCharacteristic?
    private var outputCommandCharacteristic: CBCharacteristic?
    
    // Response handlers for async operations
    private var connectionStatusReadHandler: ((CBPeripheral, CBCharacteristic, Error?) -> Void)?
    private var settingsReadHandler: ((CBPeripheral, CBCharacteristic, Error?) -> Void)?
    private var networksReadHandler: ((CBPeripheral, CBCharacteristic, Error?) -> Void)?
  
    // Callbacks
    var onDeviceDiscovered: ((CBPeripheral, [String: Any]) -> Void)?
    var onConnectionStatusChanged: ((Bool) -> Void)?
    var onWifiNetworksUpdated: (([ScannedNetwork]) -> Void)?
    var onWifiStatusChanged: ((String) -> Void)?
    var onSettingsLoaded: ((DeviceSettings) -> Void)?
    var onSavedNetworksLoaded: (([String]) -> Void)?
    
    // Debug flag - when true, scans all devices; when false, pre-filters by service UUID
    private var isDebugMode = false
    
    struct ScannedNetwork: Identifiable {
        let id = UUID()
        let ssid: String
        let signalStrength: Int
        let primaryChannel: Int
    }
    
    struct DeviceSettings {
        var accessPointName: String
        var accessPointPassword: String
        var wifiChannel: Int
        var transmitPower: Int
        var firmwareVersion: String
        var deviceID: String
        
        init() {
            self.accessPointName = "Megadish"
            self.accessPointPassword = "test1234"
            self.wifiChannel = 8
            self.transmitPower = 3
            self.firmwareVersion = "1.0.0"
            self.deviceID = "MD-000000000000"
        }
        
        init(accessPointName: String, accessPointPassword: String, wifiChannel: Int, transmitPower: Int, firmwareVersion: String, deviceID: String) {
            self.accessPointName = accessPointName
            self.accessPointPassword = accessPointPassword
            self.wifiChannel = wifiChannel
            self.transmitPower = transmitPower
            self.firmwareVersion = firmwareVersion
            self.deviceID = deviceID
        }
    }
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Debug Control
    
    func setDebugMode(_ enabled: Bool) {
        isDebugMode = enabled
        print("Debug mode \(enabled ? "enabled" : "disabled")")
    }
    
    // MARK: - Bluetooth Methods
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            print("Bluetooth is not powered on")
            return
        }
        
        if isDebugMode {
            // Debug mode: Scan all devices, then filter in discovery
            print("Starting scan for all Bluetooth devices (debug mode)...")
            centralManager.scanForPeripherals(withServices: nil,
                                            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        } else {
            // Production mode: Pre-filter by scanning only for devices advertising our service UUID
            print("Starting scan for devices with Megadish service UUID...")
            centralManager.scanForPeripherals(withServices: [WirelessService.MD_SERVICE_UUID],
                                            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }
    
    func stopScanning() {
        print("Stopping Bluetooth scan")
        centralManager.stopScan()
    }
    
    func connect(to peripheral: CBPeripheral) {
        print("Connecting to peripheral: \(peripheral.name ?? "Unknown")")
        self.peripheral = peripheral
        self.peripheral?.delegate = self
        centralManager.connect(peripheral, options: nil)
    }
    
    func disconnect() {
        if let peripheral = peripheral {
            print("Disconnecting from peripheral: \(peripheral.name ?? "Unknown")")
            centralManager.cancelPeripheralConnection(peripheral)
            self.peripheral = nil
        }
    }

    func shutdownBluetooth() {
        guard let inputCommandChar = inputCommandCharacteristic else {
            print("Error: inputCommandCharacteristic not found")
            return
        }
        
        let command = "CLOSEBTTASK"
        print("Sending Bluetooth shutdown command: \(command)")
        peripheral?.writeValue(command.data(using: .utf8)!,
                             for: inputCommandChar,
                             type: .withResponse)
        
        // Disconnect after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if let peripheral = self?.peripheral {
                self?.centralManager.cancelPeripheralConnection(peripheral)
            }
        }
    }
    
    // MARK: - WiFi Methods
      
    func scanForWiFiNetworks() {
        print("Starting WiFi network scan...")
        guard let inputCommandChar = inputCommandCharacteristic,
              let outputDataChar = outputDataCharacteristic else {
            print("Error: characteristics not found")
            return
        }
        
        // Send GETSSIDLIST command
        let command = "GETSSIDLIST"
        print("Sending GETSSIDLIST command...")
        peripheral?.writeValue(command.data(using: .utf8)!,
                             for: inputCommandChar,
                             type: .withResponse)
        
        // Wait a moment then read results from OUTPUT_DATA
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            print("Reading scan results...")
            self?.peripheral?.readValue(for: outputDataChar)
        }
    }
    
    func connect(to ssid: String, password: String) async throws -> Bool {
        guard let inputDataChar = inputDataCharacteristic,
              let inputCommandChar = inputCommandCharacteristic,
              let outputCommandChar = outputCommandCharacteristic else {
            throw WirelessError.characteristicsNotFound
        }
        
        print("Connecting to WiFi network: \(ssid)")
        
        // Step 1: Send SSID data, then SETSELSSID command
        peripheral?.writeValue(ssid.data(using: .utf8)!,
                             for: inputDataChar,
                             type: .withResponse)
        
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        peripheral?.writeValue("SETSELSSID".data(using: .utf8)!,
                             for: inputCommandChar,
                             type: .withResponse)
        
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Step 2: Send password data, then STOREPWORD command
        peripheral?.writeValue(password.data(using: .utf8)!,
                             for: inputDataChar,
                             type: .withResponse)
        
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        peripheral?.writeValue("STOREPWORD".data(using: .utf8)!,
                             for: inputCommandChar,
                             type: .withResponse)
        
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Step 3: Send CONNECTWIFI command
        peripheral?.writeValue("CONNECTWIFI".data(using: .utf8)!,
                             for: inputCommandChar,
                             type: .withResponse)
        
        // Step 4: Wait and check connection status
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        peripheral?.readValue(for: outputCommandChar)
        
        // Wait for the read response using a continuation
        return try await withCheckedThrowingContinuation { continuation in
            let handler: ((CBPeripheral, CBCharacteristic, Error?) -> Void) = { [weak self] _, characteristic, error in
                self?.connectionStatusReadHandler = nil
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let data = characteristic.value,
                      let status = String(data: data, encoding: .utf8) else {
                    continuation.resume(returning: false)
                    return
                }
                
                let isConnected = status.contains("Connected")
                continuation.resume(returning: isConnected)
            }
            
            // Store the handler temporarily
            self.connectionStatusReadHandler = handler
        }
    }
    
    // MARK: - Settings Methods
    
    func readSettings() async throws -> DeviceSettings {
        guard let inputCommandChar = inputCommandCharacteristic,
              let outputDataChar = outputDataCharacteristic else {
            throw WirelessError.characteristicsNotFound
        }
        
        print("Reading device settings...")
        
        // Send READSETTINGS command
        peripheral?.writeValue("READSETTINGS".data(using: .utf8)!,
                             for: inputCommandChar,
                             type: .withResponse)
        
        // Wait and read results
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        peripheral?.readValue(for: outputDataChar)
        
        // Wait for the read response
        return try await withCheckedThrowingContinuation { continuation in
            let handler: ((CBPeripheral, CBCharacteristic, Error?) -> Void) = { [weak self] _, characteristic, error in
                self?.settingsReadHandler = nil
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let data = characteristic.value,
                      let settingsString = String(data: data, encoding: .utf8) else {
                    continuation.resume(throwing: WirelessError.invalidResponse)
                    return
                }
                
                print("Settings received: '\(settingsString)'")
                
                // Parse settings: "ap_name|ap_password|ap_channel|tx_power|firmware_version|device_id"
                let parts = settingsString.split(separator: "|")
                var settings = DeviceSettings()
                
                if parts.count >= 4 {
                    settings.accessPointName = String(parts[0])
                    settings.accessPointPassword = String(parts[1])
                    settings.wifiChannel = Int(parts[2]) ?? 8
                    settings.transmitPower = Int(parts[3]) ?? 3
                    
                    if parts.count > 4 {
                        settings.firmwareVersion = String(parts[4])
                    }
                    if parts.count > 5 {
                        settings.deviceID = String(parts[5])
                    }
                }
                
                continuation.resume(returning: settings)
            }
            
            self.settingsReadHandler = handler
        }
    }
    
    func writeSettings(_ settings: DeviceSettings) async throws {
        guard let inputDataChar = inputDataCharacteristic,
              let inputCommandChar = inputCommandCharacteristic else {
            throw WirelessError.characteristicsNotFound
        }
        
        // Create delimited settings string: ap_name|ap_password|ap_channel|tx_power
        let settingsString = "\(settings.accessPointName)|\(settings.accessPointPassword)|\(settings.wifiChannel)|\(settings.transmitPower)"
        
        print("Sending settings: \(settingsString)")
        
        // Send settings data first, then WRITESETTINGS command
        peripheral?.writeValue(settingsString.data(using: .utf8)!,
                             for: inputDataChar,
                             type: .withResponse)
        
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        peripheral?.writeValue("WRITESETTINGS".data(using: .utf8)!,
                             for: inputCommandChar,
                             type: .withResponse)
    }
    
    func getSavedNetworks() async throws -> [String] {
        guard let inputCommandChar = inputCommandCharacteristic,
              let outputDataChar = outputDataCharacteristic else {
            throw WirelessError.characteristicsNotFound
        }
        
        print("Getting saved networks from device...")
        
        // Send GETNETWORKS command
        peripheral?.writeValue("GETNETWORKS".data(using: .utf8)!,
                             for: inputCommandChar,
                             type: .withResponse)
        
        // Wait and read results
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        peripheral?.readValue(for: outputDataChar)
        
        // Wait for the read response
        return try await withCheckedThrowingContinuation { continuation in
            let handler: ((CBPeripheral, CBCharacteristic, Error?) -> Void) = { [weak self] _, characteristic, error in
                self?.networksReadHandler = nil
                if let error = error {
                    print("Error reading saved networks: \(error)")
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let data = characteristic.value,
                      let networksString = String(data: data, encoding: .utf8) else {
                    print("No data received for saved networks")
                    continuation.resume(returning: [])
                    return
                }
                
                print("Raw networks data received: '\(networksString)'")
                
                if networksString.isEmpty || networksString == "No saved networks" {
                    print("No saved networks found")
                    continuation.resume(returning: [])
                    return
                }
                
                // Parse delimited string
                let networks = networksString.split(separator: ";")
                    .map { String($0.trimmingCharacters(in: .whitespaces)) }
                    .filter { !$0.isEmpty }
                
                print("Parsed \(networks.count) saved networks: \(networks)")
                continuation.resume(returning: networks)
            }
            
            self.networksReadHandler = handler
        }
    }
    
    func forgetNetwork(_ ssid: String) async throws {
        guard let inputDataChar = inputDataCharacteristic,
              let inputCommandChar = inputCommandCharacteristic else {
            throw WirelessError.characteristicsNotFound
        }
        
        print("Forgetting network: \(ssid)")
        
        // Send SSID data first, then FORGETNETWORK command
        peripheral?.writeValue(ssid.data(using: .utf8)!,
                             for: inputDataChar,
                             type: .withResponse)
        
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        peripheral?.writeValue("FORGETNETWORK".data(using: .utf8)!,
                             for: inputCommandChar,
                             type: .withResponse)
    }

    enum WirelessError: Error {
        case characteristicsNotFound
        case connectionFailed
        case invalidResponse
        case settingsValidationFailed
    }
    
    func disconnectWiFi(shutdownAP: Bool = false) {
        guard let inputCommandChar = inputCommandCharacteristic else {
            print("Error: inputCommandCharacteristic not found")
            return
        }
        
        let command = shutdownAP ? "SHUTDOWNALL" : "DISCONNECT"
        print("Sending WiFi disconnect command: \(command)")
        peripheral?.writeValue(command.data(using: .utf8)!,
                             for: inputCommandChar,
                             type: .withResponse)
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on")
        case .poweredOff:
            print("Bluetooth is powered off")
        case .unsupported:
            print("Bluetooth is not supported")
        case .unauthorized:
            print("Bluetooth is unauthorized")
        case .resetting:
            print("Bluetooth is resetting")
        case .unknown:
            print("Bluetooth state is unknown")
        @unknown default:
            print("Unknown Bluetooth state")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                       advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("Discovered device: \(peripheral.name ?? "Unknown") with RSSI: \(RSSI)")
        
        if isDebugMode {
            // Debug mode: Show all discovered devices
            onDeviceDiscovered?(peripheral, advertisementData)
            print("Advertisement data:")
            for (key, value) in advertisementData {
                print("\(key): \(value)")
            }
        } else {
            // Production mode: Since we pre-filtered by service UUID, any device discovered here
            // should be a valid Megadish device, but let's double-check for safety
            if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
               serviceUUIDs.contains(WirelessService.MD_SERVICE_UUID) {
                print("Found Megadish device!")
                onDeviceDiscovered?(peripheral, advertisementData)
            } else {
                // This should rarely happen in pre-filtered mode, but log for debugging
                print("Device discovered without expected service UUID (this shouldn't happen in pre-filtered mode)")
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to peripheral: \(peripheral.name ?? "Unknown")")
        peripheral.discoverServices([WirelessService.MD_SERVICE_UUID])
        onConnectionStatusChanged?(true)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from peripheral: \(peripheral.name ?? "Unknown")")
        onConnectionStatusChanged?(false)
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            print("Discovered service: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            print("Discovered characteristic: \(characteristic.uuid)")
            switch characteristic.uuid {
            case WirelessService.OUTPUT_DATA_CHAR_UUID:
                outputDataCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            case WirelessService.INPUT_COMMAND_CHAR_UUID:
                inputCommandCharacteristic = characteristic
            case WirelessService.INPUT_DATA_CHAR_UUID:
                inputDataCharacteristic = characteristic
            case WirelessService.OUTPUT_COMMAND_CHAR_UUID:
                outputCommandCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                break
            }
        }
        
        print("All characteristics discovered and configured")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // Handle specific read response handlers first (these take priority)
        if characteristic.uuid == WirelessService.OUTPUT_COMMAND_CHAR_UUID,
           let handler = connectionStatusReadHandler {
            handler(peripheral, characteristic, error)
            return
        }
        
        if characteristic.uuid == WirelessService.OUTPUT_DATA_CHAR_UUID,
           let handler = settingsReadHandler {
            handler(peripheral, characteristic, error)
            return
        }
        
        if characteristic.uuid == WirelessService.OUTPUT_DATA_CHAR_UUID,
           let handler = networksReadHandler {
            handler(peripheral, characteristic, error)
            return
        }
        
        if let error = error {
            print("Error updating characteristic value: \(error)")
            return
        }
        
        guard let data = characteristic.value,
              let stringValue = String(data: data, encoding: .utf8) else {
            return
        }
        
        print("Received update for characteristic: \(characteristic.uuid)")
        print("Value: \(stringValue)")
        
        switch characteristic.uuid {
        case WirelessService.OUTPUT_DATA_CHAR_UUID:
            handleWiFiScanResults(stringValue)
        case WirelessService.OUTPUT_COMMAND_CHAR_UUID:
            onWifiStatusChanged?(stringValue)
        default:
            break
        }
    }
    
    private func handleWiFiScanResults(_ results: String) {
        print("Processing WiFi scan results: \(results)")
        let networks = results.split(separator: ";")
            .compactMap { networkString -> ScannedNetwork? in
                let parts = networkString.split(separator: "|")
                guard parts.count >= 3,
                      let signalStrength = Int(parts[1]),
                      let primaryChannel = Int(parts[2]) else {
                    print("Failed to parse network: \(networkString)")
                    return nil
                }
                
                return ScannedNetwork(
                    ssid: String(parts[0]),
                    signalStrength: signalStrength,
                    primaryChannel: primaryChannel
                )
            }
        
        print("Found \(networks.count) networks")
        onWifiNetworksUpdated?(networks)
    }
}
