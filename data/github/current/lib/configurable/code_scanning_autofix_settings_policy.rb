# typed: true
# frozen_string_literal: true

module Configurable
  module CodeScanningAutofixSettingsPolicy
    extend T::Helpers

    requires_ancestor { Configurable }

    include Instrumentation::Model

    CODE_SCANNING_AUTOFIX_ALLOW_POLICY_KEY = "code_scanning_autofix.allow_policy"
    CODE_SCANNING_AUTOFIX_DISALLOWED_POLICY_VALUE = "disallowed"

    def allow_code_scanning_autofix_policy(actor:)
      changed = config.delete(CODE_SCANNING_AUTOFIX_ALLOW_POLICY_KEY, actor)
      instrument_code_scanning_autofix_settings(new_policy: "allowed", actor: actor) if changed
    end

    def disallow_code_scanning_autofix_policy(actor:)
      changed = config.set(CODE_SCANNING_AUTOFIX_ALLOW_POLICY_KEY, CODE_SCANNING_AUTOFIX_DISALLOWED_POLICY_VALUE, actor)
      instrument_code_scanning_autofix_settings(new_policy: CODE_SCANNING_AUTOFIX_DISALLOWED_POLICY_VALUE, actor: actor) if changed
    end

    def code_scanning_autofix_policy_allowed?
      config.get(CODE_SCANNING_AUTOFIX_ALLOW_POLICY_KEY) != CODE_SCANNING_AUTOFIX_DISALLOWED_POLICY_VALUE
    end

    private

    def instrument_code_scanning_autofix_settings(new_policy:, actor:)
      instrument "code_scanning_autofix_policy_update", new_policy: new_policy, actor: actor
    end
  end
end
