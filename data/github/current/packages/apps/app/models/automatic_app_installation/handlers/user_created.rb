# typed: true
# frozen_string_literal: true

class AutomaticAppInstallation
  module Handlers
    class UserCreated < BaseHandler
      def install_integration
        install_triggers.each do |install_trigger|
          # enqueue background job to install it
          target_id = originator.id
          integration_id = install_trigger.integration.id
          options = {
            "enqueued_timestamp" => Time.now.to_i,
            :entry_point => :automatic_app_installation_handler_user_created
          }

          InstallAutomaticIntegrationsJob.perform_later(
            target_id,
            integration_id,
            install_trigger.id,
            InstallAutomaticIntegrationsJob::INSTALL_ON_ALL_REPOS,
            options
          )
        end
      end
    end
  end
end
