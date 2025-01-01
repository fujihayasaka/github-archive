# typed: strict
# frozen_string_literal: true

require "test_helper"

class UserCardConverterTest < GitHub::TestCase
  context "#convertable?" do
    test "returns true if target is invoiced" do
      org = create(:invoiced_organization)

      assert User::CardConverter.new(org).convertable?
    end

    test "returns false if target is not invoiced" do
      org = create(:credit_card_organization)

      refute User::CardConverter.new(org).convertable?
    end

    test "returns false for invoiced account with active monthly sponsorship and PayPal payment method" do
      sponsor = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
      create(:paypal_payment_method, customer: sponsor.customer)
      create(:sponsorship, :sponsors_invoiced, sponsor: sponsor)

      refute_predicate User::CardConverter.new(sponsor), :convertable?
    end if GitHub.sponsors_enabled?

    test "returns true for invoiced account with PayPal payment method but without monthly sponsorship" do
      sponsor = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
      create(:paypal_payment_method, customer: sponsor.customer)
      create(:sponsorship, :one_time, :sponsors_invoiced, sponsor: sponsor)

      assert_predicate User::CardConverter.new(sponsor), :convertable?
    end if GitHub.sponsors_enabled?

    test "returns true for invoiced account with PayPal payment method but without active sponsorship" do
      sponsor = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
      create(:paypal_payment_method, customer: sponsor.customer)
      create(:sponsorship, :inactive, :sponsors_invoiced, sponsor: sponsor)

      assert_predicate User::CardConverter.new(sponsor), :convertable?
    end if GitHub.sponsors_enabled?

    test "returns true for invoiced account with active sponsorship but without PayPal payment method" do
      sponsor = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
      create(:payment_method, customer: sponsor.customer)
      create(:sponsorship, :sponsors_invoiced, sponsor: sponsor)

      assert_predicate User::CardConverter.new(sponsor), :convertable?
    end if GitHub.sponsors_enabled?
  end

  context "#convert" do
    test "raises exception if target is not convertable" do
      org = create(:organization)
      staff = create(:staff_admin_user)
      refute_predicate User::CardConverter.new(org), :convertable?

      error = assert_raises(User::CardConverter::ConvertError) do
        User::CardConverter.new(org).convert(actor: staff)
      end

      assert_equal "@#{org} is not invoiced.", error.message
    end

    test "raises exception explaining sponsorships must first be cancelled due to PayPal deprecation" do
      sponsor = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
      create(:paypal_payment_method, customer: sponsor.customer)
      create(:sponsorship, :sponsors_invoiced, sponsor: sponsor)
      staff = create(:staff_admin_user)

      error = assert_raises(User::CardConverter::ConvertError) do
        User::CardConverter.new(sponsor).convert(actor: staff)
      end

      assert_equal "@#{sponsor} has PayPal and an active, recurring sponsorship; either cancel the sponsorship(s) " \
        "or remove the PayPal payment method before switching to self-serve billing.", error.message
    end if GitHub.sponsors_enabled?

    test "switching an organization off of invoicing clears the Zuora account information" do
      org = create(:invoiced_organization)
      staff = create(:staff_admin_user)

      assert_predicate org, :zuora_account?
      refute_nil org.customer.zuora_account_id
      refute_nil org.customer.zuora_account_number

      User::CardConverter.new(org).convert(actor: staff)

      refute_predicate org, :zuora_account?
      assert_nil org.customer.zuora_account_id
      assert_nil org.customer.zuora_account_number
    end

    test "switching an organization off of invoicing clears associated subscription information" do
      org = create(:invoiced_organization)
      create(:billing_plan_subscription, :zuora, user: org)
      staff = create(:staff_admin_user)

      refute_nil org.plan_subscription.zuora_subscription_number
      refute_nil org.plan_subscription.zuora_subscription_id

      User::CardConverter.new(org).convert(actor: staff)

      assert_nil org.plan_subscription.zuora_subscription_number
      assert_nil org.plan_subscription.zuora_subscription_id
    end

    test "instruments billing.change_billing_type event" do
      org = create(:invoiced_organization)
      create(:billing_plan_subscription, :zuora, user: org)
      staff = create(:staff_admin_user)

      received_event = T.let(false, T::Boolean)
      event_payload = T.let({}, T::Hash[Symbol, T.untyped])
      GlobalInstrumenter.subscribe("billing.change_billing_type") do |_event, _, _, _, payload|
        received_event = true
        event_payload = payload
      end

      User::CardConverter.new(org).convert(actor: staff)

      assert received_event, "expected a billing.change_billing_type instrumentation event"
      assert_equal User::BillingDependency::INVOICE_BILLING_TYPE, event_payload[:old_billing_type]
      assert_equal User::BillingDependency::CARD_BILLING_TYPE, event_payload[:billing_type]
      assert_equal org.id, event_payload[:user].id
      assert_equal staff.id, event_payload[:actor].id
      assert_nil org.plan_subscription.zuora_subscription_number
      assert_nil org.plan_subscription.zuora_subscription_id
    end
  end
end
