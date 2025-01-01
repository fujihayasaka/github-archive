# typed: strict
# frozen_string_literal: true

class Businesses::AdvancedSecurity::UpgradeController < ::Businesses::AdvancedSecurity::SelfServeController
  extend T::Sig
  include BillingSettingsHelper
  include ActionView::Helpers::TextHelper

  before_action :ensure_billing_enabled
  before_action :business_access_required
  before_action :ensure_self_serve_advanced_security

  include Site::MicrosoftAnalyticsDependency
  before_action :allow_initial_cookie_consent, only: [:show]
  before_action :enable_microsoft_analytics, only: [:show]
  before_action :add_microsoft_analytics_csp_exceptions, only: [:show]
  before_action :add_csp_exceptions, only: [:show]
  before_action only: :show do
    T.bind(self, Businesses::AdvancedSecurity::UpgradeController)

    check_trade_compliance(target: this_business)
  end
  before_action only: [:update] do
    T.bind(self, Businesses::AdvancedSecurity::UpgradeController)

    check_trade_compliance(target: this_business, sdn_redirect: true, redirect_url: settings_billing_tab_enterprise_url(tab: :payment_information))
  end
  layout "enterprise_funnel", only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  CSP_EXCEPTIONS = T.let({
    img_src: [GitHub.paypal_checkout_url].freeze,
    connect_src: [GitHub.braintreegateway_url, GitHub.braintree_analytics_url].freeze,
  }.freeze, T::Hash[Symbol, T::Array[String]])

  javascript_bundle :billing, only: [:show]

  sig { void }
  def show
    suggested_seats = this_business.has_active_advanced_security_trial? ? this_business.advanced_security_license.consumed_seats : 1
    seats = params[:seats] ? params[:seats].to_i : suggested_seats
    seats = [[seats, 1].max, this_business.seat_limit_for_upgrades].min

    price = this_business.advanced_security_price(seats: seats)
    respond_to do |format|
      format.json do
        render json: {
          seats: seats,
          selectors: {
            ".unstyled-payment-due" => price.format,
            ".unstyled-new-seats" => pluralize(seats, "committer"),
            ".unstyled-label" => "committer".pluralize(seats),
          },
        }
      end
      format.html do
        render "businesses/billing_settings/advanced_security/upgrade", locals: {
          this_business: this_business,
          seats: seats
        }
      end
    end
  end

  sig { void }
  def update
    new_seats = params[:seats].to_i

    # Early exit: do not allow setting seats to 0
    if new_seats <= 0
      flash[:error] = "Number of committers must be greater than 0."
      return redirect_to_billing_settings_or_return_to
    end

    seat_limit = this_business.seat_limit_for_advanced_security_upgrade
    if new_seats && new_seats > seat_limit
      flash[:error] = "Number of committers must be fewer than #{seat_limit}."
      return redirect_to_billing_settings_or_return_to
    end

    converted_from_trial = this_business.has_active_advanced_security_trial?
    result = this_business.subscribe_to_advanced_security(
      seats: new_seats,
      actor: current_user,
      billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
    )
    if result.ok?
      flash[:success] = "Successfully added #{new_seats} GitHub Advanced Security #{"Committer".pluralize(new_seats)}."
      analytics_event(
        category: "business_advanced_security_subscription",
        action: "subscribe_to_advanced_security",
        label: "business_id:#{this_business.id},seats:#{new_seats},converted_from_trial:#{converted_from_trial}",
      )
    else
      flash[:error] = result.error.message
    end

    redirect_to_billing_settings_or_return_to
  end
end
