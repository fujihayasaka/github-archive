# typed: true
# frozen_string_literal: true

module IntegrationInstallationsControllerStateHelper
  extend T::Helpers

  requires_ancestor { ApplicationController }

  def ensure_app_has_not_changed
    T.bind(self, T.any(IntegrationInstallationsController, IntegrationInstallationsControllerMethods))

    return unless current_integration.present? && params[:integration_fingerprint].present?
    if current_integration.fingerprint != params[:integration_fingerprint]
      flash[:warn] = "This App has changed since you last viewed it. Please review and try again."
      app_changed_since_last_viewed(params[:action])
    end
  end
end
