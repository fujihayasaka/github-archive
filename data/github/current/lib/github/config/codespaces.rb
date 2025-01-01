# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    # Mixin for the GitHub module that contains all configuration settings
    # related to Codespaces installations.
    module Codespaces
      # Public: checks if runtime environment is codespaces within development
      #
      # Returns a Boolean
      def codespaces?
        !!(Rails.env.development? && ENV["CODESPACES"])
      end

      # Codespaces is not enabled in GHES
      # Codespaces is always enabled in tests, so that we continue to test Proxima scenarios
      # But we're temporarily pausing support for Proxima, so hide Codespaces from Proxima customers
      def codespaces_enabled?
        return false if GitHub.enterprise?
        return true if Rails.env.test?  # rubocop:disable GitHub/DoNotBranchOnRailsEnv
        !GitHub.multi_tenant_enterprise?
      end

      def codespaces_web_portal_second_level_domain
        tenant = GitHub::CurrentTenant.get
        return "github" unless tenant.present?

        "#{tenant.slug}.ghe"
      end

      def codespaces_monolith_host_name
        if Rails.env.development? && ENV["NGROK_HOSTNAME"].present?
          ENV["NGROK_HOSTNAME"]
        else
          if GitHub.multi_tenant_enterprise?
            GitHub.host_name_with_tenant
          else
            GitHub.host_name
          end
        end
      end
    end
  end

  extend Config::Codespaces
end
