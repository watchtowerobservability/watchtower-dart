Pod::Spec.new do |s|
  s.name          = 'watchtower'
  s.version       = '0.1.1'
  s.summary       = 'Flutter plugin layer over the native Watchtower iOS SDK (crashes, hangs, crash-loop guard).'
  s.license       = 'Apache-2.0'
  s.homepage      = 'https://github.com/watchtowerobservability/watchtower-dart'
  s.authors       = 'Watchtower'
  s.source        = { :path => '.' }
  s.source_files  = 'Classes/**/*.swift'
  s.platform      = :ios, '13.0'
  s.swift_version = '5.9'
  s.dependency 'Flutter'
  # The native iOS SDK (sdks/ios/WatchtowerSDK.podspec, mirrored as watchtower-ios). This pod must be
  # named `watchtower` (Flutter names it after the Dart package), so the native pod is `WatchtowerSDK`:
  # a `Watchtower` pod would clash with it case-insensitively.
  s.dependency 'WatchtowerSDK', s.version.to_s
end
