# frozen_string_literal: true

module HydroHandlers
  module GitHub
    class User
      USER_TYPES = {
        USER: "User",
        ORGANIZATION: "Organization",
      }.freeze

      PERMITTED_ATTRIBUTES = %i(
        id
        login
        type
      ).freeze

      attr_reader :id, :login, :type, :installation_id, :tenant_id, :tenant_slug

      def self.from_message(message)
        attributes = message.value.fetch(:owner).slice(*PERMITTED_ATTRIBUTES).tap do |a|
          a[:type] = USER_TYPES.fetch(a[:type])
          a[:tenant_id] = message.headers["X-GitHub-Tenant-ID"]
          a[:tenant_slug] = message.headers["X-GitHub-Tenant"]
        end

        return new(attributes, installation_id: nil) unless message.value.key?(:github_bot_install_id)

        installation_id = message.value.fetch(:github_bot_install_id).to_i
        new(attributes, installation_id: installation_id)
      end

      def initialize(attributes, installation_id:)
        @id = attributes.fetch(:id)
        @login = attributes.fetch(:login)
        @type = attributes.fetch(:type)
        @tenant_id = attributes.fetch(:tenant_id) { raise if Dependabot.proxima? }
        @tenant_slug = attributes.fetch(:tenant_slug) { raise if Dependabot.proxima? }

        @installation_id = installation_id
      end

      def attributes
        {
          id: @id,
          login: @login,
          type: @type,
          tenant_id: @tenant_id,
          tenant_slug: @tenant_slug,
        }.with_indifferent_access
      end

      # rubocop:disable Metrics/MethodLength
      def create_account!
        account = FindOrCreateAccount.new(
          github_account: attributes,
          repo_selection: "all",
          event_source: "hydro",
        ).run

        return account unless installation_id

        if account.active? && account.current_installation_id != installation_id
          Rails.logger.info "Dependabot installation ID changed from " \
                            "'#{account.current_installation_id}' to " \
                            "'#{installation_id}'"

          DeactivateAccount.new(
            account: account,
            installation_id: account.current_installation_id,
            sender: attributes,
            event_source: "hydro.github_job_ingestion"
          ).run
        end

        unless account.active?
          begin
            ActivateAccount.new(
              account: account,
              installation_id: installation_id,
              sender: attributes,
            ).run
          rescue Statesman::TransitionFailedError => e
            # It is possible for this activation to race if we ingest two jobs
            # that both attempt to activate the same account in parallel.
            raise unless e.message.include?("'active' to 'active'")
          end

          Rails.logger.info "Account activated, installation id was " \
                            "'#{account.last_transition&.installation_id}', " \
                            "now '#{installation_id}'"
        end

        account
      end
      # rubocop:enable Metrics/MethodLength

      def setup_account
        if onboard_with_global_app?
          SetupAccountWithGlobalApp.new(
            github_id: id,
            tenant_id: tenant_id,
            tenant_slug: tenant_slug,
            event_source: "hydro.vulnerability_alert",
          ).run
        else
          create_account!
        end
      end

      private

      def onboard_with_global_app?
        account = Account.find_by(github_id: id)

        if account.blank?
          Dependabot::Logger.warn(
            msg: "Account not found for existing repo",
            "code.namespace": self.class.name.to_s,
            "gh.owner.id": id,
          )

          return GitHubHelpers.onboard_account_with_global_app?(github_id: id)
        end

        account&.using_global_app? == true
      end
    end
  end
end
