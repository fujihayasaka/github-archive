# typed: true
# frozen_string_literal: true

module Configurable
  # Tracks which entities have opted into the use of fine-grained personal access tokens. Cannot be opted out of once opted in (but can be restricted by restrict_programmatic_access_tokens).
  # Note: differs from restrict_personal_access_tokens config - restriction is choosing not to grant PATs v2 access to resources, opting in is tracking engagement with the feature overall.
  module ProgrammaticAccessTokensOptIn
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Kernel }

    KEY = "programmatic_access_tokens_opt_in"
    OPT_IN_INSTRUMENTATION_KEY  = "#{KEY}.optin"

    class ConfigurationError < StandardError; end

    def opt_in_programmatic_access_tokens(actor:)
      return unless config.enable!(KEY, actor)
      instrument_opt_in_pat(actor)
    end

    def opted_in_programmatic_access_tokens?
      config.enabled?(KEY)
    end

    private

    def instrument_opt_in_pat(actor)
      payload = opt_pat_instrumentation_payload(actor)

      GitHub.instrument(OPT_IN_INSTRUMENTATION_KEY, payload)
      GlobalInstrumenter.instrument(OPT_IN_INSTRUMENTATION_KEY, payload)
    end

    def opt_pat_instrumentation_payload(actor)
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
