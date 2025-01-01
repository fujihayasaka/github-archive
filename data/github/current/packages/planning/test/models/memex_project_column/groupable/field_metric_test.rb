# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnGroupableFieldMetricTest < GitHub::TestCase
  context "#display_value" do
    test "rounds values to a max of two decimal places of precision" do
      [[1.2345, 1.23], [1.237, 1.24], [1.2, 1.2], [1.0, 1]].each do |value, expected|
        field_metric = MemexProjectColumn::Interface::Groupable::FieldMetric.new(
          field_id: 1,
          value:,
        )

        assert_equal expected, field_metric.display_value
      end
    end
  end

  context "#to_hash" do
    test "serializes value as display_value" do
      field_metric = MemexProjectColumn::Interface::Groupable::FieldMetric.new(
        field_id: 1,
        value: 1.2345,
      )

      assert_equal 1.23, field_metric.to_hash["value"]
    end
  end
end
