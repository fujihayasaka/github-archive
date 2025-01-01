# typed: true
# frozen_string_literal: true

class Orgs::CreationView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include TradeControlsHelper
  include GitHub::Memoizer
  extend Forwardable

  attr_reader :coupon, :per_seat_pricing_model, :plan, :organization,
    :annual_per_seat_pricing_model, :monthly_per_seat_pricing_model,
    :annual_business_plus_pricing_model, :monthly_business_plus_pricing_model,
    :terms_of_service, :org_transform, :current_user, :account_screening_profile,
    :org_transform_steps_complete, :admin_logins

  def_delegators :per_seat_pricing_model,
  :plan_duration,
  :final_price,
  :monthly_plan?,
  :annual_plan?

  def show_only_per_seat_plan?
    coupon && per_seat_pricing_model.final_price.zero?
  end

  def current_plan_duration
    per_seat_pricing_model.plan_duration
  end

  def trade_screening_record(ignore_user_record: false)
    unless ignore_user_record
      return current_user.trade_screening_record if standard_terms_of_service?
    end

    account_screening_profile
  end

  memoize def has_valid_trade_screening_record?
    return false unless trade_screening_record.present?

    if standard_terms_of_service?
      return false if !trade_screening_record.valid_for_owner_type?(skip_validation_errors: true, owner_type: :user) || !trade_screening_record.validated_for_sales_tax?
    else
      return false if !trade_screening_record.valid_for_owner_type?(skip_validation_errors: true, owner_type: :entity)
    end

    # billing email is collected on the billing info form but set to the org hash
    organization.billing_email.present?
  end

  def can_edit_billing_information?
    return false unless has_valid_trade_screening_record?
    return current_user.is_allowed_to_edit_trade_screening_information? if standard_terms_of_service?

    true
  end

  def has_commercial_interaction_restriction?
    return current_user.has_commercial_interaction_restriction? if standard_terms_of_service?

    false
  end

  def current_plan_duration_adjective
    "#{per_seat_pricing_model.plan_duration}ly"
  end

  def available_plan_duration
    per_seat_pricing_model.monthly_plan? ? User::BillingDependency::YEARLY_PLAN : User::BillingDependency::MONTHLY_PLAN
  end

  def available_plan_duration_adjective
    "#{available_plan_duration}ly"
  end

  def button_text
    "Next: Customize your setup"
  end

  def form_path
    urls.organizations_path
  end

  def account
    organization
  end

  def duration
    plan_duration
  end

  memoize def github_customer_terms?
    terms_of_service.downcase == "corporate"
  end

  memoize def standard_terms_of_service?
    terms_of_service.downcase == "standard"
  end

  memoize def orgs_data_collection_enabled?
    github_customer_terms? || standard_terms_of_service?
  end

  def duration_options
    User::BillingDependency::PLAN_DURATIONS.map(&:to_sym)
  end

  def billing_action_path
    urls.organizations_path
  end

  def yearly?
    plan_duration.to_s == User::BillingDependency::YEARLY_PLAN
  end

  # Public - List unit price for the new plan.
  # Does not include subscription items
  #
  # Returns Money
  def plan_unit_price(plan: self.plan)
    if yearly?
      plan_cost_in_cents = organization.annual_discount_allowed?(plan: plan, billing_cycle: User::BillingDependency::YEARLY_PLAN) ? plan.yearly_cost_in_cents_with_discount : plan.yearly_cost_in_cents
      Billing::Money.new(plan_cost_in_cents)
    else
      Billing::Money.new(plan.unit_cost_in_cents)
    end
  end

  def can_add_payment_method?
    # For organizations on the corporate terms of service, the trade screening record hasn't been created yet.
    return true unless standard_terms_of_service?

    # For organizations on the standard terms of service, the trade screening record exists already as it
    # belongs to the user creating the orgazniation. That trade screening record should have a validated address.
    trade_screening_record.validated_for_sales_tax?
  end

  def needs_valid_payment_method?
    organization.needs_valid_payment_method_to_switch_to_plan?(plan)
  end

  # Public - Checks if the price to be prorated or not
  # This returns false as during signup the price will not be prorated
  # and the view is shared between different templates
  def price_prorated?
    false
  end

  # Public - used to determine where the view is being rendered from
  # since this view can be used with different templates
  def view_from
    :orgs_creation
  end

  # Public - Will the change be applied immediately? (not a pending plan change)
  #
  # Returns Boolean
  def effective_immediately?
    true
  end

  # Public - Is the user creating org as business_plus or not
  # Only returns true if the user is creating an org as
  # a business plus plan
  #
  # Returns Boolean
  def changing_to_business_plus?
    plan.business_plus?
  end

  def coupon?
    organization.has_an_active_coupon? && organization.coupon.applicable_to?(plan)
  end

  def call_to_action_text
    button_text
  end

  def payment_method_css
    classes = ["mx-4 mx-md-0 js-payment-summary js-billing-section  zuora-billing-section js-data-collection-org-signup"]
    classes.push "has-billing" if organization.has_valid_payment_method?
    classes.push "has-removed-contents" unless (organization.new_record? && organization.try(:paid?)) || has_valid_trade_screening_record?
    if (org_transform && !current_user.has_valid_payment_method?) || (!org_transform && !current_user.has_paypal_account?)
      classes.push "PaymentMethod--creditcard"
    elsif !org_transform && current_user.has_paypal_account?
      classes.push "PaymentMethod--paypal"
    end
    classes.join(" ")
  end

  # Public - Maximum number of seats that can be purchased during a self-serve plan upgrade
  #
  # returns Integer
  def seat_limit_for_upgrades
    account.seat_limit_for_upgrades
  end

  def org_transform_step_one_complete?
    return false unless org_transform
    return false unless org_transform_steps_complete.present?

    terms_of_service.present?
  end

  def org_transform_step_two_complete?
    return false unless org_transform_step_one_complete?

    admin_logins.present?
  end

  def plan_for_org_transform
    if current_user.free_plan?
      current_user.plan
    elsif current_user.coupon.nil? && !current_user.has_billing_record?
      # Paid plan but no coupon or CC info. Downgrade them to free
      "free"
    elsif current_user.coupon && current_user.owned_private_repositories.empty?
      # Paid plan, has coupon and doesn't have private repositories
      GitHub::Plan.org_plan_for_discount(current_user.coupon.discount)
    else
      plan
    end
  end

  def show_sales_tax?
    account.customer&.in_taxable_country? || Customer::COUNTRY_CODES_SUBJECT_TO_SALES_TAX.include?(trade_screening_record&.country_code)
  end
end
