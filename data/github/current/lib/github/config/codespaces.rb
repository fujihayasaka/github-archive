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
      def codespaces_enabled?
        return false if GitHub.enterprise?
        return true if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
        return false if GitHub.multi_tenant_enterprise? && !FeatureFlag.vexi.enabled?(:codespaces_proxima_enablement, default: false)
        true
      end

      def codespaces_web_portal_second_level_domain
        "github"
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
