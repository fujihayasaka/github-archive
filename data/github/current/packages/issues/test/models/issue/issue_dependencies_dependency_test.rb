# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueDependenciesDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @source_repository = create(:repository)
    @target_repository = create(:repository)
    @source_issue = create(:issue, repository: @source_repository, user: @user)
    @target_issue = create(:issue, repository: @target_repository, user: @user)
  end

  context "blocked by" do
    test "creates blocked by dependency for an issue" do
      @source_issue.add_blocked_by!(@target_issue, @user)

      assert_equal 1, @source_issue.blocked_by_relations.length
      issue_dependency = @source_issue.blocked_by_relations.first
      assert_equal @source_issue, issue_dependency.source_issue
      assert_equal @source_repository, issue_dependency.source_repository
      assert_equal @target_issue, issue_dependency.target_issue
      assert_equal @target_repository, issue_dependency.target_repository
      assert_equal @user, issue_dependency.actor
      assert_equal "blocked_by", issue_dependency.dependency_type

      assert_equal @source_issue.blocked_by.length, 1
      assert_equal @target_issue, @source_issue.blocked_by.first
    end
  end

  context "blocks" do
    test "creates blocks dependency for an issue" do
      @source_issue.add_blocking!(@target_issue, @user)

      assert_equal 1, @source_issue.blocking_relations.length
      issue_dependency = @source_issue.blocking_relations.first
      assert_equal @source_issue, issue_dependency.source_issue
      assert_equal @source_repository, issue_dependency.source_repository
      assert_equal @target_issue, issue_dependency.target_issue
      assert_equal @target_repository, issue_dependency.target_repository
      assert_equal @user, issue_dependency.actor
      assert_equal "blocking", issue_dependency.dependency_type

      assert_equal @source_issue.blocking.length, 1
      assert_equal @target_issue, @source_issue.blocking.first
    end
  end
end
