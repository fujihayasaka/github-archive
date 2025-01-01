# typed: true
# frozen_string_literal: true

class AutomaticAppInstallation
  module Handlers
    # Automatic App Installation Handler for the :dependabot_jit_access_requested event.
    class DependabotJitAccessRequested < BaseHandler
      def install_integration
        install_triggers.flat_map do |install_trigger|
          options = {
            "enqueued_timestamp" =>  Time.now.to_i,
            :entry_point => :automatic_app_installation_handler_dependabot_jit_access_requested
          }

          target_id = originator.fetch(:target_id, nil)
          repository_id = originator.fetch(:repository_id, nil)

          result = InstallAutomaticIntegrationsJob.perform_now(
            target_id,
            install_trigger.integration_id,
            install_trigger.id,
            [repository_id],
            options,
          )

          if result.is_a?(Exception)
            raise result
          elsif result.success?
            Result.success(installation_result: result)
          else
            Result.failure(reason: result.reason, installation_result: result)
          end
        end
      end
    end
  end
end
