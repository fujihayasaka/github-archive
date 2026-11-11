# typed: true
# frozen_string_literal: true

class AutomaticAppInstallation
  module Handlers
    class PendingDependabotInstallationRequested < BaseHandler
      # Automatic App Installation Handler for the :pending_dependabot_installation_requested event.
      #
      # Arguments:
      # install_triggers - the install_triggers registered for this event.
      # actor - the pending automatic installation instance
      # originator - the pending automatic installation instance
      alias pending_installation originator

      def originator; super; end

      def install_integration
        return false unless should_install?

        install_triggers.each do |install_trigger|
          options = {
            "pending_automatic_installation_id" => pending_installation.id,
            "enqueued_timestamp" =>  Time.now.to_i,
            :entry_point => :automatic_app_installation_handler_pending_dependabot_installation_requested
          }

          MassInstallAutomaticIntegrationsJob.perform_later(
            pending_installation.targeted_user.id,
            install_trigger.integration.id,
            install_trigger.id,
            pending_installation.targeted_repository_ids,
            options,
          )
        end
      end

      # before installation job hook
      def self.should_install?(integration:, target:, repositories:, options:)
        return unless repositories.present?
        # on this callback we always expect one repo
        return if Dependabot::AutomaticInstallationCheck.new(repositories.first).should_install?
        pending_installation = PendingAutomaticInstallation.find(options["pending_automatic_installation_id"])
        ActiveRecord::Base.connected_to(role: :writing) { pending_installation.update(status: :failed, reason: :canceled) }
        false
      end

      # post installation job hook
      def self.after_integration_installed(integration: nil, installation: nil, target: nil, installer: nil, repositories: nil, options:)
        pending_installation = PendingAutomaticInstallation.find(options["pending_automatic_installation_id"])
        ActiveRecord::Base.connected_to(role: :writing) { pending_installation.installed! }
      end

      private

      def should_install?
        pending_installation.pending?
      end
    end
  end
end
