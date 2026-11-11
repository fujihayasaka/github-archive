# typed: true
# frozen_string_literal: true

class Platform::Models::RepositoryRuleConditions
  attr_reader :ruleset

  def initialize(ruleset)
    @ruleset = ruleset
  end

  def conditions
    ruleset.conditions
  end
end
