# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityCampaigns::CampaignWithGroupedCountsTest < GitHub::TestCase
  setup do
    GitHub.flipper[:security_campaigns_read_without_alerts_limit].disable
  end

  test "cursor paging works" do
    items = [5, 10, 20]

    cursor = SecurityCampaigns::CampaignWithGroupedCounts::Cursor.page(items:, page_size: 25, after_cursor: nil, before_cursor: nil)
    assert_equal [5, 10, 20], cursor.items

    # page size 1
    cursor = SecurityCampaigns::CampaignWithGroupedCounts::Cursor.page(items:, page_size: 1, after_cursor: nil, before_cursor: nil)
    assert_equal [5], cursor.items
    assert_nil cursor.prev
    assert_equal "10", cursor.next

    cursor = SecurityCampaigns::CampaignWithGroupedCounts::Cursor.page(items:, page_size: 1, after_cursor: "10", before_cursor: nil)
    assert_equal [10], cursor.items
    assert_equal "5", cursor.prev
    assert_equal "20", cursor.next

    cursor = SecurityCampaigns::CampaignWithGroupedCounts::Cursor.page(items:, page_size: 1, after_cursor: nil, before_cursor: "5")
    assert_equal [5], cursor.items
    assert_nil cursor.prev
    assert_equal "10", cursor.next

    cursor = SecurityCampaigns::CampaignWithGroupedCounts::Cursor.page(items:, page_size: 1, after_cursor: "20", before_cursor: nil)
    assert_equal [20], cursor.items
    assert_equal "10", cursor.prev
    assert_nil cursor.next

    # page size 2
    cursor = SecurityCampaigns::CampaignWithGroupedCounts::Cursor.page(items:, page_size: 2, after_cursor: nil, before_cursor: nil)
    assert_equal [5, 10], cursor.items
    assert_nil cursor.prev
    assert_equal "20", cursor.next

    cursor = SecurityCampaigns::CampaignWithGroupedCounts::Cursor.page(items:, page_size: 2, after_cursor: "10", before_cursor: nil)
    assert_equal [10, 20], cursor.items
    assert_equal "5", cursor.prev
    assert_nil cursor.next

    cursor = SecurityCampaigns::CampaignWithGroupedCounts::Cursor.page(items:, page_size: 2, after_cursor: nil, before_cursor: "10")
    assert_equal [5, 10], cursor.items
    assert_nil cursor.prev
    assert_equal "20", cursor.next

    cursor = SecurityCampaigns::CampaignWithGroupedCounts::Cursor.page(items:, page_size: 2, after_cursor: nil, before_cursor: "5")
    assert_equal [5, 10], cursor.items
    assert_nil cursor.prev
    assert_equal "20", cursor.next

    cursor = SecurityCampaigns::CampaignWithGroupedCounts::Cursor.page(items:, page_size: 2, after_cursor: "20", before_cursor: nil)
    assert_equal [20], cursor.items
    assert_equal "10", cursor.prev
    assert_nil cursor.next

    cursor = SecurityCampaigns::CampaignWithGroupedCounts::Cursor.page(items:, page_size: 2, after_cursor: "5", before_cursor: nil)
    assert_equal [5, 10], cursor.items
    assert_nil cursor.prev
    assert_equal "20", cursor.next
  end

  test "cursor paging handles missing elements" do
    items = [5, 10, 20]

    # 99 is not in the list
    # paging should start at the beginning

    cursor = SecurityCampaigns::CampaignWithGroupedCounts::Cursor.page(items:, page_size: 2, after_cursor: "99", before_cursor: nil)
    assert_equal [5, 10], cursor.items
    assert_nil cursor.prev
    assert_equal "20", cursor.next

    cursor = SecurityCampaigns::CampaignWithGroupedCounts::Cursor.page(items:, page_size: 2, after_cursor: nil, before_cursor: "99")
    assert_equal [5, 10], cursor.items
    assert_nil cursor.prev
    assert_equal "20", cursor.next
  end
end
