# typed: true
# frozen_string_literal: true

class AutomaticAppInstallation
  module Handlers
    class DependencyUpdateRequested < BaseHandler
      # Automatic App Installation Handler for the :dependency_update_requested event.
      #
      # This event is fired when a user requests that Dependabot attempts to fix a
      # vulnerability/stale dependency on repository that does not yet have an install.
      #
      # # Arguments:
      # install_triggers - the set of IntegrationInstallTriggers registered for this event.
      # originator - the RepositoryDependencyUpdate object that event relates to.
      # actor - the repository to install on.
      #
      # # Example usage:
      # ```
      # AutomaticAppInstallation.trigger(
      #   type: :dependency_update_requested,
      #   originator: dependency_update,
      #   actor: repository,
      # )
      alias repository actor
      alias dependency_update originator

      def actor; super; end
      def originator; super; end

      def install_integration
        install_triggers.each do |install_trigger|
          target_id = repository.owner_id
          integration_id = install_trigger.integration.id
          options = {
            "dependency_update_id" => dependency_update.id,
            "enqueued_timestamp" =>  Time.now.to_i,
            :entry_point => :automatic_app_installation_handler_dependency_update_requested
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

        emit_dependency_update(options["dependency_update_id"], installation.id)
      end

      def self.integration_already_installed(integration:, installation:, target:, installer:, repositories:, options: {})
        return unless integration.dependabot_github_app?

        emit_dependency_update(options["dependency_update_id"], installation.id)
      end

      private_class_method def self.emit_dependency_update(dependency_update_id, installation_id)
        return unless dependency_update_id

        dependency_update = RepositoryDependencyUpdate.find_by(id: dependency_update_id)
        T.must(dependency_update).enqueue_vulnerability_update_in_hydro(dependabot_install_id: installation_id)
      end
    end
  end
end
