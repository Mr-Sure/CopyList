import SwiftUI

struct UpdateChecker: ObservableObject {
    @Published var hasUpdate = false
    @Published var latestVersion = ""
    @Published var downloadURL = ""
    
    let currentVersion = "1.0.0"
    let updateCheckURL = "https://raw.githubusercontent.com/yourusername/copylist/main/version.json"
    
    func checkForUpdates() {
        guard let url = URL(string: updateCheckURL) else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = json["version"] as? String,
                  let download = json["download"] as? String else { return }
            
            DispatchQueue.main.async {
                self.latestVersion = version
                self.downloadURL = download
                self.hasUpdate = self.compareVersions(self.currentVersion, version)
            }
        }.resume()
    }
    
    private func compareVersions(_ current: String, _ latest: String) -> Bool {
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }
        
        for i in 0..<max(currentParts.count, latestParts.count) {
            let c = i < currentParts.count ? currentParts[i] : 0
            let l = i < latestParts.count ? latestParts[i] : 0
            if l > c { return true }
            if l < c { return false }
        }
        return false
    }
    
    func openDownloadPage() {
        if let url = URL(string: downloadURL) {
            NSWorkspace.shared.open(url)
        }
    }
}
