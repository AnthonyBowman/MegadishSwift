import CoreBluetooth
import Foundation

class WirelessService: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    // Service UUID
    static let MD_CONFIG_SERVICE_UUID = CBUUID(string: "940b7e61-f92a-4e26-aa45-d20b567fda00")
    
    // Characteristic UUIDs
    static let MD_SSID_LIST_CHAR_UUID = CBUUID(string: "9e406e3e-a7ad-4c6d-87a2-250f34c54382")
    static let MD_SSID_SEL_CHAR_UUID = CBUUID(string: "9f406e3e-a7ad-4c6d-87a2-250f34c54383")
    static let MD_PWORD_CHAR_UUID = CBUUID(string: "a0406e3e-a7ad-4c6d-87a2-250f34c54384")
    static let MD_CONNECTION_STATUS_CHAR_UUID = CBUUID(string: "a1406e3e-a7ad-4c6d-87a2-250f34c54385")
    
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var ssidListCharacteristic: CBCharacteristic?
    private var selectedSsidCharacteristic: CBCharacteristic?
    private var passwordCharacteristic: CBCharacteristic?
    private var connectionStatusCharacteristic: CBCharacteristic?
    private var connectionStatusReadHandler: ((CBPeripheral, CBCharacteristic, Error?) -> Void)?
  
    // Callbacks
    var onDeviceDiscovered: ((CBPeripheral, [String: Any]) -> Void)?
    var onConnectionStatusChanged: ((Bool) -> Void)?
    var onWifiNetworksUpdated: (([ScannedNetwork]) -> Void)?
    var onWifiStatusChanged: ((String) -> Void)?
    
    // Debug flag
    private var isDebugMode = true
    
    struct ScannedNetwork: Identifiable {
        let id = UUID()
        let ssid: String
        let signalStrength: Int
        let primaryChannel: Int
    }
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Bluetooth Methods
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            print("Bluetooth is not powered on")
            return
        }
        
        if isDebugMode {
            print("Starting scan for all Bluetooth devices...")
            centralManager.scanForPeripherals(withServices: nil,
                                            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        } else {
            print("Starting scan for Megadish devices...")
            centralManager.scanForPeripherals(withServices: [WirelessService.MD_CONFIG_SERVICE_UUID],
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
    
    // Add this method to the WirelessService class

    func shutdownBluetooth() {
        guard let ssidChar = selectedSsidCharacteristic else {
            print("Error: selectedSsidCharacteristic not found")
            return
        }
        
        let command = "CLOSEBTTASK"
        print("Sending Bluetooth shutdown command: \(command)")
        peripheral?.writeValue(command.data(using: .utf8)!,
                             for: ssidChar,
                             type: .withResponse)
        
        // We're done with this peripheral now
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if let peripheral = self?.peripheral {
                self?.centralManager.cancelPeripheralConnection(peripheral)
            }
        }
    }
    
    // MARK: - WiFi Methods
      
    func scanForWiFiNetworks() {
        print("Starting WiFi network scan...")
        guard let selCharacteristic = selectedSsidCharacteristic,
              let listCharacteristic = ssidListCharacteristic else {
            print("Error: characteristics not found")
            return
        }
        
        // Send scan command
        let command = "GETSSIDLIST"
        print("Sending GETSSIDLIST command...")
        peripheral?.writeValue(command.data(using: .utf8)!,
                             for: selCharacteristic,
                             type: .withResponse)
        
        // Wait a moment then read results
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            print("Reading scan results...")
            self?.peripheral?.readValue(for: listCharacteristic)
        }
    }
    
    func connect(to ssid: String, password: String) async throws -> Bool {
        guard let ssidChar = selectedSsidCharacteristic,
              let passwordChar = passwordCharacteristic,
              let statusChar = connectionStatusCharacteristic else {
            throw WirelessError.characteristicsNotFound
        }
        
        print("Connecting to WiFi network: \(ssid)")
        
        // Write SSID
        peripheral?.writeValue(ssid.data(using: .utf8)!,
                             for: ssidChar,
                             type: .withResponse)
        
        // Write password
        peripheral?.writeValue(password.data(using: .utf8)!,
                             for: passwordChar,
                             type: .withResponse)
        
        // Give a brief moment for connection attempt
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Read connection status
        peripheral?.readValue(for: statusChar)
        
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

    enum WirelessError: Error {
        case characteristicsNotFound
        case connectionFailed
    }
    
    func disconnectWiFi(shutdownAP: Bool = false) {
        guard let ssidChar = selectedSsidCharacteristic else {
            print("Error: selectedSsidCharacteristic not found")
            return
        }
        
        let command = shutdownAP ? "SHUTDOWNALL" : "DISCONNECT"
        print("Sending WiFi disconnect command: \(command)")
        peripheral?.writeValue(command.data(using: .utf8)!,
                             for: ssidChar,
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
            onDeviceDiscovered?(peripheral, advertisementData)
            print("Advertisement data:")
            for (key, value) in advertisementData {
                print("\(key): \(value)")
            }
        } else {
            if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
               serviceUUIDs.contains(WirelessService.MD_CONFIG_SERVICE_UUID) {
                print("Found Megadish device!")
                onDeviceDiscovered?(peripheral, advertisementData)
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to peripheral: \(peripheral.name ?? "Unknown")")
        peripheral.discoverServices([WirelessService.MD_CONFIG_SERVICE_UUID])
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
            switch characteristic.uuid {
            case WirelessService.MD_SSID_LIST_CHAR_UUID:
                ssidListCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            case WirelessService.MD_SSID_SEL_CHAR_UUID:
                selectedSsidCharacteristic = characteristic
            case WirelessService.MD_PWORD_CHAR_UUID:
                passwordCharacteristic = characteristic
            case WirelessService.MD_CONNECTION_STATUS_CHAR_UUID:
                connectionStatusCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                break
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == WirelessService.MD_CONNECTION_STATUS_CHAR_UUID,
                 let handler = connectionStatusReadHandler {
                  // If we have a handler, this is a response to our read request
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
        case WirelessService.MD_SSID_LIST_CHAR_UUID:
            handleWiFiScanResults(stringValue)
        case WirelessService.MD_CONNECTION_STATUS_CHAR_UUID:
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
