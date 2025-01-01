  require 'rubygems'
  spec = eval(File.read("meuse-client.gemspec"), nil, "meuse-client.gemspec")
  spec.version = "1.17.1"
  spec
