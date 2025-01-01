# typed: true
# frozen_string_literal: true

require "test_helper"

class OrgBlockableTest < GitHub::TestCase
  fixtures do
    @comment = create(:issue_comment)

    @org = create(:organization)
    @org_member = create(:user)
    @org.add_admin(@org_member)
    @org_owned_repo = create(:repository, owner: @org)
    @org_issue = create(:issue, repository: @org_owned_repo)
    @org_collab = create(:user)
    @org_owned_repo.add_member(@org_collab)
    @org_owned_comment = create(:issue_comment, issue: @org_issue)
  end

  test "is OrgBlockable" do
    assert CommitComment.new.is_a? OrgBlockable
    assert Issue.new.is_a? OrgBlockable
    assert IssueComment.new.is_a? OrgBlockable
    assert PullRequest.new.is_a? OrgBlockable
    assert PullRequestReview.new.is_a? OrgBlockable
    assert PullRequestReviewComment.new.is_a? OrgBlockable
  end

  context "#async_viewer_can_block_from_org?" do
    test "non-org owned always returns false" do
      refute @comment.viewer_can_block_from_org?(@comment.user)
      refute @comment.viewer_can_block_from_org?(@comment.repository.owner)
    end

    test "user without permissions returns false" do
      refute @org_owned_comment.viewer_can_block_from_org?(create(:user))
      refute @org_owned_comment.viewer_can_block_from_org?(create(:staff_admin_user))
    end

    test "user who created the content cannot be blocked by themselves" do
      refute @org_owned_comment.viewer_can_block_from_org?(@org_owned_comment.user)
    end

    test "user who is already blocked cannot be blocked" do
      @org.block(@org_owned_comment.user)

      refute @org_owned_comment.viewer_can_block_from_org?(@org_member)
      refute @org_owned_comment.viewer_can_block_from_org?(@org_collab)
    end

    test "user with permissions returns true" do
      assert @org_owned_comment.viewer_can_block_from_org?(@org_member)
      refute @org_owned_comment.viewer_can_block_from_org?(@org_collab)
    end

    if GitHub.user_abuse_mitigation_enabled?
      test "returns true for org moderator" do
        moderator = create(:user)
        @org.add_member(moderator)
        @org.moderation.add_moderator(moderator, actor: @org.owner)
        assert @org_owned_comment.viewer_can_block_from_org?(moderator)
      end
    end

    test "deleted user returns false" do
      @org_owned_comment.user.destroy
      @org_owned_comment.reload

      assert_nil @org_owned_comment.user

      refute @org_owned_comment.viewer_can_block_from_org?(@org_member)
      refute @org_owned_comment.viewer_can_block_from_org?(@org_collab)
    end

    test "member of org returns false" do
      new_org_member = create(:user)
      @org.add_member(new_org_member)
      @org_owned_comment.update_attribute(:user, @org_member)
      @org_owned_comment.reload

      assert_equal @org_owned_comment.user, @org_member

      refute @org_owned_comment.viewer_can_block_from_org?(new_org_member)
    end
  end

  context "#async_viewer_can_unblock_from_org?" do
    test "non-org owned always returns false" do
      @org.block(@org_owned_comment.user)

      refute @comment.viewer_can_unblock_from_org?(@comment.user)
      refute @comment.viewer_can_unblock_from_org?(@comment.repository.owner)
    end

    test "user without permissions returns false" do
      @org.block(@org_owned_comment.user)

      refute @org_owned_comment.viewer_can_unblock_from_org?(create(:user))
      refute @org_owned_comment.viewer_can_unblock_from_org?(create(:staff_admin_user))
    end

    test "user who created the content cannot unblock themselves" do
      @org.block(@org_owned_comment.user)

      refute @org_owned_comment.viewer_can_unblock_from_org?(@org_owned_comment.user)
    end

    test "user must be blocked to be unblocked" do
      refute @org_owned_comment.viewer_can_unblock_from_org?(@org_member)
      refute @org_owned_comment.viewer_can_unblock_from_org?(@org_collab)
    end

    test "user with permissions returns true" do
      @org.block(@org_owned_comment.user)

      assert @org_owned_comment.viewer_can_unblock_from_org?(@org_member)
      refute @org_owned_comment.viewer_can_unblock_from_org?(@org_collab)
    end


    if GitHub.user_abuse_mitigation_enabled?
      test "returns true for org moderator" do
        @org.block(@org_owned_comment.user)
        moderator = create(:user)
        @org.add_member(moderator)
        @org.moderation.add_moderator(moderator, actor: @org.owner)
        assert @org_owned_comment.viewer_can_unblock_from_org?(moderator)
      end
    end

    test "deleted user returns false" do
      @org.block(@org_owned_comment.user)
      @org_owned_comment.user.destroy
      @org_owned_comment.reload

      assert_nil @org_owned_comment.user

      refute @org_owned_comment.viewer_can_unblock_from_org?(@org_member)
      refute @org_owned_comment.viewer_can_unblock_from_org?(@org_collab)
    end
  end

end
