# typed: true
# frozen_string_literal: true

class Copilot::Signup::SparkProController < Copilot::Signup::BaseController
  before_action :spark_pro_activation_flow_enabled?
  before_action :login_required, except: [:index]
  before_action :restrict_emu_access, except: [:index]
  before_action :check_for_active_copilot_pro_or_pro_plus_subscription, only: [:new]

  before_action only: [:new] do
    T.bind(self, Copilot::Signup::SparkProController)
    check_trade_compliance(target: current_user)
  end

  before_action :add_paypal_csp_exceptions, only: [:new]

  include Site::MicrosoftAnalyticsDependency
  before_action :allow_initial_cookie_consent, only: [:index]
  before_action :enable_microsoft_analytics, only: [:index, :new]
  before_action :add_microsoft_analytics_csp_exceptions, only: [:index, :new]

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
    ApplicationRecord::Configurations,
    only: [:index, :new]

  def index
    copilot_user_or_nil = logged_in? ? copilot_user : nil

    Copilot::Instrumenter.instrument_page_view(
      Copilot::Events::COPILOT_SPARK_PRO_PAGE_VIEW,
      copilot_user_or_nil,
      utm_query_params: utm_query_params
    )

    context_region_title "Spark"

    render "copilot/pro/spark/index", locals: {
      form_submit_path: preserve_tracking_params_path(spark_pro_signup_new_path),
      payment_duration: signup_params[:payment_duration] || "monthly",
      tracking_params: tracking_params,
      copilot_user: copilot_user_or_nil,
    }, formats: :html
  end

  def new
    Copilot::Instrumenter.instrument_page_view(
      Copilot::Events::COPILOT_SPARK_PRO_SIGNUP_PAGE_VIEW,
      copilot_user,
      utm_query_params: utm_query_params
    )

    context_region_title "Spark checkout"

    render "copilot/pro/spark/new", locals: {
      payment_duration: signup_params[:payment_duration] || "monthly",
      premium_requests: signup_params[:premium_requests],
      return_to_path: preserve_tracking_params_path(spark_pro_signup_new_path, signup_params),
      update_path: preserve_tracking_params_path(spark_pro_signup_update_path),
      subscribe_path: preserve_tracking_params_path(copilot_pro_signup_create_path),
      success_path: preserve_tracking_params_path(spark_dashboard_path),
      tracking_params: tracking_params,
      copilot_user: copilot_user,
    }, formats: :html
  end

  sig { void }
  def update
    redirect_to preserve_tracking_params_path(spark_pro_signup_new_path, signup_params.slice(:payment_duration))
  end

  private

  def spark_pro_activation_flow_enabled?
    render_404 unless FeatureFlag.vexi.enabled?(:site_spark_pro_activation_flow, current_user, default: false)
  end

  sig { void }
  def check_for_active_copilot_pro_or_pro_plus_subscription
    return unless FeatureFlag.vexi.enabled_or_raise?(:site_copilot_signup_redirect_active_subscription, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    redirect_to spark_dashboard_path if copilot_user.has_pro_plus_access? || copilot_user.has_pro_access?
  end
end
