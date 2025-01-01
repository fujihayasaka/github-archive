#!/usr/bin/env ruby
# frozen_string_literal: true

require "webrick"
require "google/protobuf"
require "time"
require "proto-dependabot-api"

PORT_NO = 8765
BIND_ADDRESS = "0.0.0.0"

# Create the mock Protobuf response
def mock_suggested_fix_response
  suggested_fix = DependabotApi::V1::SuggestedFix.new(
    id: 1,
    autofix_job_id: 123456,
    description: "The breaking change detected by Dependabot is due to the use of the _.pluck method from the lodash library, which was removed in version 4.17.21. To fix this issue, we need to replace the _.pluck method with an equivalent method that is still supported in the latest version of lodash. The _.map method can be used as a replacement for _.pluck.",
    files: [
      DependabotApi::V1::SuggestedFixFile.new(
        file_path: "lodash-example/src/main-test.js",
        diff_content: "diff --git a/lodash-example/src/main-test.js b/lodash-example/src/main-test.js\n--- a/lodash-example/src/main-test.js\n+++ b/lodash-example/src/main-test.js\n@@ -1,7 +1,7 @@\n const _ = require('lodash');\n \n function getNames(users) {\n-  return _.pluck(users, 'user');\n+  return _.map(users, 'user');\n }\n \n // Test function\n",
        created_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i, nanos: Time.now.nsec),
        updated_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i, nanos: Time.now.nsec)
      )
    ],
    review_status: DependabotApi::V1::SuggestedFix::SuggestedFixReviewStatus::STATUS_UNREVIEWED,
    created_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i, nanos: Time.now.nsec),
    updated_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i, nanos: Time.now.nsec),
    dependency_metadata: []
  )

  DependabotApi::V1::GetSuggestedFixResponse.new(suggested_fix: suggested_fix)
end

def mock_apply_suggested_fix_response
  DependabotApi::V1::ApplySuggestedFixResponse.new(success: true)
end

def log_request(req)
  puts "[dependabot-autofix-mock] Received request at #{Time.now}"
  puts "[dependabot-autofix-mock] Request Method: #{req.request_method}"
  puts "[dependabot-autofix-mock] Request URI: #{req.request_uri}"
  puts "[dependabot-autofix-mock] Request Headers: #{req.header.inspect}"
  puts "[dependabot-autofix-mock] Request Body: #{req.body.inspect}"
end

# Basic WEBrick server to mock the response.
server = WEBrick::HTTPServer.new(
  Port: PORT_NO,
  BindAddress: BIND_ADDRESS
)

# Gracefully shut down the server on CTRL+C
trap("INT") { server.shutdown }

# Mock endpoint to respond to `/twirp/DependabotApi.v1.SuggestedFixes/GetSuggestedFix`
server.mount_proc "/twirp/DependabotApi.v1.SuggestedFixes/GetSuggestedFix" do |req, res|
  # Log incoming request details
  log_request(req)

  # Validate and parse Protobuf request body
  begin
    # Deserialize the Protobuf request
    request_proto = DependabotApi::V1::GetSuggestedFixRequest.decode(req.body)
  rescue Google::Protobuf::ParseError => e
    puts "[dependabot-autofix-mock] Failed to parse Protobuf body: #{e.message}"
    res.status = 400
    res.body = { error: "Invalid Protobuf format" }.to_json
    res["Content-Type"] = "application/json"
    next
  end

  # Extract parameters from the request
  autofix_job_id = request_proto.autofix_job_id
  github_pull_request_number = request_proto.github_pull_request_number
  github_repo_id = request_proto.github_repo_id

  if autofix_job_id.nil? || github_pull_request_number.nil? || github_repo_id.nil?
    puts "[dependabot-autofix-mock] Missing required parameters"
    res.status = 422
    res.body = { error: "Missing required parameters: autofix_job_id, github_pull_request_number, github_repo_id" }.to_json
    res["Content-Type"] = "application/json"
    next
  end

  # Log the incoming parameters
  puts "[dependabot-api] Params: autofix_job_id=#{autofix_job_id}, github_pull_request_number=#{github_pull_request_number}, github_repo_id=#{github_repo_id}"

  # Create the Protobuf response
  proto_response = mock_suggested_fix_response
  res.body = proto_response.to_proto
  res["Content-Type"] = "application/protobuf"
end

server.mount_proc "/twirp/DependabotApi.v1.SuggestedFixes/ApplySuggestedFix" do |req, res|
  # Log incoming request details
  log_request(req)

  # Validate and parse Protobuf request body
  begin
    # Deserialize the Protobuf request
    request_proto = DependabotApi::V1::ApplySuggestedFixRequest.decode(req.body)
  rescue Google::Protobuf::ParseError => e
    puts "[dependabot-autofix-mock] Failed to parse Protobuf body: #{e.message}"
    res.status = 400
    res.body = { error: "Invalid Protobuf format" }.to_json
    res["Content-Type"] = "application/json"
    next
  end

  autofix_job_id = request_proto.autofix_job_id
  github_pull_request_number = request_proto.github_pull_request_number
  github_repo_id = request_proto.github_repo_id

  if autofix_job_id.nil? || github_pull_request_number.nil? || github_repo_id.nil?
    puts "[dependabot-autofix-mock] Missing required parameters"
    res.status = 422
    res.body = { error: "Missing required parameters: autofix_job_id, github_pull_request_number, github_repo_id" }.to_json
    res["Content-Type"] = "application/json"
    next
  end

  # Log the incoming parameters
  puts "[dependabot-api] Params: autofix_job_id=#{autofix_job_id}, github_pull_request_number=#{github_pull_request_number}, github_repo_id=#{github_repo_id}"

  # Create the Protobuf response
  proto_response = mock_apply_suggested_fix_response
  res.body = proto_response.to_proto
  res["Content-Type"] = "application/protobuf"
end

# Start the server
puts "[dependabot-autofix-mock] Starting listener on #{BIND_ADDRESS}:#{PORT_NO}..."
server.start
