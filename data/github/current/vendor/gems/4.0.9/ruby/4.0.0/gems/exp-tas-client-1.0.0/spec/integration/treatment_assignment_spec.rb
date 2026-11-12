# frozen_string_literal: true

# Integration tests for the generated Ruby client.
# These tests require a running exp-tas server (e.g., EXP_MODE=mem make run).
#
# Run with: cd client-ruby && bundle exec rspec spec/integration --tag integration

require "spec_helper"
require "uri"

RSpec.describe "Treatment Assignment Integration", :integration do
  let(:server_url) { ENV.fetch("EXP_TAS_URL", "http://localhost:18080/api/v1") }
  let(:api) do
    uri = URI.parse(server_url)
    config = ExpTasClient::Configuration.new
    config.scheme = uri.scheme
    config.host = "#{uri.host}:#{uri.port}"
    config.base_path = uri.path
    ExpTasClient::DefaultApi.new(ExpTasClient::ApiClient.new(config))
  end

  it "returns a valid assignment response" do
    request = ExpTasClient::AssignmentRequest.new(
      user_params: { "user_id" => "integration-test-user", "clientid" => "integration-test" }
    )

    result = api.get_treatment_assignment(request)

    expect(result).to be_a(ExpTasClient::AssignmentResponse)
    expect(result.feature_variables).to be_a(Hash)
    expect(result.assigned_variants).to be_an(Array)
    expect(result.data_version).to be_a(Integer)
    expect(result.assignment_context).to be_a(String)
  end

  it "accepts optional scopes and required variants" do
    request = ExpTasClient::AssignmentRequest.new(
      user_params: { "user_id" => "integration-test-user" },
      scopes: ["my_scope"],
      required_variants: ["nonexistent-variant"]
    )

    result = api.get_treatment_assignment(request)

    expect(result).to be_a(ExpTasClient::AssignmentResponse)
    expect(result.feature_variables).to be_a(Hash)
  end

  it "raises ApiError on invalid request" do
    request = ExpTasClient::AssignmentRequest.new(user_params: { "" => "value" })

    expect { api.get_treatment_assignment(request) }.to raise_error(ExpTasClient::ApiError) do |e|
      expect(e.code).to eq(400)
    end
  end
end
