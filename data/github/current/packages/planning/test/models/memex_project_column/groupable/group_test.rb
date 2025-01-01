# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnGroupableGroupTest < GitHub::TestCase
  context "#to_hash" do
    test "serializes only those keys that are necessary for the web client" do
      group = MemexProjectColumn::Interface::Groupable::Group.new(
        group_by_key: 1,
        group_value: "foo",
      )

      assert_same_elements %w(group_value group_id group_metadata total_count field_metrics), group.to_hash.keys
    end
  end
end
