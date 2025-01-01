# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryPullRequestDependencyTest < GitHub::TestCase
  include ResiliencyHelpers

  context "#async_allowable_merge_methods" do
    test "returns merge method settings" do
      repo = build_stubbed(:repository)
      repo.update_merge_settings(
        build_stubbed(:user),
        merge_allowed: true,
        rebase_allowed: true,
        squash_allowed: false,
      )

      allowable_merge_methods = repo.async_allowable_merge_methods.sync

      assert_equal(
        Repository::PullRequestDependency::MergeMethodSettings::Value::Allowed,
        allowable_merge_methods.merge_commit)
      assert_predicate allowable_merge_methods.merge_commit, :allowed?
      refute_predicate allowable_merge_methods.merge_commit, :error?

      assert_equal(
        Repository::PullRequestDependency::MergeMethodSettings::Value::Allowed,
        allowable_merge_methods.rebase_merge)
      assert_predicate allowable_merge_methods.rebase_merge, :allowed?
      refute_predicate allowable_merge_methods.rebase_merge, :error?

      assert_equal(
        Repository::PullRequestDependency::MergeMethodSettings::Value::Disallowed,
        allowable_merge_methods.squash_merge)
      refute_predicate allowable_merge_methods.squash_merge, :allowed?
      refute_predicate allowable_merge_methods.squash_merge, :error?
    end

    test "gracefully handles database errors" do
      skip if GitHub.enterprise?

      repo = build_stubbed(:repository)

      allowable_merge_methods = prevent_connections_to(ApplicationRecord::Mysql5, ApplicationRecord::Configurations) do
        repo.async_allowable_merge_methods.sync
      end

      assert_equal(
        Repository::PullRequestDependency::MergeMethodSettings::Value::LoadError,
        allowable_merge_methods.merge_commit)
      assert_predicate allowable_merge_methods.merge_commit, :error?
      refute_predicate allowable_merge_methods.merge_commit, :allowed?

      assert_equal(
        Repository::PullRequestDependency::MergeMethodSettings::Value::LoadError,
        allowable_merge_methods.rebase_merge)
      assert_predicate allowable_merge_methods.rebase_merge, :error?
      refute_predicate allowable_merge_methods.rebase_merge, :allowed?

      assert_equal(
        Repository::PullRequestDependency::MergeMethodSettings::Value::LoadError,
        allowable_merge_methods.squash_merge)
      assert_predicate allowable_merge_methods.squash_merge, :error?
      refute_predicate allowable_merge_methods.squash_merge, :allowed?
    end
  end

  test "raise MergeMethodError when merge_commit_title has invalid options" do
    repo = create(:repository)

    assert_raises Repository::PullRequestDependency::MergeMethodError do
      repo.validate_merge_settings_update!(merge_commit_title_setting: "PR_BODY")
    end
  end

  context "squash_merge_commit_title_setting" do
    test "raises a MergeMethodError when a conflicting configuration record exists" do
      repo = build_stubbed(:repository)
      user = build_stubbed(:user)

      Configuration::Entry.create!(target: repo,
        updater: user,
        name: Configurable::SquashMergeCommitTitle::KEY,
        value: Configurable::SquashMergeCommitTitle::COMMIT_OR_PR_TITLE,
        final: false
      )

      Configuration.any_instance.stubs(:find_or_initialize_entry_by_name).with(Configurable::SquashMergeCommitTitle::KEY).returns(
        Configuration::Entry.new(
          target: repo,
          updater: user,
          name: Configurable::SquashMergeCommitTitle::KEY,
          value: Configurable::SquashMergeCommitTitle::PR_TITLE
        )
      )

      error = assert_raises Repository::PullRequestDependency::MergeMethodError do
        repo.update_merge_settings(
          user,
          squash_merge_commit_title_setting: Configurable::SquashMergeCommitTitle::PR_TITLE,
        )
      end

      assert_equal error.message, "Sorry, there was a conflict in updating the squash merge commit title setting, please check the current settings and try again if it is incorrect."
      assert_equal error.reason, :conflicting_squash_merge_commit_title_configuration
    end
  end

  context "merge_allowed" do
    test "raises a MergeMethodError when a conflicting configuration record exists for disabling merge commits" do
      repo = build_stubbed(:repository)
      user = build_stubbed(:user)

      Configuration::Entry.create!(target: repo,
        updater: user,
        name: Configurable::MergeCommits::KEY,
        value: true,
        final: false
      )

      new_entry =
        Configuration::Entry.new(
          target: repo,
          updater: user,
          name: Configurable::MergeCommits::KEY,
          value: true
        )
      Configuration::Entry.const_get(:ActiveRecord_AssociationRelation).any_instance.stubs(:first_or_initialize).with(name: Configurable::MergeCommits::KEY).returns(new_entry)
      Configuration.any_instance.stubs(:find_or_initialize_entry_by_name).with(Configurable::MergeCommits::KEY).returns(new_entry)

      error = assert_raises Repository::PullRequestDependency::MergeMethodError do
        repo.update_merge_settings(
          user,
          merge_allowed: false,
        )
      end

      assert_equal error.message, "Sorry, there was a conflict in updating the merge commits disabled setting, please check the current settings and try again if it is incorrect."
      assert_equal error.reason, :conflicting_merge_commits_disabled_configuration
    end
  end
end
