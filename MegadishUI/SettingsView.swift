import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingPasswordText = false
    @State private var showingForgetConfirmation = false
    @State private var networkToForget: SettingsViewModel.SavedNetwork?
    
    var body: some View {
        NavigationView {
            ZStack {
                Form {
                    // Access Point Settings Section
                    Section(header: Text("Access Point Settings")) {
                        // AP Name
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("AP Name (SSID)")
                                Spacer()
                                if !viewModel.isApNameValid {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                            }
                            
                            TextField("Enter AP name", text: $viewModel.accessPointName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(viewModel.isApNameValid ? Color.clear : Color.red, lineWidth: 1)
                                )
                            
                            if !viewModel.isApNameValid && !viewModel.apNameError.isEmpty {
                                Text(viewModel.apNameError)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        
                        // AP Password
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("AP Password")
                                Spacer()
                                if !viewModel.isApPasswordValid {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                            }
                            
                            HStack {
                                Group {
                                    if showingPasswordText {
                                        TextField("Enter password", text: $viewModel.accessPointPassword)
                                    } else {
                                        SecureField("Enter password", text: $viewModel.accessPointPassword)
                                    }
                                }
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(viewModel.isApPasswordValid ? Color.clear : Color.red, lineWidth: 1)
                                )
                                
                                Button(action: {
                                    showingPasswordText.toggle()
                                }) {
                                    Image(systemName: showingPasswordText ? "eye.slash" : "eye")
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            if !viewModel.isApPasswordValid && !viewModel.apPasswordError.isEmpty {
                                Text(viewModel.apPasswordError)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        
                        // WiFi Channel
                        Picker("WiFi Channel", selection: $viewModel.selectedChannel) {
                            ForEach(viewModel.availableChannels, id: \.self) { channel in
                                Text("Channel \(channel)").tag(channel)
                            }
                        }
                        
                        // Transmit Power
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Transmit Power")
                            
                            HStack {
                                Text("Low")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Slider(
                                    value: Binding(
                                        get: { Double(viewModel.transmitPower) },
                                        set: { viewModel.transmitPower = Int($0) }
                                    ),
                                    in: 0...4,
                                    step: 1
                                )
                                
                                Text("High")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text("\(viewModel.transmitPower)")
                                    .font(.caption)
                                    .frame(width: 20)
                                    .foregroundColor(.primary)
                            }
                            
                            Text(viewModel.getTransmitPowerLabel(for: viewModel.transmitPower))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Device Information Section
                    Section(header: Text("Device Information")) {
                        HStack {
                            Text("Firmware Version")
                            Spacer()
                            Text(viewModel.firmwareVersion)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Device ID")
                            Spacer()
                            Text(viewModel.deviceID)
                                .foregroundColor(.secondary)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                    
                    // Saved Networks Section
                    Section(header: 
                        HStack {
                            Text("Saved Networks")
                            Spacer()
                            if viewModel.savedNetworks.isEmpty {
                                Text("None")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("\(viewModel.savedNetworks.count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    ) {
                        if viewModel.savedNetworks.isEmpty {
                            Text("No saved networks")
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            ForEach(viewModel.savedNetworks) { network in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(network.ssid)
                                            .font(.body)
                                        Text("Last connected: \(network.lastConnectedText)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Button("Forget") {
                                        networkToForget = network
                                        showingForgetConfirmation = true
                                    }
                                    .font(.caption)
                                    .foregroundColor(.red)
                                }
                            }
                        }
                    }
                    
                    // Status Section
                    if !viewModel.statusMessage.isEmpty {
                        Section {
                            Text(viewModel.statusMessage)
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    
                    // Validation Errors Section
                    if viewModel.hasValidationErrors {
                        Section(header: Text("Validation Errors").foregroundColor(.red)) {
                            ForEach(viewModel.validationErrorMessages, id: \.self) { error in
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                    }
                }
                .disabled(viewModel.isLoading)
                
                // Loading Overlay
                if viewModel.isLoading {
                    Rectangle()
                        .fill(Color.black.opacity(0.3))
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        
                        Text("Communicating with device...")
                            .foregroundColor(.white)
                            .font(.headline)
                    }
                    .padding(32)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(16)
                }
            }
            .navigationTitle("Megadish Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isLoading)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button("Reload") {
                            Task {
                                await viewModel.loadSettings()
                            }
                        }
                        .disabled(viewModel.isLoading)
                        
                        Button("Save") {
                            Task {
                                await viewModel.saveSettings()
                            }
                        }
                        .disabled(viewModel.isLoading || !viewModel.areSettingsValid)
                        .fontWeight(.semibold)
                    }
                }
            }
        }
        .alert("Megadish Settings", isPresented: $viewModel.showAlert) {
            Button("OK") { }
        } message: {
            Text(viewModel.alertMessage)
        }
        .alert("Forget Network", isPresented: $showingForgetConfirmation) {
            Button("Cancel", role: .cancel) {
                networkToForget = nil
            }
            Button("Forget", role: .destructive) {
                if let network = networkToForget {
                    Task {
                        await viewModel.forgetNetwork(network)
                    }
                }
                networkToForget = nil
            }
        } message: {
            if let network = networkToForget {
                Text("Are you sure you want to forget the network '\(network.ssid)'?")
            }
        }
        .task {
            // Load settings and saved networks when the view appears
            await viewModel.loadSettings()
            // Also refresh saved networks separately to ensure we get the latest
            await viewModel.loadSavedNetworks()
        }
    }
}

// Preview
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a mock wireless service for preview
        let mockService = WirelessService()
        let viewModel = SettingsViewModel(wirelessService: mockService)
        
        // Set some sample data
        viewModel.accessPointName = "Megadish-Preview"
        viewModel.accessPointPassword = "test1234"
        viewModel.selectedChannel = 6
        viewModel.transmitPower = 2
        viewModel.firmwareVersion = "1.2.3"
        viewModel.deviceID = "MD-123456789ABC"
        
        // Add some sample saved networks
        viewModel.savedNetworks = [
            SettingsViewModel.SavedNetwork(ssid: "Home-WiFi", lastConnected: Date()),
            SettingsViewModel.SavedNetwork(ssid: "Office-Network", lastConnected: Date().addingTimeInterval(-86400)),
            SettingsViewModel.SavedNetwork(ssid: "Guest-WiFi", lastConnected: Date().addingTimeInterval(-172800))
        ]
        
        return SettingsView(viewModel: viewModel)
    }
}