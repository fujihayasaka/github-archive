# typed: strict
# frozen_string_literal: true

class Businesses::AdvancedSecurity::UpgradeController < ::Businesses::AdvancedSecurity::SelfServeController
  include BillingSettingsHelper
  include Billing::BilledItemsHelper
  include ActionView::Helpers::TextHelper

  before_action :ensure_billing_enabled
  before_action :business_access_required
  before_action :ensure_self_serve_advanced_security

  include Site::MicrosoftAnalyticsDependency
  before_action :allow_initial_cookie_consent, only: [:show]
  before_action :enable_microsoft_analytics, only: [:show]
  before_action :add_microsoft_analytics_csp_exceptions, only: [:show]
  before_action only: :show do
    T.bind(self, Businesses::AdvancedSecurity::UpgradeController)

    check_trade_compliance(target: this_business)
  end
  before_action only: [:update] do
    T.bind(self, Businesses::AdvancedSecurity::UpgradeController)

    check_trade_compliance(target: this_business, sdn_redirect: true, redirect_url: enterprise_billing_payment_information_url(this_business))
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
        billed_items = billed_items_for_monthly_spending
        total_monthly_charge = total_monthly_charge(billed_items)

        render "businesses/billing_settings/advanced_security/upgrade", locals: {
          this_business: this_business,
          seats: seats,
          billed_items: billed_items,
          total_monthly_charge: total_monthly_charge
        }
      end
    end
  end

  sig { void }
  def update
    unless this_business.has_active_advanced_security_trial?
      flash[:error] = "No active Advanced Security trial to upgrade."
      return redirect_to_billing_settings_or_return_to
    end

    result = this_business.end_advanced_security_trial(actor: current_user, is_stafftools_action: false, purchase_unbundled_trial: true)

    if result.ok?
      flash[:success] = "Successfully activated GitHub Advanced Security."
    else
      flash[:error] = result.error.message
    end

    redirect_to_billing_settings_or_return_to
  end

  private

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def billed_items_for_monthly_spending
    build_unbundled_ghas_billed_items(this_business)
  end

  sig { returns(Business) }
  def this_business
    T.cast(super, Business)
  end
end
