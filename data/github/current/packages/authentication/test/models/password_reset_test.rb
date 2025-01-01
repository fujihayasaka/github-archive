# typed: true
# frozen_string_literal: true

require "test_helper"

class PasswordResetTest < GitHub::TestCase
  # EMUs do not have passwords which they can reset (except first admins)
  skip_with_all_emus

  include HydroTestHelpers
  include AuthenticationHelpers

  self.these_tests_are_order_dependent_and_yearn_to_be_random

  fixtures do
    @user = create(:user)
    @user.add_email("#{SecureRandom.hex}@gmail.com").verify!
    @unverified_email = "hello@wor.ld"
    @user.add_email @unverified_email
    @secondary_email = "#{SecureRandom.hex}@gmail.com"
    @user.add_email(@secondary_email).verify!

    @tfa_user = create(:user)
    make_two_factor_credential(@tfa_user)
    @tfa_user.add_email("#{SecureRandom.hex}@gmail.com").verify!

    if GitHub.two_factor_sms_enabled?
      @sms_tfa_user = create(:user)
      make_sms_two_factor_credential(@sms_tfa_user)
      @sms_tfa_user.add_email("#{SecureRandom.hex}@gmail.com").verify!
    end

    @unverified_user = create(:user)
    @unverified_user.add_email("#{SecureRandom.hex}@gmail.com")

    @employee = create(:staff_admin_user)
    @spammy = create(:user_with_compromised_password)
    @spammy.mark_as_spammy

    create(:compromised_password, plain: COMPROMISED_USER_PASSWORD)
    create(:compromised_password, plain: COMPROMISED_USER_PASSWORD_K_ANON)
  end

  setup do
    ActionMailer::Base.deliveries.clear

    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    # Non AR "models" don't get reset between tests.
    @reset = PasswordReset.new user: @user, email: @user.email
    @tfa_reset = PasswordReset.new user: @tfa_user, email: @tfa_user.email
    @sms_tfa_reset = PasswordReset.new user: @sms_tfa_user, email: @sms_tfa_user.email if GitHub.two_factor_sms_enabled?
    @unverified_user_reset = PasswordReset.new user: @unverified_user, email: @unverified_user.email
  end

  test "creating PasswordReset sends an email" do
    CriticalAccountLoginMailer.expects(:new_password).returns(stub(deliver_later: nil))
    PasswordReset.create user: @user, email: @user.email
  end

  test "sends email with reset link in it" do
    perform_enqueued_jobs(only: [AccountLogin::CriticalMailersDeliveryJob]) do
      reset = PasswordReset.create user: @user, email: @user.email
      mail = ActionMailer::Base.deliveries.pop
      assert_includes mail.text_part.body.to_s, reset.link
      assert_includes mail.html_part.body.to_s, reset.link
    end
  end

  test "User is inferred from email address" do
    reset = PasswordReset.create user: nil, email: @user.email
    assert reset.valid?
    assert_equal @user, reset.user
    assert_equal @user.email, reset.email
  end

  test "Email can be inferred from user" do
    reset = PasswordReset.create user: @user, email: nil
    assert reset.valid?
    assert_equal @user, reset.user
    assert_equal @user.email, reset.email
  end

  test "User and email can be specified" do
    reset = PasswordReset.create user: @user, email: @user.email
    assert reset.valid?
    assert_equal @user, reset.user
    assert_equal @user.email, reset.email
  end

  test "has a reset link" do
    reset = PasswordReset.new user: @user, email: @user.email
    assert_equal "#{GitHub.url}/password_reset/#{reset.token}?auto=true", reset.link
  end

  test "PasswordReset is invalid if email doesn't belong to user" do
    reset = PasswordReset.create user: @user, email: "nope@nope.nope"
    refute reset.valid?
  end

  if GitHub.single_business_environment?
    test "PasswordReset is invalid and correct error message is displayed if email doesn't belong to any user for GHES" do
      reset = PasswordReset.create email: "nope@nope.nope"
      refute reset.valid?
      assert_equal reset.error_message, PasswordReset::GHES_INVALID_EMAIL_MESSAGE
    end
  else
    test "PasswordReset is invalid and correct error message is displayed if email doesn't belong to anyone for dotcom" do
      reset = PasswordReset.create email: "nope@nope.nope"
      refute reset.valid?
      assert_equal reset.error_message, PasswordReset::INVALID_EMAIL_OR_ACCOUNT_TYPE_MESSAGE
    end
  end

  if GitHub.single_business_environment?
    test "PasswordReset is invalid if email doesn't exist, but is associated with a deobfuscated normal email for GHES" do
      original = @user.emails.first.email
      reset = PasswordReset.create email: original.sub("@", "+1@")
      refute reset.valid?
      assert_equal reset.error_message, PasswordReset::GHES_INVALID_EMAIL_MESSAGE
    end
  else
    test "PasswordReset is invalid if email doesn't exist, but is associated with a deobfuscated normal email for dotcom" do
      # we don't show the EMU error message here since there's no EMU email match
      original = @user.emails.first.email
      reset = PasswordReset.create email: original.sub("@", "+1@")
      refute reset.valid?
      assert_equal reset.error_message, PasswordReset::INVALID_EMAIL_OR_ACCOUNT_TYPE_MESSAGE
    end
  end

  test "PasswordReset is invalid if user is suspended" do
    @user.suspend "Reasons"
    reset = PasswordReset.create user: @user, email: @user.email
    assert_equal @user, reset.user
    assert_equal @user.email, reset.email
    refute reset.valid?
  end

  test "PasswordReset is invalid if a non-human user is used" do
    bot = create(:integration).bot
    reset = PasswordReset.create user: bot
    refute reset.valid?
  end

  test "PasswordReset is valid if non-verified address is used and force is authorized" do
    reset = PasswordReset.create email: @unverified_email, force: true
    assert reset.valid?
    assert_equal @user, reset.user
    assert_equal @unverified_email, reset.email
  end

  test "a PasswordReset can be forced if user has a primary email, even if no email provided" do
    reset = PasswordReset.create user: @user, force: true
    assert reset.valid?
    assert_equal @user.email, reset.email
  end

  test "Can load a PasswordReset from a token" do
    assert reset = PasswordReset.find_by_token(@reset.token)
    assert reset.valid?
    assert_equal @user, reset.user
    assert_equal @user.email, reset.email
  end

  test "Can load a PasswordReset from an upcased token" do
    assert reset = PasswordReset.find_by_token(@reset.token.upcase)
    assert reset.valid?
    assert_equal @user, reset.user
    assert_equal @user.email, reset.email
  end

  test "Can load a PasswordReset from a downcased token" do
    assert reset = PasswordReset.find_by_token(@reset.token.downcase)
    assert reset.valid?
    assert_equal @user, reset.user
    assert_equal @user.email, reset.email
  end

  test "Preserves expiration through parsing" do
    original = PasswordReset.new(user: @user, email: @user.email)
    parsed = PasswordReset.find_by_token(original.token)

    assert_equal original.instance_variable_get("@expires").to_i,
      parsed.instance_variable_get("@expires").to_i
  end

  test "Not valid if the user deletes their email address" do
    email = "#{SecureRandom.hex}@gmail.com"
    @user.add_email(email).verify!
    reset = PasswordReset.create email: email
    assert reset.valid?
    token = reset.token
    UserEmail.find_by(email: email)&.destroy
    reset = PasswordReset.create email: email
    refute reset.valid?
    assert reset = PasswordReset.find_by_token(token)
    refute reset.valid?
  end

  test "Expired tokens are invalid" do
    token = @user.signed_auth_token(
      scope: PasswordReset::TOKEN_SCOPE,
      expires: 25.hours.ago,
      data: { "email" => @user.email },
    )
    assert_nil PasswordReset.find_by_token token
  end

  test "Can't send to secondary verified address if backup email is configured" do
    email = "#{SecureRandom.hex}@gmail.com"
    backup_email = @user.add_email(email)
    backup_email.verify!
    @user.set_backup_email(backup_email)
    assert @user.has_backup_email?
    refute_equal @user.backup_email, @secondary_email
    reset = PasswordReset.new email: @secondary_email

    refute reset.valid?
  end

  test "Can send to secondary verified address if configured as backup email" do
    secondary_email = @user.emails.find_by_email(@secondary_email)
    @user.set_backup_email(secondary_email)
    assert_equal @user.backup_email, @secondary_email
    reset = PasswordReset.new email: @secondary_email

    assert reset.valid?
  end

  test "Can't send to secondary verified address if user only wants passwords resets sent to primary" do
    @user.allow_password_reset_with_primary_email_only
    assert @user.password_reset_with_primary_email_only?
    reset = PasswordReset.new email: @secondary_email

    refute reset.valid?
  end

  test "Can send to primary if user only wants passwords resets sent to primary" do
    @user.allow_password_reset_with_primary_email_only
    assert @user.password_reset_with_primary_email_only?
    reset = PasswordReset.new email: @user.email

    assert reset.valid?
  end

  test "Will not deliver to unicode squatted names" do
    user = create(:user)
    email = "iii@example.com"
    user.add_email(email).verify!
    reset = PasswordReset.new email: "ııı@example.com"
    refute reset.valid?
  end

  test "Will not deliver to unicode squatted names without verified emails" do
    user = create(:user)
    email = "iii@example.com"
    user.add_email(email)
    reset = PasswordReset.new email: "ııı@example.com"
    refute reset.valid?
  end

  test "is valid even if email is entered with different case in local part" do
    user = create(:user)
    email = "iii@example.com"
    user.add_email(email).verify!
    reset = PasswordReset.new email: "III@example.com"
    assert reset.valid?
  end

  test "will send to email matching casing stored for user when different case is requested" do
    user = create(:user)
    email = "iii@example.com"
    user.add_email(email).verify!
    reset = PasswordReset.new email: "III@example.com"
    assert_equal "iii@example.com", reset.email
  end

  unless GitHub.enterprise?
    test "GitHub employee must use @github.com email for password reset" do
      employee = preview_user
      personal_email = create(:user_email, user: employee, email: "foo@example.com")
      github_email = create(:user_email, user: employee, email: "foo@github.com")

      assert_predicate employee, :employee?

      reset = PasswordReset.create email: personal_email.email
      refute_predicate reset, :valid?, reset.error_message

      reset = PasswordReset.create email: github_email.email
      assert_predicate reset, :valid?, reset.error_message
    end
  end

  context "for a user with no verified emails" do
    test "can send to unverified address" do
      assert @unverified_user_reset.valid?
    end

    test "unsuccessful update does not verify email" do
      new_pw = SecureRandom.hex
      @unverified_user_reset.apply(
        password: new_pw,
        password_confirmation: "#{new_pw} OOPS",
      )

      email = @unverified_user.primary_user_email.reload
      refute email.verified?
    end
  end

  context "#apply" do
    test "invalidates previous tokens" do
      old_token = @reset.token
      new_reset = PasswordReset.new user: @user, email: @user.email
      new_pw = SecureRandom.hex
      new_reset.apply(
        password: new_pw,
        password_confirmation: new_pw,
      )
      assert_nil PasswordReset.find_by_token old_token
    end

    test "changes password" do
      new_pw = SecureRandom.hex
      assert_password_change(@user) do
        assert @reset.apply(
          password: new_pw,
          password_confirmation: new_pw,
        )
      end
    end

    test "revokes active sessions" do
      create_list(:user_session, 3, user: @user)
      refute_empty @user.reload.sessions
      new_pw = SecureRandom.hex
      assert_password_change(@user) do
        assert @reset.apply(
          password: new_pw,
          password_confirmation: new_pw,
        )
      end
      assert_empty @user.reload.sessions.unrevoked
    end

    test "does not revoke oauth accesses" do
      Timecop.freeze(5.minutes.ago) do
        create(:oauth_access, user: @user)
      end

      assert_predicate @user.reload.oauth_accesses, :any?
      new_pw = SecureRandom.hex
      perform_enqueued_jobs(only: [RevokeOauthAccessesJob]) do
        assert_no_difference("@user.reload.oauth_accesses.count") do
          assert_password_change(@user) do
            assert @reset.apply(
              password: new_pw,
              password_confirmation: new_pw,
          )
          end
        end
      end
    end

    test "reset with weak password, disallow reset if feature enabled", skip_enterprise: !GitHub.weak_password_checking_enabled? do
      refute_password_change(@user) do
        refute @reset.apply(
          password: COMPROMISED_USER_PASSWORD,
          password_confirmation: COMPROMISED_USER_PASSWORD,
        )
      end
      assert_includes @user.errors[:password], User::PasswordDependency::WEAK_PASSWORD_MESSAGE
    end

    test "reset with non-weak password, allow reset even if feature enabled", skip_enterprise: !GitHub.weak_password_checking_enabled? do
      assert_password_change(@user) do
        assert @reset.apply(
          password: "securepassword123",
          password_confirmation: "securepassword123",
        )
      end
      refute_predicate @user.errors[:password], :any?
    end

    test "if user password was weak and they had a successful reset, they check result will be updated to 0", skip_enterprise: !GitHub.weak_password_checking_enabled? do

      now = Time.now.beginning_of_day
      Timecop.freeze(now) do
        check_result = PasswordCheckMetadata.new(discovery_timestamp: 25.days.ago.to_i).to_binary_s
        @user.update_attribute(:weak_password_check_result, check_result)
        # perform a successful reset
        assert_password_change(@user) do
          @reset.apply(
            password: "securepassword123",
            password_confirmation: "securepassword123",
          )
        end

        assert_equal 0, @user.password_check_metadata.discovery_timestamp
      end
    end

    test "if user had a compromised username and password resetting sets exact match to 0", skip_enterprise: true do

      now = Time.now.beginning_of_day
      Timecop.freeze(now) do
        check_result = PasswordCheckMetadata.new(
          discovery_timestamp: 25.days.ago.to_i,
          compromised_password_id: 10,
          exact_email_and_password_match: 1,
        ).to_binary_s
        @user.update_attribute(:weak_password_check_result, check_result)
        # perform a successful reset
        assert_password_change(@user) do
          @reset.apply(
            password: "securepassword123",
            password_confirmation: "securepassword123",
          )
        end

        metadata = @user.password_check_metadata

        assert_equal 0, metadata.discovery_timestamp
        assert_equal 0, metadata.exact_email_and_password_match
        assert_equal 0, metadata.compromised_password_id
      end
    end

    test "if user had a compromised username and password found via secret scanning resetting sets exact match to 0", skip_enterprise: true do
      now = Time.now.beginning_of_day
      Timecop.freeze(now) do
        @user.mark_compromised_via_secret_scanning

        assert_equal 1, @user.password_check_metadata.exact_email_and_password_match

        assert_password_change(@user) do
          @reset.apply(
            password: "securepassword123",
            password_confirmation: "securepassword123",
          )
        end

        metadata = @user.password_check_metadata

        assert_equal 0, metadata.discovery_timestamp
        assert_equal 0, metadata.exact_email_and_password_match
        assert_equal 0, metadata.compromised_password_id
      end
    end

    test "notifies users" do
      AccountMailer.expects(:password_changed).with(@user, "reset").returns(stub(deliver_later: nil))
      new_pw = SecureRandom.hex
      assert @reset.apply(
        password: new_pw,
        password_confirmation: new_pw,
      )
    end

    test "adds an audit log entry" do
      events = subscribe("user.reset_password")
      new_pw = SecureRandom.hex
      assert @reset.apply(
        password: new_pw,
        password_confirmation: new_pw,
      )
      assert event = events.pop, "expected a user.reset_password event"
      assert_equal "user.reset_password", event.name
      assert_equal false, event.payload[:two_factor_required]
      assert_nil event.payload[:two_factor_method]
    end

    test "audit logging for app totp 2FA" do
      events = subscribe("user.reset_password")
      otp = @tfa_user.two_factor_app_totp.now
      @tfa_reset.verify_two_factor(otp, totp_type: :app)

      new_pw = SecureRandom.hex
      assert @tfa_reset.apply(
        password: new_pw,
        password_confirmation: new_pw,
      )

      assert event = events.pop, "expected a user.reset_password event"
      assert_equal "user.reset_password", event.name
      assert_equal true, event.payload[:two_factor_required]
      assert_equal :app, event.payload[:two_factor_method]
    end

    test "audit logging for sms totp 2FA", skip_enterprise: true do
      events = subscribe("user.reset_password")
      otp = @sms_tfa_user.two_factor_sms_totp.now
      @sms_tfa_reset.verify_two_factor(otp, totp_type: :sms)

      new_pw = SecureRandom.hex
      assert @sms_tfa_reset.apply(
        password: new_pw,
        password_confirmation: new_pw,
      )

      assert event = events.pop, "expected a user.reset_password event"
      assert_equal "user.reset_password", event.name
      assert_equal true, event.payload[:two_factor_required]
      assert_equal :sms, event.payload[:two_factor_method]
    end

    test "audit logging for mobile 2FA" do
      events = subscribe("user.reset_password")
      @tfa_reset.verify_github_mobile_2fa

      new_pw = SecureRandom.hex
      assert @tfa_reset.apply(
        password: new_pw,
        password_confirmation: new_pw,
      )

      assert event = events.pop, "expected a user.reset_password event"
      assert_equal "user.reset_password", event.name
      assert_equal true, event.payload[:two_factor_required]
      assert_equal :mobile, event.payload[:two_factor_method]
    end

    test "audit logging for webauthn 2FA" do
      challenge = WebAuthn::Credential.options_for_get.challenge
      security_key = create(:security_key, user: @tfa_user)
      webauthn_response = security_key.fake_authenticator.get(challenge)

      events = subscribe("user.reset_password")
      @tfa_reset.verify_u2f(GitHub.url, challenge, webauthn_response.to_json)

      new_pw = SecureRandom.hex
      assert @tfa_reset.apply(
        password: new_pw,
        password_confirmation: new_pw,
      )

      assert event = events.pop, "expected a user.reset_password event"
      assert_equal "user.reset_password", event.name
      assert_equal true, event.payload[:two_factor_required]
      assert_equal :webauthn, event.payload[:two_factor_method]
    end

    test "publishes PasswordUpdate hydro message" do
      GitHub.stubs(:hydro_enabled?).returns(true)
      now = Time.now.beginning_of_day

      Timecop.freeze(now) do
        GitHub.context.push(actor_ip: "1.2.3.4")
        GitHub.context.push(user_agent: "test agent")

        new_pw = SecureRandom.hex
        @reset.apply(password: new_pw, password_confirmation: new_pw)

        assert_hydro_published(
          {
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            actor: Hydro::EntitySerializer.user(@reset.user),
            account: Hydro::EntitySerializer.user(@reset.user),
            update_type: :USER_RESET,
            spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(GitHub.context[:spamuri_form_signals]),
          },
          schema: "github.v1.PasswordUpdate",
        )
      end
    end

    test "fails to change password if confirmation doesn't match" do
      new_pw = SecureRandom.hex
      refute_password_change(@user) do
        refute @reset.apply(
          password: new_pw,
          password_confirmation: "#{new_pw}1",
        )
      end
    end

    test "fails if 2fa verification is required" do
      new_pw = SecureRandom.hex
      refute_password_change(@tfa_user) do
        refute @tfa_reset.apply(
          password: new_pw,
          password_confirmation: new_pw,
        )
      end
    end

    test "succeeds if 2fa is verified" do
      Timecop.freeze do
        otp = @tfa_user.two_factor_app_totp.now
        @tfa_reset.verify_two_factor(otp, totp_type: :app)

        new_pw = SecureRandom.hex
        assert_password_change(@tfa_user) do
          assert @tfa_reset.apply(
            password: new_pw,
            password_confirmation: new_pw,
          )
        end
      end
    end
  end

  context "find_by_token" do
    test "can load from a token" do
      assert reset = PasswordReset.find_by_token(@reset.token)
      assert reset.valid?
      assert_equal @user, reset.user
      assert_equal @user.email, reset.email
    end

    test "preserves expiration through parsing" do
      original = PasswordReset.new(user: @user, email: @user.email)
      parsed = PasswordReset.find_by_token(original.token)

      assert_equal original.instance_variable_get("@expires").to_i,
        parsed.instance_variable_get("@expires").to_i
    end

    test "preserves two_factor_verified through parsing" do
      Timecop.freeze do
        parsed = PasswordReset.find_by_token(@tfa_reset.token)
        assert_predicate parsed, :verify_two_factor?

        otp = @tfa_user.two_factor_app_totp.now
        @tfa_reset.verify_two_factor(otp, totp_type: :app)

        parsed = PasswordReset.find_by_token(@tfa_reset.token)
        refute_predicate parsed, :verify_two_factor?
      end
    end
  end

  context "#verify_two_factor?" do
    test "it is false for non-2fa users" do
      refute_predicate @reset, :verify_two_factor?
    end

    test "it is true for 2fa users" do
      assert_predicate @tfa_reset, :verify_two_factor?
    end

    test "it is false once a valid otp has been verified" do
      Timecop.freeze do
        otp = @tfa_user.two_factor_app_totp.now
        @tfa_reset.verify_two_factor(otp, totp_type: :app)
        refute_predicate @tfa_reset, :verify_two_factor?
      end
    end

    test "is true once an invalid otp has been verified" do
      @tfa_reset.verify_two_factor("xyz", totp_type: :app)
      assert_predicate @tfa_reset, :verify_two_factor?
    end
  end

  context "#verify_two_factor for app" do
    test "it returns true for valid otp" do
      Timecop.freeze do
        otp = @tfa_user.two_factor_app_totp.now
        assert @tfa_reset.verify_two_factor(otp, totp_type: :app), "expected otp to be valid"
      end
    end

    test "it returns true for valid recovery code" do
      code = GitHub::TwoFactorAuthentication.recovery_codes(@tfa_user.two_factor_credential.encrypted_recovery_secret, @tfa_user.two_factor_credential.recovery_salt_version).first
      assert @tfa_reset.verify_two_factor(code, totp_type: :app), "expected code to be valid"
    end

    test "it returns false for invalid recovery code" do
      code = "aaaaabbbbb"
      refute @tfa_reset.verify_two_factor(code, totp_type: :app), "expected code to be valid"
    end

    test "it returns false for invalid otp" do
      Timecop.freeze do
        refute @tfa_reset.verify_two_factor(invalid_app_otp(@tfa_user), totp_type: :app)
      end
    end

    test "it returns false for malformed otp" do
      refute @tfa_reset.verify_two_factor("asdfgh", totp_type: :app)
    end

    test "it returns false for empty otp" do
      refute @tfa_reset.verify_two_factor("", totp_type: :app)
    end

    test "it returns false for unknown totp_type" do
      refute @tfa_reset.verify_two_factor("", totp_type: nil)
    end
  end

  context "#verify_two_factor for sms", skip_enterprise: true do
    test "it returns true for valid otp" do
      Timecop.freeze do
        otp = @sms_tfa_user.two_factor_sms_totp.now
        assert @sms_tfa_reset.verify_two_factor(otp, totp_type: :sms), "expected otp to be valid"
      end
    end

    test "it returns true for valid recovery code" do
      code = GitHub::TwoFactorAuthentication.recovery_codes(@sms_tfa_user.two_factor_credential.encrypted_recovery_secret, @sms_tfa_user.two_factor_credential.recovery_salt_version).first
      assert @sms_tfa_reset.verify_two_factor(code, totp_type: :sms), "expected code to be valid"
    end

    test "it returns false for invalid recovery code" do
      code = "aaaaabbbbb"
      refute @sms_tfa_reset.verify_two_factor(code, totp_type: :sms), "expected code to be valid"
    end

    test "it returns false for invalid otp" do
      Timecop.freeze do
        refute @sms_tfa_reset.verify_two_factor(invalid_sms_otp(@sms_tfa_user), totp_type: :sms)
      end
    end

    test "it returns false for malformed otp" do
      refute @sms_tfa_reset.verify_two_factor("asdfgh", totp_type: :sms)
    end

    test "it returns false for empty otp" do
      refute @sms_tfa_reset.verify_two_factor("", totp_type: :sms)
    end

    test "it returns false for unknown totp_type" do
      refute @sms_tfa_reset.verify_two_factor("", totp_type: nil)
    end
  end

  context "#forced_weak_password_reset?" do
    test "it is false by default" do
      refute_predicate @reset, :forced_weak_password_reset?
    end

    test "is true when specified" do
      reset = PasswordReset.new(user: @user, email: @user.email, forced_weak_password_reset: true)
      assert_predicate reset, :valid?
      assert_predicate reset, :forced_weak_password_reset?

      parsed_reset = PasswordReset.find_by_token(reset.token)
      assert_predicate parsed_reset, :forced_weak_password_reset?
    end
  end
