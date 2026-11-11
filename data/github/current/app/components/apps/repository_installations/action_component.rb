# typed: strict
# frozen_string_literal: true

module Apps::RepositoryInstallations
  class ActionComponent < ApplicationComponent

    SUFFICIENT_ACCESS_TOOLTIP_MESSAGE = "You do not have sufficient access to configure this installation."

    sig { params(installation: IntegrationInstallation, result: IntegrationInstallation::Permissions::Result).void }
    def initialize(installation, result)
      @installation = installation
      @result = result
    end

    sig { returns(String) }
    def installation_settings_route
      return "#" unless @result.permitted?

      if @result.reason == :is_admin
        gh_settings_installation_path(@installation)
      else
        gh_edit_app_installation_path(@installation.integration, @installation, @result.actor)
      end
    end

    sig { returns(T::Boolean) }
    def permitted?
      @result.permitted?
    end

    sig { returns(String) }
    def tooltip_text
      SUFFICIENT_ACCESS_TOOLTIP_MESSAGE
    end
  end
end
