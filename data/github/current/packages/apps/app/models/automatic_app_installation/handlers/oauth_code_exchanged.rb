# typed: true
# frozen_string_literal: true

class AutomaticAppInstallation
  module Handlers
    class OauthCodeExchanged < BaseHandler
      extend T::Sig
      # Automatic App Installation Handler for the :oauth_code_exchanged event.
      #
      # Arguments:
      # install_triggers - the install_triggers registered for this event.
      # actor - the user for whom the integrator is exchanging a code for
      # originator - the GitHub App
      sig { returns(Integration) }
      def integration
        originator
      end

      def install_integration
        install_triggers.each do |install_trigger|
          options = {
            "enqueued_timestamp" =>  Time.now.to_i,
            :entry_point => :automatic_app_installation_handler_oauth_code_exchanged
          }
          next if install_trigger.integration_id != integration.id

          InstallAutomaticIntegrationsJob.perform_later(
            actor.id,
            install_trigger.integration_id,
            install_trigger.id,
            [],
            options,
          )
        end
      end
    end
  end
end
