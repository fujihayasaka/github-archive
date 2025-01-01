# typed: false
# frozen_string_literal: true

require "test_helper"

class UserTombstoneDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create :organization, login: "newface-llc"
  end

  context "enterprise", enterprise_only: true do
    test "does not create a tombstone record after destroy" do
      @user.destroy!
      refute ReservedLogin.reserved?(@user.login)
    end

    test "does not check tombstone records when creating new logins" do
      user = build :user
      create :reserved_login, :tombstoned, login: user.login
      user.save
      refute user.errors[:login].any? { |text| text =~ /is unavailable/ }
    end
  end

  context "dotcom", skip_enterprise: true, skip_with_all_emus: true, skip_in_multitenant_mode: true do
    test "creates a tombstone record after destroy" do
      refute ReservedLogin.reserved?(@user.login)
      @user.destroy!
      assert ReservedLogin.reserved?(@user.login)
    end

    test "creates a tombstone record after update to login" do
      GitHub.flipper[:user_update_tombstone].enable
      user = create(:user)
      old_login = user.login

      refute ReservedLogin.reserved?(old_login)
      user.update!(login: "newnew")
      assert ReservedLogin.reserved?(old_login)
    end

    test "does not tombstone record after update to non-login user attribute" do
      GitHub.flipper[:user_update_tombstone].enable
      Failbot.expects(:report).never
      user = create(:user)

      refute ReservedLogin.reserved?(user.login)
      user.update!(email: "new@new.com")
      refute ReservedLogin.reserved?(user.login)
    end

    test "does not tombstone record after update to login if flag is disabled" do
      GitHub.flipper[:user_update_tombstone].disable
      user = create(:user)
      old_login = user.login

      refute ReservedLogin.reserved?(old_login)
      user.update!(login: "newnew")
      refute ReservedLogin.reserved?(old_login)
    end

    test "does not attempt to tombstone a bot" do
      Failbot.expects(:report).never

      bot = create(:bot, slug: "collei")
      refute ReservedLogin.reserved?(bot.login)
      bot.destroy!
      refute ReservedLogin.reserved?(bot.login)
    end

    test "creates tombstone record when an org which is not soft deleted is destroyed" do
      refute ReservedLogin.reserved?("newface-llc")
      refute_predicate @org.reload, :soft_deleted?

      @org.destroy!
      assert ReservedLogin.reserved?("newface-llc")
    end

    test "does not create tombstone record when a soft deleted org is destroyed" do
      @org.create_soft_deleted_organization(
        organization: @org,
        created_at: Organization::RESTORABLE_PERIOD.ago
      )
      refute ReservedLogin.reserved?("newface-llc")
      assert_predicate @org.reload, :soft_deleted?

      @org.destroy!
      refute ReservedLogin.reserved?("newface-llc")
    end

    test "does not attempt to tombstone an EMU" do
      ReservedLogin.expects(:tombstone!).never

      emu = create(:emu)
      refute ReservedLogin.reserved?(emu.login)
      emu.destroy!
      refute ReservedLogin.reserved?(emu.login)
    end

    test "does not raise if validation fails" do
      # Create a pre-existing tombstone, which will cause uniqueness
      # validation to fail.
      reservation = ReservedLogin.reserve!(@user.login)

      @user.destroy!
      assert_equal reservation.id, ReservedLogin.find_by_login(@user.login).id
    end

    test "ensures that new logins matching a tombstone cannot be created" do
      user = build :user
      create :reserved_login, :tombstoned, login: user.login
      user.save
      assert user.errors[:login].any? { |text| text =~ /is unavailable/ }
    end
  end
end
