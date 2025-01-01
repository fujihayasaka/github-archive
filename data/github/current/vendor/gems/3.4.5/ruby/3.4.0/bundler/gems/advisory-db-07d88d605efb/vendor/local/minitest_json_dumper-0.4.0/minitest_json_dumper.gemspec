# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'minitest_json_dumper/version'

Gem::Specification.new do |spec|
  spec.name          = "minitest_json_dumper"
  spec.version       = MinitestJSONDumper::VERSION
  spec.authors       = ["Misty De Meo"]
  spec.email         = ["mistydemeo@github.com"]

  spec.summary       = %q{JSON output for minitest failures.}
  spec.description   = %q{Prints CI-readable JSON for every test failure/error.}
  spec.homepage      = "https://github.com/github/minitest_json_dumper"

  spec.files         = Dir.chdir(File.expand_path("..", __FILE__)) do
    Dir.glob("**/*").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "minitest-reporters", "~> 1.1", ">= 1.1.14"
  spec.add_dependency "rollup", "~> 0.4"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake", "~> 13.1"
  spec.add_development_dependency "minitest", "~> 5.0"
end
