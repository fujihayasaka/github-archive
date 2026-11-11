# frozen_string_literal: true

# Standalone Rack application for the Test Helper Service
# This service is ONLY available in test environments and runs separately from the main application.

# Ensure we're in test environment
unless ENV["RAILS_ENV"] == "test" || ENV["RACK_ENV"] == "test"
  puts "ERROR: Test Helper Service can only run in test environment"
  puts "Set RAILS_ENV=test or RACK_ENV=test"
  exit 1
end

# Set the environment
ENV["RAILS_ENV"] ||= "test"
ENV["RACK_ENV"] ||= "test"
ENV["SPOKESD_URL"] ||= "http://127.0.0.1:1343/twirp"

# Load Rails environment
require_relative "../../config/environment"

# Load the test helper service
require_relative "app"

$LOAD_PATH << "test"

require "minitest/rails_plugin"
require "test_helper"

# Initialize DGit fileservers (dgit1-dgit4) for test helper service
# This needs to happen once at server startup
::DGit.write_seed_data unless GitHub::DGit.get_hosts.any?

# Create the REST API application
app = TestHelperService::App.new

# Mount the fixture creation endpoint
map "/fixtures" do
  run app
end

# Health check endpoint
map "/health" do
  run lambda { |_|
    [200, { "Content-Type" => "text/plain" }, ["OK\n"]]
  }
end

# Root endpoint with service info
map "/" do
  run lambda { |_|
    info = {
      service: "Test Helper Service",
      version: "1.0.0",
      environment: Rails.env,
      endpoint: "/fixtures",
      method: "POST",
      health_check: "/health",
      note: "This service is only available in test environment",
      example: {
        request: {
          fixture_type: "user",
          attributes: { login: "testuser" },
        },
        response: {
          fixture: { id: 123, login: "testuser" },
          id: 123,
        },
      },
    }
    [200, { "Content-Type" => "application/json" }, [info.to_json]]
  }
end
