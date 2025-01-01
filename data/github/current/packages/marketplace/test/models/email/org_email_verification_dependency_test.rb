# typed: true
# frozen_string_literal: true

require "test_helper"

class OrgEmailVerificationDependencyTest < GitHub::TestCase
  include GitHub::LoggerHelper

  teardown do
    # The default state for GitHub::Logger in tests is disabled (to avoid
    # STDOUT noise).  So we should disable after every test.
    GitHub::Logger.disable
  end

  fixtures do
    @org_admin = create(:user)
    @org = create(:organization, admin: @org_admin)
    @org.update(profile_email: "github@github.com")
    @org_profile_email = create(:organization_profile_email, organization: @org)
    @org_email_with_token = create(:organization_profile_email, :with_verification_token)
    @verified_email = create(:organization_profile_email, :verified)
  end

  context "Set Verification Token" do
    test "returns false when email is invalid" do
      @org.update(profile_email: "abc")
      org_profile_email = build(:organization_profile_email, organization: @org)
      refute org_profile_email.set_verification_token!
    end

    test "returns false when email is already verified" do
      refute @verified_email.set_verification_token!
    end

    test "sets verification token" do
      assert_nil @org_profile_email.verification_token
      @org_profile_email.set_verification_token!
      refute_nil @org_profile_email.verification_token
    end

    test "updates additional attributes when passed" do
      second_admin = create(:user)
      @org.add_admin(second_admin)
      assert_equal @org_profile_email.initiator, @org_admin
      assert_nil @org_profile_email.verification_token

      opts = { initiator: second_admin }
      @org_profile_email.set_verification_token!(opts: opts)
      refute_equal @org_profile_email.initiator, @org_admin
      refute_nil @org_profile_email.verification_token
      assert_equal @org_profile_email.initiator, second_admin
    end
  end

  context "Verify Email" do
    test "returns already verified error when email is already verified" do
      result = @verified_email.verify_email("xyz")
      refute result.success
      assert_equal result.error, :already_verified
      assert_equal "#{@verified_email.email} is already verified.", result.error_message
    end

    test "returns blank token error when input token is blank" do
      result = @org_email_with_token.verify_email(nil)
      refute result.success
      assert_equal result.error, :blank_token
      assert_equal "There was an error verifying your email due to blank token. Please try to resend a new verification email.", result.error_message
    end

    test "returns missing token error when verification token is not present" do
      result = @org_profile_email.verify_email("xyz")
      refute result.success
      assert_equal result.error, :missing_token
      assert_equal "There was an error verifying your email. Please try re-verifying it.", result.error_message
    end

    test "returns incorrect token error when verification token is wrong" do
      result = @org_email_with_token.verify_email("xyz")
      refute result.success
      assert_equal result.error, :incorrect_token
      assert_equal "There was an error verifying your email due to incorrect token. Please try from the latest verification email received.", result.error_message
    end

    test "returns true for successful verification" do
      result = @org_email_with_token.verify_email(@org_email_with_token.verification_token)
      assert result.success
    end

    test "updates additional attributes when available" do
      assert_nil @org_email_with_token.verifier
      refute @org_email_with_token.verified?

      opts = { state: :verified, verifier: @org_admin }
      result = @org_email_with_token.verify_email(@org_email_with_token.verification_token, opts: opts)
      assert result.success
      refute_nil @org_email_with_token.verifier
      assert @org_email_with_token.verified?
    end
  end

  context "Confirm Verification" do
    test "returns false for incorrect token" do
      refute @org_email_with_token.confirm_verification("xyz", {})
    end

    test "clears token and returns true for correct token" do
      assert @org_email_with_token.confirm_verification(@org_email_with_token.verification_token, {})
      assert_nil @org_email_with_token.verification_token
    end

    test "updates additional attributes when available" do
      assert_nil @org_email_with_token.verifier
      refute @org_email_with_token.verified?

      opts = { state: :verified, verifier: @org_admin }
      assert @org_email_with_token.confirm_verification(@org_email_with_token.verification_token, opts)
      refute_nil @org_email_with_token.verifier
      assert @org_email_with_token.verified?
    end

    test "instruments email verification confirmation" do
      org = @org_email_with_token.organization
      org_admin = org.admin
      opts = { state: :verified, verifier: org_admin }

      time = Time.zone.now.change(usec: 0)
      events = subscribe "organization_profile_email.confirm_verification"
      expected_payload = {
        state: "verified",
        note: org.profile_email,
        verified_at: time,
        organization_profile_email_id: @org_email_with_token.id,
        organization_profile_email: org.profile_email,
        org: org.login,
        org_id: org.id,
        actor: org_admin.login,
        actor_id: org_admin.id,
      }

      Timecop.freeze(time) do
        @org_email_with_token.confirm_verification(@org_email_with_token.verification_token, opts)
      end

      assert event = events.pop
      assert_equal expected_payload, event.payload
    end
  end

  context "Verify" do
    test "updates verified_at" do
      assert_nil @org_email_with_token.verified_at
      @org_email_with_token.verify!({})
      refute_nil @org_email_with_token.verified_at
    end

    test "updates additional attributes when available" do
      assert_nil @org_email_with_token.verifier
      refute @org_email_with_token.verified?

      opts = { state: :verified, verifier: @org_admin }
      assert @org_email_with_token.verify!(opts)
      refute_nil @org_email_with_token.verifier
      assert @org_email_with_token.verified?
    end
  end

  context "Verification Result" do
    test "returns success when status is successful" do
      result = @org_email_with_token.verification_result(true, nil)
      assert result.success
      assert_nil result.error
      assert_nil result.error_message
    end

    test "does not log success" do
      output = capture_logs do
        @org_email_with_token.verification_result(true, nil)
      end

      assert_empty output
    end

    test "returns error when status is not successful" do
      result = @verified_email.verification_result(false, :already_verified)
      refute result.success
      assert_equal :already_verified, result.error
      assert_equal "#{@verified_email.profile_email} is already verified.", result.error_message
    end

    test "does not log already verified error" do
      output = capture_logs do
        @verified_email.verification_result(false, :already_verified)
      end

      assert_empty output
    end

    test "logs errors other than already verified" do
      expected_log = {
        "Body" => "Email verification failed",
        "SeverityText" => "WARN",
        "exception.type" => "organization_profile_email_verification",
        "exception.message" => "incorrect_token",
        "gh.organization.profile_email_id" => @verified_email.id
      }
      assert_logged(**expected_log) do
        @verified_email.verification_result(false, :incorrect_token)
      end
    end
  end
end
