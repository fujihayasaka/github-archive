# typed: true
# frozen_string_literal: true

class Businesses::TrialActivationsController < Businesses::BusinessController
  include TradeControlsControllerMethods

  before_action :dotcom_required
  before_action :business_owner_required
  before_action :metered_trial_required
  before_action :digital_front_door_mvp_ff_enabled_required
  before_action :not_eligible_to_trial_copilot_business_required
  before_action :add_csp_exceptions
  before_action only: :index do
    T.bind(self, Businesses::TrialActivationsController)
    check_trade_compliance(target: this_business)
  end

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  javascript_bundle :billing, only: [:index]

  CSP_EXCEPTIONS = T.let({
    img_src: [GitHub.paypal_checkout_url].freeze,
    connect_src: [GitHub.braintreegateway_url, GitHub.braintree_analytics_url].freeze,
  }.freeze, T::Hash[Symbol, T::Array[String]])

  sig { void }
  def create
    Billing::AuthAndCapture::AuthorizeTrialJob.perform_later(this_business, current_user)
    flash[:notice] = "Your payment method is being verified. Copilot Business will be activated once complete."
    redirect_to next_path
  end

  sig { void }
  def index
    session[:return_to] = enterprise_trial_activations_path(this_business)
    render "businesses/trial_activations/index", locals: {
      this_business: this_business,
      trade_screening_error_data: trade_screening_error_data,
      completed_billing_information: completed_billing_information?,
      completed_billing_and_shipping_information: completed_billing_and_shipping_information?,
      can_initiate_copilot_trial_activation: can_initiate_copilot_trial_activation?,
      next_path: next_path
    }
  end

  private

  sig { void }
  def metered_trial_required
    render_404 unless this_business.metered_ghec_trial?
  end

  sig { void }
  def digital_front_door_mvp_ff_enabled_required
    return if current_user.feature_enabled?(:digital_front_door_mvp)
    render_404 unless this_business.feature_enabled?(:digital_front_door_mvp)
  end

  sig { void }
  def not_eligible_to_trial_copilot_business_required
    render_404 if this_business.eligible_to_trial_copilot_business?
  end

  sig { returns(T::Boolean) }
  def completed_billing_information?
    return false unless this_business.has_saved_trade_screening_record_with_information?
    return false unless this_business.trade_screening_record.validated_for_sales_tax?
    flash[:address_validation_error].blank?
  end

  sig { returns(T::Boolean) }
  def completed_billing_and_shipping_information?
    return false unless completed_billing_information?
    this_business.shipping_contact.persisted?
  end

  sig { returns(T::Hash[Symbol, T.any(String, Symbol)]) }
  def trade_screening_error_data
    helpers.trade_screening_cannot_proceed_error_data(target: this_business)
  end

  sig { returns(T::Boolean) }
  def can_initiate_copilot_trial_activation?
    return false unless completed_billing_and_shipping_information?
    return false unless trade_screening_error_data.empty?
    this_business.has_valid_payment_method?
  end

  sig { returns(String) }
  def next_path
    if AzureEXP::Experiments.enterprise_onboarding_org_create?(current_user) && this_business.organizations.blank?
      new_enterprise_onboarding_organization_path(this_business)
    else
      enterprise_getting_started_path(this_business)
    end
  end
end
