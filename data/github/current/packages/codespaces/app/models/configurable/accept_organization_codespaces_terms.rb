# typed: true
# frozen_string_literal: true

module Configurable
  module AcceptOrganizationCodespacesTerms
    extend T::Helpers
    extend Configurable::Async

    requires_ancestor { Configurable }
    requires_ancestor { Kernel }

    KEY = "organization_codespaces_terms.accepted"

    async_configurable :organization_codespaces_terms_accepted?
    def organization_codespaces_terms_accepted?
      config.enabled?(KEY)
    end

    # Accepts organization codespaces terms by ensuring the accepted key is present.
    def accept_organization_codespaces_terms(force = false, actor:)
      changed = config.enable!(KEY, actor, force)
      return unless changed

      GitHub.dogstats.increment("organization_codespaces_terms.accepted")
      GitHub.instrument(
        "organization_codespaces_terms.accepted",
        instrumentation_payload(actor))
    end

    # Clears the organization codespaces terms setting, removing any value from inheritance
    # hierarchy
    def clear_organization_codespaces_terms_setting(actor:)
      changed = config.delete(KEY, actor)
      return unless changed

      GitHub.dogstats.increment("organization_codespaces_terms.clear")
      GitHub.instrument(
        "organization_codespaces_terms.clear",
        instrumentation_payload(actor))
    end

    # Returns whether the configuration entry has a policy enforcement
    def organization_codespaces_terms_policy?
      !!config.final?(KEY)
    end

    private def instrumentation_payload(actor)
      payload = { user: actor }

      if self.is_a?(Organization)
        payload[:org] = self
        payload[:business] = self.business if self.business
      elsif self.is_a?(Business)
        payload[:business] = self
      end

      payload
    end
  end
end
