# typed: true
# frozen_string_literal: true

require "test_helper"

class UserEmailVerifyTest < GitHub::TestCase
  fixtures do
    @email             = create(:user_email)
    @verified_email    = create(:user_email, :verified)
    @launch_code_email = create(:user_email, :launch_code)
  end

  context ".call" do
    test "verifies a specified email" do
      result = UserEmail::Verify.call(
        email_id: @email.id,
        token: @email.verification_token,
        owner: @email.user,
      )

      assert_predicate result, :success?
      assert_equal @email, result.email
      assert_predicate result.email, :verified?
      assert_nil result.error
      assert_nil result.error_message
    end

    test "verifies a launch code email with launch code" do
      Users::Kv.store.set(@launch_code_email.kv_launch_code_key, "true", expires: 1.day.from_now)

      result = UserEmail::Verify.call(
        email_id: @launch_code_email.id,
        token: @launch_code_email.verification_token,
        owner: @launch_code_email.user,
      )

      assert_predicate result, :success?
      assert_equal @launch_code_email, result.email
      assert_predicate result.email, :verified?
      assert_nil result.error
      assert_nil result.error_message
    end

    test "returns :not_found error if email does not exist" do
      params = {
        email_id: @email.id,
        token: @email.verification_token,
        owner: @email.user,
      }
      @email.destroy!

      result = UserEmail::Verify.call(params)

      refute_predicate result, :success?
      assert_nil result.email
      assert_equal :not_found, result.error
      assert_equal "Sorry, we couldn’t find an email to verify.", result.error_message
    end

    test "returns :not_found error if email_id is nil" do
      result = UserEmail::Verify.call(
        email_id: nil,
        token: @email.verification_token,
        owner: @email.user,
      )

      refute_predicate result, :success?
      assert_nil result.email
      assert_equal :not_found, result.error
      assert_equal "Sorry, we couldn’t find an email to verify.", result.error_message
    end

    test "returns :not_found error if owner is nil" do
      result = UserEmail::Verify.call(
        email_id: @email.id,
        token: @email.verification_token,
        owner: nil,
      )

      refute_predicate result, :success?
      assert_nil result.email
      assert_equal :not_found, result.error
      assert_equal "Sorry, we couldn’t find an email to verify.", result.error_message
    end

    test "returns :not_found error if owner does not own email record" do
      result = UserEmail::Verify.call(
        email_id: @email.id,
        token: @email.verification_token,
        owner: create(:user),
      )

      refute_predicate result, :success?
      assert_nil result.email
      assert_equal :not_found, result.error
      assert_equal "Sorry, we couldn’t find an email to verify.", result.error_message
    end

    test "returns :enterprise_managed error if user is EMU", skip_enterprise: true do
      emu = create(:emu)
      email = emu.primary_user_email

      result = UserEmail::Verify.call(
        email_id: email.id,
        token: "deadbeef",
        owner: emu,
      )

      refute_predicate result, :success?
      assert_equal email, result.email
      assert_equal :enterprise_managed, result.error
      assert_equal UserEmail::ENTERPRISE_MANAGED_USER_ERROR, result.error_message
    end

    test "returns :already_verified error if email is already verified" do
      result = UserEmail::Verify.call(
        email_id: @verified_email.id,
        token: "deadbeef",
        owner: @verified_email.user,
      )

      refute_predicate result, :success?
      assert_equal @verified_email, result.email
      assert_equal :already_verified, result.error
      assert_equal "#{@verified_email.email} is already verified.", result.error_message
    end

    test "returns :missing_token error if email is unverified but missing verification_token value" do
      @email.update!(verification_token: nil)

      result = UserEmail::Verify.call(
        email_id: @email.id,
        token: "deadbeef",
        owner: @email.user,
      )

      refute_predicate result, :success?
      assert_equal @email, result.email
      assert_equal :missing_token, result.error
      assert_equal "There was an error verifying your email. Please try re-verifying it.", result.error_message
    end

    test "returns :verification_failed error if token arg is empty for regular verification token" do
      result = UserEmail::Verify.call(
        email_id: @email.id,
        token: "",
        owner: @email.user,
      )

      refute_predicate result, :success?
      assert_equal @email, result.email
      assert_equal :verification_failed, result.error
      assert_equal "There was an error verifying your email.", result.error_message
    end

    test "returns :verification_failed error if token arg is nil" do
      result = UserEmail::Verify.call(
        email_id: @email.id,
        token: nil,
        owner: @email.user,
      )

      refute_predicate result, :success?
      assert_equal @email, result.email
      assert_equal :verification_failed, result.error
      assert_equal "There was an error verifying your email.", result.error_message
    end

    test "returns :verification_failed error if token arg is empty for launch code token" do
      result = UserEmail::Verify.call(
        email_id: @launch_code_email.id,
        token: "",
        owner: @launch_code_email.user,
      )

      refute_predicate result, :success?
      assert_equal @launch_code_email, result.email
      assert_equal :verification_failed, result.error
      assert_equal "Invalid launch code.", result.error_message
    end

    test "returns :launch_code_expired if launch code is expired and creates new launch code" do
      Users::Kv.store.set(@launch_code_email.kv_launch_code_key, "true", expires: Time.now)
      prev_launch_code = @launch_code_email.verification_token

      result = UserEmail::Verify.call(
        email_id: @launch_code_email.id,
        token: @launch_code_email.verification_token,
        owner: @launch_code_email.user,
      )

      refute_predicate result, :success?
      refute_equal prev_launch_code, result.email.verification_token
      assert_equal @launch_code_email, result.email
      assert_equal :launch_code_expired, result.error
      assert_equal "This launch code has expired. We've sent a new code to #{@launch_code_email}.", result.error_message
    end

    test "returns :launch_code_expired if launch code is expired and doesn't exist in database" do
      result = UserEmail::Verify.call(
        email_id: @launch_code_email.id,
        token: @launch_code_email.verification_token,
        owner: @launch_code_email.user,
      )

      refute_predicate result, :success?
      assert_equal @launch_code_email, result.email
      assert_equal :launch_code_expired, result.error
      assert_equal "This launch code has expired. We've sent a new code to #{@launch_code_email}.", result.error_message
    end

    test "returns :rate_limited error if user has too many recent verification attempts" do
      AuthenticationLimit.expects(:at_any?).with(email_verification_login: @email.user.login, increment: true).returns(true)

      result = UserEmail::Verify.call(
        email_id: @email.id,
        token: @email.verification_token,
        owner: @email.user,
      )

      refute_predicate result, :success?
      assert_equal :rate_limited, result.error
      assert_equal "Too many attempts. Try again later.", result.error_message
    end
  end
