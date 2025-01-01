# typed: true
# frozen_string_literal: true

require "test_helper"

class EmailUnlinkTest < GitHub::TestCase
  include AuthenticationHelpers

  fixtures do
    @user = create(:user)
    @user.add_email("#{SecureRandom.hex}@gmail.com").verify!
    @unverified_email = "hello@wor.ld"
    @user.add_email @unverified_email
  end

  setup do
    @email_bound_unlink = EmailUnlink.new(@user, email: @unverified_email)
    @account_bound_unlink = EmailUnlink.new(@user)
  end

  test "generated token is valid signed auth token" do
    now = Time.now.utc

    Timecop.freeze(now) do
      unlink = EmailUnlink.new(@user, email: @unverified_email)
      token = unlink.token
      refute_nil token

      verified = User.verify_signed_auth_token(token: token, scope: EmailUnlink::TOKEN_SCOPE)
      assert_equal @user, verified.user
      assert_equal @unverified_email, verified.data["email"]
      refute verified.data["success"]

      # SAT V3 expires gets truncated to seconds
      expected_expiry = now + EmailUnlink::EXPIRY
      assert_equal expected_expiry.to_i,  verified.expires.to_i
    end
  end

  context "build_from_token" do
    test "returns nil if token expired" do
      invalid = EmailUnlink.new(@user, email: @unverified_email, expires: 1.hour.ago)
      invalid_token = invalid.token

      assert_nil EmailUnlink.build_from_token(invalid_token)
    end

    [true, false].each do |success|
      test "returns EmailUnlink with correct values hydrated, success: #{success}" do
        unlink = EmailUnlink.new(@user, email: @unverified_email, success: success)
        token = unlink.token

        deserialized = EmailUnlink.build_from_token(token)

        assert_equal unlink.user, deserialized.user
        assert_equal unlink.email, deserialized.email
        assert_equal unlink.is_expired, deserialized.is_expired
        assert_equal unlink.successful?, success
        refute_equal unlink.failed?, success
      end
    end
  end

  test "user" do
    unlink = EmailUnlink.new(@user)
    assert_equal @user, unlink.user
  end


  test "email" do
    unlink = EmailUnlink.new(@user, email: @unverified_email)
    assert_equal @unverified_email, unlink.email
  end

  test "email is optional" do
    unlink = EmailUnlink.new(@user)
    refute_nil unlink.token
    assert_nil unlink.email
  end

  test "complete!" do
    unlink = EmailUnlink.new(@user)
    refute unlink.successful?
    unlink.complete!
    assert unlink.successful?
  end

  test "fail!" do
    unlink = EmailUnlink.new(@user)
    refute unlink.failed?
    unlink.fail!
    assert unlink.failed?
  end

  context "flash messages" do
    test "notice" do
      unlink = EmailUnlink.new(@user)
      refute unlink.flash_notice?
      refute unlink.flash_warn?
      refute unlink.flash_error?

      unlink.flash_notice = "you have been put on notice"
      assert unlink.flash_notice?
      assert_equal "you have been put on notice", unlink.flash_notice
    end

    test "warn" do
      unlink = EmailUnlink.new(@user)
      refute unlink.flash_notice?
      refute unlink.flash_warn?
      refute unlink.flash_error?

      unlink.flash_warn = "you have been warned"
      assert unlink.flash_warn?
      assert_equal "you have been warned", unlink.flash_warn
    end

    test "error" do
      unlink = EmailUnlink.new(@user)
      refute unlink.flash_notice?
      refute unlink.flash_warn?
      refute unlink.flash_error?

      unlink.flash_error = "how about no?"
      assert unlink.flash_error?
      assert_equal "how about no?", unlink.flash_error
    end

    test "persist through serialization" do
      unlink = EmailUnlink.new(@user, flash_messages: {
        notice: "notice message",
        warn: "warn message",
        error: "error message",
      })
      token = unlink.token
      rebuilt = EmailUnlink.build_from_token(token)

      assert_equal "notice message", rebuilt.flash_notice
      assert_equal "warn message", rebuilt.flash_warn
      assert_equal "error message", rebuilt.flash_error
    end
  end
end
