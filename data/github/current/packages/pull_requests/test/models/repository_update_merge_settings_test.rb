# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryUpdateMergeSettingsTest < GitHub::TestCase
  fixtures do
    @user = create(:paid_user)
    @repo = create(:private_repository, owner: @user)
  end

  test "allows modifying rebase setting" do
    assert_predicate @repo, :rebase_merge_allowed?
    assert_predicate @repo, :merge_commit_allowed?
    assert_predicate @repo, :squash_merge_allowed?

    @repo.update_merge_settings(@user, rebase_allowed: false)

    refute_predicate @repo, :rebase_merge_allowed?
    assert_predicate @repo, :merge_commit_allowed?
    assert_predicate @repo, :squash_merge_allowed?

    @repo.update_merge_settings(@user, rebase_allowed: true)

    assert_predicate @repo, :rebase_merge_allowed?
    assert_predicate @repo, :merge_commit_allowed?
    assert_predicate @repo, :squash_merge_allowed?
  end

  test "does not allow disabling all merge types" do
    assert_predicate @repo, :rebase_merge_allowed?
    assert_predicate @repo, :merge_commit_allowed?
    assert_predicate @repo, :squash_merge_allowed?

    @repo.update_merge_settings(@user, squash_allowed: false, merge_allowed: false)

    assert_predicate @repo, :rebase_merge_allowed?
    refute_predicate @repo, :merge_commit_allowed?
    refute_predicate @repo, :squash_merge_allowed?

    error = assert_raises Repository::PullRequestDependency::MergeMethodError do
      @repo.update_merge_settings(@user, rebase_allowed: false)
    end
    assert_equal :no_merge_method, error.reason
    assert_equal "Sorry, you need to allow at least one merge strategy.", error.message

    assert_predicate @repo, :rebase_merge_allowed?
    refute_predicate @repo, :merge_commit_allowed?
    refute_predicate @repo, :squash_merge_allowed?
  end

  test "does not allow updating squash merge title setting if squash merge strategy disabled" do
    assert_predicate @repo, :squash_merge_allowed?

    error = assert_raises Repository::PullRequestDependency::MergeMethodError do
      @repo.update_merge_settings(@user, squash_allowed: false, squash_merge_commit_title_setting: "PR_TITLE")
    end
    assert_equal :no_squash_merge_strategy, error.reason
  end

  test "does not allow updating merge title setting if merge strategy disabled" do
    assert_predicate @repo, :merge_commit_allowed?

    error = assert_raises Repository::PullRequestDependency::MergeMethodError do
      @repo.update_merge_settings(@user, merge_allowed: false, merge_commit_title_setting: "PR_TITLE")
    end
    assert_equal :no_merge_strategy, error.reason
  end

  test "does not allow invalid ccombinations of squash merge commit title and merge message settings" do
    error = assert_raises Repository::PullRequestDependency::MergeMethodError do
      @repo.update_merge_settings(@user, squash_merge_commit_message_setting: "PR_BODY", squash_merge_commit_title_setting: "COMMIT_OR_PR_TITLE")
    end
    assert_equal :invalid_squash_commit_setting_combo, error.reason

    error = assert_raises Repository::PullRequestDependency::MergeMethodError do
      @repo.update_merge_settings(@user, squash_merge_commit_message_setting: "BLANK", squash_merge_commit_title_setting: "COMMIT_OR_PR_TITLE")
    end
    assert_equal :invalid_squash_commit_setting_combo, error.reason

    error = assert_raises Repository::PullRequestDependency::MergeMethodError do
      @repo.update_merge_settings(@user, squash_merge_commit_message_setting: "BLANK")
    end
    assert_equal :invalid_squash_commit_setting_combo, error.reason

    error = assert_raises Repository::PullRequestDependency::MergeMethodError do
      @repo.update_merge_settings(@user, squash_merge_commit_message_setting: "PR_BODY")
    end
    assert_equal :invalid_squash_commit_setting_combo, error.reason
  end


  test "updated squash merge commit title and merge message settings with valid combinations" do
    @repo.update_merge_settings(@user, squash_merge_commit_message_setting: "COMMIT_MESSAGES", squash_merge_commit_title_setting: "PR_TITLE")

    assert_predicate @repo.reload, :squash_merge_commit_title_pr_title_enabled?
    assert_predicate @repo.reload, :squash_commit_message_commit_messages_enabled?

    @repo.update_merge_settings(@user, squash_merge_commit_message_setting: "BLANK", squash_merge_commit_title_setting: "PR_TITLE")

    assert_predicate @repo.reload, :squash_merge_commit_title_pr_title_enabled?
    assert_predicate @repo.reload, :squash_commit_message_blank_enabled?

    @repo.update_merge_settings(@user, squash_merge_commit_message_setting: "PR_BODY", squash_merge_commit_title_setting: "PR_TITLE")

    assert_predicate @repo.reload, :squash_merge_commit_title_pr_title_enabled?
    assert_predicate @repo.reload, :squash_commit_message_pr_body_enabled?

    @repo.update_merge_settings(@user, squash_merge_commit_message_setting: "COMMIT_MESSAGES", squash_merge_commit_title_setting: "COMMIT_OR_PR_TITLE")

    assert_predicate @repo.reload, :squash_merge_commit_title_commit_pr_title_enabled?
    assert_predicate @repo.reload, :squash_commit_message_commit_messages_enabled?

    @repo.update_merge_settings(@user, squash_merge_commit_title_setting: "PR_TITLE")

    assert_predicate @repo.reload, :squash_merge_commit_title_pr_title_enabled?
    assert_predicate @repo.reload, :squash_commit_message_commit_messages_enabled?
  end

  test "does not allow invalid combinations of merge commit title and merge message settings" do
    error = assert_raises Repository::PullRequestDependency::MergeMethodError do
      @repo.update_merge_settings(@user, merge_commit_message_setting: "PR_BODY", merge_commit_title_setting: "MERGE_MESSAGE")
    end
    assert_equal :invalid_merge_commit_setting_combo, error.reason

    error = assert_raises Repository::PullRequestDependency::MergeMethodError do
      @repo.update_merge_settings(@user, merge_commit_message_setting: "BLANK", merge_commit_title_setting: "MERGE_MESSAGE")
    end
    assert_equal :invalid_merge_commit_setting_combo, error.reason

    error = assert_raises Repository::PullRequestDependency::MergeMethodError do
      @repo.update_merge_settings(@user, merge_commit_message_setting: "PR_TITLE", merge_commit_title_setting: "PR_TITLE")
    end
    assert_equal :invalid_merge_commit_setting_combo, error.reason

    error = assert_raises Repository::PullRequestDependency::MergeMethodError do
      @repo.update_merge_settings(@user, merge_commit_title_setting: "PR_TITLE")
    end
    assert_equal :invalid_merge_commit_setting_combo, error.reason
  end

  test "updated merge commit title and merge message settings with valid combinations" do
    @repo.update_merge_settings(@user, merge_commit_message_setting: "PR_BODY", merge_commit_title_setting: "PR_TITLE")

    assert_predicate @repo.reload, :merge_commit_title_pr_title_enabled?
    assert_predicate @repo.reload, :merge_commit_message_pr_body_enabled?

    @repo.update_merge_settings(@user, merge_commit_message_setting: "BLANK", merge_commit_title_setting: "PR_TITLE")

    assert_predicate @repo.reload, :merge_commit_title_pr_title_enabled?
    assert_predicate @repo.reload, :merge_commit_message_blank_enabled?

    @repo.update_merge_settings(@user, merge_commit_message_setting: "PR_TITLE", merge_commit_title_setting: "MERGE_MESSAGE")

    assert_predicate @repo.reload, :merge_commit_title_merge_message_enabled?
    assert_predicate @repo.reload, :merge_commit_message_pr_title_enabled?
  end

  test "disallows merge commit to be the only enabled strategy, if there is at least one linear history branch protection rule" do
    @repo.protect_branch("master", creator: @repo.owner, required_linear_history: true, entry_point: :test_case)

    @repo.update_merge_settings(@user, merge_allowed: true, squash_allowed: true, rebase_allowed: false)
    assert_predicate @repo, :merge_commit_allowed?
    assert_predicate @repo, :squash_merge_allowed?
    refute_predicate @repo, :rebase_merge_allowed?

    error = assert_raises Repository::PullRequestDependency::MergeMethodError do
      @repo.update_merge_settings(@user, squash_allowed: false)
    end
    assert_equal :protected_branch_policy, error.reason
    assert_equal "Sorry, you need to allow either squash or rebase merge strategies, or both.", error.message
    assert_predicate @repo, :merge_commit_allowed?
    assert_predicate @repo, :squash_merge_allowed?
    refute_predicate @repo, :rebase_merge_allowed?
  end

  test "doesn't update auto-delete setting when no relevant option is passed" do
    @repo.allow_auto_deleting_branches(actor: @user)
    @repo.update_merge_settings(@user, squash_allowed: false)
    assert_predicate @repo, :delete_branch_on_merge?
  end

  test "doesn't update auto-merge setting when no relevant option is passed" do
    @repo.allow_auto_merge(actor: @user)
    @repo.update_merge_settings(@user, squash_allowed: false)
    assert_predicate @repo, :auto_merge_allowed?
  end

  test "disallows auto-merge when relevent option is present" do
    @repo.allow_auto_merge(actor: @user)
    assert_predicate @repo, :auto_merge_allowed?
    @repo.update_merge_settings(@user, auto_merge_allowed: false)
    refute_predicate @repo, :auto_merge_allowed?
  end
end
