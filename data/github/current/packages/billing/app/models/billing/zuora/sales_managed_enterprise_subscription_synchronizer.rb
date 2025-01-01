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
  end

  sig { void }
  def sync_sales_serve_plan_subscription
    sales_serve_plan_subscription = customer.sales_serve_plan_subscription || customer.build_sales_serve_plan_subscription

    # Don't update self_serve_eligible with the value coming from zuora, as it'll be stale
    # It's now coming from salesforce directly via HydroSalesforceSelfServeEligibleJob
    sales_serve_plan_subscription.update!(
      zuora_subscription_id: subscription.id,
      zuora_subscription_number: subscription.subscription_number,
      billing_start_date: subscription.term_start_date,
      zuora_rate_plan_charges: subscription.active_rate_plan_charges,
    )

    if business.feature_flag_enabled_or_raise?(:new_zuora_rate_plan_charges) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      charges_from_zuora = subscription.rate_plan_charges
      charges_from_zuora = charges_from_zuora.select(&:active?) unless business.feature_flag_enabled_or_raise?(:sync_inactive_rate_plan_charges) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      result = Billing::PlanSubscription::ZuoraRatePlanCharge.reconcile(
        plan_subscription: sales_serve_plan_subscription,
        active_charges_from_zuora: charges_from_zuora,
        success: true,
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
    sync_ghas_seats
  end

  sig { void }
  def sync_ghas_seats
    return unless business.feature_flag_enabled_or_raise?(:automatically_provision_ghas_seats_darkship) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    writes_enabled = business.feature_flag_enabled_or_raise?(:automatically_provision_ghas_seats) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

    actor = User.ghost
    secret_protection_charge = subscription.active_secret_protection_rate_plan_charge(ignore_start_date: true, include_msft: true)
    code_security_charge = subscription.active_code_security_rate_plan_charge(ignore_start_date: true, include_msft: true)
    bundled_ghas_charge = subscription.ghas_rate_plan_charge(active_only: true, ignore_start_date: true, include_msft_and_other_charges: true)

    bundled_ghas_seats = subscription.bundled_ghas_seats
    cs_seats = subscription.code_security_seats
    sp_seats = subscription.secret_protection_seats

    log_tags = {
      "code.namespace": self.class.name,
      "code.function": __method__,
      "gh.billing.subscription_synchronizer.secret_protection_charge_present": !secret_protection_charge.nil?,
      "gh.billing.subscription_synchronizer.code_security_charge_present": !code_security_charge.nil?,
      "gh.billing.subscription_synchronizer.bundled_ghas_charge_present": !bundled_ghas_charge.nil?,
      "gh.business.id": business.id,
      "gh.business.slug": business.slug,
      "gh.billing.subscription_synchronizer.bundled_ghas_seats": bundled_ghas_seats,
      "gh.billing.subscription_synchronizer.cs_seats": cs_seats,
      "gh.billing.subscription_synchronizer.sp_seats": sp_seats,
      "gh.billing.subscription_synchronizer.writes_enabled": writes_enabled,
    }



    GitHub.logger.info("Syncing GHAS seats based on rate plan charges", log_tags)

    if bundled_ghas_charge
      if bundled_ghas_seats == 0
        GitHub.logger.info("Will not set Advanced Security to bundled volume with 0 seats", log_tags)
        return
      end

      GitHub.logger.info("Setting bundled volume and rebundling GHAS", log_tags)

      if writes_enabled
        business.mark_advanced_security_as_purchased_for_entity(actor: actor, is_stafftools_action: false)
        business.set_advanced_security_seats_for_entity(
          seats: bundled_ghas_seats,
          actor: actor,
          is_stafftools_action: false,
        )
        business.rebundle_ghas(actor: actor, skip_billing_config_changes: true)
      end
    elsif secret_protection_charge && code_security_charge
      if cs_seats == 0 || sp_seats == 0
        GitHub.logger.info("Will not set 0 seats for either CS or SP for unbundled split volume when one has 0 seats.", log_tags)
        return
      end

      GitHub.logger.info("Setting volume unbundled and unbundling GHAS", log_tags)

      if writes_enabled
        business.mark_advanced_security_as_purchased_for_entity_as_volume_unbundled(actor: actor)
        business.set_code_security_license_count(count: cs_seats, actor: actor)
        business.set_secret_scanning_license_count(count: sp_seats, actor: actor)
        business.unbundle_ghas(actor: actor, skip_billing_config_changes: true)
      end
    elsif secret_protection_charge
      if sp_seats == 0
        GitHub.logger.info("Will not zero out seats for SP and mark as SP volume", log_tags)
        return
      end

      GitHub.logger.info("Setting secret protection only", log_tags)

      if writes_enabled
        business.mark_secret_protection_as_purchased_for_entity_as_volume(actor: actor)
        business.set_secret_scanning_license_count(count: sp_seats, actor: actor)
        business.unbundle_ghas(actor: actor, code_security_enablement_strategy: :do_not_enable_code_security, skip_billing_config_changes: true)
      end
    elsif code_security_charge
      if cs_seats == 0
        GitHub.logger.info("Will not zero out seats for CS and mark as CS volume", log_tags)
        return
      end

      GitHub.logger.info("Setting code security only", log_tags)

      if writes_enabled
        business.set_customer_to_split_volume_code_security_only(actor: actor)
        business.set_code_security_license_count(count: cs_seats, actor: actor)
        business.unbundle_ghas(actor: actor, skip_billing_config_changes: true)
      end
    end

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
