# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexSidePanel::IssueItemTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  fixtures do
    @owner = create(:user, :verified)
    @repo = create(:repository, owner: @owner)
    @issue = create(:issue, repository: @repo)
    @memex = create(:memex_project, owner: @owner)
    @memex_project_item = create(:memex_project_item, memex_project: @memex, content: @issue, repository: @repo)

    @private_repo = create(:private_repository)
    @private_repo_issue = create(:issue, repository: @private_repo)
    @private_memex_project_item = create(:memex_project_item, memex_project: @memex, content: @private_repo_issue, repository: @private_repo)
  end

  context "#show" do
    test "returns a hash of information about the issue" do
      issue_item = MemexSidePanel::IssueItem.new(@issue.id, repository_id: @repo.id, memex_project: @memex,
        current_user: @owner, cap_filter: cap_authorizing_filter)

      result = issue_item.show(omit_comments: false, omit_capabilities: false)

      assert_instance_of Hash, result

      refute_nil result[:title]
      assert_equal @issue.title, result[:title][:raw]

      refute_nil result[:itemKey]
      assert_equal "issue", result[:itemKey][:kind]
      assert_equal @issue.id, result[:itemKey][:itemId]
      assert_equal @repo.id, result[:itemKey][:repositoryId]

      refute_nil result[:description]
      assert_equal @issue.body, result[:description][:body]
      assert_nil result[:description][:editedAt]

      assert_equal @issue.url, result[:url]
      assert_equal @issue.created_at, result[:createdAt]
      assert_equal @issue.updated_at, result[:updatedAt]
      assert_equal @issue.number, result[:issueNumber]
      assert_equal @repo.name, result[:repositoryName]
      assert_empty result[:assignees]
      assert_empty result[:labels]
      assert_nil result[:milestone]
      assert_equal @memex_project_item.id, result[:projectItemId]
      assert_empty result[:comments]
      assert_same_elements %w[editTitle editDescription react comment close reopen],
        result[:capabilities]
      assert_predicate result[:liveUpdateChannel], :present?

      refute_nil result[:repository]
      assert result[:repository][:isPublic]
      refute result[:repository][:isArchived]
      assert result[:repository][:hasIssues]

      refute_nil result[:state]
      assert_equal "open", result[:state][:state]
      assert_nil result[:state][:stateReason]

      refute_nil result[:user]
      assert_equal @issue.user_id, result[:user][:id]
      assert_equal "User", result[:user][:type]
      assert_equal @issue.user.display_login, result[:user][:login]
    end
  end

  context "#suggestions_target" do
    test "errors for invalid suggestion type" do
      issue_item = MemexSidePanel::IssueItem.new(@issue.id, repository_id: @repo.id, memex_project: @memex,
        current_user: @owner, cap_filter: cap_authorizing_filter)

      error = assert_raises(MemexSidePanel::Item::InvalidParamsError) do
        issue_item.suggestions_target("foo")
      end

      assert_equal "Suggestion type must be `assignees`, `labels`, or `milestones`", error.message
    end

    test "returns the issue for a viewer who has permission" do
      issue_item = MemexSidePanel::IssueItem.new(@issue.id, repository_id: @repo.id, memex_project: @memex,
        current_user: @owner, cap_filter: cap_authorizing_filter)

      assert_equal @issue, issue_item.suggestions_target("assignees")
      assert_equal @issue, issue_item.suggestions_target("labels")
      assert_equal @issue, issue_item.suggestions_target("milestones")
    end

    test "errors for a viewer who lacks permission" do
      rando = create(:user)

      issue_item = MemexSidePanel::IssueItem.new(@issue.id, repository_id: @repo.id, memex_project: @memex,
        current_user: rando, cap_filter: cap_authorizing_filter)

      assert_raises(MemexSidePanel::Item::PermissionError) { issue_item.suggestions_target("assignees") }
      assert_raises(MemexSidePanel::Item::PermissionError) { issue_item.suggestions_target("labels") }
      assert_raises(MemexSidePanel::Item::PermissionError) { issue_item.suggestions_target("milestones") }
    end
  end

  context "#resource_for_conditional_access" do
    test "returns the issue" do
      issue_item = MemexSidePanel::IssueItem.new(@issue.id, repository_id: @repo.id, memex_project: @memex,
        current_user: @owner, cap_filter: cap_authorizing_filter)
      assert_equal @issue, issue_item.resource_for_conditional_access
    end
  end

  context "#target_for_conditional_access" do
    test "returns the repository owner" do
      other_user = create(:user)

      issue_item = MemexSidePanel::IssueItem.new(@issue.id, repository_id: @repo.id, memex_project: @memex,
        current_user: other_user, cap_filter: cap_authorizing_filter)

      assert_equal @owner, issue_item.target_for_conditional_access
    end
  end

  context "#viewer_can_read?" do
    test "returns true for issue owner" do
      issue_item = MemexSidePanel::IssueItem.new(
        @issue.id,
        repository_id: @repo.id,
        memex_project: @memex,
        current_user: @issue.user,
        cap_filter: cap_authorizing_filter
      )

      assert issue_item.viewer_can_read?
    end

    test "returns true for public issue and anonymous user" do
      issue_item = MemexSidePanel::IssueItem.new(
        @issue.id,
        repository_id: @repo.id,
        memex_project: @memex,
        current_user: nil,
        cap_filter: cap_authorizing_filter
      )

      assert issue_item.viewer_can_read?
    end

    test "returns false for private issue and anonymous user" do
      issue_item = MemexSidePanel::IssueItem.new(
        @private_repo_issue.id,
        repository_id: @private_repo.id,
        memex_project: @memex,
        current_user: nil,
        cap_filter: cap_authorizing_filter
      )

      refute issue_item.viewer_can_read?
    end
  end
end
