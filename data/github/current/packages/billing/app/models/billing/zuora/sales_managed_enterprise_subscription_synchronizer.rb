# typed: strict
# frozen_string_literal: true

class Billing::Zuora::SalesManagedEnterpriseSubscriptionSynchronizer
  include Billing::Zuora::SalesManagedSubscriptionSynchronizationHelper
  include GitHub::Memoizer

  sig { void }
  def sync
    Business.transaction do
      if business.customer.nil?
        Billing::CreateCustomer.perform(business)
        business.reload
      end

      sync_business_attributes
    end

    remove_duplicate_zuora_information_from_organizations
    sync_sales_serve_plan_subscription

    provision_education_bundle if has_education_bundle?

    ::Billing::Zuora::PrepaidMeteredUsageRefillSynchronizer.new(subscription, subscription_end_date).synchronize!
    sync_customer_attributes_without_duplicate(customer, subscription, subscription_end_date)
    ::Billing::UpdateSkippedMeteredLineItemsJob.perform_later(billable_owner: business)
  end

  sig { void }
  def sync_sales_serve_plan_subscription
    term_start_date = subscription.term_start_date
    return if term_start_date && term_start_date > GitHub::Billing.today

    sales_serve_plan_subscription = customer.sales_serve_plan_subscription || customer.build_sales_serve_plan_subscription

    # Don't update self_serve_eligible with the value coming from zuora, as it'll be stale
    # It's now coming from salesforce directly via HydroSalesforceSelfServeEligibleJob
    sales_serve_plan_subscription.update!(
      zuora_subscription_id: subscription.id,
      zuora_subscription_number: subscription.subscription_number,
      billing_start_date: term_start_date,
      zuora_rate_plan_charges: subscription.active_rate_plan_charges,
    )

    if business.feature_enabled?(:new_zuora_rate_plan_charges)
      result = Billing::PlanSubscription::ZuoraRatePlanCharge.reconcile(
        plan_subscription: sales_serve_plan_subscription,
        active_charges_from_zuora: subscription.rate_plan_charges.select(&:active?),
        success: true
      )
      if result
        sales_serve_plan_subscription.reload
      end

      GitHub.dogstats.increment(
        "billing.plan_subscription.charge_updates",
        tags: ["success:#{!!result}", "sales_serve:true"]
      )
    end
  end

  private

  delegate :customer, to: :business, private: true

  sig { returns(Business) }
  memoize def business
    T.cast(subscription.owner, Business)
  end

  sig { void }
  def sync_business_attributes
    old_seats = business.seats

    business.update(seats: subscription.seats)

    log_support_plan_change
    update_support_plan

    business.track_seat_change(old_seats)

    first_organization = business.organizations.first
    sync_data_packs(first_organization) if first_organization.present?
  end

  sig { void }
  def remove_duplicate_zuora_information_from_organizations
    existing_customer = Customer.find_by(zuora_account_number: subscription.account_number)
    return unless existing_customer.present?

    # Check if the customer is associated with any of the business's organizations
    return unless business.organizations.exists?(id: existing_customer.organizations.ids)

    # When the business and organization(s) are sharing the same customer, we unlink
    # the customer from the organization(s). Otherwise, we can just update the customer
    # to remove the Zuora account information.
    if existing_customer == business.customer
      existing_customer.customer_accounts.destroy_all
    else
      existing_customer.update(zuora_account_number: nil, zuora_account_id: nil)
    end
  end

  # Internal: Get the end date of the subscription. Unfortunately the
  # `termEndDate` field from Zuora is actually the start of the next
  # period so we need to subtract a day.
  sig { returns(Date) }
  memoize def subscription_end_date
    T.must(subscription.term_end_date) - 1.day
  end

  sig { void }
  def provision_education_bundle
    education_bundle = subscription.education_bundle_rate_plan_charge&.bundle_plan || "none"

    ::Billing::Education::BundleProvisioner.perform! \
      business: business,
      education_bundle: education_bundle
  end

  sig { returns(T.nilable(T::Boolean)) }
  def has_education_bundle?
    customer.sales_serve_plan_subscription&.education_bundle? || subscription.has_education_bundle?
  end

  sig { void }
  def log_support_plan_change
    current_support_plan = business.calculated_support_plan

    if subscription.support_plan.present?
      return if subscription.support_plan == current_support_plan

      GitHub.logger.info("automated_support_plan_entitlement", support_plan_change_log_payload.merge({
        "gh.subscription.support_plan": subscription.support_plan,
      }))
    else
      return unless eligible_for_support_disentitlement?(current_support_plan)

      GitHub.logger.info("automated_support_plan_disentitlement", support_plan_change_log_payload.merge({
        "gh.business.old_support_plan": current_support_plan,
        "gh.business.new_support_plan": Configurable::SupportPlan::STANDARD
      }))
    end
  end

  sig { void }
  def update_support_plan
    current_support_plan = business.calculated_support_plan

    if subscription.support_plan.present?
      return if subscription.support_plan == current_support_plan

      business.update(support_plan: subscription.support_plan)
    else
      return unless eligible_for_support_disentitlement?(current_support_plan)

      # No support plan on the subscription means the customer should have standard support.
      business.update(support_plan: Configurable::SupportPlan::STANDARD)
    end
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def support_plan_change_log_payload
    {
      "code.namespace": self.class.name,
      "code.function": "sync_business_attributes",
      "gh.business.id": business.id,
      "gh.business.slug": business.slug
    }
  end

  # We're limiting this to specific support plans until we have a path forward for desentitlement for
  # GitHub Engineering Direct customers.
  sig { params(support_plan: String).returns(T::Boolean) }
  def eligible_for_support_disentitlement?(support_plan)
    [Configurable::SupportPlan::PREMIUM, Configurable::SupportPlan::PREMIUM_PLUS].include?(support_plan)
  end
end
