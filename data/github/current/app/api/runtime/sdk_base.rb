# typed: true
# frozen_string_literal: true

# This should be used as the base class for our endpoints that are
# intended to be callable by the Spark SDK with ACA auth. All of them
# are expected to respond as well to standard GH auth.
class Api::Runtime::SdkBase < Api::App
  extend T::Helpers

  abstract!

  before do
    deliver_error!(404) unless current_user

    workbench_enabled = FeatureFlag.vexi.enabled?(:copilot_workbench, current_user, default: false)
    workbench_bypass_enabled = FeatureFlag.vexi.enabled?(:copilot_workbench_access_deployed_sparks, current_user, default: false)

    deliver_error!(404) unless workbench_enabled || workbench_bypass_enabled
  end

  before do
    verify_integration_access!
  end

  # Overrides default auth scheme to additionally support Spark-Bearer tokens
  def attempt_login
    attempt_login_from_spark
  end

  def verify_integration_access!
    checker = Api::Runtime::IntegrationChecker.new(
      current_user,
      current_integration,
      [:spark, :codespaces_production])

    return if checker.allowed?

    # Anything else is invalid, so let's error out
    deliver_error! 401, message: "Integration auth is not supported for this endpoint"
  end

  # Overrides default private mode authentication check so that
  # integrations can make authenticated requests
  def authenticated_for_private_mode?
    attempt_login_from_spark && current_user.present?
  end

  def find_runtime_app!
    app_name = params[:app]
    deliver_error!(404) unless app_name
    runtime_app = Spark::RuntimeApp.find_by(permanent_name: app_name)
    record_or_404 runtime_app
  end

  def app_user_display_login
    if @app_user
      @app_user
    else
      current_user.display_login
    end
  end
end
