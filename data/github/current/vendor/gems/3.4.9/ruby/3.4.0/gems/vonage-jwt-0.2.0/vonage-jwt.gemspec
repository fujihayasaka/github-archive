# frozen_string_literal: true

require File.expand_path('lib/vonage-jwt/version', File.dirname(__FILE__))

Gem::Specification.new do |s|
  s.name = 'vonage-jwt'
  s.version = Vonage::JWT::VERSION
  s.license = 'MIT'
  s.platform = Gem::Platform::RUBY
  s.authors = ['Vonage']
  s.email = ['devrel@vonage.com']
  s.homepage = 'https://github.com/Vonage/vonage-jwt-ruby'
  s.description = 'Vonage JWT Generator for Ruby'
  s.summary = 'This is the Ruby client library to generate Vonage JSON Web Tokens (JWTs).'
  s.files = Dir.glob('lib/**/*.rb') + %w[LICENSE.txt README.md vonage-jwt.gemspec]
  s.required_ruby_version = '>= 2.5.0'
  s.add_dependency('jwt', '~> 2')
  s.require_path = 'lib'
  s.metadata = {
    'homepage' => 'https://github.com/Vonage/vonage-jwt-ruby',
    'source_code_uri' => 'https://github.com/Vonage/vonage-jwt-ruby',
    'bug_tracker_uri' => 'https://github.com/Vonage/vonage-jwt-ruby/issues',
    'changelog_uri' => 'https://github.com/Vonage/vonage-jwt-ruby/blob/main/CHANGES.md',
    'documentation_uri' => 'https://rubydoc.info/github/Vonage/vonage-jwt-ruby'
  }
end
