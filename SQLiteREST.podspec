#
# Be sure to run `pod lib lint SQLiteREST.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'SQLiteREST'
  s.version          = '0.0.4-alpha.1'
  s.summary          = 'A lightweight RESTful service for SQLite databases running on iOS devices. '
  s.swift_version = '5.0'
  s.platform = :ios, '13.0'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = 'A lightweight RESTful service for SQLite databases running on iOS devices. SQLiteREST provides a simple web UI that allows you to view and edit your SQLite database in real-time, making it extremely convenient for development and QA testing. No more manually exporting sandbox files to troubleshoot issues!'

  s.homepage         = 'https://github.com/weirui-kong/SQLiteREST'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Weirui Kong' => 'weiruik@outlook.com' }
  s.source           = { :git => 'https://github.com/weirui-kong/SQLiteREST.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '13.0'

  s.source_files = 'SQLiteREST/Classes/**/*'
  
  s.resource_bundles = {
    'SQLiteREST' => ['SQLiteREST/Classes/*.html']
  }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  s.dependency 'GCDWebServer', '~> 3.0'
end
