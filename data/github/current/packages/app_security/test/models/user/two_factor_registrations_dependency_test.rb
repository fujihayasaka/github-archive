# typed: true
# frozen_string_literal: true

require "test_helper"

class UserTwoFactorRegistrationsDependencyTest < GitHub::TestCase
  include ResiliencyHelpers
  include HydroTestHelpers

  fixtures do
    @sms_user = create(:user, login: "smsuser")
    if GitHub.two_factor_sms_enabled?
      @sms_cred, @sms_registration = make_sms_two_factor_credential(@sms_user, number: "+1 7736829477")
    end

    @user = create(:user, login: "user")
    @cred, _ = make_two_factor_credential(@user)

    @india_sms_user = create(:user, login: "indiasmsuser")
    @uae_sms_user = create(:user, login: "uaesmsuser")
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    reset_monolith_redis_rate_limiter
    GitHub.flipper[:two_factor_sms_login_restriction_opt_out].disable
  end

  if GitHub.enterprise?
    test "provisioning_url includes github:user" do
      assert_includes GitHub::TwoFactorAuthentication.provisioning_url_for_authenticator_app(@user.totp_app_registration&.encrypted_otp_secret, @user.login), "GitHub%20Enterprise:github.com%2Fuser"
    end
  else
    test "provisioning_url includes github:user" do
      assert_includes GitHub::TwoFactorAuthentication.provisioning_url_for_authenticator_app(@user.totp_app_registration&.encrypted_otp_secret, @user.login), "GitHub:github.com%2Fuser"
    end
  end

  test "provisioning_url includes correct GitHub flavor" do
    assert_includes GitHub::TwoFactorAuthentication.provisioning_url_for_authenticator_app(@user.totp_app_registration&.encrypted_otp_secret, @user.login), "&issuer=GitHub"
  end

  if GitHub.two_factor_sms_enabled?
    test "send_two_factor_sms uses the default provider if one isn't configured" do
      GitHub::SMS.providers_for_env.first.expects(:noop)
      GitHub::SMS.providers_for_env.last.expects(:noop).never
      @sms_user.send_two_factor_sms
    end

    # OTP SMS should never be sent to GitHub Staff:
    # https://github.com/github/iam/issues/594
    test "does not send SMS to GitHub Staff" do
      staff = create(:staff_admin_user)
      make_two_factor_credential(staff)
      SmsRegistration.new(user: staff, encrypted_otp_secret: TwoFactorCredential.generate_secret, is_primary: true, sms_number: "+1 4158675309").save(validate: false)

      GitHub::SMS.expects(:send_message).never

      assert_raises GitHub::SMS::UnauthorizedRecipientError do
        staff.send_two_factor_sms
      end
    end

    # Fallback SMS should never be sent to GitHub Staff:
    # https://github.com/github/iam/issues/594
    test "does not send fallback SMS to GitHub Staff" do
      staff = create(:staff_admin_user)
      make_two_factor_credential(staff)
      SmsRegistration.new(user: staff, encrypted_otp_secret: TwoFactorCredential.generate_secret, is_primary: false, sms_number: "+1 4158675309").save(validate: false)

      GitHub::SMS.expects(:send_message).never

      assert_raises GitHub::SMS::UnauthorizedRecipientError do
        staff.send_two_factor_fallback_sms(:sign_in)
      end
    end

    test "sends fallback SMS to same provider if KV is unavailable" do
      Timecop.freeze do
        user = create :user
        make_two_factor_credential(user, backup_sms_number: "+1 4158675309")
        provider = GitHub::SMS.get_provider(user.two_factor_sms_provider)
        totp = user.two_factor_backup_sms_totp.now

        GitHub::SMS.expects(:send_message).with("+1 4158675309", "#{totp} is your GitHub authentication code.\n\n@#{GitHub.flavor} ##{totp}", user, equals(provider: provider, reason: :two_factor_auth_fallback)).twice

        prevent_connections_to(ApplicationRecord::Authnd) do
          user.send_two_factor_fallback_sms(:sign_in)
          user.send_two_factor_fallback_sms(:sign_in)
        end
      end
    end

    test "send_two_factor_sms uses the configured provider if there is one" do
      GitHub::SMS.providers_for_env.first.expects(:noop).never
      GitHub::SMS.providers_for_env.last.expects(:noop)
      @sms_registration&.update!(sms_provider: "test_two")
      @sms_user.reload
      @sms_user.send_two_factor_sms
    end

    test "send_two_factor_sms uses the alternate provider if told to and a provider isn't configured" do
      GitHub::SMS.providers_for_env.first.expects(:noop).never
      GitHub::SMS.providers_for_env.last.expects(:noop)
      @sms_user.send_two_factor_sms(use_alternate_provider = true)
    end

    test "send_two_factor_sms uses the other provider if told to and a provider is configured" do
      GitHub::SMS.providers_for_env.first.expects(:noop)
      GitHub::SMS.providers_for_env.last.expects(:noop).never
      @sms_registration&.update!(sms_provider: "test_two")
      @sms_user.reload
      @sms_user.send_two_factor_sms(use_alternate_provider = true)
    end

    test "send_two_factor_sms does not emit hydro event for successful SMS being sent if FF is disabled" do
      Timecop.freeze(Time.now.beginning_of_day) do
        GitHub.flipper[:publish_sms_sent_event].disable
        @sms_user.send_two_factor_sms

        refute_hydro_messages(schema: "github.v1.SmsMessageSent")
      end
    end

    test "send_two_factor_sms emits hydro event for successful SMS being sent if FF is enabled" do
      Timecop.freeze(Time.now.beginning_of_day) do
        GitHub.flipper[:publish_sms_sent_event].enable
        @sms_user.send_two_factor_sms

        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(@sms_user),
          hashed_sms_number: Digest::SHA256.hexdigest(@sms_user.two_factor_primary_sms_registration.sms_number),
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash)
        }, schema: "github.v1.SmsMessageSent")
      end
    end

    test "tracks outstanding sms otp" do
      Timecop.freeze do
        @sms_user.send_two_factor_sms
        key = @sms_user.sms_timing_key(@sms_user.two_factor_sms_totp.now, @sms_user.two_factor_primary_sms_registration&.encrypted_otp_secret)
        cached = OtpSmsTiming.by_timing_key(key)
        assert_equal Time.now.to_i, cached.created_at.to_i
        assert_equal @sms_user.id, cached.user_id
        assert_equal "test", cached.provider
      end
    end

    test "uses correct flavor in message for GitHub" do
      Timecop.freeze do
        totp = @sms_user.two_factor_sms_totp.now
        provider = GitHub::SMS.get_provider(@sms_user.two_factor_sms_provider)
        receipt = GitHub::SMS::Receipt.new(provider: provider, message_id: SecureRandom.hex)
        GitHub::SMS.expects(:send_message).with("+1 7736829477", "#{totp} is your GitHub authentication code.\n\n@#{GitHub.flavor} ##{totp}", @sms_user, equals(provider: provider, reason: :two_factor_auth_unknown, completed_captcha: false)).returns(receipt)
        @sms_user.send_two_factor_sms
      end
    end

    test "uses correct flavor in message and add origin bound code" do
      Timecop.freeze do
        totp = @sms_user.two_factor_sms_totp.now
        provider = GitHub::SMS.get_provider(@sms_user.two_factor_sms_provider)
        receipt = GitHub::SMS::Receipt.new(provider: provider, message_id: SecureRandom.hex)
        GitHub::SMS.expects(:send_message).with("+1 7736829477", "#{totp} is your GitHub authentication code.\n\n@#{GitHub.flavor} ##{totp}", @sms_user, equals(provider: provider, reason: :two_factor_auth_unknown, completed_captcha: false)).returns(receipt)
        @sms_user.send_two_factor_sms
      end
    end

    test "doesn't clobber existing stats if sms is resent" do
      first_key = T.cast(nil, T.untyped)
      second_key = T.cast(nil, T.untyped)
      first_time = T.cast(nil, T.untyped)
      second_time = T.cast(nil, T.untyped)
      time = Time.now

      # Make sure we're at a time where the OTP won't change in the next 5 seconds.
      unless @sms_user.two_factor_sms_totp.at(time) == @sms_user.two_factor_sms_totp.at(time + 5)
        time -= 15
      end

      Timecop.freeze(time) do
        @sms_user.send_two_factor_sms
        first_key = @sms_user.sms_timing_key(@sms_user.two_factor_sms_totp.now, @sms_user.two_factor_primary_sms_registration&.encrypted_otp_secret)
        cached = OtpSmsTiming.by_timing_key(first_key)
        first_time = cached.created_at
      end

      Timecop.freeze(time + 5) do
        @sms_user.send_two_factor_sms
        second_key = @sms_user.sms_timing_key(@sms_user.two_factor_sms_totp.now, @sms_user.two_factor_primary_sms_registration&.encrypted_otp_secret)
        cached = OtpSmsTiming.by_timing_key(second_key)
        second_time = cached.created_at
      end

      assert_equal first_key, second_key
      assert_equal first_time, second_time
    end

    test "raises error when SMS rate limits exceeded" do
      with_cache_enabled do
        Timecop.freeze do
          # The maximum number of times we can be called without raising
          max = GitHub::SMS::SMS_RATE_LIMIT_MAX_TRIES - 1
          max.times do
            @sms_user.send_two_factor_sms
          end

          assert_raises GitHub::SMS::RateLimitError do
            @sms_user.send_two_factor_sms
          end
        end
      end
    end

    context "#resolve_outstanding_sms_otp" do
      test "cleans up OtpSmsTiming record" do
        otp = @sms_user.two_factor_sms_totp.now
        key = @sms_user.sms_timing_key(otp, @sms_user.two_factor_primary_sms_registration&.encrypted_otp_secret)
        timing = OtpSmsTiming.create(timing_key: key, provider: "whatever", user_id: @sms_user.id)

        @sms_user.resolve_outstanding_sms_otp(otp)

        assert_nil OtpSmsTiming.by_timing_key(key)
      end

      test "updates the registration if provider recorded is different from the provider stored" do
        @sms_user.two_factor_primary_sms_registration.update!(sms_provider: "test")
        otp = @sms_user.two_factor_sms_totp.now
        key = @sms_user.sms_timing_key(otp, @sms_user.two_factor_primary_sms_registration&.encrypted_otp_secret)
        timing = OtpSmsTiming.create(timing_key: key, provider: "test2", user_id: @sms_user.id)

        @sms_user.two_factor_primary_sms_registration.expects(:update).with(sms_provider: "test2")
        @sms_user.resolve_outstanding_sms_otp(otp)
      end

      test "never updates the registration if provider recorded is same as the provider stored" do
        @sms_user.two_factor_primary_sms_registration.update!(sms_provider: "test")
        otp = @sms_user.two_factor_sms_totp.now
        key = @sms_user.sms_timing_key(otp, @sms_user.two_factor_primary_sms_registration&.encrypted_otp_secret)
        timing = OtpSmsTiming.create(timing_key: key, provider: "test", user_id: @sms_user.id)

        @sms_user.two_factor_primary_sms_registration.expects(:update).never

        @sms_user.resolve_outstanding_sms_otp(otp)
      end
    end

    test "instruments send_primary_sms audit log" do
      events = subscribe "two_factor_authentication.send_primary_sms"
      totp = @sms_user.two_factor_sms_totp.now

      provider = GitHub::SMS.get_provider(@sms_user.two_factor_sms_provider)
      message_id = SecureRandom.hex
      receipt = GitHub::SMS::Receipt.new(provider: provider, message_id: message_id)

      @sms_user.record_outstanding_sms_otp(totp, receipt, "callsite")

      expected_payload = {
        user: @sms_user.login,
        user_id: @sms_user.id,
        provider: receipt.provider.provider_name,
        message_id: receipt.message_id,
      }

      assert event = events.pop, "a send_primary_sms event was expected"
      assert_equal "two_factor_authentication.send_primary_sms", event.name
      assert_equal expected_payload, event.payload
    end

    context "SMS blocking" do
      test "does not send SMS to user when they have missed over 10 consecutive OTPs and last opt sent was an hour ago" do
        Timecop.freeze do
          @sms_registration&.update(consecutive_missed_otp_count: 10, last_otp_sent_at: 1.hour.ago)
          GitHub::SMS.expects(:send_message).never

          assert_raises GitHub::SMS::UnauthorizedRecipientError do
            @sms_user.send_two_factor_sms(false, callsite: :test)
          end

          stat = GitHub.dogstats.increments("sms_send_filter", tags: ["blocked:true", "reason:too_many_consecutive_misses", "action:test", "country:1"])[0]
          assert stat, "Expected a sms_send_filter metric to have been recorded"
        end
      end

      test "sends SMS to user when they have missed over 10 consecutive OTPs and last opt sent was a few days ago" do
        Timecop.freeze do
          @sms_registration&.update(consecutive_missed_otp_count: 10, last_otp_sent_at: 3.days.ago)

          @sms_user.send_two_factor_sms(false, callsite: :test)

          stat = GitHub.dogstats.increments("sms_send_filter", tags: ["blocked:false", "reason:too_many_consecutive_misses", "action:test", "country:1"])[0]
          assert stat, "Expected a sms_send_filter metric to have been recorded"
        end
      end

      test "sends SMS to suspicious user that has opted out" do
        GitHub.flipper[:two_factor_sms_login_restriction_opt_out].enable(@sms_user)
        @sms_user.update!(spammy: true, spammy_reason: "something else")
        @sms_user.send_two_factor_sms(false, callsite: :test)

        stat = GitHub.dogstats.increments("sms_send_filter", tags: ["blocked:false", "reason:opted_out", "action:test", "country:1"])[0]
        assert stat, "Expected a sms_send_filter metric to have been recorded"
      end

      test "sends SMS to user with a high risk country code" do
        user = create(:user)
        make_sms_two_factor_credential(user, number: "+880 1736829478", provider: "test")
        user.send_two_factor_sms(false, callsite: :test)

        assert_equal 1, GitHub::Authentication::KV.store.get("sms_daily_rate_limit:+880 1736829478").value! { 0 }.to_i
      end

      test "does not send SMS to user with a high risk country code if the SMS daily limit has been hit" do
        now = Time.now.utc
        Timecop.freeze(now) do
          user = create(:user)
          make_sms_two_factor_credential(user, number: "+880 1736829478", provider: "test")
          GitHub::Authentication::KV.store.set("sms_daily_rate_limit:+880 1736829478", "5", expires: now + 1.day)

          assert_raises GitHub::SMS::UnauthorizedRecipientError do
            user.send_two_factor_sms(false, callsite: :test)
          end
          stat = GitHub.dogstats.increments("sms_send_filter", tags: ["blocked:true", "reason:sms_daily_rate_limit", "action:test", "country:880"])[0]
          assert stat, "Expected a sms_send_filter metric to have been recorded"
        end
      end

      test "does not send SMS to user with a high risk country code if the user daily limit has been hit" do
        now = Time.now.utc
        Timecop.freeze(now) do
          user = create(:user)
          make_sms_two_factor_credential(user, number: "+880 1736829478", provider: "test")
          GitHub::Authentication::KV.store.set("user_daily_sms_rate_limit:#{user.id}", "5", expires: now + 1.day)

          assert_raises GitHub::SMS::UnauthorizedRecipientError do
            user.send_two_factor_sms(false, callsite: :test)
          end
          stat = GitHub.dogstats.increments("sms_send_filter", tags: ["blocked:true", "reason:user_daily_sms_rate_limit", "action:test", "country:880"])[0]
          assert stat, "Expected a sms_send_filter metric to have been recorded"
        end
      end

      test "does send SMS to user who has been marked as account farmer and enforcement FF is disabled" do
        GitHub.flipper[:enforce_spammy_reason_blockage].disable
        GitHub.flipper[:prevent_spammy_user_sms].disable
        now = Time.now.utc
        Timecop.freeze(now) do
          @sms_user.update!(spammy: true, spammy_reason: "Account farmer (email_domains_to_flag)")
          @sms_user.send_two_factor_sms(false, callsite: :test)

          stat = GitHub.dogstats.increments("sms_send_filter", tags: ["blocked:false", "reason:spammy_reason", "action:test", "country:1"])[0]
          assert stat, "Expected a sms_send_filter metric to have been recorded"
        end
      end

      test "does not send SMS to user who has been marked as account farmer and enforcement FF is enabled" do
        GitHub.flipper[:enforce_spammy_reason_blockage].enable
        GitHub.flipper[:prevent_spammy_user_sms].disable
        now = Time.now.utc
        Timecop.freeze(now) do
          @sms_user.update!(spammy: true, spammy_reason: "Account farmer (email_domains_to_flag)")
          assert_raises GitHub::SMS::UnauthorizedRecipientError do
            @sms_user.send_two_factor_sms(false, callsite: :test)
          end

          stat = GitHub.dogstats.increments("sms_send_filter", tags: ["blocked:true", "reason:spammy_reason", "action:test", "country:1"])[0]
          assert stat, "Expected a sms_send_filter metric to have been recorded"
        end
      end
    end
  end

  context "#valid_otp? for app type" do
    test "correctly identifies totp" do
      otp = @user.two_factor_app_totp.now
      User.any_instance.expects(:two_factor_verify_app_otp).with(otp).returns(true)
      User.any_instance.expects(:two_factor_verify_sms_otp).never
      User.any_instance.expects(:two_factor_verify_otp_for_all_2fa_registrations).never
      assert @user.valid_otp?(otp, callsite: "test", type: :app)
    end

    test "totp can be numeric" do
      otp = @user.two_factor_app_totp.now.to_i
      User.any_instance.expects(:two_factor_verify_app_otp).with(otp).returns(true)
      User.any_instance.expects(:two_factor_verify_sms_otp).never
      User.any_instance.expects(:two_factor_verify_otp_for_all_2fa_registrations).never
      assert @user.valid_otp?(otp, callsite: "test", type: :app)
    end

    test "fails if user doesn't have 2fa enabled" do
      user = create(:user)
      User.any_instance.expects(:two_factor_verify_app_otp).never
      User.any_instance.expects(:two_factor_verify_sms_otp).never
      User.any_instance.expects(:two_factor_verify_otp_for_all_2fa_registrations).never
      refute user.valid_otp?("something", callsite: "test", type: :app)
    end

    test "fails for unrecognized otp length" do
      User.any_instance.expects(:two_factor_verify_app_otp).never
      User.any_instance.expects(:two_factor_verify_sms_otp).never
      User.any_instance.expects(:two_factor_verify_otp_for_all_2fa_registrations).never
      refute @user.valid_otp?("wtf", callsite: "test", type: :app)
    end

    test "credential last_used_at is updated when app otp is valid" do
      now = Time.now.utc
      Timecop.freeze(now) do
        otp = @user.two_factor_app_totp.now
        User.any_instance.expects(:two_factor_verify_sms_otp).never
        User.any_instance.expects(:two_factor_verify_otp_for_all_2fa_registrations).never
        assert @user.valid_otp?(otp, callsite: "test", type: :app)
        assert @user.totp_app_registration.last_used_at
        assert_equal now.to_i, @user.totp_app_registration.last_used_at.to_i
      end
    end

    test "credential last_used_at isn't updated when app otp is invalid" do
      User.any_instance.expects(:two_factor_verify_app_otp).never
      User.any_instance.expects(:two_factor_verify_sms_otp).never
      User.any_instance.expects(:two_factor_verify_otp_for_all_2fa_registrations).never
      refute @user.valid_otp?("wtf", callsite: "test", type: :app)
      assert_nil @user.totp_app_registration.last_used_at
    end
  end

  context "#valid_otp? for sms type", skip_enterprise: true do
    test "correctly identifies totp" do
      otp = @sms_user.two_factor_sms_totp.now
      User.any_instance.expects(:two_factor_verify_sms_otp).with(otp).returns(true)
      User.any_instance.expects(:two_factor_verify_app_otp).never
      User.any_instance.expects(:two_factor_verify_otp_for_all_2fa_registrations).never
      assert @sms_user.valid_otp?(otp, callsite: "test", type: :sms)
    end

    test "totp can be numeric" do
      otp = @sms_user.two_factor_sms_totp.now.to_i
      User.any_instance.expects(:two_factor_verify_sms_otp).with(otp).returns(true)
      User.any_instance.expects(:two_factor_verify_app_otp).never
      User.any_instance.expects(:two_factor_verify_otp_for_all_2fa_registrations).never
      assert @sms_user.valid_otp?(otp, callsite: "test", type: :sms)
    end

    test "fails if user doesn't have 2fa enabled" do
      user = create(:user)
      User.any_instance.expects(:two_factor_verify_sms_otp).never
      User.any_instance.expects(:two_factor_verify_app_otp).never
      User.any_instance.expects(:two_factor_verify_otp_for_all_2fa_registrations).never
      refute user.valid_otp?("something", callsite: "test", type: :sms)
    end

    test "fails for unrecognized otp length" do
      User.any_instance.expects(:two_factor_verify_sms_otp).never
      User.any_instance.expects(:two_factor_verify_app_otp).never
      User.any_instance.expects(:two_factor_verify_otp_for_all_2fa_registrations).never
      refute @sms_user.valid_otp?("wtf", callsite: "test", type: :sms)
    end

    test "credential last_used_at is updated when sms otp is valid" do
      now = Time.now.utc
      Timecop.freeze(now) do
        otp = @sms_user.two_factor_sms_totp.now
        User.any_instance.expects(:two_factor_verify_app_otp).never
        User.any_instance.expects(:two_factor_verify_otp_for_all_2fa_registrations).never
        assert @sms_user.valid_otp?(otp, callsite: "test", type: :sms)
        assert @sms_user.two_factor_primary_sms_registration.last_used_at
        assert_equal now.to_i, @sms_user.two_factor_primary_sms_registration.last_used_at.to_i
      end
    end

    test "credential last_used_at is updated for both sms credentials when otp is valid" do
      user = create(:user)
      make_sms_two_factor_credential(user, number: "+1 1234567890", backup_sms_number: "+1 4159989999", provider: "test")

      now = Time.now.utc
      Timecop.freeze(now) do
        otp = user.two_factor_sms_totp.now
        User.any_instance.expects(:two_factor_verify_app_otp).never
        User.any_instance.expects(:two_factor_verify_otp_for_all_2fa_registrations).never
        assert user.valid_otp?(otp, callsite: "test", type: :sms)

        assert user.two_factor_primary_sms_registration.last_used_at
        assert_equal now.to_i, user.two_factor_primary_sms_registration.last_used_at.to_i
        assert user.two_factor_backup_sms_registration.last_used_at
        assert_equal now.to_i, user.two_factor_backup_sms_registration.last_used_at.to_i
      end
    end

    test "backup sms last_used_at is updated when app otp is valid and user has backup sms number" do
      user = create(:user)
      make_two_factor_credential(user, backup_sms_number: "+1 4159989999", backup_sms_provider: "test")

      now = Time.now.utc
      Timecop.freeze(now) do
        otp = user.two_factor_app_totp.now
        User.any_instance.expects(:two_factor_verify_sms_otp).never
        User.any_instance.expects(:two_factor_verify_otp_for_all_2fa_registrations).never
        assert user.valid_otp?(otp, callsite: "test", type: :app)

        assert user.totp_app_registration.last_used_at
        assert_equal now.to_i, user.totp_app_registration.last_used_at.to_i

        assert user.two_factor_backup_sms_registration.last_used_at
        assert_equal now.to_i, user.two_factor_backup_sms_registration.last_used_at.to_i
      end
    end

    test "credential last_used_at isn't updated when sms otp is invalid" do
      User.any_instance.expects(:two_factor_verify_app_otp).never
      User.any_instance.expects(:two_factor_verify_sms_otp).never
      User.any_instance.expects(:two_factor_verify_otp_for_all_2fa_registrations).never
      refute @sms_user.valid_otp?("wtf", callsite: "test", type: :sms)
      assert_nil @sms_user.two_factor_primary_sms_registration.last_used_at
    end
  end

  context "#valid_otp? for nil type" do
    test "fails if not allowed generic otp" do
      otp = @user.two_factor_app_totp.now
      User.any_instance.expects(:two_factor_verify_sms_otp).never
      User.any_instance.expects(:two_factor_verify_app_otp).never
      User.any_instance.expects(:two_factor_verify_otp_for_all_2fa_registrations).never
      refute @user.valid_otp?(otp, callsite: "test", type: nil)
    end

    test "correctly identifies totp if allow_generic" do
      otp = @user.two_factor_app_totp.now
      User.any_instance.expects(:two_factor_verify_sms_otp).never
      User.any_instance.expects(:two_factor_verify_app_otp).never
      User.any_instance.expects(:two_factor_verify_otp_for_all_2fa_registrations).with(otp, callsite: "test").returns(true)
      assert @user.valid_otp?(otp, type: nil, callsite: "test", allow_generic: true)
    end

    test "correctly updates app totp if allow_generic", skip_enterprise: true do
      user = create(:user)
      make_two_factor_credential_both_otp_methods(user)

      now = Time.now.utc
      Timecop.freeze(now) do
        otp = user.two_factor_app_totp.now
        User.any_instance.expects(:two_factor_verify_sms_otp).never
        User.any_instance.expects(:two_factor_verify_app_otp).never
        assert user.valid_otp?(otp, type: nil, callsite: "test", allow_generic: true)

        assert user.totp_app_registration.last_used_at
        assert_equal now.to_i, user.totp_app_registration.last_used_at.to_i
        # should not update sms
        assert_nil user.two_factor_primary_sms_registration.last_used_at
      end
    end

    test "correctly updates sms for allow_generic", skip_enterprise: true do
      user = create(:user)
      make_two_factor_credential_both_otp_methods(user)

      now = Time.now.utc
      Timecop.freeze(now) do
        otp = user.two_factor_sms_totp.now
        User.any_instance.expects(:two_factor_verify_sms_otp).never
        User.any_instance.expects(:two_factor_verify_app_otp).never
        assert user.valid_otp?(otp, type: nil, callsite: "test", allow_generic: true)

        assert user.two_factor_primary_sms_registration.last_used_at
        assert_equal now.to_i, user.two_factor_primary_sms_registration.last_used_at.to_i
        # should not update app
        assert_nil user.totp_app_registration.last_used_at
      end
    end

    test "correctly updates backup sms for app allow_generic", skip_enterprise: true do
      user = create(:user)
      make_two_factor_credential(user, backup_sms_number: "+1 4159989999", backup_sms_provider: "test")

      now = Time.now.utc
      Timecop.freeze(now) do
        otp = user.two_factor_app_totp.now
        User.any_instance.expects(:two_factor_verify_sms_otp).never
        User.any_instance.expects(:two_factor_verify_app_otp).never
        assert user.valid_otp?(otp, callsite: "test", type: nil, allow_generic: true)

        assert user.totp_app_registration.last_used_at
        assert_equal now.to_i, user.totp_app_registration.last_used_at.to_i

        assert user.two_factor_backup_sms_registration.last_used_at
        assert_equal now.to_i, user.two_factor_backup_sms_registration.last_used_at.to_i
      end
    end

    test "correctly updates backup sms for sms allow_generic", skip_enterprise: true do
      user = create(:user)
      make_sms_two_factor_credential(user, number: "+1 1234567890", backup_sms_number: "+1 4159989999", provider: "test")

      now = Time.now.utc
      Timecop.freeze(now) do
        otp = user.two_factor_sms_totp.now
        User.any_instance.expects(:two_factor_verify_sms_otp).never
        User.any_instance.expects(:two_factor_verify_app_otp).never
        assert user.valid_otp?(otp, callsite: "test", type: nil, allow_generic: true)

        assert user.two_factor_primary_sms_registration.last_used_at
        assert_equal now.to_i, user.two_factor_primary_sms_registration.last_used_at.to_i

        assert user.two_factor_backup_sms_registration.last_used_at
        assert_equal now.to_i, user.two_factor_backup_sms_registration.last_used_at.to_i
      end
    end
  end

  context "#two_factor_sms_provider", skip_enterprise: true do
    test "respects for_backup_number flag" do
      user = create(:user)
      make_sms_two_factor_credential(user, number: "+1 1234567890", backup_sms_number: "+1 4159989999", provider: "test")
      user.two_factor_backup_sms_registration.sms_provider = "test_two"
      user.two_factor_backup_sms_registration.save!

      retrieved = user.two_factor_sms_provider(for_backup_number: true)

      assert_equal "test_two", retrieved
    end

    test "uses primary provider if for_backup_number not specified" do
      user = create(:user)
      make_sms_two_factor_credential(user, number: "+1 1234567890", backup_sms_number: "+1 4159989999", provider: "test")
      user.two_factor_backup_sms_registration.sms_provider = "test_two"
      user.two_factor_backup_sms_registration.save!

      retrieved = user.two_factor_sms_provider

      assert_equal "test", retrieved
    end

    test "uses backup provider if no primary provider, even if not specified" do
      user = create(:user)
      make_two_factor_credential(user, backup_sms_number: "+1 4159989999", backup_sms_provider: "test")

      retrieved = user.two_factor_sms_provider

      assert_equal "test", retrieved
    end
  end

  context "promote_two_factor_sms_fallback_to_primary", skip_enterprise: true do
    test "returns false when fallback sms does not exists" do
      user = create(:user)
      make_sms_two_factor_credential(user)

      refute user.promote_two_factor_sms_fallback_to_primary
    end

    test "returns true when fallback sms is promoted to primary" do
      user = create(:user)
      make_sms_two_factor_credential(user, backup_sms_number: "+1 4159989999")

      assert user.promote_two_factor_sms_fallback_to_primary
    end
  end
end
