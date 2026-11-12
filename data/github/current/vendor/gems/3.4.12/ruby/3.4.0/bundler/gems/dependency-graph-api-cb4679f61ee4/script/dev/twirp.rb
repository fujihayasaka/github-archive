#! /usr/bin/env ruby

require "json"
require "net/http"
require "uri"

require_relative "../../config/environment"
require_relative "../../app/services/services"

##############
# twirp.rb
#
# Simple client for calling Twirp endpoints using natural-ish command line arguments in development.
#
# Usage:
#
# The first argument is the service, the second is the operation, and the third is a list of properties
# that will get parsed into a json object.
# Remember to escape double quotes as necessary, or just pass in an object (using Ruby syntax):
#
#   script/dev/twirp.rb repository_dependencies get_dependencies_for_repository repository_id: 1, other_arg: '"hello"'
#
# Or,
#
#   script/dev/twirp.rb repository_dependencies get_dependencies_for_repository 'repository_id: 1, other_arg: "hello"'

service = ARGV.shift
service_path = Services.send(service).mount_path

operation = ARGV.shift
operation_name = operation.camelize

# rubocop:disable Security/Eval
args = eval("{#{ARGV.join(' ')}}")

uri = URI("http://localhost:9596/#{service_path}/#{operation_name}")

puts "POST #{uri}"
jj args
puts

req = Net::HTTP::Post.new(uri)
req["Content-Type"] = "application/json"
req.set_body_internal(JSON.dump(args))

res = Net::HTTP.start(uri.hostname, uri.port) do |http|
  http.request(req)
end

puts "#{res.code} #{res.message}"
jj JSON.parse(res.body) if res.body.length > 0
