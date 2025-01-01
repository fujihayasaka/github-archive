# typed: true
# frozen_string_literal: true

require "test_helper"

module TrackingBlocks
  class KeyOnlyItemTest < GitHub::TestCase
    test "equality" do
      item = TrackingBlocks::KeyOnlyItem.new(owner_id: "owner_id", uuid: "uuid")
      other = TrackingBlocks::KeyOnlyItem.new(owner_id: "owner_id", uuid: "uuid")

      assert_equal item, other
    end

    test "equality with different owner ID" do
      item = TrackingBlocks::KeyOnlyItem.new(owner_id: "owner_id", uuid: "uuid")
      other = TrackingBlocks::KeyOnlyItem.new(owner_id: "other_owner_id", uuid: "uuid")

      refute_equal item, other
    end

    test "equality with different UUID" do
      other_repository = create(:repository)
      item = TrackingBlocks::KeyOnlyItem.new(owner_id: "owner_id", uuid: "uuid")
      other = TrackingBlocks::KeyOnlyItem.new(owner_id: "owner_id", uuid: "other_uuid")

      refute_equal item, other
    end

    test "equality with different item_id" do
      other_repository = create(:repository)
      item = TrackingBlocks::KeyOnlyItem.new(owner_id: "owner_id", item_id: 1)
      other = TrackingBlocks::KeyOnlyItem.new(owner_id: "owner_id", item_id: 2)

      refute_equal item, other
    end

    test "to hierarchy model with item_id" do
      item = TrackingBlocks::KeyOnlyItem.new(owner_id: "owner_id", item_id: 3)

      expected = {
        key: {
          ownerId: "owner_id",
          itemId: 3
        }
      }
      assert_equal expected, item.to_hierarchy_model
    end

    test "to hierarchy model with uuid" do
      item = TrackingBlocks::KeyOnlyItem.new(owner_id: "owner_id", uuid: "uuid")

      expected = {
        key: {
          ownerId: "owner_id",
          primaryKey: IssuesGraph::Proto::PrimaryKey.new(uuid: "uuid")
        }
      }
      assert_equal expected, item.to_hierarchy_model
    end
  end
end
