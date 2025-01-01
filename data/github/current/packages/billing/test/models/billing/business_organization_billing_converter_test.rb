# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::BusinessOrganizationBillingConverterTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers

  context ".perform" do
    test "converts organization to invoice if business on invoiced payments" do
      business = create(:business)
      org = create(:organization, business: business)

      assert_predicate business, :invoiced?

      ::Billing::BusinessOrganizationBillingConverter.perform \
        business: business,
        organization: org

      assert_equal org.billing_type, User::BillingDependency::INVOICE_BILLING_TYPE
    end

    test "does not convert organization to invoice if business on self-serve payments" do
      business = create(:business, :with_self_serve_payment)
      org = create(:organization, business: business)

      assert_predicate business, :self_serve_payment?

      ::Billing::BusinessOrganizationBillingConverter.perform \
        business: business,
        organization: org

      assert_equal org.billing_type, User::BillingDependency::CARD_BILLING_TYPE
    end

    test "updates billing type to card for business organizations on self-serve payments even if the organization has no admins" do
      business = create(:business, :with_self_serve_payment)
      org = create(:organization, business: business)
      org.direct_admins.delete_all

      assert_predicate business, :self_serve_payment?
      assert_predicate org.reload.admins, :empty?

      ::Billing::BusinessOrganizationBillingConverter.perform \
        business: business,
        organization: org

      assert_equal org.billing_type, User::BillingDependency::CARD_BILLING_TYPE
    end

    test "enqueues job to cancel general-purpose zuora subscription for org owned by self-serve paying non-trial business" do
      business = create(:business, :with_self_serve_payment)
      org = create(:organization, :zuora)
      plan_sub = create(:billing_plan_subscription, user: org, zuora_subscription_number: "8675309")
      org.reload

      assert_predicate business, :self_serve_payment?
      refute_nil org.plan_subscription

      assert_enqueued_with(job: CloseOutZuoraSubscriptionJob, args: [{
        zuora_subscription_number: "8675309",
        plan_subscription: plan_sub,
      }]) do
        business.add_organization(org)
        ::Billing::BusinessOrganizationBillingConverter.perform \
          business: business,
          organization: org
      end
    end

    test "enqueues job to cancel Sponsors-specific zuora subscription for org owned by self-serve paying non-trial business" do
      business = create(:business, :with_self_serve_payment)
      org = create(:organization, :zuora)
      sponsors_plan_sub = create(:billing_plan_subscription, :sponsors_invoiced, user: org, zuora_subscription_number: "123456")
      org.reload

      assert_predicate business, :self_serve_payment?
      refute_nil org.sponsors_plan_subscription

      assert_enqueued_with(job: CloseOutZuoraSubscriptionJob, args: [{
        zuora_subscription_number: "123456",
        plan_subscription: sponsors_plan_sub,
      }]) do
        business.add_organization(org)
        ::Billing::BusinessOrganizationBillingConverter.perform \
          business: business,
          organization: org
      end
    end if GitHub.sponsors_enabled?

    test "cancels pending plan changes for org owned by self-serve paying non-trial business" do
      business = create(:business, :with_self_serve_payment)
      org = create(:organization, :zuora, plan: :business, seats: 50)
      pending_plan_change = create(:billing_pending_plan_change, user: org, plan: :business_plus, seats: 100)
      org.reload
      pending_plan_change.reload

      assert_predicate business, :self_serve_payment?
      refute_predicate pending_plan_change, :is_complete?

      business.add_organization(org)
      ::Billing::BusinessOrganizationBillingConverter.perform \
        business: business,
        organization: org
      pending_plan_change.reload

      assert_predicate pending_plan_change, :is_complete?
    end

    test "enqueues job to remove payment method for org owned by self-serve paying non-trial business" do
      business = create(:business, :with_self_serve_payment)
      org = create(:credit_card_org, plan: :business_plus, seats: 10)
      org.reload

      assert_predicate business, :self_serve_payment?
      refute_nil org.payment_method

      assert_enqueued_with(job: ::Billing::PaymentMethodRemovalJob) do
        business.add_organization(org)
        ::Billing::BusinessOrganizationBillingConverter.perform \
          business: business,
          organization: org
      end
    end

    test "does not enqueue job to cancel zuora subscription for org owned by self-serve paying trial business" do
      business = create(
        :business,
        :with_self_serve_payment,
        trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
      )
      org = create(:organization, :zuora)
      create(:billing_plan_subscription, :zuora, user: org)
      org.reload

      assert_predicate business, :trial?
      assert_predicate business, :self_serve_payment?
      refute_nil org.plan_subscription

      assert_enqueued_jobs 0, only: CloseOutZuoraSubscriptionJob do
        business.add_organization(org)
        ::Billing::BusinessOrganizationBillingConverter.perform \
          business: business,
          organization: org
      end
    end

    test "does not enqueue job to cancel zuora subscription for Enterprise-plan org upgrading to a Business" do
      owner = create :user
      business = create :business, :with_self_serve_payment, owners: [owner]
      org = create(:organization, :zuora, plan: "business_plus", billing_type: "card")
      create(:billing_plan_subscription, :zuora, user: org)
      org.reload

      refute_nil org.plan_subscription

      assert_enqueued_jobs 0, only: CloseOutZuoraSubscriptionJob do
        business.attach_organization_for_upgrade(org, owner)
        ::Billing::BusinessOrganizationBillingConverter.perform \
          business: business,
          organization: org
      end
    end

    test "does not cancel pending plan changes for org owned by self-serve paying trial business" do
      business = create(
        :business,
        :with_self_serve_payment,
        trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
      )
      org = create(:organization, :zuora, plan: :business, seats: 50)
      pending_plan_change = create(:billing_pending_plan_change, user: org, plan: :business_plus, seats: 100)
      org.reload
      pending_plan_change.reload

      assert_predicate business, :trial?
      assert_predicate business, :self_serve_payment?
      refute_predicate pending_plan_change, :is_complete?

      business.add_organization(org)
      ::Billing::BusinessOrganizationBillingConverter.perform \
        business: business,
        organization: org
      pending_plan_change.reload

      refute_predicate pending_plan_change, :is_complete?
    end

    test "does not enqueue job to remove payment method for org owned by self-serve paying trial business" do
      business = create(
        :business,
        :with_self_serve_payment,
        trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
      )
      org = create(:credit_card_org, plan: :business_plus, seats: 10)
      org.reload

      assert_predicate business, :trial?
      assert_predicate business, :self_serve_payment?
      refute_nil org.payment_method

      assert_enqueued_jobs 0, only: ::Billing::PaymentMethodRemovalJob do
        business.add_organization(org)
        ::Billing::BusinessOrganizationBillingConverter.perform \
          business: business,
          organization: org
      end
    end

    test "enqueues job to cancel zuora subscription for a free or teams-plan org upgrading into an EA" do
      org = create(:organization, :zuora)
      business = create(
        :business,
        :with_self_serve_payment,
        upgrade_initiated_from_organization_id: org.id
      )
      create(:billing_plan_subscription, :zuora, user: org)
      org.upgrade_to_enterprise_in_progress!(business)
      org.reload

      business.initiate_organization_upgrade
      business.initiate_organization_upgrade_purchase

      assert_predicate business, :organization_upgrade_purchase_initiated?
      assert_equal business.upgrade_initiated_from_organization, org
      assert_predicate business, :self_serve_payment?
      refute_nil org.plan_subscription

      assert_enqueued_jobs 1, only: CloseOutZuoraSubscriptionJob do
        business.upgrade_from_organization
        assert_predicate business, :organization_upgrade_completed?
        ::Billing::BusinessOrganizationBillingConverter.perform \
          business: business,
          organization: org
      end
    end

    test "cancels pending plan changes for a free or teams-plan org upgrading into an EA" do
      org = create(:organization, :zuora, plan: :business, seats: 50)
      business = create(
        :business,
        :with_self_serve_payment,
        upgrade_initiated_from_organization_id: org.id
      )
      pending_plan_change = create(:billing_pending_plan_change, user: org, plan: :business_plus, seats: 100)
      org.reload
      pending_plan_change.reload

      business.initiate_organization_upgrade
      business.initiate_organization_upgrade_purchase

      assert_predicate business, :organization_upgrade_purchase_initiated?
      assert_equal business.upgrade_initiated_from_organization, org
      assert_predicate business, :self_serve_payment?
      refute_predicate pending_plan_change, :is_complete?

      business.upgrade_from_organization(org)
      ::Billing::BusinessOrganizationBillingConverter.perform \
        business: business,
        organization: org
      pending_plan_change.reload

      assert_predicate pending_plan_change, :is_complete?
    end

    test "enqueues job to remove payment method for a free or teams-plan org upgrading into an EA" do
      org = create(:credit_card_org, plan: :business_plus, seats: 10)
      business = create(
        :business,
        :with_self_serve_payment,
        upgrade_initiated_from_organization_id: org.id
      )
      org.reload

      business.initiate_organization_upgrade
      business.initiate_organization_upgrade_purchase

      assert_predicate business, :organization_upgrade_purchase_initiated?
      assert_equal business.upgrade_initiated_from_organization, org
      assert_predicate business, :self_serve_payment?
      refute_nil org.payment_method

      assert_enqueued_jobs 1, only: ::Billing::PaymentMethodRemovalJob do
        business.upgrade_from_organization(org)
        ::Billing::BusinessOrganizationBillingConverter.perform \
          business: business,
          organization: org
      end
    end

    test "syncs organization ToS settings for free or teams-plan org upgrading into a business" do
      standard_owner = create(:user, :verified)
      create(:account_screening_profile, owner: standard_owner)
      org = create(:credit_card_org, plan: :business_plus, seats: 10, admin: standard_owner)
      standard_owner.link_trade_screening_record_to_org(organization: org)

      business = create(
        :business,
        :with_self_serve_payment,
        upgrade_initiated_from_organization_id: org.id
      )

      business.initiate_organization_upgrade
      business.initiate_organization_upgrade_purchase

      assert_predicate org.reload.terms_of_service, :standard?
      assert_predicate business, :organization_upgrade_purchase_initiated?
      assert_equal business.upgrade_initiated_from_organization, org

      business.upgrade_from_organization(org)
      ::Billing::BusinessOrganizationBillingConverter.perform \
        business: business,
        organization: org

      assert_predicate org.reload.terms_of_service, :corporate?
    end

    test "unlocks billing for disabled organization and enqueues job to remove payment method" do
      business = create(:business)
      org = create(:credit_card_org, :with_billing_locked, business: business)

      assert_enqueued_jobs 1, only: ::Billing::PaymentMethodRemovalJob do
        ::Billing::BusinessOrganizationBillingConverter.perform \
          business: business,
          organization: org
      end

      assert org.enabled?
    end

    test "instruments billing.change_billing_type when org billing type changes" do
      business = create(:business)
      org = create(:organization)
      actor ||= (User.find_by(id: GitHub.context[:actor_id]) || User.ghost)

      assert_equal org.billing_type, User::BillingDependency::CARD_BILLING_TYPE

      events = assert_performed_audit_entries(count: 1, only: "billing.change_billing_type") do
        business.add_organization(org)
        ::Billing::BusinessOrganizationBillingConverter.perform \
          business: business,
          organization: org
      end

      expected_payload = {
        old_billing_type: User::BillingDependency::CARD_BILLING_TYPE,
        billing_type: User::BillingDependency::INVOICE_BILLING_TYPE,
        user: org.login,
        actor: actor.login,
        actor_id: actor.id
      }

      assert_equal org.billing_type, User::BillingDependency::INVOICE_BILLING_TYPE
      assert_subset_hash expected_payload, events.first
    end

    test "does not instrument billing.change_billing_type when org billing type doesn't change" do
      business = create(:business, :with_self_serve_payment)
      org = create(:organization)

      assert_equal org.billing_type, User::BillingDependency::CARD_BILLING_TYPE

      assert_performed_audit_entries(count: 0, only: "billing.change_billing_type") do
        business.add_organization(org)
        ::Billing::BusinessOrganizationBillingConverter.perform \
          business: business,
          organization: org
      end

      assert_equal org.billing_type, User::BillingDependency::CARD_BILLING_TYPE
    end
  end
end if GitHub.billing_enabled?
