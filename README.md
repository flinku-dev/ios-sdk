# FlinkuSDK for iOS

Native Swift SDK for Flinku deep linking. Supports iOS 14+.

## Installation

### Swift Package Manager
In Xcode: File → Add Package Dependencies
```
https://github.com/flinku/flinku-ios-sdk
```

## Usage

### AppDelegate
```swift
import FlinkuSDK

func application(_ application: UIApplication,
  didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

  Flinku.configure(FlinkuConfig(
    apiKey: "fku_live_your_key",
    debugMode: true
  ))

  return true
}
```

### SwiftUI App
```swift
import FlinkuSDK

@main
struct MyApp: App {
  init() {
    Flinku.configure(FlinkuConfig(
      apiKey: "fku_live_your_key",
      debugMode: true
    ))
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .task {
          let link = await Flinku.match()
          if link.matched {
            // Navigate to link.deepLink
          }
        }
    }
  }
}
```

## How It Works
1. User clicks a Flinku short link
2. Server records device fingerprint
3. User installs app
4. SDK calls match() on first launch
5. Server matches fingerprint → returns deep link
6. App navigates to correct screen
