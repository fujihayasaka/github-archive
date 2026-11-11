# typed: true
# frozen_string_literal: true

class AutomaticAppInstallation
  module Handlers
    class DependencyGraphInitialized < BaseHandler
      # Automatic App Installation Handler for the :dependency_graph_initialized event.
      #
      # # Arguments:
      # install_triggers - the set of IntegrationInstallTriggers registered for this event.
      # originator - the repository to install on.
      # actor - not used, but passed for API parity
      #
      # # Example usage:
      # ```
      # AutomaticAppInstallation.trigger(
      #   type: :dependency_graph_initialized,
      #   originator: repository,
      #   actor: repository.owner
      # )
      alias repository originator

      def originator; super; end

      def install_integration
        install_triggers.each do |install_trigger|
          target_id = repository.owner_id
          integration_id = install_trigger.integration.id
          options = {
            "enqueued_timestamp" => Time.now.to_i,
            :entry_point => :automatic_app_installation_handler_dependency_graph_initialized
          }

          # Dependabot installs as part of Dependency Graph initialization should
          # be performed as mass installs so they do not impact the primary queue
          # that serves user requests.
          MassInstallAutomaticIntegrationsJob.perform_later(
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
          # Dependabot installation takes place after manifest detection, so we need to invoke
          # Security Alerts next in order to generate alerts.
          #
          # This job calls back to Dependabot to build PRs for any alerts it creates.
          UpdateRepositoryVulnerabilityAlertsJob.enqueue_for_repository(
            repository,
            reason: :on_initialize,
            # Since this handler only gets called on installation we force `reason: :on_initialize` for the
            # RepoVulnAlerter.
          )
        end
      end
    end
  end
end
