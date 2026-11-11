# typed: strict
# frozen_string_literal: true

class Stafftools::GhasSelfServeTrialManagementComponent < ViewComponent::Base
  include GitHub::Memoizer
  include Stafftools::AdvancedSecurityHelper

  sig { params(billable_entity: T.any(Organization, Business)).void }
  def initialize(billable_entity:)
    @billable_entity = billable_entity
  end

  sig { returns(T::Boolean) }
  def render?
    billable_entity.is_a?(Business)
  end

  private

  sig { returns(T.any(Organization, Business)) }
  attr_reader :billable_entity

  sig { returns(Business) }
  def business
    T.cast(billable_entity, Business)
  end

  # Returns true if any Advanced Security trial is active (regardless of type)
  sig { returns(T::Boolean) }
  def has_active_trial?
    billable_entity.has_active_advanced_security_trial?
  end

  # Returns true only if an active self-serve trial (ghas_stand_alone or digital_front_door) is active
  sig { returns(T::Boolean) }
  def has_active_self_serve_trial?
    return false unless has_active_trial?

    trial_type = get_active_trial_type
    return false if trial_type.nil?

    [:ghas_stand_alone, :digital_front_door].include?(trial_type)
  end

  # Returns true if a sales-led trial is active
  sig { returns(T::Boolean) }
  def has_active_sales_led_trial?
    has_active_trial? && get_active_trial_type == :sales_led
  end

  # Returns the active trial type symbol (:sales_led, :ghas_stand_alone, :digital_front_door)
  # or nil if no trial is active
  sig { returns(T.nilable(Symbol)) }
  def get_active_trial_type
    if secret_protection_trial.trial_active?
      secret_protection_trial.trial_type
    elsif code_security_trial.trial_active?
      code_security_trial.trial_type
    end
  end

  sig { returns(T::Boolean) }
  def unified_trials_enabled?
    FeatureFlag.vexi.enabled?(:unified_self_serve_ghas_trials, business, default: false)
  end

  sig { returns(String) }
  def extend_trial_form_path
    advanced_security_trials_stafftools_enterprise_path(T.cast(billable_entity, Business).slug)
  end

  sig { returns(String) }
  def end_trial_form_path
    advanced_security_trials_stafftools_enterprise_path(T.cast(billable_entity, Business).slug)
  end

  # Detailed eligibility checks - returns specific reasons why trial cannot be started
  sig { returns(T::Array[String]) }
  def ineligibility_reasons
    return [] unless billable_entity.is_a?(Business)

    business = T.cast(billable_entity, Business)
    reasons = []

    # Use the main eligibility method to check if eligible
    if business.eligible_for_self_serve_advanced_security_trial?
      return [] # No reasons - eligible!
    end

    # If not eligible, check specific reasons

    # Check if already on trial first
    if business.has_active_advanced_security_trial?
      reasons << "Enterprise already has an active self-serve Advanced Security trial"
    end

    # Check underlying conditions from potentially_trial_or_purchase_advanced_security?
    unless business.potentially_trial_or_purchase_advanced_security?
      if GitHub.enterprise?
        reasons << "Not available on GitHub Enterprise Server - must be on GitHub.com"
      elsif business.downgraded_to_free_plan?
        reasons << "Enterprise is on a downgraded free plan"
      elsif business.eligible_for_self_serve_payment?
        # Self-serve payment checks - replicate metered_ghe_allow_ghas_trial? logic
        if business.metered_ghe? && !business.trial?
          reasons << "Metered GHE business must be on trial to allow GHAS trials"
        end
        if business.dunning?
          reasons << "Account is in dunning status (payment issues)"
        end
      else
        # Sales-managed payment checks
        unless business.sales_managed_subscription_self_serve_eligible?
          reasons << "Sales-managed subscription is not self-serve eligible"
        end
        unless business.billing_term_ends_on.present?
          reasons << "No active billing term found"
        end
        if business.billing_term_ends_on.present? && business.billing_term_ends_on <= (GitHub::Billing.today - 1.year)
          reasons << "Billing term expired more than a year ago"
        end
        if business.past_due_invoice?
          reasons << "Enterprise has past due invoices"
        end
      end
    end

    # Check self-serve payment eligibility
    unless business.eligible_for_self_serve_payment?
      reasons << "Enterprise must have self-serve payment enabled"
    end

    # Check if already on metered GHAS
    if business.advanced_security_metered_for_entity?
      reasons << "Enterprise already has metered Advanced Security enabled"
    end

    # Check trial duration
    if business.new_advanced_security_trial_days < 14
      reasons << "Trial duration is insufficient (less than 14 days)"
    end

    # Check if billing system allows free trial
    begin
      unless ::Billing::Public::SubscriptionItem.eligible_for_free_trial?(
        product: ::AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_MONTHLY_PRODUCT,
        account: business
      )
        reasons << "Billing system does not allow free trial (may have had a recent trial)"
      end
    rescue => e
      reasons << "Unable to check billing trial eligibility"
    end

    reasons
  end

  sig { returns(T::Boolean) }
  def all_eligibility_checks_pass?
    return false unless billable_entity.is_a?(Business)

    business = T.cast(billable_entity, Business)
    business.eligible_for_self_serve_advanced_security_trial? && !business.has_active_advanced_security_trial?
  end

  sig { returns(T.nilable(Billing::Public::SubscriptionItem)) }
  def advanced_security_subscription_item
    return nil unless billable_entity.is_a?(Business)

    business = T.cast(billable_entity, Business)
    business.advanced_security_subscription_item
  end

  sig { returns(T.nilable(Date)) }
  def expires_at
    return nil unless has_active_trial?

    # Check SKU-based trials first if FF enabled
    if unified_trials_enabled?
      return EnterpriseCloudOnboard::AdvancedSecurityTrial.advanced_security_free_trial_ends_on(billable_entity: business)
    end

    # Fall back to legacy subscription item
    subscription_item = advanced_security_subscription_item
    return nil unless subscription_item

    # Get the end date as a DateTime for proper time formatting
    subscription_item.free_trial_ends_on
  end

  sig { returns(T.nilable(Integer)) }
  def current_trial_duration_days
    return nil unless has_active_trial?

    # Check SKU-based trials first if FF enabled
    if unified_trials_enabled?
      return EnterpriseCloudOnboard::AdvancedSecurityTrial.advanced_security_trial_duration_days(billable_entity: business)
    end

    # Fall back to legacy subscription item
    subscription_item = advanced_security_subscription_item
    return nil unless subscription_item

    # Use the built-in method to calculate total trial length
    subscription_item.free_trial_length
  end

  # Trial history methods for stafftools display

  # Returns true only if BOTH SKUs are eligible for self-serve trial
  # Since users start one combined GHAS trial (not per-SKU), both must be eligible
  sig { returns(T::Boolean) }
  memoize def combined_self_serve_eligible?
    secret_protection_trial.eligibility_details[:eligible] && code_security_trial.eligibility_details[:eligible]
  end

  sig { returns(EnterpriseCloudOnboard::SecretProtectionTrial) }
  memoize def secret_protection_trial
    EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: business)
  end

  sig { returns(EnterpriseCloudOnboard::CodeSecurityTrial) }
  memoize def code_security_trial
    EnterpriseCloudOnboard::CodeSecurityTrial.new(billable_entity: business)
  end

  sig { params(trial: EnterpriseCloudOnboard::SKUTrial).returns(String) }
  def sku_display_name(trial:)
    case trial
    when EnterpriseCloudOnboard::SecretProtectionTrial
      "Secret Protection"
    when EnterpriseCloudOnboard::CodeSecurityTrial
      "Code Security"
    else
      "Unknown SKU"
    end
  end

  sig { params(details: T::Hash[Symbol, T.untyped]).returns(T::Array[String]) }
  def format_ineligibility_reasons(details:)
    reasons = []

    return reasons if details[:eligible]

    unless details[:feature_enabled]
      reasons << "Self-serve GHAS trial feature is not enabled"
    end

    if details[:trial_active]
      reasons << "A trial is already active"
    end

    if details[:trial_count_limit_reached]
      reasons << "Trial limit (#{details[:trial_count_limit]}) reached"
    end

    if details[:within_cooldown_period]
      reasons << "Within cooldown period (#{details[:remaining_cooldown_days]} days remaining)"
    end

    if details[:seat_limit_exceeded]
      seat_type = details[:metered_ghe] ? "consumed GHE" : "GHE"
      reasons << "Seat limit exceeded for self-serve trial (current: #{details[:current_seats]} #{seat_type} seats, max: #{details[:self_serve_trial_max_seats]})"
    end

    if details[:ghas_in_use]
      reasons << "GHAS is already in use (must have zero usage to start trial)"
    end

    if details[:had_paid_ghas_usage_within_cooldown]
      reasons << "Had paid GHAS usage within #{details[:cooldown_period_days]}-day cooldown period"
    end

    reasons
  end

  # Returns the SKU for a given trial instance
  sig { params(trial: EnterpriseCloudOnboard::SKUTrial).returns(GitHub::Turboghas::SKU) }
  def sku_for_trial(trial:)
    case trial
    when EnterpriseCloudOnboard::SecretProtectionTrial
      GitHub::Turboghas::SKU::SecretSecurity
    when EnterpriseCloudOnboard::CodeSecurityTrial
      GitHub::Turboghas::SKU::CodeSecurity
    else
      raise ArgumentError, "Unknown trial type"
    end
  end
end
