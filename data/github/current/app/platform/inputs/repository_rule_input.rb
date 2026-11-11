# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class RepositoryRuleInput < Platform::Inputs::Base
      description "Specifies the attributes for a new or updated rule."

      argument :id, ID, "Optional ID of this rule when updating", required: false, loads: Objects::RepositoryRule, as: :existing_rule
      argument :type, Enums::RepositoryRuleType, "The type of rule to create.", required: true
      argument :parameters, Inputs::RuleParametersInput, "The parameters for the rule.", required: false
    end
  end
end
