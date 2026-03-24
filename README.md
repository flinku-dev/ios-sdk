# FlinkuSDK

Official iOS SDK for [Flinku](https://flinku.dev) — deferred deep linking for iOS. The modern replacement for Firebase Dynamic Links.

**Version 0.2.0**

## Installation

### Swift Package Manager

In Xcode → File → Add Package Dependencies:

```
https://github.com/flinku-dev/ios-sdk
```

## Setup

Configure in your `AppDelegate` or `@main` App struct:

```swift
import FlinkuSDK

@main
struct MyApp: App {
    init() {
        Flinku.configure(baseUrl: "https://yourapp.flku.dev")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

## Handle deep links

Call `Flinku.match()` on app launch:

```swift
struct SplashView: View {
    var body: some View {
        ProgressView()
            .task {
                let link = await Flinku.match()
                if link.matched {
                    // Navigate to the correct screen
                    NavigationState.shared.deepLink = link.deepLink
                }
            }
    }
}
```

## With authentication flow

```swift
let link = await Flinku.match()

// After login completes
if link.matched {
    router.navigate(to: link.deepLink!)
} else {
    router.navigate(to: "/home")
}
```

## Query parameters

```swift
let link = await Flinku.match()

if link.matched, let params = link.params {
    let ref = params["ref"] as? String       // e.g. "instagram"
    let promo = params["promo"] as? String   // e.g. "SAVE20"
}
```

## Xcode configuration

1. Open Xcode → your target → **Signing & Capabilities**
2. Click **+ Capability** → **Associated Domains**
3. Add: `applinks:yourapp.flku.dev`

## Reset (testing only)

```swift
Flinku.reset()
```

## Requirements

- iOS 14+
- Swift 5.9+