end


class EmuPasswordResetTest < GitHub::TestCase
  include HydroTestHelpers
  include AuthenticationHelpers

  fixtures do
    @emu = create(:emu)
    @first_admin = @emu.enterprise_managed_business.find_first_emu_owner
  end

  setup do
    disable_feature_flag(:emu_password_reset_incomplete_email)
  end

  context "first emu owner" do
    test "password is changed" do
      new_reset = PasswordReset.new user: @first_admin, email: @first_admin.profile_email, force: true
      assert_predicate new_reset, :valid?

      new_pw = SecureRandom.hex
      assert_password_change(@first_admin) do
        new_reset.apply(
          password: new_pw,
          password_confirmation: new_pw,
        )
      end
    end

    test "new_reset_link" do
      new_reset = PasswordReset.new user: @first_admin, email: @first_admin.profile_email, force: true
      assert_predicate new_reset, :valid?

      disable_feature_flag(:resend_initial_first_emu_admin_password_reset)
      assert_equal new_reset.new_reset_link, "https://github.com/password_reset"
      enable_feature_flag(:resend_initial_first_emu_admin_password_reset)
      assert_equal new_reset.new_reset_link, "https://github.com/password_reset?email=#{@first_admin.remove_shortcode(@first_admin.profile_email)}&slug=#{@first_admin.enterprise_managed_business.slug}"
    end
  end

  context "emu user" do
    test "PasswordReset is invalid" do
      reset = PasswordReset.create user: @emu, email: @emu.email
      refute reset.valid?
      assert_equal reset.error_message, PasswordReset::INVALID_EMAIL_EMU_USER_MESSAGE
    end

    test "PasswordReset is invalid if associated with a deobfuscated EMU email" do
      reset = PasswordReset.create email: UserEmail.deobfuscate(@emu.email)
      refute reset.valid?
      assert_equal reset.error_message, PasswordReset::INVALID_EMAIL_OR_ACCOUNT_TYPE_MESSAGE

      enable_feature_flag(:emu_password_reset_incomplete_email)
      reset = PasswordReset.create email: UserEmail.deobfuscate(@emu.email)
      refute reset.valid?
      assert_equal reset.error_message, PasswordReset::INVALID_EMAIL_EMU_USER_MESSAGE
    end
  end

