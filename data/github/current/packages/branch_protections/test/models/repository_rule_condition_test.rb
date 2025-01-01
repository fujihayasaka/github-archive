# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryRuleConditionTest < GitHub::TestCase
  include RepositoriesTestHelper
  include RulesEngine::RefUpdateTestHelper

  fixtures do
    @user = create(:user)
    @org = create :organization, admin: @user, plan: "business_plus"

    @repo = create(:repository, owner: @org, from_example: :simple)
    @ruleset = create(:repository_ruleset, source: @repo)
    @org_ruleset = create(:repository_ruleset, source: @org)
  end

  setup do
    @ref_update = create_branch_update(@repo, name: @repo.default_branch)
    @context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @repo, ref_update: @ref_update)
  end

  context "verify run_evaluation for ref_name" do
    test "returns true when ref_update matches condition" do
      rule_condition = create(:repository_rule_condition, :targets_default_branch, repository_ruleset: @ruleset)
      assert_equal true, rule_condition.run_evaluation(@context)
    end

    test "returns false for a partial match on ref_name" do
      ref_update = create_branch_update(@repo, name: "#{@repo.default_branch}2")
      context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @repo, ref_update: ref_update)
      rule_condition = create(:repository_rule_condition, :targets_default_branch, repository_ruleset: @ruleset)
      assert_equal false, rule_condition.run_evaluation(context)
    end

    test "returns false when ref_update does not match condition" do
      rule_condition = create(:repository_rule_condition, repository_ruleset: @ruleset, parameters: { include: ["refs/heads/abc"], exclude: [] })
      assert_equal false, rule_condition.run_evaluation(@context)
    end

    test "returns true when ref_update matches include and doesn't match exclude" do
      rule_condition = create(:repository_rule_condition, repository_ruleset: @ruleset, parameters: { include: ["~DEFAULT_BRANCH"], exclude: ["refs/heads/someotherbranch"] })
      assert_equal true, rule_condition.run_evaluation(@context)
    end

    test "returns false when ref_update matches include and does match exclude" do
      rule_condition = create(:repository_rule_condition, repository_ruleset: @ruleset, parameters: { include: ["~DEFAULT_BRANCH"], exclude: ["refs/heads/*"] })
      assert_equal false, rule_condition.run_evaluation(@context)
    end

    test "returns true when there are no include parameters and does not match exclude" do
      rule_condition = create(:repository_rule_condition, repository_ruleset: @ruleset, parameters: { include: [], exclude: ["refs/heads/someotherbranch"] })
      assert_equal true, rule_condition.run_evaluation(@context)
    end

    test "returns false when there are no include parameters and does match exclude" do
      rule_condition = create(:repository_rule_condition, repository_ruleset: @ruleset, parameters: { include: [], exclude: ["~DEFAULT_BRANCH"] })
      assert_equal false, rule_condition.run_evaluation(@context)
    end

    test "returns false when there are no include parameters and no exclude parameters" do
      rule_condition = create(:repository_rule_condition, repository_ruleset: @ruleset, parameters: { include: [], exclude: [] })
      assert_equal false, rule_condition.run_evaluation(@context)
    end
  end

  context "verify run_evaluation for repository_name" do
    test "returns true when repo name matches include and doesn't match exclude" do
      rule_condition = create(:repository_rule_condition, repository_ruleset: @org_ruleset, target: :repository_name, parameters: { include: [@repo.name], exclude: ["anotherrepo"] })
      assert_equal true, rule_condition.run_evaluation(@context)
    end

    test "returns false when repo name doesn't matches include and doesn't match exclude" do
      rule_condition = create(:repository_rule_condition, repository_ruleset: @org_ruleset, target: :repository_name, parameters: { include: ["notthisrepo"], exclude: ["anotherrepo"] })
      assert_equal false, rule_condition.run_evaluation(@context)
    end

    test "returns false when repo name matches include and does match exclude" do
      rule_condition = create(:repository_rule_condition, repository_ruleset: @org_ruleset, target: :repository_name, parameters: { include: [@repo.name], exclude: ["*"] })
      assert_equal false, rule_condition.run_evaluation(@context)
    end

    test "returns false when there are no include parameters and no exclude parameters" do
      rule_condition = create(:repository_rule_condition, repository_ruleset: @org_ruleset, target: :repository_name, parameters: { include: [], exclude: [] })
      assert_equal false, rule_condition.run_evaluation(@context)
    end

    test "returns true for all repos when targeting ~ALL" do
      rule_condition = create(:repository_rule_condition, repository_ruleset: @org_ruleset, target: :repository_name, parameters: { include: ["~ALL"], exclude: [] })
      special_repo = create(:repository, name: ".github", owner: @org)
      special_repo_ref_update = create_branch_update(special_repo, name: special_repo.default_branch)
      special_repo_context = RuleEngine::Conditions::RulesetTargetContext.new(repository: special_repo, ref_update: @ref_update)

      assert_equal true, rule_condition.run_evaluation(@context)
      assert_equal true, rule_condition.run_evaluation(special_repo_context)
    end
  end

  context "verify parameter validation" do
    # TODO: Move these to target specific test files
    test "ensures regex include/exclude are arrays" do
      rule_condition = build(:repository_rule_condition, target: :ref_name, parameters: { include: "~DEFAULT_BRANCH", exclude: ["refs/heads/*"] }, repository_ruleset: @ruleset)
      refute rule_condition.valid?
      assert_equal ["Parameters are invalid for this target: Invalid parameter include: Expected array, got String"], rule_condition.errors.full_messages
    end

    test "valid when repository_name uses fnmatch" do
      rule_condition = build(:repository_rule_condition, target: :repository_name, parameters: { include: ["a"], exclude: ["b"] }, repository_ruleset: @org_ruleset)
      assert rule_condition.valid?
    end

    test "valid when include and exclude are empty" do
      # Verify for ref name
      ref_name_condition = build(:repository_rule_condition, target: :ref_name, parameters: { include: [], exclude: [] }, repository_ruleset: @ruleset)
      # Verify for repo name
      repo_name_condition = build(:repository_rule_condition, target: :repository_name, parameters: { include: [], exclude: [] }, repository_ruleset: @org_ruleset)
      assert ref_name_condition.valid?
      assert repo_name_condition.valid?
    end

    test "invalid when a value is empty" do
      # Verify for ref name
      ref_name_condition = build(:repository_rule_condition, target: :ref_name, parameters: { include: ["refs/heads/*", "refs/heads/     "], exclude: [] }, repository_ruleset: @ruleset)
      # Verify for repo name
      repo_name_condition = build(:repository_rule_condition, target: :repository_name, parameters: { include: ["repo", "   ", "a  "], exclude: [] }, repository_ruleset: @org_ruleset)
      refute ref_name_condition.valid?
      assert_equal ["Parameters are invalid for this target: Invalid parameter include: Invalid target patterns: `refs/heads/     `"], ref_name_condition.errors.full_messages
      refute repo_name_condition.valid?
      assert_equal ["Parameters are invalid for this target: Invalid parameter include: Invalid target patterns: `   `"], repo_name_condition.errors.full_messages
    end

    test "invalid when a value is in both include and exclude" do
      # Verify for ref name
      ref_name_condition = build(:repository_rule_condition, target: :ref_name, parameters: { include: ["refs/heads/*", "~ALL", "refs/heads/dev*"], exclude: ["refs/heads/*", "refs/heads/other", "~ALL"] }, repository_ruleset: @ruleset)
      # Verify for repo name
      repo_name_condition = build(:repository_rule_condition, target: :repository_name, parameters: { include: %w[repo-a repo-b], exclude: ["repo-b"] }, repository_ruleset: @org_ruleset)
      refute ref_name_condition.valid?
      assert_equal ["Parameters are invalid for this target: Target patterns found in both include and exclude parameters: `refs/heads/*`, `~ALL`"], ref_name_condition.errors.full_messages
      refute repo_name_condition.valid?
      assert_equal ["Parameters are invalid for this target: Target patterns found in both include and exclude parameters: `repo-b`"], repo_name_condition.errors.full_messages
    end
  end

  context "aliased parameters" do
    test "renames aliased repository_property parameter" do
      create :custom_property_definition, :single_select, source: @org, property_name: "test",
        description: "test", allowed_values: %w[a b c]
      create :custom_property_definition, :single_select, source: @org, property_name: "test2",
        description: "test2", allowed_values: %w[c d e]

      condition = build(:repository_rule_condition, target: :repository_property,
        parameters: { include: [{ name: "test", values: %w[a b] }], exclude: [{ name: "test2", values: %w[c d] }] }, repository_ruleset: @org_ruleset)
      condition.save(validate: false)

      # Verify that the aliased parameters are renamed
      @org_ruleset.reload
      updated_condition = @org_ruleset.conditions.find_by(target: :repository_property)
      include_param = updated_condition.parameters["include"]
      assert_equal "test", include_param[0]["name"]
      assert_nil include_param[0]["values"]
      assert_same_elements %w[a b], include_param[0]["property_values"]

      exclude_param = updated_condition.parameters["exclude"]
      assert_equal "test2", exclude_param[0]["name"]
      assert_nil exclude_param[0]["values"]
      assert_same_elements %w[c d], exclude_param[0]["property_values"]
    end

    test "ensure aliased parameters are valid" do
      create :custom_property_definition, :single_select, source: @org, property_name: "test",
        description: "test", allowed_values: %w[a b c]
      create :custom_property_definition, :single_select, source: @org, property_name: "test2",
        description: "test2", allowed_values: %w[c d e]

      condition = build(:repository_rule_condition, target: :repository_property,
        parameters: { include: [{ name: "test", values: %w[a b] }], exclude: [{ name: "test2", values: %w[c d] }] }, repository_ruleset: @org_ruleset)

      assert condition.valid?
      condition.save
      assert condition.errors.empty?
    end

    test "does not fail when parameters are invalid" do
      create :custom_property_definition, :single_select, source: @org, property_name: "test",
        description: "test", allowed_values: %w[a b c]
      create :custom_property_definition, :single_select, source: @org, property_name: "test2",
        description: "test2", allowed_values: %w[c d e]

      condition1 = build(:repository_rule_condition, target: :repository_property,
        parameters: { include: nil, exclude: { invalid: "format" } }, repository_ruleset: @org_ruleset)
      condition2 = build(:repository_rule_condition, target: :repository_property,
        parameters: { include: [nil], exclude: [{ invalid: "format" }] }, repository_ruleset: @org_ruleset)

      [condition1, condition2].each do |condition|
        assert_nothing_raised do
          refute condition.valid?
          condition.save
          refute condition.errors.empty?
        end
      end
    end
  end

  context "#changes_payload" do
    test "empty when no changes are made" do
      create(:repository_rule_condition, :targets_default_branch, repository_ruleset: @ruleset)

      rule_condition = @ruleset.reload.conditions.first

      assert_empty rule_condition.changes_payload
    end

    test "empty when no changes are made when save is false" do
      create(:repository_rule_condition, :targets_default_branch, repository_ruleset: @ruleset)

      rule_condition = @ruleset.reload.conditions.first

      assert_empty rule_condition.changes_payload
    end

    test "target should be tracked" do
      create(:repository_rule_condition, :targets_default_branch, repository_ruleset: @org_ruleset)

      rule_condition = @org_ruleset.reload.conditions.first

      rule_condition.target = :repository_name
      rule_condition.parameters = { include: ["a"], exclude: ["b"] }
      rule_condition.save!

      refute_empty rule_condition.changes_payload

      changes = rule_condition.changes_payload

      refute_nil changes[:old_target]
      assert_equal "ref_name", changes[:old_target]
    end

    test "target should be tracked when save is false" do
      create(:repository_rule_condition, :targets_default_branch, repository_ruleset: @org_ruleset)

      rule_condition = @org_ruleset.reload.conditions.first

      rule_condition.target = :repository_name
      rule_condition.parameters = { include: ["a"], exclude: ["b"] }

      refute_empty rule_condition.changes_payload(save: false)

      changes = rule_condition.changes_payload(save: false)

      refute_nil changes[:old_target]
      assert_equal %w[ref_name repository_name], changes[:old_target]
    end

    test "parameters should be tracked" do
      create(:repository_rule_condition, :targets_default_branch, repository_ruleset: @org_ruleset)

      rule_condition = @org_ruleset.reload.conditions.first

      rule_condition.target = :repository_name
      rule_condition.parameters = { include: ["a"], exclude: ["b"] }
      rule_condition.save!

      refute_empty rule_condition.changes_payload

      changes = rule_condition.changes_payload

      refute_nil changes[:old_target]
      assert_equal ["~DEFAULT_BRANCH"], changes[:old_parameters]["include"]
      assert_equal [], changes[:old_parameters]["exclude"]
    end

    test "parameters should be tracked when save is false" do
      create(:repository_rule_condition, :targets_default_branch, repository_ruleset: @org_ruleset)

      rule_condition = @org_ruleset.reload.conditions.first

      rule_condition.target = :repository_name
      rule_condition.parameters = { include: ["a"], exclude: ["b"] }

      refute_empty rule_condition.changes_payload(save: false)

      changes = rule_condition.changes_payload(save: false)

      refute_nil changes[:old_target]
      assert_equal [{ "exclude" => [], "include" => ["~DEFAULT_BRANCH"] }, { "include" => ["a"], "exclude" => ["b"] }], changes[:old_parameters]
    end
  end

  context "#supports_source?" do
    test "returns true if the source is supported by the condition" do
      rule_condition = create(:repository_rule_condition, :targets_default_branch, repository_ruleset: @ruleset)
      assert rule_condition.supports_source?
      assert RepositoryRuleCondition.supports_source?(rule_condition, @repo)
    end

    test "returns false if the source is not supported by the condition" do
      rule_condition = create(:repository_rule_condition, target: :repository_name, parameters: { include: [@repo.name], exclude: ["*"] }, repository_ruleset: @org_ruleset)
      refute RepositoryRuleCondition.supports_source?(rule_condition, @repo)
    end
  end

  context "supports_ruleset_target?" do
    test "returns true if the ruleset target is supported by the condition" do
      GitHub.flipper[:push_rulesets].enable
      ruleset = create(:repository_ruleset, source: @org, target: "push")
      rule_condition = create(:repository_rule_condition, :targets_all_repos, repository_ruleset: ruleset)
      assert rule_condition.supports_ruleset_target?
      assert RepositoryRuleCondition.supports_ruleset_target?(rule_condition, ruleset.target)
    end

    test "returns false if the ruleset target is not supported by the condition" do
      GitHub.flipper[:push_rulesets].enable
      ruleset = create(:repository_ruleset, source: @org, target: "push")
      rule_condition = build(:repository_rule_condition, :targets_default_branch, repository_ruleset: ruleset)
      refute rule_condition.supports_ruleset_target?
      refute RepositoryRuleCondition.supports_ruleset_target?(rule_condition, ruleset.target)
    end
  end

  context "ensure_no_public_repository_conditions" do
    test "cannot target public repositories" do
      GitHub.flipper[:push_rulesets].enable
      GitHub.flipper[:rules_exclude_public_repositories_from_targeting].enable

      push_ruleset = create(:repository_ruleset, source: @org, target: "push")
      rule_condition = build(:repository_rule_condition, target: :repository_id, parameters: { repository_ids: [@repo.global_relay_id] }, repository_ruleset: push_ruleset)

      refute rule_condition.valid?
      assert_equal ["Parameters are invalid for this target: Invalid parameter repository_ids: public repositories cannot be targeted by push rulesets"], rule_condition.errors.full_messages
    end
  end
end
