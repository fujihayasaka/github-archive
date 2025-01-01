# typed: true
# frozen_string_literal: true

require "test_helper"

class RulesEngine::AsyncValidationsTest < GitHub::TestCase
  fixtures do
    @repo = create :repository
    @ruleset1 = create :repository_ruleset, name: "test", source: @repo
    @ruleset2 = create :repository_ruleset, name: "test2"
  end

  test "validates ruleset names" do
    assert RulesEngine::AsyncValidations.validate_value(@repo, "ruleset_name", { "name" => "test", "id" => @ruleset1.id })

    # allow duplicates across sources
    assert RulesEngine::AsyncValidations.validate_value(@repo, "ruleset_name", { "name" => "test2" })

    # disallow case-insensitive differences
    refute RulesEngine::AsyncValidations.validate_value(@repo, "ruleset_name", { "name" => "TEST" })

    refute RulesEngine::AsyncValidations.validate_value(@repo, "ruleset_name", { "name" => "test" })
    refute RulesEngine::AsyncValidations.validate_value(@repo, "regex", {})
  end
end
