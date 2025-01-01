# typed: true
# frozen_string_literal: true

require "test_helper"

class UserInvoiceConverterTest < GitHub::TestCase
  context "#convertable?" do
    test "returns true if target is not invoiced" do
      org = create :credit_card_organization

      assert User::InvoiceConverter.new(org).convertable?
    end

    test "returns false if target is invoiced" do
      org = create :invoiced_organization

      refute User::InvoiceConverter.new(org).convertable?
    end

    test "returns false if owned by a business and billing_type is invoiced" do
      business = create :business
      org = create :invoiced_organization
      business.add_organization org

      refute User::InvoiceConverter.new(org.reload).convertable?
    end

    test "returns true if owned by a business and billing_type is not invoiced" do
      business = create :business
      org = create :credit_card_organization
      business.add_organization org

      assert User::InvoiceConverter.new(org.reload).convertable?
    end
  end

  context "#convert" do
    test "switches organization to invoiced with 0 billing attempts and a yearly duration" do
      FakeZuora.mock
      org = create :organization, :zuora, plan_duration: User::BillingDependency::MONTHLY_PLAN
      staff = create(:staff_admin_user)

      assert User::InvoiceConverter.new(org).convert(actor: staff)

      assert org.invoiced?
      assert_equal 0, org.billing_attempts
      assert User::BillingDependency::YEARLY_PLAN, org.plan_duration
    end

    test "cancels external plan subscriptions and removes all payment methods" do
      org = create :organization, :zuora, plan_duration: User::BillingDependency::MONTHLY_PLAN
      create(:billing_plan_subscription, user: org)
      org.reload

      org.customer.expects(:cancel_external_subscriptions).once
      ::Billing::PaymentMethodRemovalJob.expects(:perform_later).with \
        user: org,
        actor: org.admins.first

      assert User::InvoiceConverter.new(org).convert(actor: org.admins.first)
    end

    test "cancels any pending plan changes" do
      org = create(:organization, :zuora, plan: :business_plus, seats: 100)
      pending_plan_change = create(:billing_pending_plan_change, user: org, plan: nil, seats: 50)

      User::InvoiceConverter.new(org).convert(actor: org.admins.first)

      assert pending_plan_change.reload.is_complete?
      assert_equal 100, org.reload.seats
    end

    test "instruments billing.change_billing_type event" do
      staff = create(:staff_admin_user)
      org = create :credit_card_organization
      create(:billing_plan_subscription, user: org)
      org.reload

      received_event = T.let(false, T::Boolean)
      event_payload = T.let({}, T::Hash[T.untyped, T.untyped])
      GlobalInstrumenter.subscribe("billing.change_billing_type") do |_event, _, _, _, payload|
        received_event = true
        event_payload = payload
      end

      org.customer.expects(:cancel_external_subscriptions)
      ::Billing::PaymentMethodRemovalJob.expects(:perform_later).with \
        user: org,
        actor: staff
      User::InvoiceConverter.new(org).convert(actor: staff)

      assert received_event, "expected a billing.change_billing_type instrumentation event"
      assert_equal User::BillingDependency::CARD_BILLING_TYPE, event_payload[:old_billing_type]
      assert_equal User::BillingDependency::INVOICE_BILLING_TYPE, event_payload[:billing_type]
      assert_equal org.id, event_payload[:user].id
      assert_equal staff.id, event_payload[:actor].id
    end

    test "expires existing enterprise cloud trial" do
      org = create :organization, :zuora, plan_duration: User::BillingDependency::MONTHLY_PLAN
      create(:billing_plan_subscription, user: org)
      Billing::EnterpriseCloudTrial.new(org).create
      org.reload

      org.customer.expects(:cancel_external_subscriptions).once
      ::Billing::PaymentMethodRemovalJob.expects(:perform_later).with \
        user: org,
        actor: org.admins.first

      assert User::InvoiceConverter.new(org).convert(actor: org.admins.first)
      assert Billing::EnterpriseCloudTrial.new(org).expired?
    end

    test "doesn't change billing type when deactivating the trial fails" do
      org = create :free_organization
      create(:customer, customer_account_user: org)
      org.reload

      org.customer.expects(:cancel_external_subscriptions).once
      ::Billing::PaymentMethodRemovalJob.expects(:perform_later).with \
        user: org,
        actor: org.admins.first

      Billing::EnterpriseCloudTrial.expects(:new).raises(StandardError)

      assert_raises(StandardError) do
        User::InvoiceConverter.new(org).convert(actor: org.admins.first)
      end

      refute org.reload.invoiced?
    end
  end
end unless GitHub.enterprise?
