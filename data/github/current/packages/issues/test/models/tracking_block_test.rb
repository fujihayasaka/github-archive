# typed: true
# frozen_string_literal: true

require "test_helper"

class TrackingBlockTest < GitHub::TestCase
  fixtures do
    @issue = create(:issue)
  end

  test "equality" do
    tracking_block = TrackingBlock.new(id: "id1", issue: @issue)
    other_tracking_block = TrackingBlock.new(id: "id1", issue: @issue)

    assert_equal tracking_block, other_tracking_block
  end

  test "not equal with different id values" do
    tracking_block = TrackingBlock.new(id: "id1", issue: @issue)
    other_tracking_block = TrackingBlock.new(id: "id2", issue: @issue)

    refute_equal tracking_block, other_tracking_block
  end

  test "not equal with different issue values" do
    other_issue = create(:issue)
    tracking_block = TrackingBlock.new(id: "id1", issue: @issue)
    other_tracking_block = TrackingBlock.new(id: "id1", issue: other_issue)

    refute_equal tracking_block, other_tracking_block
  end

  test "url generation" do
    user = create(:user, login: "tracking")
    repository = create(:repository, owner: user, name: "blocks")
    issue = create(:issue, repository: repository, number: 1)
    tracking_block = TrackingBlock.new(id: "test", issue: issue)
    expected_url = "https://github.com/tracking/blocks/issues/1#tasklist-block-test"

    assert_equal expected_url, tracking_block.url
  end
end
