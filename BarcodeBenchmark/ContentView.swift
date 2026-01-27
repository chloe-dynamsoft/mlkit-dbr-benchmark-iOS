import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: MainViewModel
    
    var body: some View {
        NavigationStack {
            HomeView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(MainViewModel())
}
