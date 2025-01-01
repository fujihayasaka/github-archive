# typed: true
# frozen_string_literal: true

require "test_helper"

class TwoFactorCredentialTest < GitHub::TestCase
  extend EncryptedColumnTestHelper
  include ResiliencyHelpers
  test_encrypted_column(:two_factor_credential, :encrypted_recovery_secret)

  fixtures do
    @user = create(:user, login: "user")
    @cred, _ = make_two_factor_credential(@user)

    @sms_user = create(:user, login: "smsuser")
    if GitHub.two_factor_sms_enabled?
      @sms_cred, _ = make_sms_two_factor_credential(@sms_user, number: "+1 7736829477")
    end

    @india_sms_user = create(:user, login: "indiasmsuser")
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    reset_monolith_redis_rate_limiter
  end

  # The way 2FA is setup requires that we temporarily store 2FA secrets in
  # GitHub KV across several steps. At each step we reconstitute a "temporary
  # two factor credential" with the state pulled from GitHub KV. As such, we
  # don't want new `TwoFactorCredential` objects to auto-generate secrets, as
  # it could lead to a condition where a secret is auto-generated rather than
  # pulled from GitHub KV. In the worst case, we could end up saving such a
  # record and have it not match what the user verified during the 2FA setup
  # flow. The number of places we need to manipulate these records is few, so
  # the additinal work of having to manually generate the secrets is
  # worthwhile.
  test "does not auto-generate secrets by default" do
    two_factor_cred = TwoFactorCredential.new(user: @user)
    assert_nil two_factor_cred.encrypted_recovery_secret
    assert_nil two_factor_cred.recovery_used_bitfield
    refute two_factor_cred.recovery_codes_viewed

    refute_predicate two_factor_cred, :valid?
    assert_includes_match /can't be blank/, two_factor_cred.errors[:encrypted_recovery_secret]
    assert_includes_match /can't be blank/, two_factor_cred.errors[:recovery_used_bitfield]
  end

  test "model is not valid when SMS fallback is configured for a GitHub employee", skip_enterprise: true do
    staff = create(:staff_admin_user)
    cred, _ = make_two_factor_credential(staff)
    assert_predicate cred, :valid?
    sms_registration = SmsRegistration.new(
      user_id: staff.id,
      is_primary: false,
      encrypted_otp_secret: TwoFactorCredential.generate_secret,
      sms_number: "+1 7736829477"
    )
    refute sms_registration.save
  end

  test "model is valid after generating secrets" do
    user = create(:user)
    two_factor_cred = TwoFactorCredential.new(user: user)
    two_factor_cred.generate_recovery_secret!
    refute_nil two_factor_cred.encrypted_recovery_secret
    assert_equal 0, two_factor_cred.recovery_used_bitfield
    refute two_factor_cred.recovery_codes_viewed

    assert_predicate two_factor_cred, :valid?
  end

  test "two-factor authenticates an app user" do
    otp = @user.two_factor_app_totp.now
    assert @user.two_factor_verify_app_otp(otp)
  end

  test "two-factor authenticates a sms user", skip_enterprise: true do
    otp = @sms_user.two_factor_sms_totp.now
    assert @sms_user.two_factor_verify_sms_otp(otp)
  end

  test "two_factor_verify_app_otp prevents TOTP reuse" do
    reset_cache
    enable_cache_storage
    otp = @user.two_factor_app_totp.now
    assert @user.two_factor_verify_app_otp(otp)
    refute @user.two_factor_verify_app_otp(otp)
    disable_cache_storage
  end

  test "two_factor_verify_sms_otp prevents TOTP reuse", skip_enterprise: true do
    reset_cache
    enable_cache_storage
    otp = @sms_user.two_factor_sms_totp.now
    assert @sms_user.two_factor_verify_sms_otp(otp)
    refute @sms_user.two_factor_verify_sms_otp(otp)
    disable_cache_storage
  end

  test "two_factor_verify_sms_otp does not prevent TOTP reuse if KV is unavailable", skip_enterprise: true do
    reset_cache
    enable_cache_storage
    prevent_connections_to(ApplicationRecord::Authnd) do
      otp = @sms_user.two_factor_sms_totp.now
      assert @sms_user.two_factor_verify_sms_otp(otp)
      assert @sms_user.two_factor_verify_sms_otp(otp)
    end
    disable_cache_storage
  end

  test "formatted recovery codes match normal recovery codes" do
    formatted = @cred.formatted_recovery_codes
    normal = GitHub::TwoFactorAuthentication.recovery_codes(@cred.encrypted_recovery_secret)

    formatted.zip(normal).each do |a, b|
      assert_includes a, "-"
      assert_equal a.sub("-", ""), b
    end
  end

  test "two-factor authenticates a user with recovery code" do
    code = GitHub::TwoFactorAuthentication.recovery_code(@cred.encrypted_recovery_secret, 0)
    assert_equal @user, User.two_factor_authenticate_with_recovery(@user.login, code)
  end

  test "recovery codes can't be reused" do
    code = GitHub::TwoFactorAuthentication.recovery_code(@cred.encrypted_recovery_secret, 0)
    assert_equal @user, User.two_factor_authenticate_with_recovery(@user.login, code)
    assert_nil User.two_factor_authenticate_with_recovery(@user.login, code)
  end

  test "low global notice next banner is set when there is less than 5 remaining and FF is enabled" do
    user = create :user, :verified
    cred, _ = make_two_factor_credential(user)
    cred.recovery_codes_viewed!

    notice = user.global_notice

    code_used_idx = 0
    while cred.number_of_remaining_codes > 6
      cred.reload
      notice.reload

      User.two_factor_authenticate_with_recovery(user.login,
        GitHub::TwoFactorAuthentication.recovery_code(cred.encrypted_recovery_secret, code_used_idx)
      )

      refute_equal notice.name, "two_factor_low_recovery_codes"
      code_used_idx += 1
    end

    cred.reload
    notice.reload
    code = GitHub::TwoFactorAuthentication.recovery_code(cred.encrypted_recovery_secret, 0)
    User.two_factor_authenticate_with_recovery(user.login, code)

    assert_equal notice.name, "two_factor_low_recovery_codes"
  end

  test "fail with bad otp" do
    refute @user.two_factor_verify_app_otp("000000")
  end

  test "fails if user has 2fa diabled" do
    user = create(:user)
    TwoFactorCredential.expects(:verify_totp).never
    refute @user.two_factor_verify_app_otp("123456")
  end

  test "sets global notice when two-factor credential created if recovery codes not viewed" do
    user = create :user
    make_two_factor_credential(user)

    notice = GlobalNoticeNext.new(viewer: user)
    assert_equal :two_factor_recovery_codes, notice.current_notice_name
  end

  test "does not set global notice when two-factor credential created if recovery codes viewed" do
    user = create :user, :verified
    cred, _ = make_two_factor_credential(user)
    cred.recovery_codes_viewed!

    # Refresh notice state in KV
    user.global_notice.refresh

    # Create a new GlobalNoticeNext (since it caches the state of the notice in an instance field)
    notice = GlobalNoticeNext.new(viewer: user)
    assert_nil notice.current_notice_name
  end

  test "does not set global notice when two-factor credential deleted" do
    user = create :user, :verified
    cred, _ = make_two_factor_credential(user)
    cred.destroy!
    user.reload

    # Refresh notice state in KV
    user.global_notice.refresh

    # Create a new GlobalNoticeNext (since it caches the state of the notice in an instance field)
    notice = GlobalNoticeNext.new(viewer: user)
    assert_nil notice.current_notice_name
  end

  test "does not set if user has no two-factor codes" do
    user = create :user
    notice = GlobalNoticeNext.new(viewer: user)
    assert_nil notice.current_notice_name
  end

  unless GitHub.single_business_environment?
    test "sets status in BusinessUserAccount when created" do
      user = create :user
      business = create :business, owners: [user]
      cred, totp_app_registration = make_two_factor_credential(user, backup_sms_number: "+1 1123456789")
      assert business.business_user_account_for(user).two_factor_enabled?
    end
  end

  context "#destroy" do
    test "cleans up associated app registration record and backup sms number" do
      user = create :user
      cred, totp_app_registration = make_two_factor_credential(user, backup_sms_number: "+1 1123456789")

      assert TwoFactorCredential.find_by(user_id: user.id)
      assert TotpAppRegistration.find_by(user_id: user.id)
      assert_equal 1, SmsRegistration.where(user_id: user.id).count

      cred.destroy

      refute TwoFactorCredential.find_by(user_id: user.id)
      refute TotpAppRegistration.find_by(user_id: user.id)
      assert_equal 0, SmsRegistration.where(user_id: user.id).count
    end

    test "cleans up associated sms registration records", skip_enterprise: true do
      user = create :user
      cred, sms_registration = make_sms_two_factor_credential(user, backup_sms_number: "+1 1123456789")

      assert TwoFactorCredential.find_by(user_id: user.id)
      assert_equal 2, SmsRegistration.where(user_id: user.id).count

      cred.destroy

      refute TwoFactorCredential.find_by(user_id: user.id)
      assert_equal 0, SmsRegistration.where(user_id: user.id).count
    end

    unless GitHub.single_business_environment?
      test "updates status in BusinessUserAccount" do
        user = create :user
        business = create :business, owners: [user]
        assert business.business_user_account_for(user).two_factor_disabled?

        cred, totp_app_registration = make_two_factor_credential(user, backup_sms_number: "+1 1123456789")
        assert business.business_user_account_for(user).two_factor_enabled?

        cred.destroy
        assert business.business_user_account_for(user).two_factor_disabled?
      end
    end
  end

  if GitHub.two_factor_sms_enabled?
    test "instruments falling back to sms codes with authenticator configured" do
      user = create :user
      cred, sms_registration = make_two_factor_credential(user, backup_sms_number: "+1 7736829477")

      user.security_checkup_completed("updated")

      events = subscribe "two_factor_authentication.sign_in_fallback_sms"
      user.send_two_factor_fallback_sms(:sign_in)

      assert event = events.pop, "a send_fallback_sms event was expected"
      assert_equal "two_factor_authentication.sign_in_fallback_sms", event.name
    end
  end
end
