# typed: true
# frozen_string_literal: true

class Api::Runtime::App < Api::App
  extend T::Helpers

  abstract!

  def find_runtime_app!
    app_name = params[:app]
    deliver_error!(404) unless app_name
    runtime_app = Spark::RuntimeApp.find_by(permanent_name: app_name)
    record_or_404 runtime_app
    check_github_token_access!(runtime_app)
    runtime_app
  end

  # Checks that the current GitHub token has access to the codespace
  # associated with the current Spark, to prevent cross-codespace access.
  def check_github_token_access!(runtime_app)
    return unless FeatureFlag.vexi.enabled?(:spark_map_github_token_to_spark_codespace, current_user, default: false)

    workbench = Spark::Workbench.find_by(runtime_app: runtime_app)

    # if no associated workbench, nothing to check
    if workbench.nil?
      return
    end

    installation = current_user.oauth_access&.installation
    if installation&.is_a?(SiteScopedIntegrationInstallation)
      unless installation.codespace_ids.include?(workbench.cloud_environment_id)
        deliver_error!(403, message: "This app does not belong to the current codespace")
      end
    end
  end
end
