# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::SalesServeSubscriptionChangeRequestItemTest < GitHub::TestCase
  context "validations" do
    test "pass for default values" do
      item = build(:sales_serve_subscription_change_request_item)

      assert_predicate(item, :valid?)
    end

    test "status is required" do
      item = build(:sales_serve_subscription_change_request_item, status: nil)

      refute_predicate(item, :valid?)
      assert_equal ["can't be blank"], item.errors[:status]
    end

    test "product_rate_plan_charge_id is required" do
      item = build(:sales_serve_subscription_change_request_item, product_rate_plan_charge_id: nil)

      refute_predicate(item, :valid?)
      assert_equal ["can't be blank"], item.errors[:product_rate_plan_charge_id]
    end

    test "change_type is required" do
      item = build(:sales_serve_subscription_change_request_item, change_type: nil)

      refute_predicate(item, :valid?)
      assert_equal ["can't be blank"], item.errors[:change_type]
    end

    test "start_date is required" do
      item = build(:sales_serve_subscription_change_request_item, start_date: nil)

      refute_predicate(item, :valid?)
      assert_equal ["can't be blank"], item.errors[:start_date]
    end

    test "end_date is required" do
      item = build(:sales_serve_subscription_change_request_item, end_date: nil)

      refute_predicate(item, :valid?)
      assert_equal ["can't be blank"], item.errors[:end_date]
    end

    test "change_request is required" do
      item = build(:sales_serve_subscription_change_request_item, change_request: nil)

      refute_predicate(item, :valid?)
      assert_equal ["must exist"], item.errors[:change_request]
    end

    test "we allow removal of ghe seats within the renewal period" do
      business = create(:business, seats: 10)
      customer = create(:customer, :invoiced, business: business, billing_end_date: 20.days.from_now)
      change_request = create(:sales_serve_subscription_change_request, customer: customer)
      item = build(:sales_serve_subscription_change_request_item, :github_enterprise, change_request: change_request, quantity: 9)

      # Can remove seats
      assert item.valid?

      # Can keep the same number of seats
      item.quantity = 10
      assert item.valid?

      # Can add seats
      item.quantity = 11
      assert item.valid?
    end if GitHub.billing_enabled?

    test "we allow removal of ghas seats within the renewal period" do
      site_admin = create(:staff_admin_user)
      business = create(:business)
      customer = create(:customer, :invoiced, business: business, billing_end_date: 20.days.from_now)
      business.mark_advanced_security_as_purchased_for_entity(actor: site_admin, is_stafftools_action: true)
      business.set_advanced_security_seats_for_entity(seats: 10, actor: site_admin, is_stafftools_action: true)
      change_request = create(:sales_serve_subscription_change_request, customer: customer)
      item = build(:sales_serve_subscription_change_request_item, :github_advanced_security, change_request: change_request, quantity: 9)

      # Can remove seats
      assert item.valid?

      # Can keep the same number of seats
      item.quantity = 10
      assert item.valid?

      # Can add seats
      item.quantity = 11
      assert item.valid?
    end if GitHub.billing_enabled?

    test "we don't allow the removal of ghe seats outside the renewal period" do
      business = create(:business, seats: 10)
      customer = create(:customer, :invoiced, business: business, billing_end_date: 200.days.from_now)
      change_request = create(:sales_serve_subscription_change_request, customer: customer)
      item = build(:sales_serve_subscription_change_request_item, :github_enterprise, change_request: change_request, quantity: 9)

      # Can't remove seats
      refute_predicate(item, :valid?)
      assert_equal ["can't remove GHE seats outside of a renewal period"], item.errors[:quantity]

      # Can keep the same number of seats
      item.quantity = 10
      assert item.valid?

      # Can add seats
      item.quantity = 11
      assert item.valid?
    end if GitHub.billing_enabled?

    test "we don't allow the removal of ghas seats outside the renewal period" do
      site_admin = create(:staff_admin_user)
      business = create(:business, seats: 10)
      customer = create(:customer, :invoiced, business: business, billing_end_date: 200.days.from_now)
      business.mark_advanced_security_as_purchased_for_entity(actor: site_admin, is_stafftools_action: true)
      business.set_advanced_security_seats_for_entity(seats: 10, actor: site_admin, is_stafftools_action: true)
      product_uuid = create(:billing_product_uuid, :advanced_security)
      create(:billing_subscription_item, plan_subscription: business.plan_subscription, subscribable: product_uuid, quantity: 10, customer: business.customer)
      change_request = create(:sales_serve_subscription_change_request, customer: customer)
      item = build(:sales_serve_subscription_change_request_item, :github_advanced_security, change_request: change_request, quantity: 9)

      # Can't remove seats
      refute_predicate(item, :valid?)
      assert_equal ["can't remove GHAS seats outside of a renewal period"], item.errors[:quantity]

      # Can keep the same number of seats
      item.quantity = 10
      assert item.valid?

      # Can add seats
      item.quantity = 11
      assert item.valid?
    end if GitHub.billing_enabled?
  end

  test ".github_enterprise scope returns GitHub Enterprise items" do
    github_enterprise = create(:sales_serve_subscription_change_request_item, :github_enterprise)
    github_advanced_security = create(:sales_serve_subscription_change_request_item, :github_advanced_security)

    assert_includes Billing::SalesServeSubscriptionChangeRequestItem.github_enterprise, github_enterprise
    refute_includes Billing::SalesServeSubscriptionChangeRequestItem.github_enterprise, github_advanced_security
  end

  test ".github_advanced_security scope returns GitHub Advanced Security items" do
    github_enterprise = create(:sales_serve_subscription_change_request_item, :github_enterprise)
    github_advanced_security = create(:sales_serve_subscription_change_request_item, :github_advanced_security)

    assert_includes Billing::SalesServeSubscriptionChangeRequestItem.github_advanced_security, github_advanced_security
    refute_includes Billing::SalesServeSubscriptionChangeRequestItem.github_advanced_security, github_enterprise
  end

  test "updating the item updates the change request" do
    request = create(:sales_serve_subscription_change_request_with_items)
    assert_changes("request.reload.updated_at") do
      request.items.first.update!(status: :complete)
    end
  end

  context "#product" do
    test "returns GitHub Enterprise for GHE product_rate_plan_charge_id" do
      item = build(:sales_serve_subscription_change_request_item, product_rate_plan_charge_id: GitHub.zuora_sales_serve_ghe_product_charge_ids.first)

      assert_equal "GitHub Enterprise", item.product
    end

    test "returns GitHub Advanced Security for GHAS product_rate_plan_charge_id" do
      item = build(:sales_serve_subscription_change_request_item, product_rate_plan_charge_id: GitHub.zuora_sales_serve_ghas_product_charge_ids.first)

      assert_equal "GitHub Advanced Security", item.product
    end

    test "returns Unknown for other product_rate_plan_charge_id" do
      item = build(:sales_serve_subscription_change_request_item, product_rate_plan_charge_id: "test-product-rate-plan-charge-id")

      assert_equal "Unknown", item.product
    end
  end
end
