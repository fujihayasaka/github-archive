# typed: true
# frozen_string_literal: true

require "test_helper"

class RulesetMatcherTest < GitHub::TestCase
  include RulesEngine

  setup do
    setup_search
  end

  teardown do
    teardown_search
  end

  fixtures do
    @enterprise = create(:business)
    @owner = create(:user, plan: "business_plus")
    @org = create(:business_plus_organization, admin: @owner, business: @enterprise)
    @org_repo = create(:repository, owner: @org, name: "org-repo", from_example: :simple)
    @user_repo = create(:repository, owner: @owner)

    @org_repo_ruleset = create(:repository_ruleset, source: @org_repo)
    create(:repository_rule_condition,
      repository_ruleset: @org_repo_ruleset,
      target: :ref_name,
      parameters:
      {
        include: ["refs/heads/*"],
        exclude: []
      }
    )
    @org_repo_ruleset.reload
  end

  context "rulesets_target_count for org ruleset" do
    test "returns empty if no rulesets" do
      assert_empty RulesetMatcher.rulesets_target_count(@org, [])
    end

    test "returns empty if not property ruleset" do
      ruleset = create(:repository_ruleset, name: "Foo", source: @org_repo)

      assert_query_count_per_table({ repository: 0 }) do
        assert_empty RulesetMatcher.rulesets_target_count(@org, [ruleset.id])
      end
    end

    test "returns count nil if Elastomer error" do
      Search::Queries::RepoQuery.any_instance.stubs(:count_with_timeout).raises(ElastomerClient::Client::Error)

      definition = create :custom_property_definition, source: @org, property_name: "environment"
      create :custom_property_value, target: @org_repo, definition: definition, value: "testing"

      ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
      create(:repository_rule_condition, target: "repository_property", parameters: {
        include: [
          { name: "environment", property_values: ["testing"], source: "custom" }
        ],
        exclude: []
      }, repository_ruleset: ruleset)

      make_searchable(@org_repo)

      target_count = assert_query_count_per_table({ repositories: 0 }) do
        RulesetMatcher.rulesets_target_count(@org, [ruleset.id])
      end
      assert_equal [{ rulesetId: ruleset.id, count: nil }], target_count
    end

    test "returns ruleset preview for a single property ruleset" do
      definition = create :custom_property_definition, source: @org, property_name: "environment"
      create :custom_property_value, target: @org_repo, definition: definition, value: "testing"

      ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
      create(:repository_rule_condition, target: "repository_property", parameters: {
        include: [
          { name: "environment", property_values: ["testing"], source: "custom" }
        ],
        exclude: []
      }, repository_ruleset: ruleset)

      make_searchable(@org_repo)

      target_count = assert_query_count_per_table({ repositories: 0 }) do
        RulesetMatcher.rulesets_target_count(@org, [ruleset.id])
      end
      assert_equal [{ rulesetId: ruleset.id, count: 1 }], target_count
    end

    test "returns ruleset preview for multiple property rulesets" do
      env_definition = create :custom_property_definition, source: @org, property_name: "environment"
      platform_definition = create :custom_property_definition, source: @org, property_name: "platform"

      create :custom_property_value, target: @org_repo, definition: env_definition, value: "testing"

      another_org_repo = create(:repository, owner: @org)
      create :custom_property_value, target: another_org_repo, definition: env_definition, value: "testing"
      create :custom_property_value, target: another_org_repo, definition: platform_definition, value: "android"

      ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
      create(:repository_rule_condition, target: "repository_property", parameters: {
        include: [
          { name: "environment", property_values: ["testing"], source: "custom" }
        ],
        exclude: []
        }, repository_ruleset: ruleset)

      another_ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
      create(:repository_rule_condition, target: "repository_property", parameters: {
        include: [
          { name: "environment", property_values: ["testing"], source: "custom" },
          { name: "platform", property_values: ["android"], source: "custom" }
        ],
        exclude: []
        }, repository_ruleset: another_ruleset)

      no_property_ruleset = create(:repository_ruleset, name: "Foo", source: @org_repo)

      make_searchable(@org_repo, another_org_repo)

      expected_result = [
        { rulesetId: ruleset.id, count: 2 },
        { rulesetId: another_ruleset.id, count: 1 }
      ]

      target_count = assert_query_count_per_table({ repositories: 0 }) do
        RulesetMatcher.rulesets_target_count(@org, [ruleset.id, another_ruleset.id, no_property_ruleset.id])
      end
      assert_same_elements expected_result, target_count
    end

    test "returns ruleset preview for a repo name ruleset" do
      ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
      create(
        :repository_rule_condition,
        repository_ruleset: ruleset,
        target: "repository_name",
        parameters: { include: ["*"], exclude: [] }
      )

      target_count = assert_query_count_per_table({ repositories: 2 }) do
        RulesetMatcher.rulesets_target_count(@org, [ruleset.id])
      end
      assert_equal [{ rulesetId: ruleset.id, count: 1, sampleTargetNames: ["org-repo"] }], target_count
    end

    test "returns a ruleset preview limiting the sample repos to MAX_SAMPLE_NAMES for the repo name ruleset" do
      2.times { create(:repository, owner: @org) }

      ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
      create(
        :repository_rule_condition,
        repository_ruleset: ruleset,
        target: "repository_name",
        parameters: { include: ["*"], exclude: [] }
      )

      RulesEngine::RulesetMatcher.stub_const(:MAX_SAMPLE_NAMES, 2) do
        target_count = RulesetMatcher.rulesets_target_count(@org, [ruleset.id])

        assert_equal target_count.count, 1
        ruleset_target = T.must(target_count.first)

        assert_equal ruleset_target[:rulesetId], ruleset.id
        assert_equal ruleset_target[:count], 3
        assert_equal ruleset_target[:sampleTargetNames].count, 2
      end
    end

    test "returns ruleset preview for multiple repo name rulesets" do
      create(:repository, owner: @org, name: "org-repository")

      ruleset_1 = create(:repository_ruleset, :targets_default_branch, source: @org)
      create(
        :repository_rule_condition,
        repository_ruleset: ruleset_1,
        target: "repository_name",
        parameters: { include: ["*org*"], exclude: [] }
      )

      ruleset_2 = create(:repository_ruleset, :targets_default_branch, source: @org)
      create(
        :repository_rule_condition,
        repository_ruleset: ruleset_2,
        target: "repository_name",
        parameters: { include: ["*repository*"], exclude: [] }
      )

      target_count = assert_query_count_per_table({ repositories: 2 }) do
        RulesetMatcher.rulesets_target_count(@org, [ruleset_1.id, ruleset_2.id])
      end

      expected_result = [
        { rulesetId: ruleset_1.id, count: 2, sampleTargetNames: %w[org-repo org-repository] },
        { rulesetId: ruleset_2.id, count: 1, sampleTargetNames: ["org-repository"] }
      ]

      assert_same_elements expected_result, target_count
    end

    test "returns ruleset preview for a mix of repo name and property rulesets" do
      another_org_repo = create(:repository, owner: @org, name: "org-repository")

      definition = create :custom_property_definition, source: @org, property_name: "environment"
      create :custom_property_value, target: @org_repo, definition: definition, value: "testing"
      create :custom_property_value, target: another_org_repo, definition: definition, value: "testing"

      property_ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
      create(:repository_rule_condition, target: "repository_property", parameters: {
        include: [
          { name: "environment", property_values: ["testing"], source: "custom" }
        ],
        exclude: []
      }, repository_ruleset: property_ruleset)

      make_searchable(@org_repo, another_org_repo)

      repo_name_ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
      create(
        :repository_rule_condition,
        repository_ruleset: repo_name_ruleset,
        target: "repository_name",
        parameters: { include: ["*repository*"], exclude: [] }
      )

      target_count = assert_query_count_per_table({ repositories: 2 }) do
        RulesetMatcher.rulesets_target_count(@org, [property_ruleset.id, repo_name_ruleset.id])
      end

      expected_result = [
        { rulesetId: repo_name_ruleset.id, count: 1, sampleTargetNames: %w[org-repository] },
        { rulesetId: property_ruleset.id, count: 2 }
      ]
      assert_same_elements expected_result, target_count
    end

    test "returns error message if too many repositories for a repo name ruleset" do
      2.times { create(:repository, owner: @org) }

      ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
      create(
        :repository_rule_condition,
        repository_ruleset: ruleset,
        target: "repository_name",
        parameters: { include: ["*"], exclude: [] }
      )

      RulesEngine::RulesetMatcher.stub_const(:MAX_MATCHING_TARGETS, 2) do
        target_count = assert_query_count_per_table({ repositories: 1 }) do
          RulesetMatcher.rulesets_target_count(@org, [ruleset.id])
        end

        assert_equal [{
          rulesetId: ruleset.id,
          errorMessage: "Unable to display affected targets due to a large number of repositories in this organization."
        }], target_count
      end
    end
  end

  context "rulesets_target_count for repo ruleset" do
    test "returns empty if no rulesets" do
      assert_empty RulesetMatcher.rulesets_target_count(@org_repo, [])
    end

    test "returns empty if not ref name ruleset created for the repo neither the org" do
      user_repo = create(:repository, owner: @owner)
      ruleset = create(:repository_ruleset, :targets_default_branch, source: user_repo)

      assert_query_count_per_table({ repository: 0 }) do
        assert_empty RulesetMatcher.rulesets_target_count(@org_repo, [ruleset.id])
      end
    end

    test "returns ruleset preview for a ref name ruleset" do
      target_count = RulesetMatcher.rulesets_target_count(@org_repo, [@org_repo_ruleset.id])
      assert_equal [{ rulesetId: @org_repo_ruleset.id, count: 3, sampleTargetNames: %w[-gh-pages cr-line-endings master] }], target_count
    end

    test "returns ruleset preview for a tag name ruleset" do
      ruleset = create(:repository_ruleset, target: :tag, source: @org_repo)
      create(:repository_rule_condition,
        repository_ruleset: ruleset,
        target: :ref_name,
        parameters:
        {
          include: ["refs/tags/v*"],
          exclude: []
        }
      )
      ruleset.reload

      target_count = RulesetMatcher.rulesets_target_count(@org_repo, [ruleset.id])
      assert_equal [{ rulesetId: ruleset.id, count: 2, sampleTargetNames: %w[v2 v1] }], target_count
    end

    test "returns ruleset preview for multiple rulesets" do
      org_ruleset = create(:repository_ruleset, target: :tag, source: @org_repo)
      create(:repository_rule_condition, :targets_tag, tag_name: "refs/tags/v1", repository_ruleset: org_ruleset)
      org_ruleset.reload

      target_count = RulesetMatcher.rulesets_target_count(@org_repo, [@org_repo_ruleset.id, org_ruleset.id])

      expected_result = [
        { rulesetId: @org_repo_ruleset.id, count: 3, sampleTargetNames: %w[-gh-pages cr-line-endings master] },
        { rulesetId: org_ruleset.id, count: 1, sampleTargetNames: %w[v1] }
      ]
      assert_same_elements expected_result, target_count
    end

    test "limit the sample repos to MAX_SAMPLE_NAMES for the ref name ruleset" do
      RulesEngine::RulesetMatcher.stub_const(:MAX_SAMPLE_NAMES, 2) do
        target_count = RulesetMatcher.rulesets_target_count(@org_repo, [@org_repo_ruleset.id])

        assert_equal [{
          rulesetId: @org_repo_ruleset.id,
          count: 3,
          sampleTargetNames: %w[-gh-pages cr-line-endings]
          }], target_count
      end
    end

    test "returns error message if too many refs for a ref name ruleset" do
      RulesEngine::RulesetMatcher.stub_const(:MAX_MATCHING_TARGETS, 2) do
        target_count = RulesetMatcher.rulesets_target_count(@org_repo, [@org_repo_ruleset.id])

        assert_equal [{
          rulesetId: @org_repo_ruleset.id,
          errorMessage: "Unable to display affected targets due to a large number of branches in this repository."
        }], target_count
      end
    end

    test "return ruleset repo preview an org ruleset that target an org repository" do
      ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
      create(
        :repository_rule_condition,
        repository_ruleset: ruleset,
        target: "repository_name",
        parameters: { include: ["*"], exclude: [] }
      )

      assert_equal [{ rulesetId: ruleset.id, count: 1, sampleTargetNames: [@org_repo.default_branch] }], RulesetMatcher.rulesets_target_count(@org_repo, [ruleset.id])
    end

    test "return ruleset repo preview for org and repo rulesets" do
      org_ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
      repo_ruleset = create(:repository_ruleset, :targets_default_branch, source: @org_repo)

      expected_result = [
        { rulesetId: org_ruleset.id, count: 1, sampleTargetNames: [@org_repo.default_branch] },
        { rulesetId: repo_ruleset.id, count: 1, sampleTargetNames: [@org_repo.default_branch] }
      ]
      assert_same_elements expected_result, RulesetMatcher.rulesets_target_count(@org_repo, [org_ruleset.id, repo_ruleset.id])
    end

    test "return ruleset repo preview a repository not part of an organization" do
      user_repo = create(:repository, owner: @owner, from_example: :simple)
      ruleset = create(:repository_ruleset, :targets_default_branch, source: user_repo)

      assert_equal [{ rulesetId: ruleset.id, count: 1, sampleTargetNames: [user_repo.default_branch] }], RulesetMatcher.rulesets_target_count(user_repo, [ruleset.id])
    end

    test "return ruleset repo preview for a ruleset without ref_name conditions (allowed in non public repos)" do
      GitHub.flipper[:push_rulesets].enable

      private_org_repo = create(:private_repository, owner: @org, from_example: :simple)
      repo_ruleset = create(:repository_ruleset, target: :push, source: private_org_repo)

      assert_empty RulesetMatcher.rulesets_target_count(private_org_repo, [repo_ruleset.id])
    end
  end

  context "async_preview_ff_enabled" do
    test "When FFs are disabled" do
      GitHub.flipper[:ruleset_async_preview].disable
      GitHub.flipper[:property_ruleset_async_preview].disable

      refute RulesetMatcher.async_preview_ff_enabled?(@org, @owner)
      refute RulesetMatcher.async_preview_ff_enabled?(@org, nil)
      refute RulesetMatcher.async_preview_ff_enabled?(@org_repo, @owner)
      refute RulesetMatcher.async_preview_ff_enabled?(@org_repo, nil)
      refute RulesetMatcher.async_preview_ff_enabled?(@user_repo, @owner)
    end

    test "ruleset_async_preview enabled and property_ruleset_async_preview disabled" do
      GitHub.flipper[:ruleset_async_preview].enable(@owner)
      GitHub.flipper[:property_ruleset_async_preview].disable(@org)

      assert RulesetMatcher.async_preview_ff_enabled?(@org, @owner)
      refute RulesetMatcher.async_preview_ff_enabled?(@org, nil)
      assert RulesetMatcher.async_preview_ff_enabled?(@org_repo, @owner)
      refute RulesetMatcher.async_preview_ff_enabled?(@org_repo, nil)
      assert RulesetMatcher.async_preview_ff_enabled?(@user_repo, @owner)
    end

    test "ruleset_async_preview disabled and property_ruleset_async_preview enabled" do
      GitHub.flipper[:ruleset_async_preview].disable(@owner)
      GitHub.flipper[:property_ruleset_async_preview].enable(@org)

      assert RulesetMatcher.async_preview_ff_enabled?(@org, @owner)
      assert RulesetMatcher.async_preview_ff_enabled?(@org, nil)
      refute RulesetMatcher.async_preview_ff_enabled?(@org_repo, @owner)
      refute RulesetMatcher.async_preview_ff_enabled?(@org_repo, nil)
      refute RulesetMatcher.async_preview_ff_enabled?(@user_repo, @owner)
    end
  end

  context "rulesets_target_count for enterprise ruleset" do
    test "returns for organization_name" do
      ruleset = create(:repository_ruleset, source: @enterprise, target: "member_privilege")
      create(
        :repository_rule_condition,
        repository_ruleset: ruleset,
        target: "organization_name",
        parameters: { include: ["*"], exclude: [] }
      )

      target_count = RulesetMatcher.rulesets_target_count(@enterprise, [ruleset.id])
      assert_equal [{ rulesetId: ruleset.id, count: 1, sampleTargetNames: [@org.display_login] }], target_count
    end
  end

  context "matching_organization_targets_or_message" do
    test "matches org targets" do
      another_org = create(:organization, business: @enterprise)

      ruleset = create(:repository_ruleset, source: @enterprise, target: "member_privilege")
      create(:repository_rule_condition, :targets_org, org_name: @org.display_login, repository_ruleset: ruleset)
      ruleset.reload

      result = RulesEngine::RulesetMatcher.matching_organization_targets_or_message(@enterprise, ruleset)
      assert_same_elements [@org.display_login], result
    end
  end
end
