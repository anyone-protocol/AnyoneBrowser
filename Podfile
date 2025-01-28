use_frameworks!

platform :ios, '17.0'

#source 'https://cdn.cocoapods.org/'
#source 'https://cocoapods-cdn.netlify.app/'
source 'https://github.com/CocoaPods/Specs.git'

target 'AnyoneBrowser' do
  pod 'DTFoundation/DTASN1'
  pod 'TUSafariActivity'

  pod 'SDCAlertView', '~> 12'
  pod 'FavIcon', :git => 'https://github.com/tladesignz/FavIcon.git'
  pod 'MBProgressHUD', '~> 1.2'
  pod 'Eureka', '~> 5.3'
  pod 'ImageRow', '~> 4.1'

  pod 'AnyoneKit',
    '~> 409'
#    :path => '../AnyoneKit'
end

target 'AnyoneBrowser Tests' do
  pod 'OCMock'
  pod 'DTFoundation/DTASN1'
end

# Fix Xcode 15 compile issues.
post_install do |installer|
  installer.pods_project.targets.each do |target|
    if target.respond_to?(:name) and !target.name.start_with?("Pods-")
      target.build_configurations.each do |config|
        if config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_f < 12
          config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '12.0'
        end
      end
    end
  end
end
