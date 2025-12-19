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
  pod 'MBProgressHUD', :git => 'https://github.com/jdg/MBProgressHUD.git', :commit => '4a7c5f3e53cdea77c5dcb8578c2ee5acacdf6781'
  pod 'Eureka', '~> 5.5'
  pod 'ImageRow', :git => 'https://github.com/erickyim/ImageRow.git', :commit => 'd38369b8894425a9225ccf1e267226833b1950f0'

  pod 'SwiftSoup', '~> 2.7'

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
