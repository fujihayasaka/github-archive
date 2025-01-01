# typed: true
# frozen_string_literal: true

require "test_helper"

class UserStaffTwoFactorNoticeTest < GitHub::TestCase
  context "check_staff_has_two_factor_enabled notice" do
    test "is not set when user is created as non-admin" do
      set_two_factor_required_to true do
        user = create :user

        refute user.site_admin_without_two_factor_check?
        refute user.site_admin?

        assert_nil GlobalNoticeNext.new(viewer: user).current_notice_name
      end
    end

    test "is set when user is created as admin with no two-factor" do
      set_two_factor_required_to true do
        user = create :user
        add_as_employee(user)
        user.change_role "staff", "testing", :site_admin_test

        assert user.site_admin_without_two_factor_check?
        refute user.site_admin?

        assert_nil user.two_factor_credential
        assert_equal :check_staff_has_two_factor_enabled, GlobalNoticeNext.new(viewer: user).current_notice_name
      end
    end

    test "is set when staff user deletes 2fa credential" do
      set_two_factor_required_to true do
        user = create :user, :verified
        add_as_employee(user)
        cred, _ = make_two_factor_credential(user)
        user.change_role "staff", "testing", :site_admin_test

        assert user.site_admin_without_two_factor_check?
        assert user.site_admin?

        # Reload stuff
        cred.destroy!
        user.reload
        GlobalNoticeNext.new(viewer: user).refresh

        assert user.site_admin_without_two_factor_check?
        refute user.site_admin?

        assert_nil user.two_factor_credential
        assert_equal :check_staff_has_two_factor_enabled, GlobalNoticeNext.new(viewer: user).current_notice_name
      end
    end

    test "is not set when staff user restores 2fa credential" do
      set_two_factor_required_to true do
        user = create :user, :verified
        add_as_employee(user)
        cred, new_cred = make_two_factor_credential(user)
        cred.recovery_codes_viewed!
        user.change_role "staff", "testing", :site_admin_test

        assert user.site_admin_without_two_factor_check?
        assert user.site_admin?

        # Reload stuff
        cred.destroy!
        new_cred.destroy! if new_cred
        user.reload
        GlobalNoticeNext.new(viewer: user).refresh

        cred, new_cred = make_two_factor_credential(user)
        cred.recovery_codes_viewed!
        GlobalNoticeNext.new(viewer: user).refresh

        assert user.site_admin_without_two_factor_check?
        assert user.site_admin?

        refute_nil user.two_factor_credential
        refute_equal :check_staff_has_two_factor_enabled, GlobalNoticeNext.new(viewer: user).current_notice_name
      end
    end

    test "is not set when user is created as admin with two-factor" do
      set_two_factor_required_to true do
        user = create :staff_admin_user, :verified
        cred, _ = make_two_factor_credential(user)
        cred.recovery_codes_viewed!
        user.reload

        assert user.site_admin_without_two_factor_check?
        assert user.site_admin?

        # GNN will have cached the set_notice triggered above, we need to refresh that cache.
        # It's also cached in the GNN instance, so we create a separate instance later when we assert it for nil.
        GlobalNoticeNext.new(viewer: user).refresh

        refute_nil user.two_factor_credential
        refute_equal :check_staff_has_two_factor_enabled, GlobalNoticeNext.new(viewer: user).current_notice_name
      end
    end

    test "is not set when admins aren't required to have two-factor enabled" do
      set_two_factor_required_to false do
        user = create :staff_admin_user

        assert user.site_admin_without_two_factor_check?
        assert user.site_admin?

        assert_nil user.two_factor_credential
        refute_equal :check_staff_has_two_factor_enabled, GlobalNoticeNext.new(viewer: user).current_notice_name
      end
    end
  end

  def set_two_factor_required_to(value, &block)
    original_value = GitHub.require_two_factor_for_site_admin?
    GitHub.require_two_factor_for_site_admin = value
    yield
  ensure
    GitHub.require_two_factor_for_site_admin = original_value
  end
end
