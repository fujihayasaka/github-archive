# frozen_string_literal: true
# typed: true

require "vexi_management"
require "net/http"
require "uri"
require "json"
require "socket"

# To verify the Checks and Management local HMACs
def req_hmac(hmac_key)
  ts = Time.now.to_i.to_s
  digest = OpenSSL::Digest.new("sha256")
  sign_bytes = OpenSSL::HMAC.digest(digest, hmac_key, ts)
  sign_hex = sign_bytes.unpack1("H*")
  "#{ts}.#{sign_hex}"
end

# Following the same way Postman creates a feature flag for testing with the Management API
def management_call(url, body)
  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)

  request = Net::HTTP::Post.new(uri.path)
  request["Content-Type"] = "application/json"
  request["X-GitHub-User"] = "@test_user"
  request["Request-HMAC"] = req_hmac("management-key-1")
  request.body = body.to_json
  response = http.request(request)

  response.body
end

def build_segment_member_body(segment_json)
  {
    "segment_name" => segment_json["name"],
    "member_ids" => segment_json["actors"]
  }
end

def build_ff_body(ff_json)
  ff_body = {
    "feature" => {
      "name" => ff_json["name"],
      "tracking_url" => "https://github.com/github/github/issues/1",
      "description" => "description",
      "slack_channel" => "slackChannel",
      "owning_service" => ff_json["owning_service"],
      "long_lived" => false,
      "nodes" => ff_json["nodes"].nil? ? [] : ff_json["nodes"],
      "etag" => ff_json["etag"].nil? ? "" : ff_json["etag"]
    }
  }

  embedded_segment_body = if !ff_json["actors"].nil? && !ff_json["actors"].empty?
                            {
                              "segment_name" => ff_json["default_segment"],
                              "member_ids" => ff_json["actors"]
                            }
                          else
                            []
                          end

  [ff_body, embedded_segment_body]
end

def create_demo_examples
  ff_url = "http://localhost:8090/twirp/feature_management.feature_flags.management.v3.FeatureFlags/"
  segment_url = "http://localhost:8090/twirp/feature_management.feature_flags.management.v3.SegmentMembers/AddMembers"

  Dir.glob("examples/feature_flags/*.json").each do |file|
    file_content = File.read(file)
    ff_json = JSON.parse(file_content)

    state = FeatureManagement::FeatureFlags::Data::V1::FeatureFlagState.lookup(ff_json["state"]).to_s
    ff_body, embedd_segment_body = build_ff_body(ff_json)
    management_call("#{ff_url}CreateFeatureFlag", ff_body)
    management_call(segment_url, embedd_segment_body) unless embedd_segment_body.empty?

    next unless ff_json["state"] != "1"

    ff_get_body = {
      "name" => ff_json["name"]
    }
    ff_get_json = JSON.parse(management_call("#{ff_url}GetFeatureFlag", ff_get_body))
    node_list = []
    ff_get_json["nodes"].each do |node|
      node_list << {
        "name" => node["name"],
        "state" => state,
        "parent" => node["parent"],
        "percentage_of_calls" => {
          "enabled" => !ff_json["percentage_of_calls"].zero?,
          "value" => ff_json["percentage_of_calls"].nil? ? 0 : ff_json["percentage_of_calls"]
        },
        "percentage_of_actors" => {
          "enabled" => !ff_json["percentage_of_actors"].zero?,
          "value" => ff_json["percentage_of_actors"].nil? ? 0 : ff_json["percentage_of_actors"]
        },
        "custom_gates" => {
          "enabled" => !ff_json["custom_gates"].empty?,
          "values" => ff_json["custom_gates"].nil? ? [] : ff_json["custom_gates"]
        }
      }
    end

    ff_json["nodes"] = node_list
    ff_json["etag"] = ff_get_json["etag"]
    ff_update_body, = build_ff_body(ff_json)
    management_call("#{ff_url}UpdateFeatureFlag", ff_update_body)
  end

  Dir.glob("examples/segments/*.json").each do |file|
    file_content = File.read(file)
    segment_json = JSON.parse(file_content)

    body = build_segment_member_body(segment_json)
    management_call(segment_url, body)
  end

  # Wait for the feature flags to be loaded on the FFH side
  sleep(5)
end
