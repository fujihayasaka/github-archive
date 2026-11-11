# typed: strict
# frozen_string_literal: true

module RuleEngine
  class RulesetImplementationPayload < T::Struct
    const :ruleset_class, String
    const :rule_condition_class, String
    const :rule_configuration_class, String
    const :ruleset_history_class, String
    const :ruleset_bypass_actor_class, T.nilable(String)

    const :ruleset_association_name, String
  end
end
