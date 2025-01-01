# typed: true
# frozen_string_literal: true
require "test_helper"

module SlashCommands
  class ItemTest < GitHub::TestCase
    test "accepts text, value, and description" do
      item = Item.new(
        text: "My text",
        value: "my_value",
        description: "My description"
      )

      assert_equal "My text", item.text
      assert_equal "my_value", item.value
      assert_equal "My description", item.description
    end

    test "can be instantiated with only a value" do
      item = Item.new(value: "my_value")

      assert_equal "my_value", item.text
      assert_equal "my_value", item.value
      assert_nil item.description
    end

    context ".wrap" do
      test "always returns array of item instances" do
        item = Item.new(text: "Item 1", value: "item_1")
        hash = { text: "Item 2", value: "item_2" }

        assert_equal [item], Item.wrap(item)
        assert_equal [Item.from(hash)], Item.wrap(hash)
        assert_equal [item, Item.from(hash)], Item.wrap([item, hash])
      end
    end

    context ".from" do
      test "returns item" do
        item = Item.new(text: "Item 1", value: "item_1")

        assert_equal item, Item.from(item)
      end

      test "returns item from hash" do
        hash = { text: "Item 1", value: "item_1", description: "item description" }
        item = Item.new(text: "Item 1", value: "item_1", description: "item description")

        assert_equal item, Item.from(hash)
      end

      test "accepts hash with only name" do
        hash = { name: "item_1" }
        item = Item.new(text: "item_1", value: "item_1")

        assert_equal item, Item.from(hash)
      end

      test "accepts hash with only value" do
        hash = { value: "item_1" }
        item = Item.new(text: "item_1", value: "item_1")

        assert_equal item, Item.from(hash)
      end

      test "accepts string" do
        item = Item.new(text: "item_1", value: "item_1")

        assert_equal item, Item.from("item_1")
      end
    end
  end
end
