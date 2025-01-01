# typed: true
# frozen_string_literal: true

class Copilot::Signup::BaseController < ApplicationController
  include Site::PreserveTrackingParamsDependency
  include Billing::CopilotIapSubscription

  before_action :restrict_in_app_purchase_access
  before_action :restrict_enterprise_access
  before_action :restrict_multi_tenant_access
  before_action :check_copilot_administrative_block

  layout "enterprise_funnel"

  stylesheet_bundle :copilot
  javascript_bundle :copilot

  UTM_PARAMS = [:utm_source, :utm_medium, :utm_campaign, :utm_term, :utm_content].freeze

  private

  # Check if the user has any active in-app purchases and, if they do, then redirect them to the Copilot
  # settings page. We do not want to allow users who purchased Copilot via a mobile storefront to upgrade or
  # perform _any_ subscription management actions via the web. These users must use their mobile storefront
  # accounts to manage their subscriptions.
  sig { void }
  def restrict_in_app_purchase_access
    return unless logged_in?
    return unless current_user.feature_flag_enabled?(:copilot_in_app_purchase_web_suppression, default: false)
    return unless copilot_iap_subscription?(current_user)

    flash[:error] = simple_copilot_management_message(current_user)
    redirect_to "/settings/copilot"
  end

  sig { returns(ActionController::Parameters) }
  def signup_params
    params.permit(
      :authenticity_token, :_method,
      :payment_duration, :premium_requests, :cft,
      :return_to_path, :success_path,
      *UTM_PARAMS,
      user_contact_info: [:first_name, :last_name, :email, :country, :marketing_consent]
    )
  end

  sig { void }
  def add_paypal_csp_exceptions
    paypal_csp_exceptions = {
      img_src: [GitHub.paypal_checkout_url],
      connect_src: [GitHub.braintreegateway_url, GitHub.braintree_analytics_url]
    }
    SecureHeaders.append_content_security_policy_directives(request, paypal_csp_exceptions)
  end

  sig { returns(Copilot::User) }
  memoize def copilot_user
    T.must_because(current_copilot_user) { "#login_required ensures non-nil" }
  end

  sig { void }
  def restrict_enterprise_access
    # If a user is on an enterprise subscription, redirect them to the Copilot settings page
    if logged_in? && copilot_user.orgs_using_copilot_for_business.any?
      redirect_to "/settings/copilot"
    end
  end

  sig { void }
  def restrict_multi_tenant_access
    # If a user is on a multi-tenant instance, redirect them to the Copilot settings page
    redirect_to "/settings/copilot" if GitHub.multi_tenant_enterprise?
  end

  sig { void }
  def check_copilot_administrative_block
    if logged_in? && copilot_user.administrative_blocked?
      flash[:error] = "Your account is unable to upgrade Copilot. Please contact Support"
      redirect_to preserve_tracking_params_path(copilot_signup_path(context: "administrative_block"))
    end
  end

  def preserve_tracking_params_path(to_path, additional_params = {})
    super(to_path, editor_utm_params.merge(additional_params))
  end

  sig { returns(T::Hash[Symbol, String]) }
  def utm_query_params
    tracked_utm_params.merge(editor_utm_params)
  end

  sig { returns(T::Hash[Symbol, String]) }
  def editor_utm_params
    return {} unless override_utm_for_editor?
    { utm_source: params[:editor], utm_medium: "editor" }
  end

  sig { returns(T::Boolean) }
  def override_utm_for_editor?
    return false if params.key?(:utm_source) || params.key?(:utm_medium)
    request.query_parameters[:editor].present?
  end

  sig { returns(T.any(Symbol, Object)) }
  def target_for_conditional_access
    # This is safe due to :login_required
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  sig { returns(T.any(Copilot::Signup::BaseController, User)) }
  def resource_for_conditional_access
    return self unless logged_in?
    current_user
  end

  sig { void }
  def restrict_emu_access
    redirect_to "/settings/copilot" if copilot_user.is_enterprise_managed?
  end
end
