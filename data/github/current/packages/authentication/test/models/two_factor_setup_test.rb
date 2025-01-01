# typed: true
# frozen_string_literal: true

require "test_helper"

class TwoFactorSetupTest < GitHub::TestCase
  setup do
    reset_monolith_redis_rate_limiter
  end

  context "#pending?" do
    test "returns false if no value in KV" do
      user = create(:user)
      refute TwoFactorSetup.pending?(user)
    end

    test "returns false if value in KV is empty" do
      user = create(:user)
      GitHub::Authentication::KV.store.set(TwoFactorSetup.kv_key(user), {}.to_json)
      refute TwoFactorSetup.pending?(user)
    end

    test "returns true if value in KV is not empty" do
      user = create(:user)
      GitHub::Authentication::KV.store.set(TwoFactorSetup.kv_key(user), { foo: "bar" }.to_json)
      assert TwoFactorSetup.pending?(user)
    end
  end

  context "#start" do
    test "sets expected KV values" do
      user = create(:user)
      TwoFactorSetup.start(user)
      kv_json = GitHub::Authentication::KV.store.get(TwoFactorSetup.kv_key(user)).value! { nil }
      refute_nil kv_json
      kv_values = JSON.parse(kv_json, symbolize_names: true)
      kv_value_keys = kv_values.keys
      assert kv_value_keys.include?(:secret)
      assert kv_value_keys.include?(:recovery_secret)
      assert kv_value_keys.include?(:recovery_salt_version)
      assert kv_value_keys.include?(:app_salt_version)
      assert_equal 4, kv_values.size
    end

    test "sets expected KV values if skip_recovery_secret" do
      user = create(:user)
      TwoFactorSetup.start(user, skip_recovery_secret: true)
      kv_json = GitHub::Authentication::KV.store.get(TwoFactorSetup.kv_key(user)).value! { nil }
      refute_nil kv_json
      kv_values = JSON.parse(kv_json, symbolize_names: true)
      kv_value_keys = kv_values.keys
      assert kv_value_keys.include?(:secret)
      assert kv_value_keys.include?(:app_salt_version)
      refute kv_value_keys.include?(:recovery_secret)
      refute kv_value_keys.include?(:recovery_salt_version)
      assert_equal 2, kv_values.size
    end

    test "sets SMS provider KV values if they already exists" do
      user = create(:user)
      TwoFactorSetup.start(user)
      number = "+1 7736829477"
      provider = "foo"
      TwoFactorSetup.set_sms_values(user, number, provider)
      kv_json = GitHub::Authentication::KV.store.get(TwoFactorSetup.kv_key(user)).value! { nil }
      refute_nil kv_json
      kv_values = JSON.parse(kv_json, symbolize_names: true)
      initial_provider = kv_values[:provider]
      assert kv_values.include?(:provider)
      assert kv_values.include?(:sms_number)

      TwoFactorSetup.start(user)
      kv_json = GitHub::Authentication::KV.store.get(TwoFactorSetup.kv_key(user)).value! { nil }
      refute_nil kv_json
      kv_values = JSON.parse(kv_json, symbolize_names: true)

      assert kv_values.include?(:provider)
      refute kv_values.include?(:sms_number)
      assert_equal initial_provider, kv_values[:provider]
    end

    test "resets KV values if called when they already exist" do
      user = create(:user)
      TwoFactorSetup.start(user)
      kv_json = GitHub::Authentication::KV.store.get(TwoFactorSetup.kv_key(user)).value! { nil }
      refute_nil kv_json
      kv_values = JSON.parse(kv_json, symbolize_names: true)
      initial_secret = kv_values[:secret]
      initial_recovery_secret = kv_values[:recovery_secret]
      refute_nil initial_secret
      refute_nil initial_recovery_secret
      TwoFactorSetup.start(user)
      kv_json = GitHub::Authentication::KV.store.get(TwoFactorSetup.kv_key(user)).value! { nil }
      refute_nil kv_json
      kv_values = JSON.parse(kv_json, symbolize_names: true)
      new_secret = kv_values[:secret]
      new_recovery_secret = kv_values[:recovery_secret]
      refute_nil new_secret
      refute_nil new_recovery_secret
      refute_equal initial_secret, new_secret
      refute_equal initial_recovery_secret, new_recovery_secret
    end

    test "internal kv cache is not shared between users" do
      user1 = create(:user)
      TwoFactorSetup.start(user1)
      user2 = create(:user)
      TwoFactorSetup.start(user2)

      kv_json_for_user1 = GitHub::Authentication::KV.store.get(TwoFactorSetup.kv_key(user1)).value! { nil }
      refute_nil kv_json_for_user1
      kv_json_for_user2 = GitHub::Authentication::KV.store.get(TwoFactorSetup.kv_key(user2)).value! { nil }
      refute_nil kv_json_for_user2

      kv_values_for_user1 = JSON.parse(kv_json_for_user1, symbolize_names: true)
      kv_values_for_user2 = JSON.parse(kv_json_for_user2, symbolize_names: true)

      refute_equal kv_values_for_user1[:secret], kv_values_for_user2[:secret]
      refute_equal kv_values_for_user1[:recovery_secret], kv_values_for_user2[:recovery_secret]
    end

    test "sets expected value for recovery code salt when ff is enabled" do
      user = create(:user)
      now = Time.now.utc
      Timecop.freeze(now) do
        TwoFactorSetup.start(user)
      end

      kv_json = GitHub::Authentication::KV.store.get(TwoFactorSetup.kv_key(user)).value! { nil }
      refute_nil kv_json
      kv_values = JSON.parse(kv_json, symbolize_names: true)
      kv_value_keys = kv_values.keys

      assert_equal GitHub.recovery_code_salt_version, kv_values[:recovery_salt_version]
      assert kv_value_keys.include?(:recovery_salt_version)
      assert kv_value_keys.include?(:app_salt_version)
      assert_equal 4, kv_values.size
    end
  end

  context "#values_for" do
    test "returns nil for values if no value in KV" do
      user = create(:user)
      assert_equal [nil, nil], TwoFactorSetup.values_for(user, :secret, :recovery_secret)
    end

    test "returns value for key if it exists" do
      user = create(:user)
      TwoFactorSetup.start(user)
      kv_json = GitHub::Authentication::KV.store.get(TwoFactorSetup.kv_key(user)).value! { nil }
      refute_nil kv_json
      refute_nil JSON.parse(kv_json, symbolize_names: true)[:secret]
      assert_equal [JSON.parse(kv_json, symbolize_names: true)[:secret]], TwoFactorSetup.values_for(user, :secret)
    end

    test "returns value for key if it exists in the KV object even if a non existing value is provided" do
      user = create(:user)
      TwoFactorSetup.start(user)
      kv_json = GitHub::Authentication::KV.store.get(TwoFactorSetup.kv_key(user)).value! { nil }
      refute_nil kv_json
      refute_nil JSON.parse(kv_json, symbolize_names: true)[:secret]
      assert_equal [nil, JSON.parse(kv_json, symbolize_names: true)[:secret]], TwoFactorSetup.values_for(user, :not_a_thing, :secret)
    end
  end

  context "#set_sms_values" do
    test "sets expected KV values and preserves existing values from initialization" do
      user = create(:user)
      TwoFactorSetup.start(user)
      number = "+1 7736829477"
      provider = "foo"
      TwoFactorSetup.set_sms_values(user, number, provider)
      kv_json = GitHub::Authentication::KV.store.get(TwoFactorSetup.kv_key(user)).value! { nil }
      refute_nil kv_json
      kv_values = JSON.parse(kv_json, symbolize_names: true)
      kv_value_keys = kv_values.keys
      assert kv_value_keys.include?(:secret)
      assert kv_value_keys.include?(:recovery_secret)
      assert_equal number, kv_values[:sms_number]
      assert_equal provider, kv_values[:provider]
      assert kv_value_keys.include?(:recovery_salt_version)
      assert kv_value_keys.include?(:app_salt_version)
      assert_equal 6, kv_values.size
    end
  end

  context "#set_recovery_codes_last_downloaded_at" do
    test "sets expected KV value when recovery codes are downloaded" do
      user = create(:user)
      now = Time.now.utc
      Timecop.freeze(now) do
        TwoFactorSetup.start(user)
        TwoFactorSetup.set_recovery_codes_last_downloaded_at(user)
      end

      kv_json = GitHub::Authentication::KV.store.get(TwoFactorSetup.kv_key(user)).value! { nil }
      refute_nil kv_json
      kv_values = JSON.parse(kv_json, symbolize_names: true)
      kv_value_keys = kv_values.keys

      assert kv_value_keys.include?(:recovery_codes_last_downloaded_at)
      assert_equal now.to_i, DateTime.parse(kv_values[:recovery_codes_last_downloaded_at]).to_i
      assert kv_value_keys.include?(:recovery_salt_version)
      assert kv_value_keys.include?(:app_salt_version)
      assert_equal 5, kv_values.size
    end

    test "sets expected value for recovery code salt when ff is enabled" do
      user = create(:user)
      now = Time.now.utc
      Timecop.freeze(now) do
        TwoFactorSetup.start(user)
      end

      kv_json = GitHub::Authentication::KV.store.get(TwoFactorSetup.kv_key(user)).value! { nil }
      refute_nil kv_json
      kv_values = JSON.parse(kv_json, symbolize_names: true)
      kv_value_keys = kv_values.keys

      assert_equal GitHub.recovery_code_salt_version, kv_values[:recovery_salt_version]
      assert kv_value_keys.include?(:recovery_salt_version)
      assert kv_value_keys.include?(:app_salt_version)
      assert_equal 4, kv_values.size
    end
  end

  context "#verify_totp" do
    test "does not set verified if otp is nil" do
      user = create(:user)
      TwoFactorSetup.start(user)
      TwoFactorSetup.verify_totp(:app, user, nil)

      kv_json = GitHub::Authentication::KV.store.get(TwoFactorSetup.kv_key(user)).value! { nil }
      refute_nil kv_json
      kv_values = JSON.parse(kv_json, symbolize_names: true)
      kv_value_keys = kv_values.keys
      refute kv_value_keys.include?(:verified)
      # verify the initial KV values still exist
      assert kv_value_keys.include?(:secret)
      assert kv_value_keys.include?(:recovery_secret)
      assert kv_value_keys.include?(:recovery_salt_version)
      assert kv_value_keys.include?(:app_salt_version)
      assert_equal 4, kv_values.size
    end

    test "does not set verified if otp is empty string" do
      user = create(:user)
      TwoFactorSetup.start(user)
      TwoFactorSetup.verify_totp(:app, user, "")

      kv_json = GitHub::Authentication::KV.store.get(TwoFactorSetup.kv_key(user)).value! { nil }
      refute_nil kv_json
      kv_values = JSON.parse(kv_json, symbolize_names: true)
      kv_value_keys = kv_values.keys
      refute kv_value_keys.include?(:verified)
      # verify the initial KV values still exist
      assert kv_value_keys.include?(:secret)
      assert kv_value_keys.include?(:recovery_secret)
      assert kv_value_keys.include?(:recovery_salt_version)
      assert kv_value_keys.include?(:app_salt_version)
      assert_equal 4, kv_values.size
    end

    test "does not set verified if otp verification fails" do
      user = create(:user)
      TwoFactorSetup.start(user)
      kv_json = GitHub::Authentication::KV.store.get(TwoFactorSetup.kv_key(user)).value! { nil }
      refute_nil kv_json
      kv_values = JSON.parse(kv_json, symbolize_names: true)
      expected_secret = kv_values[:secret]
      refute_nil expected_secret

      otp = "123456"
      GitHub::TwoFactorAuthentication.expects(:verify_otp_for_setup).once.with(:app, otp, expected_secret, GitHub.app_otp_salt_version).returns(false)
      TwoFactorSetup.verify_totp(:app, user, otp)

      kv_json = GitHub::Authentication::KV.store.get(TwoFactorSetup.kv_key(user)).value! { nil }
      refute_nil kv_json
      kv_values = JSON.parse(kv_json, symbolize_names: true)
      kv_value_keys = kv_values.keys
      refute kv_value_keys.include?(:verified)
      # verify the initial KV values still exist
      assert kv_value_keys.include?(:secret)
      assert kv_value_keys.include?(:recovery_secret)
      assert kv_value_keys.include?(:recovery_salt_version)
      assert kv_value_keys.include?(:app_salt_version)
      assert_equal 4, kv_values.size
    end

    test "sets kv as verified and preserves existing values from initialization when otp verification succeeds" do
      user = create(:user)
      TwoFactorSetup.start(user)
      kv_json = GitHub::Authentication::KV.store.get(TwoFactorSetup.kv_key(user)).value! { nil }
      refute_nil kv_json
      kv_values = JSON.parse(kv_json, symbolize_names: true)
      expected_secret = kv_values[:secret]
      refute_nil expected_secret

      otp = "123456"
      GitHub::TwoFactorAuthentication.expects(:verify_otp_for_setup).once.with(:app, otp, expected_secret, GitHub.app_otp_salt_version).returns(true)
      TwoFactorSetup.verify_totp(:app, user, otp)
      kv_json = GitHub::Authentication::KV.store.get(TwoFactorSetup.kv_key(user)).value! { nil }
      refute_nil kv_json
      kv_values = JSON.parse(kv_json, symbolize_names: true)
      kv_value_keys = kv_values.keys
      assert kv_value_keys.include?(:verified)
      # verify the initial KV values still exist
      assert kv_value_keys.include?(:secret)
      assert kv_value_keys.include?(:recovery_secret)
      assert kv_value_keys.include?(:recovery_salt_version)
      assert kv_value_keys.include?(:app_salt_version)
      assert_equal 5, kv_values.size
    end
  end

  # used by tests below to create a user that has went through the required setup steps up
  # until the enable_two_factor call
  # returns initialized secrets
  def prep_user_for_enable_two_factor(user, sms_number: nil, provider: nil, skip_recovery_secret: false)
    TwoFactorSetup.start(user, skip_recovery_secret: skip_recovery_secret)
    if sms_number
      TwoFactorSetup.set_sms_values(user, sms_number, provider.provider_name)
    end
    GitHub::TwoFactorAuthentication.expects(:verify_otp_for_setup).once.returns(true)
    TwoFactorSetup.verify_totp(sms_number.present? ? :sms : :app, user, "123456")

    TwoFactorSetup.set_recovery_codes_last_downloaded_at(user)
    kv_json = GitHub::Authentication::KV.store.get(TwoFactorSetup.kv_key(user)).value! { nil }
    refute_nil kv_json
    kv_values = JSON.parse(kv_json, symbolize_names: true)
    [kv_values[:secret], kv_values[:recovery_secret]]
  end

  context "#enable_two_factor" do
    test "returns false if type is not correct" do
      user = create(:user)
      TwoFactorSetup.start(user)
      refute TwoFactorSetup.enable_two_factor(user, nil)
      user.reload
      refute user.two_factor_credential
      refute user.totp_app_registration
      refute user.two_factor_primary_sms_registration?
      refute user.two_factor_backup_sms_registration?
      refute TwoFactorSetup.enable_two_factor(user, "")
      user.reload
      refute user.two_factor_credential
      refute user.totp_app_registration
      refute user.two_factor_primary_sms_registration?
      refute user.two_factor_backup_sms_registration?
      refute TwoFactorSetup.enable_two_factor(user, "nah")
      user.reload
      refute user.two_factor_credential
      refute user.totp_app_registration
      refute user.two_factor_primary_sms_registration?
      refute user.two_factor_backup_sms_registration?
    end

    test "returns false if not verified" do
      user = create(:user)
      TwoFactorSetup.start(user)
      refute TwoFactorSetup.enable_two_factor(user, "app")
      user.reload
      refute user.two_factor_credential
      refute user.totp_app_registration
      refute user.two_factor_primary_sms_registration?
      refute user.two_factor_backup_sms_registration?
    end

    test "returns false if a user is reconfiguring" do
      user = create(:user)
      make_two_factor_credential(user)
      user.reload
      expected_2fa_credential = user.two_factor_credential
      expected_totp_registration = user.totp_app_registration

      prep_user_for_enable_two_factor(user)
      refute TwoFactorSetup.enable_two_factor(user, "app")

      user.reload
      # the users 2fa credential should not have changed
      assert_equal expected_2fa_credential, user.two_factor_credential
      assert_equal expected_totp_registration, user.totp_app_registration
    end

    if GitHub.two_factor_sms_enabled?
      test "new sms setup" do
        user = create(:user)

        sms_number = "+1 7736829477"
        provider = GitHub::SMS::Test.new
        expected_is_reconfiguring = false
        AccountMailer.expects(:two_factor_enable).with(instance_of(TwoFactorCredential), expected_is_reconfiguring).once.returns(stub(deliver_later: nil))
        GitHub::SMS.expects(:send_message).with(sms_number, regexp_matches(/\AYou have successfully configured.*/), user, equals({ provider: provider.provider_name.to_s, reason: :two_factor_setup_confirmation }))

        secret, recovery_secret = prep_user_for_enable_two_factor(user, sms_number: sms_number, provider: provider)
        # enable and check 2fa settings are persisted to the user
        assert TwoFactorSetup.enable_two_factor(user, "sms")
        user.reload
        assert_equal recovery_secret, user.two_factor_credential.encrypted_recovery_secret
        assert_equal sms_number, user.two_factor_sms_number
        assert_equal "test", user.two_factor_sms_provider
        assert user.two_factor_configured_with?(:sms)
        refute user.two_factor_configured_with?(:app)
        assert_equal secret, user.two_factor_primary_sms_registration.encrypted_otp_secret

        # kv values have been cleared
        refute TwoFactorSetup.pending?(user)

        refute user.totp_app_registration
        refute_empty user.sms_registrations
        assert_equal 1, user.sms_registrations.length

        registration = user.sms_registrations.first
        assert_equal secret, registration.encrypted_otp_secret
        assert_equal sms_number, registration.sms_number
        assert_equal "test", user.two_factor_sms_provider
        assert registration.is_primary?
      end
    end

    test "2fa bypass date is set when configuring 2fa" do
      user = create(:user)

      prep_user_for_enable_two_factor(user)
      assert TwoFactorSetup.enable_two_factor(user, "app")
      assert user.is_flagged_for_two_factor_checkup?
    end

    test "deletes orphaned 2FA records before enabling app 2FA" do
      user = create(:user)

      # creating orphaned records before enabling 2FA
      if GitHub.two_factor_sms_enabled?
        create(:user_two_factor_primary_sms_registration, user: user)
      end
      old_totp_record = create(:totp_app_registration, user: user)
      user.reload

      assert user.totp_app_registration.present?
      assert user.two_factor_primary_sms_registration? if GitHub.two_factor_sms_enabled?

      prep_user_for_enable_two_factor(user)

      assert TwoFactorSetup.enable_two_factor(user, "app")
      assert user.totp_app_registration.present?
      refute_equal old_totp_record.id, user.totp_app_registration.id
      refute user.two_factor_primary_sms_registration? if GitHub.two_factor_sms_enabled?
    end

    test "deletes orphaned 2FA records before enabling sms 2FA", skip_enterprise: true do
      user = create(:user)

      sms_number = "+1 7736829477"
      provider = GitHub::SMS::Test.new

      # creating orphaned records before enabling 2FA
      old_sms_record = create(:user_two_factor_primary_sms_registration, user: user)
      create(:totp_app_registration, user: user)

      user.reload

      assert user.totp_app_registration.present?
      assert user.two_factor_primary_sms_registration?

      prep_user_for_enable_two_factor(user, sms_number: sms_number, provider: provider)

      assert TwoFactorSetup.enable_two_factor(user, "sms")
      assert user.two_factor_primary_sms_registration?
      refute_equal old_sms_record.id, user.two_factor_primary_sms_registration.id
      refute user.totp_app_registration.present?
    end

    test "saves salt originally used for recovery codes even if ff is disabled during enrollment" do
      user = create(:user)
      assert_equal GitHub.recovery_code_salt_version, 1
      GitHub.stubs(:recovery_code_salt_version).returns(2)
      assert_equal GitHub.recovery_code_salt_version, 2
      prep_user_for_enable_two_factor(user)
    end

    test "saves default salt value when ff is disabled" do
      user = create(:user)
      prep_user_for_enable_two_factor(user)
      assert_equal GitHub.recovery_code_salt_version, 1
      assert TwoFactorSetup.enable_two_factor(user, "app")
      assert_equal user.two_factor_credential.recovery_salt_version, 1
    end

    test "sets default value for recovery code salt when ff is enabled" do
      user = create(:user)
      prep_user_for_enable_two_factor(user)
      assert_equal GitHub.recovery_code_salt_version, 1
      assert TwoFactorSetup.enable_two_factor(user, "app")
      assert_equal user.two_factor_credential.recovery_salt_version, 1
    end

    test "sets latest value for recovery code salt when ff is enabled" do
      GitHub.stubs(:recovery_code_salt_version).returns(2)
      user = create(:user)
      prep_user_for_enable_two_factor(user)
      assert_equal GitHub.recovery_code_salt_version, 2
      assert TwoFactorSetup.enable_two_factor(user, "app")
      assert_equal user.two_factor_credential.recovery_salt_version, 2
    end

    test "sets default value for app salt version when ff is enabled" do
      user = create(:user)
      prep_user_for_enable_two_factor(user)
      assert_equal GitHub.app_otp_salt_version, 1
      assert TwoFactorSetup.enable_two_factor(user, "app")
      assert_equal user.totp_app_registration.salt_version, 1
    end

    test "sets latest value for app salt version when ff is enabled" do
      GitHub.stubs(:app_otp_salt_version).returns(2)
      user = create(:user)
      prep_user_for_enable_two_factor(user)
      assert_equal GitHub.app_otp_salt_version, 2
      assert TwoFactorSetup.enable_two_factor(user, "app")
      assert_equal user.totp_app_registration.salt_version, 2
    end
  end

  context "#configure_app" do
    test "returns false if not verified" do
      user = create(:user)
      TwoFactorSetup.start(user, skip_recovery_secret: true)
      refute TwoFactorSetup.configure_app(user)
    end

    test "returns false if 2FA setup does not exist" do
      user = create(:user)

      refute TwoFactorSetup.configure_app(user)
    end

    test "successfully reconfigures app" do
      user = create(:user)
      make_two_factor_credential(user)
      registration_id = user.totp_app_registration.id
      totp_app_secret = user.totp_app_registration.encrypted_otp_secret
      recovery_secret = user.two_factor_credential.encrypted_recovery_secret
      assert user.totp_app_registration

      AccountMailer.expects(:two_factor_configure_factor).with(user, "authenticator app", reconfiguring: true).once.returns(stub(deliver_later: nil))

      new_secret, _ = prep_user_for_enable_two_factor(user, skip_recovery_secret: true)

      result = TwoFactorSetup.configure_app(user)

      user.reload
      refute TwoFactorSetup.pending?(user) # kv values have been cleared
      assert result

      refute_equal totp_app_secret, user.totp_app_registration.encrypted_otp_secret
      assert_equal new_secret, user.totp_app_registration.encrypted_otp_secret
      assert_equal recovery_secret, user.two_factor_credential.encrypted_recovery_secret
      refute_equal registration_id, user.totp_app_registration.id
    end

    test "successfully configures app when sms is already configured", skip_enterprise: true do
      user = create(:user)
      make_sms_two_factor_credential(user)
      recovery_secret = user.two_factor_credential.encrypted_recovery_secret
      assert user.two_factor_primary_sms_registration.present?

      AccountMailer.expects(:two_factor_configure_factor).with(user, "authenticator app", reconfiguring: false).once.returns(stub(deliver_later: nil))

      new_secret, _ = prep_user_for_enable_two_factor(user, skip_recovery_secret: true)

      result = TwoFactorSetup.configure_app(user)

      user.reload
      refute TwoFactorSetup.pending?(user) # kv values have been cleared
      assert result

      assert user.totp_app_registration.present?
      assert user.two_factor_primary_sms_registration.present?
      assert_equal new_secret, user.totp_app_registration.encrypted_otp_secret
      refute_equal new_secret, user.two_factor_primary_sms_registration.encrypted_otp_secret
      assert_equal recovery_secret, user.two_factor_credential.encrypted_recovery_secret
    end

    test "configure_app sets default value for app salt version when ff is enabled" do
      assert_equal GitHub.app_otp_salt_version, 1

      user = create(:user)
      make_two_factor_credential(user)
      registration_id = user.totp_app_registration.id
      totp_app_secret = user.totp_app_registration.encrypted_otp_secret
      recovery_secret = user.two_factor_credential.encrypted_recovery_secret
      assert user.totp_app_registration

      AccountMailer.expects(:two_factor_configure_factor).with(user, "authenticator app", reconfiguring: true).once.returns(stub(deliver_later: nil))
      new_secret, _ = prep_user_for_enable_two_factor(user, skip_recovery_secret: true)
      result = TwoFactorSetup.configure_app(user)

      user.reload
      refute TwoFactorSetup.pending?(user) # kv values have been cleared
      assert result

      refute_equal totp_app_secret, user.totp_app_registration.encrypted_otp_secret
      assert_equal new_secret, user.totp_app_registration.encrypted_otp_secret
      assert_equal recovery_secret, user.two_factor_credential.encrypted_recovery_secret
      refute_equal registration_id, user.totp_app_registration.id
      assert_equal 1, user.totp_app_registration.salt_version
    end

    test "configure_app sets latest value for app salt version when ff is enabled" do
      GitHub.stubs(:app_otp_salt_version).returns(2)
      assert_equal GitHub.app_otp_salt_version, 2

      user = create(:user)
      make_two_factor_credential(user)
      registration_id = user.totp_app_registration.id
      totp_app_secret = user.totp_app_registration.encrypted_otp_secret
      recovery_secret = user.two_factor_credential.encrypted_recovery_secret
      assert user.totp_app_registration

      AccountMailer.expects(:two_factor_configure_factor).with(user, "authenticator app", reconfiguring: true).once.returns(stub(deliver_later: nil))
      new_secret, _ = prep_user_for_enable_two_factor(user, skip_recovery_secret: true)
      result = TwoFactorSetup.configure_app(user)

      user.reload
      refute TwoFactorSetup.pending?(user) # kv values have been cleared
      assert result

      refute_equal totp_app_secret, user.totp_app_registration.encrypted_otp_secret
      assert_equal new_secret, user.totp_app_registration.encrypted_otp_secret
      assert_equal recovery_secret, user.two_factor_credential.encrypted_recovery_secret
      refute_equal registration_id, user.totp_app_registration.id
      assert_equal user.totp_app_registration.salt_version, 2
    end

    test "2fa checkup date is bumped when user reconfigures app" do
      now = Time.now.utc
      Timecop.freeze(now) do
        user = create(:user)

        prep_user_for_enable_two_factor(user)
        assert TwoFactorSetup.enable_two_factor(user, "app")
        assert user.is_flagged_for_two_factor_checkup?
        old_2fa_checkup_date = GitHub::Authentication::KV.store.get(user.two_factor_checkup_key).value { nil }

        Timecop.travel(1.week)

        prep_user_for_enable_two_factor(user, skip_recovery_secret: true)
        TwoFactorSetup.configure_app(user)

        assert user.is_flagged_for_two_factor_checkup?

        new_2fa_checkup_date = GitHub::Authentication::KV.store.get(user.two_factor_checkup_key).value { nil }

        refute_equal old_2fa_checkup_date, new_2fa_checkup_date
        assert new_2fa_checkup_date > old_2fa_checkup_date
      end
    end

    test "2fa checkup date is not set when kv value is cleared when user reconfigures app" do
      user = create(:user)

      prep_user_for_enable_two_factor(user)
      assert TwoFactorSetup.enable_two_factor(user, "app")
      assert user.is_flagged_for_two_factor_checkup?

      user.clear_two_factor_checkup_date

      prep_user_for_enable_two_factor(user, skip_recovery_secret: true)
      TwoFactorSetup.configure_app(user)
      refute user.is_flagged_for_two_factor_checkup?
    end
  end

  context "#configure_sms", skip_enterprise: true do
    test "returns false if not verified" do
      user = create(:user)
      TwoFactorSetup.start(user, skip_recovery_secret: true)
      refute TwoFactorSetup.configure_sms(user)
    end

    test "returs false if 2Fa setup does not exist" do
      user = create(:user)
      refute TwoFactorSetup.configure_sms(user)
    end

    test "successfully configures sms" do
      user = create(:user)
      make_sms_two_factor_credential(user)

      assert user.two_factor_primary_sms_registration?

      primary_sms_registration = user.two_factor_primary_sms_registration
      recovery_secret = user.two_factor_credential.encrypted_recovery_secret

      AccountMailer.expects(:two_factor_configure_factor).with(user, "SMS", reconfiguring: true).once.returns(stub(deliver_later: nil))

      sms_number = "+1 7736829477"
      provider = GitHub::SMS::Test.new

      new_secret, _ = prep_user_for_enable_two_factor(user, sms_number: sms_number, provider: provider, skip_recovery_secret: true)

      result = TwoFactorSetup.configure_sms(user)

      user.reload
      refute TwoFactorSetup.pending?(user) # kv values have been cleared
      assert result

      refute_equal primary_sms_registration.id, user.two_factor_primary_sms_registration.id
      refute_equal primary_sms_registration.encrypted_otp_secret, user.two_factor_primary_sms_registration.encrypted_otp_secret
      assert_equal new_secret, user.two_factor_primary_sms_registration.encrypted_otp_secret
      assert_equal recovery_secret, user.two_factor_credential.encrypted_recovery_secret
    end

    test "keeps backup sms otp secret consistent" do
      user = create(:user)
      make_sms_two_factor_credential(user, backup_sms_number: "+1 7736829476")

      sms_number = "+1 7736829477"
      provider = GitHub::SMS::Test.new
      new_secret, _ = prep_user_for_enable_two_factor(user, sms_number: sms_number, provider: provider, skip_recovery_secret: true)
      result = TwoFactorSetup.configure_sms(user)

      user.reload
      assert_equal new_secret, user.two_factor_primary_sms_registration.encrypted_otp_secret
      assert_equal new_secret, user.two_factor_backup_sms_registration.encrypted_otp_secret
    end

    test "successfully configures sms when app is already configured" do
      user = create(:user)
      make_two_factor_credential(user)
      app_registration_secret = user.totp_app_registration.encrypted_otp_secret
      recovery_secret = user.two_factor_credential.encrypted_recovery_secret
      assert user.totp_app_registration.present?

      AccountMailer.expects(:two_factor_configure_factor).with(user, "SMS", reconfiguring: false).once.returns(stub(deliver_later: nil))
      sms_number = "+1 7736829477"
      provider = GitHub::SMS::Test.new

      new_secret, _ = prep_user_for_enable_two_factor(user, sms_number: sms_number, provider: provider, skip_recovery_secret: true)

      result = TwoFactorSetup.configure_sms(user)

      user.reload
      refute TwoFactorSetup.pending?(user) # kv values have been cleared
      assert result

      assert user.totp_app_registration.present?
      assert user.two_factor_primary_sms_registration?
      assert_equal app_registration_secret, user.totp_app_registration.encrypted_otp_secret
      refute_equal app_registration_secret, user.two_factor_primary_sms_registration.encrypted_otp_secret
      assert_equal recovery_secret, user.two_factor_credential.encrypted_recovery_secret
    end

    test "2fa checkup date is bumped when user reconfigures sms" do
      now = Time.now.utc
      Timecop.freeze(now) do
        user = create(:user)

        sms_number = "+1 7736829477"
        provider = GitHub::SMS::Test.new
        prep_user_for_enable_two_factor(user, sms_number: sms_number, provider: provider)

        assert TwoFactorSetup.enable_two_factor(user, "sms")
        assert user.is_flagged_for_two_factor_checkup?
        old_2fa_checkup_date = GitHub::Authentication::KV.store.get(user.two_factor_checkup_key).value { nil }

        Timecop.travel(1.week)

        sms_number = "+1 7736829412"
        prep_user_for_enable_two_factor(user, sms_number: sms_number, provider: provider, skip_recovery_secret: true)
        TwoFactorSetup.configure_sms(user)

        assert user.is_flagged_for_two_factor_checkup?

        new_2fa_checkup_date = GitHub::Authentication::KV.store.get(user.two_factor_checkup_key).value { nil }
        refute_equal old_2fa_checkup_date, new_2fa_checkup_date
        assert new_2fa_checkup_date > old_2fa_checkup_date
      end
    end

    test "2fa checkup date is not set when kv value is cleared when user reconfigures sms" do
      user = create(:user)

      sms_number = "+1 7736829477"
      provider = GitHub::SMS::Test.new
      prep_user_for_enable_two_factor(user, sms_number: sms_number, provider: provider)
      assert TwoFactorSetup.enable_two_factor(user, "sms")
      assert user.is_flagged_for_two_factor_checkup?

      user.clear_two_factor_checkup_date

      TwoFactorSetup.configure_sms(user)
      refute user.is_flagged_for_two_factor_checkup?
    end
  end
end
