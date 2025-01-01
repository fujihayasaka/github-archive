# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionCommentItemBatchTest < GitHub::TestCase
  fixtures do
    @discussion = create(:discussion)
    @repo = @discussion.repository
    @comment0, @comment1 = create_pair(:discussion_comment, discussion: @discussion, repository: @repo)
  end

  test "raises an exception if :items key is absent" do
    params = ActionController::Parameters.new({ nope: 123 })

    assert_raises(ActionController::ParameterMissing) { Discussion::CommentItemBatch.new(@repo, params) }
  end

  test "#comments returns a collection of valid loaded comments" do
    unrelated = create(:discussion_comment)
    params = ActionController::Parameters.new({
      "items" => {
        "item-0" => { "comment_id" => @comment1.id.to_s },
        "item-1" => { "discussion_id" => @discussion.id.to_s },
        "item-2" => { "comment_id" => "-1" },
        "item-3" => { "comment_id" => unrelated.id.to_s }
      }
    })
    item_batch = Discussion::CommentItemBatch.new(@repo, params)

    assert_equal [@comment1], item_batch.comments
  end

  test "#comment_ids returns a collection of the IDs of valid comments" do
    unrelated = create(:discussion_comment)
    params = ActionController::Parameters.new({
      "items" => {
        "item-0" => { "comment_id" => @comment1.id.to_s },
        "item-1" => { "discussion_id" => @discussion.id },
        "item-2" => { "comment_id" => "-1" },
        "item-3" => { "comment_id" => unrelated.id.to_s }
      }
    })
    item_batch = Discussion::CommentItemBatch.new(@repo, params)

    assert_equal [@comment1.id], item_batch.comment_ids
  end

  test "#discussions returns a collection of valid loaded discussions" do
    unrelated = create(:discussion)
    params = ActionController::Parameters.new({
      "items" => {
        "item-0" => { "discussion_id" => @discussion.id.to_s },
        "item-1" => { "discussion_id" => "-1" },
        "item-2" => { "discussion_id" => unrelated.id.to_s }
      }
    })
    item_batch = Discussion::CommentItemBatch.new(@repo, params)

    assert_same_elements [@discussion], item_batch.discussions
  end

  test "executes a block for each item with its comment or discussion and returns the collected results" do
    params = ActionController::Parameters.new({
      "items" => {
        "item-0" => { "comment_id" => @comment0.id.to_s },
        "item-1" => { "discussion_id" => @discussion.id.to_s },
        "item-2" => { "comment_id" => @comment1.id.to_s },
        "item-3" => { "comment_id" => "-1" }
      }
    })

    item_batch = Discussion::CommentItemBatch.new(@repo, params)
    actual = item_batch.map_inputs do |handler|
      handler.comment { |comment| "comment: #{comment.id}" }
      handler.discussion { |discussion| "discussion: #{discussion.id}" }
    end

    expected = {
      "item-0" => "comment: #{@comment0.id}",
      "item-1" => "discussion: #{@discussion.id}",
      "item-2" => "comment: #{@comment1.id}",
      "item-3" => "",
    }
    assert_equal expected, actual
  end

  test "doesn't raise an error if input keys are not as expected" do
    params = ActionController::Parameters.new({
      "items" => {
        "item-0" => { "wrong_key" => @comment0.id.to_s },
      },
    })

    item_batch = Discussion::CommentItemBatch.new(@repo, params)
    actual = item_batch.map_inputs do |handler|
      handler.discussion { |discussion| "discussion: #{discussion.id}" }
      handler.comment { |comment| "comment: #{comment.id}" }
    end

    expected = {
      "item-0" => "",
    }
    assert_equal expected, actual
  end
end
