# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessBillingDependencyTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include GitHub::LoggerHelper
  include GitHub::ZuoraTestHelper
  include HydroTestHelpers
  include DogstatsTestHelpers

  fixtures do
    @org1 = create :organization, plan: GitHub::Plan.business_plus, seats: 10
    @org2 = create :organization, plan: GitHub::Plan.business_plus, seats: 10
    @business = create(
      :business,
      :with_valid_contact_for_billing,
      billing_email: "veryimportant@example.com",
      organizations: [@org1, @org2])
    @org = create(:organization)
    @org_member_one = create :user
    @org.add_member @org_member_one
    @org_member_two = create :user
    @org.add_member @org_member_two

    if GitHub.billing_enabled?
      @business_with_azure_subscription = create(:business, :with_azure_subscription)
      @business_metered_trial = create(:business, :with_valid_contact_for_billing, :with_azure_subscription)
      @business_metered_trial.customer.update!(metered_ghe: true, billing_type: Customer::BILLING_TYPE_CARD)
      @business_metered_trial.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
      @business_trial_with_credit_card = create(:business, :with_self_serve_payment, trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now)
      @business_trial_with_credit_card.customer.update!(metered_ghe: true, billing_type: Customer::BILLING_TYPE_CARD)
      @business_with_self_serve_payment = create(:business, :with_valid_contact_for_billing, :with_self_serve_payment)
      @advanced_security_product_uuid = create(:billing_product_uuid, :advanced_security)
      @owner = create :user, login: "owner"
      @upgrading_org = create :organization, name: "upgrading-org", admins: [@owner]
      @business_to_upgrade = create :business, :with_valid_contact_for_billing, name: "Business to upgrade", owners: [@owner]
      @business_to_create_from_coupon = create :business, :with_valid_contact_for_billing, name: "Business to create from coupon", owners: [@owner]
      @org_plan_subscription = create :billing_plan_subscription, user: @org
      @listing_plan = create :marketplace_listing_plan, :verified_listing
      @coupon = create :coupon, discount: 0.1, plan: "business_plus", group: "microsoft", code: "real-ghec-coupon"
    end
  end

  setup do
    if GitHub.billing_enabled?
      GitHub::Experiment.raise_on_mismatches = false
      @business_to_create_from_coupon.customer.update_attribute(:billing_type, "card")
      @business_to_create_from_coupon.initiate_creation_from_coupon
      @business_to_create_from_coupon.upgrade_initiated_from_organization = @org
      @business_to_upgrade.initiate_organization_upgrade
    end
  end

  context ".needs_billed" do
    if GitHub.billing_enabled?
      test "does not pick up businesses with a trial expiration date" do
        assert_difference "Business.needs_billed.size", 1 do
          business = create(:business, :with_self_serve_payment)
          business.customer.update!(billing_end_date: nil)
        end

        assert_no_difference "Business.needs_billed.size" do
          business = create(:business, :with_self_serve_payment, :in_trial)
          business.customer.update!(billing_end_date: nil)
        end
      end
    end
  end

  context "#billing_term_expired?" do
    test "returns true if the billing_term_ends_at is in the past" do
      @business.billing_term_ends_at = GitHub::Billing.today - 2.days
      assert @business.billing_term_expired?
    end

    test "returns false if the billing_term_ends_at is in the future" do
      @business.billing_term_ends_at = GitHub::Billing.today + 2.days
      refute @business.billing_term_expired?
    end

    test "returns false if the billing_term_ends_at is today" do
      @business.billing_term_ends_at = GitHub::Billing.today
      refute @business.billing_term_expired?
    end

    test "returns false if the billing_term_ends_at is nil" do
      @business.billing_term_ends_at = nil
      refute @business.billing_term_expired?
    end
  end

  context "#billing_term_ends_at=" do
    test "accepts empty values" do
      @business.billing_term_ends_at = nil
      assert_nil @business.billing_term_ends_on
      @business.billing_term_ends_at = ""
      assert_nil @business.billing_term_ends_on
    end

    test "accepts a parseable String" do
      @business.billing_term_ends_at = "2015-01-01"
      assert_equal Date.new(2015, 1, 1).to_time(:utc), @business.billing_term_ends_on
    end

    test "gracefully handles invalid String" do
      @business.billing_term_ends_at = "foobar"
      assert_nil @business.billing_term_ends_at
    end

    test "accepts a Date" do
      date = Date.new(2015, 1, 1)
      @business.billing_term_ends_at = date
      assert_equal date.to_time(:utc), @business.billing_term_ends_on
    end

    test "accepts a DateTime" do
      time = Date.new(2015, 1, 1).to_time(:utc)
      @business.billing_term_ends_at = time
      assert_equal time, @business.billing_term_ends_on
    end

    test "also sets customer.billing_end_date" do
      time = Date.new(2015, 1, 1).to_time(:utc)

      @business.billing_term_ends_at = time
      assert_equal time, @business.customer.billing_end_date
      assert @business.customer.valid?
    end

    test_zones = %w[America/Vancouver UTC Asia/Tokyo].map do |name|
      ActiveSupport::TimeZone[name]
    end
    test_zones.each do |zone|
      test_zones.each do |viewer_zone|
        test "returns a consistent #billing_term_ends_on when set in #{zone} and viewed in #{viewer_zone}" do
          date = Date.new(2014, 12, 4)
          Time.use_zone(zone) do
            Timecop.freeze Time.local(2014, 12, 1) do
              @business.billing_term_ends_at = date.beginning_of_day
            end
          end
          Time.use_zone(viewer_zone) do
            Timecop.freeze Time.local(2014, 12, 1) do
              assert_equal date, @business.billing_term_ends_on,
                "Midnight in #{viewer_zone} is #{date.beginning_of_day.utc}\nLocal Time is #{Time.current}"
            end
          end
        end
      end
    end
  end if GitHub.billing_enabled?

  context "#successful_paid_payments?" do
    test "returns false for users with no successful paid transactions" do
      create(:billing_transaction, :failed, amount_in_cents: 4, customer: @business.customer)
      create(:billing_transaction, amount_in_cents: 0, customer: @business.customer)

      refute @business.successful_paid_payments?
    end

    test "returns true for users with the minimum count of successful paid transactions" do
      create(:billing_transaction, amount_in_cents: 4, customer: @business.customer)
      assert @business.successful_paid_payments?
      refute @business.successful_paid_payments?(minimum_payment_count: 2)

      create(:billing_transaction, amount_in_cents: 4, customer: @business.customer)
      assert @business.successful_paid_payments?(minimum_payment_count: 2)
      refute @business.successful_paid_payments?(minimum_payment_count: 3)

      create(:billing_transaction, amount_in_cents: 4, customer: @business.customer)
      assert @business.successful_paid_payments?(minimum_payment_count: 3)
      refute @business.successful_paid_payments?(minimum_payment_count: 4)
    end

    test "returns true for users with successful paid transactions after the start date" do
      create(:billing_transaction, amount_in_cents: 4, customer: @business.customer, created_at: GitHub::Billing.today)

      assert @business.successful_paid_payments?(start_date: GitHub::Billing.today - 1.day)
      refute @business.successful_paid_payments?(start_date: GitHub::Billing.today + 1.day)
    end
  end

  context "#invoiced?" do
    if GitHub.single_business_environment?
      test "false in single business environment" do
        @business.customer.update_attribute(:billing_type, "invoice")
        refute_predicate @business, :invoiced?
      end
    else
      test "true when not in single business environment" do
        @business.customer.update_attribute(:billing_type, "invoice")
        assert_predicate @business, :invoiced?
      end
    end
  end

  context "#plan" do
    if GitHub.enterprise?
      test "the default plan is returned" do
        assert_equal @business.plan, GitHub::Plan.default_plan
      end
    else
      test "the business_plus plan is returned" do
        assert_equal @business.plan, GitHub::Plan.business_plus
      end
    end
  end

  context "#plan_supports?" do
    test "delegates to plan and defaults org to false" do
      plan = @business.plan
      plan.expects(:supports?).with(:foo, visibility: nil, feature_flag: nil, org: false).returns(true)

      assert @business.plan_supports?(:foo, org: true)
    end
  end

  context "on_paid_plan scope" do
    if GitHub.single_business_environment?
      test "returns no results if the single business is not on a paid plan" do
        refute_predicate GitHub.global_business.plan, :paid?, "need a global business on a free plan"
        assert_empty Business.on_paid_plan
      end
    else
      test "includes businesses on a paid plan" do
        free_business = create(:business)
        free_business.downgrade_to_free_plan
        assert_predicate free_business, :downgraded_to_free_plan?, "need a business that has moved to a free plan"
        business_ids = [@business, @business_with_azure_subscription, @business_with_self_serve_payment,
          free_business].map(&:id)

        result = Business.on_paid_plan.where(id: business_ids)

        assert_includes result, @business
        assert_includes result, @business_with_azure_subscription
        assert_includes result, @business_with_self_serve_payment
        refute_includes result, free_business
        assert result.map(&:plan).all?(&:paid?), "expected only businesses on a paid plan to be returned"
      end
    end
  end

  context "#can_self_serve?" do
    if GitHub.single_business_environment?
      test "returns false in single business environment" do
        refute @business.can_self_serve?
      end
    else
      test "returns true in multi business environment if enabled" do
        assert @business.can_self_serve?
      end
      test "returns false in multi business environment if disabled" do
        @business.can_self_serve = false
        @business.save!
        refute @business.reload.can_self_serve?
      end
    end
  end

  context "#self_serve_payment?" do
    if GitHub.billing_enabled?
      test "returns true if billing_type is card" do
        @business.customer.update_attribute(:billing_type, "card")

        assert_equal "card", @business.customer.billing_type
        assert_predicate @business, :self_serve_payment?
      end

      test "returns false if billing_type is invoice" do
        @business.customer.update_attribute(:billing_type, "invoice")

        assert_equal "invoice", @business.customer.billing_type
        refute_predicate @business, :self_serve_payment?
      end

      test "returns false if billing_type is not set" do
        @business.customer.update_attribute(:billing_type, nil)

        assert_nil @business.customer.billing_type
        refute_predicate @business, :self_serve_payment?
      end
    else
      test "returns false for environment where billing is disabled" do
        @business.customer.update_attribute(:billing_type, "card")

        refute_predicate @business, :self_serve_payment?
      end
    end
  end

  context "#sales_managed?" do
    if GitHub.billing_enabled?
      test "returns false if billing_type is card" do
        @business.customer.update! billing_type: Customer::BILLING_TYPE_CARD

        refute_predicate @business, :sales_managed?
      end

      test "returns true if billing_type is invoice" do
        @business.customer.update! billing_type: Customer::BILLING_TYPE_INVOICE

        assert_predicate @business, :sales_managed?
      end

      test "returns false if billing_type is not set" do
        @business.customer.update! billing_type: nil

        refute_predicate @business, :sales_managed?
      end
    else
      test "returns false for environment where billing is disabled" do
        refute_predicate @business, :sales_managed?
      end
    end
  end

  context "#enable_self_serve_payments" do
    if GitHub.billing_enabled?
      test "does not update billing type if there are trade restrictions" do
        enable_feature_flag(:live_sdn_screening, @business)
        @business.trade_screening_record.true_match!
        assert_equal Customer::BILLING_TYPE_INVOICE, @business.billing_type

        @business.enable_self_serve_payments
        refute_equal Customer::BILLING_TYPE_CARD, @business.reload.billing_type
      end

      test "updates billing type to card" do
        @business.enable_self_serve_payments
        assert_equal "card", @business.reload.customer.billing_type
      end

      test "updates plan duration to yearly when no plan duration specified" do
        @business.enable_self_serve_payments
        assert_predicate @business, :yearly_plan?
      end

      test "updates plan duration to yearly when yearly plan duration specified" do
        @business.enable_self_serve_payments(plan_duration: "year")
        assert_predicate @business, :yearly_plan?
      end

      test "updates plan duration to monthly when monthly plan duration specified" do
        @business.enable_self_serve_payments(plan_duration: "month")
        assert_predicate @business, :monthly_plan?
      end

      test "creates a customer and plan_subscription and synchronizes with zuora" do
        business = create(:business, customer: create(:customer, :invoiced))
        synchronize_github_products_to_zuora

        assert_nil business.customer.zuora_account_id
        assert_nil business.reload.plan_subscription
        only = [CheckForSpamJob, SynchronizePlanSubscriptionJob, UpdateLockedRepositoriesJob]
        perform_enqueued_jobs(only: only) do
          with_live_zuora("zuora_subscription/success_create_enterprise_customer_and_separate_subscription") do
            business.enable_self_serve_payments
            business.reload
            refute_nil business.customer.zuora_account_id
            zuora_basic_info = business.customer.zuora_account.body["basicInfo"]
            zuora_billing_and_payment = business.customer.zuora_account.body["billingAndPayment"]
            communication_profile_id = GitHub.zuora_self_serve_communication_profile_id
            assert_equal "Self-Serve", zuora_basic_info["BusinessSegment__c"]
            assert_equal "Batch10", zuora_basic_info["batch"]
            assert_equal "No", zuora_basic_info["SynctoNetSuite__NS"]
            assert_equal 0, zuora_billing_and_payment["billCycleDay"]
            assert_equal communication_profile_id, zuora_basic_info["communicationProfileId"]
            assert_equal "USD", zuora_billing_and_payment["currency"]
            assert_equal "Stripe v3", zuora_billing_and_payment["paymentGateway"]
            assert business.plan_subscription.present?
            unless GitHub.flipper[:billing_contact_required_to_create_subscription].enabled?
              assert business.plan_subscription.zuora_subscription.present?
              zuora_subscription = business.plan_subscription.zuora_subscription
              assert_equal 7, zuora_subscription.active_rate_plans.count
              business_rate_plans = zuora_subscription.active_rate_plans.map { |p| p[:productName].to_s.downcase }
              assert_includes business_rate_plans, GitHub::Plan.business_plus(account: business).zuora_product_name.downcase
            end
          end
        end
      end

      test "creates new zuora account and associates it with the converted self-serve enterprise's customer and plan_subscription" do
        original_zuora_account = @business.customer.zuora_account
        synchronize_github_products_to_zuora

        zuora_successful_customer_account_creation(@business)
        refute_nil @business.customer.zuora_account.id
        assert_nil @business.reload.plan_subscription

        only = [CheckForSpamJob, SynchronizePlanSubscriptionJob, UpdateLockedRepositoriesJob]
        perform_enqueued_jobs(only: only) do
          with_live_zuora("zuora_subscription/success_create_enterprise_subscription_for_existing_separate_zuora_account") do
            @business.enable_self_serve_payments
            @business.reload
            zuora_basic_info = @business.customer.zuora_account.body["basicInfo"]
            zuora_billing_and_payment = @business.customer.zuora_account.body["billingAndPayment"]
            communication_profile_id = GitHub.zuora_self_serve_communication_profile_id
            assert_equal "Self-Serve", zuora_basic_info["BusinessSegment__c"]
            assert_equal "Batch10", zuora_basic_info["batch"]
            assert_equal "No", zuora_basic_info["SynctoNetSuite__NS"]
            assert_equal "True", zuora_basic_info["APM__c"]
            assert_equal 13, zuora_billing_and_payment["billCycleDay"]
            assert_equal communication_profile_id, zuora_basic_info["communicationProfileId"]
            assert_equal "USD", zuora_billing_and_payment["currency"]
            assert_equal "Stripe v3", zuora_billing_and_payment["paymentGateway"]
            assert @business.plan_subscription.present?
            unless GitHub.flipper[:billing_contact_required_to_create_subscription].enabled?
              assert @business.plan_subscription.zuora_subscription.present?
              refute_equal original_zuora_account.id, @business.customer.zuora_account.id
              zuora_subscription = @business.plan_subscription.zuora_subscription
              assert_equal 7, zuora_subscription.active_rate_plans.count
              business_rate_plans = zuora_subscription.active_rate_plans.map { |p| p[:productName].to_s.downcase }
              assert_includes business_rate_plans, GitHub::Plan.business_plus(account: @business).zuora_product_name.downcase
            end
          end
        end
      end

      test "synchronizes the bill cycle day for the customer object during customer and subscription creation" do
        disable_feature_flag(:billing_contact_required_to_create_subscription)
        business = create(:business, customer: create(:customer, :invoiced))
        synchronize_github_products_to_zuora

        assert_nil business.customer.zuora_account_id
        assert_nil business.reload.plan_subscription
        only = [CheckForSpamJob, SynchronizePlanSubscriptionJob, UpdateLockedRepositoriesJob]
        perform_enqueued_jobs(only: only) do
          with_live_zuora("zuora_subscription/success_create_enterprise_customer_and_subscription_and_sync_billing_cycle_day") do
            business.enable_self_serve_payments
            business.reload
            assert_equal GitHub::Billing.today.day, business.customer.bill_cycle_day  # The customer bill cycle day should be synced
          end
        end
      end

      test "job to sync billing settings to orgs enqueued" do
        assert_enqueued_with(
          job: SyncBusinessOrganizationBillingSettingsJob,
          args: [@business, enterprise_purchase: false, switch_org_billing_to_invoice: false]
        ) do
          @business.enable_self_serve_payments(plan_duration: "month")
        end
      end
    end
  end

  context "#switch_to_invoiced_payments" do
    if GitHub.billing_enabled?
      test "does not update billing type if there are trade restrictions" do
        enable_feature_flag(:live_sdn_screening, @business_with_self_serve_payment)
        @business_with_self_serve_payment.trade_screening_record.true_match!
        assert_equal Customer::BILLING_TYPE_CARD, @business_with_self_serve_payment.billing_type

        @business_with_self_serve_payment.switch_to_invoiced_payments
        refute_equal Customer::BILLING_TYPE_INVOICE, @business_with_self_serve_payment.reload.billing_type
      end

      test "updates billing type to invoice" do
        assert_equal Customer::BILLING_TYPE_CARD, @business_with_self_serve_payment.billing_type

        @business_with_self_serve_payment.switch_to_invoiced_payments
        assert_equal Customer::BILLING_TYPE_INVOICE, @business_with_self_serve_payment.reload.billing_type
      end

      test "updates plan duration to yearly when plan duration monthly" do
        @business_with_self_serve_payment.update!(plan_duration: Business::BillingDependency::MONTHLY_PLAN)
        assert_equal Business::BillingDependency::MONTHLY_PLAN, @business_with_self_serve_payment.plan_duration

        @business_with_self_serve_payment.switch_to_invoiced_payments
        assert_equal Business::BillingDependency::YEARLY_PLAN, @business_with_self_serve_payment.plan_duration
      end

      test "resets billing attempts" do
        @business_with_self_serve_payment.set_billing_attempts(1)
        assert_equal 1, @business_with_self_serve_payment.billing_attempts

        @business_with_self_serve_payment.switch_to_invoiced_payments
        assert_equal 0, @business_with_self_serve_payment.billing_attempts
      end

      test "job to sync billing settings to orgs with org billing being switched to invoice enqueued" do
        @business_with_self_serve_payment.add_organization(create(:organization))
        assert_enqueued_with(
          job: SyncBusinessOrganizationBillingSettingsJob,
          args: [@business_with_self_serve_payment, enterprise_purchase: false, switch_org_billing_to_invoice: true]
        ) do
          @business_with_self_serve_payment.switch_to_invoiced_payments
        end
      end

      test "instruments billing.change_billing_type event" do
        events = assert_performed_audit_entries(count: 1, only: "billing.change_billing_type") do
          @business_with_self_serve_payment.switch_to_invoiced_payments
        end

        assert_equal last_performed_audit_entries, events

        expected_payload = {
          business_id: @business_with_self_serve_payment.id,
          business: @business_with_self_serve_payment.slug,
          old_billing_type: Customer::BILLING_TYPE_CARD,
          billing_type: Customer::BILLING_TYPE_INVOICE
        }

        assert_subset_hash expected_payload, events.first
      end

      test "instruments account.plan_change event when plan duration changed" do
        @business_with_self_serve_payment.update!(plan_duration: Business::BillingDependency::MONTHLY_PLAN)
        assert_predicate @business_with_self_serve_payment, :monthly_plan?

        events = assert_performed_audit_entries(count: 1, only: "account.plan_change") do
          @business_with_self_serve_payment.switch_to_invoiced_payments
        end

        assert_equal last_performed_audit_entries, events

        expected_payload = {
          old_plan: GitHub::Plan.business_plus.name,
          plan: GitHub::Plan.business_plus.name,
          old_plan_duration: Business::BillingDependency::MONTHLY_PLAN,
          plan_duration: Business::BillingDependency::YEARLY_PLAN,
          old_seats: @business_with_self_serve_payment.seats,
          seats:  @business_with_self_serve_payment.seats,
          old_data_packs: @business_with_self_serve_payment.data_packs,
          asset_packs: @business_with_self_serve_payment.data_packs,
          tos_sha: TosAcceptance.current_sha
        }

        @business_with_self_serve_payment.reload
        assert_predicate @business_with_self_serve_payment, :yearly_plan?
        assert_subset_hash expected_payload, events.first
      end
    end
  end

  context "#create_billing_customer_and_plan_subscription" do
    if GitHub.billing_enabled?
      test "creates new zuora account when billing type changed" do
        zuora_account_id = @business.customer.zuora_account_id
        refute_nil zuora_account_id

        @business.create_billing_customer_and_plan_subscription(billing_type_changed: true)
        @business.reload
        new_zuora_account_id = @business.customer.zuora_account_id

        refute_nil new_zuora_account_id
        refute_equal zuora_account_id, new_zuora_account_id
      end

      test "creates new zuora account when no zuora account exists" do
        @business.customer.update_attribute(:zuora_account_id, nil)
        @business.reload
        assert_nil @business.customer.zuora_account_id

        @business.create_billing_customer_and_plan_subscription
        @business.reload

        refute_nil @business.customer.zuora_account_id
      end

      test "does not create new zuora account when billing type not changed and zuora account exists" do
        zuora_account_id = @business.customer.zuora_account_id
        refute_nil zuora_account_id

        @business.create_billing_customer_and_plan_subscription
        @business.reload
        new_zuora_account_id = @business.customer.zuora_account_id

        refute_nil new_zuora_account_id
        assert_equal zuora_account_id, new_zuora_account_id
      end

      test "creates new plan subscription when no plan subscription exists" do
        assert_nil @business.plan_subscription

        @business.create_billing_customer_and_plan_subscription
        @business.reload

        refute_nil @business.plan_subscription
      end

      test "does not create new plan subscription when plan subscription exists" do
        plan_subscription = create(:billing_plan_subscription, :business_owned, customer: @business.customer)
        @business.reload
        plan_subscription = @business.plan_subscription
        refute_nil plan_subscription

        @business.create_billing_customer_and_plan_subscription
        @business.reload
        new_plan_subscription = @business.plan_subscription

        refute_nil plan_subscription
        assert_equal plan_subscription, new_plan_subscription
      end
    end
  end

  context "#billing_type" do
    if GitHub.billing_enabled?
      test "returns correct value if billing_type is card" do
        @business.customer.update_attribute(:billing_type, Customer::BILLING_TYPE_CARD)

        assert_equal Customer::BILLING_TYPE_CARD, @business.billing_type
      end

      test "returns correct value if  billing_type is invoice" do
        @business.customer.update_attribute(:billing_type, Customer::BILLING_TYPE_INVOICE)

        assert_equal Customer::BILLING_TYPE_INVOICE, @business.billing_type
      end
    else
      test "returns nil for environment where billing is disabled" do
        @business.customer.update_attribute(:billing_type, Customer::BILLING_TYPE_CARD)

        assert_nil @business.billing_type
      end
    end
  end

  context "#eligible_for_self_serve_payment?" do
    if GitHub.billing_enabled?
      test "returns false if billing not handled via a self serve payment method" do
        @business.customer.update_attribute(:billing_type, "invoice")

        refute_predicate @business, :self_serve_payment?
        refute_predicate @business, :eligible_for_self_serve_payment?
      end

      test "returns true if billing handled via a self serve payment method" do
        @business.customer.update_attribute(:billing_type, "card")

        assert_predicate @business, :self_serve_payment?
        assert_predicate @business, :eligible_for_self_serve_payment?
      end
    else
      test "returns false for environment where billing is disabled" do
        @business.customer.update_attribute(:billing_type, "card")

        refute_predicate @business, :self_serve_payment?
      end
    end
  end

  context "#has_self_serve_advanced_security" do
    test "returns false if potentially_trial_or_purchase_advanced_security? is false" do
      @business.stubs(:potentially_trial_or_purchase_advanced_security?).returns(false)
      @business.stubs(:advanced_security_purchased_for_entity?).returns(true)
      refute @business.has_self_serve_advanced_security?
    end

    test "returns false if advanced_security_purchased_for_entity? is false" do
      @business.stubs(:potentially_trial_or_purchase_advanced_security?).returns(true)
      @business.stubs(:advanced_security_purchased_for_entity?).returns(false)
      refute @business.has_self_serve_advanced_security?
    end

    test "returns true if purchased ghas" do
      owner = @business_with_self_serve_payment.owners.first
      result = @business_with_self_serve_payment.subscribe_to_advanced_security(
        actor: owner,
        seats: 1,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      assert result.ok?
      assert @business_with_self_serve_payment.has_self_serve_advanced_security?
    end

    test "returns false if sales is running a manual trial" do
      owner = @business_with_self_serve_payment.owners.first

      @business_with_self_serve_payment.mark_advanced_security_as_purchased_for_entity(actor: owner)

      refute @business_with_self_serve_payment.has_self_serve_advanced_security?
    end

    test "returns true if running a self_serve trial" do
      owner = @business_with_self_serve_payment.owners.first

      result = @business_with_self_serve_payment.subscribe_to_advanced_security_trial(
        actor: owner,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      assert result.ok?

      assert @business_with_self_serve_payment.has_self_serve_advanced_security?
    end

    test "returns true if running a self serve ghas trial and EA trial" do
      @business_with_self_serve_payment.update_attribute :trial_expires_at, ::Billing::EnterpriseCloudTrial.trial_length.from_now

      owner = @business_with_self_serve_payment.owners.first

      result = @business_with_self_serve_payment.subscribe_to_advanced_security_trial(
        actor: owner,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      assert result.ok?

      assert @business_with_self_serve_payment.has_self_serve_advanced_security?
    end

    test "returns false if a GHEC business purchased GHAS but the business is then downgraded to free" do
      owner = @business_with_self_serve_payment.owners.first
      result = @business_with_self_serve_payment.subscribe_to_advanced_security(
        actor: owner,
        seats: 1,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      assert result.ok?
      assert @business_with_self_serve_payment.has_self_serve_advanced_security?

      @business.downgrade_to_free_plan
      assert_predicate @business, :downgraded_to_free_plan?
      refute @business.has_self_serve_advanced_security?
    end
  end if GitHub.billing_enabled?

  context "Metered billable" do

    test "can lock metered billing services" do
      refute @business.metered_services_locked?

      @business.lock_metered_services

      assert @business.metered_services_locked?
    end

    test "can unlock metered billing services" do
      @business.lock_metered_services
      assert @business.metered_services_locked?

      @business.unlock_metered_services

      refute @business.metered_services_locked?
    end
  end

  context "#metered_services_billable?" do
    test "returns false if zuora account is not present and feature flag is enabled" do
      business = create(:business, :invoiced)
      enable_feature_flag(:strict_zuora_validation_on_metered_billable_check, business)
      business.customer.update!(zuora_account_id: nil)
      metered_services_billable = business.metered_services_billable?

      refute metered_services_billable[:billable]
      assert_equal :non_azure_no_zuora_account, metered_services_billable[:reason]
    end

    test "returns true if zuora account is not present and feature flag is disabled" do
      business = create(:business, :invoiced)
      disable_feature_flag(:strict_zuora_validation_on_metered_billable_check, business)
      business.customer.update!(zuora_account_id: nil)
      metered_services_billable = business.metered_services_billable?

      assert metered_services_billable[:billable]
      assert_equal :zuora_invoiced_subscription, metered_services_billable[:reason]
    end

    test "returns false if zuora subscription is not present and feature flag is enabled" do
      business = create(:business, :invoiced)
      enable_feature_flag(:strict_zuora_validation_on_metered_billable_check, business)
      business.customer.update!(zuora_account_id: SecureRandom.hex)
      metered_services_billable = business.metered_services_billable?

      refute metered_services_billable[:billable]
      assert_equal :non_azure_no_zuora_subscription, metered_services_billable[:reason]
    end

    test "returns true if zuora subscription is not present and feature flag is disabled" do
      business = create(:business, :invoiced)
      disable_feature_flag(:strict_zuora_validation_on_metered_billable_check, business)
      business.customer.update!(zuora_account_id: SecureRandom.hex)
      metered_services_billable = business.metered_services_billable?

      assert metered_services_billable[:billable]
      assert_equal :zuora_invoiced_subscription, metered_services_billable[:reason]
    end

    test "returns true for invoiced customer" do
      business = create(:business, :invoiced)
      enable_feature_flag(:strict_zuora_validation_on_metered_billable_check, business)
      business.customer.update!(zuora_account_id: SecureRandom.hex)
      create(
        :billing_sales_serve_plan_subscription,
        customer: business.customer
      )

      metered_services_billable = business.metered_services_billable?

      assert metered_services_billable[:billable]
      assert_equal :zuora_invoiced_subscription, metered_services_billable[:reason]
    end

    test "returns false if zuora account is not present on self-serve customer and feature flag is enabled" do
      business = create(:business, :with_self_serve_payment)
      enable_feature_flag(:strict_zuora_validation_on_metered_billable_check, business)
      business.customer.update!(zuora_account_id: nil)
      metered_services_billable = business.metered_services_billable?

      refute metered_services_billable[:billable]
      assert_equal :non_azure_no_zuora_account, metered_services_billable[:reason]
    end

    test "returns false if zuora account is not present on self-serve customer and feature flag is disabled" do
      business = create(:business, :with_self_serve_payment)
      disable_feature_flag(:strict_zuora_validation_on_metered_billable_check, business)
      business.customer.update!(zuora_account_id: nil)
      metered_services_billable = business.metered_services_billable?

      refute metered_services_billable[:billable]
      assert_equal :non_azure_no_zuora_account, metered_services_billable[:reason]
    end

    test "returns false if zuora subscription is not present on self-serve customer and feature flag is enabled" do
      business = create(:business, :with_self_serve_payment)
      enable_feature_flag(:strict_zuora_validation_on_metered_billable_check, business)
      metered_services_billable = business.metered_services_billable?

      refute metered_services_billable[:billable]
      assert_equal :non_azure_no_zuora_subscription, metered_services_billable[:reason]
    end

    test "returns false if zuora subscription is not present on self-serve customer and feature flag is disabled" do
      business = create(:business, :with_self_serve_payment)
      disable_feature_flag(:strict_zuora_validation_on_metered_billable_check, business)
      metered_services_billable = business.metered_services_billable?

      refute metered_services_billable[:billable]
      assert_equal :non_azure_no_zuora_subscription, metered_services_billable[:reason]
    end

    test "returns true for self-serve customer" do
      business = create(:business, :with_self_serve_payment)
      enable_feature_flag(:strict_zuora_validation_on_metered_billable_check, business)
      create(
        :billing_plan_subscription,
        customer: business.customer,
        zuora_subscription_number: "123"
      )

      metered_services_billable = business.metered_services_billable?

      assert metered_services_billable[:billable]
      assert_equal :zuora_valid_payment_method, metered_services_billable[:reason]
    end

    test "returns true for business with commercial interaction restrictions" do
      business = create(:business, :with_credit_card, :with_trade_screening_record)
      business.trade_screening_record.hit_in_review!
      enable_feature_flag(:live_sdn_screening, business)
      create(:billing_plan_subscription, :zuora, customer: business.customer)

      assert business.has_commercial_interaction_restriction?

      metered_services_billable = business.metered_services_billable?

      assert metered_services_billable[:billable]
      assert_equal :zuora_valid_payment_method, metered_services_billable[:reason]
    end
  end if GitHub.billing_enabled?

  context "#sync_all_organization_billing_settings" do
    if GitHub.billing_enabled?
      test "job to sync billing settings to organizations enqueued for non-trial business" do
        refute_predicate @business, :trial?

        assert_enqueued_with(
          job: SyncBusinessOrganizationBillingSettingsJob,
          args: [@business, enterprise_purchase: false, switch_org_billing_to_invoice: false]
        ) do
          @business.sync_all_organization_billing_settings
        end
      end

      test "job to sync billing settings to organizations not enqueued for trial business" do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        assert_predicate @business, :trial?

        assert_enqueued_jobs 0, only: SyncBusinessOrganizationBillingSettingsJob do
          @business.sync_all_organization_billing_settings
        end
      end

      test "job to sync billing settings to organizations not enqueued for cancelled trial business" do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        @business.cancel_trial(@business.admins.first)
        assert_predicate @business, :trial_cancelled?

        assert_enqueued_jobs 0, only: SyncBusinessOrganizationBillingSettingsJob do
          @business.sync_all_organization_billing_settings
        end
      end

      test "job to onboard organization to sponsors enqueued for non-trial business when enterprise purchase is true" do
        upgraded_organization = create(:organization)
        business = create(:business, organizations: [upgraded_organization], customer: create(:customer, :self_serve), owners: [@owner], upgraded_from: upgraded_organization)
        refute_predicate business, :trial?

        assert_enqueued_with(
          job: SponsorsBusinessOrgOnboardingJob,
          args: [organization: upgraded_organization, actor: User.ghost]
        ) do
          business.sync_all_organization_billing_settings(enterprise_purchase: true)
        end
      end

      test "job to onboard organization to sponsors not enqueued for non-trial business when enterprise purchase is false" do
        upgraded_organization = create(:organization)
        business = create(:business, customer: create(:customer, :self_serve), owners: [@owner], upgraded_from: upgraded_organization)
        refute_predicate business, :trial?

        assert_enqueued_jobs 0, only: SponsorsBusinessOrgOnboardingJob do
          business.sync_all_organization_billing_settings
        end
      end

      test "no-ops if business does not have any organizations" do
        @business.organizations.delete_all
        assert @business.organizations.empty?

        assert_enqueued_jobs(0, only: [SyncBusinessOrganizationBillingSettingsJob, SponsorsBusinessOrgOnboardingJob]) do
          @business.sync_all_organization_billing_settings(enterprise_purchase: true)
        end
      end
    end
  end

  context "#sync_organization_billing_settings" do
    if GitHub.billing_enabled?
      test "syncs billing settings to organization when customer account is available for non-trial business" do
        assert @business.customer
        refute_equal @business.plan, @org.plan
        refute_predicate @business, :trial?

        @business.sync_organization_billing_settings(@org)
        assert_equal @business.plan, @org.plan
      end

      test "syncs billing settings to organization when customer account is not set and billing_term_ends_at is set for non-trial business" do
        @business.update!(billing_term_ends_at: @business.customer.billing_end_date, customer: nil)
        refute @business.customer
        refute_equal @business.plan, @org.plan
        refute_predicate @business, :trial?

        @business.sync_organization_billing_settings(@org)
        assert_equal @business.plan, @org.plan
      end

      test "syncs billing settings to organization when customer account is not set for non-trial business" do
        @business.update!(customer: nil)
        refute @business.customer
        refute_equal @business.plan, @org.plan
        refute_predicate @business, :trial?

        @business.sync_organization_billing_settings(@org)
        assert_equal @business.plan, @org.plan
      end

      test "does not sync billing settings to organization for trial business" do
        @business.update!(trial_expires_at: 2.weeks.from_now)
        refute_equal @business.plan_name, @org.plan
        assert_predicate @business, :trial?

        @business.sync_organization_billing_settings(@org)
        refute_equal @business.plan, @org.plan
      end

      test "does not sync billing settings to organization for cancelled trial business" do
        @business.update!(trial_expires_at: 2.weeks.from_now)
        @business.cancel_trial(@business.owners.first)
        refute_equal @business.plan_name, @org.plan
        assert_predicate  @business, :trial_cancelled?

        @business.sync_organization_billing_settings(@org)
        refute_equal @business.plan, @org.plan
      end

      test "syncs billing settings even if the organization has no admins" do
        @org.admins.delete_all
        assert_predicate @org.admins, :empty?

        assert @business.customer
        refute_equal @business.plan, @org.plan
        refute_predicate @business, :trial?

        @business.sync_organization_billing_settings(@org)
        assert_equal @business.plan, @org.plan
      end
    else
      test "does not sync business billing settings to an organization" do
        assert @business.customer
        refute_equal @business.plan, @org.plan

        @business.sync_organization_billing_settings(@org)
        refute_equal @business.plan, @org.plan
      end
    end
  end

  context "#migrate_organization_to_business_billing" do
    if GitHub.billing_enabled?
      test "changes organization to invoiced billing" do
        refute @org.invoiced?
        @business.migrate_organization_to_business_billing(@org)
        assert @org.invoiced?
      end

      test "unlock organization billing" do
        customer = create(:customer_account, user: @org).customer
        @org.disable!
        assert @org.disabled?
        @business.migrate_organization_to_business_billing(@org)
        assert @org.enabled?
      end
    end
  end

  context "#skip_metered_billing_permission_check_for", skip_enterprise: true do
    test "returns true if the key has been set" do
      @business.skip_metered_billing_permission_check_for(product: :packages, expires: 1.year.from_now)

      assert_equal true, @business.skip_metered_billing_permission_check_for?(product: :packages)
    end

    test "returns false if the key has not been set" do
      assert_equal false, @business.skip_metered_billing_permission_check_for?(product: :packages)
    end

    test "returns false if the key has been set but is expired" do
      Timecop.freeze do
        @business.stubs(:next_metered_billing_cycle_starts_at).returns(GitHub::Billing.now.beginning_of_day - 1.day)
        @business.skip_metered_billing_permission_check_for(product: :packages)

        assert_equal false, @business.skip_metered_billing_permission_check_for?(product: :packages)
      end
    end
  end

  context "#budget_for", skip_enterprise: true do
    test "returns a new in-memory object with default values if no record exists when the business is on an enterprise agreement with an azure subscription" do
      config = @business_with_azure_subscription.budget_for(group: "shared")

      assert config.enforce_spending_limit?
      assert_equal 0, config.spending_limit_in_subunits
      refute config.persisted?
      refute config.readonly?
    end

    test "returns the record from the DB if it exists and the business is on an enterprise agreement with an azure subscription" do
      create(:billing_budget, owner: @business_with_azure_subscription, enforce_spending_limit: false, spending_limit_in_subunits: 1000)

      config = @business_with_azure_subscription.budget_for(group: "shared")

      refute config.enforce_spending_limit?
      assert_equal 1000, config.spending_limit_in_subunits
      refute config.readonly?
    end

    test "returns a readonly in-memory record with an enforced limit 0 if they have an enterprise agreement and a customer with no azure subscription id" do
      @business_with_azure_subscription.customer.update!(azure_subscription_id: nil)
      create(:billing_budget, owner: @business_with_azure_subscription, enforce_spending_limit: false, spending_limit_in_subunits: 1000)

      config = @business_with_azure_subscription.budget_for(group: "shared")

      assert config.enforce_spending_limit?
      assert_equal 0, config.spending_limit_in_subunits
      refute config.persisted?
      assert config.readonly?
    end

    test "returns a new unlimited budget record for enterprise billed by github if there is no default budget" do
      config = @business.budget_for(group: "shared")

      refute config.enforce_spending_limit?
    end

    test "returns the existing budget for enterprise with azure subscription if there is an existing budget for the group" do
      existing_budget = create(:billing_budget, owner: @business_with_azure_subscription, enforce_spending_limit: false)

      budget = @business_with_azure_subscription.budget_for(group: "shared")

      assert_equal existing_budget, budget
    end

    test "businesses without enterprise agreement convert codespaces product to appropriate product_key" do
      config = @business.budget_for(product: "codespaces_compute")
      assert_equal "codespaces", config.product
      refute config.persisted?
      refute config.readonly?
    end

    test "businesses with enterprise agreement do not convert codespaces product" do
      config = @business_with_azure_subscription.budget_for(group: "codespaces")
      assert_equal "codespaces", config.product
      refute config.persisted?
      refute config.readonly?
    end
  end

  context "#current_metered_billing_cycle_starts_at", skip_enterprise: true do
    test "returns the beginning of the day (in the billing time zone) on the most recent day-of-month + 1 that the billing term ends (even if the billing term ended in the past)" do
      travel_to GitHub::Billing.timezone.local(2019, 10, 16, 12, 12, 12) do
        business = Business.new(customer: Customer.new)
        business.billing_term_ends_at = Date.new(2019, 6, 10)
        business.customer&.bill_cycle_day = T.must(business.billed_on).day
        assert_equal GitHub::Billing.timezone.local(2019, 10, 11), business.current_metered_billing_cycle_starts_at
      end
    end

    test "returns the beginning of the day (in the billing time zone) on the most recent day-of-month + 1 that the billing term ends (even if the billing term ends in the future)" do
      travel_to GitHub::Billing.timezone.local(2019, 10, 16, 12, 12, 12) do
        business = Business.new(customer: Customer.new)
        business.billing_term_ends_at = Date.new(2020, 9, 10)
        business.customer&.bill_cycle_day = T.must(business.billed_on).day
        assert_equal GitHub::Billing.timezone.local(2019, 10, 11), business.current_metered_billing_cycle_starts_at
      end
    end

    test "returns the beginning of the day (in the billing time zone) on the most recent day-of-month + 1 that the billing term ends (even if that falls in the previous month)" do
      travel_to GitHub::Billing.timezone.local(2019, 10, 16, 12, 12, 12) do
        business = Business.new(customer: Customer.new)
        business.billing_term_ends_at = Date.new(2020, 9, 20)
        business.customer&.bill_cycle_day = T.must(business.billed_on).day
        assert_equal GitHub::Billing.timezone.local(2019, 9, 21), business.current_metered_billing_cycle_starts_at
      end
    end

    test "returns the beginning of the day (in the billing time zone) on the last day of the month if the day-of-month + 1 that the billing term ends is greater than the days in the current month" do
      travel_to GitHub::Billing.timezone.local(2019, 3, 2, 12, 12, 12) do
        business = Business.new(customer: Customer.new)
        business.billing_term_ends_at = Date.new(2020, 7, 30)
        business.customer&.bill_cycle_day = T.must(business.billed_on).day
        assert_equal GitHub::Billing.timezone.local(2019, 2, 28), business.current_metered_billing_cycle_starts_at
      end
    end

    test "returns the beginning of the day (in the billing time zone) on the last day of the month if it is the last day of the month and the bcd > last day of the month" do
      travel_to GitHub::Billing.timezone.local(2019, 2, 28, 12, 12, 12) do
        business = Business.new(customer: Customer.new)
        business.billing_term_ends_at = Date.new(2020, 7, 30)
        business.customer&.bill_cycle_day = T.must(business.billed_on).day
        assert_equal GitHub::Billing.timezone.local(2019, 2, 28), business.current_metered_billing_cycle_starts_at
      end
    end

    test "returns the first of the current month (based on UTC, not the billing timezone) when there's an enterprise agreement" do
      travel_to GitHub::Billing.timezone.local(2019, 9, 30, 23, 59, 59) do
        assert_equal Time.find_zone("UTC").local(2019, 10, 1), @business_with_azure_subscription.current_metered_billing_cycle_starts_at
      end
    end

    test "returns the first of the current month (based on UTC, not the billing timezone) when an enterprise is metered via azure" do
      travel_to GitHub::Billing.timezone.local(2019, 9, 30, 23, 59, 59) do
        business = create(:business, :with_azure_subscription)
        business.customer.update!(metered_via_azure: true)
        assert_equal Time.find_zone("UTC").local(2019, 10, 1), business.current_metered_billing_cycle_starts_at
      end
    end

    test "returns the first of the current month (based on UTC, not the billing timezone) when an enterprise is billed through billing platform" do
      travel_to GitHub::Billing.timezone.local(2019, 9, 30, 23, 59, 59) do
        business = create(:business)
        business.customer.update!(billed_via_billing_platform: true)
        assert_equal Time.find_zone("UTC").local(2019, 10, 1), business.current_metered_billing_cycle_starts_at
      end
    end
  end

  context "#next_metered_billing_cycle_starts_at", skip_enterprise: true do
    test "returns the beginning of the day (in the billing time zone) on the most recent day-of-month + 1 that the billing term ends (even if the billing term ended in the past)" do
      travel_to GitHub::Billing.timezone.local(2019, 10, 16, 12, 12, 12) do
        business = Business.new(customer: Customer.new)
        business.billing_term_ends_at = Date.new(2019, 6, 10)
        business.customer&.bill_cycle_day = T.must(business.billed_on).day
        assert_equal GitHub::Billing.timezone.local(2019, 11, 11), business.next_metered_billing_cycle_starts_at
      end
    end

    test "returns the beginning of the day (in the billing time zone) on the most recent day-of-month + 1 that the billing term ends (even if the billing term ends in the future)" do
      travel_to GitHub::Billing.timezone.local(2019, 10, 16, 12, 12, 12) do
        business = Business.new(customer: Customer.new)
        business.billing_term_ends_at = Date.new(2020, 9, 10)
        business.customer&.bill_cycle_day = T.must(business.billed_on).day
        assert_equal GitHub::Billing.timezone.local(2019, 11, 11), business.next_metered_billing_cycle_starts_at
      end
    end

    test "returns the beginning of the day (in the billing time zone) on the most recent day-of-month + 1 that the billing term ends (even if that falls in the previous month)" do
      travel_to GitHub::Billing.timezone.local(2019, 10, 16, 12, 12, 12) do
        business = Business.new(customer: Customer.new)
        business.billing_term_ends_at = Date.new(2020, 9, 20)
        business.customer&.bill_cycle_day = T.must(business.billed_on).day
        assert_equal GitHub::Billing.timezone.local(2019, 10, 21), business.next_metered_billing_cycle_starts_at
      end
    end

    test "returns the beginning of the day (in the billing time zone) on the last day of the month if the day-of-month + 1 that the billing term ends is greater than the days in the current month" do
      travel_to GitHub::Billing.timezone.local(2019, 3, 2, 12, 12, 12) do
        business = Business.new(customer: Customer.new)
        business.billing_term_ends_at = Date.new(2020, 7, 30)
        business.customer&.bill_cycle_day = T.must(business.billed_on).day
        assert_equal GitHub::Billing.timezone.local(2019, 3, 31), business.next_metered_billing_cycle_starts_at
      end
    end

    test "returns the first of the current month (based on UTC, not the billing timezone) when there's an enterprise agreement" do
      travel_to GitHub::Billing.timezone.local(2019, 9, 30, 23, 59, 59) do
        assert_equal Time.find_zone("UTC").local(2019, 11, 1), @business_with_azure_subscription.next_metered_billing_cycle_starts_at
      end
    end

    test "returns the first of the next month (based on UTC, not the billing timezone) when an enterprise is metered via azure" do
      travel_to GitHub::Billing.timezone.local(2019, 9, 30, 23, 59, 59) do
        business = create(:business, :with_azure_subscription)
        business.customer.update!(metered_via_azure: true)
        assert_equal Time.find_zone("UTC").local(2019, 11, 1), business.next_metered_billing_cycle_starts_at
      end
    end

    test "returns the first of the next month (based on UTC, not the billing timezone) when an enterprise is billed through billing platform" do
      travel_to GitHub::Billing.timezone.local(2019, 9, 30, 23, 59, 59) do
        business = create(:business)
        business.customer.update!(billed_via_billing_platform: true)
        assert_equal Time.find_zone("UTC").local(2019, 11, 1), business.next_metered_billing_cycle_starts_at
      end
    end
  end

  context ".with_active_azure_subscription" do
    test "returns only businesses with active enterprise agreements and azure subscription IDs specified", skip_enterprise: true do
      _with_active_no_subscription = create(:business, :with_azure_subscription).tap do |business|
        business.customer.update!(azure_subscription_id: nil)
      end
      _with_ended_subscription = create(:business, :with_azure_subscription).tap do |business|
        business.enterprise_agreements.each(&:ended!)
      end
      _with_no_enterprise_agreement = @business

      assert_same_elements [@business_with_azure_subscription, @business_metered_trial], Business.with_active_azure_subscription
    end
  end

  context "#billed_through_azure_subscription?", skip_enterprise: true do
    test "returns false when there are no active enterprise agreements" do
      refute @business.billed_through_azure_subscription?
    end

    test "returns true when there are active enterprise agreements because the customer will pay MSFT" do
      assert @business_with_azure_subscription.billed_through_azure_subscription?
    end

    test "returns true when customer is copilot standalone" do
      # This is temporary until standalone decides to support Zuora
      business = create(:business, seats_plan_type: :basic)
      assert business.billed_through_azure_subscription?
    end
  end

  context "#linked_azure_subscription?", skip_enterprise: true do
    test "returns true with an azure subscription ID on record" do
      assert @business_with_azure_subscription.linked_azure_subscription?
    end

    test "returns false without an azure subscription ID on record" do
      business = create(:business, :with_azure_subscription).tap do |business|
        business.customer.update!(azure_subscription_id: nil)
      end

      refute business.linked_azure_subscription?
    end
  end

  context "#pays_github_directly?", skip_enterprise: true do
    test "true when there are no active enterprise agreements" do
      assert @business.pays_github_directly?
    end

    test "false when there are active enterprise agreements because the customer will pay MSFT" do
      refute @business_with_azure_subscription.pays_github_directly?
    end
  end

  context "#customer_bill_cycle_day", skip_enterprise: true do
    test "returns 1 for customers with active enterprise agreements" do
      assert_equal 1, @business_with_azure_subscription.customer_bill_cycle_day
    end

    test "returns the bill_cycle_day from the customer for non-enterprise agreement businesses" do
      @business.customer.update!(bill_cycle_day: 4)
      assert_equal 4, @business.customer_bill_cycle_day
    end
  end

  context "#downgraded_to_free_plan?" do
    if GitHub.billing_enabled?
      test "returns false when downgraded_at is nil" do
        @business.update_attribute(:downgraded_at, nil)
        refute_predicate @business, :downgraded_to_free_plan?
      end

      test "returns true when downgraded_at is not nil" do
        @business.update_attribute(:downgraded_at, GitHub::Billing.now)
        assert_predicate @business, :downgraded_to_free_plan?
      end
    else
      test "returns false for environment where billing is not enabled" do
        refute_predicate @business, :downgraded_to_free_plan?
      end
    end
  end

  context "#unlock_billing!" do
    if GitHub.billing_enabled?
      test "enables a disabled non-trial account" do
        business = create :business
        business.disable!

        business.unlock_billing!
        business.reload
        refute_predicate business, :trial?
        assert_predicate business, :enabled?
      end

      test "moves the billing end date to 2 days from today" do
        Timecop.freeze("2016-05-01") do
          today = GitHub::Billing.today
          business = create :business
          business.customer.update!(billing_end_date: today - 1.week)
          business.disable!

          business.unlock_billing!
          assert_equal today + 1.day, business.reload.customer.billing_end_date
          assert_equal today + 2.days, business.billed_on
        end
      end

      test "resets the billing attempts" do
        business = create :business
        business.disable!
        business.increment_billing_attempts
        assert_equal business.billing_attempts, 1

        business.unlock_billing!
        assert business.reload.billing_attempts.zero?
      end

      test "does not change billing end date if it's already in the future" do
        Timecop.freeze("2016-05-01") do
          today = GitHub::Billing.today
          business = create :business
          business.customer.update!(billing_end_date: today + 1.week)

          business.unlock_billing!
          assert_equal today + 1.week, business.reload.customer.billing_end_date
        end
      end

      test "does not modify billed on date if there's a plan subscription present" do
        Timecop.freeze("2016-05-01") do
          business = create :business
          business.enable_self_serve_payments(plan_duration: "year")
          refute_nil business.reload.plan_subscription
          billed_on = business.billed_on
          business.unlock_billing!

          assert_equal billed_on, business.reload.billed_on
        end
      end

      test "changes the billing end date to match the metered ghec trial end date if the trial is still active" do
        Timecop.freeze("2025-01-16") do
          @business_metered_trial.customer.update!(metered_ghe: true, billing_type: Customer::BILLING_TYPE_CARD)
          @business_metered_trial.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
          @business_metered_trial.customer.update!(billing_end_date: GitHub::Billing.today + 15.days)
          @business_metered_trial.disable!
          @business_metered_trial.unlock_billing!

          assert_equal @business_metered_trial.trial_expires_at, @business_metered_trial.customer.billing_end_date
        end
      end
    end
  end

  context "#downgrade_to_free_plan" do
    if GitHub.billing_enabled?
      test "downgrades business account to free plan" do
        refute_predicate @business, :downgraded_to_free_plan?
        @business.downgrade_to_free_plan

        assert_predicate @business, :downgraded_to_free_plan?
        assert_equal GitHub::Plan.free, @business.plan
      end

      test "enqueues job to synchronize organization billing settings after downgrade" do
        refute_predicate @business, :downgraded_to_free_plan?

        assert_enqueued_jobs(1, only: SyncBusinessOrganizationBillingSettingsJob) do
          @business.downgrade_to_free_plan
        end
      end

      test "disables SAML on the business if it was downgraded because of trial expiration" do
        provider = create(:business_saml_provider)
        business = provider.business
        refute_nil business.saml_provider

        business.update_attribute :trial_expires_at, GitHub::Billing.today - 1.day
        assert_predicate business.reload, :trial_expired?

        business.downgrade_to_free_plan

        assert_nil business.reload.saml_provider
      end

      test "disables SAML on the business if it was downgraded because of trial cancellation" do
        provider = create(:business_saml_provider)
        business = provider.business
        refute_nil business.saml_provider

        business.trial_cancelled!
        assert_predicate business.reload, :trial_cancelled?

        business.downgrade_to_free_plan

        assert_nil business.reload.saml_provider
      end

      test "does not disable SAML on the business if it is not in a trial expired or cancelled state" do
        provider = create(:business_saml_provider)
        business = provider.business
        refute_nil business.saml_provider

        business.downgrade_to_free_plan

        refute_nil business.reload.saml_provider
      end

      test "disables ssh certificate requirement for enterprise orgs during enterprise downgrade" do
        business_org = create(:business_plus_org)
        business = create(:business_organization_membership, organization: business_org).business.reload

        ca2 = create(:ssh_certificate_authority, owner: business_org)
        business_org.enable_ssh_certificate_requirement(business.owners.first)
        business_org.reload
        business.reload

        business.downgrade_to_free_plan
        assert_predicate business, :downgraded_to_free_plan?
        assert_equal GitHub::Plan.free, business.plan

        business.reload
        refute_predicate business, :ssh_certificate_requirement_enabled?
        # verify the enterprise org ssh certificate requirement was disabled
        business_org.reload
        refute_predicate business_org, :ssh_certificate_requirement_enabled?
      end

      test "ssh certificate requirement remains enabled during orgless enterprise downgrade" do
        business_org = create(:business_plus_org)
        business = create(:business_organization_membership, organization: business_org).business.reload

        ca1 = create(:ssh_certificate_authority, owner: business)
        business.enable_ssh_certificate_requirement(business.owners.first)
        business.remove_organization business_org, actor: business.owners.first

        business_org.reload
        business.reload

        business.downgrade_to_free_plan
        assert_predicate business, :downgraded_to_free_plan?
        assert_equal GitHub::Plan.free, business.plan

        # Businesses don't lose access to the SSH CA feature when their plan is downgraded,
        # so we don't need to disable the business level SSH CA requirement.
        business.reload
        assert_predicate business, :ssh_certificate_requirement_enabled?
        business_org.reload
        refute_predicate business_org, :ssh_certificate_requirement_enabled?
      end

      test "does not downgrade business account to free plan if it has already been downgraded" do
        @business.update_attribute(:downgraded_at, GitHub::Billing.now)
        assert_predicate @business, :downgraded_to_free_plan?
        @business.reload

        @business.downgrade_to_free_plan

        refute_predicate @business, :saved_change_to_downgraded_at?  # Ensure the downgraded_at attribute has not changed
        assert_predicate @business, :downgraded_to_free_plan?
        assert_equal GitHub::Plan.free, @business.plan
      end

      test "instruments account.plan_change event for downgrading business account to free plan" do
        refute_predicate @business, :downgraded_to_free_plan?

        events = assert_performed_audit_entries(count: 1, only: "account.plan_change") do
          @business.downgrade_to_free_plan
        end

        expected_payload = {
          old_plan: GitHub::Plan.business_plus.name,
          plan: GitHub::Plan.free.name,
          old_plan_duration: @business.plan_duration,
          plan_duration: @business.plan_duration,
          old_seats: @business.seats,
          seats:  @business.seats,
          old_data_packs: @business.data_packs,
          asset_packs: @business.data_packs,
          tos_sha: TosAcceptance.current_sha
        }

        @business.reload
        assert_equal GitHub::Plan.free.name, @business.plan.name
        assert_subset_hash expected_payload, events.first
      end

      test "does not instrument account.plan_change event during downgrade attempt if business has already been downgraded" do
        @business.update_attribute(:downgraded_at, GitHub::Billing.now)  # Do the downgrade first
        assert_predicate @business, :downgraded_to_free_plan?
        @business.reload

        assert_performed_audit_entries(count: 0, only: "account.plan_change") do  # Event should not be called
          @business.downgrade_to_free_plan
        end

        @business.reload
        assert_equal GitHub::Plan.free.name, @business.plan.name
      end
    else
      test "does nothing for environment where billing is not enabled" do
        refute_predicate @business, :downgraded_to_free_plan?
        @business.downgrade_to_free_plan

        refute_predicate @business, :downgraded_to_free_plan?
        assert_equal GitHub::Plan.default_plan(account: @business), @business.plan
      end

      test "does not instrument account.plan_change event on a business_plus plan when billing is not enabled" do
        refute_predicate @business, :downgraded_to_free_plan?
        assert_performed_audit_entries(count: 0, only: "account.plan_change") do
          @business.downgrade_to_free_plan
        end

        refute_predicate @business, :downgraded_to_free_plan?
        assert_equal GitHub::Plan.default_plan(account: @business), @business.plan
      end
    end
  end

  context "#upgrade_to_business_plus_plan" do
    if GitHub.billing_enabled?
      test "upgrades business account to business plus plan" do
        @business.update_attribute(:downgraded_at, GitHub::Billing.now)
        assert_predicate @business, :downgraded_to_free_plan?
        @business.upgrade_to_business_plus_plan

        refute_predicate @business, :downgraded_to_free_plan?
        assert_equal GitHub::Plan.business_plus(account: @business), @business.plan
      end

      test "enqueues job to synchronize organization billing settings after upgrade" do
        @business.update_attribute(:downgraded_at, GitHub::Billing.now)
        assert_predicate @business, :downgraded_to_free_plan?

        assert_enqueued_jobs(1, only: SyncBusinessOrganizationBillingSettingsJob) do
          @business.upgrade_to_business_plus_plan
        end
      end

      test "does not upgrade business account to business_plus plan if it has not been downgraded" do
        refute_predicate @business, :downgraded_to_free_plan?

        @business.upgrade_to_business_plus_plan

        refute_predicate @business, :saved_change_to_downgraded_at?  # Ensure the downgraded_at attribute has not changed
        refute_predicate @business, :downgraded_to_free_plan?
        assert_equal GitHub::Plan.business_plus(account: @business), @business.plan
      end

      test "instruments audit log event for upgrading business account to business_plus plan" do
        @business.update_attribute(:downgraded_at, GitHub::Billing.now)
        assert_predicate @business, :downgraded_to_free_plan?

        events = assert_performed_audit_entries(count: 1, only: "account.plan_change") do
          @business.upgrade_to_business_plus_plan
        end

        expected_payload = {
          old_plan: GitHub::Plan.free.name,
          plan: GitHub::Plan.business_plus(account: @business).name,
          old_plan_duration: @business.plan_duration,
          plan_duration: @business.plan_duration,
          old_seats: @business.seats,
          seats:  @business.seats,
          old_data_packs: @business.data_packs,
          asset_packs: @business.data_packs,
          tos_sha: TosAcceptance.current_sha
        }

        @business.reload
        assert_equal GitHub::Plan.business_plus(account: @business), @business.plan
        assert_subset_hash expected_payload, events.first
      end

      test "does not instrument account.plan_change event during upgrade attempt if business has not been downgraded" do
        refute_predicate @business, :downgraded_to_free_plan?

        assert_performed_audit_entries(count: 0, only: "account.plan_change") do  # Event should not be called
          @business.upgrade_to_business_plus_plan
        end

        @business.reload
        assert_equal GitHub::Plan.business_plus(account: @business), @business.plan
      end
    else
      test "does nothing for environment where billing is not enabled" do
        refute_predicate @business, :downgraded_to_free_plan?
        @business.upgrade_to_business_plus_plan

        refute_predicate @business, :downgraded_to_free_plan?
        assert_equal GitHub::Plan.default_plan(account: @business), @business.plan
      end
    end
  end

  context "#upgrading_from_organization?" do
    test "returns true if Business is in the organization_upgrade_initiated state" do
      assert_predicate @business_to_upgrade, :organization_upgrade_initiated?

      assert_predicate @business_to_upgrade, :upgrading_from_organization?
    end

    test "returns true if Business is in the organization_upgrade_purchase_initiated state" do
      assert_predicate @business_to_upgrade, :organization_upgrade_initiated?

      @business_to_upgrade.initiate_organization_upgrade_purchase
      assert_predicate @business_to_upgrade, :organization_upgrade_purchase_initiated?

      assert_predicate @business_to_upgrade, :upgrading_from_organization?
    end

    test "returns false if Business is in a trial state" do
      trial_business = create :business, owners: [@owner]
      trial_business.update(trial_expires_at: 1.week.from_now)
      assert_predicate trial_business, :trial?

      refute_predicate trial_business, :upgrading_from_organization?
    end

    test "returns false for a regular Business" do
      business = create :business
      refute_predicate business, :upgrading_from_organization?
    end
  end if GitHub.billing_enabled?

  context "#being_created_from_coupon" do
    test "returns true if Business is in the creation_initiated_from_coupon state" do
      @business.initiate_creation_from_coupon
      assert_predicate @business, :creation_initiated_from_coupon?

      assert_predicate @business, :being_created_from_coupon?
    end

    test "returns true if Business is in the creation_from_coupon_purchase_initiated state" do
      @business.initiate_creation_from_coupon

      @business.initiate_creation_purchase_from_coupon
      assert_predicate @business, :creation_from_coupon_purchase_initiated?

      assert_predicate @business, :being_created_from_coupon?
    end

    test "returns false if Business is in a trial state" do
      trial_business = create :business, owners: [@owner]
      trial_business.update(trial_expires_at: 1.week.from_now)
      assert_predicate trial_business, :trial?

      refute_predicate trial_business, :being_created_from_coupon?
    end

    test "returns false for a regular Business" do
      business = create :business
      refute_predicate business, :being_created_from_coupon?
    end
  end if GitHub.billing_enabled?

  context "#plan" do
    if GitHub.single_business_environment?
      test "returns default plan on single business environment" do
        assert_equal GitHub::Plan.default_plan(account: @business), @business.plan
      end
    else
      test "returns business plus plan for business account that is not downgraded" do
        refute_predicate @business, :downgraded_to_free_plan?
        assert_equal GitHub::Plan.business_plus(account: @business), @business.plan
      end

      test "returns free plan for business account that is downgraded" do
        @business.update_attribute(:downgraded_at, GitHub::Billing.now)

        assert_predicate @business, :downgraded_to_free_plan?
        assert_equal GitHub::Plan.free, @business.plan
      end
    end
  end

  context "#paid_plan?" do
    test "returns false for Business on free plan" do
      free_business = create(:business)
      free_business.downgrade_to_free_plan
      assert_predicate free_business, :downgraded_to_free_plan?
      refute_predicate free_business, :paid_plan?
    end

    test "returns true for Business on paid plan" do
      assert_predicate @business, :paid_plan?
      assert_predicate @business_with_azure_subscription, :paid_plan?
      assert_predicate @business_with_self_serve_payment, :paid_plan?
    end
  end if GitHub.billing_enabled?

  context "#plan_name" do
    if GitHub.single_business_environment?
      test "returns enterprise plan name on single business environment" do
        assert_equal "enterprise", @business.plan_name
      end
    else
      test "returns business plus plan name for business account that is not downgraded" do
        refute_predicate @business, :downgraded_to_free_plan?
        assert_equal "business_plus", @business.plan_name
      end

      test "returns free plan name for business account that is downgraded" do
        @business.update_attribute(:downgraded_at, GitHub::Billing.now)

        assert_predicate @business, :downgraded_to_free_plan?
        assert_equal "free", @business.plan_name
      end
    end
  end

  context "#plan_effective_at" do
    test "returns the current time for a new Business" do
      Timecop.freeze do
        business = build :business
        assert_equal GitHub::Billing.now.to_i, business.plan_effective_at.to_i
      end
    end

    test "uses enterprise agreement effective at for azure customers" do
      business = create :business, :with_azure_subscription
      assert_equal business.enterprise_agreement_effective_at.to_i, business.plan_effective_at.to_i
    end

    test "uses billing start date for github customers" do
      billing_start_date = GitHub::Billing.today - 5.days
      business = create :business, :with_github_subscription
      create :billing_sales_serve_plan_subscription,
        customer: business.customer,
        billing_start_date: billing_start_date
      billing_start_datetime = GitHub::Billing.date_in_timezone(billing_start_date)
      assert_equal billing_start_datetime.to_i, business.plan_effective_at.to_i
    end

    test "defaults to now for users without a billing start date" do
      Timecop.freeze do
        business = create :business, :with_github_subscription
        assert_equal GitHub::Billing.now.to_i, business.plan_effective_at.to_i
      end
    end

    test "uses the active agreement that started first" do
      business = create :business, :with_azure_subscription
      create :enterprise_agreement, :github_enterprise_unified, business: business,
        starts_at: 10.days.ago
      first_agreement = create :enterprise_agreement, :github_enterprise_unified, business: business,
        starts_at: 15.days.ago
      assert_equal first_agreement.starts_at.to_i, business.plan_effective_at.to_i
    end
  end if GitHub.billing_enabled?

  context "#previous_billing_date" do
    test "returns the previous billed_on date for business on monthly plan" do
      billed_on = GitHub::Billing.today
      last_billed_on = billed_on - 1.month
      @business.update(plan_duration: "month", billing_term_ends_at: billed_on - 1.day)

      assert_predicate @business, :monthly_plan?
      assert_equal last_billed_on, @business.previous_billing_date
    end

    test "returns the previous billed_on date for business on yearly plan" do
      billed_on = GitHub::Billing.today
      last_billed_on = billed_on - 1.year
      @business.update(plan_duration: "year", billing_term_ends_at: billed_on - 1.day)

      assert_predicate @business, :yearly_plan?
      assert_equal last_billed_on, @business.previous_billing_date
    end

    test "returns one cycle from today if no billed_on date exists for business on monthly plan" do
      travel_to(Date.new(2020, 5, 1)) do
        last_billed_on = GitHub::Billing.today - 1.month
        @business.update(plan_duration: "month", billing_term_ends_at: nil)
        @business.customer.update(billing_end_date: nil)

        assert_nil @business.billed_on
        assert_equal last_billed_on, @business.previous_billing_date
      end
    end

    test "returns one cycle from today if no billed_on date exists for business on yearly plan" do
      travel_to(Date.new(2020, 5, 1)) do
        last_billed_on = GitHub::Billing.today - 1.year
        @business.update(plan_duration: "year", billing_term_ends_at: nil)
        @business.customer.update(billing_end_date: nil)

        assert_nil @business.billed_on
        assert_equal last_billed_on, @business.previous_billing_date
      end
    end

    test "returns the previous billed_on date based on cycles specified for business on monthly plan" do
      billed_on = GitHub::Billing.today
      last_billed_on = billed_on - 4.months
      @business.update(plan_duration: "month", billing_term_ends_at: billed_on - 1.day)

      assert_equal last_billed_on, @business.previous_billing_date(cycles: 4)
    end

    test "returns the previous billed_on date based on cycles specified for business on yearly plan" do
      billed_on = GitHub::Billing.today
      last_billed_on = billed_on - 2.years
      @business.update(plan_duration: "year", billing_term_ends_at: billed_on - 1.day)

      assert_equal last_billed_on, @business.previous_billing_date(cycles: 2)
    end
  end

  context "#metered_cycle_day", skip_enterprise: true do
    test "returns 1 for businesses with active enterprise agreements" do
      assert_equal 1, @business_with_azure_subscription.metered_cycle_day
    end

    test "returns 1 for businesses without enterprise agreements when there is no customer" do
      @business.customer = nil
      assert_equal 1, @business.metered_cycle_day
    end

    test "returns 1 for businesses without enterprise agreements whose customer have a bill_cycle_day of 0" do
      @business.customer.update!(bill_cycle_day: 0)
      assert_equal 1, @business.metered_cycle_day
    end

    test "returns 1 for businesses without enterprise agreements whose customer is metered via azure" do
      business = create(:business, :with_azure_subscription)
      business.customer.update!(metered_via_azure: true)
      assert_equal 1, business.metered_cycle_day
    end

    test "returns the bill cyle day of the customer for businesses without enterprise agreements whose customer have a positive bill_cycle_day" do
      @business.customer.update!(bill_cycle_day: 4)
      assert_equal 4, @business.metered_cycle_day
    end
  end

  context "#add_billing_email" do
    test "validates email format" do
      errors = @business.add_billing_email("eee")
      assert_equal ["Email does not look like an email address"], errors
    end

    test "validates that email is not disposable", skip_enterprise: true do
      email = "billing@gmai.com"
      assert UserEmail::DisposableEmailsDependency.disposable_email?(email)

      errors = @business.add_billing_email(email)

      assert_equal ["Email cannot be billing@gmai.com - domain could not be verified"], errors
    end

    test "validates uniqueness" do
      errors = @business.add_billing_email("one@example.com")
      assert_empty errors
      errors = @business.add_billing_email("one@example.com")
      assert_equal ["Email has already been taken"], errors
    end

    test "validates that primary is not duplicated to #billing_external_emails" do
      @business.update! billing_email: "billing@example.com"
      errors = @business.add_billing_email("billing@example.com")
      assert_equal ["Email can't be the same as primary billing email"], errors
    end

    test "adds first email as primary billing email" do
      @business.update! billing_email: nil
      errors = @business.add_billing_email("billing@example.com")
      assert_empty errors
      assert_equal "billing@example.com", @business.billing_email
      assert_empty @business.billing_external_emails
    end

    test "adds additional emails to #billing_external_emails" do
      @business.update! billing_email: "billing@example.com"
      errors = @business.add_billing_email("one@example.com")
      assert_empty errors
      errors = @business.add_billing_email("two@example.com")
      assert_empty errors
      assert_same_elements \
        ["one@example.com", "two@example.com"],
        @business.billing_external_emails.map(&:email)
    end
  end

  context "#mark_billing_email_primary" do
    test "marks email as primary when primary is nil" do
      @business.update! billing_email: nil
      email = create :billing_external_email, owner: @business
      original_email = email.email
      assert_same_elements [email.email], @business.billing_external_emails.map(&:email)

      errors = @business.mark_billing_email_primary(email)

      assert_empty errors
      assert_equal original_email, @business.billing_email
      assert_empty @business.reload.billing_external_emails
    end

    test "marks email as primary when primary is blank" do
      @business.update! billing_email: ""
      email = create :billing_external_email, owner: @business
      original_email = email.email
      assert_same_elements [email.email], @business.billing_external_emails.map(&:email)

      errors = @business.mark_billing_email_primary(email)

      assert_empty errors
      assert_equal original_email, @business.billing_email
      assert_empty @business.reload.billing_external_emails
    end

    test "marks email as primary when primary is present" do
      email = create :billing_external_email, owner: @business
      original_email = email.email
      assert_same_elements [email.email], @business.billing_external_emails.map(&:email)
      original_primary_email = @business.billing_email

      errors = @business.mark_billing_email_primary(email)

      assert_empty errors
      assert_equal original_email, @business.billing_email
      assert_same_elements [original_primary_email], @business.reload.billing_external_emails.map(&:email)
    end

    test "returns error when email is not associated with the Business" do
      other_email = create :billing_external_email, owner: create(:organization)
      email = create :billing_external_email, owner: @business
      original_email = email.email
      assert_same_elements [email.email], @business.billing_external_emails.map(&:email)
      original_primary_email = @business.billing_email

      errors = @business.mark_billing_email_primary(other_email)

      assert_equal ["Email not found"], errors
      assert_equal original_primary_email, @business.billing_email
      assert_same_elements [original_email], @business.reload.billing_external_emails.map(&:email)
    end

    test "returns error when email is invalid" do
      email = create :billing_external_email, owner: @business
      email.update_column :email, "notanemail"
      original_email = email.email
      assert_same_elements [email.email], @business.billing_external_emails.map(&:email)
      original_primary_email = @business.billing_email

      errors = @business.mark_billing_email_primary(email)

      assert_equal ["Email does not look like an email address"], errors
      assert_equal original_primary_email, @business.billing_email
      assert_same_elements [original_email], @business.reload.billing_external_emails.map(&:email)
    end
  end

  context "#billable?" do
    if GitHub.billing_enabled?
      test "returns true for environment where billing is enabled" do
        assert_predicate @business, :billable?
      end
    else
      test "returns false for environment where billing is disabled" do
        refute_predicate @business, :billable?
      end
    end
  end

  context "#has_credit_card?" do
    if GitHub.billing_enabled?
      test "returns false if a business has no credit card linked to their enterprise account" do
        refute_predicate @business, :has_credit_card?
      end

      test "returns true if a business has a credit card linked to their enterprise account" do
        payment_method = create(:payment_method, :zuora)
        payment_method.update_attribute(:customer, @business.customer)

        assert_predicate @business, :has_credit_card?
      end
    else
      test "returns false for environment where billing is disabled" do
        refute_predicate @business, :has_credit_card?
      end
    end
  end

  context "#has_paypal_account?" do
    if GitHub.billing_enabled?
      test "returns false if a business has no PayPal account linked to their enterprise account" do
        refute_predicate @business, :has_paypal_account?
      end

      test "returns true if a business has a PayPal account linked to their enterprise account" do
        payment_method = create(:paypal_payment_method, :zuora, paypal_email: @business.owners.first.email)
        payment_method.update_attribute(:customer, @business.customer)

        assert_predicate @business, :has_paypal_account?
      end
    else
      test "returns false for environment where billing is disabled" do
        refute_predicate @business, :has_paypal_account?
      end
    end
  end

  context "#has_valid_azure_subscription?" do
    if GitHub.billing_enabled?
      test "returns false if a business has no Azure subscription linked to their enterprise account" do
        refute_predicate @business, :has_valid_azure_subscription?
      end

      test "returns true if a business has an Azure subscription linked to their enterprise account" do
        assert_predicate @business_with_azure_subscription, :has_valid_azure_subscription?
      end

      test "returns false if a business has an invalid Azure subscription linked to their enterprise account" do
        Billing::Kv.store.set(@business_with_azure_subscription.customer.invalid_azure_subscription_id_key, "true", expires: Time.now + 1.day)
        refute_predicate @business_with_azure_subscription, :has_valid_azure_subscription?
      end
    end
  end

  context "#has_valid_payment_method?" do
    if GitHub.billing_enabled?
      test "returns false if a business has no payment method linked to their enterprise account" do
        assert_nil @business.payment_method
        refute @business.has_valid_payment_method?
      end

      test "returns true if a business has a valid credit card linked to their enterprise account" do
        payment_method = create(:payment_method, :zuora)
        payment_method.update_attribute(:customer, @business.customer)

        assert_predicate @business, :has_credit_card?
        assert_predicate @business, :has_valid_payment_method?
      end

      test "returns true if a business has a valid PayPal account linked to their enterprise account" do
        payment_method = create(:paypal_payment_method, :zuora, paypal_email: @business.owners.first.email)
        payment_method.update_attribute(:customer, @business.customer)

        assert_predicate @business, :has_paypal_account?
        assert_predicate @business, :has_valid_payment_method?
      end

      test "returns true if a business has a valid Azure subscription and is on a metered plan" do
        @business_with_azure_subscription.customer.update! metered_ghe: true
        assert_predicate @business_with_azure_subscription, :has_valid_azure_subscription?
        assert_predicate @business_with_azure_subscription, :has_valid_payment_method?
      end

      test "returns false if a business has a valid Azure subscription without a metered plan" do
        assert_predicate @business_with_azure_subscription, :has_valid_azure_subscription?
        refute_predicate @business_with_azure_subscription, :has_valid_payment_method?
      end

      test "returns true for metered business with valid credit card" do
        @business.update!(customer: (create :credit_card_customer, metered_ghe: true))
        @business.reload
        assert_predicate @business, :has_credit_card?
        assert_predicate @business, :has_valid_payment_method?
      end
    else
      test "returns false for environment where billing is disabled" do
        refute_predicate @business, :has_valid_payment_method?
      end
    end
  end

  context "#external_subscription?" do
    if GitHub.billing_enabled?
      test "returns false if a business has no subscription associated with their enterprise account" do
        assert_nil @business.plan_subscription
        refute_predicate @business, :external_subscription?
      end

      test "returns false if a business has no external subscription associated with their enterprise account" do
        plan_subscription = create(
          :billing_plan_subscription,
          customer: @business.customer,
          zuora_subscription_number: nil
        )

        assert_equal plan_subscription, @business.plan_subscription
        refute_predicate @business, :external_subscription?
      end

      test "returns true if a business has an external subscription associated with their enterprise account" do
        plan_subscription = create(
          :billing_plan_subscription,
          customer: @business.customer,
          zuora_subscription_number: "123"
        )

        assert_equal plan_subscription, @business.plan_subscription
        assert_predicate @business, :external_subscription?
      end
    else
      test "returns false for environment where billing is disabled" do
        refute_predicate @business, :external_subscription?
      end
    end
  end

  context "#customer_for" do
    test "returns customer associated with business" do
      assert_equal @business.customer, @business.customer_for(Customer::DEFAULT_PURPOSE)
    end
  end

  context "#billing_customer" do
    test "returns customer associated with business" do
      assert_equal @business.customer, @business.billing_customer
    end
  end

  context "#payment_processor_email" do
    test "returns billing_email of the business" do
      assert_equal @business.billing_email, @business.payment_processor_email
    end
  end

  context "#payment_processor_account_name" do
    test "returns slug of the business" do
      assert_equal @business.slug, @business.payment_processor_account_name
    end
  end

  context "#default_seats" do
    test "returns the number of seats for the Business" do
      assert_equal @business.default_seats, @business.seats
    end
  end

  context "PayPal support methods for business" do
    test "#billing_extra returns nil for business" do
      assert_nil @business.billing_extra
    end

    test "#vat_code returns nil for business" do
      assert_nil @business.vat_code
    end
  end

  context "#plan_duration" do
    if GitHub.billing_enabled?
      test "#yearly_plan? returns true for a business with yearly plan duration" do
        @business.update_attribute :plan_duration, Business::BillingDependency::YEARLY_PLAN

        assert_predicate @business, :yearly_plan?
      end

      test "#monthly_plan? returns true for a business with monthly plan duration" do
        @business.update_attribute :plan_duration, Business::BillingDependency::MONTHLY_PLAN

        assert_predicate @business, :monthly_plan?
      end

      test "instruments account.plan_change event when plan duration changes from yearly to monthly" do
        @business.update_attribute :plan_duration, Business::BillingDependency::YEARLY_PLAN

        assert_predicate @business, :yearly_plan?

        events = assert_performed_audit_entries(count: 1, only: "account.plan_change") do
          @business.update_attribute :plan_duration, Business::BillingDependency::MONTHLY_PLAN
        end

        expected_payload = {
          old_plan: GitHub::Plan.business_plus.name,
          plan: GitHub::Plan.business_plus.name,
          old_plan_duration: Business::BillingDependency::YEARLY_PLAN,
          plan_duration: Business::BillingDependency::MONTHLY_PLAN,
          old_seats: @business.seats,
          seats:  @business.seats,
          old_data_packs: @business.data_packs,
          asset_packs: @business.data_packs,
          tos_sha: TosAcceptance.current_sha
        }

        @business.reload
        assert_predicate @business, :monthly_plan?
        assert_subset_hash expected_payload, events.first
      end

      test "instruments account.plan_change event when plan duration changes from monthly to yearly" do
        @business.update_attribute :plan_duration, Business::BillingDependency::MONTHLY_PLAN

        assert_predicate @business, :monthly_plan?

        events = assert_performed_audit_entries(count: 1, only: "account.plan_change") do
          @business.update_attribute :plan_duration, Business::BillingDependency::YEARLY_PLAN
        end

        expected_payload = {
          old_plan: GitHub::Plan.business_plus.name,
          plan: GitHub::Plan.business_plus.name,
          old_plan_duration: Business::BillingDependency::MONTHLY_PLAN,
          plan_duration: Business::BillingDependency::YEARLY_PLAN,
          old_seats: @business.seats,
          seats:  @business.seats,
          old_data_packs: @business.data_packs,
          asset_packs: @business.data_packs,
          tos_sha: TosAcceptance.current_sha
        }

        @business.reload
        assert_predicate @business, :yearly_plan?
        assert_subset_hash expected_payload, events.first
      end
    end
  end

  context "#first_time_charge?" do
    test "returns false for a business with successful first-time billing_transactions" do
      customer = create(:customer, :zuora, billing_type: "card")
      @business.update_attribute(:customer, customer)
      plan_subscription = create(:billing_plan_subscription, :business_owned, customer: customer)

      create :billing_transaction,
        :business_owned,
        plan_subscription: plan_subscription,
        customer: customer,
        transaction_type: "first-time-paid-upgrade",
        last_status: :settled

      refute_predicate @business, :first_time_charge?
    end

    test "returns true for a business without successful first-time billing_transactions" do
      customer = create(:customer, :zuora, billing_type: "card")
      @business.update_attribute(:customer, customer)
      plan_subscription = create(:billing_plan_subscription, :business_owned, customer: customer)

      create :billing_transaction,
        :business_owned,
        plan_subscription: plan_subscription,
        customer: customer,
        last_status: :settled

      assert_predicate @business, :first_time_charge?
    end
  end

  context "#recurring_charge_type" do
    test "returns 'first-time-paid-upgrade' for a business without a successful first-time billing transaction" do
      customer = create(:customer, :zuora, billing_type: "card")
      @business.update_attribute(:customer, customer)
      plan_subscription = create(:billing_plan_subscription, :business_owned, customer: customer)

      create :billing_transaction,
        :business_owned,
        plan_subscription: plan_subscription,
        customer: customer,
        last_status: :settled

      assert_equal "first-time-paid-upgrade", @business.recurring_charge_type
    end

    test "returns 'recurring-charge' for a business with successful first time transactions" do
      customer = create(:customer, :zuora, billing_type: "card")
      @business.update_attribute(:customer, customer)
      plan_subscription = create(:billing_plan_subscription, :business_owned, customer: customer)

      create :billing_transaction,
        :business_owned,
        plan_subscription: plan_subscription,
        customer: customer,
        transaction_type: "first-time-paid-upgrade",
        last_status: :settled

      assert_equal "recurring-charge", @business.recurring_charge_type
    end
  end

  context "#recurring_charge" do
    if GitHub.billing_enabled?
      test "retries the charge for business with external subscription" do
        plan_subscription = create :billing_plan_subscription, :zuora, :business_owned
        business = plan_subscription.business
        business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
        assert_predicate business, :external_subscription?

        business.plan_subscription.expects(:retry_charge)
        business.recurring_charge
      end

      test "creates and synchronizes plan subscription for business transitioning to external subscription" do
        @business_with_self_serve_payment.customer.update! billing_end_date: 2.weeks.ago
        @business_with_self_serve_payment.reload
        assert_predicate @business_with_self_serve_payment, :should_transition_to_external_subscription?
        assert_nil @business_with_self_serve_payment.plan_subscription

        assert_enqueued_jobs 1, only: SynchronizePlanSubscriptionJob do
          @business_with_self_serve_payment.recurring_charge
          refute_nil @business_with_self_serve_payment.reload.plan_subscription
        end
      end

      test "processes a zero charge transaction for a business" do
        plan_subscription = create :billing_plan_subscription, :business_owned
        business = plan_subscription.business
        business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
        business.customer.update!(billing_end_date: 2.weeks.ago)
        business.payment_method.destroy!

        business.redeem_coupon(create(:coupon, discount: 25200, expires_at: GitHub::Billing.today + 2.months).code, actor: @owner)
        business.reload.recurring_charge

        assert_equal business.billing_transactions.first.amount_in_cents, 0.0
      end

      test "re-enables a disabled business with a coupon" do
        plan_subscription = create :billing_plan_subscription, :business_owned
        business = plan_subscription.business
        business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
        business.disable!
        assert_predicate business, :disabled?

        business.redeem_coupon(create(:coupon, discount: 25200, expires_at: GitHub::Billing.today + 2.months).code, actor: @owner)
        business.reload.recurring_charge

        refute_predicate business.reload, :disabled?
      end

      test "doesn't run charge with coupon for zuora businesses" do
        plan_subscription = create :billing_plan_subscription, :zuora, :business_owned
        business = plan_subscription.business
        business.customer.update! billing_type: Customer::BILLING_TYPE_CARD

        business.plan_subscription.expects(:retry_charge)
        business.expects(:recurring_charge_with_coupon).never

        business.recurring_charge
      end
    end
  end

  context "#process_zero_charge_transaction" do
    test "moves the billed_on date according to the bill cycle day if it's set" do
      travel_to Date.new(2021, 3, 26) do
        customer = create(:customer, :zuora, billing_type: "card")
        customer.update_attribute(:bill_cycle_day, 25)
        @business.update_attribute(:customer, customer)

        @business.reload
        @business.process_zero_charge_transaction

        assert_equal @business.reload.billed_on, Date.new(2021, 4, 25)
      end
    end

    test "handles moving the billed on date for months that have less days than the bill cycle day" do
      travel_to Date.new(2021, 4, 20) do
        customer = create(:customer, :zuora, billing_type: "card")
        customer.update_attribute(:bill_cycle_day, 31)
        @business.update_attribute(:customer, customer)

        @business.reload
        @business.process_zero_charge_transaction

        assert_equal @business.reload.billed_on, Date.new(2021, 4, 30)
      end
    end

    test "enables account if it should not be disabled" do
      @business.disable!
      refute @business.should_disable?

      @business.process_zero_charge_transaction

      assert @business.reload.enabled?, "Business should be enabled"
    end

    test "does not enable account if it should be disabled" do
      customer = create(:customer, :zuora, billing_type: "card")
      @business.update_attribute(:customer, customer)
      @business.disable!(reason: Billing::Public::BillingDisabledReasons::AuthorizationFailure)
      assert @business.reload.should_disable?

      @business.process_zero_charge_transaction

      refute @business.reload.enabled?, "Business should still be disabled"
    end

    test "updates the customer's bill cycle day if a customer exists and has no bill cycle day set" do
      customer = create(:customer, :zuora, billing_type: "card")
      @business.update_attribute(:customer, customer)
      @business.reload
      @business.customer.update!(bill_cycle_day: 0)

      @business.process_zero_charge_transaction

      @business.reload
      assert_equal @business.billed_on.day, @business.customer.bill_cycle_day
    end
  end if GitHub.billing_enabled?

  context "#log_zero_charge_transaction" do
    test "logs a zero charge transaction" do
      plan_subscription = create(:billing_plan_subscription, :zuora, customer: @business.customer)
      billing_transaction = @business.log_zero_charge_transaction

      assert_equal billing_transaction.user_login, @business.slug
      assert_equal billing_transaction.amount_in_cents, 0
    end

  end if GitHub.billing_enabled?

  context "#new_billed_on" do
    test "returns the correct value for a business on the yearly plan" do
      current_billed_on = @business.billed_on
      assert_equal @business.plan_duration, "year"

      assert_equal @business.new_billed_on(current_billed_on), current_billed_on + 1.year
    end

    test "returns the correct value for a business on the monthly plan" do
      current_billed_on = @business.billed_on
      @business.update(plan_duration: "month")
      assert_equal @business.plan_duration, "month"

      assert_equal @business.new_billed_on(current_billed_on), current_billed_on + 1.month
    end
  end if GitHub.billing_enabled?

  context "#payment_amount" do
    test "returns the payment amount for a business" do
      payment_amount = @business.payment_amount
      assert_equal payment_amount, 25200
    end

    test "returns a discounted payment amount for a business with a coupon" do
      @business.customer.update(billing_type: Customer::BILLING_TYPE_CARD)
      @business.redeem_coupon(@coupon.code, actor: @owner) # 10% off

      payment_amount = @business.payment_amount
      assert_equal payment_amount, 22680
    end

    test "returns a discount amount of a month off when the annual plan discount flag is set to true" do
      payment_amount = @business.payment_amount(plan_annual_discount: true)
      assert_equal payment_amount, 23100 # New total = $22500 - $2100 (one month)
    end

    test "does not return a discount amount of a month off when the annual plan discount flag is set to false" do
      payment_amount = @business.payment_amount(plan_annual_discount: false)
      assert_equal payment_amount, 25200
    end

    test "returns a discounted payment amount for a business with both a coupon and an annual plan discount" do
      @business.customer.update(billing_type: Customer::BILLING_TYPE_CARD)
      @business.redeem_coupon(@coupon.code, actor: @owner) # 10% off

      payment_amount = @business.payment_amount(plan_annual_discount: true)
      # After "one month free" discount: $25200 - $2100 = $23100
      # 10% coupon discount is added on top: $20790
      assert_equal payment_amount, 20790
    end

    test "does not incorporate the annual discount if the business is on the monthly billing cadence, even if flag is set to true" do
      @business.customer.update(billing_type: Customer::BILLING_TYPE_CARD)
      @business.update!(plan_duration: Business::BillingDependency::MONTHLY_PLAN)

      payment_amount = @business.payment_amount(plan_annual_discount: true)
      # 100 seats at 21$ per seat per month = $2100 per month
      assert_equal payment_amount, 2100  # No additional discount is applied
    end
  end if GitHub.billing_enabled?

  context "plan subscription" do
    if GitHub.billing_enabled?
      test "destroyed when the business is destroyed" do
        plan_subscription = create(:billing_plan_subscription, :zuora, :business_owned)
        plan_subscription.business.customer.update(billing_type: Customer::BILLING_TYPE_CARD)
        plan_subscription.business.reload
        plan_subscription.business.destroy

        assert_raises ActiveRecord::RecordNotFound do
          plan_subscription.reload
        end
      end

      test "create when external subscription not present" do
        only = [CheckForSpamJob, SynchronizePlanSubscriptionJob, TradeControls::ComplianceCheckJob, ProcessEmailDomainForReputationDataJob]
        perform_enqueued_jobs(only: only) do
          plan_subscription = create(:billing_plan_subscription, :business_owned)
          business = plan_subscription.business
          business.customer.update(billing_type: Customer::BILLING_TYPE_CARD)

          Billing::PlanSubscription::Synchronizer.expects(:create).once

          business.create_or_update_external_subscription!(force: true)
        end
      end

      test "synchronized with seat changes and zuora subscription" do
        synchronize_github_products_to_zuora

        zuora_successful_customer_account_creation(@business)
        @business.reload
        @business.customer.update(billing_type: Customer::BILLING_TYPE_CARD)

        only = [CheckForSpamJob, SynchronizePlanSubscriptionJob, UpdateLockedRepositoriesJob]
        perform_enqueued_jobs(only: only) do
          with_live_zuora("zuora_subscription/success_subscription_upgrade_seats_enterprise") do
            @business.seats = 5
            @business.save!
            @business.customer.create_plan_subscription!
            @business.reload

            assert @business.plan_subscription.present?
            assert @business.plan_subscription.zuora_subscription.present?
            zuora_subscription = @business.plan_subscription.zuora_subscription
            assert_equal 7, zuora_subscription.active_rate_plans.count
            business_rate_plan = zuora_subscription.active_rate_plans.detect do |rate_plan|
              rate_plan[:productName] == GitHub::Plan.business_plus.zuora_product_name
            end
            assert business_rate_plan
            assert_equal 2, business_rate_plan[:ratePlanCharges].count
            assert_equal 5, business_rate_plan[:ratePlanCharges].sum { |charge| charge[:quantity] }

            # Complely reload Business as otherwise the result of
            # external_subscription? is cached and the subscription is
            # not synced
            @business = Business.find(@business.id)
            @business.update(seats: 15)

            zuora_subscription = @business.plan_subscription.reload.zuora_subscription
            assert_equal 7, zuora_subscription.active_rate_plans.count
            business_rate_plan = zuora_subscription.active_rate_plans.detect do |rate_plan|
              rate_plan[:productName] == GitHub::Plan.business_plus.zuora_product_name
            end
            assert business_rate_plan
            assert_equal 2, business_rate_plan[:ratePlanCharges].count
            assert_equal 15, business_rate_plan[:ratePlanCharges].sum { |charge| charge[:quantity] }
          end
        end
      end

      test "not synchronized with seat changes when skip_update_external_subscription is set to true" do
        business = create(:business, seats: 50)
        create(:billing_plan_subscription, :business_owned, customer: business.customer, zuora_subscription_number: "A-12345")
        business.customer.update(billing_type: Customer::BILLING_TYPE_CARD)
        business.reload

        assert_enqueued_jobs 0, only: SynchronizePlanSubscriptionJob do
          business.skip_update_external_subscription = true
          business.update_attribute(:seats, 100)
        end

        assert_enqueued_jobs 1, only: SynchronizePlanSubscriptionJob do
          business.skip_update_external_subscription = false
          business.update_attribute(:seats, 200)
        end
      end
    end
  end

  context "manual dunning period" do
    if GitHub.billing_enabled?
      test "destroyed when the business is destroyed" do
        business = create(:business, :with_self_serve_payment)
        business.payment_method.update!(country: "IND")
        create :billing_plan_subscription, :zuora, customer: business.customer, balance_in_cents: 7_00
        assert_predicate business.customer, :requires_manual_transactions?

        manual_dunning_period = ::Billing::ManualDunningPeriod.create(customer: business.customer).run
        refute_nil manual_dunning_period

        if manual_dunning_period
          manual_dunning_period.business.reload
          manual_dunning_period.business.destroy

          assert_raises ActiveRecord::RecordNotFound do
            manual_dunning_period.reload
          end
        end
      end
    end
  end

  if GitHub.billing_enabled?
    context "#unable_to_bill?" do
      test "returns false when billing_attempts not present" do
        assert_equal 0, @business.billing_attempts
        refute_predicate @business, :unable_to_bill?
      end

      test "returns false when billing_attempts < 3" do
        @business.customer.update billing_attempts: 2
        refute_predicate @business, :unable_to_bill?
      end

      test "returns true when billing_attempts >= 3" do
        @business.customer.update billing_attempts: 3
        assert_predicate @business, :unable_to_bill?
      end
    end

    context "#billing_trouble?" do
      test "returns false when billing_attempts not present" do
        assert_equal 0, @business.billing_attempts
        refute_predicate @business, :billing_trouble?
      end

      test "returns false when billing_attempts < 3" do
        @business.customer.update billing_attempts: 2
        refute_predicate @business, :billing_trouble?
      end

      test "returns false when billing_attempts >= 3 but payment_amount 0" do
        @business.customer.update billing_attempts: 3
        @business.stubs(:payment_amount).returns(0)
        refute_predicate @business, :billing_trouble?
      end

      test "returns false when billing_attempts >= 3 and payment_amount > 0" do
        @business.customer.update billing_attempts: 3
        @business.stubs(:payment_amount).returns(10)
        assert_predicate @business, :billing_trouble?
      end
    end

    context "#manual_payment_due_date" do
      test "returns nil if the Business is not in manual dunning" do
        assert_nil @business.manual_dunning_period
        assert_nil @business.manual_payment_due_date
      end

      test "returns the manual dunning due date when the Business has a corresponding record" do
        manual_dunning_record = create :manual_dunning_period, customer: @business.customer
        assert_equal manual_dunning_record.due_date.to_date, @business.manual_payment_due_date
      end
    end

    context "#manual_dunning?" do
      test "returns false if the Business is not in manual dunning" do
        refute_predicate @business, :manual_dunning?
      end

      test "returns false if the Business is in manual dunning but balance is <= 0" do
        create :manual_dunning_period, customer: @business.customer
        refute_predicate @business.reload, :manual_dunning?
      end

      test "returns true if the Business is in manual dunning" do
        create \
          :billing_plan_subscription,
          :business_owned,
          balance_in_cents: 1000,
          customer: @business.customer
        create :manual_dunning_period, customer: @business.customer
        assert_predicate @business.reload, :manual_dunning?
      end
    end

    context "#enable!" do
      test "upgrades Business to business_plus plan" do
        @business.downgrade_to_free_plan
        assert_predicate @business, :downgraded_to_free_plan?
        refute_predicate @business, :enabled?

        @business.enable!

        refute_predicate @business, :downgraded_to_free_plan?
        assert_predicate @business, :enabled?
        assert_equal GitHub::Plan.business_plus, @business.plan
      end
    end

    context "#disable!" do
      test "downgrades Business to free plan" do
        refute_predicate @business, :downgraded_to_free_plan?
        refute_predicate @business, :disabled?

        @business.disable!

        assert_predicate @business, :downgraded_to_free_plan?
        assert_predicate @business, :disabled?
        assert_equal GitHub::Plan.free, @business.plan
      end

      test "downgrades Business-owned organizations to the free plan" do
        org1 = create :organization
        org2 = create :organization
        @business.add_organization(org1)
        @business.add_organization(org2)
        assert_equal GitHub::Plan.business_plus, org1.reload.plan
        assert_equal GitHub::Plan.business_plus, org2.reload.plan

        @business.disable!

        assert_equal GitHub::Plan.free, org1.reload.plan
        assert_equal GitHub::Plan.free, org2.reload.plan
      end

      test "enqueues CancelPastDueProductsJob when FF is enabled" do
        enable_feature_flag(:billing_cancel_past_due_products_for_business)
        assert_enqueued_jobs(1, only: [Billing::CancelPastDueProductsJob]) do
          @business.disable!
        end
      end
    end

    context "#should_disable?" do
      test "returns false for trial business whose trial conversion has been initiated" do
        @business_with_self_serve_payment.update! trial_expires_at: 2.weeks.from_now
        @business_with_self_serve_payment.initiate_trial_conversion
        @business_with_self_serve_payment.reload
        assert_predicate @business_with_self_serve_payment, :trial_conversion_initiated?

        refute_predicate @business_with_self_serve_payment.reload, :should_disable?
      end

      test "returns true for expired trial business whose trial conversion has not been initiated" do
        @business_with_self_serve_payment.update! trial_expires_at: 1.day.ago
        @business_with_self_serve_payment.reload
        assert_predicate @business_with_self_serve_payment, :trial_expired?
        refute_predicate @business_with_self_serve_payment, :trial_conversion_initiated?

        assert_predicate @business_with_self_serve_payment.reload, :should_disable?
      end

      test "returns true for businesses with any disabled reason" do
        @business_with_self_serve_payment.customer.update_disabled_reasons(Billing::Public::BillingDisabledReasons::AuthorizationFailure)
        assert_predicate @business_with_self_serve_payment.reload, :should_disable?
      end
    end

    context "#never_disable?" do
      test "returns true for business on invoiced payments" do
        assert_predicate @business, :invoiced?

        assert_predicate @business, :never_disable?
      end

      test "returns true for business whose trial conversion has been initiated" do
        @business_with_self_serve_payment.update! trial_expires_at: 2.weeks.from_now
        @business_with_self_serve_payment.initiate_trial_conversion
        @business_with_self_serve_payment.reload
        assert_predicate @business_with_self_serve_payment, :trial_conversion_initiated?

        assert_predicate @business_with_self_serve_payment.reload, :never_disable?
      end
    end

    context "business_billing_trouble notice" do
      test "enqueues job to set business_billing_trouble notice if Business has billing trouble" do
        @business.stubs(:billing_trouble?).returns(true)

        assert_enqueued_jobs(1, queue: "billing", only: Billing::BusinessBillingTroubleCheckJob) do
          @business.customer.update(updated_at: 1.day.ago)
        end
      end

      test "does not enqueue job to set business_billing_trouble notice if Business does not have billing trouble" do
        @business.stubs(:billing_trouble?).returns(false)

        assert_enqueued_jobs(0, queue: "billing", only: Billing::BusinessBillingTroubleCheckJob) do
          @business.customer.update(updated_at: 1.day.ago)
        end
      end
    end

    context "#update_billing_date" do
      test "update billing_date does not validate billing email" do
        enable_feature_flag(:skip_billing_email_domain_validation)
        bad_email = "zero@dietcoke.ze.cx"
        assert UserEmail::DisposableEmailsDependency.disposable_email?(bad_email)
        @business.update_column :billing_email, bad_email
        refute_predicate @business, :valid?

        billing_date = GitHub::Billing.today
        @business.update_billing_date(next_billing_date: billing_date)
        @business.reload

        assert_equal billing_date, @business.billed_on
      end

      test "updates billing end date to the day before the next billing date" do
        billing_date = GitHub::Billing.today
        @business.update_billing_date(next_billing_date: billing_date, billing_attempts: 0)
        @business.reload

        assert_equal billing_date, @business.billed_on
        assert_equal 0, @business.billing_attempts
      end

      test "preserves the existing billing_attempts value if none is provided" do
        billing_date = GitHub::Billing.today
        @business.increment_billing_attempts
        assert_equal @business.billing_attempts, 1

        @business.update_billing_date(next_billing_date: billing_date)
        @business.reload

        assert_equal billing_date, @business.billed_on
        assert_equal 1, @business.billing_attempts
      end

      test "logs when the billing date is updated" do
        billing_date = GitHub::Billing.today
        @business.update_billing_date(next_billing_date: billing_date, billing_attempts: 0)
        @business.reload
        expected_log = {
          "Body" => "Setting billing_term_ends_at",
          "code.namespace" => "Business",
          "code.function" => "billing_term_ends_at=",
          "gh.business.id" => @business.id,
          "gh.business.slug" => @business.slug,
          "gh.billing.billing_term_ends_at.new" => billing_date
        }
        assert_logged(**expected_log) do
          @business.billing_term_ends_at = billing_date
        end
      end
    end

    context "#transfer_billing_from_organization" do
      test "transfers organization's Zuora account and subscription to the Business" do
        organization = create :organization, admin: @owner, plan: "business_plus"
        zuora_successful_customer_account_creation(organization)

        with_live_zuora("zuora/transfer_zuora_subscription_from_organization") do
          business = create :business
          organization.reload

          transferred_customer = organization.customer  # Get current customer and subscription to be used for future comparison
          transferred_subscription = organization.plan_subscription
          refute_nil transferred_customer
          refute_nil transferred_subscription
          assert_equal transferred_customer.name, organization.name

          business.transfer_billing_from_organization(organization, @owner)

          assert_nil organization.reload.customer  # Organization should no longer be associated with the customer account or subscription
          assert_nil organization.plan_subscription
          assert_equal business.reload.customer, transferred_customer.reload # Customer and plan subscription should now be attached to the Business
          assert_equal business.customer.plan_subscription, transferred_subscription.reload
          assert_equal transferred_customer.name, business.name # The customer's name is updated to match the Business
        end
      end

      test "transfers organization's trade screening record to the Business" do
        user = create(:user, :verified)
        organization = create :organization, :with_account_screening_profile, admin: user, plan: "business_plus"
        organization.trade_screening_record.update!(msft_trade_screening_status: "no_hit")
        organization.terms_of_service.update(type: "Corporate", actor: user)
        assert organization.trade_screening_record.valid?(:entity)
        assert_predicate organization.trade_screening_record, :valid?
        assert_equal organization.trade_screening_record.msft_trade_screening_status, "no_hit"

        zuora_successful_customer_account_creation(organization)

        with_live_zuora("zuora/transfer_zuora_subscription_from_organization") do
          business = create :business
          organization.reload

          trade_screening_record = organization.trade_screening_record
          refute_nil trade_screening_record

          business.transfer_billing_from_organization(organization, user)

          assert_equal business.reload.trade_screening_record, trade_screening_record.reload # Trade screening record should now be attached to the Business
          assert_equal trade_screening_record.owner_id, business.id  # Owner of the TSR is now the business
          assert_equal trade_screening_record.msft_trade_screening_status, "no_hit"
          assert_equal business.trade_screening_record.external_uuid, trade_screening_record.external_uuid
        end
      end

      test "transfers organization's billing end date to the Business" do
        organization = create :organization, admin: @owner, plan: "business_plus"
        zuora_successful_customer_account_creation(organization)

        with_live_zuora("zuora/transfer_billing_end_date_from_organization") do
          business = create :business
          organization.billed_on = GitHub::Billing.today + 1.year
          organization.save!
          organization.reload

          billed_on_date = organization.billed_on
          refute_nil billed_on_date

          business.transfer_billing_from_organization(organization, @owner)

          assert_equal business.reload.customer.billing_end_date.to_date, billed_on_date.to_date - 1.day
        end
      end

      test "transfers organization's active marketplace items to the Business" do
        organization = create :organization, admin: @owner, plan: "business_plus", billing_type: "card"
        zuora_successful_customer_account_creation(organization)

        with_live_zuora("zuora/transfer_marketplace_items_of_upgrading_enterprise_plan_org") do
          listing_plan = create :marketplace_listing_plan, :verified_listing
          ano_listing_plan = create :marketplace_listing_plan, :verified_listing
          qty = 99
          org_subscription_item = create :billing_subscription_item, plan_subscription: organization.plan_subscription,
            subscribable: listing_plan, quantity: qty
          cancelled_org_subscription_item = create :billing_subscription_item, plan_subscription: organization.plan_subscription,
            subscribable: ano_listing_plan, quantity: 0

          business = create :business
          organization.reload

          assert_equal 0, business.subscription_items.count

          business.transfer_billing_from_organization(organization, @owner)

          assert_equal 2, business.subscription_items.count

          business_subscription_item = business.subscription_items.find { |si| si.quantity == qty }
          cancelled_business_subscription_item = business.subscription_items.find { |si| si.quantity == 0 }

          assert_equal org_subscription_item.subscribable, business_subscription_item.subscribable
          assert_equal qty, business_subscription_item.quantity

          assert_equal cancelled_org_subscription_item.subscribable, cancelled_business_subscription_item.subscribable

          assert_equal organization.id, business_subscription_item.organization_id
          assert_equal organization.id, cancelled_business_subscription_item.organization_id
        end
      end

      test "transfers pending cancellation status of marketplace item" do
        organization = create :organization, admin: @owner, plan: "business_plus", billing_type: "card"
        zuora_successful_customer_account_creation(organization)

        with_live_zuora("zuora/transfer_marketplace_items_of_upgrading_enterprise_plan_org") do
          listing_plan = create :marketplace_listing_plan, :verified_listing

          org_pending_cancellation = create(:billing_pending_plan_change,
            plan: nil,
            plan_duration: nil,
            seats: 0,
            user: organization,
            active_on: 1.week.from_now
          )
          org_subscription_item = create(:billing_subscription_item,
            quantity: 99,
            plan_subscription: organization.plan_subscription,
            subscribable: listing_plan,
          )
          pending_subscription_item_change = create(:billing_pending_subscription_item_change,
            quantity: 0,
            subscribable: listing_plan,
            pending_plan_change: org_pending_cancellation,
          )

          business = create :business
          organization.reload

          assert_equal 0, business.subscription_items.count

          business.transfer_billing_from_organization(organization, @owner)

          assert_equal 1, business.subscription_items.count
          assert_equal 0, organization.active_marketplace_listing_subscription_items.count

          assert marketplace_item = business.subscription_items.for_organization(organization).first

          assert marketplace_item.pending_subscription_item_change.present?
          assert marketplace_item.pending_cancellation?
          assert_nil marketplace_item.pending_subscription_item_change.user
          assert_equal business.customer, marketplace_item.pending_subscription_item_change.customer
          assert_equal organization, marketplace_item.pending_subscription_item_change.organization
        end
      end

      test "transfers organization's sponsors subscription items to the Business" do
        organization = create :organization, :sponsorable, admin: @owner, plan: "business_plus", billing_type: "card"

        zuora_successful_customer_account_creation(organization)

        with_live_zuora("zuora/transfer_sponsors_items_of_upgrading_enterprise_plan_org") do
          sponsorship_1 = create(:sponsorship, sponsor: organization)
          sponsorship_2 = create(:sponsorship, sponsor: organization)

          qty = 5
          org_sponsor_subscription_item = sponsorship_1.subscription_item
          org_sponsor_subscription_item.update(quantity: qty)
          cancelled_org_sponsor_subscription_item = sponsorship_2.subscription_item
          cancelled_org_sponsor_subscription_item.update(quantity: 0)

          business = create :business
          organization.reload

          assert_equal 0, business.subscription_items.for_sponsors_tiers.count
          assert_equal 2, organization.subscription_items.for_sponsors_tiers.count

          business.transfer_billing_from_organization(organization, @owner)

          assert_equal 2, business.subscription_items.for_sponsors_tiers.count
          assert_equal 0, organization.subscription_items.for_sponsors_tiers.count

          business_subscription_item = business.subscription_items.find { |si| si.quantity == qty }
          cancelled_business_subscription_item = business.subscription_items.find { |si| si.quantity == 0 }

          assert_equal org_sponsor_subscription_item.subscribable, business_subscription_item.subscribable
          assert_equal qty, business_subscription_item.quantity

          assert_equal cancelled_org_sponsor_subscription_item.subscribable, cancelled_business_subscription_item.subscribable

          assert_equal organization.id, business_subscription_item.organization_id
          assert_equal organization.id, cancelled_business_subscription_item.organization_id
        end
      end

      test "transfers pending cancellation status of the sponsors subscription item" do
        organization = create :organization, :sponsorable, admin: @owner, plan: "business_plus", billing_type: "card"
        zuora_successful_customer_account_creation(organization)

        with_live_zuora("zuora/transfer_sponsors_items_of_upgrading_enterprise_plan_org") do
          sponsorship = create(:sponsorship, sponsor: organization)

          org_sponsor_subscription_item = sponsorship.subscription_item
          org_sponsor_subscription_item.update(quantity: 50)

          org_pending_cancellation = create(:billing_pending_plan_change,
            plan: nil,
            plan_duration: nil,
            seats: 0,
            user: organization,
            active_on: 1.week.from_now
          )
          pending_subscription_item_change = create(:billing_pending_subscription_item_change,
            quantity: 0,
            subscribable: org_sponsor_subscription_item.subscribable,
            pending_plan_change: org_pending_cancellation,
          )

          business = create :business
          organization.reload

          assert_equal 0, business.subscription_items.for_sponsors_tiers.count
          assert_equal 1, organization.subscription_items.for_sponsors_tiers.count

          business.transfer_billing_from_organization(organization, @owner)

          assert_equal 1, business.subscription_items.for_sponsors_tiers.count
          assert_equal 0, organization.subscription_items.for_sponsors_tiers.count

          assert sponsors_subscription_item = business.subscription_items.for_sponsors_tiers.for_organization(organization).first

          assert sponsors_subscription_item.pending_subscription_item_change.present?
          assert sponsors_subscription_item.pending_cancellation?
          assert_nil sponsors_subscription_item.pending_subscription_item_change.user
          assert_equal business.customer, sponsors_subscription_item.pending_subscription_item_change.customer
          assert_equal organization, sponsors_subscription_item.pending_subscription_item_change.organization
        end
      end

      test "preserves organization's restricted trade screening status when transferring to the Business" do
        user = create(:user, :verified)
        organization = create :organization, :with_account_screening_profile, admin: user, plan: "business_plus"
        organization.terms_of_service.update(type: "Corporate", actor: user)
        organization.trade_screening_record.update!(msft_trade_screening_status: "lic_a")

        assert organization.trade_screening_record.valid?(:entity)
        assert_predicate organization.trade_screening_record, :valid?
        assert_equal organization.trade_screening_record.msft_trade_screening_status, "lic_a"

        zuora_successful_customer_account_creation(organization)

        with_live_zuora("zuora/transfer_zuora_subscription_from_organization") do
          business = create :business
          organization.reload

          trade_screening_record = organization.trade_screening_record
          refute_nil trade_screening_record

          business.transfer_billing_from_organization(organization, user)

          assert_equal business.reload.trade_screening_record, trade_screening_record.reload # Trade screening record should now be attached to the Business
          assert_equal business.trade_screening_record.msft_trade_screening_status, "lic_a"
        end
      end

      test "does not transfer organization's Zuora account and subscription to the Business if organization is invoiced" do
        organization = create :organization, admin: @owner, plan: "business_plus", billing_type: "invoice"
        zuora_successful_customer_account_creation(organization)

        with_live_zuora("zuora/transfer_zuora_subscription_from_organization") do
          business = create :business
          organization.reload
          create(:billing_plan_subscription, :zuora, user: organization)

          transferred_customer = organization.customer  # Get current customer and subscription to be used for future comparison
          transferred_subscription = organization.plan_subscription
          refute_nil transferred_customer
          refute_nil transferred_subscription

          business.transfer_billing_from_organization(organization, @owner)

          refute_nil organization.customer  # Organization should still be associated with the customer account or subscription
          refute_nil organization.plan_subscription
          refute_equal business.customer, transferred_customer.reload  # Customer and plan subscription should not be attached to the Business
          refute_equal business.customer.plan_subscription, transferred_subscription.reload
        end
      end

      test "does not transfer organization's Zuora account and subscription to the Business if organization is not on business_plus plan" do
        organization = create :organization, admin: @owner, plan: "business"
        zuora_successful_customer_account_creation(organization)

        with_live_zuora("zuora/transfer_zuora_subscription_from_organization") do
          business = create :business
          organization.reload

          transferred_customer = organization.customer  # Get current customer and subscription to be used for future comparison
          transferred_subscription = organization.plan_subscription
          refute_nil transferred_customer
          refute_nil transferred_subscription

          business.transfer_billing_from_organization(organization, @owner)

          refute_nil organization.customer  # Organization should still be associated with the customer account or subscription
          refute_nil organization.plan_subscription
          refute_equal business.customer, transferred_customer.reload  # Customer and plan subscription should not be attached to the Business
          refute_equal business.customer.plan_subscription, transferred_subscription.reload
        end
      end

      test "does not transfer organization's Zuora account to the Business if plan subscription does not exist" do
        organization = create :organization, admin: @owner, plan: "business_plus", billing_type: "card"
        zuora_successful_customer_account_creation(organization)

        with_live_zuora("zuora/transfer_zuora_subscription_from_organization") do
          business = create :business
          organization.plan_subscription = nil
          organization.reload

          transferred_customer = organization.customer  # Get current customer and subscription to be used for future comparison
          transferred_subscription = organization.plan_subscription
          refute_nil transferred_customer
          assert_nil transferred_subscription

          business.transfer_billing_from_organization(organization, @owner)

          refute_nil organization.customer  # Organization should still be associated with the customer account or subscription
          assert_nil organization.plan_subscription
          refute_equal business.customer, transferred_customer.reload  # Customer and plan subscription should not be attached to the Business
          assert_nil business.customer.plan_subscription
        end
      end

      test "transfers enterprise-plan organization's coupon to the business" do
        business_plus_card_org = create :organization, admin: @owner, plan: "business_plus"
        coupon = create(:coupon, plan: "business_plus", discount: "100%")
        business_plus_card_org.redeem_coupon(coupon.code, actor: @owner)
        zuora_successful_customer_account_creation(business_plus_card_org)

        with_live_zuora("zuora/transfer_zuora_subscription_from_organization") do
          business = create :business
          business_plus_card_org.reload

          transferred_customer = business_plus_card_org.customer  # Get current customer and subscription to be used for future comparison
          transferred_subscription = business_plus_card_org.plan_subscription
          refute_nil transferred_customer
          refute_nil transferred_subscription
          assert_equal transferred_customer.name, business_plus_card_org.name

          business.transfer_billing_from_organization(business_plus_card_org, @owner)

          assert_nil business_plus_card_org.plan_subscription
          assert_equal business.reload.customer, transferred_customer.reload # Customer and plan subscription should now be attached to the Business
          assert_equal business.customer.plan_subscription, transferred_subscription.reload
          assert_equal transferred_customer.name, business.name # The customer's name is updated to match the Business
          assert_predicate business.reload, :has_an_active_coupon?
        end
      end

      test "transfers enterprise-plan organization's coupon to the business, even if the org does not have a plan subscription" do
        disable_feature_flag(:lowercased_opt_out_org_to_ea_upgrade)
        business_plus_card_org = create(:business_plus_organization, admin: @owner, billing_type: "card")
        business = create :business
        coupon = create(:coupon, plan: "business_plus", discount: "100%")
        business_plus_card_org.redeem_coupon(coupon.code, actor: @owner)

        assert_predicate business_plus_card_org, :eligible_for_upgrade_to_enterprise?
        assert_predicate business_plus_card_org, :has_an_active_coupon?
        assert_nil business_plus_card_org.plan_subscription
        refute_predicate business, :has_an_active_coupon?

        business.transfer_billing_from_organization(business_plus_card_org, @owner)

        assert_predicate business.reload, :has_an_active_coupon?
      end

      test "transfers the billing transactions associated with the organization, as well as those associated with the organization's customer, to the newly created EA's customer, and deduplicates them" do
        business_plus_card_org = create :organization, admin: @owner, plan: "business_plus"
        business = create :business
        zuora_successful_customer_account_creation(business_plus_card_org)
        create(:billing_transaction, user: business_plus_card_org, customer: business_plus_card_org.customer)
        create(:billing_transaction, user: business_plus_card_org, customer: nil)
        all_org_billing_transactions = business_plus_card_org.billing_transactions + business_plus_card_org.customer.billing_transactions

        assert_equal business_plus_card_org.customer.billing_transactions.count, 1
        assert_equal business_plus_card_org.billing_transactions.count, 2
        assert_includes business_plus_card_org.billing_transactions, \
                        business_plus_card_org.customer.billing_transactions.first

        business.transfer_billing_from_organization(business_plus_card_org, @owner)

        assert_equal all_org_billing_transactions.count, 3
        assert_equal all_org_billing_transactions.uniq.count, 2
        assert_same_elements business.reload.billing_transactions,\
                              all_org_billing_transactions.uniq
      end
    end

    context "#transfer_marketplace_purchases_from_org_to_business" do
      test "transfers org's marketplace subscription items to business" do
        ano_listing_plan = create :marketplace_listing_plan, :verified_listing
        qty = 99
        org_subscription_item = create :billing_subscription_item, plan_subscription: @org_plan_subscription,
          subscribable: @listing_plan, quantity: qty
        cancelled_org_subscription_item = create :billing_subscription_item, plan_subscription: @org_plan_subscription,
          subscribable: ano_listing_plan, quantity: 0
        @business_to_upgrade.enable_self_serve_payments

        assert_equal 0, @business_to_upgrade.subscription_items.count

        @business_to_upgrade.transfer_marketplace_purchases_from_org_to_business(@org, @owner)

        assert_equal 2, @business_to_upgrade.subscription_items.count

        business_subscription_item = @business_to_upgrade.subscription_items.find { |si| si.quantity == qty }
        cancelled_business_subscription_item = @business_to_upgrade.subscription_items.find { |si| si.quantity == 0 }

        assert_equal org_subscription_item.subscribable, business_subscription_item.subscribable
        assert_equal qty, business_subscription_item.quantity

        assert_equal cancelled_org_subscription_item.subscribable, cancelled_business_subscription_item.subscribable

        org_subscription_item.reload
        assert_predicate org_subscription_item.quantity, :zero?
        assert_equal @org.id, business_subscription_item.organization_id
        assert_equal @org.id, cancelled_business_subscription_item.organization_id
      end

      test "re-transfers org's marketplace subscription items to business" do
        qty = 99
        org_subscription_item = create :billing_subscription_item, plan_subscription: @org_plan_subscription,
          subscribable: @listing_plan, quantity: qty
        @business_to_upgrade.enable_self_serve_payments

        business_plan_subscription = create :billing_plan_subscription, :business_owned, customer: @business_to_upgrade.customer
        old_org_ea_subscription_item = create :billing_subscription_item, plan_subscription: business_plan_subscription,
          subscribable: @listing_plan, quantity: 0, organization_id: @org.id

        assert_equal 1, @business_to_upgrade.subscription_items.count

        @business_to_upgrade.transfer_marketplace_purchases_from_org_to_business(@org, @owner)

        assert_equal 1, @business_to_upgrade.subscription_items.count

        business_subscription_item = @business_to_upgrade.subscription_items.find { |si| si.quantity == qty }

        assert_equal org_subscription_item.subscribable, business_subscription_item.subscribable
        assert_equal qty, business_subscription_item.quantity

        org_subscription_item.reload
        assert_predicate org_subscription_item.quantity, :zero?
        assert_equal @org.id, business_subscription_item.organization_id
      end

      test "sets trial end date to original trial date if app still in trial at time of transfer" do
        org_trial_end = create(:billing_pending_plan_change,
          plan: nil,
          plan_duration: nil,
          seats: nil,
          user: @org,
          active_on: 1.week.from_now
        )
        org_subscription_item = create(:billing_subscription_item,
          plan_subscription: @org_plan_subscription,
          subscribable: @listing_plan,
          free_trial_ends_on: 1.week.from_now
        )
        create(:billing_pending_subscription_item_change,
          free_trial: true,
          subscribable: @listing_plan,
          pending_plan_change: org_trial_end,
        )

        @business_to_upgrade.enable_self_serve_payments

        assert_equal 0, @business_to_upgrade.subscription_items.count

        @business_to_upgrade.transfer_marketplace_purchases_from_org_to_business(@org, @owner)

        assert_equal 1, @business_to_upgrade.subscription_items.count
        assert_equal 0, @org.active_marketplace_listing_subscription_items.count

        business_subscription_item = @business_to_upgrade.subscription_items.last
        assert_equal org_subscription_item.free_trial_ends_on, business_subscription_item.free_trial_ends_on
        assert business_subscription_item.has_pending_cycle_change?
        refute org_subscription_item.has_pending_cycle_change?
        assert_nil business_subscription_item.pending_subscription_item_change.user
        assert_equal @business_to_upgrade.customer, business_subscription_item.pending_subscription_item_change.customer
        assert_equal @org, business_subscription_item.pending_subscription_item_change.organization
      end

      test "transfers pending cancellation and ensure doesn't apply to other orgs with same plan" do
        business_plan_subscription = create :billing_plan_subscription, :business_owned, customer: @business_to_upgrade.customer
        existing_ea_org = create :organization, business: @business_to_upgrade, admin: @business_to_upgrade.owners.first
        create(:billing_subscription_item,
          quantity: 2,
          plan_subscription: business_plan_subscription,
          subscribable: @listing_plan,
          organization: existing_ea_org
        )

        org_pending_cancellation = create(:billing_pending_plan_change,
          plan: nil,
          plan_duration: nil,
          seats: 0,
          user: @org,
          active_on: 1.week.from_now
        )
        org_subscription_item = create(:billing_subscription_item,
          quantity: 99,
          plan_subscription: @org_plan_subscription,
          subscribable: @listing_plan,
        )
        create(:billing_pending_subscription_item_change,
          quantity: 0,
          subscribable: @listing_plan,
          pending_plan_change: org_pending_cancellation,
        )

        @business_to_upgrade.enable_self_serve_payments

        assert_equal 1, @business_to_upgrade.subscription_items.count

        @business_to_upgrade.transfer_marketplace_purchases_from_org_to_business(@org, @owner)

        assert_equal 2, @business_to_upgrade.subscription_items.count
        assert_equal 0, @org.active_marketplace_listing_subscription_items.count
        refute org_subscription_item.has_pending_cycle_change?

        assert transferred = @business_to_upgrade.subscription_items.for_organization(@org).first
        assert existing = @business_to_upgrade.subscription_items.for_organization(existing_ea_org).first

        assert transferred.pending_subscription_item_change.present?
        assert transferred.pending_cancellation?
        assert_nil transferred.pending_subscription_item_change.user
        assert_equal @business_to_upgrade.customer, transferred.pending_subscription_item_change.customer
        assert_equal @org, transferred.pending_subscription_item_change.organization

        refute existing.pending_subscription_item_change.present?
        refute existing.pending_cancellation?
      end

      test "does not transfer org's marketplace subscription items to business if business does not have self-serve payments enabled" do
        create :billing_subscription_item, plan_subscription: @org_plan_subscription, subscribable: @listing_plan, quantity: 99

        assert_equal 0, @business_to_upgrade.subscription_items.count

        @business_to_upgrade.transfer_marketplace_purchases_from_org_to_business(@org, @owner)

        assert_equal 0, @business_to_upgrade.subscription_items.count
        assert_equal 1, @org.active_marketplace_listing_subscription_items.count
      end
    end

    context "#latest_bill_balance" do
      test "returns zero balance for business without a Zuora account" do
        @business.customer.update(zuora_account_id: nil, zuora_account_number: nil)
        @business.reload

        assert_nil @business.zuora_account
        assert_equal 0, @business.latest_bill_balance
      end

      test "returns latest bill balance for business from its zuora metrics" do
        with_live_zuora("zuora/enterprise_metrics_latest_bill_balance") do
          zuora_account_id = "8ad085518098b8b80180aeff1ee56303"
          @business.customer.update_attribute(:zuora_account_id, zuora_account_id)
          @business.reload

          assert_equal 25200.0, @business.latest_bill_balance
        end
      end
    end

    context "#earliest_due_invoice" do
      test "returns nil for business without a Zuora account" do
        @business.customer.update(zuora_account_id: nil, zuora_account_number: nil)
        @business.reload

        assert_nil @business.zuora_account
        assert_nil @business.latest_bill
      end

      test "returns earliest bill due date for business with unpaid invoices" do
        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([
          create(:zuora_invoice, amount: 25200, dueDate: (GitHub::Billing.today - 1.month).to_s),
          create(:zuora_invoice, amount: 12600, dueDate: GitHub::Billing.today.to_s),
        ])
        Billing::Zuora::Invoice.any_instance.stubs(:invoice_items).returns([])

        assert_equal (GitHub::Billing.today - 1.month).to_s, @business.earliest_due_invoice.due_date
      end

      test "returns nil for business without a positive balance invoice" do
        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([])

        assert_nil @business.earliest_due_invoice
      end
    end

    context "#latest_bill" do
      test "returns nil for business without a Zuora account" do
        @business.customer.update(zuora_account_id: nil, zuora_account_number: nil)
        @business.reload

        assert_nil @business.zuora_account
        assert_nil @business.latest_bill
      end

      test "returns latest bill due date for business with unpaid invoices" do
        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([
          create(:zuora_invoice, amount: 25200, dueDate: (GitHub::Billing.today - 1.month).to_s),
          create(:zuora_invoice, amount: 12600, dueDate: GitHub::Billing.today.to_s),
        ])
        Billing::Zuora::Invoice.any_instance.stubs(:invoice_items).returns([])

        assert_equal GitHub::Billing.today - 1.month, @business.latest_bill[:due_date]
      end

      test "returns nil for business without a positive balance invoice" do
        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([])

        assert_nil @business.latest_bill
      end
    end

    context "#will_be_expired?" do
      test "returns false" do
        refute_predicate @business, :will_be_expired?
      end
    end

    context "#next_billing_date" do
      test "returns billed_on if billed_on is after today" do
        billed_on = GitHub::Billing.timezone.local(2016, 8, 10).to_billing_date
        @business.update_attribute :billing_term_ends_at, billed_on - 1.day

        travel_to(GitHub::Billing.timezone.local(2016, 7, 10)) do
          assert_equal "2016-08-10", @business.next_billing_date.strftime("%F")
        end
      end

      test "returns today if billed_on is in the past" do
        billed_on = GitHub::Billing.timezone.local(2015, 5, 5).to_billing_date
        @business.update_attribute :billing_term_ends_at, billed_on - 1.day

        travel_to(GitHub::Billing.timezone.local(2016, 7, 10)) do
          assert_equal "2016-07-10", @business.next_billing_date.strftime("%F")
        end
      end

      test "returns today if billing_term_ends_at is nil" do
        @business.update_attribute :billing_term_ends_at, nil

        travel_to(GitHub::Billing.timezone.local(2016, 7, 10)) do
          assert_equal "2016-07-10", @business.next_billing_date.strftime("%F")
        end
      end

      test "returns first day of next month if billing platform" do
        @business.customer.update!(billed_via_billing_platform: true)
        billed_on = GitHub::Billing.timezone.local(2016, 7, 10).to_billing_date
        @business.customer.update_attribute :bill_cycle_day, 1
        travel_to(GitHub::Billing.timezone.local(2016, 7, 11)) do
          assert_equal "2016-08-01", @business.next_billing_date.strftime("%F")
        end
      end

      test "returns last day of next month even if bill cycle day is bigger than the number of days in a given month if billing platform" do
        @business.customer.update!(billed_via_billing_platform: true)
        billed_on = GitHub::Billing.timezone.local(2024, 8, 31).to_billing_date
        @business.customer.update_attribute :bill_cycle_day, 31
        travel_to(GitHub::Billing.timezone.local(2024, 8, 31)) do
          assert_equal "2024-09-30", @business.next_billing_date.strftime("%F")
        end
      end
    end

    context "#bill_overdue?" do
      test "returns true if billing_trouble? is true" do
        @business.set_billing_attempts(3) # Simulate billing trouble
        assert @business.bill_overdue?, "Expected overdue when billing_trouble? is true"
        @business.set_billing_attempts(0) # Reset billing attempts
      end

      test "returns false when feature flag is disabled and there is no bill" do
        disable_feature_flag(:billing_use_earliest_invoice_due_date_for_latest_bill)
        @business.customer.destroy! # Ensure there is no bill
        refute @business.bill_overdue?, "Expected not overdue when there is no bill and feature flag is disabled"
        @business.customer = create(:customer, business: @business) # Restore customer for other tests
      end

      test "feature flag disabled: returns false when has bill and today is on or before latest_bill's due_date" do
        disable_feature_flag(:billing_use_earliest_invoice_due_date_for_latest_bill)
        tomorrow = GitHub::Billing.today + 1
        create(:billing_sales_serve_plan_subscription, customer: @business.customer, billing_start_date: tomorrow)
        @business.customer.update!(billing_end_date: tomorrow)
        refute @business.bill_overdue?, "Expected not overdue when today's date is on or before latest_bill due date"
      end

      test "returns true when feature flag is enabled and the latest bill's due date is in the past" do
        enable_feature_flag(:billing_use_earliest_invoice_due_date_for_latest_bill)
        yesterday = GitHub::Billing.today - 1

        # Create subscription and set up invoice stubs
        create(:billing_sales_serve_plan_subscription, customer: @business.customer, billing_start_date: yesterday)
        @business.customer.update!(billing_end_date: yesterday)

        # Stub Zuora invoice behavior
        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([
          create(:zuora_invoice, amount: 25200, dueDate: yesterday.to_s),
          create(:zuora_invoice, amount: 12600, dueDate: (GitHub::Billing.today + 1.day).to_s)
        ])
        Billing::Zuora::Invoice.any_instance.stubs(:invoice_items).returns([])

        assert @business.bill_overdue?, "Expected overdue when feature flag is enabled and latest bill's due date is in the past"
      end

      test "returns false when feature flag is enabled but no open invoices exist" do
        enable_feature_flag(:billing_use_earliest_invoice_due_date_for_latest_bill)
        today = GitHub::Billing.today

        # Create subscription with current date
        create(:billing_sales_serve_plan_subscription, customer: @business.customer, billing_start_date: today)
        @business.customer.update!(billing_end_date: today)

        # Stub Zuora to return empty invoice list
        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([])
        Billing::Zuora::Invoice.any_instance.stubs(:invoice_items).returns([])
        refute @business.bill_overdue?, "Expected not overdue when feature flag is enabled but no open invoices exist"
      end

      test "returns true when feature flag is enabled and has unpaid invoice despite having paid ones" do
        enable_feature_flag(:billing_use_earliest_invoice_due_date_for_latest_bill)
        yesterday = GitHub::Billing.today - 1

        # Create subscription
        create(:billing_sales_serve_plan_subscription, customer: @business.customer, billing_start_date: yesterday)
        @business.customer.update!(billing_end_date: yesterday)

        # Stub Zuora with mix of paid and unpaid invoices
        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([
          create(:zuora_invoice, amount: 25200, dueDate: yesterday.to_s, status: "Paid"),
          create(:zuora_invoice, amount: 12600, dueDate: yesterday.to_s, status: "Unpaid")
        ])

        Billing::Zuora::Invoice.any_instance.stubs(:invoice_items).returns([])
        assert @business.bill_overdue?, "Expected overdue when feature flag is enabled and has unpaid invoice"
      end

      test "returns false when feature flag is enabled and all invoices are paid" do
        enable_feature_flag(:billing_use_earliest_invoice_due_date_for_latest_bill)
        today = GitHub::Billing.today

        # Create subscription with today's date
        create(:billing_sales_serve_plan_subscription, customer: @business.customer, billing_start_date: today)
        @business.customer.update!(billing_end_date: today)

        # Stub Zuora with all paid invoices
        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([
          create(:zuora_invoice, amount: 25200, due_date: today.to_s, status: "Paid"),
          create(:zuora_invoice, amount: 12600, due_date: (GitHub::Billing.today + 1.day).to_s, status: "Paid")
        ])
        Billing::Zuora::Invoice.any_instance.stubs(:invoice_items).returns([])

        refute @business.bill_overdue?, "Expected not overdue when feature flag is enabled and all invoices are paid"
      end

    end

    context "#next_billing_date(with_dunning: true)" do
      test "returns the upcoming billing date if not past due" do
        travel_to("2016-10-01 12:00:00 PDT") do
          billed_on = GitHub::Billing.today + 1.week
          @business.update_attribute :billing_term_ends_at, billed_on - 1.day

          assert_equal Date.new(2016, 10, 8), @business.next_billing_date(with_dunning: true)
        end
      end

      test "returns seven days from the billing date if one billing attempt has been made" do
        travel_to("2016-10-01 12:00:00 PDT") do
          billed_on = GitHub::Billing.today
          @business.update_attribute :billing_term_ends_at, billed_on - 1.day
          @business.customer.update_attribute :billing_attempts, 1
          @business.reload

          assert_equal Date.new(2016, 10, 8), @business.next_billing_date(with_dunning: true)
        end
      end

      test "returns fifteen days from the billing date if two billing attempts have been made" do
        travel_to("2016-10-01 12:00:00 PDT") do
          billed_on = GitHub::Billing.today
          @business.update_attribute :billing_term_ends_at, billed_on - 1.day
          @business.customer.update_attribute :billing_attempts, 2
          @business.reload

          assert_equal Date.new(2016, 10, 16), @business.next_billing_date(with_dunning: true)
        end
      end

      test "returns nil if three billing attempts have been made" do
        travel_to("2016-10-01 12:00:00 PDT") do
          billed_on = GitHub::Billing.today
          @business.update_attribute :billing_term_ends_at, billed_on - 1.day
          @business.customer.update_attribute :billing_attempts, 3
          @business.reload

          assert_nil @business.next_billing_date(with_dunning: true)
        end
      end
    end

    context "#cancel_billing" do
      test "enqueues CloseOutZuoraSubscriptionJob for the plan subscription" do
        plan_subscription = create(:billing_plan_subscription, :zuora, customer: @business.customer)

        assert_enqueued_with(job: CloseOutZuoraSubscriptionJob) do
          @business.cancel_billing
        end
      end

      test "cancels all pending plan changes for the business" do
        plan_subscription = create(:billing_plan_subscription, customer: @business.customer)
        pending_plan_change = create(:billing_pending_plan_change, :active, :business, customer: @business.customer)

        @business.cancel_billing

        assert pending_plan_change.reload.is_complete?
      end
    end

    context "#suspend_billing" do
      test "enqueues the SuspendPlanSubscriptionJob to suspend the Business' plan subscription" do
        plan_subscription = create(:billing_plan_subscription, customer: @business.customer)

        assert_enqueued_with(job: SuspendPlanSubscriptionJob, args: [plan_subscription]) do
          @business.suspend_billing
        end
      end

      test "maintains automatic self-serve payment setting for the Business" do
        create(:billing_plan_subscription, customer: @business.customer)
        staff = create :staff_admin_user

        @business.customer.update(billing_type: Customer::BILLING_TYPE_CARD)
        @business.enable_automatic_self_serve_payment(staff)
        assert_predicate @business, :automatic_self_serve_payment_enabled?

        @business.suspend_billing
        assert_predicate @business.reload, :automatic_self_serve_payment_enabled?
      end
    end

    context "#resume_billing" do
      test "enqueues the ResumePlanSubscriptionJob to unsuspend the Business' plan subscription" do
        plan_subscription = create(:billing_plan_subscription, customer: @business.customer)
        @business.suspend_billing

        assert_enqueued_with(job: ResumePlanSubscriptionJob, args: [plan_subscription]) do
          @business.resume_billing
        end
      end
    end
  end

  context "annual_discount_allowed?" do
    test "returns false if remove_enterprise_plan_annual_discount FF enabled" do
      enable_feature_flag(:remove_enterprise_plan_annual_discount)

      refute @business.annual_discount_allowed?(billing_cycle: Business::BillingDependency::YEARLY_PLAN)
    end

    test "returns false if target billing cycle is not yearly" do
      disable_feature_flag(:remove_enterprise_plan_annual_discount)

      refute @business.annual_discount_allowed?(billing_cycle: Business::BillingDependency::MONTHLY_PLAN)
    end

    test "returns true during trial, with no disqualifying transactions" do
      disable_feature_flag(:remove_enterprise_plan_annual_discount)

      @business.update(trial_expires_at: 1.week.from_now)
      assert @business.annual_discount_allowed?(plan: GitHub::Plan.business_plus, billing_cycle: Business::BillingDependency::YEARLY_PLAN)
    end

    test "returns false if plan is nil" do
      disable_feature_flag(:remove_enterprise_plan_annual_discount)

      refute @business.annual_discount_allowed?(plan: nil, billing_cycle: Business::BillingDependency::YEARLY_PLAN)
    end

    test "returns true if has no yearly Enterprise transactions" do
      disable_feature_flag(:remove_enterprise_plan_annual_discount)

      customer = create(:customer, :zuora, billing_type: "card")
      @business.update_attribute(:customer, customer)
      plan_subscription = create(:billing_plan_subscription, :business_owned, customer: customer)

      create :billing_transaction,
        :business_owned,
        plan_subscription: plan_subscription,
        plan_name: "business_plus",
        customer: customer,
        renewal_frequency: :monthly,
        amount_in_cents: 21_00

      assert @business.annual_discount_allowed?(plan: GitHub::Plan.business_plus, billing_cycle: Business::BillingDependency::YEARLY_PLAN)
    end

    test "returns false if has yearly Enterprise transactions" do
      disable_feature_flag(:remove_enterprise_plan_annual_discount)

      jan_1st_2023 = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      jan_2nd_2024 = GitHub::Billing.date_in_timezone Date.parse("2024-01-02")
      travel_to jan_1st_2023 do
        customer = create(:customer, :zuora, billing_type: "card")
        @business.update_attribute(:customer, customer)
        plan_subscription = create(:billing_plan_subscription, :business_owned, customer: customer)

        create :billing_transaction,
          :business_owned,
          plan_subscription: plan_subscription,
          plan_name: "business_plus",
          customer: customer,
          renewal_frequency: :monthly,
          amount_in_cents: 21_00

        create :billing_transaction,
          :business_owned,
          plan_subscription: plan_subscription,
          plan_name: "business_plus",
          customer: customer,
          renewal_frequency: :yearly,
          amount_in_cents: 231_00
      end
      travel_to jan_2nd_2024 do
        refute @business.annual_discount_allowed?(plan: GitHub::Plan.business_plus, billing_cycle: Business::BillingDependency::YEARLY_PLAN)
      end
    end
  end

  context "#upgrade_from_trial" do
    if GitHub.billing_enabled?
      test "does not upgrade business not eligible for self-serve payments" do
        refute_predicate @business, :eligible_for_self_serve_payment?

        assert_equal false, @business.upgrade_from_trial(@business.owners.first)
      end

      test "does not upgrade business that can't enable automatic self-serve payments" do
        @business.disable_auto_pay!(:staff_override)
        refute_predicate @business, :can_enable_automatic_self_serve_payment?

        assert_equal false, @business.upgrade_from_trial(@business.owners.first)
      end

      test "does not upgrade business that does not have a valid payment method" do
        @business.customer.update_attribute(:billing_type, "card")
        refute_predicate @business, :has_valid_payment_method?

        assert_equal false, @business.upgrade_from_trial(@business.owners.first)
      end

      test "does not upgrade business not on trial" do
        @business.customer.update_attribute(:billing_type, "card")
        refute_predicate @business, :trial?

        assert_equal false, @business.upgrade_from_trial(@business.owners.first)
      end

      test "upgrade of eligible trial business with valid payment method initiates trial conversion" do
        @business.customer.update_attribute(:billing_type, "card")
        @business.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
        create(:payment_method, customer: @business.customer)
        create(:billing_plan_subscription, :zuora, customer: @business.customer)

        assert_predicate @business, :trial?
        assert_predicate @business, :eligible_for_self_serve_payment?
        assert_predicate @business, :has_valid_payment_method?
        @business.upgrade_from_trial(@business.owners.first)
        @business.reload

        assert_predicate @business, :trial_conversion_initiated?
      end

      test "does not upgrade eligible business with valid payment method if trial conversion not initiated" do
        @business.customer.update_attribute(:billing_type, "card")
        create(:payment_method, customer: @business.customer)
        create(:billing_plan_subscription, :zuora, customer: @business.customer)

        assert_predicate @business, :eligible_for_self_serve_payment?
        assert_predicate @business, :has_valid_payment_method?
        refute_predicate @business, :trial_conversion_initiated?
        assert_equal false, @business.upgrade_from_trial(@business.owners.first)
      end

      test "upgrade of eligible trial business with valid payment method updates billing cycle day to today" do
        @business.customer.update_attribute(:billing_type, "card")
        @business.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
        create(:payment_method, customer: @business.customer)
        create(:billing_plan_subscription, :zuora, customer: @business.customer)

        assert_predicate @business, :trial?
        assert_predicate @business, :eligible_for_self_serve_payment?
        assert_predicate @business, :has_valid_payment_method?
        @business.upgrade_from_trial(@business.owners.first)
        @business.reload

        assert_equal GitHub::Billing.today.strftime("%d").to_i, @business.customer_bill_cycle_day
      end

      test "upgrade of eligible enabled trial business with valid payment method enqueues job to sync plan subscription" do
        @business.customer.update_attribute(:billing_type, "card")
        @business.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
        create(:payment_method, customer: @business.customer)
        create(:billing_plan_subscription, :zuora, customer: @business.customer)

        assert_predicate @business, :trial?
        assert_predicate @business, :eligible_for_self_serve_payment?
        assert_predicate @business, :has_valid_payment_method?
        assert_predicate @business, :enabled?

        assert_enqueued_with(
          job: SynchronizePlanSubscriptionJob,
          args: [{ business_id: @business.id, plan_name: @business.plan.name }, business: @business]
        ) do
          @business.upgrade_from_trial(@business.owners.first)
        end
      end

      test "can skip zuora sync if we need to group updates for multi-checkout" do
        @business.customer.update_attribute(:billing_type, "card")
        @business.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
        create(:payment_method, customer: @business.customer)
        create(:billing_plan_subscription, :zuora, customer: @business.customer)

        assert @business.trial?
        assert @business.eligible_for_self_serve_payment?
        assert @business.has_valid_payment_method?
        assert @business.enabled?

        assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
          assert @business.upgrade_from_trial(@business.owners.first, skip_sync: true)
        end

        assert_equal GitHub::Billing.today.strftime("%d").to_i, @business.customer_bill_cycle_day
        assert @business.automatic_self_serve_payment_enabled?
        assert @business.trial?
        refute @business.trial_converted?
        assert @business.trial_conversion_initiated?
      end

      test "eligible disabled trial business with valid payment method gets enabled and enqueues job to sync plan subscription" do
        @business.customer.update_attribute(:billing_type, "card")
        @business.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
        create(:payment_method, customer: @business.customer)
        create(:billing_plan_subscription, :zuora, customer: @business.customer)
        @business.disable!

        assert_predicate @business, :trial?
        assert_predicate @business, :eligible_for_self_serve_payment?
        assert_predicate @business, :has_valid_payment_method?
        assert_predicate @business, :disabled?

        # Completely reload business to clear cached variables
        @business = Business.find(@business.id)

        assert_enqueued_with(
          job: SynchronizePlanSubscriptionJob,
          args: [{ business_id: @business.id, plan_name: GitHub::Plan::BUSINESS_PLUS }, business: @business]
        ) do
          @business.upgrade_from_trial(@business.owners.first)
        end
        assert_predicate @business, :enabled?
      end

      test "eligible trial business with valid payment method gets auto-pay enabled" do
        @business.customer.update_attribute(:billing_type, "card")
        @business.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
        create(:payment_method, customer: @business.customer)
        create(:billing_plan_subscription, :zuora, customer: @business.customer)

        assert_predicate @business, :trial?
        assert_predicate @business, :eligible_for_self_serve_payment?
        assert_predicate @business, :has_valid_payment_method?
        refute_predicate @business, :automatic_self_serve_payment_enabled?

        @business.upgrade_from_trial(@business.owners.first)
        assert_predicate @business, :automatic_self_serve_payment_enabled?
      end

      test "metered trial business with cc payment method gets auto-pay enabled" do
        @business_metered_trial.clear_azure_subscription_references!
        @business_metered_trial.update! customer: (create :credit_card_customer, billing_type: "card", metered_ghe: true)

        assert_predicate @business_metered_trial.reload, :has_credit_card?
        assert_predicate @business_metered_trial, :trial?
        assert_predicate @business_metered_trial, :eligible_for_self_serve_payment?
        assert_predicate @business_metered_trial, :has_valid_payment_method?
        refute_predicate @business_metered_trial, :automatic_self_serve_payment_enabled?

        @business_metered_trial.upgrade_from_trial(@business_metered_trial.owners.first)
        assert_predicate @business_metered_trial, :automatic_self_serve_payment_enabled?
      end

      test "metered trial business with azure subscription converted immediately" do
        refute_predicate @business_metered_trial, :has_credit_card?
        assert_predicate @business_metered_trial, :linked_azure_subscription?

        @business_metered_trial.upgrade_from_trial(@business_metered_trial.owners.first)
        refute_predicate @business_metered_trial, :trial?
        assert_predicate @business_metered_trial, :trial_converted?
      end

      test "metered trial business with credit card converted immediately" do
        @business_metered_trial.clear_azure_subscription_references!
        @business_metered_trial.update! customer: (create :credit_card_customer, billing_type: "card", metered_ghe: true)
        assert_predicate @business_metered_trial.reload, :has_credit_card?

        @business_metered_trial.upgrade_from_trial(@business_metered_trial.owners.first)
        refute_predicate @business_metered_trial, :trial?
        assert_predicate @business_metered_trial, :trial_converted?
      end
    end
  end

  context "#purchase_enterprise_and_ghas" do

    test "updates seats and billing cycle before attempting a trial conversion" do
      result = @business_to_upgrade.purchase_enterprise_and_ghas(
        actor: @business_to_upgrade.owners.first,
        enterprise_seats: 5,
        enterprise_plan_duration: "month",
        ghas_committers: 2,
      )
      @business_to_upgrade.stubs(:upgrade_from_trial).raises(StandardError.new("oops"))
      refute result.ok?
      assert_equal "Failed to complete GitHub Enterprise purchase. Please try again later or contact support.", result.error
      assert_equal 5, @business_to_upgrade.seats
      assert_equal "month", @business_to_upgrade.plan_duration
      refute @business_to_upgrade.has_active_advanced_security_subscription?

    end

    test "enforces seat minimum" do
      @business_to_upgrade.expects(:total_consumed_licenses).returns(10)
      result = @business_to_upgrade.purchase_enterprise_and_ghas(
        actor: @business_to_upgrade.owners.first,
        enterprise_seats: 5,
        enterprise_plan_duration: "year",
        ghas_committers: 0,
      )

      refute result.ok?
      assert_equal "You must purchase at least 10 seats to support your 10 existing members.", result.error
    end

    test "enforces seat maximum" do
      seat_limit = @business_to_upgrade.seat_limit_for_upgrades
      result = @business_to_upgrade.purchase_enterprise_and_ghas(
        actor: @business_to_upgrade.owners.first,
        enterprise_seats: seat_limit + 1,
        enterprise_plan_duration: "year",
        ghas_committers: 0,
      )

      refute result.ok?
      assert_equal "You can only add up to #{seat_limit} seats when upgrading.", result.error
    end

    test "allows purchase when ghas seats is greater than enterprise seats" do
      @business_to_upgrade.customer.update_attribute(:billing_type, "card")
      @business_to_upgrade.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
      create(:payment_method, customer: @business_to_upgrade.customer)
      create(:billing_plan_subscription, :zuora, customer: @business_to_upgrade.customer)

      assert_enqueued_jobs 1, only: SynchronizePlanSubscriptionJob do
        result = @business_to_upgrade.purchase_enterprise_and_ghas(
          actor: @business_to_upgrade.owners.first,
          enterprise_seats: 5,
          enterprise_plan_duration: "year",
          ghas_committers: 9,
        )
        assert result.ok?
      end
    end

    test "instruments multi_checkout action" do
      @business_to_upgrade.customer.update_attribute(:billing_type, "card")
      @business_to_upgrade.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
      create(:payment_method, customer: @business_to_upgrade.customer)
      create(:billing_plan_subscription, :zuora, customer: @business_to_upgrade.customer)


      events = assert_performed_audit_entries(count: 1, only: "business.multi_checkout") do
        assert_enqueued_jobs 1, only: SynchronizePlanSubscriptionJob do
          result = @business_to_upgrade.purchase_enterprise_and_ghas(
            actor: @business_to_upgrade.owners.first,
            enterprise_seats: 5,
            enterprise_plan_duration: "year",
            ghas_committers: 9,
          )
          assert result.ok?
        end
      end

      expected_payload = {
        actor: @business_to_upgrade.owners.first.display_login,
        advanced_security_seats: 9,
        advanced_security_plan_duration: "month",
        enterprise_seats: 5,
        enterprise_plan_duration: "year",

      }
      assert_subset_hash expected_payload, events.first
    end

    test "returns error if user is spammy" do
      actor = @business_to_upgrade.owners.first
      actor.spammy = true
      result = @business_to_upgrade.purchase_enterprise_and_ghas(
        actor: actor,
        enterprise_seats: 5,
        enterprise_plan_duration: "invalid",
        ghas_committers: 0,
      )

      refute result.ok?
      assert_equal "Cannot complete purchase because your account has been flagged. If you believe this is a mistake, contact support.", result.error
    end

    test "returns error when duration is invalid" do
      result = @business_to_upgrade.purchase_enterprise_and_ghas(
        actor: @business_to_upgrade.owners.first,
        enterprise_seats: 5,
        enterprise_plan_duration: "invalid",
        ghas_committers: 0,
      )

      refute result.ok?
      assert_equal "Duration must be either 'month' or 'year'.", result.error
    end

    test "returns error when enterprise upgrade fails" do
      @business_to_upgrade.expects(:upgrade_from_trial).returns(false)

      assert_enqueued_jobs 0, only: SynchronizePlanSubscriptionJob do
        result = @business_to_upgrade.purchase_enterprise_and_ghas(
          actor: @business_to_upgrade.owners.first,
          enterprise_seats: 5,
          enterprise_plan_duration: "year",
          ghas_committers: 0,
        )

        refute result.ok?
        assert_equal "Failed to complete GitHub Enterprise purchase. Please try again later or contact support.", result.error
      end
    end

    test "returns error when ghas purchase fails" do
      @business_to_upgrade.expects(:upgrade_from_trial).returns(true)
      ghas_error_message = "Failed to complete GitHub Advanced Security purchase."
      @business_to_upgrade.expects(:subscribe_to_advanced_security).returns(GitHub::Result.error(StandardError.new(ghas_error_message)))

      assert_enqueued_jobs 0, only: SynchronizePlanSubscriptionJob do
        result = @business_to_upgrade.purchase_enterprise_and_ghas(
          actor: @business_to_upgrade.owners.first,
          enterprise_seats: 5,
          enterprise_plan_duration: "year",
          ghas_committers: 5,
        )

        refute result.ok?
        assert_equal ghas_error_message, result.error
      end
    end

    test "succeeds and enqueues synchronization job" do
      @business_to_upgrade.customer.update_attribute(:billing_type, "card")
      @business_to_upgrade.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
      create(:payment_method, customer: @business_to_upgrade.customer)
      create(:billing_plan_subscription, :zuora, customer: @business_to_upgrade.customer)

      assert_enqueued_jobs 1, only: SynchronizePlanSubscriptionJob do
        result = @business_to_upgrade.purchase_enterprise_and_ghas(
          actor: @business_to_upgrade.owners.first,
          enterprise_seats: 5,
          enterprise_plan_duration: "year",
          ghas_committers: 5,
        )
        assert result.ok?
      end
    end
  end if GitHub.billing_enabled?

  context "#upgrade_from_free_or_business_plan_org" do
    if GitHub.billing_enabled?
      test "does not upgrade a business that is not eligible for self-serve payments" do
        refute_predicate @business_to_upgrade, :eligible_for_self_serve_payment?

        assert_equal false, @business_to_upgrade.upgrade_from_trial(@business_to_upgrade.owners.first)
      end

      test "does not upgrade if the business does not have a valid payment method" do
        @business_to_upgrade.customer.update_attribute(:billing_type, "card")

        assert_predicate @business_to_upgrade, :organization_upgrade_initiated?
        refute_predicate @business_to_upgrade, :has_valid_payment_method?

        assert_equal false, @business_to_upgrade.upgrade_from_free_or_business_plan_org(@business_to_upgrade.owners.first)
      end

      test "does not upgrade if the business has not initiated an organization upgrade" do
        random_business = create :business, owners: [@owner]

        refute_predicate random_business, :organization_upgrade_initiated?
        assert_equal false, random_business.upgrade_from_free_or_business_plan_org(random_business.owners.first)
      end

      test "upgrade of eligible business with valid payment method initiates purchase" do
        @business_to_upgrade.customer.update_attribute(:billing_type, "card")

        create(:payment_method, customer: @business_to_upgrade.customer)
        create(:billing_plan_subscription, :zuora, customer: @business_to_upgrade.customer)

        assert_predicate @business_to_upgrade, :organization_upgrade_initiated?
        assert_predicate @business_to_upgrade, :eligible_for_self_serve_payment?
        assert_predicate @business_to_upgrade, :has_valid_payment_method?
        assert_equal true, @business_to_upgrade.upgrade_from_free_or_business_plan_org(@business_to_upgrade.owners.first)
        @business_to_upgrade.reload

        assert_predicate @business_to_upgrade, :organization_upgrade_purchase_initiated?
      end

      test "upgrade of eligible business with valid payment method updates billing cycle day to today" do
        @business_to_upgrade.customer.update_attribute(:billing_type, "card")
        @business_to_upgrade.initiate_organization_upgrade

        create(:payment_method, customer: @business_to_upgrade.customer)
        create(:billing_plan_subscription, :zuora, customer: @business_to_upgrade.customer)

        assert_predicate @business_to_upgrade, :organization_upgrade_initiated?
        assert_predicate @business_to_upgrade, :eligible_for_self_serve_payment?
        assert_predicate @business_to_upgrade, :has_valid_payment_method?
        assert_equal true, @business_to_upgrade.upgrade_from_free_or_business_plan_org(@business_to_upgrade.owners.first)
        @business_to_upgrade.reload

        assert_equal GitHub::Billing.today.strftime("%d").to_i, @business_to_upgrade.customer_bill_cycle_day
      end

      test "upgrade of eligible business with valid payment method enqueues job to sync plan subscription" do
        @business_to_upgrade.customer.update_attribute(:billing_type, "card")
        @business_to_upgrade.initiate_organization_upgrade
        create(:payment_method, customer: @business_to_upgrade.customer)
        create(:billing_plan_subscription, :zuora, customer: @business_to_upgrade.customer)

        assert_predicate @business_to_upgrade, :organization_upgrade_initiated?
        assert_predicate @business_to_upgrade, :eligible_for_self_serve_payment?
        assert_predicate @business_to_upgrade, :has_valid_payment_method?
        assert_predicate @business_to_upgrade, :enabled?

        assert_enqueued_with(
          job: SynchronizePlanSubscriptionJob,
          args: [{ business_id: @business_to_upgrade.id, plan_name: @business_to_upgrade.plan.name }, business: @business_to_upgrade]
        ) do
          @business_to_upgrade.upgrade_from_free_or_business_plan_org(@business_to_upgrade.owners.first)
        end
      end

      test "eligible business with valid payment method gets auto-pay enabled" do
        @business_to_upgrade.customer.update_attribute(:billing_type, "card")
        @business_to_upgrade.initiate_organization_upgrade
        create(:payment_method, customer: @business_to_upgrade.customer)
        create(:billing_plan_subscription, :zuora, customer: @business_to_upgrade.customer)

        assert_predicate @business_to_upgrade, :organization_upgrade_initiated?
        assert_predicate @business_to_upgrade, :eligible_for_self_serve_payment?
        assert_predicate @business_to_upgrade, :has_valid_payment_method?
        refute_predicate @business_to_upgrade, :automatic_self_serve_payment_enabled?

        @business_to_upgrade.upgrade_from_free_or_business_plan_org(@business_to_upgrade.owners.first)
        assert_predicate @business_to_upgrade, :automatic_self_serve_payment_enabled?
      end
    end
  end

  context "#schedule_async_coupon_payment_collection" do
    test "redeems a coupon and places the business in the creation_from_coupon_purchase_initiated state" do
      self_serve_business_plus_coupon = create :coupon, group: "microsoft"
      Business.any_instance.stubs(:has_valid_payment_method?).returns(true)
      Business.any_instance.stubs(:has_saved_trade_screening_record_with_information?).returns(true)

      assert_predicate @business_to_create_from_coupon, :creation_initiated_from_coupon?
      refute_predicate @business_to_create_from_coupon, :creation_from_coupon_purchase_initiated?

      result = @business_to_create_from_coupon.schedule_async_coupon_payment_collection(self_serve_business_plus_coupon, @owner)

      assert result.success?
      assert_predicate @business_to_create_from_coupon.reload, :creation_from_coupon_purchase_initiated?  # Payment is being processed asynchronously
      @business_to_create_from_coupon.clear_coupon_local_cache
      assert_equal @business_to_create_from_coupon.reload.coupon, self_serve_business_plus_coupon
    end

    test "redeems a coupon for a pre-existing enterprise account" do
      enable_feature_flag(:coupon_application_for_existing_ea)
      self_serve_business_plus_coupon = create :coupon, group: "microsoft"
      Business.any_instance.stubs(:has_valid_payment_method?).returns(true)
      Business.any_instance.stubs(:has_saved_trade_screening_record_with_information?).returns(true)

      business = create(:business, owners: [@owner])
      business.customer.update_attribute(:billing_type, "card")
      refute_predicate business, :creation_initiated_from_coupon?
      result = business.schedule_async_coupon_payment_collection(self_serve_business_plus_coupon, @owner)

      assert result.success?
      assert_equal business.reload.coupon, self_serve_business_plus_coupon
      refute_nil business.coupon_redemption
    end

    test "fails if the coupon cannot be redeemed again" do
      self_serve_business_plus_coupon = create :coupon, group: "microsoft"
      Coupon.any_instance.stubs(:limit).returns(0)
      Business.any_instance.stubs(:has_valid_payment_method?).returns(true)
      Business.any_instance.stubs(:has_saved_trade_screening_record_with_information?).returns(true)

      assert_predicate @business_to_create_from_coupon, :creation_initiated_from_coupon?
      refute_predicate @business_to_create_from_coupon, :creation_from_coupon_purchase_initiated?

      result = @business_to_create_from_coupon.schedule_async_coupon_payment_collection(self_serve_business_plus_coupon, @owner)

      refute result.success?
      assert_equal result.error_message, "Coupon can't be redeemed any more times."
      refute_predicate @business_to_create_from_coupon.reload, :creation_from_coupon_purchase_initiated?  # Payment is not being processed
      @business_to_create_from_coupon.clear_coupon_local_cache
      assert_nil @business_to_create_from_coupon.reload.coupon
    end

    test "returns a failure if the business could not be put in the creation_from_coupon_purchase_initiated state, and restores coupon" do
      self_serve_business_plus_coupon = create :coupon, group: "microsoft"
      Business.any_instance.stubs(:has_valid_payment_method?).returns(false)  # Cannot place account in purchase state if it has no payment method
      Business.any_instance.stubs(:has_saved_trade_screening_record_with_information?).returns(true)
      limit_before_purchase_attempt = self_serve_business_plus_coupon.limit

      assert_predicate @business_to_create_from_coupon, :creation_initiated_from_coupon?
      refute_predicate @business_to_create_from_coupon, :creation_from_coupon_purchase_initiated?

      result = @business_to_create_from_coupon.schedule_async_coupon_payment_collection(self_serve_business_plus_coupon, @owner)

      refute result.success?
      assert_equal result.error_message, "Failed to complete GitHub Enterprise purchase. Please try again later or contact support."
      refute_predicate @business_to_create_from_coupon.reload, :creation_from_coupon_purchase_initiated?  # Payment is not being processed
      @business_to_create_from_coupon.clear_coupon_local_cache
      assert_nil @business_to_create_from_coupon.reload.coupon
      assert_equal limit_before_purchase_attempt, self_serve_business_plus_coupon.reload.limit
    end

    test "redeems a coupon and upgrades the business if no payment is required" do
      self_serve_business_plus_coupon = create :coupon, group: "microsoft"
      Business.any_instance.stubs(:payment_amount).returns(0) # No payment is required

      assert_predicate @business_to_create_from_coupon, :creation_initiated_from_coupon?
      refute_predicate @business_to_create_from_coupon, :creation_from_coupon_purchase_initiated?

      result = @business_to_create_from_coupon.schedule_async_coupon_payment_collection(self_serve_business_plus_coupon, @owner)

      assert result.success?
      assert_predicate @business_to_create_from_coupon.reload, :created_from_coupon?  # Immediately upgraded
      @business_to_create_from_coupon.clear_coupon_local_cache
      assert_equal @business_to_create_from_coupon.reload.coupon, self_serve_business_plus_coupon
    end

    test "returns a failure if the business with no payment required could not be upgraded, and restores coupon" do
      self_serve_business_plus_coupon = create :coupon, group: "microsoft"
      Business.any_instance.stubs(:complete_creation_from_coupon).returns(false)  # Account upgrade failed
      Business.any_instance.stubs(:payment_amount).returns(0) # No payment is required
      limit_before_purchase_attempt = self_serve_business_plus_coupon.limit

      assert_predicate @business_to_create_from_coupon, :creation_initiated_from_coupon?
      refute_predicate @business_to_create_from_coupon, :creation_from_coupon_purchase_initiated?

      result = @business_to_create_from_coupon.schedule_async_coupon_payment_collection(self_serve_business_plus_coupon, @owner)

      refute result.success?
      assert_equal result.error_message, "Failed to complete GitHub Enterprise purchase. Please try again later or contact support."
      assert_predicate @business_to_create_from_coupon.reload, :creation_initiated_from_coupon? # Payment has not been initiated, and business has not been upgraded
      @business_to_create_from_coupon.clear_coupon_local_cache
      assert_nil @business_to_create_from_coupon.reload.coupon
      assert_equal limit_before_purchase_attempt, self_serve_business_plus_coupon.reload.limit
    end

    test "emails the owner(s) of the business to let them know business creation was successful, if no payment is required" do
      self_serve_business_plus_coupon = create :coupon, group: "microsoft", discount: "100%"

      assert_predicate @business_to_create_from_coupon, :creation_initiated_from_coupon?
      refute_predicate @business_to_create_from_coupon, :creation_from_coupon_purchase_initiated?

      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        assert_difference "ActionMailer::Base.deliveries.size", +1 do
          result = @business_to_create_from_coupon.schedule_async_coupon_payment_collection(self_serve_business_plus_coupon, @owner)

          assert result.success?
        end
      end

      mail = ActionMailer::Base.deliveries.last
      assert_equal \
        "[GitHub] Welcome to GitHub Enterprise — Let's Get Started!",
        mail.subject

      assert_predicate @business_to_create_from_coupon.reload, :created_from_coupon?  # Immediately upgraded
      @business_to_create_from_coupon.clear_coupon_local_cache
      assert_equal @business_to_create_from_coupon.reload.coupon, self_serve_business_plus_coupon
    end

    test "does not email the owner(s) of the business to let them know business creation was successful, if a payment is being processed" do
      self_serve_business_plus_coupon = create :coupon, group: "microsoft", discount: "10%"
      Business.any_instance.stubs(:has_valid_payment_method?).returns(true)
      Business.any_instance.stubs(:has_saved_trade_screening_record_with_information?).returns(true)
      assert_predicate @business_to_create_from_coupon, :creation_initiated_from_coupon?

      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        assert_no_difference "ActionMailer::Base.deliveries.size" do
          result = @business_to_create_from_coupon.schedule_async_coupon_payment_collection(self_serve_business_plus_coupon, @owner)

          assert result.success?
        end
      end

      assert_predicate @business_to_create_from_coupon.reload, :creation_from_coupon_purchase_initiated?  # Payment is being processed asynchronously
      @business_to_create_from_coupon.clear_coupon_local_cache
      assert_equal @business_to_create_from_coupon.reload.coupon, self_serve_business_plus_coupon
    end
  end if GitHub.billing_enabled?

  context "#upgrade_from_coupon_redemption" do
    test "does nothing for a business that is not eligible for self-serve payments" do
      ramdom_business = create(:business, owners: [@owner])
      ramdom_business.customer.update_attribute(:billing_type, "invoice")
      refute_predicate ramdom_business, :eligible_for_self_serve_payment?

      assert_equal false, ramdom_business.upgrade_from_coupon_redemption(ramdom_business.owners.first)
    end

    test "does nothing for a business does not have a valid payment method" do
      assert_predicate @business_to_create_from_coupon, :creation_initiated_from_coupon?
      refute_predicate @business_to_create_from_coupon, :has_valid_payment_method?

      assert_equal false, @business_to_create_from_coupon.upgrade_from_coupon_redemption(@business_to_create_from_coupon.owners.first)
    end

    test "does nothing if the business has not initiated creation from a coupon" do
      random_business = create :business, owners: [@owner]

      refute_predicate random_business, :creation_initiated_from_coupon?
      assert_equal false, random_business.upgrade_from_coupon_redemption(random_business.owners.first)
    end

    test "initiates purchase for an eligible business with a valid payment method" do
      create(:payment_method, customer: @business_to_create_from_coupon.customer)
      create(:billing_plan_subscription, :zuora, customer: @business_to_create_from_coupon.customer)

      assert_predicate @business_to_create_from_coupon, :creation_initiated_from_coupon?
      assert_predicate @business_to_create_from_coupon, :eligible_for_self_serve_payment?
      assert_predicate @business_to_create_from_coupon, :has_valid_payment_method?
      assert_equal true, @business_to_create_from_coupon.upgrade_from_coupon_redemption(@business_to_create_from_coupon.owners.first)
      @business_to_create_from_coupon.reload

      assert_predicate @business_to_create_from_coupon, :creation_from_coupon_purchase_initiated?
    end

    test "updates the bill cycle day to today for an eligible business with a valid payment method" do
      create(:payment_method, customer: @business_to_create_from_coupon.customer)
      create(:billing_plan_subscription, :zuora, customer: @business_to_create_from_coupon.customer)

      assert_predicate @business_to_create_from_coupon, :creation_initiated_from_coupon?
      assert_predicate @business_to_create_from_coupon, :eligible_for_self_serve_payment?
      assert_predicate @business_to_create_from_coupon, :has_valid_payment_method?
      assert_equal true, @business_to_create_from_coupon.upgrade_from_coupon_redemption(@business_to_create_from_coupon.owners.first)
      @business_to_create_from_coupon.reload

      assert_equal GitHub::Billing.today.strftime("%d").to_i, @business_to_create_from_coupon.customer_bill_cycle_day
    end

    test "job to sync plan subscription is enqueued for an eligible business with a valid payment method" do
      create(:payment_method, customer: @business_to_create_from_coupon.customer)
      create(:billing_plan_subscription, :zuora, customer: @business_to_create_from_coupon.customer)

      assert_predicate @business_to_create_from_coupon, :creation_initiated_from_coupon?
      assert_predicate @business_to_create_from_coupon, :eligible_for_self_serve_payment?
      assert_predicate @business_to_create_from_coupon, :has_valid_payment_method?
      assert_predicate @business_to_create_from_coupon, :enabled?

      assert_enqueued_with(
        job: SynchronizePlanSubscriptionJob,
        args: [{ business_id: @business_to_create_from_coupon.id, plan_name: @business_to_create_from_coupon.plan.name }, business: @business_to_create_from_coupon]
      ) do
        @business_to_create_from_coupon.upgrade_from_coupon_redemption(@business_to_create_from_coupon.owners.first)
      end
    end

    test "auto-pay is enabled for an eligible business with a valid payment method" do
      create(:payment_method, customer: @business_to_create_from_coupon.customer)
      create(:billing_plan_subscription, :zuora, customer: @business_to_create_from_coupon.customer)

      assert_predicate @business_to_create_from_coupon, :creation_initiated_from_coupon?
      assert_predicate @business_to_create_from_coupon, :eligible_for_self_serve_payment?
      assert_predicate @business_to_create_from_coupon, :has_valid_payment_method?
      refute_predicate @business_to_create_from_coupon, :automatic_self_serve_payment_enabled?

      @business_to_create_from_coupon.upgrade_from_coupon_redemption(@business_to_create_from_coupon.owners.first)
      assert_predicate @business_to_create_from_coupon, :automatic_self_serve_payment_enabled?
    end
  end if GitHub.billing_enabled?

  context "#reset_coupon_purchase_status" do
    test "does nothing if the business is not in the creation_from_coupon_purchase_initiated state" do
      assert_predicate @business_to_create_from_coupon, :creation_initiated_from_coupon?
      refute_predicate @business_to_create_from_coupon, :creation_from_coupon_purchase_initiated?

      refute @business_to_create_from_coupon.reset_coupon_purchase_status

      assert_predicate @business_to_create_from_coupon, :creation_initiated_from_coupon?
    end

    test "moves a creation_from_coupon_purchase_initiated business back to the creation_from_coupon_initiated state, and resets the coupon limit" do
      # autopay gets enabled when we initiate a purchase
      # need to do that manually here
      @business_to_create_from_coupon.enable_automatic_self_serve_payment(@owner)
      @business_to_create_from_coupon.initiate_creation_purchase_from_coupon
      assert_predicate @business_to_create_from_coupon, :creation_from_coupon_purchase_initiated?
      assert_predicate @business_to_create_from_coupon, :automatic_self_serve_payment_enabled?

      assert @business_to_create_from_coupon.reset_coupon_purchase_status

      assert_predicate @business_to_create_from_coupon, :creation_initiated_from_coupon?
      refute_predicate @business_to_create_from_coupon, :automatic_self_serve_payment_enabled?
    end

    test "expires the active coupon and removes it from the list of past coupon redemptions for the business, so that it's not blocked from redeeming the same coupon again when reattempting purchase" do
      @business_to_create_from_coupon.redeem_coupon(@coupon.code, actor: @owner)
      @business_to_create_from_coupon.initiate_creation_purchase_from_coupon
      assert_predicate @business_to_create_from_coupon, :creation_from_coupon_purchase_initiated?
      assert_predicate @business_to_create_from_coupon, :has_an_active_coupon?

      assert @business_to_create_from_coupon.reset_coupon_purchase_status

      assert_predicate @business_to_create_from_coupon, :creation_initiated_from_coupon?
      refute_predicate @business_to_create_from_coupon.reload, :has_an_active_coupon?
      assert_empty @business_to_create_from_coupon.coupon_redemptions.where(coupon_id: @coupon.code)

      # this business can now redeem this same coupon again, which it will need to when
      # reattempting purchase
      @business_to_create_from_coupon.redeem_coupon(@coupon.code, actor: @owner)
      assert_predicate @business_to_create_from_coupon.reload, :has_an_active_coupon?
    end

    test "notifies owner of unsuccessful payment" do
      @business_to_create_from_coupon.initiate_creation_purchase_from_coupon
      assert_predicate @business_to_create_from_coupon, :creation_from_coupon_purchase_initiated?

      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        assert_difference "ActionMailer::Base.deliveries.size", +1 do
          assert @business_to_create_from_coupon.reset_coupon_purchase_status
        end
      end

      assert_predicate @business_to_create_from_coupon, :creation_initiated_from_coupon?
      mail = ActionMailer::Base.deliveries.last
      assert_equal "[GitHub] Your purchase of GitHub Enterprise was unsuccessful",
                    mail.subject
      assert_same_elements \
       [@business_to_create_from_coupon.owners.first.email],
        mail.to
    end

    test "logs to hydro the instrument creation from coupon event" do
      @business_to_create_from_coupon.redeem_coupon(@coupon.code, actor: @owner)
      @business_to_create_from_coupon.initiate_creation_purchase_from_coupon
      assert_predicate @business_to_create_from_coupon, :creation_from_coupon_purchase_initiated?

      reset_hydro
      assert @business_to_create_from_coupon.reset_coupon_purchase_status

      assert_predicate @business_to_create_from_coupon, :creation_initiated_from_coupon?

      assert_hydro_published({
        enterprise: Hydro::EntitySerializer.business(@business_to_create_from_coupon),
        actor: Hydro::EntitySerializer.user(@owner),
        organization: Hydro::EntitySerializer.organization(@org),
        slug: @business_to_create_from_coupon.slug,
        status: :CREATION_INITIATED_FROM_COUPON,
        coupon: @coupon.code,
        organization_previous_plan: @org.plan.name,
      }, schema: "github.enterprise_account.v0.CreationFromCouponRedemption")
    end
  end if GitHub.billing_enabled?

  context "#pending_cycle_change" do
    test "returns the pending plan change if there is one" do
      pending_downgrade = create(:billing_pending_plan_change, :business, customer: @business.customer)
      assert_equal pending_downgrade.id, @business.pending_cycle_change.id
    end

    test "returns the pending plan change for the github plan even if there is an earlier subscription item change" do
      @business.update!(customer: create(:customer, :zuora, :self_serve, billing_end_date: 1.year.from_now))

      plan_change = create(:billing_pending_plan_change, :business, customer: @business.customer)
      subscription_item_change = create(:billing_pending_plan_change, :business, customer: @business.customer, active_on: 1.month.from_now)

      refute_equal subscription_item_change.id, @business.pending_cycle_change.id
      assert_equal plan_change.id, @business.pending_cycle_change.id
    end

    test "returns the pending plan change for the github plan even if there is a later subscription item change" do
      @business.update!(customer: create(:customer, :zuora, :self_serve, billing_end_date: 1.month.from_now))

      plan_change = create(:billing_pending_plan_change, :business, customer: @business.customer)
      subscription_item_change = create(:billing_pending_plan_change, :business, customer: @business.customer, active_on: 2.months.from_now)

      refute_equal subscription_item_change.id, @business.pending_cycle_change.id
      assert_equal plan_change.id, @business.pending_cycle_change.id
    end

    test "does not return the pending plan change if it has completed" do
      create(:billing_pending_plan_change, :business, is_complete: true, customer: @business.customer)
      assert_nil @business.pending_cycle_change
    end
  end

  context "#update_billing_and_sync_subscription" do
    if GitHub.billing_enabled?
      test "returns true if update is successful" do
        @business.customer.update_attribute(:billing_type, "card")
        @business.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
        create(:payment_method, customer: @business.customer)
        create(:billing_plan_subscription, :zuora, customer: @business.customer)

        assert_predicate @business, :trial?
        assert_predicate @business, :eligible_for_self_serve_payment?
        assert_predicate @business, :has_valid_payment_method?

        assert @business.update_billing_and_sync_subscription(current_user: @business.owners.first)
      end

      test "returns false if update failed" do
        @business.customer.update_attribute(:billing_type, "card")
        @business.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
        create(:payment_method, customer: @business.customer)
        create(:billing_plan_subscription, :zuora, customer: @business.customer)

        assert_predicate @business, :trial?
        assert_predicate @business, :eligible_for_self_serve_payment?
        assert_predicate @business, :has_valid_payment_method?

        refute @business.update_billing_and_sync_subscription(current_user: @business.owners.first, bill_cycle_day: nil)
      end

      test "updates billing_end_date to a month in the future" do
        @business.customer.update_attribute(:billing_type, "card")
        @business.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
        @business.plan_duration = "month"
        @business.save!
        create(:payment_method, customer: @business.customer)
        create(:billing_plan_subscription, :zuora, customer: @business.customer)

        travel_to Time.current + 5.days
        assert @business.update_billing_and_sync_subscription(current_user: @business.owners.first)
        assert_equal GitHub::Billing.today + 1.month - 1.day, @business.customer.billing_end_date.to_date
      end

      test "updates billing_end_date to a year in the future" do
        @business.customer.update_attribute(:billing_type, "card")
        @business.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
        create(:payment_method, customer: @business.customer)
        create(:billing_plan_subscription, :zuora, customer: @business.customer)

        travel_to Time.current + 5.days
        assert @business.update_billing_and_sync_subscription(current_user: @business.owners.first)
        assert_equal GitHub::Billing.today + 1.year - 1.day, @business.customer.billing_end_date.to_date
      end
    end
  end

  context "#pending_cycle" do
    test "shows if the pending change is a downgrade" do
      create(:billing_pending_plan_change, :business, seats: 1, customer: @business.customer)
      assert @business.pending_cycle.downgrading?
    end

    test "shows the number of seats of next downgrade" do
      pending_downgrade = create(:billing_pending_plan_change, :business, seats: 1, customer: @business.customer)
      assert_equal pending_downgrade.seats, @business.pending_cycle.seats
    end
  end


  context "#only_for_copilot?" do
    test "returns true if the sales serve plan subscription has a ghec_for_copilot charge" do
      create :billing_sales_serve_plan_subscription,
        customer: @business.customer,
        billing_start_date:  GitHub::Billing.today - 5.days,
        zuora_rate_plan_charges: {
          Billing::SalesServePlanSubscription::GHEC_FOR_COPILOT_CHARGE_ID => { number: "C-123" }
        }

      assert @business.only_for_copilot?
    end

    test "returns false if the sales serve plan subscription does not have a ghec_for_copilot charge" do
      create :billing_sales_serve_plan_subscription,
        customer: @business.customer,
        billing_start_date:  GitHub::Billing.today - 5.days
      refute @business.only_for_copilot?
    end

    test "returns false if there is no sales serve plan subscription" do
      refute @business.only_for_copilot?
    end
  end

  context "#should_transition_to_external_subscription?" do
    if GitHub.billing_enabled?
      test "returns false for business without valid payment method" do
        refute_predicate @business, :trial?
        refute_predicate @business, :has_valid_payment_method?

        refute_predicate @business, :should_transition_to_external_subscription?
      end

      test "returns true for business with valid payment method" do
        @business_with_self_serve_payment.customer.update! billing_end_date: 2.weeks.ago
        refute_predicate @business_with_self_serve_payment, :trial?
        assert_predicate @business_with_self_serve_payment, :has_valid_payment_method?
        assert_predicate @business_with_self_serve_payment, :past_due?

        assert_predicate @business_with_self_serve_payment, :should_transition_to_external_subscription?
      end
    end
  end

  context "#past_due_invoice?" do
    test "returns false if the business does not have a sales serve plan subscription" do
      customer = @business.customer
      assert_predicate customer, :invoiced?
      assert_nil customer.sales_serve_plan_subscription
      refute_predicate @business, :past_due_invoice?
    end

    test "returns false if the business next billing date is in the future" do
      Timecop.freeze(GitHub::Billing.timezone.parse("May 06 2015")) do
        customer = @business.customer
        FactoryBot.create(:billing_sales_serve_plan_subscription, customer: customer)
        unless GitHub.single_business_environment?
          Billing::Pricing.any_instance.stubs(:discounted).returns(Billing::Money.new(10_00))
        end

        assert_predicate customer, :invoiced?
        refute_nil customer.sales_serve_plan_subscription
        assert @business.next_billing_date > GitHub::Billing.today
        refute_predicate @business, :past_due_invoice?
      end
    end

    test "returns false if there are no past invoices available for the business" do
      Timecop.freeze(GitHub::Billing.timezone.parse("May 06 2015")) do
        customer = @business.customer
        FactoryBot.create(:billing_sales_serve_plan_subscription, customer: customer)

        Business.any_instance.stubs(:next_billing_date).returns(Time.now - 2.days)
        unless GitHub.single_business_environment?
          Billing::Pricing.any_instance.stubs(:discounted).returns(Billing::Money.new(10_00))
          Billing::Zuora::Invoice.expects(:past_due).with(account_id: customer.zuora_account_id).returns([])
        end

        assert_predicate customer, :invoiced?
        refute_nil customer.sales_serve_plan_subscription
        assert GitHub::Billing.today > @business.next_billing_date
        refute_predicate @business, :past_due_invoice?
      end
    end

    test "returns true if there are past invoices available for the business" do
      Timecop.freeze(GitHub::Billing.timezone.parse("May 06 2015")) do
        customer = @business.customer
        FactoryBot.create(:billing_sales_serve_plan_subscription, customer: customer)

        Business.any_instance.stubs(:next_billing_date).returns(Time.now - 2.days)
        unless GitHub.single_business_environment?
          Billing::Pricing.any_instance.stubs(:discounted).returns(Billing::Money.new(10_00))
          invoice = build(:zuora_invoice, invoiceDate: (Time.now - 2.days).to_s)
          Billing::Zuora::Invoice.expects(:past_due)
            .with(account_id: customer.zuora_account_id)
            .returns([invoice])
        end

        assert_predicate customer, :invoiced?
        refute_nil customer.sales_serve_plan_subscription
        assert GitHub::Billing.today > @business.next_billing_date
        if GitHub.single_business_environment?
          refute_predicate @business, :past_due_invoice?
        else
          assert_predicate @business, :past_due_invoice?
        end
      end
    end
  end

  context "#disabled_due_to_failed_recurring_charge?" do
    if GitHub.billing_enabled?
      test "returns false for business with active trial" do
        @business.update! trial_expires_at: 2.weeks.from_now
        assert_predicate @business, :trial?

        refute_predicate @business, :disabled_due_to_failed_recurring_charge?
      end

      test "returns false for business with expired trial" do
        @business.update! trial_expires_at: 1.day.ago
        assert_predicate @business, :trial_expired?

        refute_predicate @business, :disabled_due_to_failed_recurring_charge?
      end

      test "returns false for business with cancelled trial" do
        @business.update! trial_expires_at: 2.weeks.from_now
        @business.cancel_trial(@business.admins.first)
        assert_predicate @business, :trial_cancelled?

        refute_predicate @business, :disabled_due_to_failed_recurring_charge?
      end

      test "returns false for business in an enabled state" do
        assert_predicate @business, :enabled?

        refute_predicate @business, :disabled_due_to_failed_recurring_charge?
      end

      test "returns false for disabled business under billing attempts limit" do
        @business.downgrade_to_free_plan
        assert_predicate @business, :disabled?
        assert_predicate @business, :under_billing_attempts_limit?

        refute_predicate @business, :disabled_due_to_failed_recurring_charge?
      end

      test "returns false for disabled business over billing attempts limit and dunning period not expired" do
        @business.downgrade_to_free_plan
        @business.customer.update! billing_attempts: 3, billing_end_date: 1.week.ago
        @business.stubs(:never_successfully_billed?).returns false
        @business.reload
        assert_predicate @business, :disabled?
        assert_predicate @business, :over_billing_attempts_limit?
        refute_predicate @business, :dunning_period_expired?

        refute_predicate @business, :disabled_due_to_failed_recurring_charge?
      end

      test "returns false for disabled business under billing attempts limit and dunning period expired" do
        @business.downgrade_to_free_plan
        @business.customer.update! billing_end_date: 3.weeks.ago
        @business.reload
        assert_predicate @business, :disabled?
        assert_predicate @business, :under_billing_attempts_limit?
        assert_predicate @business, :dunning_period_expired?

        refute_predicate @business, :disabled_due_to_failed_recurring_charge?
      end

      test "returns true for disabled business over billing attempts limit and dunning period expired" do
        @business.downgrade_to_free_plan
        @business.customer.update! billing_attempts: 3, billing_end_date: 3.weeks.ago
        @business.reload
        assert_predicate @business, :disabled?
        assert_predicate @business, :over_billing_attempts_limit?
        assert_predicate @business, :dunning_period_expired?

        assert_predicate @business, :disabled_due_to_failed_recurring_charge?
      end
    end
  end

  context "#update_customer_name" do
    if GitHub.billing_enabled?
      test "queues the UpdateExternalCustomerJob to update the Zuora account" do
        with_live_zuora("zuora/update_business_customer_name") do
          business = create :business
          zuora_successful_customer_account_creation(business)
          customer = business.reload.customer

          assert_enqueued_with(job: UpdateExternalCustomerJob, args: [customer]) do
            business.update_customer_name
          end
        end
      end

      test "updates customer name, bill_to, and sold_to to match name of Business" do
        with_live_zuora("zuora/update_business_customer_name") do
          business = create :business
          zuora_successful_customer_account_creation(business)
          customer = business.reload.customer

          before_update_account = customer.zuora_account
          refute_equal business.name, before_update_account["basicInfo"]["name"]
          refute_equal business.name, before_update_account["billToContact"]["firstName"]
          refute_equal business.name, before_update_account["billToContact"]["lastName"]
          refute_equal business.name, before_update_account["soldToContact"]["firstName"]
          refute_equal business.name, before_update_account["soldToContact"]["lastName"]

          business.update_column(:name, "updated-name")
          perform_enqueued_jobs(only: UpdateExternalCustomerJob) do
            business.update_customer_name
          end

          after_update_account = customer.zuora_account
          assert_equal business.name, after_update_account["basicInfo"]["name"]
          assert_equal business.name, after_update_account["billToContact"]["firstName"]
          assert_equal business.name, after_update_account["billToContact"]["lastName"]
          assert_equal business.name, after_update_account["soldToContact"]["firstName"]
          assert_equal business.name, after_update_account["soldToContact"]["lastName"]
        end
      end
    end
  end

  context "show_volume_license_spend_tile?" do
    if GitHub.billing_enabled?
      test "returns true if a user is not self serve but sales managed " do
        Business.any_instance.stubs(:owner?).returns(true)

        user = create(:user)
        @business.can_self_serve = false
        @business.save!

        assert @business.show_volume_license_spend_tile?(user)
      end

      test "returns false if a user is not a billing mananger or owner" do
        Business.any_instance.stubs(:owner?).returns(false)

        user = create(:user)

        refute @business_with_self_serve_payment.show_volume_license_spend_tile?(user)
      end

      test "returns false for metered business" do
        @business_with_self_serve_payment.customer.update!(metered_ghe: true)
        assert_predicate @business_with_self_serve_payment.reload, :metered_ghe?

        owner = @business_with_self_serve_payment.owners.first

        refute @business_with_self_serve_payment.show_volume_license_spend_tile?(owner)
      end

      test "returns false if a business is in trial" do
        Business.any_instance.stubs(:owner?).returns(true)
        Business.any_instance.stubs(:trial?).returns(true)

        user = create(:user)

        refute @business_with_self_serve_payment.show_volume_license_spend_tile?(user)
      end

      test "returns true if a business is invoiced" do
        Business.any_instance.stubs(:owner?).returns(true)
        Business.any_instance.stubs(:invoiced?).returns(true)

        user = create(:user)

        assert @business_with_self_serve_payment.show_volume_license_spend_tile?(user)
      end

      test "returns true if a user is an owner and business can self serve and is non trial" do
        Business.any_instance.stubs(:owner?).returns(true)

        user = create(:user)

        assert @business_with_self_serve_payment.show_volume_license_spend_tile?(user)
      end
    end
  end

  context "#free_plan?" do
    if GitHub.billing_enabled?
      test "returns true if the business is on a free plan" do
        @business.downgrade_to_free_plan
        assert_predicate @business, :free_plan?
      end

      test "returns false if the business is on a paid plan" do
        refute_predicate @business, :free_plan?
      end
    end
  end

  context "#paid_plan?" do
    if GitHub.billing_enabled?
      test "returns true if the business is on a paid plan" do
        assert_predicate @business, :paid_plan?
      end

      test "returns false if the business is on a free plan" do
        @business.downgrade_to_free_plan
        refute_predicate @business, :paid_plan?
      end
    end
  end

  context "#bill_cycle_day_editable_in_stafftools?" do
    test "returns false if business is not eligible for self serve payment" do
      Business.any_instance.stubs(:eligible_for_self_serve_payment?).returns(false)
      @business.customer.update!(billed_via_billing_platform: false)

      refute @business.bill_cycle_day_editable_in_stafftools?
    end

    test "returns true if business is not on billing platform and eligible for self serve payment" do
      Business.any_instance.stubs(:eligible_for_self_serve_payment?).returns(true)
      @business.customer.update!(billed_via_billing_platform: false)

      assert @business.bill_cycle_day_editable_in_stafftools?
    end

    test "returns true if business is on billing platform and eligible for self serve payment" do
      Business.any_instance.stubs(:eligible_for_self_serve_payment?).returns(true)
      @business.customer.update!(billed_via_billing_platform: true)

      assert @business.bill_cycle_day_editable_in_stafftools?
    end
  end


  context "#aggregated_asset_status" do
    test "returns aggregated asset status for owned orgs" do
      create :asset_status, owner: @org1, asset_packs: 2
      create :asset_status, owner: @org2, asset_packs: 5

      expected = {
        asset_packs: @org1.asset_status.asset_packs + @org2.asset_status.asset_packs,
        bandwidth_usage: @org1.asset_status.bandwidth_usage + @org2.asset_status.bandwidth_usage,
        bandwidth_quota: @org1.asset_status.bandwidth_quota + @org2.asset_status.bandwidth_quota,
        storage_usage: @org1.asset_status.storage_usage + @org2.asset_status.storage_usage,
        storage_quota: @org1.asset_status.storage_quota + @org2.asset_status.storage_quota,
      }
      assert_equal expected, @business.aggregated_asset_status
    end

    test "works for businesses without any orgs" do
      @business.organizations.destroy_all
      expected = {
        asset_packs: 0,
        bandwidth_usage: 0.0,
        bandwidth_quota: 0.0,
        storage_usage: 0.0,
        storage_quota: 0.0,
      }
      assert_equal expected, @business.reload.aggregated_asset_status
    end
  end

  context "#bandwidth_usage_percentage" do
    test "returns bandwidth usage percentage for owned orgs" do
      create :asset_status, owner: @org1, asset_packs: 2, bandwidth_down: 0.2, storage: 0.2
      create :asset_status, owner: @org2, asset_packs: 5, bandwidth_down: 0.2, storage: 0.2

      assert_equal 0, @business.bandwidth_usage_percentage
    end

    test "works for businesses without any orgs" do
      @business.organizations.destroy_all
      assert_equal 0, @business.bandwidth_usage_percentage
    end
  end

  context "#storage_usage_percentage" do
    test "returns storage usage percentage for owned orgs" do
      create :asset_status, owner: @org1, asset_packs: 2, bandwidth_down: 0.2, storage: 0.2
      create :asset_status, owner: @org2, asset_packs: 5, bandwidth_down: 0.2, storage: 0.2

      assert_equal 0, @business.storage_usage_percentage
    end

    test "works for businesses without any orgs" do
      @business.organizations.destroy_all
      assert_equal 0, @business.storage_usage_percentage
    end
  end

  context "#can_be_authorized?" do
    if GitHub.billing_enabled?
      test "returns true for non tier one businesses (trial businesses) with a payment method" do
        @business_with_self_serve_payment.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        create(:billing_budget, owner: @business_with_self_serve_payment)

        assert @business_with_self_serve_payment.can_be_authorized?
      end

      test "returns false for businesses metered via Azure" do
        business = create(:business, :with_azure_subscription)
        business.customer.update!(metered_via_azure: true)

        business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        create(:billing_budget, owner: business)

        refute business.can_be_authorized?
      end

      test "returns false for trial businesses without a payment method" do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        create(:billing_budget, owner: @business)

        refute @business.can_be_authorized?
      end

      test "returns false for non-trial businesses with established billing history" do
        create(:billing_budget, owner: @business_with_self_serve_payment)
        create(:billing_transaction, :zuora, customer: @business_with_self_serve_payment.customer, asset_packs_total: 5, created_at: 10.days.ago)
        create(:billing_transaction, :zuora, customer: @business_with_self_serve_payment.customer, asset_packs_total: 5, created_at: 66.days.ago)

        refute @business_with_self_serve_payment.trial?
        refute @business_with_self_serve_payment.can_be_authorized?
      end

      test "returns true for non tier one businesses (trial businesses) with a payment method on billing platform" do
        @business_with_self_serve_payment.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        @business_with_self_serve_payment.customer.billed_via_billing_platform = true

        assert @business_with_self_serve_payment.trial?
        assert @business_with_self_serve_payment.can_be_authorized?
      end

      test "returns true for paypal payment method" do
        business_with_paypal_payment = create(:business, :with_paypal)
        business_with_paypal_payment.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        create(:billing_budget, owner: business_with_paypal_payment)

        assert business_with_paypal_payment.can_be_authorized?
      end
    end
  end

  context "#run_trial_authorization" do
    if GitHub.billing_enabled?
      test "returns false if business is not on a trial" do
        @business.update! dfd_trial: true

        refute @business.run_trial_authorization
      end

      test "returns false for non-DFD trial business" do
        refute @business_trial_with_credit_card.run_trial_authorization
      end

      test "returns false if the business is in a non-active trial state" do
        @business_trial_with_credit_card.update! dfd_trial: true
        @business_trial_with_credit_card.expire_trial(@business_trial_with_credit_card.owners.first)

        assert @business_trial_with_credit_card.trial?
        refute @business_trial_with_credit_card.no_trial_or_active_trial?
        refute @business_trial_with_credit_card.run_trial_authorization
      end

      test "returns false if business does not have a customer" do
        @business_trial_with_credit_card.update! dfd_trial: true
        @business_trial_with_credit_card.customer.destroy!
        assert_nil @business_trial_with_credit_card.reload.customer

        refute @business_trial_with_credit_card.run_trial_authorization
      end

      test "returns false if the business does not have a valid payment method on file" do
        @business_trial_with_credit_card.update! dfd_trial: true
        @business_trial_with_credit_card.payment_method.destroy!
        assert_nil @business_trial_with_credit_card.reload.payment_method

        refute @business_trial_with_credit_card.run_trial_authorization
      end

      test "returns false if there is already an authorization in progress" do
        @business_trial_with_credit_card.update! dfd_trial: true
        unsuccessful_transaction = create(
          :billing_transaction,
          customer_id: @business_trial_with_credit_card.customer.id,
          transaction_type: "authorization",
          last_status: :authorizing
        )

        refute @business_trial_with_credit_card.run_trial_authorization
      end

      test "returns false if authorization fails" do
        @business_trial_with_credit_card.update! dfd_trial: true
        Billing::CreateAuthorizationBillingTransactionJob.expects(:perform_now).once.returns(false)

        refute @business_trial_with_credit_card.run_trial_authorization
      end

      test "emails business owners and billing manager to inform them if authorization fails" do
        @business_trial_with_credit_card.update! dfd_trial: true
        @business_trial_with_credit_card.customer.update!(billed_via_billing_platform: true)
        @business_trial_with_credit_card.billing.add_manager(
                      create(:user),
                      actor: @business_trial_with_credit_card.owners.first
                      )
        unsuccessful_transaction = create(
          :billing_transaction,
          customer_id: @business_trial_with_credit_card.customer.id,
          transaction_type: "authorization",
          last_status: :processor_declined
        )
        Billing::CreateAuthorizationBillingTransactionJob.expects(:perform_now).once.returns(false)

        perform_enqueued_jobs(only: ApplicationDeliveryJob) do
          refute @business_trial_with_credit_card.run_trial_authorization
        end

        mail = ActionMailer::Base.deliveries.last
        assert_same_elements mail.bcc,
        @business_trial_with_credit_card.owners.map(&:email) + @business_trial_with_credit_card.billing.managers.map(&:email)
        assert_equal "[GitHub] We were unable to verify your identity using your credit card", mail.subject
      end

      test "returns true without calling authorization job if customer is being billed through Azure" do
        @business_metered_trial.update! dfd_trial: true
        # We destroy enterprise agreements because azure subscribed trials may not have them.
        @business_metered_trial.enterprise_agreements.destroy_all
        Billing::CreateAuthorizationBillingTransactionJob.expects(:perform_now).never

        assert @business_metered_trial.run_trial_authorization
      end

      test "returns true if authorization succeeds for a business with a credit card" do
        @business_trial_with_credit_card.update! dfd_trial: true
        Billing::CreateAuthorizationBillingTransactionJob.expects(:perform_now).once.returns(true)

        assert @business_trial_with_credit_card.run_trial_authorization
      end
    end
  end

  context "#show_payment_due_tile?" do
    if GitHub.billing_enabled?
      test "returns false if a user cannot self serve" do
        Business.any_instance.stubs(:owner?).returns(true)

        user = create(:user)
        @business.can_self_serve = false
        @business.save!

        refute @business.show_payment_due_tile?(user)
      end

      test "returns false if a user is not a billing mananger or owner" do
        Business.any_instance.stubs(:owner?).returns(false)

        user = create(:user)

        refute @business_with_self_serve_payment.show_payment_due_tile?(user)
      end

      test "returns false if a business is in trial" do
        Business.any_instance.stubs(:owner?).returns(true)
        Business.any_instance.stubs(:trial?).returns(true)

        user = create(:user)

        refute @business_with_self_serve_payment.show_payment_due_tile?(user)
      end

      test "returns false if a business is invoiced" do
        Business.any_instance.stubs(:owner?).returns(true)
        Business.any_instance.stubs(:invoiced?).returns(true)

        user = create(:user)

        refute @business_with_self_serve_payment.show_payment_due_tile?(user)
      end

      test "returns true if a user is an owner and business can self serve and is non trial" do
        Business.any_instance.stubs(:owner?).returns(true)

        user = create(:user)

        assert @business_with_self_serve_payment.show_payment_due_tile?(user)
      end
    end
  end

  context "#show_past_invoices_tab?" do
    if GitHub.billing_enabled?
      test "returns false if a user is not a billing mananger or owner" do
        user = create(:user)

        refute @business.show_past_invoices_tab?(user)
      end

      test "returns false if business does NOT pay GitHub directly" do
        @business.add_owner @owner, actor: @owner

        refute @business_with_azure_subscription.show_past_invoices_tab?(@owner)
      end

      test "returns false if business is self-serve" do
        @business.add_owner @owner, actor: @owner

        refute @business_with_self_serve_payment.show_past_invoices_tab?(@owner)
      end

      test "returns true if business is a reseller customer" do
        @business.add_owner @owner, actor: @owner
        Business.any_instance.stubs(:reseller_customer?).returns(true)

        refute @business.show_past_invoices_tab?(@owner)
      end

      test "returns true if a business is invoiced" do
        @business.add_owner @owner, actor: @owner
        Business.any_instance.stubs(:invoiced?).returns(true)

        assert @business.show_past_invoices_tab?(@owner)
      end
    end
  end

  context "billed_via_billing_platform?" do
    test "returns false if the business is not billed_via_billing_platform" do
      @business.customer.update!(billed_via_billing_platform: false)
      refute @business.billed_via_billing_platform?
    end

    test "returns true if the business is billed_via_billing_platform" do
      @business.customer.update!(billed_via_billing_platform: true)
      assert @business.billed_via_billing_platform?
    end
  end

  context "#remove_azure_subscription_on_adding_cc_paypal?" do
    if GitHub.single_business_environment?
      test "returns false for single business environment" do
        refute_predicate @business, :remove_azure_subscription_on_adding_cc_paypal?
      end
    else
      test "returns false for non-metered business" do
        refute_predicate @business, :metered_ghe?

        refute_predicate @business, :remove_azure_subscription_on_adding_cc_paypal?
      end

      test "returns false for metered business with no azure subscription" do
        @business.customer.update!(metered_ghe: true)
        @business.reload
        assert_predicate @business, :metered_ghe?
        refute_predicate @business, :linked_azure_subscription?

        refute_predicate @business, :remove_azure_subscription_on_adding_cc_paypal?
      end

      test "returns true for metered business with azure subscription" do
        @business.customer.update!(
          metered_ghe: true,
          azure_subscription_id: "80e769f2-ce0f-11ed-afa1-0242ac120002",
          azure_subscription_name: "My subscription"
        )
        @business.reload
        assert_predicate @business, :metered_ghe?
        assert_predicate @business, :linked_azure_subscription?

        assert_predicate @business, :remove_azure_subscription_on_adding_cc_paypal?
      end
    end
  end

  context "#clear_azure_subscription_references!" do
    test "test azure subscription references cleared" do
      @business.customer.update!(
        azure_subscription_id: "80e769f2-ce0f-11ed-afa1-0242ac120002",
        azure_subscription_name: "My subscription"
      )
      assert_predicate @business.reload, :linked_azure_subscription?

      @business.clear_azure_subscription_references!
      refute_predicate @business.reload, :linked_azure_subscription?
    end
  end

  context "#validate_purchases_allowed", skip_enterprise: true do
    test "allowed for business in good standing" do
      result = @business.validate_purchases_allowed

      assert result.success?
    end

    test "not allowed for spammy businesses" do
      @business.update(spammy: true)
      assert @business.spammy?

      result = @business.validate_purchases_allowed

      assert result.failed?
      assert result.error_message.include?("Your account is flagged and unable to make purchases")
    end

    test "not allowed for spammy actors when actor is provided" do
      user = create(:spammy_user)
      assert user.spammy?
      refute @business.spammy?

      result = @business.validate_purchases_allowed(actor: user)

      assert result.failed?
      assert result.error_message.include?("Your account is flagged and unable to make purchases")
    end

    test "allowed for disabled businesses when check_disabled is false" do
      user = create(:billing_locked_user)
      assert user.disabled?

      result = user.validate_purchases_allowed(check_disabled: false)

      assert result.success?
    end

    test "not allowed for disabled businesses when check_disabled is true" do
      @business.update(downgraded_at: GitHub::Billing.now)
      assert @business.disabled?

      result = @business.validate_purchases_allowed(check_disabled: true)

      assert result.failed?
      assert result.error_message.include?("Your account is currently locked from purchases")
    end

    test "allowed for businesses in dunning when check_dunning is false" do
      @business.set_billing_attempts(1)
      assert @business.dunning?

      result = @business.validate_purchases_allowed(check_dunning: false)

      assert result.success?
    end

    test "not allowed for businesses in dunning when check_dunning is true" do
      @business.set_billing_attempts(1)
      assert @business.dunning?

      result = @business.validate_purchases_allowed(check_dunning: true)

      assert result.failed?
      assert result.error_message.include?("Your account is currently locked from purchases")
    end

    test "allowed for trade restricted businesses when check_trade_restrictions is false" do
      Business.any_instance.stubs(:has_any_trade_restrictions?).returns(true)

      result = @business.validate_purchases_allowed(check_trade_restrictions: false)

      assert result.success?
    end

    test "not allowed for trade restricted businesses when check_trade_restrictions is true" do
      Business.any_instance.stubs(:has_any_trade_restrictions?).returns(true)

      result = @business.validate_purchases_allowed(check_trade_restrictions: true)

      assert result.failed?
      assert result.error_message.include?("Due to U.S. trade controls law restrictions, your GitHub account has been restricted")
    end
  end

  context "#shipping_information_required?" do
    if GitHub.single_business_environment?
      test "returns false for single business environment" do
        refute_predicate @business, :shipping_information_required?
      end
    else
      test "returns false for non-metered business" do
        refute_predicate @business, :metered_ghe?

        refute_predicate @business, :shipping_information_required?
      end

      test "returns true for metered business" do
        @business.customer.update! metered_ghe: true

        assert_predicate @business, :shipping_information_required?
      end
    end
  end

  context "#hide_non_azure_payment_methods?" do
    test "returns false for non-multitenant mode with feature flag disabled", skip_in_multitenant_mode: true do
      disable_feature_flag(:hide_non_azure_payment_methods)
      assert !@business.hide_non_azure_payment_methods?
    end

    test "returns false for non-multitenant mode with feature flag enabled", skip_in_multitenant_mode: true do
      enable_feature_flag(:hide_non_azure_payment_methods)
      assert !@business.hide_non_azure_payment_methods?
    end

    test "returns false for multitenant mode with feature flag disabled", skip_unless: :multi_tenant_enterprise_test_mode? do
      disable_feature_flag(:hide_non_azure_payment_methods)
      assert !@business.hide_non_azure_payment_methods?
    end

    test "returns true for multitenant mode with feature flag enabled", skip_unless: :multi_tenant_enterprise_test_mode? do
      enable_feature_flag(:hide_non_azure_payment_methods)
      assert @business.hide_non_azure_payment_methods?
    end
  end

  context "#disable_legacy_billing_page?" do
    test "returns false for non vnext customer" do
      @business.customer.update!(billed_via_billing_platform: false)
      refute @business.disable_legacy_billing_page?
    end

    test "returns false for vnext native customer" do
      @business.customer.update!(created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE + 1.day)
      refute @business.disable_legacy_billing_page?
    end

    test "returns false for vnext beta customer created before GA, billing through vnext but don't have 'migration_date' set" do
      @business.customer.update!(created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE - 1.day, billed_via_billing_platform: true)
      create :billing_platform_enabled_product, customer: @business.customer, migration_date: nil
      refute @business.disable_legacy_billing_page?
    end

    test "returns false for vnext customer created before GA, billing through vnext and have 'migration_date' of 10 days ago" do
      @business.customer.update!(created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE - 1.day, billed_via_billing_platform: true)
      create :billing_platform_enabled_product, customer: @business.customer, migration_date: 10.days.ago
      refute @business.disable_legacy_billing_page?
    end

    test "returns true for vnext customer created before GA, billing through vnext and have 'migration_date' of 31 days ago" do
      @business.customer.update!(created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE - 1.day, billed_via_billing_platform: true)
      create :billing_platform_enabled_product, customer: @business.customer, migration_date: 31.days.ago
      assert @business.disable_legacy_billing_page?
    end
  end

  context "#cost_centers" do
    test "properly queries cost centers via billing platform client" do
      ::Billing::Platform::Api::Client.any_instance.expects(:get_all_cost_centers).with(customer_id: @business.customer.id.to_s, use_cache: true).returns(
        {
          costCenters: []
        }
      )

      cost_centers = @business.cost_centers
      assert_equal 0, cost_centers.count
      assert_dogstats_increment("businesses.billing_platform.get_all_cost_centers", tags: ["status:success"])
    end

    test "returns nil when error" do
      ::Billing::Platform::Api::Client.any_instance.stubs(:get_all_cost_centers).returns(Billing::Platform::Api::Error.new("Error"))

      cost_centers = @business.cost_centers
      assert_nil cost_centers
      assert_dogstats_increment("businesses.billing_platform.get_all_cost_centers", tags: ["status:error"])
    end
  end

  context "show_volume_license_spend_tile_for_business?" do
    if GitHub.billing_enabled?
      test "returns false if Business not metered ghe and is copilot standalone" do
        Business.any_instance.stubs(:metered_ghe?).returns(false)
        business = create(:business, seats_plan_type: :basic)
        refute business.show_volume_license_spend_tile_for_business?
      end

      test "returns true if Business is metered ghe and is not copilot standalone and not trial" do
        assert @business.show_volume_license_spend_tile_for_business?
      end
    end
  end
end
