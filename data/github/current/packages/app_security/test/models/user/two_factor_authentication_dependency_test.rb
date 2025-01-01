# typed: true
# frozen_string_literal: true
require "test_helper"

require "webauthn/fake_client"

class UsertwoFactorAuthenticationDependencyTest < GitHub::TestCase
  include AuthenticationHelpers
  include AuthndClientTestHelpers

  fixtures do
    @user = create(:user)
    @org = make_trusted_oauth_apps_owner
    @two_factor_user = create(:user)
    @two_factor_cred, _ = make_two_factor_credential(@two_factor_user)

    make_trusted_oauth_apps_owner
    @ios_app = Apps::Privileged.oauth_application(:ios_mobile)
    @ios_app ||= create(
      :oauth_application,
      user_id: GitHub.trusted_oauth_apps_owner,
      name: "GitHub iOS",
    )
    PrivilegedAppHelper.reconfigure_privileged_app(app_alias: :ios_mobile, app: @ios_app)

    unless GitHub.single_business_environment?
      enterprise = create(:business, :enterprise_managed)
      create(:business_saml_provider, business: enterprise)
      @managed_user = User.create_with_random_password("monalisa", false,
        { "email" => "monalisa@github.com", "force_enterprise_managed" => true, "login_suffix" => "mona" })
      enterprise.add_user_accounts([@managed_user.id])
    end
  end

  setup do
    setup_authnd_stub
  end

  teardown do
    remove_authnd_stub
  end

  context "#two_factor_authentication_enabled?" do
    test "with default auth, returns true if 2FA credentials are configured" do
      with_auth_mode(:default) do
        refute @user.two_factor_authentication_enabled?
        assert @two_factor_user.two_factor_authentication_enabled?
      end
    end

    test "with LDAP auth, returns true if 2FA credentials are configured" do
      with_auth_mode(:ldap) do
        refute @user.two_factor_authentication_enabled?
        assert @two_factor_user.two_factor_authentication_enabled?

        create(:user_ldap_mapping, subject: @two_factor_user)
        assert @two_factor_user.reload.two_factor_authentication_enabled?
      end
    end

    test "with SAML auth, only returns true if 2FA credentials are configured and the user is using builtin auth" do
      with_auth_mode(:saml) do
        GitHub.stubs(:builtin_auth_fallback).returns(false)
        refute @user.two_factor_authentication_enabled?
        refute @two_factor_user.two_factor_authentication_enabled?

        GitHub.stubs(:builtin_auth_fallback).returns(true)
        refute @user.two_factor_authentication_enabled?
        assert @two_factor_user.two_factor_authentication_enabled?

        create(:user_saml_mapping, user: @two_factor_user)
        refute @two_factor_user.reload.two_factor_authentication_enabled?
      end
    end

    test "with CAS auth, only returns true if 2FA credentials are configured and the user is using builtin auth" do
      with_auth_mode(:cas) do
        GitHub.stubs(:builtin_auth_fallback).returns(false)
        refute @user.two_factor_authentication_enabled?
        refute @two_factor_user.two_factor_authentication_enabled?

        GitHub.stubs(:builtin_auth_fallback).returns(true)
        refute @user.two_factor_authentication_enabled?
        assert @two_factor_user.two_factor_authentication_enabled?

        create(:cas_mapping, user: @two_factor_user)
        refute @two_factor_user.reload.two_factor_authentication_enabled?
      end
    end

    test "with GitHub auth, 2FA is never enabled" do
      with_auth_mode(:github_oauth) do
        refute @user.two_factor_authentication_enabled?
        refute @two_factor_user.two_factor_authentication_enabled?
      end
    end

    unless GitHub.single_business_environment?
      test "2FA is disabled for emu user" do
        refute @managed_user.two_factor_authentication_enabled?
      end

      test "2FA is enabled for emu shortcode user" do
        emu_business = create(:business, :enterprise_managed, :without_enterprise_managed_user_owner)
        emu_business.create_and_add_first_emu_owner(email: "monalisa@github.com", actor: @user)
        shortcode_user = User.find_by_login(emu_business.shortcode + "_admin")
        create(:two_factor_credential, user: shortcode_user)

        assert shortcode_user.two_factor_authentication_enabled?
      end
    end
  end

  test "accept a valid webauthn authentication attempt" do
    sign_hash = webauthn_register_and_sign

    assert_difference "@webauthn_registration.reload.counter", 1,  "expected counter to be incremented" do
      refute_nil @two_factor_user.webauthn_json_authenticated_registration(:test, GitHub.url, @challenge, sign_hash.to_json)
    end
  end

  test "includes passkeys in security_keys_for_settings when passkeys are disabled", enterprise_only: true do
    disable_enterprise_passkeys
    security_key = create(:security_key, user: @two_factor_user)
    trusted_device = create(:trusted_device, user: @two_factor_user)

    assert_same_elements [security_key, trusted_device], @two_factor_user.security_keys_for_settings
  end

  test "excludes passkeys from security_keys_for_settings when passkeys are enabled" do
    security_key = create(:security_key, user: @two_factor_user)
    trusted_device = create(:trusted_device, user: @two_factor_user)

    assert_equal [security_key], @two_factor_user.security_keys_for_settings
  end

  context "#available_u2f_registrations_description" do
    test "security key" do
      create(:security_key, user: @two_factor_user)

      assert_equal "security key", @two_factor_user.available_u2f_registrations_description
      assert_equal "Security key", @two_factor_user.available_u2f_registrations_description(capitalize_first_word: true)
      assert_equal "security keys", @two_factor_user.available_u2f_registrations_description(pluralize_each: true)
    end

    test "passkey" do
      authenticated_device = create(:authenticated_device, :verified_device, user: @two_factor_user)
      authenticated_device.trusted_device_client_registrations.create!(trusted_device: create(:trusted_device, user: @two_factor_user), user: @two_factor_user)

      assert_equal "passkey", @two_factor_user.available_u2f_registrations_description(authenticated_device.device_id)
      assert_equal "Passkey", @two_factor_user.available_u2f_registrations_description(authenticated_device.device_id, capitalize_first_word: true)
      assert_equal "passkeys", @two_factor_user.available_u2f_registrations_description(authenticated_device.device_id, pluralize_each: true)
    end

    test "passkey or security key" do
      create(:security_key, user: @two_factor_user)
      authenticated_device = create(:authenticated_device, :verified_device, user: @two_factor_user)
      authenticated_device.trusted_device_client_registrations.create!(trusted_device: create(:trusted_device, user: @two_factor_user), user: @two_factor_user)

      assert_equal "passkey or security key", @two_factor_user.available_u2f_registrations_description(authenticated_device.device_id)
      assert_equal "Passkey or security key", @two_factor_user.available_u2f_registrations_description(authenticated_device.device_id, capitalize_first_word: true)
      assert_equal "passkeys or security keys", @two_factor_user.available_u2f_registrations_description(authenticated_device.device_id, pluralize_each: true)

      assert_equal "Passkeys or security keys", @two_factor_user.available_u2f_registrations_description(authenticated_device.device_id, capitalize_first_word: true, pluralize_each: true)
      assert_equal "passkey", @two_factor_user.available_u2f_registrations_description(authenticated_device.device_id, passkeys_only: true)
    end
  end

  test "rejects an invalid webauthn authentication attempt" do
    sign_hash = webauthn_register_and_sign

    invalid_signature = "MEUCIEHupc95nNR6MDmmhdezZwU/L+dxdPu1VwWm5HCPQJ3oAiEAwcq0Uv42minwkNPKhf7kqTwd4LfoS6qz36eA5GiuELI="
    sign_hash["response"]["signature"] = invalid_signature

    assert_nil @two_factor_user.webauthn_json_authenticated_registration(:test, GitHub.url, @challenge, sign_hash.to_json)
  end

  context "#gh_mobile_auth_enabled?" do
    if GitHub.enterprise?
      test "gh mobile 2FA is disabled for enterprise user" do
        refute @user.gh_mobile_auth_enabled?
      end
    else
      context "true" do
        test "EMU first admin" do
          business = create(:emu, :owner).enterprise_managed_business
          admin = business.find_first_emu_owner

          assert admin.gh_mobile_auth_enabled?
        end

        test "user with no device key registration" do
          assert @user.gh_mobile_auth_enabled?
        end

        test "user with one mobile device key registration" do
          authnd_setup_gh_mobile_auth_user(@user)
          assert @user.gh_mobile_auth_enabled?
        end
      end

      context "false" do
        test "gh mobile 2FA is disabled for Proxima" do
          on_multi_tenant_enterprise do
            refute @user.gh_mobile_auth_enabled?
          end
        end
        test "gh mobile 2FA is disabled for EMUs" do
          emu = create(:emu)
          refute emu.gh_mobile_auth_enabled?
        end
        test "with GitHub auth, gh mobile 2FA is never enabled" do
          authnd_setup_gh_mobile_auth_user(@two_factor_user)

          with_auth_mode(:github_oauth) do
            refute @user.gh_mobile_auth_enabled?
            refute @two_factor_user.gh_mobile_auth_enabled?
          end
        end
      end
    end
  end

  context "#gh_mobile_auth_available?" do
    if GitHub.enterprise?
      test "gh mobile 2FA is not available for enterprise user" do
        authnd_setup_gh_mobile_auth_user(@user)
        refute @user.gh_mobile_auth_available?
      end
    else
      context "true" do
        test "user with one mobile device key registration" do
          authnd_setup_gh_mobile_auth_user(@user)

          assert @user.gh_mobile_auth_available?

          # verify the result is memoized
          stub_authnd_find_device_auth_key_registrations(user_id: @user.id, raise_with: Faraday::TimeoutError.new)
          assert @user.gh_mobile_auth_available?
        end

        test "returns true for user with multiple mobile device key registrations" do
          oauth_access_ios = make_oauth(@user, ["user"], @ios_app)
          oauth_access_ios_2 = make_oauth(@user, ["user"], @ios_app)

          stub_authnd_find_device_auth_key_registrations(user_id: @user.id, registrations: [
            Authnd::Proto::DeviceKeyRegistration.new(
              id: 2, device_name: "#{@user.login}'s iPhone", device_model: "iPhone-37", device_os: "osx", oauth_access_id: oauth_access_ios.id,
            ),
            Authnd::Proto::DeviceKeyRegistration.new(
              id: 3, device_name: "#{@user.login}'s Galaxy", device_model: "Galaxy S38", device_os: "android", oauth_access_id: oauth_access_ios_2.id,
            ),
          ])

          assert @user.gh_mobile_auth_available?
        end
      end

      context "false" do
        test "user without feature flag" do
          refute @user.gh_mobile_auth_available?
        end

        test "user with no mobile device key registrations" do
          stub_authnd_find_device_auth_key_registrations(user_id: @user.id)

          refute @user.gh_mobile_auth_available?
        end

        test "request fails" do
          stub_authnd_find_device_auth_key_registrations(user_id: @user.id, response_result: :RESULT_FAILED_GENERIC)

          refute @user.gh_mobile_auth_available?
        end

        test "with GitHub auth, gh mobile 2FA is never enabled" do
          authnd_setup_gh_mobile_auth_user(@user)
          authnd_setup_gh_mobile_auth_user(@two_factor_user)

          with_auth_mode(:github_oauth) do
            refute @user.gh_mobile_auth_available?
            refute @two_factor_user.gh_mobile_auth_available?
          end
        end

        [
          {
            exception: Faraday::TimeoutError.new,
            kind: "timeout"
          },
          {
            exception: ::Authnd::Proto::Error.new(message: "an error", twirp_error: Twirp::Error::new(:unavailable, "bad gateway")),
            kind: "unavailable"
          },
        ].each do |info|
          context info[:kind] do
            test "client raises" do
              stub_authnd_find_device_auth_key_registrations(user_id: @user.id, raise_with: info[:exception])

              refute @user.gh_mobile_auth_available?
            end
          end
        end
      end
    end

    unless GitHub.enterprise?
      context "#all_mobile_device_auth_keys" do
        test "returns empty array when a user has no mobile device registrations" do
          assert @user.all_mobile_device_auth_keys.empty?
        end

        test "returns an array of mobile device registrations" do
          stub_authnd_find_device_auth_key_registrations(user_id: @user.id, registrations: [
            Authnd::Proto::DeviceKeyRegistration.new(
              id: 3, device_name: "#{@user.login}'s iPhone", device_model: "iPhone-37", device_os: "ios", oauth_access_id: 2,
            ),
            Authnd::Proto::DeviceKeyRegistration.new(
              id: 4, device_name: "#{@user.login}'s iPhone", device_model: "iPhone-38", device_os: "ios", oauth_access_id: 3,
            ),
            ]
          )

          assert_equal 2, @user.all_mobile_device_auth_keys.count
        end
      end

      context "#display_mobile_device_auth_keys" do
        test "returns empty array when a user has no mobile device registrations" do
          assert @user.display_mobile_device_auth_keys.empty?
        end

        test "user with active mobile device registrations" do
          oauth_access_ios = make_oauth(@user, ["user"], @ios_app)
          oauth_access_ios_2 = make_oauth(@user, ["user"], @ios_app)

          stub_authnd_find_device_auth_key_registrations(user_id: @user.id, registrations: [
            Authnd::Proto::DeviceKeyRegistration.new(
              id: 3, device_name: "#{@user.login}'s iPhone", device_model: "iPhone-37", device_os: "ios", oauth_access_id: oauth_access_ios.id,
            ),
            Authnd::Proto::DeviceKeyRegistration.new(
              id: 4, device_name: "#{@user.login}'s iPhone", device_model: "iPhone-38", device_os: "ios", oauth_access_id: oauth_access_ios_2.id,
            ),
            ]
          )

          assert_equal 2, @user.display_mobile_device_auth_keys.length
        end

        test "stats and filters out mobile device with stale oauth access id" do
          GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
          ios_user = create(:user)

          make_trusted_oauth_apps_owner
          ios_app = Apps::Privileged.oauth_application(:ios_mobile)
          ios_app ||= create(
            :oauth_application,
            user_id: GitHub.trusted_oauth_apps_owner,
            name: "GitHub iOS",
          )
          PrivilegedAppHelper.reconfigure_privileged_app(app_alias: :ios_mobile, app: ios_app)

          # created but never accessed
          oauth_access_ios = make_oauth(ios_user, ["user"], ios_app)
          oauth_access_ios.update!(created_at: 2.years.ago)
          oauth_access_ios.update!(accessed_at: nil)

          # created but accessed over 2 years ago (stale)
          oauth_access_ios_2 = make_oauth(ios_user, ["user"], ios_app)
          oauth_access_ios_2.update!(created_at: 3.years.ago)
          oauth_access_ios_2.update!(accessed_at: 2.years.ago)

          oauth_access_ios_3 = make_oauth(ios_user, ["user"], ios_app)

          stub_authnd_find_device_auth_key_registrations(user_id: ios_user.id, registrations: [
            Authnd::Proto::DeviceKeyRegistration.new(
              id: 3, device_name: "#{ios_user.login}'s iPhone", device_model: "iPhone-37", device_os: "ios", oauth_access_id: oauth_access_ios.id,
            ),
            Authnd::Proto::DeviceKeyRegistration.new(
              id: 4, device_name: "#{ios_user.login}'s iPhone", device_model: "iPhone-38", device_os: "ios", oauth_access_id: oauth_access_ios_2.id,
            ),
            Authnd::Proto::DeviceKeyRegistration.new(
              id: 5, device_name: "#{ios_user.login}'s iPhone", device_model: "iPhone-39", device_os: "ios", oauth_access_id: oauth_access_ios_3.id,
            ),
            ]
          )

          assert_equal 1, ios_user.display_mobile_device_auth_keys.length
          assert_equal 2, GitHub.dogstats.increments("mobile_device_auth_keys.oauth_access", tags: ["status:stale"]).length
        end

        test "stats and filters out mobile device with a deleted oauth access id" do
          GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
          ios_user = create(:user)

          make_trusted_oauth_apps_owner
          ios_app = Apps::Privileged.oauth_application(:ios_mobile)
          ios_app ||= create(
            :oauth_application,
            user_id: GitHub.trusted_oauth_apps_owner,
            name: "GitHub iOS",
          )
          PrivilegedAppHelper.reconfigure_privileged_app(app_alias: :ios_mobile, app: ios_app)

          oauth_access_ios = make_oauth(ios_user, ["user"], ios_app)

          # deleted oauth access
          oauth_access_ios_2 = make_oauth(ios_user, ["user"], ios_app)
          oauth_access_ios_2.destroy

          stub_authnd_find_device_auth_key_registrations(user_id: ios_user.id, registrations: [
            Authnd::Proto::DeviceKeyRegistration.new(
              id: 3, device_name: "#{ios_user.login}'s iPhone", device_model: "iPhone-37", device_os: "ios", oauth_access_id: oauth_access_ios_2.id,
            ),
            Authnd::Proto::DeviceKeyRegistration.new(
              id: 4, device_name: "#{ios_user.login}'s iPhone", device_model: "iPhone-38", device_os: "ios", oauth_access_id: oauth_access_ios.id,
            ),
            ])

          assert_equal 1, ios_user.display_mobile_device_auth_keys.length
          assert_equal 1, GitHub.dogstats.increments("mobile_device_auth_keys.oauth_access", tags: ["status:deleted"]).length
        end

        test "filters multiple records for identical devices by oauth access recency" do
          GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
          mobile_user = create(:user)

          make_trusted_oauth_apps_owner
          ios_app = Apps::Privileged.oauth_application(:ios_mobile)
          ios_app ||= create(
            :oauth_application,
            user_id: GitHub.trusted_oauth_apps_owner,
            name: "GitHub iOS",
          )
          PrivilegedAppHelper.reconfigure_privileged_app(app_alias: :ios_mobile, app: ios_app)
          android_app = Apps::Privileged.oauth_application(:android_mobile)
          android_app ||= create(
            :oauth_application,
            user_id: GitHub.trusted_oauth_apps_owner,
            name: "GitHub Android",
          )
          PrivilegedAppHelper.reconfigure_privileged_app(app_alias: :android_mobile, app: android_app)

          # valid oauth accesses
          oauth_access_ios = make_oauth(mobile_user, ["user"], ios_app)
          oauth_access_ios_2 = make_oauth(mobile_user, ["user"], ios_app)
          oauth_access_android = make_oauth(mobile_user, ["user"], android_app)
          oauth_access_android_2 = make_oauth(mobile_user, ["user"], android_app)

          # created but accessed over 2 years ago (stale)
          oauth_access_ios_3 = make_oauth(mobile_user, ["user"], ios_app)
          oauth_access_ios_3.update!(created_at: 3.years.ago)
          oauth_access_ios_3.update!(accessed_at: 2.years.ago)

          stub_authnd_find_device_auth_key_registrations(user_id: mobile_user.id, registrations: [
            Authnd::Proto::DeviceKeyRegistration.new(
              id: 2, device_name: "#{mobile_user.login}'s Pixel", device_model: "Pixel 42 Pro", device_os: "Android", oauth_access_id: oauth_access_android_2.id,
            ),
            Authnd::Proto::DeviceKeyRegistration.new(
              id: 3, device_name: "#{mobile_user.login}'s iPhone", device_model: "iPhone-37", device_os: "ios", oauth_access_id: oauth_access_ios.id,
            ),
            Authnd::Proto::DeviceKeyRegistration.new(
              id: 4, device_name: "#{mobile_user.login}'s iPhone", device_model: "iPhone-38", device_os: "ios", oauth_access_id: oauth_access_ios_2.id,
            ),
            Authnd::Proto::DeviceKeyRegistration.new(
              id: 5, device_name: "#{mobile_user.login}'s iPhone", device_model: "iPhone-38", device_os: "ios", oauth_access_id: oauth_access_ios_3.id,
            ),
            Authnd::Proto::DeviceKeyRegistration.new(
              id: 6, device_name: "#{mobile_user.login}'s Pixel", device_model: "Pixel 42 Pro", device_os: "Android", oauth_access_id: oauth_access_android.id,
            ),
            ])

          auth_keys = mobile_user.display_mobile_device_auth_keys
          assert_same_elements [2, 3, 4], auth_keys.map(&:id)
          assert_equal 3, auth_keys.length
          assert_equal 1, GitHub.dogstats.increments("mobile_device_auth_keys.oauth_access", tags: ["status:stale"]).length
        end
      end
    end
  end

  test "GitHub.url is an origin" do
    assert_equal GitHub.url, Addressable::URI.parse(GitHub.url).origin, "expected GitHub.url to be formatted as an origin (webauthn code depends on this)"
  end

  test "two_factor_enabled scope returns the correct users" do
    assert_equal [@two_factor_user], User.two_factor_enabled.to_a
  end

  test "two_factor_disabled scope returns the correct users" do
    assert_same_elements (User.all.to_a - [@two_factor_user]), User.two_factor_disabled.to_a
  end

  context "#passkeys_enabled?" do
    test "returns true when feature enabled" do
      assert @two_factor_user.passkeys_enabled?
    end

    test "returns false when feature disabled", enterprise_only: true do
      disable_enterprise_passkeys
      refute @two_factor_user.passkeys_enabled?
    end

    unless GitHub.single_business_environment?
      test "passkeys are disabled for emu user" do
        refute @managed_user.passkeys_enabled?
      end

      test "passkeys are enabled for emu shortcode user" do
        emu_business = create(:business, :enterprise_managed, :without_enterprise_managed_user_owner)
        emu_business.create_and_add_first_emu_owner(email: "monalisa@github.com", actor: @user)
        shortcode_user = User.find_by_login(emu_business.shortcode + "_admin")
        create(:two_factor_credential, user: shortcode_user)

        assert shortcode_user.passkeys_enabled?
      end
    end
    test "passkeys can be enabled for enterprise if built-in auth enabled", enterprise_only: true do
      assert GitHub.passkeys_enabled?
      assert @user.passkeys_enabled?
    end
  end

  context "#allow_tfa_recovery_without_password?" do
    test "returns true correctly", skip_enterprise: true do
      GitHub.flipper[:tfa_recovery_without_password].enable

      assert @two_factor_user.allow_tfa_recovery_without_password?
    end

    test "returns false if enterprise", enterprise_only: true do
      GitHub.flipper[:tfa_recovery_without_password].enable

      refute @two_factor_user.allow_tfa_recovery_without_password?
    end

    test "returns false if flipper flag disabled", skip_enterprise: true do
      GitHub.flipper[:tfa_recovery_without_password].disable

      refute @two_factor_user.allow_tfa_recovery_without_password?
    end

    test "returns false if user is suspended", skip_enterprise: true do
      GitHub.flipper[:tfa_recovery_without_password].enable
      @two_factor_user.suspended_at = Time.now

      refute @two_factor_user.allow_tfa_recovery_without_password?
    end

    test "returns false if user doesn't have 2FA", skip_enterprise: true do
      GitHub.flipper[:tfa_recovery_without_password].enable

      refute @user.allow_tfa_recovery_without_password?
    end
  end

  test "destroying a user destroys their two factor credential and registrations" do
    user = create(:user)
    if GitHub.two_factor_sms_enabled?
      make_two_factor_credential_both_otp_methods(user,  backup_sms_number: "+1 1123456789")
    else
      make_two_factor_credential(user)
    end
    TwoFactorRequirementMetadata.create!(user: user, requirement_reason: "test", required_by: 3.years.ago, state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:required])

    assert user.two_factor_credential
    assert user.totp_app_registration
    assert user.two_factor_primary_sms_registration? if GitHub.two_factor_sms_enabled?
    assert user.two_factor_backup_sms_registration? if GitHub.two_factor_sms_enabled?
    assert user.two_factor_requirement_metadata

    user.destroy
    refute TwoFactorCredential.find_by(user_id: user.id)
    refute TotpAppRegistration.find_by(user_id: user.id)
    refute SmsRegistration.find_by(user_id: user.id)
    refute TwoFactorRequirementMetadata.find_by(user_id: user.id)
  end

  context "github mobile helpers are safe to call when feature not available", enterprise_only: true, skip_in_multitenant_mode: true, skip_with_all_emus: true do
    test "#has_mobile_device_auth_key?" do
      oauth_access_ios = make_oauth(@user, ["user"], @ios_app)

      stub_authnd_find_device_auth_key_registration(
        user_id: @user.id,
        oauth_access_id: oauth_access_ios.id,
        raise_with: Exception.new("should not be called"),
      )

      assert_nothing_raised do
        refute @user.has_mobile_device_auth_key?(oauth_access_ios.id)
      end
    end

    test "#all_mobile_device_auth_keys" do
      stub_authnd_find_device_auth_key_registrations(
        user_id: @user.id,
        raise_with: Exception.new("should not be called"),
      )

      assert_nothing_raised do
        assert_empty @user.all_mobile_device_auth_keys
      end
    end

    test "#display_mobile_device_auth_keys" do
      stub_authnd_find_device_auth_key_registrations(
        user_id: @user.id,
        raise_with: Exception.new("should not be called"),
      )

      assert_nothing_raised do
        assert_empty @user.display_mobile_device_auth_keys
      end
    end

    test "#revoke_mobile_device_auth_key" do
      oauth_access_ios = make_oauth(@user, ["user"], @ios_app)

      stub_authnd_revoke_device_auth_key_by_oauth_access_id(
        oauth_access_id: oauth_access_ios.id,
        raise_with: Exception.new("should not be called"),
      )

      assert_nothing_raised do
        assert_equal :RESULT_FAILED_UNSUPPORTED, @user.revoke_mobile_device_auth_key(@user, oauth_access_ios.id, "testing")
      end
    end

    test "#revoke_mobile_device_auth_keys" do
      stub_authnd_revoke_device_keys_by_user_id(
        user_id: @user.id,
        raise_with: Exception.new("should not be called"),
      )

      assert_nothing_raised do
        assert_equal :RESULT_FAILED_UNSUPPORTED, @user.revoke_mobile_device_auth_keys(@user, "testing")
      end
    end

    test "#revoke_mobile_keys_by_ids" do
      oauth_access_ios = make_oauth(@user, ["user"], @ios_app)
      oauth_access_ios_2 = make_oauth(@user, ["user"], @ios_app)
      ids = [oauth_access_ios.id, oauth_access_ios_2.id]

      stub_authnd_revoke_device_keys_by_ids(
        ids: ids,
        raise_with: Exception.new("should not be called"),
      )

      assert_nothing_raised do
        assert_equal :RESULT_FAILED_UNSUPPORTED, @user.revoke_mobile_device_keys_by_ids(@user, ids, "testing")
      end
    end
  end
end
