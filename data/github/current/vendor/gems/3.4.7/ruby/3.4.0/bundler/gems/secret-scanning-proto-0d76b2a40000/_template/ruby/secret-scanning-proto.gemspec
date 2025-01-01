# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |s|
  s.name          = 'secret-scanning-proto'
  s.version       = '0.0.1'
  s.authors       = 'GitHub'
  s.homepage      = 'https://github.com/github/secret-scanning-proto/tree/master/gen/ruby'
  s.summary       = 'Generated client/server code for Token Scanning Service API.'
  s.license       = 'Nonstandard'

  s.files         = Dir['**/*.rb']
  s.require_paths = ["lib".freeze]

  s.add_runtime_dependency 'faraday', '>= 0.15.4'
  s.add_runtime_dependency 'google-protobuf', '~> 3.9'
  s.add_dependency         'twirp', '~> 1.1'

  s.add_development_dependency 'rspec', '~> 3.9'
  s.add_development_dependency 'vcr', '~> 5.1'
  s.add_development_dependency 'webmock', '~> 3.14'
end

