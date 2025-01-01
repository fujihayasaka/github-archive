# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionTimeline::SingleCommentRenderContextTest < GitHub::TestCase
  fixtures do
    @repo_owner = create(:verified_user)
    @public_repo = create(:repository, owner: @repo_owner, has_discussions: true)
    @discussion = create(:discussion, repository: @public_repo)
    @comment = create(:discussion_comment, discussion: @discussion)
  end

  context "#reply_threads_by_parent_id" do
    test "returns a single, empty thread rooted at comment" do
      render_context = DiscussionTimeline::SingleCommentRenderContext.new(
        @discussion,
        @comment,
        viewer: @repo_owner
      )

      threads = render_context.reply_threads_by_parent_id
      assert_equal 1, threads.size
      thread = threads[@comment.id]
      assert_equal @comment, thread.parent
      assert_empty thread.replies
      assert_equal 0, thread.older_count
      assert_equal 0, thread.newer_count
    end

    test "fetches a page of comments if an anchor and back/forward page numbers are provided" do
      older_comments = create_list(:discussion_comment, 3, discussion: @discussion, parent_comment: @comment)
      newer_comments = create_list(:discussion_comment, 5 + DiscussionTimeline::DEFAULT_INITIAL_REPLY_COUNT,
        discussion: @discussion, parent_comment: @comment)

      render_context = DiscussionTimeline::SingleCommentRenderContext.new(
        @discussion,
        @comment,
        viewer: @repo_owner,
        nested_comments_per_page: 2,
        anchor_id: newer_comments.first.id,
        back_page: 1,
        forward_page: 2,
      )

      expected_comments = older_comments.last(2) +
        newer_comments.first(DiscussionTimeline::DEFAULT_INITIAL_REPLY_COUNT + 4)

      threads = render_context.reply_threads_by_parent_id
      assert_equal 1, threads.size
      thread = threads[@comment.id]
      assert_equal @comment, thread.parent
      assert_equal expected_comments, thread.replies
      assert_equal 1, thread.older_count
      assert_equal 1, thread.newer_count
    end
  end

  context "#renderables" do
    test "returns passed in comment" do
      render_context = DiscussionTimeline::SingleCommentRenderContext.new(
        @discussion,
        @comment,
        viewer: @repo_owner
      )

      expected = [
        [@comment]
      ]

      assert_equal expected, render_context.renderables
    end
  end

  context "#timeline_items" do
    test "returns passed in comment" do
      render_context = DiscussionTimeline::SingleCommentRenderContext.new(
        @discussion,
        @comment,
        viewer: @repo_owner
      )

      expected = [
        @comment
      ]

      assert_equal expected, render_context.timeline_items
    end
  end

  context "#max_number_of_nested_comments" do
    context "when the pagination feature is enabled" do
      test "returns nil when page is provided and per_page is nil" do
        render_context = DiscussionTimeline::SingleCommentRenderContext.new(
          @discussion,
          @comment,
          viewer: @repo_owner,
          nested_comments_page: 1,
        )

        assert_nil render_context.max_number_of_nested_comments
      end

      test "returns nil when per_page is provided and page is nil" do
        render_context = DiscussionTimeline::SingleCommentRenderContext.new(
          @discussion,
          @comment,
          viewer: @repo_owner,
          nested_comments_per_page: 4,
        )

        assert_nil render_context.max_number_of_nested_comments
      end

      test "returns page * per_page when page and per_page are provided" do
        render_context = DiscussionTimeline::SingleCommentRenderContext.new(
          @discussion,
          @comment,
          viewer: @repo_owner,
          nested_comments_per_page: 4,
          nested_comments_page: 3,
        )

        assert_equal 4 * 3, render_context.max_number_of_nested_comments
      end
    end

    context "when the pagination feature is disabled" do
      test "it returns nil" do
        render_context = DiscussionTimeline::SingleCommentRenderContext.new(
          @discussion,
          @comment,
          viewer: @repo_owner
        )

        assert_nil render_context.max_number_of_nested_comments
      end
    end
  end
end
