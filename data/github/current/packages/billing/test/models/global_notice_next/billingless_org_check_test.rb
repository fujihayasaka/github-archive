# typed: true
# frozen_string_literal: true

require "test_helper"

class GlobalNoticeNext::BillinglessOrgCheckTest < GitHub::TestCase
  fixtures do
    @user = create(:user, :verified, plan: "small")
  end

  context "#should_show_notice?" do
    test "returns true if a user has a billingless org" do
      org = create :organization, admin: @user, plan: "bronze"
      org.update_column :organization_billing_email, ""

      check = GlobalNoticeNext::BillinglessOrgCheck.new(viewer: @user)

      assert check.should_show_notice?
    end

    test "returns false if user does not have a billingless org" do
      check = GlobalNoticeNext::BillinglessOrgCheck.new(viewer: @user)

      refute check.should_show_notice?
    end
  end
end
