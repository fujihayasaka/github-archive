# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Pullsd
  module Shared
    # Shared module for finding an installation matching a given ID that belongs
    # to a bot's integration. Used by multiple pullsd Twirp handlers that need
    # to resolve scoped/site-scoped/regular installations for bot viewers.
    module InstallationFinder
      extend T::Helpers

      # Finds the installation matching the given ID that belongs to the bot's
      # integration. Uses installation_type to directly load the correct model,
      # matching the monolith REST API behavior where scoped tokens retain
      # their reduced permissions.
      #
      # Returns nil if installation_type is not provided or not recognized.
      sig do
        params(
          viewer: Bot,
          installation_id: Integer,
          installation_type: String,
        ).returns(T.nilable(T.any(ScopedIntegrationInstallation, SiteScopedIntegrationInstallation, IntegrationInstallation)))
      end
      def find_installation_for_bot(viewer, installation_id, installation_type)
        integration = viewer.integration
        return unless integration

        case installation_type
        when "ScopedIntegrationInstallation"
          scoped = ScopedIntegrationInstallation.find_by(id: installation_id)
          scoped if scoped && integration.installations.where(id: scoped.integration_installation_id).exists?
        when "SiteScopedIntegrationInstallation"
          SiteScopedIntegrationInstallation.find_by(id: installation_id, integration_id: integration.id)
        when "IntegrationInstallation"
          integration.installations.find_by(id: installation_id)
        end
      end
    end
  end
end
