# typed: true
# frozen_string_literal: true

class Businesses::TrialActivationsController < Businesses::BusinessController
  include TradeControlsControllerMethods
  include Site::MicrosoftAnalyticsDependency

  before_action :dotcom_required
  before_action :business_owner_required
  before_action :metered_trial_required
  before_action :dfd_trial_required
  before_action :add_csp_exceptions
  before_action only: :index do
    T.bind(self, Businesses::TrialActivationsController)
    check_trade_compliance(target: this_business)
  end

  # Enable 1DS / MSFT analytics
  before_action :enable_microsoft_analytics
  before_action :add_microsoft_analytics_csp_exceptions

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Copilot,
    only: [:index]

  layout "layouts/enterprise_funnel", only: [:index]
  javascript_bundle :billing, only: [:index]

  CSP_EXCEPTIONS = T.let({
    img_src: [GitHub.paypal_checkout_url].freeze,
    connect_src: [GitHub.braintreegateway_url, GitHub.braintree_analytics_url].freeze,
  }.freeze, T::Hash[Symbol, T::Array[String]])

  sig { void }
  def create
    if can_initiate_copilot_trial_activation?
      Billing::AuthAndCapture::AuthorizeTrialJob.perform_later(this_business, current_user)
      flash[:notice] = "Your payment method is being verified. Copilot Business will be activated once complete."
      redirect_to next_path
    else
      render "businesses/trial_activations/index", locals: {
        this_business: this_business,
        is_trade_restricted: this_business.has_commercial_interaction_restriction?,
        completed_billing_information: completed_billing_information?,
        completed_billing_and_shipping_information: completed_billing_and_shipping_information?,
        validate_payment_method_error: "Add a valid payment method.",
        next_path: next_path
      }
    end
  end

  sig { void }
  def index
    session[:return_to] = enterprise_trial_activations_path(this_business)
    render "businesses/trial_activations/index", locals: {
      this_business: this_business,
      is_trade_restricted: this_business.has_commercial_interaction_restriction?,
      completed_billing_information: completed_billing_information?,
      completed_billing_and_shipping_information: completed_billing_and_shipping_information?,
      validate_payment_method_error: nil,
      next_path: next_path,
      microsoft_analytics_metadata: this_business.get_microsoft_analytics_metadata,
    }
  end

  private

  sig { void }
  def metered_trial_required
    render_404 unless this_business.metered_ghec_trial?
  end

  sig { void }
  def dfd_trial_required
    render_404 unless this_business.dfd_trial?
  end

  sig { returns(T::Boolean) }
  def completed_billing_information?
    helpers.billing_info_exists_without_errors?(this_business) && this_business.billing_contact.validated_for_sales_tax?
  end

  sig { returns(T::Boolean) }
  def completed_billing_and_shipping_information?
    return false unless completed_billing_information?
    this_business.shipping_contact.persisted?
  end

  sig { returns(T::Boolean) }
  def can_initiate_copilot_trial_activation?
    return false unless completed_billing_and_shipping_information?
    return false if this_business.has_commercial_interaction_restriction?
    this_business.has_valid_payment_method?
  end

  sig { returns(String) }
  def next_path
    if this_business.organizations.blank?
      new_enterprise_onboarding_organization_path(this_business)
    else
      enterprise_getting_started_path(this_business)
    end
  end
end
