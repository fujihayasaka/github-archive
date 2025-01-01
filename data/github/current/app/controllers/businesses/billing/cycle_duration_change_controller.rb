# typed: strict
# frozen_string_literal: true

# Used for customer-initiated GHE upgrades for both self and sales-serve customers.
class Businesses::Billing::CycleDurationChangeController < Businesses::BusinessController
  include Billing::ProrationMath

  before_action :ensure_billing_enabled
  before_action :ensure_not_spammy_user
  before_action :business_access_required
  before_action :ensure_metered
  before_action :ensure_not_trial

  before_action :eligible_for_self_serve_payment_required

  layout "enterprise_funnel", only: [:new]
  javascript_bundle :billing, only: [:new]
  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new],
    optional: true

  CSP_EXCEPTIONS = T.let({
    img_src: [GitHub.paypal_checkout_url].freeze,
    connect_src: [GitHub.braintreegateway_url, GitHub.braintree_analytics_url].freeze,
  }.freeze, T::Hash[Symbol, T::Array[String]])

  sig { void }
  def new
    selected_duration = params[:plan_duration] || default_plan_duration(this_business)
    respond_to do |format|
      format.html do
        render "businesses/billing_settings/cycle_change", locals: {
          this_business: this_business,
          selected_duration: selected_duration,
        }
      end
      format.json do
        duration_in_months = selected_duration == User::BillingDependency::MONTHLY_PLAN ? 1 : 12
        seats = params[:seats] ? params[:seats].to_i : this_business.seats
        seats = [seats, this_business.seat_limit_for_upgrades].min
        seats = [seats, this_business.total_consumed_licenses, 1].max
        plan = GitHub::Plan.business_plus(account: this_business)
        subscription = Billing::Subscription.for_account(
          this_business,
          seats: seats,
          plan: plan,
          duration_in_months: duration_in_months
        )
        plan_change = Billing::PlanChange::PerSeatPricingModel.new(
          this_business,
          plan_duration: selected_duration,
          new_plan: plan,
          seats: seats,
          plan_effective_at: nil,
          plan_and_seat_cost_only: true
        )
        render json: {
          seats: seats,
          duration: selected_duration,
          selectors: {
            ".unstyled-renewal-price" => subscription.plan_and_seat_cost.format,
            ".unstyled-payment-due" => plan_change.renewal_price(github_only: plan_change.changing_duration?).format,
            ".unstyled-new-seats" => seats,
          },
        }
      end
    end
  end

  sig { void }
  def create
    if this_business.plan_duration == params[:plan_duration]
      message = "You are already being billed on a #{params[:plan_duration]}ly billing cycle."
      type = "error"
    else
      seats = params[:seats]&.to_i || this_business.seats
      min_seats = [this_business.total_consumed_licenses, 1].max
      max_seats = this_business.seat_limit_for_upgrades
      now = Time.zone.now

      if seats < min_seats || seats > max_seats
        message = "Selected seats cannot be less than #{min_seats} or more than #{max_seats} seats."
        type = "error"
      else
        Billing::SchedulePlanChange.run(
          account: this_business,
          actor: current_user,
          seats: seats,
          plan_duration: params[:plan_duration],
          active_on: now
        )
        message = "You have been successfully switched to #{params[:plan_duration]}ly billing."
        type = "success"
      end
    end

    redirect_to enterprise_billing_payment_information_path(this_business, banner_message: message, banner_type: type)
  end

  private

  sig { void }
  def ensure_metered
    this_business.metered_plan?
  end

  sig { void }
  def ensure_not_in_lock_out_period
    redirect_to settings_billing_enterprise_path(this_business) if this_business.in_lock_out_period?
  end

  sig { void }
  def ensure_not_trial
    return render_404 if this_business.trial_conversion_initiated?
    redirect_to edit_multi_checkout_enterprise_path(this_business) if this_business.trial?
  end
end
