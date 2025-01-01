# typed: strict
# frozen_string_literal: true

# An invoiced organization is also known as an enterprise plan organization
class Billing::Zuora::SalesManagedOrganizationSubscriptionSynchronizer
  include Billing::Zuora::SalesManagedSubscriptionSynchronizationHelper
  include GitHub::Memoizer

  sig { void }
  def sync
    Organization.transaction do
      sync_organization_attributes
      sync_data_packs(organization)
    end

    sync_customer_attributes_without_duplicate(customer, subscription, T.must(subscription.term_end_date))
    sync_plan_subscription_data

    organization.expire_active_coupon
    ::Billing::Zuora::PrepaidMeteredUsageRefillSynchronizer.new(subscription, T.must(organization.next_billing_date)).synchronize!
  end

  private

  sig { returns(Organization) }
  memoize def organization
    T.cast(subscription.owner, Organization)
  end

  sig { void }
  def sync_organization_attributes
    old_seats = organization.seats
    old_plan = organization.plan
    old_plan_duration = organization.plan_duration
    old_billing_type = organization.billing_type

    organization.seats = subscription.seats
    organization.plan = subscription.plan || old_plan
    organization.billed_on = subscription.term_end_date
    organization.disabled = false
    organization.customer&.unlock_billing
    organization.switch_billing_type_to_invoice(organization)

    organization.save!

    GitHub.instrument(
      "billing.change_billing_type",
      old_billing_type: old_billing_type,
      billing_type: organization.billing_type,
      user: organization,
      actor: organization,
      actor_id: organization.id,
    )

    organization.track_seat_change(organization, old_seats: old_seats)
    organization.track_plan_change(organization, old_plan)
    organization.track_plan_duration_change(organization, old_plan_duration.to_s)
  end

  sig { returns(Customer) }
  memoize def customer
    organization.customer || Billing::CreateCustomer.perform(organization).customer
  end

  sig { void }
  def sync_plan_subscription_data
    plan_subscription = organization.plan_subscription || Billing::PlanSubscription.new(user: organization, customer: customer.reload)
    term_start_date = subscription.term_start_date

    unless term_start_date.blank?
      plan_subscription.billing_start_date = term_start_date
    end

    # TODO: this can be DRYed up once we consolidate zuora_webhook/subscription with
    # billing/zuora_subscription.
    plan_subscription.zuora_subscription_id = subscription.id
    plan_subscription.zuora_subscription_number = subscription.subscription_number
    plan_subscription.zuora_rate_plan_charges = subscription.active_rate_plan_charges
    plan_subscription.save!

    if organization.feature_flag_enabled_or_raise?(:new_zuora_rate_plan_charges) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      result = Billing::PlanSubscription::ZuoraRatePlanCharge.reconcile(
        plan_subscription: plan_subscription,
        active_charges_from_zuora: subscription.rate_plan_charges.select(&:active?),
        success: true
      )
      if result
        plan_subscription.reload
      end

      GitHub.dogstats.increment(
        "billing.plan_subscription.charge_updates",
        tags: ["success:#{!!result}", "sales_serve:true"]
      )
    end
  end
end
