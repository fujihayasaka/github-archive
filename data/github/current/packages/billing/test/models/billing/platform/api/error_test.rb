# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Platform::Api::ErrorTest < GitHub::TestCase
  context "#http_status" do
    test "returns 500 when original_error is not a Twirp::Error" do
      error = Billing::Platform::Api::Error.new("An error occurred")
      assert_equal 500, error.http_status
    end

    test "returns 500 when original_error is a Twirp::Error but code is invalid" do
      error = Billing::Platform::Api::Error.new("An error occurred", original_error: Twirp::Error.new("invalid_code", "An error occurred"))
      assert_equal 500, error.http_status
    end

    {
      canceled:             408, # Request Timeout
      invalid_argument:     400, # Bad Request
      malformed:            400, # Bad Request
      deadline_exceeded:    408, # Request Timeout
      not_found:            404, # Not Found
      bad_route:            404, # Not Found
      already_exists:       409, # Conflict
      permission_denied:    403, # Forbidden
      unauthenticated:      401, # Unauthorized
      resource_exhausted:   429, # Too Many Requests
      failed_precondition:  412, # Precondition Failed
      aborted:              409, # Conflict
      out_of_range:         400, # Bad Request

      internal:             500, # Internal Server Error
      unknown:              500, # Internal Server Error
      unimplemented:        501, # Not Implemented
      unavailable:          503, # Service Unavailable
      data_loss:            500, # Internal Server Error
    }.each do |code, status|
      test "returns #{status} when original_error is a Twirp::Error with code #{code}" do
        error = Billing::Platform::Api::Error.new("An error occurred", original_error: Twirp::Error.new(code, "An error occurred"))
        assert_equal status, error.http_status
      end
    end
  end

  context "#http_5xx?" do
    test "returns true when http_status is between 500 and 599" do
      error = Billing::Platform::Api::Error.new("An error occurred", original_error: Twirp::Error.new("internal", "An error occurred"))
      assert error.http_5xx?
    end

    test "returns false when http_status is not between 500 and 599" do
      error = Billing::Platform::Api::Error.new("An error occurred", original_error: Twirp::Error.new("not_found", "An error occurred"))
      refute error.http_5xx?
    end
  end
end
