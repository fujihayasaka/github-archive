# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionTimeline::PermissionPreloaderTest < GitHub::TestCase
  fixtures do
    @repo_owner = create(:verified_user)
    @public_repo = create(:repository, owner: @repo_owner, has_discussions: true)
    @discussion = create(:discussion, :question, repository: @public_repo)
    @discussion_comment = create(:discussion_comment, discussion: @discussion)
  end

  context "#can?" do
    test "logged out user does not fetch permissions and always returns false" do
      permissions = DiscussionTimeline::PermissionPreloader.new(
        discussion: @discussion,
        comments: [],
        viewer: nil,
        can_interact_with_repo: true
      )

      permissions.stubs(:permissions).never

      refute permissions.can?(:react, @discussion)
    end

    test "fetches permissions for logged in user" do
      permissions = DiscussionTimeline::PermissionPreloader.new(
        discussion: @discussion,
        comments: [@discussion_comment],
        viewer: @repo_owner,
        can_interact_with_repo: true
      )

      assert permissions.can?(:react, @discussion)
      assert permissions.can?(:react, @discussion_comment)
    end
  end

  test "does not load reaction permissions when skip_reaction_permissions is true" do
    @discussion.expects(:async_reactable_by?).never
    @discussion_comment.expects(:async_reactable_by?).never

    permissions = DiscussionTimeline::PermissionPreloader.new(
      discussion: @discussion,
      comments: [@discussion_comment],
      viewer: @repo_owner,
      can_interact_with_repo: true,
      skip_reaction_permissions: true
    )

    permissions.preload
  end

  test "loads reaction permissions when skip_reaction_permissions is false" do
    @discussion.expects(:async_reactable_by?).once
    @discussion_comment.expects(:async_reactable_by?).once

    permissions = DiscussionTimeline::PermissionPreloader.new(
      discussion: @discussion,
      comments: [@discussion_comment],
      viewer: @repo_owner,
      can_interact_with_repo: true,
      skip_reaction_permissions: false
    )

    permissions.preload
  end

  test "does not load mark answer permissions when no comments are passed" do
    @discussion.expects(:async_can_toggle_answer?).never

    permissions = DiscussionTimeline::PermissionPreloader.new(
      discussion: @discussion,
      comments: [],
      can_interact_with_repo: true,
      viewer: @repo_owner
    )

    permissions.preload

    refute permissions.can?(:mark_answer, @discussion), "Can't mark answer if no comments"
  end

  test "does not load mark answer permissions when category doesn't support answers" do
    unanswerable_category = create(:discussion_category, repository: @discussion.repository, supports_mark_as_answer: false)
    @discussion.update!(category: unanswerable_category)
    @discussion.expects(:async_can_toggle_answer?).never

    permissions = DiscussionTimeline::PermissionPreloader.new(
      discussion: @discussion,
      comments: [@discussion_comment],
      can_interact_with_repo: true,
      viewer: @repo_owner
    )

    permissions.preload

    refute permissions.can?(:mark_answer, @discussion), "Can't mark answer if category doesn't support it"
  end

  test "loads mark answer permissions when comments are passed" do
    @discussion.expects(:async_can_toggle_answer?).once.returns(Promise.resolve(true))

    permissions = DiscussionTimeline::PermissionPreloader.new(
      discussion: @discussion,
      comments: [@discussion_comment],
      viewer: @repo_owner,
      can_interact_with_repo: true
    )

    permissions.preload

    assert permissions.can?(:mark_answer, @discussion), "Can mark answer if comments are passed"
  end

  test "loads label permissions" do
    @discussion.expects(:async_labelable_by?).once.returns(Promise.resolve(true))

    permissions = DiscussionTimeline::PermissionPreloader.new(
      discussion: @discussion,
      comments: [@discussion_comment],
      viewer: @repo_owner,
      can_interact_with_repo: true
    )

    permissions.preload

    assert permissions.can?(:edit_labels, @discussion), "Can edit discussion labels"
  end
end
