# typed: true
# frozen_string_literal: true

module Configurable
  module RestrictLegacyPersonalAccessTokens
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Kernel }

    KEY = "restrict_legacy_personal_access_tokens"

    ENABLE_INSTRUMENTATION_KEY  = "#{KEY}.enable"
    DISABLE_INSTRUMENTATION_KEY = "#{KEY}.disable"
    RESET_INSTRUMENTATION_KEY   = "#{KEY}.reset"

    ERROR_MESSAGE = "Your organization is not not permitted to enable this setting because your enterprise restricts access via personal access tokens (classic)."

    class ConfigurationError < StandardError; end

    def restrict_legacy_personal_access_tokens(actor:)
      if legacy_personal_access_tokens_permitted_policy?
        raise(ConfigurationError, ERROR_MESSAGE)
      end

      return unless config.enable!(KEY, actor)
      instrument_legacy_pat_restricted(actor)
    end

    def permit_legacy_personal_access_tokens(actor:)
      if legacy_personal_access_tokens_restricted_policy?
        raise(ConfigurationError, ERROR_MESSAGE)
      end

      return unless config.disable!(KEY, actor)
      instrument_legacy_pat_permitted(actor)
    end

    def reset_legacy_personal_access_tokens_restriction(actor:)
      return unless config.delete(KEY, actor)
      instrument_legacy_pat_restriction_reset(actor)
    end

    def legacy_personal_access_tokens_restricted?
      config.enabled?(KEY)
    end

    def legacy_personal_access_tokens_delegated_policy?
      return config.get(KEY).nil? if instance_of?(Business)
      return true if instance_of?(Organization) && !configuration_owner.instance_of?(Business)

      configuration_owner.config.get(KEY).nil?
    end

    def legacy_personal_access_tokens_permitted_policy?
      config.get(KEY) == false && config.inherited?(KEY)
    end

    def legacy_personal_access_tokens_restricted_policy?
      legacy_personal_access_tokens_restricted? && config.inherited?(KEY)
    end

    private

    def instrument_legacy_pat_restricted(actor)
      payload = restrict_legacy_pat_payload(actor)

      GitHub.instrument(ENABLE_INSTRUMENTATION_KEY, payload)
      GlobalInstrumenter.instrument(ENABLE_INSTRUMENTATION_KEY, payload)
    end

    def instrument_legacy_pat_permitted(actor)
      payload = restrict_legacy_pat_payload(actor)

      GitHub.instrument(DISABLE_INSTRUMENTATION_KEY, payload)
      GlobalInstrumenter.instrument(DISABLE_INSTRUMENTATION_KEY, payload)
    end

    def instrument_legacy_pat_restriction_reset(actor)
      payload = restrict_legacy_pat_payload(actor)

      GitHub.instrument(RESET_INSTRUMENTATION_KEY, payload)
      GlobalInstrumenter.instrument(RESET_INSTRUMENTATION_KEY, payload)
    end

    def restrict_legacy_pat_payload(actor)
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
