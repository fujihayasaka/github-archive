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
          suggested_advanced_security_seats: this_business.has_active_advanced_security_trial? ? this_business.advanced_security_license.consumed_seats : 0,
          monthly_summary:,
          yearly_summary:,
          due_today:,
          monthly_enterprise_line_item:,
          monthly_advanced_security_line_item:,
          monthly_is_hidden: monthly_summary[:line_items].length == 0,
          yearly_is_hidden: selected_duration == "month",
        }
      end
      format.json do
        render json: summary.merge({
          selectors: {
            ".multi-checkout-monthly-enterprise-description": monthly_enterprise_line_item&.[](:description),
            ".multi-checkout-monthly-enterprise-cost": monthly_enterprise_line_item&.[](:cost),
            ".multi-checkout-monthly-advanced-security-description": monthly_advanced_security_line_item&.[](:description),
            ".multi-checkout-monthly-advanced-security-cost": monthly_advanced_security_line_item&.[](:cost),
            ".multi-checkout-monthly-total": monthly_summary[:recurring_total],
            ".multi-checkout-yearly-enterprise-description": yearly_enterprise_line_item&.[](:description),
            ".multi-checkout-yearly-enterprise-cost": yearly_enterprise_line_item&.[](:cost),
            ".multi-checkout-due-today": due_today,
          },
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
    enterprise_line_item = {
      name: "Enterprise",
      description: "· #{pluralize(enterprise_seats, "seat")}",
      seats: enterprise_seats,
      cost: subscription.plan_and_seat_cost.format,
    }

    monthly_enterprise_line_item = nil
    monthly_advanced_security_line_item = nil
    yearly_enterprise_line_item = nil
    if plan_change.monthly_plan?
      enterprise_line_item[:description] = "Monthly #{enterprise_line_item[:description]}"
      monthly_summary[:line_items] << enterprise_line_item
      monthly_enterprise_line_item = enterprise_line_item
      monthly_summary[:recurring_total] += subscription.plan_and_seat_cost
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
        yearly_enterprise_line_item:,
      },
    ]
  end

  sig { void }
  def business_trial_required
    render_404 unless this_business.trial?
    render_404 if this_business.metered_plan?
  end

  sig { void }
  def trial_conversion_not_initiated_required
    render_404 if this_business.trial_conversion_initiated?
  end

  sig { returns(String) }
  memoize def selected_duration
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
end