end

class EmuUserEmailVerifyTest < GitHub::TestCase
  fixtures do
    @emudoe = create :emu, login: "emudoe", email: "emudoe@example.com"

    @email = @emudoe.primary_user_email

    @emu_business_without_owner = create(:business, :enterprise_managed, :without_enterprise_managed_user_owner)

    @user = create(:user)
    @emu_business_without_owner.create_and_add_first_emu_owner(email: "firstowner@microsoft.com", actor: @user)

    @admin_user = User.find_by_login(@emu_business_without_owner.shortcode + "_admin")
    @admin_email = @admin_user.primary_user_email

    @admin_email.update! state: "unverified", verified_at: nil
    @admin_email.request_verification(requested_by: @admin_user)
  end

  test "does not allow verification of an email for an emu user" do
    result = UserEmail::Verify.call(
      email_id: @email.id,
      token: @email.verification_token,
      owner: @email.user,
    )

    refute_predicate result, :success?
    refute_nil result.error
    assert_equal UserEmail::ENTERPRISE_MANAGED_USER_ERROR, result.error_message
  end

  test "verifies a specified email for emu first owner" do
    refute_predicate @admin_email, :verified?

    result = UserEmail::Verify.call(
      email_id: @admin_email.id,
      token: @admin_email.verification_token,
      owner: @admin_email.user,
    )

    assert_predicate result, :success?
    assert_nil result.error
  end
end unless GitHub.single_business_environment?
