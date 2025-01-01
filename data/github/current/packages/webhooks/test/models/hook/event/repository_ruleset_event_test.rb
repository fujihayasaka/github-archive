# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventRepositoryRulesetTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do

    GitHub.flipper[:push_rulesets].enable

    @owner = create(:user)
    @org = create(:organization, admin: @owner, plan: "business_plus")
    @repo = create(:repository, owner: @owner)

    @repo_ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo)
    create(:repository_rule_configuration, repository_ruleset: @repo_ruleset, rule_type: "max_file_path_length", parameters: { "max_file_path_length" => 255 })

    @org_ruleset = create(:repository_ruleset, :targets_all_repos, :targets_default_branch, source: @org)
    create(:repository_rule_configuration, repository_ruleset: @org_ruleset, rule_type: "deletion")
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::RepositoryRulesetEvent, :action, :repository_ruleset_id
  end

  test "actor is present" do
    assert build_repository_ruleset_event.actor
  end

  context "#target_repository" do
    test "is nil for org rulesets" do
      org_ruleset = create(:repository_ruleset, source: @org)
      assert_nil build_repository_ruleset_event(ruleset_id: org_ruleset.id).target_repository
    end

    test "is not nil for repository rulesets" do
      refute_nil build_repository_ruleset_event.target_repository
    end
  end

  context "#target_organization" do
    test "is not nil for org rulesets" do
      org_ruleset = create(:repository_ruleset, source: @org)
      refute_nil build_repository_ruleset_event(ruleset_id: org_ruleset.id).target_organization
    end

    test "is nil for repository rulesets not owned by orgs" do
      assert_nil build_repository_ruleset_event.target_organization
    end

    test "is not nil for repository rulesets owned by orgs" do
      org_repo = create(:repository, owner: @org)
      org_repo_ruleset = create(:repository_ruleset, :targets_default_branch, source: org_repo)
      refute_nil build_repository_ruleset_event(ruleset_id: org_repo_ruleset.id).target_organization
    end
  end

  context "#repository_ruleset" do
    test "is not nil" do
      refute_nil build_repository_ruleset_event.repository_ruleset
    end
  end

  context "#changes" do
    test "should be nil if no changes" do
      assert_nil build_repository_ruleset_event(changes: nil).changes
    end

    test "should include ruleset column changes" do
      changes = { ruleset_old_name: "old name", ruleset_name: "new name", ruleset_old_enforcement: "disabled", ruleset_enforcement: "enabled" }
      expected = { name: { from: "old name" }, enforcement: { from: "disabled" } }

      assert_equal expected, build_repository_ruleset_event(action: :edited, changes: changes).changes
    end

    test "should not include rules if no rule changes" do
      payload = { ruleset_old_name: "old name", ruleset_name: "new name" }

      changes = build_repository_ruleset_event(action: :edited, changes: payload).changes
      assert_nil changes[:rules]
    end

    test "should not include conditions if no condition changes" do
      payload = { ruleset_old_name: "old name", ruleset_name: "new name" }

      changes = build_repository_ruleset_event(action: :edited, changes: payload).changes
      assert_nil changes[:conditions]
    end

    test "should include new rules" do
      ruleset = create(:repository_ruleset, source: @repo)

      ruleset.upsert_rules([{ rule_type: "max_file_path_length", parameters: { "max_file_path_length" => 255 } }])

      ruleset.reload
      changes = build_repository_ruleset_event(action: :edited, changes: ruleset.changes_payload, ruleset_id: ruleset.id).changes
      expected = Api::Serializer.serialize(:repository_rule_hash, ruleset.rule_configurations.first)

      refute_nil changes[:rules][:added]
      assert_equal expected, changes[:rules][:added].first
    end

    test "should include updated rules" do
      @repo_ruleset.upsert_rules([{ id: @repo_ruleset.rule_configurations.first.id, rule_type: "max_file_path_length", parameters: { "max_file_path_length" => 100 } }])

      changes = build_repository_ruleset_event(action: :edited, changes: @repo_ruleset.changes_payload).changes
      expected = { rule: Api::Serializer.serialize(:repository_rule_hash, @repo_ruleset.reload.rule_configurations.first), changes: { configuration: { from: { "max_file_path_length" => 255 }.to_json } } }

      refute_nil changes[:rules][:updated]
      assert_equal expected, changes[:rules][:updated].first
    end

    test "should include deleted rules" do
      old_rule = @repo_ruleset.rule_configurations.first

      @repo_ruleset.upsert_rules([])

      changes = build_repository_ruleset_event(action: :edited, changes: @repo_ruleset.changes_payload(include_deleted_models: true)).changes
      expected = Api::Serializer.serialize(:repository_rule_hash, old_rule)

      refute_nil changes[:rules][:deleted]
      assert_equal expected, changes[:rules][:deleted].first
    end

    test "should include added conditions" do
      ruleset = create(:repository_ruleset, source: @repo)

      ruleset.upsert_conditions([{ target: "ref_name", parameters: { exclude: [], include: ["refs/heads/test"] } }])

      ruleset.reload
      added_condition = ruleset.conditions.first

      changes = build_repository_ruleset_event(action: :edited, changes: ruleset.changes_payload, ruleset_id: ruleset.id).changes
      expected = Api::Serializer.serialize(:repository_rule_condition_hash, added_condition, request_source: @repo)

      refute_nil changes[:conditions][:added]
      assert_equal expected, changes[:conditions][:added].first
    end

    test "should include updated conditions" do
      @repo_ruleset.upsert_conditions([{ id: @repo_ruleset.conditions.first.id, target: "ref_name", parameters: { exclude: [], include: ["refs/heads/test"] } }])

      updated_condition = @repo_ruleset.reload.conditions.first

      changes = build_repository_ruleset_event(action: :edited, changes: @repo_ruleset.changes_payload).changes
      expected = { condition: Api::Serializer.serialize(:repository_rule_condition_hash, updated_condition, request_source: @repo), changes: { include: { from: ["~DEFAULT_BRANCH"] } } }

      refute_nil changes[:conditions][:updated]
      assert_equal expected, changes[:conditions][:updated].first
    end

    test "should include deleted conditions" do
      deleted_condition = @repo_ruleset.conditions.first

      @repo_ruleset.upsert_conditions([])

      changes = build_repository_ruleset_event(action: :edited, changes: @repo_ruleset.changes_payload(include_deleted_models: true)).changes
      expected = Api::Serializer.serialize(:repository_rule_condition_hash, deleted_condition, request_source: @repo)
      refute_nil changes[:conditions][:deleted]
      assert_equal expected, changes[:conditions][:deleted].first
    end

    test "should include repository_name conditions" do
      deleted_conditions = @org_ruleset.conditions.to_a

      @org_ruleset.upsert_conditions([])

      changes = build_repository_ruleset_event(action: :edited, ruleset_id: @org_ruleset.id, changes: @org_ruleset.changes_payload(include_deleted_models: true)).changes
      expected = Api::Serializer.serialize(:repository_rule_conditions_hash, deleted_conditions, request_source: @org)

      refute_nil changes[:conditions][:deleted]
      assert_equal 2, changes[:conditions][:deleted].size
      assert_same_elements %w[repository_name ref_name], expected.keys
      assert_same_elements expected.keys, changes[:conditions][:deleted].map { |c| c.keys }.flatten
    end
  end

  def build_repository_ruleset_event(action: :created, changes: nil, ruleset_id: nil)
    ruleset_id ||= @repo_ruleset.id

    Hook::Event::RepositoryRulesetEvent.new(actor_id: @owner.id, repository_ruleset_id: ruleset_id, action: action, changes: changes)
  end
end
