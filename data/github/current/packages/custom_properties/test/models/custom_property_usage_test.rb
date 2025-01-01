# typed: true
# frozen_string_literal: true

require "test_helper"

class CustomPropertyUsageTest < GitHub::TestCase
  setup do
    @org = create :organization
    @definition = create :custom_property_definition, source: @org, property_name: "environment"

    @default_values = {
      definition_id: @definition.id,
      consumer_id: 1,
      consumer_type: :ruleset,
      property_value: "production"
    }
  end

  test "creates a new custom property condition usage" do
    assert CustomPropertyUsage.create!(@default_values)
  end

  test "resolves relation to definition" do
    usage = CustomPropertyUsage.create!(@default_values)

    assert CustomPropertyUsage.find_by(id: usage.id), @definition
  end

  test "validates consumer_type" do
    assert_raises_with_message ActiveRecord::RecordInvalid, "Validation failed: Consumer type 'unknown' is unknown consumer type" do
      CustomPropertyUsage.create!(@default_values.merge(consumer_type: :unknown))
    end
  end
end
