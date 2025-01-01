# typed: true
# frozen_string_literal: true

require "fast/helper"

class SpokesAPIErrorTest < Test::Fast::TestCase
  def test_error_mappings
    check_error_mapping Twirp::Error.canceled("testing"),
      error_class: SpokesAPI::Canceled, message: "testing"
    check_error_mapping Twirp::Error.invalid_argument("testing"),
      error_class: SpokesAPI::InvalidArgument, message: "testing"
    check_error_mapping Twirp::Error.deadline_exceeded("testing"),
      error_class: SpokesAPI::TimedOut, message: "testing"
    check_error_mapping Twirp::Error.not_found("testing"),
      error_class: SpokesAPI::NotFound, message: "testing"
    check_error_mapping Twirp::Error.bad_route("testing"),
      error_class: SpokesAPI::TwirpClientError, message: "testing"
    check_error_mapping Twirp::Error.already_exists("testing"),
      error_class: SpokesAPI::TwirpClientError, message: "testing"
    check_error_mapping Twirp::Error.permission_denied("testing"),
      error_class: SpokesAPI::TwirpClientError, message: "testing"
    check_error_mapping Twirp::Error.unauthenticated("testing"),
      error_class: SpokesAPI::TwirpClientError, message: "testing"
    check_error_mapping Twirp::Error.resource_exhausted("testing"),
      error_class: SpokesAPI::ResourceExhausted, message: "testing"
    check_error_mapping Twirp::Error.failed_precondition("testing"),
      error_class: SpokesAPI::TwirpClientError, message: "testing"
    check_error_mapping Twirp::Error.aborted("testing"),
      error_class: SpokesAPI::TwirpClientError, message: "testing"
    check_error_mapping Twirp::Error.out_of_range("testing"),
      error_class: SpokesAPI::TwirpClientError, message: "testing"

    check_error_mapping Twirp::Error.internal("testing"),
      error_class: SpokesAPI::TwirpServerError, message: "testing"
    check_error_mapping Twirp::Error.unknown("testing"),
      error_class: SpokesAPI::TwirpServerError, message: "testing"
    check_error_mapping Twirp::Error.unimplemented("testing"),
      error_class: SpokesAPI::TwirpServerError, message: "testing"
    check_error_mapping Twirp::Error.unavailable("testing"),
      error_class: SpokesAPI::TwirpServerError, message: "testing"
    check_error_mapping Twirp::Error.data_loss("testing"),
      error_class: SpokesAPI::TwirpServerError, message: "testing"

    check_error_mapping Twirp::Error.new(:unknown_error_code, "testing"),
      error_class: SpokesAPI::TwirpError, message: "testing"

    check_error_mapping Twirp::Error.unknown("invalid connection"),
      error_class: SpokesAPI::TwirpConnectionError, message: "invalid connection"
  end

  def check_error_mapping(twirp_error, error_class:, message:)
    actual = SpokesAPI::Error.from_twirp_error(twirp_error)
    assert_instance_of error_class, actual
    assert_same twirp_error, actual.twirp_error
    assert_equal message, actual.message
  end
end
