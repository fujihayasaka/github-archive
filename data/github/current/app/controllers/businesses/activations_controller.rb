# typed: true
# frozen_string_literal: true

class Businesses::ActivationsController < Businesses::BusinessController
  include TradeControlsControllerMethods
  include TradeControlsHelper

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
        label: "Consumed user licenses",
        cost: plan_change.unit_price,
        quantity: seats,
        unit: "seat",
        allow_removal: false,
        removal_text: "",
        id: "consumed-user-licenses",
      }

    if this_business.has_active_advanced_security_trial?
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
        id: "advanced-security-licenses",
      }
    end

    total_monthly_charge = Billing::Money.zero
    billed_items.each do |billed_item|
      total_monthly_charge += billed_item[:cost] * billed_item[:quantity]
    end

    render "businesses/activations/index", locals: {
      this_business: this_business,
      selected_duration: duration,
      billed_items: billed_items,
      total_monthly_charge: total_monthly_charge,
      trade_screening_error_data: trade_screening_cannot_proceed_error_data(target: this_business)
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
end
