# typed: strict
# frozen_string_literal: true

# Whether a customer has configured GitHub Code Quality to be
# enabled on (existing and future) repos created in this org.
module Configurable
  module CodeQualityNewRepos
    extend T::Helpers

    class ConfigurationError < StandardError; end

    NEW_REPOS_ENABLED_KEY = T.let("code_quality.new_repos".freeze, String)

    requires_ancestor { Configurable }
    requires_ancestor { Instrumentation::Model }

    sig { params(actor: T.nilable(User)).void }
    def enable_code_quality_on_new_repos(actor:)
      T.bind(self, T.any(User, Organization))

      raise ConfigurationError, "Code Quality org settings feature flag is not enabled for this organization" unless is_code_quality_org_settings_ff_enabled_for_org?

      changed = config.enable(NEW_REPOS_ENABLED_KEY, actor)
      instrument_code_quality_new_repos(new_policy: "enabled", actor: actor) if changed
    end

    sig { params(actor: T.nilable(User)).void }
    def disable_code_quality_on_new_repos(actor:)
      T.bind(self, T.any(User, Organization))

      raise ConfigurationError, "Code Quality org settings feature flag is not enabled for this organization" unless is_code_quality_org_settings_ff_enabled_for_org?

      changed = config.delete(NEW_REPOS_ENABLED_KEY, actor)
      instrument_code_quality_new_repos(new_policy: "disabled", actor: actor) if changed
    end

    sig { returns(T::Boolean) }
    def code_quality_enabled_on_new_repos?
      T.bind(self, T.any(User, Organization))

      return false unless self.organization?

      is_code_quality_org_settings_ff_enabled_for_org? && config.enabled?(NEW_REPOS_ENABLED_KEY)
    end

    private

    sig { params(new_policy: String, actor: T.nilable(User)).void }
    def instrument_code_quality_new_repos(new_policy:, actor:)
      instrument "code_quality_new_repos", new_policy: new_policy, actor: actor
    end

    sig { returns(T::Boolean) }
    def is_code_quality_org_settings_ff_enabled_for_org?
      T.bind(self, T.any(User, Organization))

      FeatureFlag.vexi.enabled?(:code_quality_org_settings, self, default: false)
    end
  end
end
