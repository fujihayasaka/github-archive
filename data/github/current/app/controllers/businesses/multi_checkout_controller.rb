# typed: strict
# frozen_string_literal: true

class Businesses::MultiCheckoutController < Businesses::BusinessController
  include BillingSettingsHelper

  class UnprocessableError < StandardError; end
  before_action :ensure_billing_enabled
  before_action :ensure_not_spammy_user
  before_action :business_access_required
  before_action :business_trial_required
  before_action :trial_conversion_not_initiated_required
  before_action :eligible_for_self_serve_payment_required
  before_action :check_trade_compliance_before_metered_checkout_page, only: [:edit]
  before_action :eligible_for_volume_to_metered_transition
  before_action :add_csp_exceptions, only: [:edit]
  before_action only: [:update] do
    T.bind(self, Businesses::MultiCheckoutController)

    check_trade_compliance(target: this_business, sdn_redirect: true, redirect_url: settings_billing_tab_enterprise_url(tab: :payment_information))
  end
  before_action only: [:edit] do
    T.bind(self, Businesses::MultiCheckoutController)

    check_trade_compliance(target: this_business)
  end

  include Site::MicrosoftAnalyticsDependency
  before_action :allow_initial_cookie_consent, only: [:edit]
  before_action :enable_microsoft_analytics, only: [:edit]
  before_action :add_microsoft_analytics_csp_exceptions, only: [:edit]
  before_action :require_tos_acceptance, only: [:update]

  layout "enterprise_funnel", only: [:edit]
  javascript_bundle :billing, only: [:edit]
  stylesheet_bundle :settings

  # Used to render 404
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:edit], optional: true

  CSP_EXCEPTIONS = T.let({
    img_src: [GitHub.paypal_checkout_url].freeze,
    connect_src: [GitHub.braintreegateway_url, GitHub.braintree_analytics_url].freeze,
  }.freeze, T::Hash[Symbol, T::Array[String]])

  sig { void }
  def update
    if params[:volume_to_metered] == "true"

      analytics_event(
        category: "licensing.self_serve_metered_transition",
        action: "accept_terms_of_service",
        label: "business_slug:#{this_business.to_param};user:#{current_user.display_login};accept_terms_of_service:#{params[:agreed_to_terms] == 'yes'};timestamp:#{Time.current.iso8601}"
      )

      transition_date = volume_to_metered_transition_date

      transition = this_business.customer&.new_licensing_model_transition(
        licensing_model: "metered",
        actor: current_user,
        transition_date: transition_date,
        unbundle_ghas: :unbundle_ghas,
      )

      if !transition&.save
        flash[:error] = "Metered transition unsuccessful."
      end
      redirect_to enterprise_licensing_path(this_business)
      return
    end

    result = this_business.purchase_enterprise_and_ghas(
      actor: current_user,
      enterprise_seats: enterprise_seats,
      enterprise_plan_duration: selected_duration,
      ghas_committers: ghas_committers
    )

    if result.ok?
      plan_change, summary, line_item_detail = price_summary
      total = summary[:due_today]
      analytics_event(
        category: "business_multi_checkout",
        action: "complete_github_enterprise_purchase",
        label: "enterprise_id:#{this_business.id};seats:#{enterprise_seats};committers:#{ghas_committers};duration:#{selected_duration};total:#{total}"
      )
      GitHub.dogstats.increment("business.multi_checkout", tags: ["enterprise", "advanced_security:#{ghas_committers > 0}"])
      flash[:notice] = "Your purchase will complete when your payment is successful."
      redirect_to enterprise_path(this_business)
    else
      error = result.error.is_a?(String) ? UnprocessableError.new(result.error) : result.error
      Failbot.report(
        error,
        {
          :catalog_service => "github/ghas_self_serve_trial",
          "gh.business.id" => this_business.id,
          "code.namespace" => "business.multi_checkout",
        }
      )
      GitHub.dogstats.increment("business.multi_checkout.error", tags: ["enterprise", "advanced_security:#{ghas_committers > 0}"])
      flash[:error] = result.error
      redirect_to edit_multi_checkout_enterprise_path(this_business)
    end
  end

  sig { void }
  def edit
    plan_change, summary, line_item_detail = price_summary
    monthly_summary = summary[:monthly_summary]
    yearly_summary = summary[:yearly_summary]
    due_today = summary[:due_today]
    monthly_enterprise_line_item = line_item_detail[:monthly_enterprise_line_item]
    monthly_advanced_security_line_item = line_item_detail[:monthly_advanced_security_line_item]
    monthly_secret_protection_line_item = line_item_detail[:monthly_secret_protection_line_item]
    monthly_code_security_line_item = line_item_detail[:monthly_code_security_line_item]
    yearly_enterprise_line_item = line_item_detail[:yearly_enterprise_line_item]
    respond_to do |format|
      format.html do
        render "businesses/billing_settings/multi_checkout", locals: {
          this_business: this_business,
          selected_duration: selected_duration,
          maximum_seat_count: Billing::EnterpriseCloudTrial::INITIAL_SEAT_COUNT,
          price_per_seat: plan_change.unit_price,
          advanced_security_price_per_seat: this_business.advanced_security_price(
            seats: 1,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
          ),
          secret_protection_price_per_seat: secret_protection_unit_price || Billing::Money.new(0),
          code_security_price_per_seat: code_security_unit_price || Billing::Money.new(0),
          suggested_advanced_security_seats: this_business.has_active_advanced_security_trial? ? this_business.advanced_security_license.consumed_seats : 0,
          consumed_enterprise_seats: consumed_enterprise_seats,
          consumed_advanced_security_seats: consumed_advanced_security_seats,
          consumed_secret_protection_seats: consumed_secret_protection_seats,
          consumed_code_security_seats: consumed_code_security_seats,
          monthly_summary:,
          yearly_summary:,
          due_today:,
          monthly_enterprise_line_item:,
          monthly_advanced_security_line_item:,
          monthly_secret_protection_line_item:,
          monthly_code_security_line_item:,
          monthly_is_hidden: monthly_summary[:line_items].length == 0,
          yearly_is_hidden: selected_duration == "month",
          volume_to_metered_transition_date: volume_to_metered_transition_date,
        }
      end
      format.json do
        selectors = {
          ".multi-checkout-monthly-enterprise-description": monthly_enterprise_line_item&.[](:description),
          ".multi-checkout-monthly-enterprise-cost": monthly_enterprise_line_item&.[](:cost),
          ".multi-checkout-monthly-advanced-security-description": monthly_advanced_security_line_item&.[](:description),
          ".multi-checkout-monthly-advanced-security-cost": monthly_advanced_security_line_item&.[](:cost),
          ".multi-checkout-monthly-total": monthly_summary[:recurring_total],
          ".multi-checkout-yearly-enterprise-description": yearly_enterprise_line_item&.[](:description),
          ".multi-checkout-yearly-enterprise-cost": yearly_enterprise_line_item&.[](:cost),
          ".multi-checkout-due-today": due_today,
        }

        if params[:volume_to_metered].present?
          selectors.merge!({
            ".multi-checkout-monthly-secret-protection-description": monthly_secret_protection_line_item&.[](:description),
            ".multi-checkout-monthly-secret-protection-cost": monthly_secret_protection_line_item&.[](:cost),
            ".multi-checkout-monthly-code-security-description": monthly_code_security_line_item&.[](:description),
            ".multi-checkout-monthly-code-security-cost": monthly_code_security_line_item&.[](:cost),
          })
        end

        render json: summary.merge({
          selectors: selectors,
        })
      end
    end
  end

  private

  sig { returns [Billing::PlanChange::PerSeatPricingModel, T::Hash[Symbol, T.untyped], T::Hash[Symbol, T.untyped]] }
  def price_summary
    plan = GitHub::Plan.business_plus(account: this_business)
    subscription = Billing::Subscription.for_account(
      this_business,
      seats: enterprise_seats,
      plan: plan,
      duration_in_months: duration_in_months
    )
    plan_change = Billing::PlanChange::PerSeatPricingModel.new(
      this_business,
      plan_duration: selected_duration,
      new_plan: plan,
      seats: enterprise_seats,
      plan_effective_at: this_business.trial? ? this_business.trial_expires_at.to_date : nil,
      plan_and_seat_cost_only: true
    )

    due_today = Billing::Money.zero
    monthly_summary = { line_items: [], recurring_total: Billing::Money.zero }
    yearly_summary = { line_items: [] }
    seat_or_license = params[:volume_to_metered].present? ? "license" : "seat"

    enterprise_consumed_or_available_licenses = if params[:volume_to_metered].present?
      consumed_enterprise_seats
    else
      enterprise_seats
    end

    cost_subscription = Billing::Subscription.for_account(
      this_business,
      seats: enterprise_consumed_or_available_licenses,
      plan: GitHub::Plan.business_plus(account: this_business),
      duration_in_months: duration_in_months
    )

    enterprise_cloud_cost = if params[:volume_to_metered].present?
      plan = GitHub::Plan.business_plus(account: this_business)
      metered_cost = enterprise_monthly_cost(unit_cost_in_cents: plan.unit_cost_in_cents, seats: enterprise_consumed_or_available_licenses)
      metered_cost
    else
      cost_subscription.plan_and_seat_cost
    end

    enterprise_line_item = {
      name: "Enterprise",
      description: "· #{pluralize(enterprise_consumed_or_available_licenses, seat_or_license)}",
      seats: enterprise_consumed_or_available_licenses,
      cost: enterprise_cloud_cost.format,
    }

    monthly_enterprise_line_item = nil
    monthly_advanced_security_line_item = nil
    monthly_secret_protection_line_item = nil
    monthly_code_security_line_item = nil
    yearly_enterprise_line_item = nil
    if plan_change.monthly_plan?
      enterprise_line_item[:description] = "Monthly #{enterprise_line_item[:description]}"
      monthly_summary[:line_items] << enterprise_line_item
      monthly_enterprise_line_item = enterprise_line_item
      monthly_summary[:recurring_total] += enterprise_cloud_cost
    else
      enterprise_line_item[:description] = "Yearly #{enterprise_line_item[:description]}"
      yearly_summary[:line_items] << enterprise_line_item
      yearly_enterprise_line_item = enterprise_line_item
      due_today += plan_change.renewal_price(github_only: plan_change.changing_duration?)
    end

    # Currently we only support monthly billing for Advanced Security
    if ghas_committers > 0
      advanced_security_cost = this_business.advanced_security_price(seats: ghas_committers, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      per_committer_cost = advanced_security_cost / ghas_committers
      monthly_advanced_security_line_item = {
        name: "Advanced Security",
        description: "Monthly · #{pluralize(ghas_committers, "committers")}",
        seats: ghas_committers,
        cost: advanced_security_cost.format,
      }
      monthly_summary[:line_items] << monthly_advanced_security_line_item
      monthly_summary[:recurring_total] += advanced_security_cost
    end

    # Secret Protection Monthly Summary
    monthly_secret_protection_line_item = {
      name: "Secret Protection",
      description: "Monthly · #{pluralize(consumed_secret_protection_seats, 'license')}",
      cost: secret_protection_monthly_cost.format,
    }

    # Code Security Monthly Summary
    monthly_code_security_line_item = {
      name: "Code Security",
      description: "Monthly · #{pluralize(consumed_code_security_seats, 'license')}",
      cost: code_security_monthly_cost.format,
    }

    if params[:volume_to_metered].present?
      monthly_summary[:recurring_total] = enterprise_cloud_cost + secret_protection_monthly_cost + code_security_monthly_cost
    end

    due_today += monthly_summary[:recurring_total]
    monthly_summary[:recurring_total] = monthly_summary[:recurring_total] == Billing::Money.zero ? nil : monthly_summary[:recurring_total].format

    [
      plan_change,
      {
        yearly_summary:,
        monthly_summary:,
        due_today: due_today.format,
      },
      {
        monthly_enterprise_line_item:,
        monthly_advanced_security_line_item:,
        monthly_secret_protection_line_item:,
        monthly_code_security_line_item:,
        yearly_enterprise_line_item:,
      },
    ]
  end

  sig { void }
  def business_trial_required
    # bypass trial requirement for volume to metered transitions
    return if params[:volume_to_metered] == "true"
    return render_404 unless this_business.trial?
    render_404 if this_business.metered_plan?
  end

  sig { void }
  def trial_conversion_not_initiated_required
    render_404 if this_business.trial_conversion_initiated?
  end

  sig { returns(String) }
  memoize def selected_duration
    return User::BillingDependency::MONTHLY_PLAN if params[:volume_to_metered].present?
    params[:plan_duration] || default_plan_duration(this_business)
  end

  sig { returns(Integer) }
  memoize def duration_in_months
    selected_duration == User::BillingDependency::MONTHLY_PLAN ? 1 : 12
  end

  sig { returns(Integer) }
  memoize def enterprise_seats
    seats = params[:seats] ? params[:seats].to_i : this_business.seats
    seats = [seats, this_business.seat_limit_for_upgrades].min
    [seats, this_business.total_consumed_licenses, 1].max
  end

  sig { returns(Integer) }
  memoize def ghas_committers
    committers = params[:committers] ? params[:committers].to_i : 0
    [committers, this_business.seat_limit_for_advanced_security_upgrade].min
  end

  sig { void }
  def eligible_for_volume_to_metered_transition
    return unless params[:volume_to_metered].present?

    unless this_business.eligible_for_self_serve_metered_transition?(current_user: current_user, on_licensing_page: true)
      render_404
    end
  end

  sig { returns(Date) }
  def volume_to_metered_transition_date
    transition_date = this_business.next_billing_date
    if transition_date == Date.current
      transition_date = transition_date + 1.month
    end
    transition_date
  end

  sig { void }
  def check_trade_compliance_before_metered_checkout_page
    return unless params[:volume_to_metered].present?

    T.bind(self, Businesses::MultiCheckoutController)
    check_trade_compliance(target: this_business, sdn_redirect: true, redirect_url: enterprise_licensing_path(this_business))
  end

  sig { returns(Integer) }
  memoize def consumed_enterprise_seats
    this_business.total_consumed_licenses
  end

  sig { returns(Integer) }
  memoize def consumed_advanced_security_seats
    this_business.advanced_security_license.consumed_seats
  end

  sig { returns(Integer) }
  memoize def consumed_secret_protection_seats
    if this_business.advanced_security_products_bundled?
      consumed_advanced_security_seats
    else
      this_business.secret_protection.seats_used
    end
  end

  sig { returns(Integer) }
  memoize def consumed_code_security_seats
    if this_business.advanced_security_products_bundled?
      consumed_advanced_security_seats
    else
      this_business.code_security.seats_used
    end
  end

  sig { returns(::Billing::Platform::Api::Client) }
  memoize def billing_client
    ::Billing::Platform::Api::Client.new
  end

  sig { params(sku: String).returns(T.nilable(Float)) }
  def unit_price_for_unbundled_sku(sku)
    pricing_response = billing_client.get_pricing(sku: sku)
    if pricing_response.is_a?(::Billing::Platform::Api::Error)
      Failbot.report(StandardError.new("Failed to fetch pricing for unbundled SKU"),
        error: pricing_response,
        business_id: this_business.id,
        sku: sku
      )
      return nil
    end

    pricing = pricing_response[:pricing]&.slice(:price)
    if pricing.nil?
      Failbot.report(StandardError.new("Received empty price for unbundled SKU"),
        business_id: this_business.id,
        sku: sku,
        response: pricing_response
      )
      return nil
    end

    pricing[:price]
  end

  sig { returns(T.nilable(Billing::Money)) }
  memoize def secret_protection_unit_price
    price = unit_price_for_unbundled_sku("ghas_secret_protection_licenses")
    price.nil? ? nil : Billing::Money.new(price * 100)
  end

  sig { returns(T.nilable(Billing::Money)) }
  memoize def code_security_unit_price
    price = unit_price_for_unbundled_sku("ghas_code_security_licenses")
    price.nil? ? nil : Billing::Money.new(price * 100)
  end

  sig { params(unit_cost_in_cents: Integer, seats: Integer).returns(Billing::Money) }
  def enterprise_monthly_cost(unit_cost_in_cents:, seats:)
    Billing::Money.new(unit_cost_in_cents) * seats
  end

  sig { returns(Billing::Money) }
  def secret_protection_monthly_cost
    unit_price = secret_protection_unit_price || Billing::Money.new(0)
    unit_price * consumed_secret_protection_seats
  end

  sig { returns(Billing::Money) }
  def code_security_monthly_cost
    unit_price = code_security_unit_price || Billing::Money.new(0)
    unit_price * consumed_code_security_seats
  end
end
