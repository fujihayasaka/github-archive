# typed: true
# frozen_string_literal: true

class AutomaticAppInstallation
  module Handlers
    class ThirdPartyAgentsEnabled < BaseHandler
      alias integration originator
      alias target actor

      def actor
        super
      end

      def originator
        super
      end

      def install_integration
        install_triggers.each do |install_trigger|
          next unless install_trigger.integration_id == integration.id

          options = {
            "enqueued_timestamp" => Time.now.to_i,
            :entry_point => :automatic_app_installation_handler_third_party_agents_enabled,
          }

          InstallAutomaticIntegrationsJob.perform_later(
            target.id,
            install_trigger.integration.id,
            install_trigger.id,
            InstallAutomaticIntegrationsJob::INSTALL_ON_ALL_REPOS,
            options,
          )
        end
      end
    end
  end
end
