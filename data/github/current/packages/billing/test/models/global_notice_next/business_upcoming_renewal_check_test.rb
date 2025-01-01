# typed: true
# frozen_string_literal: true

require "test_helper"

class GlobalNoticeNext::BusinessupcomingRenewalCheckTest < GitHub::TestCase
  fixtures do
    @user = create :user
    @business = create :business, customer: create(:customer, :zuora, :invoiced, term_length: 12), owners: [@user]
  end

  setup do
    GitHub.flipper[:ghe_sales_serve_renewals].enable(@business)
    # Eligibility check override
    GitHub.flipper[:sales_managed_subscription_self_serve_eligible_override].enable
  end

  context "#should_show_notice?" do
    test "returns true if the user has a business with upcoming renewal" do
      @business.customer.update(billing_end_date: GitHub::Billing.today + 1.week)
      check = GlobalNoticeNext::BusinessUpcomingRenewalCheck.new viewer: @user

      assert check.should_show_notice?
    end

    test "returns false if the user has a business without upcoming renewal" do
      @business.customer.update(billing_end_date: GitHub::Billing.today + 2.months)
      check = GlobalNoticeNext::BusinessUpcomingRenewalCheck.new viewer: @user

      refute check.should_show_notice?
    end

    test "returns false if the user only has business with pending renewal" do
      @business.customer.update(billing_end_date: GitHub::Billing.today + 1.week)
      # simulate the business going through renewal
      create(:sales_serve_subscription_change_request, customer: @business.customer, items: [
        create(:sales_serve_subscription_change_request_item, start_date: @business.billing_term_ends_on + 1.day, end_date: @business.billing_term_ends_on + 1.year),
      ])
      check = GlobalNoticeNext::BusinessUpcomingRenewalCheck.new viewer: @user

      refute check.should_show_notice?
    end

    test "returns false if the user has a business without self-serve eligible subscription" do
      GitHub.flipper[:sales_managed_subscription_self_serve_eligible_override].disable
      @business.customer.update(billing_end_date: GitHub::Billing.today + 1.week)
      check = GlobalNoticeNext::BusinessUpcomingRenewalCheck.new viewer: @user

      refute check.should_show_notice?
    end
  end
end if GitHub.billing_enabled?
