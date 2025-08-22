// Add this to your AppDelegate or SceneDelegate to initialize signatures at app launch
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Load signatures when app starts
        SignatureScanner.loadSignatures()
        return true
    }
}
