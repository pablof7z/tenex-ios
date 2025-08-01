import SwiftUI
import NDKSwift

struct ContentView: View {
    @Environment(NostrManager.self) var nostrManager
    @State private var privateKey = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if nostrManager.isAuthenticated {
                // Authenticated content
                MainTabView()
            } else {
                // Authentication view
                VStack(spacing: 20) {
                Text("TENEX")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Sign in with your Nostr key")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Private Key (nsec)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    SecureField("nsec1...", text: $privateKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                .padding(.horizontal)
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                Button(action: {
                    signIn()
                }) {
                    Text("Sign In")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isLoading ? Color.blue.opacity(0.6) : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .padding(.horizontal)
                .disabled(privateKey.isEmpty || isLoading)
                
                Spacer()
            }
            .padding(.top, 50)
            }
        }
        .onChange(of: nostrManager.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                // Authentication state will be handled by NostrManager's observation
                print("User authenticated")
            }
        }
    }
    
    private func signIn() {
        guard !privateKey.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // Login through nostrManager
                try await nostrManager.login(with: privateKey)
                
                // The NostrManager will automatically handle the session via auth state observation
                
                await MainActor.run {
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to sign in: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}