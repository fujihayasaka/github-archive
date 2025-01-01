# typed: true
# frozen_string_literal: true

class Businesses::ActivationsController < Businesses::BusinessController
  include TradeControlsControllerMethods
  include TradeControlsHelper
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
        label: "Consumed user licenses",
        cost: plan_change.unit_price,
        quantity: seats,
        unit: "seat",
        allow_removal: false,
        removal_text: "",
        id: "consumed-user-licenses",
      }

    unbundle_ghas_products = feature_flag_enabled?(this_business, FeatureFlags::GHE_ACTIVATION_UNBUNDLED_GHAS_PRODUCTS)
    if this_business.has_active_advanced_security_trial? && !unbundle_ghas_products
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

    if this_business.has_active_advanced_security_trial? && unbundle_ghas_products
      secret_protection_id = "secret-protection-unbundled"
      code_security_id = "code-security-unbundled"

      secret_protection_pricing_sku = "ghas_secret_protection_licenses"
      code_security_pricing_sku = "ghas_code_security_licenses"

      secret_protection_unit_price = unit_price_for_unbundled_sku(secret_protection_pricing_sku)
      code_security_unit_price = unit_price_for_unbundled_sku(code_security_pricing_sku)

      billed_items << {
        label: "Secret Protection",
        cost: secret_protection_unit_price.nil? ? nil : Billing::Money.new(secret_protection_unit_price * 100),
        quantity: secret_protection_seats,
        unit: "committer",
        show_info: true,
        info: safe_join([
          "To remove Secret Protection, disable it for private and internal repositories in ",
          ActionController::Base.helpers.link_to(
            "security settings",
            settings_security_analysis_enterprise_path(this_business)
          ),
          "."]
        ),
        id: secret_protection_id,
      }

      billed_items << {
        label: "Code Security",
        cost: code_security_unit_price.nil? ? nil : Billing::Money.new(code_security_unit_price * 100),
        quantity: code_security_seats,
        unit: "committer",
        show_info: true,
        info: safe_join([
          "To remove Code Security, disable it for private and internal repositories in",
          ActionController::Base.helpers.link_to(
            "security settings",
            settings_security_analysis_enterprise_path(this_business)
          ),
          "."]
        ),
        id: code_security_id,
      }
    end

    if this_business.has_ongoing_copilot_business_trial?
      copilot_business = Copilot::Business.new(this_business)
      trial_seats = copilot_business.copilot_enabled_members_count_by_license[:business] || 0
      billed_items << {
        label: "Copilot Business",
        cost: Billing::Money.new(Copilot::COPILOT_BUSINESS_MONTHLY_BASE_PRICE * 100),
        quantity: trial_seats,
        unit: "seats",
        allow_removal: true,
        removal_text: "This will immediately remove Copilot Business from your enterprise, and it cannot be re-enabled during the trial.",
        id: "copilot-business-seats",
      }
    end

    total_monthly_charge = Billing::Money.zero
    billed_items.each do |billed_item|
      if billed_item[:cost].nil?
        return render "businesses/activations/index", locals: {
          this_business: this_business,
          selected_duration: duration,
          billed_items: billed_items,
          total_monthly_charge: nil,
          trade_screening_error_data: trade_screening_cannot_proceed_error_data(target: this_business)
        }
      end
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

  sig { returns(::Billing::Platform::Api::Client) }
  memoize def billing_client
    ::Billing::Platform::Api::Client.new
  end


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

  sig { params(sku: String).returns(T.nilable(Float)) }
  def unit_price_for_unbundled_sku(sku)
    pricing_response = billing_client.get_pricing(sku: sku)
    if pricing_response.is_a?(::Billing::Platform::Api::Error)
      Failbot.report("Failed to fetch pricing for unbundled SKU",
        error: pricing_response,
        business_id: this_business.id,
        sku: sku
      )
      return nil
    end

    pricing = pricing_response[:pricing]&.slice(:price)
    if pricing.nil?
      Failbot.report("Received empty price for unbundled SKU",
        business_id: this_business.id,
        sku: sku,
        response: pricing_response
      )
      return nil
    end

    pricing[:price]
  end

  def secret_protection_seats
    this_business.secret_protection.seats_used
  end

  def code_security_seats
    this_business.code_security.seats_used
  end
end