end unless GitHub.single_business_environment?

# Password reset is not very applicable to multi-tenant
# But it does apply to the first emu owner
class PasswordResetMultiTenantTest < GitHub::TestCase
  fixtures do
    on_multi_tenant_enterprise do
      @emu = create :emu, :owner
      @tenant = @emu.enterprise_managed_business
      @emu2 = create :emu, :owner
      @pretend_stafftools_tenant = @emu2.enterprise_managed_business
    end
  end

  context "#link and new_reset_link" do
    test "should be a link for the current tenant" do
      on_multi_tenant_enterprise(tenant: @tenant) do
        reset = PasswordReset.new user: @emu, email: @emu.email

        link_subdomain = T.must(URI.parse(reset.link).host).split(".").first
        assert_equal link_subdomain, @tenant.slug

        new_pw_reset_link_subdomain = T.must(URI.parse(reset.new_reset_link).host).split(".").first
        assert_equal new_pw_reset_link_subdomain, @tenant.slug
      end
    end

    test "should be a link to the _correct_ tenant if current tenant is stafftools" do
      GitHub::CurrentTenant.stubs(:stafftools_tenant?).returns(true)
      on_multi_tenant_enterprise(tenant: @pretend_stafftools_tenant) do
        reset = PasswordReset.new user: @emu, email: @emu.email

        link_subdomain = T.must(URI.parse(reset.link).host).split(".").first
        assert_equal link_subdomain, @tenant.slug

        new_pw_reset_link_subdomain = T.must(URI.parse(reset.new_reset_link).host).split(".").first
        assert_equal new_pw_reset_link_subdomain, @tenant.slug
      end
    end
  end
end
