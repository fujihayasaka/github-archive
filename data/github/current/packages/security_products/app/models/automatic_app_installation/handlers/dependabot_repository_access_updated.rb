# typed: true
# frozen_string_literal: true

class AutomaticAppInstallation
  module Handlers
    class DependabotRepositoryAccessUpdated < BaseHandler
      # Automatic App Installation Handler for the :dependabot_repository_access_updated event.
      #
      # Arguments:
      # install_triggers - the install_triggers registered for this event
      # actor            - the user that updated Dependabot's repository access
      # originator       - the Hash identifying the target and the accessible repositories
      #                    :target_id      - The integer org ID for the org
      #                                      whose repository access is being
      #                                      updated.
      #                    :repository_ids - The Array of integer repository IDs
      #                                      identifying the repositories to
      #                                      append to the target's Dependabot
      #                                      installation.
      def install_integration
        install_triggers.each do |install_trigger|
          options = {
            "enqueued_timestamp" =>  Time.now.to_i,
            :entry_point => :automatic_app_installation_handler_dependabot_repository_access_updated
          }

          target_id = originator.fetch(:target_id)
          repository_ids = originator.fetch(:repository_ids, InstallAutomaticIntegrationsJob::INSTALL_ON_ALL_REPOS)

          InstallAutomaticIntegrationsJob.perform_later(
            target_id,
            install_trigger.integration_id,
            install_trigger.id,
            repository_ids,
            options,
          )
        end
      end
    end
  end
end
