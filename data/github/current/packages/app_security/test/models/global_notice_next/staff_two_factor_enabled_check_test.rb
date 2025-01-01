# typed: true
# frozen_string_literal: true

require "test_helper"

class GlobalNoticeNext::StaffTwoFactorEnabledTest < GitHub::TestCase
  fixtures do
    @user = create(:user, :verified)
    @site_admin = create(:user, :staff)
  end

  context "#should_show_notice?" do
    context "when require two factor for site admin is true" do
      test "returns true if user is staff and has not enabled two factor" do
        set_two_factor_required_to true do
          check = GlobalNoticeNext::StaffTwoFactorEnabledCheck.new(viewer: @site_admin)

          assert check.should_show_notice?
        end
      end

      test "returns false if user is staff and has enabled two factor" do
        set_two_factor_required_to true do
          @site_admin.two_factor_credential = create(:two_factor_credential)

          check = GlobalNoticeNext::StaffTwoFactorEnabledCheck.new(viewer: @site_admin.reload)

          refute check.should_show_notice?
        end
      end
    end

    context "when require two factor for site admin is false" do
      test "returns true if user is staff and has not enabled two factor" do
        set_two_factor_required_to false do
          check = GlobalNoticeNext::StaffTwoFactorEnabledCheck.new(viewer: @site_admin)

          refute check.should_show_notice?
        end
      end
    end

    test "returns false if user is not staff" do
      check = GlobalNoticeNext::StaffTwoFactorEnabledCheck.new(viewer: @user)

      refute check.should_show_notice?
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
