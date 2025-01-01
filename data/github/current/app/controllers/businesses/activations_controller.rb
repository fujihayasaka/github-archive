# typed: true
# frozen_string_literal: true

class Businesses::ActivationsController < Businesses::BusinessController
  include TradeControlsControllerMethods
  include TradeControlsHelper
  include Billing::BilledItemsHelper
  include SecretScanning::Features::FeatureFlagHelper

  before_action :business_owner_required
  before_action :metered_trial_required
  before_action :add_csp_exceptions, only: [:index]
  before_action only: :index do
    T.bind(self, Businesses::ActivationsController)
    check_trade_compliance(target: target)
  end


  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index]

  javascript_bundle :billing, only: [:index]
  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  CSP_EXCEPTIONS = T.let({
    img_src: [GitHub.paypal_checkout_url].freeze,
    connect_src: [GitHub.braintreegateway_url, GitHub.braintree_analytics_url].freeze,
  }.freeze, T::Hash[Symbol, T::Array[String]])

  def index
    billed_items = []
    billed_items << {
        label: this_business.enterprise_managed? ? "Enterprise" : "Enterprise Cloud",
        cost: plan_change.unit_price,
        quantity: seats,
        unit: "seat",
        allow_removal: false,
        removal_text: "",
        id: "consumed-user-licenses",
        show_info: this_business.enterprise_managed? || seats >= 0,
        info: this_business.enterprise_managed? ? "Organization members consume Enterprise seats." : "",
      }

    ghas_bundled = this_business.advanced_security_products_bundled?
    if this_business.has_active_advanced_security_trial? && ghas_bundled
      billed_items << {
        label: "Advanced Security",
        cost: advanced_security_unit_price,
        quantity: advanced_security_seats,
        unit: "committer",
        allow_removal: true,
        removal_text: safe_join([
          "This will immediately remove GitHub Advanced Security from your enterprise.",
          content_tag(:br),
          "To turn off GitHub Advanced Security on all repositories instead, go to ",
          ActionController::Base.helpers.link_to(
            "Configure security and analysis features",
            settings_security_analysis_enterprise_path(this_business)
          ),
          "."]
        ),
        removal_button_text: "Remove",
        show_info: nil,
        info: nil,
        id: "advanced-security-licenses",
      }
    end

    if this_business.has_active_advanced_security_trial? && !ghas_bundled
      billed_items.concat(build_unbundled_ghas_billed_items(this_business))
    end

    if show_copilot_seat_information?
      copilot_business = Copilot::Business.new(this_business)
      trial_seats = copilot_business.copilot_enabled_members_count_by_license[:business] || 0
      billed_items << {
        label: "Copilot Business",
        cost: Billing::Money.new(Copilot::COPILOT_BUSINESS_MONTHLY_BASE_PRICE * 100),
        quantity: trial_seats,
        unit: "seats",
        allow_removal: true,
        removal_text: "This will immediately remove Copilot Business from your enterprise, and it cannot be re-enabled during the trial.",
        removal_button_text: "Remove",
        show_info: nil,
        info: nil,
        id: "copilot-business-seats",
      }
    end

    render "businesses/activations/index", locals: {
      this_business: this_business,
      selected_duration: duration,
      billed_items: billed_items,
      total_monthly_charge: total_monthly_charge(billed_items),
      is_trade_restricted: this_business.has_commercial_interaction_restriction?,
    }
  end

  private

  memoize def plan_change
    plan = GitHub::Plan.business_plus(account: this_business)
    ::Billing::PlanChange::PerSeatPricingModel.new this_business,
      plan_duration: duration,
      new_plan: plan,
      seats: seats,
      plan_effective_at: nil
  end

  def duration
    User::BillingDependency::MONTHLY_PLAN
  end

  memoize def seats
    this_business.total_consumed_licenses
  end

  def business_owner_required
    render_404 unless this_business&.owner?(current_user)
  end

  def metered_trial_required
    unless this_business&.metered_plan? && this_business&.trial?
      redirect_to settings_billing_tab_enterprise_path(this_business, tab: :payment_information)
    end
  end

  def advanced_security_unit_price
    this_business.advanced_security_price(
      seats: 1,
      billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
    )
  end

  def advanced_security_seats
    this_business.advanced_security_license.consumed_seats
  end

  sig { override.returns(Business) }
  memoize def target
    this_business
  end

  def show_copilot_seat_information?
    return false unless this_business
    Copilot::Business.new(this_business).copilot_enabled_for_all_organizations? || this_business.has_ongoing_copilot_business_trial?
  end
end
