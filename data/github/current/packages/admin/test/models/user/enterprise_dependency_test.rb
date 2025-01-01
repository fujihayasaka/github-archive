# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseSpecificUserOptionsDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  context "#show_enterprise_contribution_counts_on_dotcom" do
    if GitHub.enterprise?
      test "#show_enterprise_contribution_counts_on_dotcom? is initially false" do
        refute @user.show_enterprise_contribution_counts_on_dotcom?
      end

      test "#show_enterprise_contribution_counts_on_dotcom? is false if no last sync date is set on dotcom user" do
        DotcomUser.create(user: @user)

        refute @user.show_enterprise_contribution_counts_on_dotcom?
      end

      test "#show_enterprise_contribution_counts_on_dotcom? is true if dotcom user has a last sync date" do
        DotcomUser.create(user: @user, last_contributions_sync: Time.now)

        assert @user.show_enterprise_contribution_counts_on_dotcom?
      end

      test "#show_enterprise_contribution_counts_on_dotcom=true fills in an empty sync date" do
        assert_nil DotcomUser.for(@user).last_contributions_sync
        @user.show_enterprise_contribution_counts_on_dotcom = true
        refute_nil DotcomUser.for(@user).last_contributions_sync
      end

      test "#show_enterprise_contribution_counts_on_dotcom=true doesn't touch an existing sync date" do
        sync_date = Time.now - 1.week
        DotcomUser.create(user: @user, last_contributions_sync: sync_date)

        assert_equal sync_date.to_i, DotcomUser.for(@user).last_contributions_sync.to_i
        @user.show_enterprise_contribution_counts_on_dotcom = true
        assert_equal sync_date.to_i, DotcomUser.for(@user).last_contributions_sync.to_i
      end

      test "#show_enterprise_contribution_counts_on_dotcom=false clears sync date" do
        sync_date = Time.now - 1.week
        DotcomUser.create(user: @user, last_contributions_sync: sync_date)

        refute_nil DotcomUser.for(@user).last_contributions_sync
        @user.show_enterprise_contribution_counts_on_dotcom = false
        assert_nil DotcomUser.for(@user).last_contributions_sync
      end
    end
  end

  context "::users_consuming_seats" do
    test "returns all users consuming license seats" do
      another_user = create :user
      assert_same_elements [@user, another_user], User.users_consuming_seats
    end

    test "excludes User.ghost" do
      User.create_ghost
      another_user = create :user
      assert_same_elements [@user, another_user], User.users_consuming_seats
    end

    test "excludes User.staff_user" do
      staff_user = create :user, login: GitHub.staff_user_login
      another_user = create :user
      assert_same_elements [@user, another_user], User.users_consuming_seats
    end

    test "excludes User.actions_admin_user when actions is enabled" do
      GitHub.stubs(:actions_enabled?).returns(true)

      actions_admin_user = create :user, login: GitHub.actions_admin_login
      another_user = create :user

      actions_org = create :organization, admins: [actions_admin_user, another_user]
      GitHub.stubs(:actions_org).returns(actions_org)

      assert_same_elements [@user, another_user], User.users_consuming_seats
    end

    test "excludes suspended users" do
      another_user = create :user
      suspended_user = create :user
      suspended_user.suspend "Reasons"
      assert_same_elements [@user, another_user], User.users_consuming_seats
    end
  end

  context "::count_seats_used" do
    test "counts all users consuming license seats" do
      another_user = create :user
      assert_equal 2, User.count_seats_used
    end

    test "does not count User.ghost" do
      User.create_ghost
      another_user = create :user
      assert_equal 2, User.count_seats_used
    end

    test "does not count suspended users" do
      another_user = create :user
      suspended_user = create :user
      suspended_user.suspend "Reasons"
      assert_equal 2, User.count_seats_used
    end
  end
end
