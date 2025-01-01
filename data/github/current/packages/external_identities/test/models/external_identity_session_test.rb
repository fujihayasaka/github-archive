# typed: true
# frozen_string_literal: true

require "test_helper"

class ExternalIdentitySessionTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @active_session  = create :external_identity_session, expires_at: 1.day.from_now
    @expired_session = create :external_identity_session, expires_at: 1.day.ago

    @admin = create :user, skip_enterprise_managed_user: true
    @non_emu_business = create :business, owners: [@admin], skip_enterprise_managed_business: true
    @non_emu_user = create :user, skip_enterprise_managed_user: true
    @non_emu_business.add_user_accounts([@non_emu_user.id])
  end

  context "validates" do
    test "all fields present" do
      assert_predicate @active_session, :valid?
    end

    test "the presence of a user_session" do
      @active_session.user_session = nil
      @active_session.valid?
      refute_empty @active_session.errors[:user_session]
    end

    test "the presence of an external_identity" do
      @active_session.external_identity = nil
      @active_session.valid?
      refute_empty @active_session.errors[:external_identity]
    end
  end

  context "expires_at" do
    test "defaults to 1 day from now if FF is disabled" do
      GitHub.flipper[:org_saml_session_length_configurable].disable
      Timecop.freeze do
        @active_session.expires_at = nil
        assert_predicate @active_session, :valid?

        assert_same_time 1.day.from_now, @active_session.expires_at
      end
    end

    test "If no expiration time is set when the session is created or updated, and the FF is enabled, and value set in db, use it" do
      GitHub.flipper[:org_saml_session_length_configurable].enable
      session = create :external_identity_session, expires_at: nil
      provider = session.external_identity.provider
      provider.update!(session_length_in_minutes: 10_000)

      Timecop.freeze do
        session.update!(expires_at: nil)
        assert_in_delta 10_000.minutes.from_now, session.expires_at, 5.seconds
      end

      provider.update!(session_length_in_minutes: 10_079)
      user_session = session.user_session

      Timecop.freeze do
        new_ext_session = user_session.external_identity_sessions.create(external_identity: session.external_identity, expires_at: nil)
        assert_in_delta 10_079.minutes.from_now, new_ext_session.expires_at, 5.seconds
      end
    end

    test "If no expiration time is set when the session is created or updated, and the FF is enabled, and value not set in db, use default" do
      GitHub.flipper[:org_saml_session_length_configurable].enable
      session = create :external_identity_session, expires_at: nil
      provider = session.external_identity.provider
      provider.update!(session_length_in_minutes: nil)

      Timecop.freeze do
        session.update!(expires_at: nil)
        assert_in_delta 1.day.from_now, session.expires_at, 5.seconds
      end

      user_session = session.user_session

      Timecop.freeze do
        new_ext_session = user_session.external_identity_sessions.create(external_identity: session.external_identity, expires_at: nil)
        assert_in_delta 1.day.from_now, new_ext_session.expires_at, 5.seconds
      end
    end
  end

  context ".active" do
    test "includes active (unexpired) sessions, excludes expired sessions" do
      assert_includes ExternalIdentitySession.active, @active_session
      refute_includes ExternalIdentitySession.active, @expired_session
    end
  end

  context ".expired" do
    test "includes expired sessions, excludes active (unexpired) sessions" do
      assert_includes ExternalIdentitySession.expired, @expired_session
      refute_includes ExternalIdentitySession.expired, @active_session
    end
  end

  context ".require_user_sessions" do
    test "does not include active sessions without user session" do
      active_session_without_user_session = create :external_identity_session, expires_at: 1.day.from_now
      active_session_without_user_session.user_session.delete

      assert_includes ExternalIdentitySession.with_user_session, @active_session
      refute_includes ExternalIdentitySession.with_user_session, active_session_without_user_session
    end
  end

  test "user_session not revoked for non-EMU" do
    session = create :user_session, user: @non_emu_user
    external_identity_session = create :external_identity_session, user_session: session
    assert @non_emu_user.sessions.active.any?
    assert @non_emu_user.external_identity_sessions.active.any?

    external_identity_session.destroy
    refute @non_emu_user.reload.external_identity_sessions.any?
    refute session.reload.revoked?

    assert_dogstats_increment 1, "external_identity_session.destroy.revoke_user_session", tags: ["revoked:false"]
  end

  test "delegates user_id to the user_session" do
    session = create :user_session, user: @non_emu_user
    external_identity_session = create :external_identity_session, user_session: session
    assert @non_emu_user.sessions.active.any?
    assert @non_emu_user.external_identity_sessions.active.any?

    assert_equal session.user_id, external_identity_session.user_id
  end
end

class EMUExternalIdentitySessionTest < GitHub::TestCase
  skip_enterprise

  include DogstatsTestHelpers

  fixtures do
    @emu = create :emu, provider_type: :oidc
    @business = @emu.enterprise_managed_business
    create :emu, :owner, business: @business
    @emu_owner = @business.find_first_emu_owner
  end

  context "destroy" do
    test "user_session revoked for EMU with FF enabled" do
      GitHub.flipper[:emu_user_session_expiration].enable(@emu)

      session = create :user_session, user: @emu
      external_identity_session = create :external_identity_session, user_session: session
      assert @emu.sessions.active.any?
      assert @emu.external_identity_sessions.active.any?

      external_identity_session.destroy
      refute @emu.reload.external_identity_sessions.any?
      assert session.reload.revoked?
      assert_equal "emu_session_revoked", session.reload.revoked_reason

      assert_dogstats_increment 1, "external_identity_session.destroy.revoke_user_session", tags: ["revoked:true"]
    end

    test "user_session not revoked for EMU with FF disabled" do
      GitHub.flipper[:emu_user_session_expiration].disable(@emu)

      session = create :user_session, user: @emu
      external_identity_session = create :external_identity_session, user_session: session
      assert @emu.sessions.active.any?
      assert @emu.external_identity_sessions.active.any?

      external_identity_session.destroy
      refute @emu.reload.external_identity_sessions.any?
      refute session.reload.revoked?

      assert_dogstats_increment 1, "external_identity_session.destroy.revoke_user_session", tags: ["revoked:false"]
    end

    test "user_session not revoked for EMU first owner" do
      session = create :user_session, user: @emu_owner
      external_identity_session = create :external_identity_session, user_session: session
      assert @emu_owner.sessions.active.any?
      assert @emu_owner.external_identity_sessions.active.any?

      external_identity_session.destroy
      refute @emu_owner.reload.external_identity_sessions.any?
      refute session.reload.revoked?

      assert_dogstats_increment 1, "external_identity_session.destroy.revoke_user_session", tags: ["revoked:false"]
    end

    test "user_session destroy does not cause revoke" do
      GitHub.flipper[:emu_user_session_expiration].enable(@emu)

      session = create :user_session, user: @emu
      external_identity_session = create :external_identity_session, user_session: session
      assert @emu.sessions.active.any?
      assert @emu.external_identity_sessions.active.any?

      session.destroy
      refute @emu.reload.external_identity_sessions.any?
      refute @emu.reload.sessions.active.any?

      assert_dogstats_increment 1, "external_identity_session.destroy.revoke_user_session", tags: ["revoked:false"]
    end

  end
end
