# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryRulesetHistoryTest < GitHub::TestCase

  fixtures do
    @ruleset = create(:repository_ruleset, :example_ruleset)
    @history = @ruleset.histories.first
  end

  context "#deserialized" do
    test "deserializes the state" do
      deserialized = @history.deserialized
      assert deserialized.is_a?(Hash)
      assert_equal deserialized[:name], @ruleset.name
    end
  end if GitHub.flipper[:rules_history].enabled?

  context "#ruleset_from_state" do
    test "builds ruleset from serialized data" do
      ruleset = @history.ruleset_from_state
      assert ruleset.is_a?(RepositoryRuleset)
      assert_nil ruleset.id
      assert_equal @ruleset.name, ruleset.name
      keys = %w[id created_at updated_at created_by_id updated_by_id repository_ruleset_id]
      assert_same_elements @ruleset.conditions.map { |c| c.attributes.except(*keys) }, ruleset.conditions.map { |c| c.attributes.except(*keys) }
      assert_same_elements @ruleset.rule_configurations.map { |r| r.attributes.except(*keys) }, ruleset.rule_configurations.map { |r| r.attributes.except(*keys) }
      assert_same_elements @ruleset.bypass_actors.map { |ba| ba.attributes.except(*keys) }, ruleset.bypass_actors.map { |ba| ba.attributes.except(*keys) }
    end if GitHub.flipper[:rules_history].enabled?

    test "builds ruleset with deploy key bypass" do
      GitHub.flipper[:rules_history].enable
      @ruleset.deploy_key_bypass = true
      @ruleset.save
      ruleset = @ruleset.histories.first.ruleset_from_state
      assert ruleset.deploy_key_bypass
    end
  end
end
