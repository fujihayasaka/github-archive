# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexSidePanel::DraftIssueItemTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, :verified)
    @repo = create(:repository, owner: @owner)
    @draft_issue = create(:draft_issue, assignees: [@owner])
    @memex = create(:memex_project, owner: @owner)
    @memex_project_item = create(:memex_project_item, memex_project: @memex, content: @draft_issue, repository: @repo,
      draft_issue: @draft_issue)
  end

  context "#show" do
    test "returns a hash of information about the issue" do
      draft_issue_item = MemexSidePanel::DraftIssueItem.new(@memex_project_item.id, memex_project: @memex,
        current_user: @owner)

      result = draft_issue_item.show(omit_comments: false, omit_capabilities: true)

      assert_instance_of Hash, result

      refute_nil result[:title]
      assert_equal @draft_issue.title, result[:title][:raw]

      refute_nil result[:itemKey]
      assert_equal "project_draft_issue", result[:itemKey][:kind]
      assert_equal @memex_project_item.id, result[:itemKey][:projectItemId]

      refute_nil result[:description]
      assert_nil result[:description][:body]
      assert_equal @memex_project_item.updated_at, result[:description][:editedAt]

      assert_equal @memex_project_item.created_at, result[:createdAt]
      assert_equal @memex_project_item.updated_at, result[:updatedAt]
      assert_equal @memex_project_item.id, result[:projectItemId]
      assert_nil result[:capabilities]
      assert_predicate result[:liveUpdateChannel], :present?

      assert_equal 1, result[:assignees].size
      assert_equal @owner.id, result[:assignees].first[:id]

      refute_nil result[:state]
      assert_equal "draft", result[:state][:state]

      refute_nil result[:user]
      assert_equal @memex_project_item.creator_id, result[:user][:id]
      assert_equal @memex_project_item.creator.display_login, result[:user][:login]
    end
  end

  context "#resource_for_conditional_access" do
    test "returns the project board" do
      draft_issue_item = MemexSidePanel::DraftIssueItem.new(@memex_project_item.id, memex_project: @memex,
        current_user: @owner)
      assert_equal @memex, draft_issue_item.resource_for_conditional_access
    end
  end

  context "#target_for_conditional_access" do
    test "returns the project board owner" do
      other_user = create(:user)

      draft_issue_item = MemexSidePanel::DraftIssueItem.new(@memex_project_item.id, memex_project: @memex,
        current_user: other_user)

      assert_equal @owner, draft_issue_item.target_for_conditional_access
    end
  end
end
