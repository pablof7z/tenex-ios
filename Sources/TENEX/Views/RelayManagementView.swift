import SwiftUI
import NDKSwift
import NDKSwiftUI

struct RelayManagementView: View {
    @Environment(NostrManager.self) var nostrManager

    var body: some View {
        NDKUIRelayManagementView(ndk: nostrManager.ndk)
    }
}