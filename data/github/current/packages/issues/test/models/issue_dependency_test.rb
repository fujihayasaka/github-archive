# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @source_repository = create(:repository)
    @target_repository = create(:repository)
    @source_issue = create(:issue, repository: @source_repository, user: @user)
    @target_issue = create(:issue, repository: @target_repository, user: @user)
  end

  test "creates blocked by issue dependency" do
    issue_dependency = IssueDependency.create!(
      source_issue: @source_issue,
      target_issue: @target_issue,
      actor: @user,
      dependency_type: :blocked_by
    )

    assert_equal issue_dependency, saved_issue_dependency = IssueDependency.find(T.must(issue_dependency.id))
    assert_equal @source_issue, saved_issue_dependency.source_issue
    assert_equal @source_repository, saved_issue_dependency.source_repository
    assert_equal @target_issue, saved_issue_dependency.target_issue
    assert_equal @target_repository, saved_issue_dependency.target_repository
    assert_equal @user, saved_issue_dependency.actor
    assert_equal "blocked_by", saved_issue_dependency.dependency_type
  end

  test "creates blocking issue dependency" do
    issue_dependency = IssueDependency.create!(
      source_issue: @source_issue,
      target_issue: @target_issue,
      actor: @user,
      dependency_type: :blocking
    )

    assert_equal issue_dependency, saved_issue_dependency = IssueDependency.find(T.must(issue_dependency.id))
    assert_equal @source_issue, saved_issue_dependency.source_issue
    assert_equal @source_repository, saved_issue_dependency.source_repository
    assert_equal @target_issue, saved_issue_dependency.target_issue
    assert_equal @target_repository, saved_issue_dependency.target_repository
    assert_equal @user, saved_issue_dependency.actor
    assert_equal "blocking", saved_issue_dependency.dependency_type
  end

  context "#csv_column_value" do
    test "returns name with display owner" do
      assert_equal @source_repository.name_with_display_owner, @source_repository.csv_column_value
    end
  end

  context "validations" do
    test "source and target cannot be the same" do
      issue_dependency = IssueDependency.build(
        source_issue: @source_issue,
        target_issue: @source_issue,
        actor: @user,
        dependency_type: :blocked_by
      )

      refute issue_dependency.valid?
      assert issue_dependency.errors.messages[:target_issue_id].first, "cannot be the same as the source issue"
    end

    test "cannot create conflicting dependencies" do
      blocked_by = IssueDependency.create!(
        source_issue: @source_issue,
        target_issue: @target_issue,
        actor: @user,
        dependency_type:
        :blocked_by
      )
      assert blocked_by.valid?

      blocking = IssueDependency.build(
        source_issue: @source_issue,
        target_issue: @target_issue,
        actor: @user,
        dependency_type: :blocking
      )

      refute blocking.valid?
      assert blocking.errors.messages[:dependency_type].first, "cannot have both blocking and blocked_by for the target issue"
    end

    test "cannot use pull request for source issue" do
      pull = create(:pull_request, :disable_disk_access)
      issue_dependency = IssueDependency.build(
        source_issue: pull.issue.reload,
        target_issue: @target_issue,
        actor: @user,
        dependency_type: :blocked_by
      )

      refute issue_dependency.valid?
      assert issue_dependency.errors.messages[:source_issue_id].first, "may only be an issue"
    end

    test "cannot use pull request for target issue" do
      pull = create(:pull_request, :disable_disk_access)
      issue_dependency = IssueDependency.build(
        source_issue: @source_issue,
        target_issue: pull.issue.reload,
        actor: @user,
        dependency_type: :blocked_by
      )

      refute issue_dependency.valid?
      assert issue_dependency.errors.messages[:target_issue_id].first, "may only be an issue"
    end
  end
end
