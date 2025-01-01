# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::Webhooks::PaymentProcessedTest < GitHub::BillingTestCase
  include DogstatsTestHelpers
  include GitHub::Billing::CurrencyTestHelper
  include GitHub::ZuoraTestHelper
  include AuditLog::IntegrationTestHelpers

  setup do
    setup_currency_exchange
  end

  context "#perform" do
    test "updates zuora subscription ids when user subscription isn't found" do
      synchronize_github_products_to_zuora
      user = create(:user, plan: :pro, billed_on: GitHub::Billing.today + 1.month)
      zuora_successful_customer_account_creation(user)
      user.reload

      with_live_zuora("zuora/payment_processed_webhook_attach_subscription") do
        user.customer.update(bill_cycle_day: user.billed_on.day)
        plan_subscription = user.plan_subscription
        payment_id = "2c92c0fa6205232601622035ebfc5334"

        webhook = build(
          :zuora_webhook,
          :payment_processed,
          account_id: plan_subscription.zuora_account_id,
          payload: { "AccountId" => plan_subscription.zuora_account_id, "PaymentId" => payment_id },
        )

        assert_nil user.plan_subscription.zuora_subscription_number

        assert_difference "Billing::BillingTransaction.count", 1 do
          webhook.perform
        end

        assert_dogstats_increment("billing.missing_zuora_subscription.count",
          tags: ["class:billing/zuora/webhooks/payment_processed"]
        )

        user.reload

        assert_predicate webhook, :processed?

        billing_transaction = Billing::BillingTransaction.last
        assert_equal plan_subscription, T.must(billing_transaction).plan_subscription
        assert_equal payment_id, T.must(billing_transaction).platform_transaction_id
        refute_nil user.plan_subscription.zuora_subscription_number
      end
    end

    test "updates zuora subscription ids when business subscription isn't found" do
      synchronize_github_products_to_zuora
      business = create(:business, :with_self_serve_payment)
      zuora_successful_customer_account_creation(business)
      business.reload

      with_live_zuora("zuora/business_payment_processed_webhook_attach_subscription") do
        business.customer.update(bill_cycle_day: business.billed_on.day)
        plan_subscription = business.plan_subscription
        payment_id = "8ad095dd806f5e4a018070bda71b5a2e"

        webhook = build(
          :zuora_webhook,
          :payment_processed,
          account_id: plan_subscription.zuora_account_id,
          payload: { "AccountId" => plan_subscription.zuora_account_id, "PaymentId" => payment_id },
        )

        assert_nil business.plan_subscription.zuora_subscription_number

        assert_difference "Billing::BillingTransaction.count", 1 do
          webhook.perform
        end

        business.reload

        assert_predicate webhook, :processed?

        billing_transaction = Billing::BillingTransaction.last
        assert_equal plan_subscription, T.must(billing_transaction).plan_subscription
        assert_equal payment_id, T.must(billing_transaction).platform_transaction_id
        refute_nil business.plan_subscription.zuora_subscription_number
      end
    end

    test "marks a business trial as converted if its trial conversion has been initiated" do
      synchronize_github_products_to_zuora
      business = create(:business, :with_self_serve_payment, trial_expires_at: 1.month.from_now)
      business.initiate_trial_conversion
      zuora_successful_customer_account_creation(business)
      business.reload

      assert_predicate business, :trial?
      assert_predicate business, :trial_conversion_initiated?

      with_live_zuora("zuora/business_payment_processed_webhook_attach_subscription") do
        business.customer.update(bill_cycle_day: business.billed_on.day)
        plan_subscription = business.plan_subscription
        payment_id = "8ad095dd806f5e4a018070bda71b5a2e"

        webhook = build(
          :zuora_webhook,
          :payment_processed,
          account_id: plan_subscription.zuora_account_id,
          payload: { "AccountId" => plan_subscription.zuora_account_id, "PaymentId" => payment_id },
        )

        assert_nil business.plan_subscription.zuora_subscription_number

        events = assert_performed_audit_entries(count: 1, only: "billing.payment_processed") do
          assert_difference "Billing::BillingTransaction.count", 1 do
            webhook.perform
          end
        end

        business.reload

        assert_predicate webhook, :processed?
        expected_payload = {
          action: "billing.payment_processed",
          business: business.display_login,
          business_id: business.id,
          payment_method_id: events.first[:payment_method_id],
          payment_amount: 2500000,
          attempt_number: 1,
          processor_response_code: "200",
          trial_completion_status_before_processing: "trial_conversion_initiated",
          trial_completion_status_after_processing: "trial_converted",
        }
        assert_subset_hash expected_payload, events.first

        billing_transaction = Billing::BillingTransaction.last
        assert_equal plan_subscription, T.must(billing_transaction).plan_subscription
        assert_equal payment_id, T.must(billing_transaction).platform_transaction_id
        refute_nil business.plan_subscription.zuora_subscription_number
        refute_predicate business, :trial?
        assert_predicate business, :trial_converted?
      end
    end

    test "marks a business trial as converted if a payment has been processed for an RBI-affected customer" do
      synchronize_github_products_to_zuora
      business = create(:business, :with_self_serve_payment, trial_expires_at: 1.month.from_now)
      zuora_successful_customer_account_creation(business)

      business.reload
      business.payment_method.update!(country: "IND")
      business.disable_automatic_self_serve_payment(User.ghost, reason: :india_rbi)
      assert_predicate business.customer, :autopay_disabled_by_india_rbi?
      assert_predicate business, :trial?
      refute_predicate business, :trial_conversion_initiated?

      with_live_zuora("zuora/business_rbi_convert_trial_payment_processed_webhook") do
        business.customer.update(bill_cycle_day: business.billed_on.day)
        plan_subscription = business.plan_subscription
        payment_id = "8ad095dd806f5e4a018070bda71b5a2e"

        webhook = build(
          :zuora_webhook,
          :payment_processed,
          account_id: plan_subscription.zuora_account_id,
          payload: { "AccountId" => plan_subscription.zuora_account_id, "PaymentId" => payment_id },
        )

        assert_difference "Billing::BillingTransaction.count", 1 do
          webhook.perform
        end

        business.reload

        assert_predicate webhook, :processed?

        refute_predicate business, :automatic_self_serve_payment_enabled?
        assert_predicate business, :autopay_disabled_by_india_rbi?
        refute_predicate business, :trial?
        assert_predicate business, :trial_converted?
      end
    end

    test "does not mark a business trial as converted if its trial conversion has not been initiated" do
      synchronize_github_products_to_zuora
      business = create(:business, :with_self_serve_payment, trial_expires_at: 1.month.from_now)
      zuora_successful_customer_account_creation(business)
      business.reload

      assert_predicate business, :trial?
      refute_predicate business, :trial_conversion_initiated?

      with_live_zuora("zuora/business_payment_processed_webhook_attach_subscription") do
        business.customer.update(bill_cycle_day: business.billed_on.day)
        plan_subscription = business.plan_subscription
        payment_id = "8ad095dd806f5e4a018070bda71b5a2e"

        webhook = build(
          :zuora_webhook,
          :payment_processed,
          account_id: plan_subscription.zuora_account_id,
          payload: { "AccountId" => plan_subscription.zuora_account_id, "PaymentId" => payment_id },
        )

        assert_nil business.plan_subscription.zuora_subscription_number

        events = assert_performed_audit_entries(count: 1, only: "billing.payment_processed") do
          assert_difference "Billing::BillingTransaction.count", 1 do
            webhook.perform
          end
        end

        business.reload

        assert_predicate webhook, :processed?
        expected_payload = {
          action: "billing.payment_processed",
          business: business.display_login,
          business_id: business.id,
          payment_method_id: events.first[:payment_method_id],
          payment_amount: 2500000,
          attempt_number: 1,
          processor_response_code: "200",
          processor_response: "Approved",
          trial_completion_status_before_processing: "no_trial_or_active_trial",
          trial_completion_status_after_processing: "no_trial_or_active_trial",
        }
        assert_subset_hash expected_payload, events.first

        billing_transaction = Billing::BillingTransaction.last
        assert_equal plan_subscription, T.must(billing_transaction).plan_subscription
        assert_equal payment_id, T.must(billing_transaction).platform_transaction_id
        refute_nil business.plan_subscription.zuora_subscription_number
        assert_predicate business, :trial?
        refute_predicate business, :trial_converted?
      end
    end

    test "marks a business created from an upgrading org as organization_upgrade_completed if the organization upgrade purchase was successful, and adds the upgrading organization", skip_enterprise: true do
      synchronize_github_products_to_zuora
      business = create(:business, :with_self_serve_payment)
      business.initiate_organization_upgrade
      business.initiate_organization_upgrade_purchase
      zuora_successful_customer_account_creation(business)
      business.reload

      assert_predicate business, :organization_upgrade_purchase_initiated?
      refute_predicate business, :organization_upgrade_completed?

      with_live_zuora("zuora/business_payment_processed_webhook_attach_subscription") do
        business.customer.update(bill_cycle_day: business.billed_on.day)
        plan_subscription = business.plan_subscription
        payment_id = "8ad095dd806f5e4a018070bda71b5a2e"

        webhook = build(
          :zuora_webhook,
          :payment_processed,
          account_id: plan_subscription.zuora_account_id,
          payload: { "AccountId" => plan_subscription.zuora_account_id, "PaymentId" => payment_id },
        )

        assert_nil business.plan_subscription.zuora_subscription_number

        events = assert_performed_audit_entries(count: 1, only: "billing.payment_processed") do
          assert_difference "Billing::BillingTransaction.count", 1 do
            webhook.perform
          end
        end

        business.reload

        assert_predicate webhook, :processed?
        expected_payload = {
          action: "billing.payment_processed",
          business: business.display_login,
          business_id: business.id,
          payment_method_id: events.first[:payment_method_id],
          payment_amount: 2500000,
          attempt_number: 1,
          processor_response_code: "200",
          trial_completion_status_before_processing: "organization_upgrade_purchase_initiated",
          trial_completion_status_after_processing: "organization_upgrade_completed",
        }
        assert_subset_hash expected_payload, events.first

        billing_transaction = Billing::BillingTransaction.last
        assert_equal plan_subscription, T.must(billing_transaction).plan_subscription
        assert_equal payment_id, T.must(billing_transaction).platform_transaction_id
        refute_nil business.plan_subscription.zuora_subscription_number

        refute_predicate business, :organization_upgrade_purchase_initiated?
        assert_predicate business, :organization_upgrade_completed?
      end
    end

    test "does not mark a business created from an upgrading org as organization_upgrade_completed if the organization upgrade purchase has not been initiated", skip_enterprise: true do
      synchronize_github_products_to_zuora
      business = create(:business, :with_self_serve_payment)
      business.initiate_organization_upgrade
      zuora_successful_customer_account_creation(business)
      business.reload

      assert_predicate business, :organization_upgrade_initiated?
      refute_predicate business, :organization_upgrade_purchase_initiated?
      refute_predicate business, :organization_upgrade_completed?

      with_live_zuora("zuora/business_payment_processed_webhook_attach_subscription") do
        business.customer.update(bill_cycle_day: business.billed_on.day)
        plan_subscription = business.plan_subscription
        payment_id = "8ad095dd806f5e4a018070bda71b5a2e"

        webhook = build(
          :zuora_webhook,
          :payment_processed,
          account_id: plan_subscription.zuora_account_id,
          payload: { "AccountId" => plan_subscription.zuora_account_id, "PaymentId" => payment_id },
        )

        assert_nil business.plan_subscription.zuora_subscription_number

        events = assert_performed_audit_entries(count: 1, only: "billing.payment_processed") do
          assert_difference "Billing::BillingTransaction.count", 1 do
            webhook.perform
          end
        end

        business.reload

        assert_predicate webhook, :processed?
        expected_payload = {
          action: "billing.payment_processed",
          business: business.display_login,
          business_id: business.id,
          payment_method_id: events.first[:payment_method_id],
          payment_amount: 2500000,
          attempt_number: 1,
          processor_response_code: "200",
          trial_completion_status_before_processing: "organization_upgrade_initiated",
          trial_completion_status_after_processing: "organization_upgrade_initiated",
        }
        assert_subset_hash expected_payload, events.first

        billing_transaction = Billing::BillingTransaction.last
        assert_equal plan_subscription, T.must(billing_transaction).plan_subscription
        assert_equal payment_id, T.must(billing_transaction).platform_transaction_id
        refute_nil business.plan_subscription.zuora_subscription_number

        assert_predicate business, :organization_upgrade_initiated?
        refute_predicate business, :organization_upgrade_purchase_initiated?
        refute_predicate business, :organization_upgrade_completed?
      end
    end

    test "marks a business created from a coupon as created_from_coupon if an outstanding payment was successful", skip_enterprise: true do
      GitHub.flipper[:new_ea_creation_from_coupon].enable
      synchronize_github_products_to_zuora
      business = create(:business, :with_self_serve_payment)
      business.initiate_creation_from_coupon
      business.initiate_creation_purchase_from_coupon
      zuora_successful_customer_account_creation(business)
      business.reload

      assert_predicate business, :creation_from_coupon_purchase_initiated?
      refute_predicate business, :created_from_coupon?

      with_live_zuora("zuora/business_payment_processed_webhook_attach_subscription") do
        business.customer.update(bill_cycle_day: business.billed_on.day)
        plan_subscription = business.plan_subscription
        payment_id = "8ad095dd806f5e4a018070bda71b5a2e"

        webhook = build(
          :zuora_webhook,
          :payment_processed,
          account_id: plan_subscription.zuora_account_id,
          payload: { "AccountId" => plan_subscription.zuora_account_id, "PaymentId" => payment_id },
        )

        assert_nil business.plan_subscription.zuora_subscription_number

        events = assert_performed_audit_entries(count: 1, only: "billing.payment_processed") do
          assert_difference "Billing::BillingTransaction.count", 1 do
            webhook.perform
          end
        end

        business.reload

        assert_predicate webhook, :processed?
        expected_payload = {
          action: "billing.payment_processed",
          business: business.display_login,
          business_id: business.id,
          payment_method_id: events.first[:payment_method_id],
          payment_amount: 2500000,
          attempt_number: 1,
          processor_response_code: "200",
          trial_completion_status_before_processing: "creation_from_coupon_purchase_initiated",
          trial_completion_status_after_processing: "created_from_coupon",
        }
        assert_subset_hash expected_payload, events.first

        billing_transaction = Billing::BillingTransaction.last
        assert_equal plan_subscription, T.must(billing_transaction).plan_subscription
        assert_equal payment_id, T.must(billing_transaction).platform_transaction_id
        refute_nil business.plan_subscription.zuora_subscription_number

        refute_predicate business, :creation_from_coupon_purchase_initiated?
        assert_predicate business, :created_from_coupon?
      end
    end

    test "does not mark a business created from a coupon as created_from_coupon if an outstanding payment has not been initiated", skip_enterprise: true do
      GitHub.flipper[:new_ea_creation_from_coupon].enable
      synchronize_github_products_to_zuora
      business = create(:business, :with_self_serve_payment)
      business.initiate_creation_from_coupon
      zuora_successful_customer_account_creation(business)
      business.reload

      assert_predicate business, :creation_initiated_from_coupon?
      refute_predicate business, :creation_from_coupon_purchase_initiated?
      refute_predicate business, :created_from_coupon?

      with_live_zuora("zuora/business_payment_processed_webhook_attach_subscription") do
        business.customer.update(bill_cycle_day: business.billed_on.day)
        plan_subscription = business.plan_subscription
        payment_id = "8ad095dd806f5e4a018070bda71b5a2e"

        webhook = build(
          :zuora_webhook,
          :payment_processed,
          account_id: plan_subscription.zuora_account_id,
          payload: { "AccountId" => plan_subscription.zuora_account_id, "PaymentId" => payment_id },
        )

        assert_nil business.plan_subscription.zuora_subscription_number

        events = assert_performed_audit_entries(count: 1, only: "billing.payment_processed") do
          assert_difference "Billing::BillingTransaction.count", 1 do
            webhook.perform
          end
        end

        business.reload

        assert_predicate webhook, :processed?
        expected_payload = {
          action: "billing.payment_processed",
          business: business.display_login,
          business_id: business.id,
          payment_method_id: events.first[:payment_method_id],
          payment_amount: 2500000,
          attempt_number: 1,
          processor_response_code: "200",
          trial_completion_status_before_processing: "creation_initiated_from_coupon",
          trial_completion_status_after_processing: "creation_initiated_from_coupon",
        }
        assert_subset_hash expected_payload, events.first

        billing_transaction = Billing::BillingTransaction.last
        assert_equal plan_subscription, T.must(billing_transaction).plan_subscription
        assert_equal payment_id, T.must(billing_transaction).platform_transaction_id
        refute_nil business.plan_subscription.zuora_subscription_number

        assert_predicate business, :creation_initiated_from_coupon?
        refute_predicate business, :creation_from_coupon_purchase_initiated?
        refute_predicate business, :created_from_coupon?
      end
    end

    test "emails single owner of a business created from a coupon if an outstanding payment is processed successfully", skip_enterprise: true do
      GitHub.flipper[:new_ea_creation_from_coupon].enable
      synchronize_github_products_to_zuora
      business = create(:business, :with_self_serve_payment)
      business.initiate_creation_from_coupon
      business.initiate_creation_purchase_from_coupon
      zuora_successful_customer_account_creation(business)
      business.reload

      assert_predicate business, :creation_from_coupon_purchase_initiated?
      refute_predicate business, :created_from_coupon?

      with_live_zuora("zuora/business_payment_processed_webhook_email") do
        business.customer.update(bill_cycle_day: business.billed_on.day)
        plan_subscription = business.plan_subscription
        payment_id = "8ad095dd806f5e4a018070bda71b5a2e"

        webhook = build(
          :zuora_webhook,
          :payment_processed,
          account_id: plan_subscription.zuora_account_id,
          payload: { "AccountId" => plan_subscription.zuora_account_id, "PaymentId" => payment_id },
        )

        assert_nil business.plan_subscription.zuora_subscription_number

        events = assert_performed_audit_entries(count: 1, only: "billing.payment_processed") do
          assert_difference "Billing::BillingTransaction.count", 1 do
            perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
              webhook.perform
            end
          end
        end

        assert_predicate webhook, :processed?
        assert_predicate business.reload, :created_from_coupon?
        mail = ActionMailer::Base.deliveries.last
        assert_equal \
          "[GitHub] Welcome to GitHub Enterprise — Let's Get Started!",
          mail.subject
        assert_includes \
          mail.html_part.body.to_s,
          "Hi @#{business.owners.first.display_login}!"
        assert_includes mail.html_part.body.to_s,
          "Thank you for creating your GitHub Enterprise account, #{business}."
        assert_includes \
          mail.text_part.body.to_s,
          "Hi @#{business.owners.first.display_login}!"
        assert_includes mail.text_part.body.to_s,
          "Thank you for creating your GitHub Enterprise account, #{business}."

        expected_payload = {
          action: "billing.payment_processed",
          business: business.display_login,
          business_id: business.id,
          payment_method_id: events.first[:payment_method_id],
          payment_amount: 2500000,
          attempt_number: 1,
          processor_response_code: "200",
          trial_completion_status_before_processing: "creation_from_coupon_purchase_initiated",
          trial_completion_status_after_processing: "created_from_coupon",
        }
        assert_subset_hash expected_payload, events.first
        billing_transaction = Billing::BillingTransaction.last
        assert_equal plan_subscription, T.must(billing_transaction).plan_subscription
        assert_equal payment_id, T.must(billing_transaction).platform_transaction_id
        refute_nil business.plan_subscription.zuora_subscription_number
      end
    end

    test "emails all owners of a business created from a coupon if an outstanding payment is processed successfully and org is attached to business", skip_enterprise: true do
      GitHub.flipper[:new_ea_creation_from_coupon].enable
      synchronize_github_products_to_zuora
      business = create(:business, :with_self_serve_payment)
      org_to_attach = create :organization, plan: GitHub::Plan.free, admins: [business.owners.first, create(:user)]
      business.upgrade_initiated_from_organization_id = org_to_attach.id
      org_to_attach.upgrade_to_enterprise_in_progress!(business)
      org_to_attach.save!
      business.save!
      business.initiate_creation_from_coupon
      business.initiate_creation_purchase_from_coupon
      zuora_successful_customer_account_creation(business)
      business.reload

      assert_predicate business, :creation_from_coupon_purchase_initiated?
      refute_predicate business, :created_from_coupon?
      assert org_to_attach.admins.count > 1
      assert business.owners.count, 1

      with_live_zuora("zuora/business_payment_processed_webhook_email") do
        business.customer.update(bill_cycle_day: business.billed_on.day)
        plan_subscription = business.plan_subscription
        payment_id = "8ad095dd806f5e4a018070bda71b5a2e"

        webhook = build(
          :zuora_webhook,
          :payment_processed,
          account_id: plan_subscription.zuora_account_id,
          payload: { "AccountId" => plan_subscription.zuora_account_id, "PaymentId" => payment_id },
        )

        assert_nil business.plan_subscription.zuora_subscription_number

        events = assert_performed_audit_entries(count: 1, only: "billing.payment_processed") do
          assert_difference "Billing::BillingTransaction.count", 1 do
            perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
              assert_enqueued_jobs(1, only: BusinessCreatedFromOrganizationJob) do
                webhook.perform
              end
            end
          end
        end

        # BusinessCreatedFromOrganizationJob promotes org admins to business owners
        # asynchronously.
        # Only allowing BusinessCreatedFromOrganizationJob to run after the email job
        # has run, to verify that promoting org admins to business owners
        # after email is sent still results in all business owners
        # receiving the email
        perform_enqueued_jobs(only: [BusinessCreatedFromOrganizationJob])
        assert_same_elements business.reload.owners, org_to_attach.admins

        assert_predicate webhook, :processed?
        assert_predicate business.reload, :created_from_coupon?
        assert_equal business.organizations, [org_to_attach]

        mail = ActionMailer::Base.deliveries.last
        assert_same_elements mail.bcc, business.admins.map { |user| user.email }
        assert_equal \
          "[GitHub] Welcome to GitHub Enterprise — Let's Get Started!",
          mail.subject
        assert_match \
          %r{Hello! @#{business.owners.first.display_login} has created the new #{business.name} Enterprise account on GitHub.},
          mail.html_part.body.to_s
        assert_match \
          %r{Hello! @#{business.owners.first.display_login} has created the new #{business.name} Enterprise account on GitHub.},
          mail.text_part.body.to_s

        expected_payload = {
          action: "billing.payment_processed",
          business: business.display_login,
          business_id: business.id,
          payment_method_id: events.first[:payment_method_id],
          payment_amount: 2500000,
          attempt_number: 1,
          processor_response_code: "200",
          trial_completion_status_before_processing: "creation_from_coupon_purchase_initiated",
          trial_completion_status_after_processing: "created_from_coupon",
        }
        assert_subset_hash expected_payload, events.first
        billing_transaction = Billing::BillingTransaction.last
        assert_equal plan_subscription, T.must(billing_transaction).plan_subscription
        assert_equal payment_id, T.must(billing_transaction).platform_transaction_id
        refute_nil business.plan_subscription.zuora_subscription_number
      end
    end

    test "updates the billing dates of a self-serve enterprise account upon successful payment" do
      synchronize_github_products_to_zuora
      business = create(:business, :with_self_serve_payment)
      zuora_successful_customer_account_creation(business)
      business.customer.update(billing_end_date: nil)
      business.reload

      # travel to specific date to prevent issues with the date update in the future
      # event happens on the 21st of november so the next billing date should be the 20th of november
      date = Date.parse("2023-11-21")
      travel_to date do
        with_live_zuora("zuora/business_payment_processed_webhook_update_business_billing_dates") do
          plan_subscription = create(:billing_plan_subscription, :business_owned, customer: business.customer)
          payment_id = "8ad095dd806f5e4a018070bda71b5a2e"

          webhook = build(
            :zuora_webhook,
            :payment_processed,
            account_id: plan_subscription.zuora_account_id,
            payload: { "AccountId" => plan_subscription.zuora_account_id, "PaymentId" => payment_id },
          )

          assert_difference "Billing::BillingTransaction.count", 1 do
            webhook.perform
          end

          assert_predicate webhook, :processed?

          business.reload
          # Dates are fetched from the VCR recording since we use the
          # chargedThroughDate to calculate the next billing date
          assert_equal Date.new(2023, 11, 19), business.billing_term_ends_at.to_date
          assert_equal Date.new(2023, 11, 19), business.billing_term_ends_on
          assert_equal Date.new(2023, 11, 20), business.billed_on
        end
      end
    end

    test "logs the billing transaction if user has trade restrictions" do
      synchronize_github_products_to_zuora
      user = create(:user, plan: :pro, billed_on: GitHub::Billing.today + 1.month)
      zuora_successful_customer_account_creation(user)
      user.reload

      with_live_zuora("zuora/payment_processed_webhook_attach_subscription") do
        user.customer.update(bill_cycle_day: user.billed_on.day)
        user.trade_controls_restriction.full!
        plan_subscription = user.plan_subscription
        payment_id = "2c92c0fa6205232601622035ebfc5334"

        webhook = build(
            :zuora_webhook,
            :payment_processed,
            account_id: plan_subscription.zuora_account_id,
            payload: { "AccountId" => plan_subscription.zuora_account_id, "PaymentId" => payment_id },
            )

        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        assert_difference(-> { Billing::BillingTransaction.count }) do
          webhook.perform
        end

        assert_predicate webhook, :processed?

        billing_transaction = Billing::BillingTransaction.last
        assert_equal payment_id, T.must(billing_transaction).platform_transaction_id
        assert_equal plan_subscription, T.must(billing_transaction).plan_subscription
        assert_equal 1, stats.increments(
            "billing.trade_controls_restriction.billing_transaction.successful_transaction_for_restricted_user",
        ).count
      end
    end

    test "does not log transaction for user not trade restricted" do
      synchronize_github_products_to_zuora
      user = create(:user, plan: :pro, billed_on: GitHub::Billing.today + 1.month)
      zuora_successful_customer_account_creation(user)
      user.reload

      with_live_zuora("zuora/payment_processed_webhook_attach_subscription") do
        user.customer.update(bill_cycle_day: user.billed_on.day)
        plan_subscription = user.plan_subscription

        webhook = build(
            :zuora_webhook,
            :payment_processed,
            account_id: plan_subscription.zuora_account_id,
            payload: { "AccountId" => plan_subscription.zuora_account_id, "PaymentId" => "2c92c0fa6205232601622035ebfc5334" },
            )

        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        webhook.perform

        assert_predicate webhook, :processed?
        assert_equal 0, stats.increments(
          "billing.trade_controls_restriction.billing_transaction.successful_transaction_for_restricted_user",
        ).count
      end
    end

    test "cleans up orphaned customer when user deleted" do
      with_live_zuora("zuora/payment_processed_webhook_attach_subscription") do
        synchronize_github_products_to_zuora

        user = create(:user, plan: :pro)

        zuora_successful_customer_account_creation(user)
        user.reload

        Billing::Zuora::Webhooks::PaymentProcessed.any_instance.expects(:refund_payment).once
        Billing::Zuora::Webhooks::PaymentProcessed.any_instance.expects(:close_invoices).once

        customer = user.customer
        customer_id = customer.id
        plan_subscription = user.plan_subscription
        plan_subscription_id = plan_subscription.id

        webhook = build(
          :zuora_webhook,
          :payment_processed,
          account_id: plan_subscription.zuora_account_id,
          payload: { "AccountId" => plan_subscription.zuora_account_id, "PaymentId" => "2c92c0fa6205232601622035ebfc5334" },
        )

        user.delete

        refute_nil customer.reload
        refute_nil plan_subscription.reload

        webhook.perform

        assert_predicate webhook, :processed?
        refute Customer.exists?(id: customer_id)
        refute Billing::PlanSubscription.exists?(id: plan_subscription_id)
      end
    end

    test "clean up orphaned customer when business deleted" do
      with_live_zuora("zuora/business_payment_processed_webhook_attach_subscription") do
        synchronize_github_products_to_zuora
        business = create(:business, :with_self_serve_payment)
        zuora_successful_customer_account_creation(business)
        business.reload

        Billing::Zuora::Webhooks::PaymentProcessed.any_instance.expects(:refund_payment).once
        Billing::Zuora::Webhooks::PaymentProcessed.any_instance.expects(:close_invoices).once

        customer = business.customer
        customer_id = customer.id
        plan_subscription = create(:billing_plan_subscription, user: nil, customer: customer)
        plan_subscription_id = plan_subscription.id

        webhook = build(
          :zuora_webhook,
          :payment_processed,
          account_id: plan_subscription.zuora_account_id,
          payload: { "AccountId" => plan_subscription.zuora_account_id, "PaymentId" => "8ad095dd806f5e4a018070bda71b5a2e" },
        )

        business.delete

        refute_nil customer.reload
        refute_nil plan_subscription.reload

        webhook.perform

        assert_predicate webhook, :processed?
        refute Customer.exists?(id: customer_id)
        refute Billing::PlanSubscription.exists?(id: plan_subscription_id)
      end
    end

    test "refund if user's plan supscription is deleted" do
      with_live_zuora("zuora/payment_processed_webhook_refund_id_plan_subscription_is_deleted") do
        zuora_account_id = "2c92c0fb6abc1799016ac135063c1448"
        payment_id = "2c92c0fb6abc1799016ac1371e796cc3"
        zuora_subscription_id = "2c92c0fb6abc1799016ac137103f6bad"
        customer = create(:customer, zuora_account_id: zuora_account_id)
        user = create(:credit_card_user)

        plan_subscription = create(
          :billing_plan_subscription,
          customer: customer,
          user: user,
          zuora_subscription_id: zuora_subscription_id,
          zuora_subscription_number: "A-S00008525",
        )

        webhook = create(
          :zuora_webhook,
          :payment_processed,
          account_id: zuora_account_id,
          payload: { "AccountId" => zuora_account_id, "PaymentId" => payment_id },
        )

        Billing::PlanSubscription.delete(plan_subscription.id)
        webhook.perform

        assert_predicate webhook, :processed?

        zuora_payment = Billing::Zuora::Payment.find(payment_id)
        assert_equal "Voided", zuora_payment.status

        # Invoice is zero'd out
        zuora_account = customer.zuora_account
        assert_equal 0, zuora_account["metrics"]["totalInvoiceBalance"]
      end
    end

    test "refund if business's plan subscription is deleted" do
      with_live_zuora("zuora/payment_processed_webhook_refund_id_plan_subscription_is_deleted") do
        zuora_account_id = "2c92c0fb6abc1799016ac135063c1448"
        payment_id = "2c92c0fb6abc1799016ac1371e796cc3"
        zuora_subscription_id = "2c92c0fb6abc1799016ac137103f6bad"
        business = create(:business, :with_self_serve_payment)
        business.customer.update_columns(zuora_account_id: zuora_account_id)
        customer = business.customer

        plan_subscription = create(
          :billing_plan_subscription,
          customer: customer,
          user: nil,
          zuora_subscription_id: zuora_subscription_id,
          zuora_subscription_number: "A-S00008525",
        )

        webhook = create(
          :zuora_webhook,
          :payment_processed,
          account_id: zuora_account_id,
          payload: { "AccountId" => zuora_account_id, "PaymentId" => payment_id },
        )

        Billing::PlanSubscription.delete(plan_subscription.id)
        webhook.perform

        assert_predicate webhook, :processed?

        zuora_payment = Billing::Zuora::Payment.find(payment_id)
        assert_equal "Voided", zuora_payment.status

        # Invoice is zero'd out
        zuora_account = customer.zuora_account
        assert_equal 0, zuora_account["metrics"]["totalInvoiceBalance"]
      end
    end

    test "refund if user and customer are deleted" do
      with_live_zuora("zuora/payment_processed_webhook_refund_customer_is_deleted") do
        zuora_account_id = "2c92c0fb6abc1799016ac135063c1448"
        payment_id = "2c92c0fb6abc1799016ac1371e796cc3"
        zuora_subscription_id = "2c92c0fb6abc1799016ac137103f6bad"

        plan_subscription = create(
          :billing_plan_subscription,
          zuora_subscription_id: zuora_subscription_id,
          zuora_subscription_number: "A-S00008525",
        )
        plan_subscription_id = plan_subscription.id

        webhook = create(
          :zuora_webhook,
          :payment_processed,
          account_id: zuora_account_id,
          payload: { "AccountId" => zuora_account_id, "PaymentId" => payment_id },
        )

        plan_subscription.user.delete
        plan_subscription.customer.delete
        assert Billing::PlanSubscription.exists?(id: plan_subscription_id)

        webhook.perform

        assert_predicate webhook, :processed?
        refute Billing::PlanSubscription.exists?(id: plan_subscription_id)
      end
    end

    test "uses zuora subscription from invoice when no zuora subscription is attached on the user's plan subscription" do
      user = create(:user, plan: :pro)
      zuora_successful_customer_account_creation(user)
      user.reload

      with_live_zuora("zuora/payment_processed_webhook_no_zuora_subscription") do
        subscription_id = "2c92c0fb6abc1799016ac137103f6bad"
        invalid_subscription_number = "A-S0000852500"
        payment_id = "2c92c0fa6205232601622035ebfc5334"

        user.plan_subscription.update(
          zuora_subscription_id: subscription_id,
          zuora_subscription_number: invalid_subscription_number,
        )
        plan_subscription = user.plan_subscription

        webhook = build(
          :zuora_webhook,
          :payment_processed,
          account_id: plan_subscription.zuora_account_id,
          payload: { "AccountId" => plan_subscription.zuora_account_id, "PaymentId" => payment_id },
        )

        assert_difference "Billing::BillingTransaction.count", 1 do
          webhook.perform
        end

        assert_predicate webhook, :processed?
        billing_transaction = Billing::BillingTransaction.last
        assert_equal payment_id, T.must(billing_transaction).platform_transaction_id
        assert_equal plan_subscription, T.must(billing_transaction).plan_subscription
      end
    end

    test "uses zuora subscription from invoice when no zuora subscription is attached on the business's plan subscription" do
      business = create(:business, :with_self_serve_payment)
      zuora_successful_customer_account_creation(business)
      business.reload

      with_live_zuora("zuora/business_payment_processed_webhook_no_zuora_subscription") do
        subscription_id = "2c92c0fb6abc1799016ac137103f6bad"
        invalid_subscription_number = "A-S0000852500"
        payment_id = "2c92c0fa6205232601622035ebfc5334"

        business.plan_subscription.update(zuora_subscription_id: subscription_id, zuora_subscription_number: invalid_subscription_number)
        plan_subscription = business.plan_subscription

        webhook = build(
          :zuora_webhook,
          :payment_processed,
          account_id: plan_subscription.zuora_account_id,
          payload: { "AccountId" => plan_subscription.zuora_account_id, "PaymentId" => payment_id },
        )

        assert_difference "Billing::BillingTransaction.count", 1 do
          webhook.perform
        end

        assert_predicate webhook, :processed?
        billing_transaction = Billing::BillingTransaction.last
        assert_equal payment_id, T.must(billing_transaction).platform_transaction_id
        assert_equal plan_subscription, T.must(billing_transaction).plan_subscription
      end
    end

    test "logs transactions for sponsorships" do
      synchronize_github_products_to_zuora
      # we need a stable id due to SponsorTier subscribable tracking
      tier = create(:sponsors_tier, :approved_sponsors_listing,
        id: 100_000,
      )
      user = create(:credit_card_user)
      # create general-purpose plan subscription first to later assert the sponsors-purpose one is still preferred
      create(:billing_plan_subscription, user: user)
      sponsorship = create(:sponsorship, sponsor: user, tier: tier)
      sponsors_listing = sponsorship.sponsors_listing
      plan_subscription = sponsorship.plan_subscription
      customer = plan_subscription.customer
      # from test/fixtures/vcr_cassettes/zuora/sponsorship_payment_processed_webhook.yml
      customer.update!(zuora_account_id: "2c92c0fb7a5b3ac8017a5b9dd1a57e2e")
      synchronizer = ::Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription)

      with_live_zuora("zuora/sponsorship_payment_processed_webhook") do
        sponsors_listing.sync_to_zuora

        result = synchronizer.create
        payment_id = result.external_result["paymentId"]

        webhook = build(
          :zuora_webhook,
          :payment_processed,
          account_id: plan_subscription.zuora_account_id,
          payload: { "AccountId" => plan_subscription.zuora_account_id, "PaymentId" => payment_id },
        )

        assert_difference({
          "Billing::BillingTransaction.count" => 1,
          "Billing::BillingTransaction::LineItem.count" => 1,
        }) do
          webhook.perform
        end

        assert_predicate webhook, :processed?
        transaction = Billing::BillingTransaction.last
        assert_predicate transaction, :success?
        assert_equal sponsorship.plan_subscription, T.must(transaction).plan_subscription
        line_item = Billing::BillingTransaction::LineItem.last
        assert_equal sponsorship, T.must(line_item).sponsorship
      end
    end

    test "logs transactions and transfers funds for enterprise account member org sponsorships" do
      synchronize_github_products_to_zuora

      sub_item = create(:sponsors_subscription_item, :self_serve_business)
      listing = sub_item.listing
      subscribable = sub_item.subscribable
      plan_subscription = sub_item.plan_subscription
      customer = plan_subscription.customer
      business = plan_subscription.billable_entity
      business.enable_feature(:sponsors_self_serve_enterprise)
      member_org = sub_item.organization

      other_member_org = create(:organization, business: business)
      other_member_org_sub_item = create(:sponsors_subscription_item,
        account: other_member_org,
        subscribable: sub_item.sponsors_tier
      )

      create(:stripe_connect_account, sponsors_listing: listing)

      # we need stable subscription item ids due to recorded subscription item tracking
      sub_item.update_columns(id: 100_000)
      other_member_org_sub_item.update_columns(id: 100_001)
      # we need a stable item amount since it exists on the recorded invoice items
      subscribable.update_columns(monthly_price_in_cents: 1_00)

      assert_equal other_member_org.business, member_org.business
      assert_equal other_member_org_sub_item.subscribable, sub_item.subscribable

      # from test/fixtures/vcr_cassettes/zuora/enterprise_sponsorship_payment_processed_webhook.yml
      customer.update!(zuora_account_id: "2c92c0fb7a5b3ac8017a5b9dd1a57e2e")
      synchronizer = ::Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription)

      with_live_zuora("zuora/enterprise_sponsorship_payment_processed_webhook") do
        sub_item.listing.sync_to_zuora

        result = synchronizer.create
        payment_id = result.external_result["paymentId"]

        webhook = build(
          :zuora_webhook,
          :payment_processed,
          account_id: plan_subscription.zuora_account_id,
          payload: { "AccountId" => plan_subscription.zuora_account_id, "PaymentId" => payment_id },
        )

        expected_transfer_amount = (2 * sub_item.monthly_price_in_cents) * 12
        ::Stripe::Transfer.expects(:create).with(
          amount: expected_transfer_amount,
          currency: "usd",
          destination: listing.active_stripe_connect_account.stripe_account_id,
          transfer_group: "8ad09b2189d483de0189d6ab00c46ba2", # from VCR cassette
          metadata: {
            payment_amount: expected_transfer_amount,
            match_amount: 0,
            stripe_charge_id: "ch_3NcvmMEQsq43iHhX17EoxDkD", # from VCR cassette
            sponsors_listing_id: listing.id
          }
        )

        assert_difference({
          "Billing::BillingTransaction.count" => 1,
          "Billing::BillingTransaction::LineItem.count" => 2,
        }) do
          webhook.perform
        end

        assert_predicate webhook, :processed?
        transaction = Billing::BillingTransaction.last
        assert_predicate transaction, :success?

        sponsors_line_items = T.must(transaction).line_items.sponsorships
        expected_orgs = [sub_item.organization_id, other_member_org.id]
        assert_same_elements expected_orgs, sponsors_line_items.map { |item| item.extras["managing_entity_id"] }
      end
    end

    test "logs transaction for pro plan" do
      synchronize_github_products_to_zuora
      user = create(:credit_card_user, plan: GitHub::Plan.pro)
      plan_subscription = create(:billing_plan_subscription, user: user)
      customer = plan_subscription.customer
      # from test/fixtures/vcr_cassettes/zuora/pro_plan_payment_processed_webhook.yml
      customer.update!(
        zuora_account_id: "2c92c0fb7a5b3ac8017a5b9dd1a57e2e",
      )
      synchronizer = ::Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription, collect: true)

      with_live_zuora("zuora/pro_plan_payment_processed_webhook") do
        result = synchronizer.create
        payment_id = result.external_result["paymentId"]

        webhook = build(
          :zuora_webhook,
          :payment_processed,
          account_id: plan_subscription.zuora_account_id,
          payload: { "AccountId" => plan_subscription.zuora_account_id, "PaymentId" => payment_id },
        )

        assert_difference({
          "Billing::BillingTransaction.count" => 1,
        }) do
          webhook.perform
        end

        assert_predicate webhook, :processed?
        transaction = Billing::BillingTransaction.last
        assert_predicate transaction, :success?
      end
    end

    test "unlocks a user that was disabled due to a failed authorization" do
      synchronize_github_products_to_zuora
      user = create(:credit_card_user, plan: GitHub::Plan.pro, disabled: true)
      plan_subscription = create(:billing_plan_subscription, user: user)
      customer = plan_subscription.customer
      # from test/fixtures/vcr_cassettes/zuora/pro_plan_payment_processed_webhook.yml
      customer.update!(
        zuora_account_id: "2c92c0fb7a5b3ac8017a5b9dd1a57e2e",
        disabled_reasons: Set[Billing::Public::BillingDisabledReasons::AuthorizationFailure.serialize],
      )
      synchronizer = ::Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription, collect: true)

      user.reload
      assert user.disabled?
      assert user.should_disable?

      with_live_zuora("zuora/pro_plan_payment_processed_webhook") do
        result = synchronizer.create
        payment_id = result.external_result["paymentId"]

        webhook = build(
          :zuora_webhook,
          :payment_processed,
          account_id: plan_subscription.zuora_account_id,
          payload: { "AccountId" => plan_subscription.zuora_account_id, "PaymentId" => payment_id },
        )

        assert_difference({ "Billing::BillingTransaction.count" => 1 }) do
          webhook.perform
        end

        assert_predicate webhook, :processed?
        refute user.reload.disabled?
      end
    end
  end
end if GitHub.billing_enabled?
