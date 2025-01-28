import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @StateObject private var viewModel = MainViewModel()
    @State private var selectedBluetoothDevice: CBPeripheral?
    @State private var selectedWiFiNetwork: WirelessService.ScannedNetwork?
    @State private var showingPasswordPrompt = false
    @State private var wifiPassword = ""
    @State private var showingDisconnectOptions = false
    
    var body: some View {
        NavigationView {
            VStack {
                // Status Message
                Text(viewModel.statusMessage)
                    .padding()
                
                if !viewModel.isBluetoothConnected {
                    // Bluetooth Devices List
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
                } else {
                    // WiFi Networks List
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
                        .disabled(viewModel.isWifiConnected)
                    }
                    .listStyle(InsetGroupedListStyle())
                    
                    HStack {
                        // WiFi Scan Button
                        Button(action: viewModel.scanForWiFiNetworks) {
                            Text("Scan for WiFi")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .disabled(viewModel.isWifiConnected)
                        
                        // Disconnect WiFi Button
                        if viewModel.isWifiConnected {
                            Button(action: { showingDisconnectOptions = true }) {
                                Text("Disconnect WiFi")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.red)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                        }
                    }
                    .padding()
                    
                    // Disconnect Bluetooth Button
                    Button(action: viewModel.disconnectBluetoothDevice) {
                        Text("Disconnect Bluetooth")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
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
            .actionSheet(isPresented: $showingDisconnectOptions) {
                ActionSheet(
                    title: Text("Disconnect Options"),
                    buttons: [
                        .destructive(Text("Shutdown AP & Disconnect WiFi")) {
                            viewModel.disconnectWiFi(shutdownAP: true)
                        },
                        .destructive(Text("Disconnect WiFi Only")) {
                            viewModel.disconnectWiFi(shutdownAP: false)
                        },
                        .cancel()
                    ]
                )
            }
        }
    }
}
