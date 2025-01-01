# typed: true
# frozen_string_literal: true

require "test_helper"

# Traffic mirroring
class Api::TrafficMirroringTest < GitHub::TestCase
  include PlatformTestHelpers::InterfaceHelpers

  teardown do
    GitHub.rate_limiting_enabled = nil
  end

  def test_mirrored_request
    # Test when request is mirrored
    request = Rack::Request.new({ "HTTP_X_GITHUB_MIRRORED_REQUEST" => "1" })
    assert Api::TrafficMirroring.mirrored_request?(request)

    # Test when request is not mirrored
    request = Rack::Request.new({})
    refute Api::TrafficMirroring.mirrored_request?(request)
  end

  def test_mutation_is_blocked_in_shadow_lab
    GitHub.stub(:deployed_to, "shadow-lab") do
      mutation = <<-'GRAPHQL'
        mutation($input: ReportBrowserErrorInput!) {
          reportBrowserError(input: $input) {
            __typename
          }
        }
      GRAPHQL

      input = { error: { type: "Error", value: "b00m", stacktrace: [] } }
      response = Platform.execute(mutation, variables: { input: input }, target: :internal)

      refute_predicate response, :success?, "Expected an error response, but didn't get one: #{response.to_h}"
      assert_error_response(response.errors,
        message: "The reportBrowserError mutation is not allowed.",
        locations: [{ "line" => 2, "column" => 11 }],
        type: "UNAUTHENTICATED",
      )
    end
  end

  def test_mutation_is_not_blocked_outside_of_shadow_lab
    mutation = <<-'GRAPHQL'
      mutation($input: ReportBrowserErrorInput!) {
        reportBrowserError(input: $input) {
          __typename
        }
      }
    GRAPHQL

    input = { error: { type: "Error", value: "b00m", stacktrace: [] } }
    response = Platform.execute(mutation, variables: { input: input }, target: :internal)

    assert_predicate response, :success?, "Expected an error response, but didn't get one: #{response.to_h}"
  end

  if !GitHub.enterprise?
    def test_rate_limiting_is_disabled_in_shadow_lab
      GitHub.stub(:deployed_to, "shadow-lab") do
        refute GitHub.rate_limiting_enabled?
      end
    end

    def test_rate_limiting_is_enabled_outside_of_shadow_lab
      assert GitHub.rate_limiting_enabled?
    end
  end
end
