# Build Anyone Browser
## Build Dependencies

Anyone Browser uses [CocoaPods](https://cocoapods.org/) as its dependency manager.


## Steps to build Anyone Browser

```bash
git clone git@github.com:anyone-protocol/AnyoneBrowser.git
cd AnyoneBrowser
git checkout main
pod repo update
pod install
open AnyoneBrowser.xcworkspace
```

## Edit Config.xcconfig

Instead of changing signing/release-related configuration in the main project configuration 
(which mainly edits the `project.pbxproj` file), do it in `Config.xcconfig` instead, which avoids
accidental checkins of sensitive information.

You will at least need to edit the `PRODUCT_BUNDLE_IDENTIFIER[config=Debug]` line to be able to run
the app in a simulator. 

Make sure, you didn't accidentally remove the references to that in `project.pbxproj`!
