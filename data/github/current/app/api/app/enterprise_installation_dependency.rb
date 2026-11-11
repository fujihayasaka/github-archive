# typed: true
# frozen_string_literal: true

module Api::App::EnterpriseInstallationDependency
  extend T::Helpers
  requires_ancestor { Api::App }

  def require_enterprise_installation!
    return if current_enterprise_installation
    if enterprise_installation_token
      deliver_error! 403, message: "Invalid Enterprise token."
    else
      deliver_error! 404
    end
  end

  # Public: Fetches the enterprise installation for the current request.
  #
  # Returns either a EnterpriseInstallation or nil.
  def current_enterprise_installation
    return nil if GitHub.enterprise?
    return @current_enterprise_installation if defined?(@current_enterprise_installation)

    @current_enterprise_installation = if current_integration
      EnterpriseInstallation.for_github_app(current_integration)
    else
      nil
    end
  end

  attr_writer :current_enterprise_installation

  def enterprise_installation_token
    request.env["HTTP_X_GITHUB_ENTERPRISE_TOKEN"]
  end
end
