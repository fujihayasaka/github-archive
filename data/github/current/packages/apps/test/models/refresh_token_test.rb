# typed: true
# frozen_string_literal: true

require "test_helper"

class RefreshTokensTest < GitHub::TestCase
  fixtures do
    @integration = create :integration
    @access = create :github_app_access, application: @integration
    @access.redeem
    @refresh_token = @access.refresh_token
  end

  test "redeeming token resets hashed_token and refresh_token" do
    assert @access.application.user_token_expiration_enabled?
    hashed_token = @access.hashed_token
    refresh_token = @refresh_token.hashed_token

    @refresh_token.redeem(entry_point: :test_case)
    @access.reload

    refute_equal hashed_token, @access.hashed_token
    refute_equal refresh_token, @refresh_token.hashed_token
  end

  test "redeeming token resets expires_at" do
    access_expires_at = @access.expires_at
    expires_at = @refresh_token.expires_at

    Timecop.travel(1.month) do
      @refresh_token.redeem(entry_point: :test_case)
      @access.reload
    end

    refute_equal expires_at, @refresh_token.expires_at
    refute_equal access_expires_at, @access.expires_at
  end

  test "active doesn't return expired tokens" do
    Timecop.travel(@refresh_token.expires_at + 1.day) do
      assert_nil RefreshToken.active.find_by(id: @refresh_token.id)
    end
  end

  test "generates tokens that match RefreshToken::TOKEN_PATTERN_GR1" do
    token = @refresh_token.reset_token(entry_point: :test_case)

    assert_match RefreshToken::TOKEN_PATTERN_GR1, token
  end

  test "generates tokens with random characters" do
    token_value_1 = @refresh_token.reset_token(entry_point: :test_case)
    token_value_2 = @refresh_token.reset_token(entry_point: :test_case)

    assert_match /[a-zA-Z0-9]{76}\z/i, token_value_1
    assert_match /[a-zA-Z0-9]{76}\z/i, token_value_2
    refute_equal token_value_1, token_value_2
  end

  test "for_plaintext_token finds active tokens by their hashed value" do
    refute @refresh_token.expired?

    token = @refresh_token.reset_token(entry_point: :test_case)
    result = RefreshToken.for_plaintext_token(token, application: @integration)
    assert_equal @refresh_token, result.token
  end

  test "for_plaintext_token returns a hashed token for the plaintext token" do
    _access, refresh_token = @refresh_token.redeem(entry_point: :test_case)

    result = RefreshToken.for_plaintext_token(refresh_token, application: @integration)
    refute_nil result.token
  end

  test "for_plaintext_token returns nil for plaintext tokens that don't exist" do
    result = RefreshToken.for_plaintext_token("notavalidrefreshtoken", application: @integration)
    assert_nil result.token
    assert_equal :not_found, result.reason
  end

  test "for_plaintext_token returns nil for plaintext tokens that don't belong to the application" do
    integration = create :integration
    token = @refresh_token.reset_token(entry_point: :test_case)

    result = RefreshToken.for_plaintext_token(token, application: @integration)
    refute_nil result.token

    result = RefreshToken.for_plaintext_token(token, application: integration)
    assert_nil result.token
    assert_equal :mismatched_application, result.reason
  end

  test "for_plaintext_token returns nil when application is not passed" do
    result = RefreshToken.for_plaintext_token(@refresh_token.reset_token(entry_point: :test_case), application: nil)
    assert_nil result.token
    assert_equal :no_application, result.reason
  end

  test "for_plaintext_token returns nil with expired reason when refresh token is too old" do
    token = @refresh_token.reset_token(entry_point: :test_case)
    @refresh_token.update(expires_at: Time.now - 10)

    result = RefreshToken.for_plaintext_token(token, application: @integration)

    assert_nil result.token
    assert_equal :expired, result.reason
  end

  test "for_plaintext_token returns nil with invalid_checksum reason when used with invalid checksum" do
    token = @refresh_token.reset_token(entry_point: :test_case)
    @refresh_token.update(expires_at: Time.now - 10)
    token = "#{token[0..-7]}lolnah"

    result = RefreshToken.for_plaintext_token(token, application: @integration)

    assert_predicate result, :new_format?
    assert_nil result.token
    assert_equal :invalid_checksum, result.reason
  end

  test "for_plaintext_token returns token when used with valid checksum" do
    token = @refresh_token.reset_token(entry_point: :test_case)
    result = RefreshToken.for_plaintext_token(token, application: @integration)

    assert_predicate result, :new_format?
    refute_nil result.token
    assert_equal :success, result.reason
  end

  test "valid_checksum? with nil or empty token returns false" do
    refute RefreshToken.valid_checksum?(nil)
    refute RefreshToken.valid_checksum?("")
  end

  test "valid_checksum? will return false if the string is too short to have a checksum" do
    refute RefreshToken.valid_checksum?("123456")
  end

  test "valid_checksum? with valid checksum returns true" do
    token = @refresh_token.reset_token(entry_point: :test_case)
    assert RefreshToken.valid_checksum?(token)
  end

  test "DEFAULT_EXPIRY is 6 months" do
    assert_equal 6.months, RefreshToken::DEFAULT_EXPIRY,
      "The refresh token expiry should be 6 months, as agreed with AppSec. "\
      "See https://github.com/github/appsec-reviews/issues/447 for discussion"
  end
end
