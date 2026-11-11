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
ENV["DISABLE_TEST_SERVICES"] = "1" # Prevent automatic test services startup in tests
ENV["DISABLE_PRELOAD"] = "true" # Disable preload for this service

# Load Rails environment
require_relative "../../config/environment"

# Load the test helper service
require_relative "app"

$LOAD_PATH << "test"

require "minitest/rails_plugin"
require "test_helper"

# Create the REST API application
app = TestHelperService::App.new

# Mount the fixture creation endpoint
map "/fixtures" do
  run app
end

# Mount the reset endpoint
map "/reset" do
  run app
end

# Mount the truncate endpoint
map "/truncate" do
  run app
end

map "/start_services" do
  run app
end

# Mount the export_env endpoint
map "/export_env" do
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
      note: "This service is only available in test environment",
      endpoints: {
        health_check: {
          path: "/health",
          method: "GET",
          description: "Health check endpoint",
        },
        fixtures: {
          path: "/fixtures",
          method: "POST",
          description: "Create test fixtures using FactoryBot",
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
        },
        reset: {
          path: "/reset",
          method: "POST",
          description: "Reset test state (calls reset_everything and re-initializes DGit)",
          example: {
            response: {
              success: true,
              message: "Reset completed",
            },
          },
        },
        truncate: {
          path: "/truncate",
          method: "POST",
          description: "Truncate all database tables across all clusters",
          example: {
            response: {
              success: true,
              message: "Databases truncated",
            },
          },
        },
        start_services: {
          path: "/start_services",
          method: "POST",
          description: "Start test services for CI",
          example: {
            response: {
              success: true,
              message: "Test services started",
              pids: { reposd: 12345, pullsd: 12346 },
            },
          },
        },
        export_env: {
          path: "/export_env",
          method: "GET",
          description: "Export environment variables for a specific test service to a file",
          parameters: {
            app: "Service name (e.g., reposd, pullsd, gotauth)",
            env_dest: "Destination file path for the environment variables",
          },
          example: {
            request: "GET /export_env?app=reposd&env_dest=/tmp/reposd.env",
            response: {
              success: true,
              path: "/tmp/reposd.env",
            },
          },
        },
      },
    }
    [200, { "Content-Type" => "application/json" }, [info.to_json]]
  }
end
