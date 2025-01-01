# typed: strict
# frozen_string_literal: true

class Copilot::ProPlusSignupController < ApplicationController
  before_action :check_copilot_pro_plus_feature_flag
  before_action :login_required, except: [:index]
  before_action :restrict_enterprise_access
  before_action :restrict_multi_tenant_access
  before_action :check_copilot_administrative_block

  before_action only: [:new] do
    T.bind(self, Copilot::ProPlusSignupController)
    check_trade_compliance(target: current_user)
  end

  before_action only: [:create] do
    T.bind(self, Copilot::ProPlusSignupController)
    check_trade_compliance(target: current_user, feature_type: :copilot, sdn_redirect: true)
  end

  before_action :add_paypal_csp_exceptions, only: [:new]

  include Site::PreserveTrackingParamsDependency
  include Site::MicrosoftAnalyticsDependency
  before_action :allow_initial_cookie_consent
  before_action :enable_microsoft_analytics
  before_action :add_microsoft_analytics_csp_exceptions

  layout "enterprise_funnel"

  stylesheet_bundle :copilot
  javascript_bundle :copilot
  javascript_bundle :billing, only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations

  UTM_PARAMS = T.let([:utm_source, :utm_medium, :utm_campaign, :utm_term, :utm_content].freeze, T::Array[Symbol])

  sig { void }
  def index
    copilot_user_or_nil = logged_in? ? copilot_user : nil

    # TODO: Instrumentation

    context_region_title "Copilot Pro+"

    render "copilot/pro_plus/index", locals: {
      form_submit_path: preserve_tracking_params_path(copilot_pro_plus_signup_new_path),
      payment_duration: signup_params[:payment_duration] || "monthly",
      tracking_params: tracking_params,
      copilot_user: copilot_user_or_nil,
    }, formats: :html
  end

  sig { void }
  def new
    if !pro_plus_signup_billing_valid?
      flash[:error] = "Missing required parameters"
      redirect_to preserve_tracking_params_path(copilot_signup_path)
      return
    end

    # TODO: Instrumentation

    context_region_title "Copilot Pro+ Checkout"

    render "copilot/pro_plus/new", locals: {
      payment_duration: signup_params[:payment_duration] || "monthly",
      return_to_path: preserve_tracking_params_path(copilot_pro_plus_signup_path, signup_params),
      subscribe_path: preserve_tracking_params_path(copilot_pro_plus_signup_create_path),
      tracking_params: tracking_params,
      copilot_user: copilot_user,
    }, formats: :html
  end

  sig { void }
  def create
    if !pro_plus_signup_billing_valid?
      flash[:error] = "Missing required parameters"
      redirect_to preserve_tracking_params_path(copilot_signup_path)
      return
    end

    duration = signup_params[:payment_duration] == "monthly" ? :month : :year

    url_options = { host: GitHub.admin_host_name, protocol: "https" }
    staff_url = stafftools_user_copilot_settings_url(current_user, **url_options)

    blocked = copilot_user.block_if_sharing_payment_method_with_other_blocked_users!

    if blocked
      copilot_user.send_abuse_notification(
        url: staff_url,
        is_trial_signup: false, # Pro+ doesn't offer trials
        duration: duration.to_s,
        signed_up: false,
      )
      flash[:error] = "Unable to sign up for Copilot"
      redirect_to preserve_tracking_params_path(copilot_signup_path)
      return
    end

    if copilot_user.shares_payment_method_with_blocked_user?
      copilot_user.send_abuse_notification(
        url: staff_url,
        is_trial_signup: false,
        duration: duration.to_s,
        signed_up: true,
      )
    end

    # If the user has limited access (free tier), remove their free access record
    Copilot::LimitedUser.find_by(user_id: copilot_user.id)&.destroy

    # Create Pro+ subscription
    # TODO Billing: https://github.com/github/billing-core/issues/890#issuecomment-2716930021
    # result = copilot_user.subscribe_pro_plus(duration)
    #
    # if !result.ok?
    #   flash[:error] = "There was an error processing your subscription"
    #   redirect_to preserve_tracking_params_path(copilot_signup_path)
    #   return
    # end

    flash[:notice] = "You've successfully upgraded to GitHub Copilot Pro+"
    redirect_to preserve_tracking_params_path(copilot_immersive_path)
  end

  private

  sig { void }
  def check_copilot_pro_plus_feature_flag
    redirect_to "/github-copilot/signup" unless feature_enabled_globally_or_for_current_user?(:copilot_pro_plus)
  end

  # TODO: rename to billing_valid to something? similar to signup#signup_billing_valid or just reuse it
  sig { returns(T::Boolean) }
  def pro_plus_signup_billing_valid?
    signup_params[:payment_duration] == "monthly" || signup_params[:payment_duration] == "yearly"
  end

  sig { returns(ActionController::Parameters) }
  def signup_params
    params.permit(
      :payment_duration, :authenticity_token,
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

  sig { void }
  def restrict_enterprise_access
    # If a user is on an enterprise subscription, redirect them to the Copilot settings page
    if logged_in? && copilot_user.orgs_using_copilot_for_business.any?
      redirect_to "/settings/copilot"
    end
  end

  sig { void }
  def check_copilot_administrative_block
    if logged_in? && copilot_user.administrative_blocked?
      flash[:error] = "Your account is unable to upgrade Copilot. Please contact Support"
      redirect_to preserve_tracking_params_path(copilot_signup_path(context: "administrative_block"))
    end
  end

  sig { void }
  def restrict_multi_tenant_access
    # If a user is on a multi-tenant instance, redirect them to the Copilot settings page
    redirect_to "/settings/copilot" if GitHub.multi_tenant_enterprise?
  end

  sig { returns(T.any(Symbol, Object)) }
  def target_for_conditional_access
    # This is safe due to :login_required
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  sig { returns(T.any(Copilot::ProPlusSignupController, User)) }
  def resource_for_conditional_access
    return self unless logged_in?
    current_user
  end
end
