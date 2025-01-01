# typed: true
# frozen_string_literal: true

module Configurable
  module CodeScanningAutofixSettingsPolicy
    extend T::Helpers

    requires_ancestor { Configurable }

    include Instrumentation::Model

    ALLOWED_POLICY_VALUE = "allowed"
    DISALLOWED_POLICY_VALUE = "disallowed"

    CODE_SCANNING_AUTOFIX_ALLOW_POLICY_KEY = "code_scanning_autofix.allow_policy"

    def allow_code_scanning_autofix_policy(actor:)
      changed = config.delete(CODE_SCANNING_AUTOFIX_ALLOW_POLICY_KEY, actor)
      instrument_code_scanning_autofix_settings(new_policy: ALLOWED_POLICY_VALUE, actor: actor) if changed
    end

    def disallow_code_scanning_autofix_policy(actor:)
      changed = config.set(CODE_SCANNING_AUTOFIX_ALLOW_POLICY_KEY, DISALLOWED_POLICY_VALUE, actor)
      instrument_code_scanning_autofix_settings(new_policy: DISALLOWED_POLICY_VALUE, actor: actor) if changed
    end

    def code_scanning_autofix_policy_allowed?
      config.get(CODE_SCANNING_AUTOFIX_ALLOW_POLICY_KEY) != DISALLOWED_POLICY_VALUE
    end

    CODE_SCANNING_AUTOFIX_THIRD_PARTY_TOOLS_ALLOW_POLICY_KEY = "code_scanning_autofix_third_party_tools.allow_policy"

    def allow_code_scanning_autofix_third_party_tools_policy(actor:)
      changed = config.delete(CODE_SCANNING_AUTOFIX_THIRD_PARTY_TOOLS_ALLOW_POLICY_KEY, actor)
      instrument_code_scanning_autofix_third_party_tools_settings(new_policy: ALLOWED_POLICY_VALUE, actor: actor) if changed
    end

    def disallow_code_scanning_autofix_third_party_tools_policy(actor:)
      changed = config.set(CODE_SCANNING_AUTOFIX_THIRD_PARTY_TOOLS_ALLOW_POLICY_KEY, DISALLOWED_POLICY_VALUE, actor)
      instrument_code_scanning_autofix_third_party_tools_settings(new_policy: DISALLOWED_POLICY_VALUE, actor: actor) if changed
    end

    def code_scanning_autofix_third_party_tools_policy_allowed?
      config.get(CODE_SCANNING_AUTOFIX_THIRD_PARTY_TOOLS_ALLOW_POLICY_KEY) != DISALLOWED_POLICY_VALUE
    end

    private

    def instrument_code_scanning_autofix_settings(new_policy:, actor:)
      instrument "code_scanning_autofix_policy_update", new_policy: new_policy, actor: actor
    end

    def instrument_code_scanning_autofix_third_party_tools_settings(new_policy:, actor:)
      instrument "code_scanning_autofix_third_party_tools_policy_update", new_policy: new_policy, actor: actor
    end

  end
end
