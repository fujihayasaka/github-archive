# typed: true
# frozen_string_literal: true

class AutomaticAppInstallation
  module Handlers
    class ButtonClicked < BaseHandler

      # Automatic App Installation Handler for the :button_clicked event.
      #
      # Arguments:
      # install_triggers - the install_triggers registered for this event
      # actor - the repository to install on.
      # originator - the app to be installed
      alias integration originator
      alias repository actor

      def actor; super; end
      def originator; super; end

      def install_integration
        install_triggers.flat_map do |install_trigger|
          next unless install_trigger.integration_id == integration.id
          target_id = repository.owner_id

          options = {
            "enqueued_timestamp" =>  Time.now.to_i,
            :entry_point => :automatic_app_installation_handler_button_clicked
          }

          InstallAutomaticIntegrationsJob.perform_now(
            target_id,
            install_trigger.integration_id,
            install_trigger.id,
            [repository.id],
            options,
          )
        end
      end
    end
  end
end
