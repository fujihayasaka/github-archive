# typed: true
# frozen_string_literal: true

require "test_helper"

class Business::BillingContractUpdateDependencyTest < GitHub::TestCase
  include GitHub::SalesManagedSubscriptionTestHelper

  fixtures do
    @org1 = create :organization, plan: GitHub::Plan.business_plus, seats: 10
    @org2 = create :organization, plan: GitHub::Plan.business_plus, seats: 10
    @business = create(
      :business,
      billing_email: "veryimportant@example.com",
      organizations: [@org1, @org2])
  end

  context "self_renewal_eligible scope" do
    test "only includes invoiced businesses" do
      business_1 = create(:business, customer: create(:customer, :zuora, :invoiced, term_length: 12))
      business_2 = create(:business, customer: create(:customer, :zuora, term_length: 12))

      assert_includes Business.self_renewal_eligible, business_1
      refute_includes Business.self_renewal_eligible, business_2
    end

    test "only includes yearly term businesses" do
      business_1 = create(:business, customer: create(:customer, :zuora, :invoiced, term_length: 12))
      business_2 = create(:business, customer: create(:customer, :zuora, :invoiced, term_length: 1))

      assert_includes Business.self_renewal_eligible, business_1
      refute_includes Business.self_renewal_eligible, business_2
    end

    test "only includes businesses with zuora accounts" do
      business_1 = create(:business, customer: create(:customer, :zuora, :invoiced, term_length: 12))
      business_2 = create(:business, customer: create(:customer, :invoiced, term_length: 12))

      assert_includes Business.self_renewal_eligible, business_1
      refute_includes Business.self_renewal_eligible, business_2
    end

    test "only includes businesses that are not in a trial" do
      business_1 = create(:business, customer: create(:customer, :zuora, :invoiced, term_length: 12))
      business_2 = create(:business, trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now, customer: create(:customer, :zuora, :invoiced, term_length: 12))

      assert_includes Business.self_renewal_eligible, business_1
      refute_includes Business.self_renewal_eligible, business_2
    end
  end

  context "with_term_end_date scope" do
    test "only includes businesses with a term end date" do
      business_1 = create(:business, customer: create(:customer, billing_end_date: 10.days.from_now))
      business_2 = create(:business, customer: create(:customer, billing_end_date: 20.days.from_now))

      assert_includes Business.with_term_end_date(..15.days.from_now), business_1
      refute_includes Business.with_term_end_date(..15.days.from_now), business_2
    end
  end

  context "#sales_managed_subscription_self_serve_eligible?" do
    test "returns false if the business does not have a sales managed subscription" do
      GitHub.flipper[:sales_managed_subscription_self_serve_eligible_override].disable

      refute @business.sales_managed_subscription_self_serve_eligible?
    end

    test "returns false if the business does not have a self serve eligible subscription" do
      GitHub.flipper[:sales_managed_subscription_self_serve_eligible_override].disable
      @business.stubs(:sales_managed_subscription).returns(self_serve_ineligible_subscription)

      refute @business.sales_managed_subscription_self_serve_eligible?
    end

    test "returns true if the business has a self serve eligible subscription" do
      GitHub.flipper[:sales_managed_subscription_self_serve_eligible_override].disable
      @business.stubs(:sales_managed_subscription).returns(self_serve_eligible_subscription)

      assert @business.sales_managed_subscription_self_serve_eligible?
    end

    test "returns true if the business has the override feature enabled" do
      GitHub.flipper[:sales_managed_subscription_self_serve_eligible_override].enable(@business)

      assert @business.reload.sales_managed_subscription_self_serve_eligible?
    end
  end

  context "#in_lock_out_period?" do
    test "returns true if the renewal start date is within 7 days" do
      @business.billing_term_ends_at = GitHub::Billing.today + 7.days
      create(:sales_serve_subscription_change_request, customer: @business.customer, items: [
        create(:sales_serve_subscription_change_request_item, start_date: @business.billing_term_ends_on + 1.day, end_date: @business.billing_term_ends_on + 1.year),
      ])

      assert @business.in_lock_out_period?
    end

    test "returns false if the renewal start date is not within 7 days" do
      @business.billing_term_ends_at = GitHub::Billing.today + 8.days
      create(:sales_serve_subscription_change_request, customer: @business.customer, items: [
        create(:sales_serve_subscription_change_request_item, start_date: @business.billing_term_ends_on + 1.day, end_date: @business.billing_term_ends_on + 1.year),
      ])

      refute @business.in_lock_out_period?
    end

    test "returns true if the renewal start date is in the past and renewal is not successful" do
      @business.billing_term_ends_at = GitHub::Billing.today - 2.days
      create(:sales_serve_subscription_change_request, customer: @business.customer, items: [
        create(:sales_serve_subscription_change_request_item, start_date: @business.billing_term_ends_on + 1.day, end_date: @business.billing_term_ends_on + 1.year),
      ])

      assert @business.in_lock_out_period?
    end

    test "returns false if the renewal start date is in the past and renewal is successful" do
      @business.billing_term_ends_at = GitHub::Billing.today - 2.days
      create(:sales_serve_subscription_change_request, customer: @business.customer, items: [
        create(:sales_serve_subscription_change_request_item, start_date: @business.billing_term_ends_on + 1.day, end_date: @business.billing_term_ends_on + 1.year, status: :complete),
      ])

      refute @business.in_lock_out_period?
    end

    test "returns false if there is no renewal request" do
      @business.billing_term_ends_at = GitHub::Billing.today + 6.days
      create(:sales_serve_subscription_change_request, customer: @business.customer, items: [
        create(:sales_serve_subscription_change_request_item, change_type: :update, start_date: @business.billing_term_ends_on + 1.day, end_date: @business.billing_term_ends_on + 1.year),
      ])

      refute @business.in_lock_out_period?
    end
  end

  context "#eligible_for_renewal?" do
    test "returns true if the business is in the renewal window" do
      @business.billing_term_ends_at = GitHub::Billing.today + 4.weeks

      assert @business.eligible_for_renewal?
    end

    test "returns false if the business is not in the renewal window" do
      @business.billing_term_ends_at = GitHub::Billing.today + 4.months

      refute @business.eligible_for_renewal?
    end

    test "returns false if a renewal has already been requested" do
      @business.billing_term_ends_at = GitHub::Billing.today + 4.weeks
      create(:sales_serve_subscription_change_request, customer: @business.customer, items: [
        create(:sales_serve_subscription_change_request_item, start_date: @business.billing_term_ends_on + 1.day, end_date: @business.billing_term_ends_on + 1.year),
      ])

      refute @business.eligible_for_renewal?
    end
  end

  context "#eligible_for_update?" do
    test "returns false if expired" do
      GitHub.flipper[:ghe_sales_serve_upgrades].enable
      @business.billing_term_ends_at = 1.day.ago
      refute @business.eligible_for_upgrade?
    end

    test "returns false if in lock out period" do
      GitHub.flipper[:ghe_sales_serve_upgrades].enable
      @business.billing_term_ends_at = GitHub::Billing.today + 7.days
      create(:sales_serve_subscription_change_request, customer: @business.customer, items: [
        create(:sales_serve_subscription_change_request_item, start_date: @business.billing_term_ends_on + 1.day, end_date: @business.billing_term_ends_on + 1.year),
      ])
      refute @business.eligible_for_upgrade?
    end

    test "returns false if feature is not enabled" do
      GitHub.flipper[:ghe_sales_serve_upgrades].disable
      refute @business.eligible_for_upgrade?
    end

    test "returns true if outside renewal window" do
      GitHub.flipper[:ghe_sales_serve_upgrades].enable
      @business.billing_term_ends_at = GitHub::Billing.today + 4.months
      assert @business.eligible_for_upgrade?
    end

    context "within renewal window" do
      test "returns false if renewal not requested" do
        GitHub.flipper[:ghe_sales_serve_upgrades].enable
        @business.billing_term_ends_at = GitHub::Billing.today + 4.weeks
        refute @business.eligible_for_upgrade?
      end

      test "returns false if renewal does not have seat gap" do
        GitHub.flipper[:ghe_sales_serve_upgrades].enable
        @business.billing_term_ends_at = GitHub::Billing.today + 4.weeks
        create(:sales_serve_subscription_change_request, customer: @business.customer, items: [
          create(
            :sales_serve_subscription_change_request_item,
            :github_enterprise,
            start_date: @business.billing_term_ends_on + 1.day,
            end_date: @business.billing_term_ends_on + 1.year,
            quantity: 100,
            status: :complete,
            change_type: :renewal
          ),
        ])
        refute @business.eligible_for_upgrade?
      end

      test "returns true if renewal has seat gap" do
        GitHub.flipper[:ghe_sales_serve_upgrades].enable
        @business.billing_term_ends_at = GitHub::Billing.today + 4.weeks
        create(:sales_serve_subscription_change_request, customer: @business.customer, items: [
          create(
            :sales_serve_subscription_change_request_item,
            :github_enterprise,
            start_date: @business.billing_term_ends_on + 1.day,
            end_date: @business.billing_term_ends_on + 1.year,
            quantity: 101,
            status: :complete,
            change_type: :renewal
          ),
        ])
        assert @business.eligible_for_upgrade?
      end
    end
  end

  context "#in_renewal_window?" do
    test "returns false if the business is not invoiced" do
      @business.customer.update_attribute(:billing_type, Customer::BILLING_TYPE_CARD)
      @business.billing_term_ends_at = Time.current.beginning_of_day + 1.week
      refute @business.in_renewal_window?
    end

    test "returns true if the business is in the short renewal window" do
      @business.customer.update_attribute(:billing_type, Customer::BILLING_TYPE_INVOICE)
      @business.billing_term_ends_at = Time.current.beginning_of_day + 1.week
      assert @business.in_renewal_window?(short_window: true)
    end

    test "returns false if the business is not in the short renewal window" do
      @business.customer.update_attribute(:billing_type, Customer::BILLING_TYPE_INVOICE)
      @business.billing_term_ends_at = Time.current.beginning_of_day + 2.months
      refute @business.in_renewal_window?(short_window: true)
    end

    test "returns true if the business is in the long renewal window" do
      @business.customer.update_attribute(:billing_type, Customer::BILLING_TYPE_INVOICE)
      @business.billing_term_ends_at = Time.current.beginning_of_day + 2.months
      assert @business.in_renewal_window?(short_window: false)
    end

    test "returns false if the business is not in the long renewal window" do
      @business.customer.update_attribute(:billing_type, Customer::BILLING_TYPE_INVOICE)
      @business.billing_term_ends_at = Time.current.beginning_of_day + 4.months
      refute @business.in_renewal_window?(short_window: false)
    end

    test "returns true if the business is expired within a year" do
      @business.customer.update_attribute(:billing_type, Customer::BILLING_TYPE_INVOICE)
      @business.billing_term_ends_at = Time.current.beginning_of_day - 1.year + 1.day
      assert @business.in_renewal_window?
    end

    test "returns false if the business is expired more than a year" do
      @business.customer.update_attribute(:billing_type, Customer::BILLING_TYPE_INVOICE)
      @business.billing_term_ends_at = Time.current.beginning_of_day - 1.year - 1.day
      refute @business.in_renewal_window?
    end
  end

  context "#renewal_already_requested?" do
    test "returns true if a renewal has already been requested" do
      create(:sales_serve_subscription_change_request, customer: @business.customer, items: [
        create(:sales_serve_subscription_change_request_item, start_date: @business.billing_term_ends_on + 1.day, end_date: @business.billing_term_ends_on + 1.year),
      ])

      assert @business.renewal_already_requested?
    end

    test "returns false if a renewal has not been requested" do
      refute @business.renewal_already_requested?
    end
  end

  context "#has_contract_change?" do
    test "returns true if a request has been made within the window" do
      travel_to(3.months.ago) do
        create(:sales_serve_subscription_change_request_with_items, customer: @business.customer)
      end

      assert_predicate @business, :has_contract_change?
    end

    test "returns false if a request has not been made outside the window" do
      travel_to(5.months.ago) do
        create(:sales_serve_subscription_change_request_with_items, customer: @business.customer)
      end

      refute_predicate @business, :has_contract_change?
    end
  end

  context "#has_any_failed_ghas_change_requests?" do
    test "returns true if there is a failed ghas update request" do
      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, status: :pending, change_type: :update)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete, change_type: :update)
      request.items << create(:sales_serve_subscription_change_request_item, :github_advanced_security, status: :error, change_type: :update)

      assert_predicate @business, :has_any_failed_ghas_change_requests?
    end

    test "returns true if there is a failed ghas renewal request" do
      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, status: :pending, change_type: :renewal)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete, change_type: :renewal)
      request.items << create(:sales_serve_subscription_change_request_item, :github_advanced_security, status: :error, change_type: :renewal)

      assert_predicate @business, :has_any_failed_ghas_change_requests?
    end

    test "returns false if there is no failed ghas requests" do
      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, status: :pending, change_type: :update)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete, change_type: :update)
      request.items << create(:sales_serve_subscription_change_request_item, status: :pending, change_type: :renewal)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete, change_type: :renewal)
      request.items << create(:sales_serve_subscription_change_request_item, :github_enterprise, status: :error, change_type: :renewal)
      request.items << create(:sales_serve_subscription_change_request_item, :github_enterprise, status: :error, change_type: :update)

      refute_predicate @business, :has_any_failed_ghas_change_requests?
    end
  end

  context "#has_any_failed_change_requests?" do
    test "returns true if there is a failed update request" do
      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, status: :pending, change_type: :update)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete, change_type: :update)
      request.items << create(:sales_serve_subscription_change_request_item, status: :error, change_type: :update)

      assert_predicate @business, :has_any_failed_change_requests?
    end

    test "returns true if there is a failed renewal request" do
      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, status: :pending, change_type: :renewal)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete, change_type: :renewal)
      request.items << create(:sales_serve_subscription_change_request_item, status: :error, change_type: :renewal)

      assert_predicate @business, :has_any_failed_change_requests?
    end

    test "returns false if there is no failed request" do
      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, status: :pending, change_type: :update)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete, change_type: :update)
      request.items << create(:sales_serve_subscription_change_request_item, status: :pending, change_type: :renewal)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete, change_type: :renewal)

      refute_predicate @business, :has_any_failed_change_requests?
    end
  end

  context "#has_any_pending_change_requests?" do
    test "returns true if there is a pending update request" do
      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, status: :pending, change_type: :update)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete, change_type: :update)
      request.items << create(:sales_serve_subscription_change_request_item, status: :error, change_type: :update)

      assert_predicate @business, :has_any_pending_change_requests?
    end

    test "returns true if there is a pending renewal request" do
      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, status: :pending, change_type: :renewal)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete, change_type: :renewal)
      request.items << create(:sales_serve_subscription_change_request_item, status: :error, change_type: :renewal)

      assert_predicate @business, :has_any_pending_change_requests?
    end

    test "returns false if there is no pending request" do
      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete, change_type: :update)
      request.items << create(:sales_serve_subscription_change_request_item, status: :error, change_type: :update)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete, change_type: :renewal)
      request.items << create(:sales_serve_subscription_change_request_item, status: :error, change_type: :renewal)

      refute_predicate @business, :has_any_pending_change_requests?
    end
  end

  context "#renewal_successful?" do
    test "returns true if the renewal request has all items complete" do
      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete, change_type: :renewal)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete, change_type: :update)

      assert_predicate @business, :renewal_successful?
    end

    test "should only consider renewal request" do
      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, status: :error, change_type: :update)

      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete, change_type: :renewal)

      assert_predicate @business, :renewal_successful?
    end

    test "returns false if one of the item is error" do
      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, status: :error, change_type: :renewal)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete, change_type: :renewal)

      refute_predicate @business, :renewal_successful?
    end

    test "returns false if one of the item is pending" do
      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, status: :pending, change_type: :renewal)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete, change_type: :renewal)

      refute_predicate @business, :renewal_successful?
    end

    test "returns false if there is no renewal request" do
      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete, change_type: :update)

      refute_predicate @business, :renewal_successful?
    end
  end

  context "#ghe_renewal_seat_quantity_difference" do
    test "returns the difference between the current quantity and the update request quantity" do
      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, :github_advanced_security, quantity: 170, status: :complete, change_type: :update)
      request.items << create(:sales_serve_subscription_change_request_item, :github_advanced_security, quantity: 200, status: :complete, change_type: :renewal)
      request.items << create(:sales_serve_subscription_change_request_item, :github_enterprise, quantity: 150, status: :complete, change_type: :update)
      request.items << create(:sales_serve_subscription_change_request_item, :github_enterprise, quantity: 200, status: :complete, change_type: :renewal)

      assert_equal 100, @business.ghe_renewal_seat_quantity_difference
    end
  end

  context "#ghas_update_seat_quantity_difference" do
    test "returns the difference between the current quantity and the update request quantity" do
      @business.mark_advanced_security_as_metered_for_entity(actor: User.ghost)
      @business.set_advanced_security_seats_for_entity(seats: 150, actor: User.ghost)
      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, :github_advanced_security, quantity: 200, status: :complete, change_type: :renewal)
      request.items << create(:sales_serve_subscription_change_request_item, :github_advanced_security, quantity: 170, status: :complete, change_type: :update)
      request.items << create(:sales_serve_subscription_change_request_item, :github_enterprise, quantity: 200, status: :complete, change_type: :renewal)
      request.items << create(:sales_serve_subscription_change_request_item, :github_enterprise, quantity: 150, status: :complete, change_type: :update)

      assert_equal 20, @business.ghas_update_seat_quantity_difference
    end
  end

  context "#ghas_renewal_seat_quantity_difference" do
    test "returns the difference between the current quantity and the renewal request quantity" do
      @business.mark_advanced_security_as_metered_for_entity(actor: User.ghost)
      @business.set_advanced_security_seats_for_entity(seats: 150, actor: User.ghost)
      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, :github_advanced_security, quantity: 170, status: :complete, change_type: :update)
      request.items << create(:sales_serve_subscription_change_request_item, :github_advanced_security, quantity: 200, status: :complete, change_type: :renewal)
      request.items << create(:sales_serve_subscription_change_request_item, :github_enterprise, quantity: 150, status: :complete, change_type: :update)
      request.items << create(:sales_serve_subscription_change_request_item, :github_enterprise, quantity: 200, status: :complete, change_type: :renewal)

      assert_equal 50, @business.ghas_renewal_seat_quantity_difference
    end
  end

  context "#renewal_has_seat_gap?" do
    test "returns false if there is an update request" do
      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, :github_enterprise, status: :complete, change_type: :update)
      request.items << create(:sales_serve_subscription_change_request_item, :github_enterprise, status: :complete, change_type: :renewal)

      refute_predicate @business, :renewal_has_seat_gap?
    end

    test "returns false if there is no renewal request" do
      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, :github_enterprise, status: :complete, change_type: :update)

      refute_predicate @business, :renewal_has_seat_gap?
    end

    test "returns false if the renewal quantity is the same as the current quantity" do
      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, :github_enterprise, quantity: 100, status: :complete, change_type: :renewal)

      refute_predicate @business, :renewal_has_seat_gap?
    end

    test "returns true if the renewal quantity is greater than the current quantity" do
      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, :github_enterprise, quantity: 101, status: :complete, change_type: :renewal)

      assert_predicate @business, :renewal_has_seat_gap?
    end
  end

  context "#renewal_scheduled_start_datetime" do
    test "returns the start date of the renewal request" do
      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, change_type: :renewal)

      assert_equal request.items.change_type_renewal.first.start_date, @business.renewal_scheduled_start_datetime
    end

    test "returns nil if no renewal request exists" do
      assert_nil @business.renewal_scheduled_start_datetime
    end
  end

  context "#update_successful?" do
    test "returns false if there is no update request" do
      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete, change_type: :renewal)

      refute_predicate @business, :update_successful?
    end

    test "returns true if all items in the update request are complete" do
      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, status: :error, change_type: :renewal)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete, change_type: :update)

      assert_predicate @business, :update_successful?
    end

    test "returns false if one of the items in the update request is pending" do
      request = create(:sales_serve_subscription_change_request, customer: @business.customer)
      request.items << create(:sales_serve_subscription_change_request_item, status: :pending, change_type: :update)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete, change_type: :update)

      refute_predicate @business, :update_successful?
    end
  end

  context "#has_change_request_update_newer_than?" do
    test "returns true if there is a change request newer than the given timestamp" do
      request = create(:sales_serve_subscription_change_request_with_items, customer: @business.customer)

      assert @business.has_change_request_update_newer_than?(2.days.ago)
    end

    test "returns true if any of the change requests are newer than the given timestamp" do
      travel_to(3.days.ago) do
        request = create(:sales_serve_subscription_change_request_with_items, customer: @business.customer)
      end
      request = create(:sales_serve_subscription_change_request_with_items, customer: @business.customer)

      assert @business.has_change_request_update_newer_than?(2.days.ago)
    end

    test "returns false if there is no change request newer than the given timestamp" do
      travel_to(3.days.ago) do
        request = create(:sales_serve_subscription_change_request_with_items, customer: @business.customer)
      end

      refute @business.has_change_request_update_newer_than?(2.days.ago)
    end
  end
end if GitHub.billing_enabled?
