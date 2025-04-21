import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @StateObject private var viewModel = MainViewModel()
    @State private var selectedBluetoothDevice: CBPeripheral?
    @State private var selectedWiFiNetwork: WirelessService.ScannedNetwork?
    @State private var showingPasswordPrompt = false
    @State private var wifiPassword = ""
    
    var body: some View {
        NavigationView {
            VStack {
                // Status Message
                Text(viewModel.statusMessage)
                    .padding()
                
                if !viewModel.isBluetoothConnected {
                    // INITIAL SCREEN: Bluetooth Devices List
                    List(viewModel.bluetoothDevices, id: \.identifier) { device in
                        Button(action: {
                            selectedBluetoothDevice = device
                            viewModel.connectToBluetoothDevice(device)
                        }) {
                            Text(device.name ?? "Unknown Device")
                                .foregroundColor(.primary)
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                    
                    // Bluetooth Scan Button
                    Button(action: viewModel.startBluetoothScan) {
                        Text("Scan for Megadish devices")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding()
                } else if viewModel.isWifiConnected {
                    // FINAL SCREEN: Configuration Complete (New UI)
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .resizable()
                            .frame(width: 80, height: 80)
                            .foregroundColor(.green)
                            .padding(.top, 20)
                        
                        Text("Configuration Complete")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        VStack(spacing: 8) {
                            Text("Successfully connected to")
                                .foregroundColor(.secondary)
                            
                            // Extract network name from status message
                            Text(extractNetworkName(from: viewModel.statusMessage))
                                .font(.headline)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 12)
                                .background(Color.green.opacity(0.15))
                                .cornerRadius(8)
                                
                            Text("To reapply settings power off and then power on your Megadish device")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                        }
                        
                        Text("Your Megadish device has been successfully configured.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        Spacer()
                        
                        // Finish button - just disconnects for now
                        Button(action: {
                            viewModel.shutdownAndDisconnect()
                        }) {
                            Text("Finish")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                    .padding()
                } else {
                    // MIDDLE SCREEN: WiFi Networks List
                    List(viewModel.wifiNetworks) { network in
                        Button(action: {
                            selectedWiFiNetwork = network
                            showingPasswordPrompt = true
                        }) {
                            HStack {
                                Text(network.ssid)
                                Spacer()
                                Text("\(network.signalStrength) dBm")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                    
                    // WiFi Scan Button
                    Button(action: viewModel.scanForWiFiNetworks) {
                        Text("Scan for WiFi")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding()
                }
            }
            .navigationTitle("Megadish Control")
            .alert("Enter WiFi Password", isPresented: $showingPasswordPrompt) {
                TextField("Password", text: $wifiPassword)
                Button("Connect") {
                    if let network = selectedWiFiNetwork {
                        viewModel.connectToWiFi(network: network, password: wifiPassword)
                    }
                    wifiPassword = ""
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
    
    // Helper function to extract network name from status message
    private func extractNetworkName(from status: String) -> String {
        if status.contains("Successfully connected to") {
            if let range = status.range(of: "Successfully connected to ") {
                return String(status[range.upperBound...])
            }
        }
        return "WiFi Network"
    }
}
