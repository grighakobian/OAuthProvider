Pod::Spec.new do |s|
  s.name             = 'OAuthProvider'
  s.version          = '0.1.0'
  s.summary          = 'A short description of OAuthProvider.'

  s.description      = <<-DESC
 TODO: Add long description of the pod here.
                        DESC
  s.homepage         = 'https://github.com/grighakobian/OAuthProvider'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Grigor Hakobyan' => 'grighakobian@gmail.com' }
  s.source           = { :git => 'https://github.com/grighakobian/OAuthProvider.git', :tag => s.version.to_s }

  s.default_subspec = "Core"
  s.swift_version = '5.0'
  s.cocoapods_version = '>= 1.4.0'
  s.ios.deployment_target = '10.0'
  s.osx.deployment_target = '10.12'
  s.tvos.deployment_target = '10.0'
  s.watchos.deployment_target = '3.0'
  
  s.subspec "Core" do |ss|
    ss.source_files  = "Sources/Core/"
    s.dependency 'Moya', '~> 14.0'
    ss.framework  = "Foundation"
  end
  
  s.subspec "RxSwift" do |ss|
    ss.source_files = "Sources/Rx/"
    ss.dependency "OAuthProvider/Core"
    ss.dependency "RxSwift", "~> 5.0"
  end
  
  s.subspec "ReactiveSwift" do |ss|
    ss.source_files = "Sources/Reactive/"
    ss.dependency "OAuthProvider/Core"
    ss.dependency "ReactiveSwift", "~> 6.0"
  end
  
end
