import SwiftUI
import FamilyControls

struct ContentView: View {
    @StateObject var model = ScreenTimeSelectAppsModel.shared
    @State private var isAuthorizationAlertPresented = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Button("Select Apps to Block") {
                    Task {
                        await requestAuthorizationAndShowPicker()
                    }
                }
                .buttonStyle(.borderedProminent)

                let selectionCount = model.activitySelection.applicationTokens.count + model.activitySelection.categoryTokens.count + model.activitySelection.webDomainTokens.count
                if selectionCount > 0 {
                    Text("\(selectionCount) item(s) selected.")
                }

                if !model.isBlockingActive {
                    Button("Block Selected Apps (1 Hour)") {
                        model.startBlocking(durationHours: 1)
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectionCount == 0)
                } else {
                    Button("Stop Blocking") {
                        model.stopBlocking()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                Spacer()

                Text(model.isBlockingActive ? "Blocking is Active" : "Blocking is Inactive")
                    .font(.headline)
                    .padding()
                Text("Note: Blocking may not affect certain system apps, apps with special permissions (like MDM or some security apps), or ScreenGamba itself.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .navigationTitle("App Blocker")
            .padding()
            .familyActivityPicker(
                isPresented: $model.isPickerPresented,
                selection: $model.activitySelection
            )
            .alert("Authorization Required", isPresented: $isAuthorizationAlertPresented) {
                 Button("OK", role: .cancel) { }
                 Button("Open Settings") {
                     if let url = URL(string: UIApplication.openSettingsURLString) {
                         UIApplication.shared.open(url)
                     }
                 }
            } message: {
                 Text("Please grant Screen Time permissions to select apps. This is usually managed in the main Settings > Screen Time section, not within this app's specific settings page.")
            }
            
        }
    }

    @MainActor
    private func requestAuthorizationAndShowPicker() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)

            print("Authorization successful or already granted.")
            model.isPickerPresented = true // Show the picker

        } catch {
            print("Authorization failed: \(error.localizedDescription)")
            isAuthorizationAlertPresented = true
        }
    }
}

