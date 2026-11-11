#!/usr/bin/env ruby
# frozen_string_literal: true

require "webrick"
require "google/protobuf"
require "time"

require File.expand_path("../../config/basic", __FILE__)

require_relative "./dependabot-api-twirp-mock/repository_access_service"
require_relative "./dependabot-api-twirp-mock/suggested_fixes_service"

include RepositoryAccessService
include SuggestedFixesService

PORT_NO = 8765
BIND_ADDRESS = "0.0.0.0"

def log_to_console(msg)
  puts "[dependabot-api-twirp-mock] #{msg}"
end

def log_request(req)
  log_to_console("Received request at #{Time.now}")
  log_to_console("Request Method: #{req.request_method}")
  log_to_console("Request URI: #{req.request_uri}")
  log_to_console("Request Headers: #{req.header.inspect}")
  log_to_console("Request Body: #{req.body.inspect}")
end

def decode_protobuf_request(req, proto_class)
  begin
    # Deserialize the Protobuf request
    proto_class.decode(req.body)
  rescue Google::Protobuf::ParseError => e
    log_to_console("Failed to parse Protobuf body: #{e.message}")
    nil
  end
end

def json_response(res, object, status: 200)
  res.status = status
  res.body = object.to_json
  res["Content-Type"] = "application/json"
end

def proto_response(res, object, status: 200)
  res.status = status
  res.body = object.to_proto
  res["Content-Type"] = "application/protobuf"
end

# Basic WEBrick server to mock the response.
server = WEBrick::HTTPServer.new(
  Port: PORT_NO,
  BindAddress: BIND_ADDRESS,
  RequestCallback: ->(req, _) { log_request(req) }
)

# Gracefully shut down the server on CTRL+C
trap("INT") { server.shutdown }

# Include mocked service methods
mock_repository_access_service(server)
mock_suggested_fixes_service(server)

# Start the server
log_to_console("Starting listener on #{BIND_ADDRESS}:#{PORT_NO}...")
log_to_console("Export the following environment variables in your dotcom server bash console to use this server:")
log_to_console("export DEPENDABOT_INTERNAL_URL=\"http://localhost:#{PORT_NO}/\"")
log_to_console("export DEPENDABOT_HMAC_KEY=\"dotcomhmac\"")
log_to_console("Press CTRL+C to stop the server.")
server.start
