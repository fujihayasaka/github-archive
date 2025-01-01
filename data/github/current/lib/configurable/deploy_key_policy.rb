# typed: strict
# frozen_string_literal: true

module Configurable
  module DeployKeyPolicy
    extend T::Sig
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Object }

    KEY = T.let("deploy_key_policy".freeze, String)
    INSTRUMENT_DEPLOY_KEY_POLICY_ENABLED = T.let("#{KEY}.enabled", String)
    INSTRUMENT_DEPLOY_KEY_POLICY_DISABLED = T.let("#{KEY}.disabled", String)
    INSTRUMENT_DEPLOY_KEY_POLICY_UNSET = T.let("#{KEY}.unset", String)

    # Public: Enable the deploy key policy for this Organization or Business.
    sig { params(actor: User).void }
    def enable_deploy_key_policy(actor:)
      return unless can_set_deploy_key_policy?

      # If enabling for the organization, and the business has set a policy, do nothing.
      return if self.is_a?(Organization) && deploy_key_policy_inherited?

      # the third argument is the "final" attribute on the config, which is used to determine
      # which config value to use when there are multiple values set on the org and business
      # we set it to true for businesses so that it takes precedence over the org value
      return unless config.enable!(KEY, actor, self.is_a?(Business))
      instrument_deploy_key_policy_enabled(actor)
    end

    # Public: Disable the deploy key policy for this Organization or Business.
    sig { params(actor: User).void }
    def disable_deploy_key_policy(actor:)
      return unless can_set_deploy_key_policy?

      # If disabling for the organization, and the business has set a policy, do nothing.
      return if self.is_a?(Organization) && deploy_key_policy_inherited?

      # the third argument is the "final" attribute on the config, which is used to determine
      # which config value to use when there are multiple values set on the org and business
      # we set it to true for businesses so that it takes precedence over the org value
      return unless config.disable!(KEY, actor, self.is_a?(Business))
      instrument_deploy_key_policy_disabled(actor)
    end

    # Public: Unset the deploy key policy for this Organization or Business. Resolving in "no policy" defaults.
    sig { params(actor: User).void }
    def unset_deploy_key_policy(actor:)
      return unless can_set_deploy_key_policy?
      return unless config.delete(KEY, actor)
      instrument_deploy_key_policy_unset(actor)
    end

    # Public: Returns true if the deploy key policy is enabled for this Organization or Business.
    # The Business policy takes precedence over the Organization policy, if set.
    sig { returns(T::Boolean) }
    def deploy_key_policy_enabled?
      config.enabled?(KEY)
    end

    # Public: Returns true if the deploy key policy is enabled for this Organization or Business.
    # The Business policy takes precedence over the Organization policy, if set.
    # Important - this function is not intended to be used alone to determine if a deploy key can be used.
    # The policy defaults (i.e. no policy, unset, nil values) are not considered here and should be checked separately.
    sig { returns(T::Boolean) }
    def deploy_key_policy_disabled?
      config.get(KEY) == false
    end

    # Public: Returns true if the deploy key policy is not set for this Organization or Business.
    # This is the default state, meaning the policy has not been explicitly enabled or disabled by admins.
    sig { returns(T::Boolean) }
    def deploy_key_policy_unset?
      config.get(KEY).nil?
    end

    # Public: Returns true if the deploy key policy is inherited from the Business.
    sig { returns(T::Boolean) }
    def deploy_key_policy_inherited?
      !!config.inherited?(KEY)
    end

    private

    sig { returns(T::Boolean) }
    def can_set_deploy_key_policy?
      if self.is_a?(Organization)
        return self.feature_enabled?(:deploy_key_policy) || !!self.business&.feature_enabled?(:deploy_key_policy)
      end
      self.is_a?(Business) && self.feature_enabled?(:deploy_key_policy)
    end

    sig { params(actor: User).void }
    def instrument_deploy_key_policy_enabled(actor)
      payload = instrumentation_payload(actor)
      GitHub.instrument(INSTRUMENT_DEPLOY_KEY_POLICY_ENABLED, payload)
      GlobalInstrumenter.instrument(INSTRUMENT_DEPLOY_KEY_POLICY_ENABLED, payload)
    end

    sig { params(actor: User).void }
    def instrument_deploy_key_policy_disabled(actor)
      payload = instrumentation_payload(actor)
      GitHub.instrument(INSTRUMENT_DEPLOY_KEY_POLICY_DISABLED, payload)
      GlobalInstrumenter.instrument(INSTRUMENT_DEPLOY_KEY_POLICY_DISABLED, payload)
    end

    sig { params(actor: User).void }
    def instrument_deploy_key_policy_unset(actor)
      payload = instrumentation_payload(actor)
      GitHub.instrument(INSTRUMENT_DEPLOY_KEY_POLICY_UNSET, payload)
      GlobalInstrumenter.instrument(INSTRUMENT_DEPLOY_KEY_POLICY_UNSET, payload)
    end

    sig { params(actor: User).returns(T::Hash[Symbol, T.untyped]) }
    def instrumentation_payload(actor)
      payload = {
        user: actor
      }

      case self
      when ::Organization
        payload[:org] = self
        payload[:business] = self.business if self.business
      when ::Business
        payload[:business] = self
      end

      payload
    end
  end
end
