# typed: true
# frozen_string_literal: true

module Configurable
  module RestrictPersonalAccessTokens
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Kernel }

    KEY = "restrict_personal_access_tokens"

    ENABLE_INSTRUMENTATION_KEY  = "#{KEY}.enable"
    DISABLE_INSTRUMENTATION_KEY = "#{KEY}.disable"
    RESET_INSTRUMENTATION_KEY = "#{KEY}.reset"

    ALLOWED_ERROR_MESSAGE = "Your organization is not permitted to enable fine-grained personal access tokens because your enterprise restricts access."
    ORG_DENY_ERROR_MESSAGE    = "Your organization is not permitted to disable fine-grained personal access tokens because your enterprise enforces access."

    class ConfigurationError < StandardError; end

    def permit_personal_access_tokens(actor:)
      # Do not let orgs enable PATs when the enterprise has restricted them.
      if personal_access_tokens_restricted_policy?
        raise(ConfigurationError, ALLOWED_ERROR_MESSAGE)
      end

      return unless config.disable!(KEY, actor)
      instrument_pat_enablement(actor)
    end

    def restrict_personal_access_tokens(actor:)
      if personal_access_tokens_enforced_policy?
        raise(ConfigurationError, ORG_DENY_ERROR_MESSAGE)
      end

      return unless config.enable!(KEY, actor)
      instrument_pat_rejection(actor)
    end

    def reset_personal_access_tokens_restriction(actor:)
      return unless config.delete(KEY, actor)
      instrument_pat_rejection_reset(actor)
    end

    def personal_access_tokens_restricted?
      config.enabled?(KEY)
    end

    def personal_access_tokens_allowed?
      !personal_access_tokens_restricted?
    end

    def personal_access_tokens_delegated_policy?
      return config.get(KEY).nil? if instance_of?(Business)
      return true if instance_of?(Organization) && !configuration_owner.instance_of?(Business)

      configuration_owner.config.get(KEY).nil?
    end

    def personal_access_tokens_restricted_policy?
      personal_access_tokens_restricted? && config.inherited?(KEY)
    end

    def personal_access_tokens_enforced_policy?
      config.get(KEY) == false && config.inherited?(KEY)
    end

    private

    def instrument_pat_enablement(actor)
      payload = pat_instrumentation_payload(actor)

      GitHub.instrument(ENABLE_INSTRUMENTATION_KEY, payload)
      GlobalInstrumenter.instrument(ENABLE_INSTRUMENTATION_KEY, payload)
    end

    def instrument_pat_rejection(actor)
      payload = pat_instrumentation_payload(actor)

      GitHub.instrument(DISABLE_INSTRUMENTATION_KEY, payload)
      GlobalInstrumenter.instrument(DISABLE_INSTRUMENTATION_KEY, payload)
    end

    def instrument_pat_rejection_reset(actor)
      payload = pat_instrumentation_payload(actor)

      GitHub.instrument(RESET_INSTRUMENTATION_KEY, payload)
      GlobalInstrumenter.instrument(RESET_INSTRUMENTATION_KEY, payload)
    end

    def pat_instrumentation_payload(actor)
      payload = { user: actor }

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
