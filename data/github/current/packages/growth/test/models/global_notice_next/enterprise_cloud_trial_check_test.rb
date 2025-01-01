# typed: true
# frozen_string_literal: true

require "test_helper"

unless GitHub.enterprise?
  class GlobalNoticeNext::EnterpriseCloudTrialCheckTest < GitHub::TestCase
    fixtures do
      @user         = create(:user)
      @organization = create(:organization, admin: @user, plan: :free)
    end

    context "#should_show_notice?" do
      test "returns true if user has an organization with a recent ghec trial" do
        pending_plan_change = create(:billing_pending_plan_change, active_on: 3.days.from_now)
        create(:billing_plan_trial, :active, user: @organization, pending_plan_change: pending_plan_change)

        check = GlobalNoticeNext::EnterpriseCloudTrialCheck.new(viewer: @user)

        assert check.should_show_notice?
      end

      test "returns true if user has an organization with a recent business trial" do
        business = create(:business, trial_expires_at: 3.days.from_now)
        business_org = create(:organization, business: business)
        business_org.add_admin(@user)

        check = GlobalNoticeNext::EnterpriseCloudTrialCheck.new(viewer: @user)

        assert check.should_show_notice?
      end

      test "returns true if trial is expired" do
        business = create(:business, trial_expires_at: 15.days.ago)
        business_org = create(:organization, business: business)
        business_org.add_admin(@user)

        check = GlobalNoticeNext::EnterpriseCloudTrialCheck.new(viewer: @user)

        assert check.should_show_notice?
      end

      test "returns false if user has no organization with recent trial" do
        check = GlobalNoticeNext::SpammyCheck.new(viewer: @user)

        refute check.should_show_notice?
      end
    end
  end
end
