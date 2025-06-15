import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @StateObject private var viewModel = MainViewModel()
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    // Status Bar
                    statusBar
                    
                    // Main Content
                    if viewModel.showBluetoothDevices {
                        bluetoothDevicesView
                    } else if viewModel.showWiFiNetworks {
                        wifiNetworksView
                    } else if viewModel.showCompletion {
                        completionView
                    }
                }
                
                // Loading Overlay
                if viewModel.isScanning {
                    scanningOverlay
                }
            }
            .navigationTitle("Megadish Control")
            .navigationBarTitleDisplayMode(.large)
        }
        .navigationViewStyle(StackNavigationViewStyle()) // Force single view on all devices
        .alert("Enter WiFi Password", isPresented: $viewModel.showingPasswordPrompt) {
            SecureField("Password", text: $viewModel.wifiPassword)
            Button("Connect") {
                viewModel.connectToWiFi()
            }

            Button("Cancel", role: .cancel) {
                viewModel.cancelWiFiPrompt()
            }
        } message: {
            if let network = viewModel.selectedWiFiNetwork {
                Text("Enter the password for '\(network.ssid)'")
            }
        }
        .sheet(isPresented: $viewModel.showingSettings) {
            if let settingsVM = viewModel.settingsViewModel {
                SettingsView(viewModel: settingsVM)
            }
        }
    }
    
    // MARK: - Status Bar
    
    private var statusBar: some View {
        VStack(spacing: 8) {
            HStack {
                // Connection Status Indicator
                Circle()
                    .fill(viewModel.isBluetoothConnected ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                
                Text(viewModel.isBluetoothConnected ? "Connected" : "Disconnected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if viewModel.isWifiConnected && !viewModel.connectedNetworkName.isEmpty {
                    HStack {
                        Image(systemName: "wifi")
                            .foregroundColor(.green)
                        Text(viewModel.connectedNetworkName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Text(viewModel.statusMessage)
                .font(.subheadline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separator)),
            alignment: .bottom
        )
    }
    
    // MARK: - Bluetooth Devices View
    
    private var bluetoothDevicesView: some View {
        VStack(spacing: 16) {
            if viewModel.bluetoothDevices.isEmpty && !viewModel.isScanning {
                emptyBluetoothDevicesView
            } else {
                devicesList
            }
            
            // Scan Button
            Button(action: {
                if viewModel.isScanning {
                    viewModel.stopBluetoothScan()
                } else {
                    viewModel.startBluetoothScan()
                }
            }) {
                HStack {
                    if viewModel.isScanning {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("Stop Scanning")
                    } else {
                        Image(systemName: "magnifyingglass")
                        Text("Scan for Megadish Devices")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.isScanning ? Color.red : Color.blue)
                .foregroundColor(.white)
                .font(.headline)
                .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
    
    private var emptyBluetoothDevicesView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Devices Found")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(spacing: 8) {
                Text("Make sure your Megadish device is:")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Powered on")
                    Text("• In Bluetooth pairing mode")
                    Text("• Within range (< 10 meters)")
                    Text("• Not connected to another device")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            
            // Debug info
            Text("Tip: Check the Xcode console for detailed scan logs")
                .font(.caption2)
                .foregroundColor(.blue)
                .padding(.top, 16)
            
            Spacer()
        }
    }
    
    private var devicesList: some View {
        List(viewModel.bluetoothDevices, id: \.identifier) { device in
            deviceRow(device)
        }
        .listStyle(InsetGroupedListStyle())
    }
    
    private func deviceRow(_ device: CBPeripheral) -> some View {
        Button(action: {
            viewModel.connectToBluetoothDevice(device)
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name ?? "Unknown Device")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(device.identifier.uuidString.prefix(8) + "...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                
                Spacer()
                
                // Last connected indicator
                if viewModel.lastConnectedDeviceId == device.identifier.uuidString {
                    VStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Last")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - WiFi Networks View
    
    private var wifiNetworksView: some View {
        VStack(spacing: 0) {
            if viewModel.wifiNetworks.isEmpty {
                emptyWifiNetworksView
            } else {
                wifiNetworksList
            }
            
            // Bottom Buttons
            VStack(spacing: 12) {
                Button("Scan for WiFi Networks") {
                    viewModel.scanForWiFiNetworks()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .font(.headline)
                .cornerRadius(12)
                
                Button("Settings") {
                    viewModel.openSettings()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .font(.headline)
                .cornerRadius(12)
            }
            .padding()
            .background(Color(.systemGroupedBackground))
        }
    }
    
    private var emptyWifiNetworksView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "wifi.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Networks Found")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Tap 'Scan for WiFi Networks' to search for available networks")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
        }
    }
    
    private var wifiNetworksList: some View {
        List(viewModel.wifiNetworks) { network in
            wifiNetworkRow(network)
        }
        .listStyle(InsetGroupedListStyle())
    }
    
    private func wifiNetworkRow(_ network: WirelessService.ScannedNetwork) -> some View {
        Button(action: {
            viewModel.selectWiFiNetwork(network)
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(network.ssid)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack {
                        Text("\(network.signalStrength) dBm")
                        Text("•")
                        Text("Channel \(network.primaryChannel)")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Signal Strength Icon
                VStack {
                    Image(systemName: viewModel.getSignalStrengthIcon(for: network.signalStrength))
                        .foregroundColor(.blue)
                    
                    // Signal bars indicator
                    HStack(spacing: 2) {
                        ForEach(1...4, id: \.self) { bar in
                            Rectangle()
                                .frame(width: 3, height: CGFloat(bar * 3))
                                .foregroundColor(bar <= viewModel.getSignalStrengthBars(for: network.signalStrength) ? .blue : .gray.opacity(0.3))
                        }
                    }
                }
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Completion View
    
    private var completionView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Success Icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "megadish_icon")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
            }
            
            VStack(spacing: 16) {
                Text("Configuration Complete")
                    .font(.title)
                    .fontWeight(.bold)
                
                VStack(spacing: 8) {
                    Text("Successfully connected to")
                        .foregroundColor(.secondary)
                    
                    Text(viewModel.connectedNetworkName)
                        .font(.headline)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(8)
                    
                    Text("To apply settings, power off and then power on your Megadish device")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
                
                Text("Your Megadish device has been successfully configured and is ready to use.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
            
            // Action Buttons
            VStack(spacing: 12) {
                Button("Settings") {
                    viewModel.openSettings()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .font(.headline)
                .cornerRadius(12)
                
                Button("Finish") {
                    viewModel.shutdownAndDisconnect()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .font(.headline)
                .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
    
    // MARK: - Scanning Overlay
    
    private var scanningOverlay: some View {
        Rectangle()
            .fill(Color.black.opacity(0.3))
            .ignoresSafeArea()
            .overlay(
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(2.0)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    
                    VStack(spacing: 8) {
                        Text("Scanning for devices...")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text("Scanning for 30 seconds")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text("Check Xcode console for details")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    Button("Stop") {
                        viewModel.stopBluetoothScan()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(20)
                }
                .padding(32)
                .background(Color.black.opacity(0.7))
                .cornerRadius(16)
            )
    }
}

// Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
