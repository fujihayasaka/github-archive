# typed: true
# frozen_string_literal: true

class AutomaticAppInstallation
  module Handlers
    class AutomaticSecurityUpdatesInitialized < BaseHandler
      alias :repository :originator

      def originator; super; end

      # Automatic App Installation Handler for the :automatic_security_updates_initialized event.
      #
      # # Arguments:
      # install_triggers - the set of IntegrationInstallTriggers registered for this event.
      # originator - the repository to install on.
      # actor - not used, but passed for API parity
      #
      # # Example usage:
      # ```
      # AutomaticAppInstallation.trigger(
      #   type: :automatic_security_updates_initialized,
      #   originator: repository,
      #   actor: repository.owner
      # )
      def install_integration
        install_triggers.each do |install_trigger|
          target_id = repository.owner_id
          integration_id = install_trigger.integration.id
          options = {
            "enqueued_timestamp" => Time.now.to_i,
            :entry_point => :automatic_app_installation_handler_security_updates_initialized
          }

          InstallAutomaticIntegrationsJob.perform_later(
            target_id,
            integration_id,
            install_trigger.id,
            [repository.id],
            options,
          )
        end
      end

      def self.after_integration_installed(integration:, installation:, target:, installer:, repositories:, options: {})
        return unless integration.dependabot_github_app?

        repositories.each do |repository|
          Dependabot::RepositoryEnrollJob.enqueue(repository)
        end
      end
    end
  end
end
