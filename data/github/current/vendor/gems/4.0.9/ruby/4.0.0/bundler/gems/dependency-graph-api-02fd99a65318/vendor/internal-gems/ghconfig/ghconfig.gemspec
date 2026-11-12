# coding: utf-8

Gem::Specification.new do |spec|
  spec.name          = "ghconfig"
  spec.version       = '1.0.2'
  spec.authors       = ["David Calavera"]
  spec.email         = ["david.calavera@gmail.com"]
  spec.description   = %q{Common GitHub configuration options}
  spec.summary       = %q{Common interface to make your application Enterprise ready™}
  spec.homepage      = "https://github.com/github/ghconfig"
  spec.license       = "MIT"

  # NOTE: This line has been changed from github/ghconfig so we don't need git installed
  spec.files         = Dir["lib/**/*", "LICENSE.txt", "README.md"]
  # spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
end
