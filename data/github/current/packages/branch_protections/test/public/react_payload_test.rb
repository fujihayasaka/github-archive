# typed: true
# frozen_string_literal: true

require "test_helper"

class RulesEngine::ReactPayloadTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper

  class MockRefLoader < Git::Ref::Loader
    def initialize(repository, prefix, data)
      super(repository)

      refs = data.map do |ref, sha|
        ["refs/#{prefix}/#{ref}", sha]
      end

      build_and_cache_ref_data(refs)
    end
  end

  fixtures do
    @org_admin = create(:user)
    @org = create(:business_plus_org, admin: @org_admin)
    @repo = create(:repository, owner: @org)
  end

  setup do
    GitHub.flipper[:ruleset_skip_condition_count].disable
  end

  context "ruleset JSON payload" do
    test "includes warning affected target message when too many repositories" do
      @org.repositories.stubs(:count).returns(100_000)

      ruleset = create(:repository_ruleset, source: @org)
      json = RulesEngine::ReactPayload.ruleset_json(ruleset, viewing_source: @org)

      if @org.feature_enabled?(:property_ruleset_async_preview)
        assert_nil json[:matches]
      else
        assert_match /unable to display affected targets .* repositories in this organization/i, json[:matches]
      end
    end

    test "includes all matching repositories" do
      repositories = [
        create(:repository, name: "test-repo-1", owner: @org),
        create(:repository, name: "test-repo-2", owner: @org)
      ]

      ruleset = create(:repository_ruleset, source: @org)
      ruleset.conditions << create(:repository_rule_condition, :targets_repo, repo_name: "test-repo-*", repository_ruleset: ruleset)
      json = RulesEngine::ReactPayload.ruleset_json(ruleset, viewing_source: @org)

      if @org.feature_enabled?(:property_ruleset_async_preview)
        assert_nil json[:matches]
      else
        assert_equal 2, json[:matches].size
        assert_same_elements repositories.sort_by(&:name).map(&:name), json[:matches]
      end
    end

    test "excludes repository matches when there are no repository conditions" do
      ruleset = create(:repository_ruleset, source: @org)
      json = RulesEngine::ReactPayload.ruleset_json(ruleset, viewing_source: @org)

      if @org.feature_enabled?(:property_ruleset_async_preview)
        assert_nil json[:matches]
      else
        assert_empty json[:matches]
      end

      ruleset.conditions << create(:repository_rule_condition, :targets_branch, repository_ruleset: ruleset)
      json = RulesEngine::ReactPayload.ruleset_json(ruleset, viewing_source: @org)

      if @org.feature_enabled?(:property_ruleset_async_preview)
        assert_nil json[:matches]
      else
        assert_empty json[:matches]
      end
    end

    test "includes warning affected target message when too many branches" do
      @repo.heads.stubs(:size).returns(100_000)

      ruleset = create(:repository_ruleset, source: @repo)
      json = RulesEngine::ReactPayload.ruleset_json(ruleset, viewing_source: @repo)

      assert_match /unable to display affected targets .* branches in this repository/i, json[:matches]
    end

    test "includes all matching branches" do
      branches = (1..100).map { |i| ["branch-#{i}", create_random_sha] }
      @repo.stubs(:heads).returns(Git::Ref::Collection.new(loader: MockRefLoader.new(@repo, "heads", branches), prefix: "refs/heads/"))

      ruleset = create(:repository_ruleset, :targets_branch, qualified_ref_name: "refs/heads/branch-1", source: @repo)
      json = RulesEngine::ReactPayload.ruleset_json(ruleset, viewing_source: @repo)

      assert_equal 1, json[:matches].size
      assert_same_elements [T.must(branches.first).first], json[:matches]
    end

    test "excludes branch matches when there are no ref conditions" do
      branches = (1..100).map { |i| ["tag-#{i}", create_random_sha] }
      @repo.stubs(:heads).returns(Git::Ref::Collection.new(loader: MockRefLoader.new(@repo, "heads", branches), prefix: "refs/heads/"))

      ruleset = create(:repository_ruleset, source: @repo)
      json = RulesEngine::ReactPayload.ruleset_json(ruleset, viewing_source: @repo)

      assert_empty json[:matches]
    end

    test "includes warning affected target message when too many tags" do
      @repo.tags.stubs(:size).returns(100_000)

      ruleset = create(:repository_ruleset, :example_ruleset, target: :tag, source: @repo)
      json = RulesEngine::ReactPayload.ruleset_json(ruleset, viewing_source: @repo)

      assert_match /unable to display affected targets .* tags in this repository/i, json[:matches]
    end

    test "includes all matching tags" do
      tags = (1..100).map { |i| ["tag-#{i}", create_random_sha] }
      @repo.stubs(:tags).returns(Git::Ref::Collection.new(loader: MockRefLoader.new(@repo, "tags", tags), prefix: "refs/tags/"))

      ruleset = create(:repository_ruleset, target: :tag, source: @repo)
      ruleset.conditions << create(:repository_rule_condition, :targets_tag, tag_name: "refs/tags/tag-2", repository_ruleset: ruleset)
      json = RulesEngine::ReactPayload.ruleset_json(ruleset, viewing_source: @repo)

      assert_equal 1, json[:matches].size
      assert_same_elements [T.must(tags.second).first], json[:matches]
    end

    test "excludes tag matches when there are no ref conditions" do
      tags = (1..100).map { |i| ["tag-#{i}", create_random_sha] }
      @repo.stubs(:tags).returns(Git::Ref::Collection.new(loader: MockRefLoader.new(@repo, "tags", tags), prefix: "refs/tags/"))

      ruleset = create(:repository_ruleset, target: :tag, source: @repo)
      json = RulesEngine::ReactPayload.ruleset_json(ruleset, viewing_source: @repo)

      assert_empty json[:matches]
    end

    test "returns inherited rulesets targeting a repository" do
      ruleset = create(:repository_ruleset, source: @org)
      create(:repository_rule_condition, :targets_repo, repo_name: "*", repository_ruleset: ruleset)

      inherited_ruleset = RulesEngine::ReactPayload.ruleset_json(ruleset, viewing_source: @repo)
      refute_nil inherited_ruleset
      assert_equal ruleset.id, inherited_ruleset[:id]
    end
  end

  test "excludes matching targets when feature flag is enabled" do
    GitHub.flipper[:ruleset_skip_condition_count].enable

    repositories = [
      create(:repository, name: "test-repo-1", owner: @org),
      create(:repository, name: "test-repo-2", owner: @org)
    ]

    ruleset = create(:repository_ruleset, source: @org)
    ruleset.conditions << create(:repository_rule_condition, :targets_repo, repo_name: "test-repo-*", repository_ruleset: ruleset)
    json = RulesEngine::ReactPayload.ruleset_json(ruleset, viewing_source: @org)

    if @org.feature_enabled?(:property_ruleset_async_preview)
      assert_nil json[:matches]
    else
      assert_match "", json[:matches]
    end
  end
end
