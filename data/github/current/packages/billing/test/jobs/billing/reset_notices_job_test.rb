# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::ResetNoticesJobTest < GitHub::TestCase
  fixtures do
    @notice = "depleted_prepaid_credits"
    @business = create(:business)
    @business_owner = @business.owners.first

    @organization = create(:organization)
    @org_admin = @organization.admins.first
  end

  context "business" do
    test "resets notice of owners" do
      @business_owner.dismiss_business_notice(@notice, business_id: @business.id)

      Billing::ResetNoticesJob.new(@notice, @business).perform_now

      refute @business_owner.dismissed_business_notice?(@notice, business_id: @business.id)
    end

    test "resets notice of billing managers" do
      billing_manager = create(:user)
      @business.billing.add_manager(billing_manager, actor: @business_owner)
      billing_manager.dismiss_business_notice(@notice, business_id: @business.id)
      @business.reload

      Billing::ResetNoticesJob.new(@notice, @business).perform_now

      refute billing_manager.dismissed_business_notice?(@notice, business_id: @business.id)
    end
  end

  context "organization" do
    test "resets notice of admins" do
      @org_admin.dismiss_organization_notice(@notice, @organization)

      Billing::ResetNoticesJob.new(@notice, @organization).perform_now

      refute @org_admin.dismissed_organization_notice?(@notice, @organization)
    end

    test "resets notice of billing managers" do
      billing_manager = create(:user)
      @organization.billing.add_manager(billing_manager, actor: @org_admin)
      billing_manager.dismiss_organization_notice(@notice, @organization)

      Billing::ResetNoticesJob.new(@notice, @organization).perform_now

      refute billing_manager.dismissed_organization_notice?(@notice, @organization)
    end
  end
end if GitHub.billing_enabled?
