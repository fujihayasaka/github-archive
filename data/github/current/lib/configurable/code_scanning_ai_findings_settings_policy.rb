# typed: true
# frozen_string_literal: true

module Configurable
  module CodeScanningAiFindingsSettingsPolicy
    extend T::Helpers

    requires_ancestor { Object }
    requires_ancestor { Configurable }

    include Instrumentation::Model

    ALLOWED_POLICY_VALUE = "allowed"
    DISALLOWED_POLICY_VALUE = "disallowed"

    CODE_SCANNING_AI_FINDINGS_ALLOW_POLICY_KEY = "code_scanning_ai_findings.allow_policy"

    def allow_code_scanning_ai_findings_policy(actor:)
      changed = config.set(CODE_SCANNING_AI_FINDINGS_ALLOW_POLICY_KEY, ALLOWED_POLICY_VALUE, actor)
      instrument_code_scanning_ai_findings_settings(new_policy: ALLOWED_POLICY_VALUE, actor: actor) if changed
    end

    def disallow_code_scanning_ai_findings_policy(actor:)
      changed = config.set(CODE_SCANNING_AI_FINDINGS_ALLOW_POLICY_KEY, DISALLOWED_POLICY_VALUE, actor)
      instrument_code_scanning_ai_findings_settings(new_policy: DISALLOWED_POLICY_VALUE, actor: actor) if changed
    end

    sig { returns(T::Boolean) }
    def code_scanning_ai_findings_policy_allowed?
      return false if GitHub.enterprise?

      found_policy = config.get(CODE_SCANNING_AI_FINDINGS_ALLOW_POLICY_KEY)
      return false if is_a?(Business) && found_policy.nil?

      found_policy != DISALLOWED_POLICY_VALUE
    end

    private

    def instrument_code_scanning_ai_findings_settings(new_policy:, actor:)
      instrument "code_scanning_ai_findings_policy_update", new_policy: new_policy, actor: actor
    end
  end
end
