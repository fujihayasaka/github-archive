# typed: strict
# frozen_string_literal: true

# Manage whether Copilot coding agent is allowed to be used in repositories owned by a business.
module Configurable
  module SweAgentRepositoryAccess
    extend T::Helpers

    requires_ancestor { ApplicationRecord::Base }

    KEY = "swe_agent_repository_access"

    sig { params(actor: User).void }
    def enable_swe_agent_repository_access(actor:)
      raise ArgumentError, "swe_agent_repository_access can only be configured on a Business" unless is_a?(Business)
      T.bind(self, Business)

      # Delete the config to enable access, as the config is enabled when the user blocks access
      changed = config.delete(KEY, actor)
      return unless changed

      GitHub.dogstats.increment("swe_agent_repository_access.enable")
      GitHub.instrument(
          "swe_agent_repository_access.enable",
          { user: actor, business: self })
    end

    sig { params(actor: User, force: T::Boolean).void }
    def disable_swe_agent_repository_access(actor:, force: false)
      raise ArgumentError, "swe_agent_repository_access can only be configured on a Business" unless is_a?(Business)
      T.bind(self, Business)

      # Enable the config to block access, as the config is enabled when the user blocks access
      changed = config.enable!(KEY, actor, force)
      return unless changed

      GitHub.dogstats.increment("swe_agent_repository_access.disable")
      GitHub.instrument(
          "swe_agent_repository_access.disable",
          { user: actor, business: self })
    end

    sig { returns(T::Boolean) }
    def swe_agent_repository_access_enabled?
      T.bind(self, Configurable)

      # We _don't_ want the config to be enabled because if it is, that means the user has blocked access
      !config.enabled?(KEY)
    end
  end
end
