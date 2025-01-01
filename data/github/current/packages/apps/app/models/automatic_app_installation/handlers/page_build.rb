# typed: true
# frozen_string_literal: true

class AutomaticAppInstallation
  module Handlers
    class PageBuild < BaseHandler

      # Automatic App Installation Handler for the :page_build event.
      #
      # # Arguments:
      # install_triggers - the install_triggers registered for this event.
      # actor - the repository to install app(s) on.
      # originator - the options argument to later be passed to the
      #   `after_integration_installed` class method.
      #
      # # Example usage:
      # ```
      # AutomaticAppInstallation.trigger(
      #   type: :page_build,
      #   originator: {
      #     page_id: page.id,
      #     pusher_id: pusher.id,
      #     git_ref_name: git_ref_name
      #   },
      #   actor: repository
      # )
      # ```
      sig { returns(T::Hash[Symbol, T.any(Integer, String)]) }
      def options
        originator
      end

      sig { returns(T.nilable(Repository)) }
      def repository
        actor
      end

      # Private: Starts `InstallAutomaticIntegrationsJob` for each install trigger.
      def install_integration
        return false unless should_install?

        install_triggers.each do |install_trigger|
          # enqueue background job to install it
          target_id = T.must(repository).owner_id
          integration_id = install_trigger.integration.id

          InstallAutomaticIntegrationsJob.perform_later(
            target_id,
            integration_id,
            install_trigger.id,
            [T.must(repository).id],
            options.merge(
              {
                "enqueued_timestamp" => Time.now.to_i,
                :entry_point => :automatic_app_installation_handler_page_build
              }
            ),
          )
        end
      end

      # Private: After the integration is installed, this method starts a Page build job.
      #
      # It's worth noting that the symbols in the `options` hash get converted to strings
      # in serialization.
      #
      # Returns true if the job was successfully started.
      def self.after_integration_installed(integration: nil, installation: nil, target: nil, installer: nil, repositories: nil, options:)
        options = options.stringify_keys
        page = Page.find_by!(id: options["page_id"])
        pusher = User.find_by!(id: options["pusher_id"])

        git_ref_name = options["git_ref_name"]
        ActiveRecord::Base.connected_to(role: :writing) do
          page.publish(pusher, git_ref_name: git_ref_name)
        end
      rescue ActiveRecord::RecordNotFound => error
        Failbot.report!(error)
      end

      private

      def should_install?
        return false unless repository
        return false unless FeatureFlag.vexi.enabled?(:pages_github_app, repository, default: false)
        T.must(repository).has_gh_pages?
      end
    end
  end
end
