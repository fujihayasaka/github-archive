# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryRulesetHistoryTest < GitHub::TestCase
  include RepositoryRulesets::HashBuilder

  fixtures do
    @business_owner = create(:user)
    @business = create(:business, owners: [@business_owner])
    @org = create(:business_plus_organization, business: @business)
    @org_repo = create(:repository, owner: @org)
    @ruleset = create(:repository_ruleset, :example_ruleset, name: "testing", source: @org)
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
      enable_feature_flag(:rules_history)
      @ruleset.bypass_actors << DeployKeyBypassActor.new
      @ruleset.save
      ruleset = @ruleset.histories.first.ruleset_from_state
      assert ruleset.bypass_actors.any? { |ba| ba.is_a?(DeployKeyBypassActor) }
    end

    test "ruleset hash with org admin bypass" do
      disable_feature_flag(:report_authzd_indeterminates) # this test fails when authzd raises errors
      enable_feature_flag(:rules_history)
      @ruleset.bypass_actors << OrganizationAdminBypassActor.new(bypass_mode: 0)
      @ruleset.save
      rule = @ruleset.histories.first.ruleset_from_state

      hash = repository_ruleset_hash(rule, { request_source: @org_repo, current_user: @org_repo.owner })
      assert hash[:current_user_can_bypass] == "always"
    end

    test "builds ruleset with org admin bypass" do
      enable_feature_flag(:rules_history)
      @ruleset.bypass_actors << OrganizationAdminBypassActor.new(bypass_mode: 0)
      @ruleset.save
      rule = @ruleset.histories.first.ruleset_from_state

      assert_equal 1, rule.bypass_actors.size
      assert_equal "OrganizationAdminBypassActor", rule.bypass_actors.first.type
      assert_equal 0, rule.bypass_actors.first.bypass_mode

      @ruleset.upsert_bypass_actors([])
      @ruleset.save
      rule = @ruleset.histories.first.ruleset_from_state
      assert_equal 0, rule.bypass_actors.size
    end

    test "deserializes without type field" do
      enable_feature_flag(:rules_history)

      @ruleset.bypass_actors << OrganizationAdminBypassActor.new(bypass_mode: 0)
      @ruleset.save

      rule = @ruleset.histories.first.ruleset_from_state
      assert_equal 1, rule.bypass_actors.size
      # assert we get the concrete subclass, not the base class
      assert_equal "OrganizationAdminBypassActor", rule.bypass_actors.first.type
    end
  end
end
