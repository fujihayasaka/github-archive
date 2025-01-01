require "vcr"

VCR.configure do |c|
  c.ignore_hosts "127.0.0.1", "127.0.0.2", "localhost"
  c.cassette_library_dir = "test/vcr_cassettes"
  c.default_cassette_options = {
   match_requests_on: [:method, VCR.request_matchers.uri_without_param(:page)]
  }
  c.hook_into :webmock
end
