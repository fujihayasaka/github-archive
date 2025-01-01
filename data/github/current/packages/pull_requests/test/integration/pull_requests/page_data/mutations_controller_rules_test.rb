# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequests::PageData::MutationsControllerRulesTest < GitHub::IntegrationTestCase
  include PullRequestIntegrationTestHelpers
  include RepositoriesTestHelper

  fixtures do
    enable_feature_flag(:mergebox_react_partial)
    Spokesd.enable_spokesd

    @owner = create(:user)

    @org = create(:business_plus_organization, admin: @owner)
    @repo = create(:repository, owner: @org, from_example: :simple)
    @repo.add_member(@owner, action: :admin)
    @repo.allow_auto_merge(actor: @owner)

    @pull = create(:pull_request, :with_mergeable_head, repository: @repo, user: @owner)

    @ruleset = create(:repository_ruleset, :targets_branch, qualified_ref_name: "refs/heads/master", source: @repo)

    @rule_config = create(:repository_rule_configuration, repository_ruleset: @ruleset, rule_type: "commit_message_pattern", parameters: {
      operator: "starts_with",
      pattern: "Merge",
      negate: true
    })

    example_repo_snapshot
  end

  setup do
    example_repo_restore

    @page_data_path = "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data"
  end

  context "#enable_auto_merge" do
    test "returns success when commit parameters are valid" do
      as @owner

      @rule_config.update!(parameters: {
        operator: "regex",
        pattern: ".+",
      })

      post "#{@page_data_path}/enable_auto_merge", xhr: true

      assert_response :success
    end

    test "returns error when commit parameters violate metadata rules (blocked by other rules)" do
      # This is needed because the original implementation did not check for rule violations before requesting an auto merge
      enable_feature_flag(:rulesets_prx_merge_improvements)

      as @owner

      create(:repository_rule_configuration, :pull_request, repository_ruleset: @ruleset, required_approving_review_count: 1)

      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?

      post "#{@page_data_path}/enable_auto_merge", params: {
        commitTitle: "Merge pull request",
        commitMessage: "",
      }, xhr: true

      assert_response :unprocessable_entity

      assert_rule_error_message(response)
    end

    test "returns error when commit parameters violate metadata rules (clean merge)" do
      as @owner

      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?

      post "#{@page_data_path}/enable_auto_merge", params: {
        commitTitle: "Merge pull request",
        commitMessage: "",
      }, xhr: true

      assert_response :unprocessable_entity
      assert_rule_error_message(response)
    end

    test "returns error when default commit parameters violate metadata rules" do
      as @owner

      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?

      post "#{@page_data_path}/enable_auto_merge", xhr: true

      assert_response :unprocessable_entity
      assert_rule_error_message(response)
    end

    test "with merge queue, does not return error for squash merge if default merge message meets requirements", skip_if_feature_disabled: :pass_merge_queue_merge_method do
      @repo.set_squash_merge_commit_title_setting(setting: "PR_TITLE", actor: @owner)
      @pull.issue.update(title: "resolves #1")
      ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo)
      create(:repository_rule_configuration, :merge_queue, repository_ruleset: ruleset, merge_method: "squash")
      create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "commit_message_pattern", parameters: {
        operator: "contains",
        pattern: "resolves"
      })
      ruleset.save!
      assert @repo.merge_queue_for(branch: @repo.default_branch)
      as @owner

      enable_feature_flag(:rulesets_prx_merge_improvements)

      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?

      post "#{@page_data_path}/enable_auto_merge", params: {
        mergeMethod: "group",
        commitTitle: nil,
        commitMessage: nil,
      }, xhr: true

      assert_response :success
      # TODO: Ensure the PR is queued and not just that auto merge is enabled
      # See: https://github.com/github/repos/issues/14126
      assert @pull.reload.auto_merge_request
    end

    test "with merge queue, returns error for squash merge if default merge message does not meet requirements", skip_if_feature_disabled: :pass_merge_queue_merge_method do
      @repo.set_squash_merge_commit_title_setting(setting: "PR_TITLE", actor: @owner)
      ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo)
      create(:repository_rule_configuration, :merge_queue, repository_ruleset: ruleset, merge_method: "squash")
      create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "commit_message_pattern", parameters: {
        operator: "contains",
        pattern: "resolves"
      })
      create(:merge_queue, repository: @pull.repository)
      as @owner

      enable_feature_flag(:rulesets_prx_merge_improvements)

      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?

      post "#{@page_data_path}/enable_auto_merge", params: {
        mergeMethod: "group",
        commitTitle: nil,
        commitMessage: nil,
      }, xhr: true

      assert_response :unprocessable_entity
      json_response = JSON.parse(response.body)
      assert_equal  "Merging was blocked due to commit metadata restriction violation errors.", json_response["error"]
      expected_metadata = { "ruleErrors" => ["Commit message must contain a matching pattern: resolves"] }
      assert_equal expected_metadata, json_response["metadata"]
      refute @pull.reload.auto_merge_request
    end
  end

  context "#merge" do
    [:merge, :rebase, :squash].each do |merge_method|
      test "returns success when rules are not violated (#{merge_method})" do
        as @owner

        @rule_config.destroy!
        @rule_config = create(:repository_rule_configuration, :pull_request, repository_ruleset: @ruleset)

        assert @pull.create_merge_commit
        assert @pull.git_merges_cleanly?

        post "#{@page_data_path}/merge", params: {
          mergeMethod: merge_method,
        }, xhr: true

        assert_response :success
        assert @pull.reload.merged?
      end

      test "returns error when rules are violated (#{merge_method})" do
        @rule_config.destroy!
        @rule_config = create(:repository_rule_configuration, :update, repository_ruleset: @ruleset)

        as @owner

        assert @pull.create_merge_commit
        assert @pull.git_merges_cleanly?

        post "#{@page_data_path}/merge", params: {
          mergeMethod: merge_method,
        }, xhr: true

        assert_response :unprocessable_entity
        json_response = JSON.parse(response.body)
        assert_equal  "Merging was blocked due to rule violation errors.", json_response["error"]
        assert_nil json_response["message"]

        refute @pull.reload.merged?
      end

      test "returns error when commit parameters violate metadata rules (#{merge_method})" do
        as @owner

        enable_feature_flag(:rulesets_prx_merge_improvements)

        ##
        # The current implementation does not support validating emails from the merge box. This is needed to ensure
        # that these violations to assert that these errors are not returned to the user.
        create(:repository_rule_configuration, repository_ruleset: @ruleset, rule_type: "commit_author_email_pattern", parameters: {
          operator: "ends_with",
          pattern: "fake_email"
        })

        assert @pull.create_merge_commit
        assert @pull.git_merges_cleanly?

        post "#{@page_data_path}/merge", params: {
          mergeMethod: merge_method,
          commitTitle: "Merge pull request",
          commitMessage: "",
        }, xhr: true

        assert_response :unprocessable_entity
        assert_rule_error_message(response)

        refute @pull.reload.merged?
      end

      test "rejects empty commit messages that violate metadata rules (#{merge_method})" do
        as @owner

        enable_feature_flag(:rulesets_prx_merge_improvements)

        ##
        # The current implementation does not support validating emails from the merge box. This is needed to ensure
        # that these violations to assert that these errors are not returned to the user.
        create(:repository_rule_configuration, repository_ruleset: @ruleset, rule_type: "commit_author_email_pattern", parameters: {
          operator: "ends_with",
          pattern: "fake_email"
        })

        assert @pull.create_merge_commit
        assert @pull.git_merges_cleanly?

        post "#{@page_data_path}/merge", params: {
          mergeMethod: merge_method,
          commitTitle: "",
          commitMessage: "",
        }, xhr: true

        assert_response :unprocessable_entity
        assert_rule_error_message(response)

        refute @pull.reload.merged?
      end unless merge_method == :rebase
    end

    test "skip commit message validation for rebases" do
      as @owner

      enable_feature_flag(:rulesets_prx_merge_improvements)

      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?

      post "#{@page_data_path}/merge", params: {
        mergeMethod: "rebase",
        commitTitle: "",
        commitMessage: "",
      }, xhr: true

      assert_response :success
      assert @pull.reload.merged?
    end
  end

  private

  def assert_rule_error_message(response)
    json_response = JSON.parse(response.body)

    if GitHub.flipper[:rulesets_prx_merge_improvements].enabled?
      assert_equal  "Merging was blocked due to commit metadata restriction violation errors.", json_response["error"]
      expected_metadata = { "ruleErrors" => ["Commit message must not start with a matching pattern: Merge"] }
      assert_equal expected_metadata, json_response["metadata"]
    else
      assert_equal  "Merging was blocked due to rule violation errors.", json_response["error"]
      assert_nil json_response["metadata"]
    end
  end
end
