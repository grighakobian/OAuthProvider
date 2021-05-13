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
  s.ios.deployment_target = '12.0'
  
  s.subspec "Core" do |ss|
    ss.source_files  = "Sources/Core/"
    s.dependency 'Moya', '~> 14.0'
    ss.framework  = "Foundation"
  end
  
end
