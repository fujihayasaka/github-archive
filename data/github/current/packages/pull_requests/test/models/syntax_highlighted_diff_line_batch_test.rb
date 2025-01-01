# typed: true
# frozen_string_literal: true

require "test_helper"

class SyntaxHighlightedDiffLineBatchTest < GitHub::TestCase
  fixtures do
    @repository = create(:repository, from_example: :prose)


    @pull_request = create(:pull_request, repository: @repository, head_ref: "improvements", base_ref: "master")

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  test "#as_json" do
    review_thread_1 = create(:pull_request_review_thread, pull_request: @pull_request)
    review_thread_2 = create(:pull_request_review_thread, pull_request: @pull_request)
    batch = SyntaxHighlightedDiffLineBatch.new(
      @pull_request.id,
      item1: review_thread_1.id,
      item2: review_thread_2.id,
    )

    json = batch.as_json

    assert_equal [:item1, :item2], json.keys
    assert_equal :hunk, json[:item1].fetch(0).fetch(:type)
  end

  test "handles deleted comments" do
    review_thread_1 = create(:pull_request_review_thread, pull_request: @pull_request)
    review_thread_2 = create(:pull_request_review_thread, pull_request: @pull_request)
    batch = SyntaxHighlightedDiffLineBatch.new(
      @pull_request.id,
      item1: review_thread_1.id,
      item2: review_thread_2.id,
    )
    review_thread_1.destroy!

    json = batch.as_json

    assert_equal [:item2], json.keys
    assert_equal :hunk, json[:item2].fetch(0).fetch(:type)
  end
end
