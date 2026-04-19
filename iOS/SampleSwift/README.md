# SampleSwift
SampleSwift is a sample iOS app project demonstrating the use of Sonar in a Swift app.

## Building
This project is a legacy CocoaPods sample and is no longer the recommended
validation path for Flopper KMP artifacts.

Use the podless Apple smoke build from the repository root instead:

```bash
./gradlew :flopper-ios:assembleFlopperKitKmpXCFramework
./scripts/verify-apple-xcframework.sh
```
