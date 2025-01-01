# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnValueJsonValueValidator < GitHub::TestCase

  setup do
    @validator = MemexProjectColumnValue::JsonValueValidator.new
  end

  context "for columns of data_type :text" do
    test "validates json_value with top-level 'raw' and 'html' keys" do
      value = build(
        :memex_project_column_value,
        json_value: { raw: "raw value", "html": "html value" }
      )
      @validator.validate(value)

      assert_empty value.errors
    end

    test "requires json_value for a text column to be non-nil" do
      value = build(
        :memex_project_column_value,
        json_value: nil
      )
      @validator.validate(value)

      assert_includes value.errors.full_messages, "Json value must be a Hash"
    end

    test "requires json_value for a text column to be a hash" do

      value = build(
        :memex_project_column_value,
        json_value: "123"
      )
      @validator.validate(value)

      assert_includes value.errors.full_messages, "Json value must be a Hash"
    end

    test "requires json_value for text column to have top-level 'raw' and 'html' keys" do
      value = build(
        :memex_project_column_value,
        json_value: { "bogus" => "foo" }
      )
      @validator.validate(value)

      assert_includes value.errors.full_messages, "Json value must include an entry for the 'raw' key"
      assert_includes value.errors.full_messages, "Json value must include an entry for the 'html' key"
    end
  end

  context "for columns of data_type :number" do
    test "validates json_value with a top-level 'value' key" do
      value = build(
        :number_memex_project_column_value,
        json_value: { value: 10 }
      )
      @validator.validate(value)

      assert_empty value.errors
    end

    test "requires json_value for a number column to be non-nil" do
      value = build(
        :number_memex_project_column_value,
        json_value: nil
      )
      @validator.validate(value)

      assert_includes value.errors.full_messages, "Json value must be a Hash"
    end

    test "requires json_value for a number column to be a hash" do
      value = build(
        :number_memex_project_column_value,
        json_value: "123"
      )
      @validator.validate(value)

      assert_includes value.errors.full_messages, "Json value must be a Hash"
    end

    test "requires json_value for number column to have a top-level 'value' key" do
      value = build(
        :number_memex_project_column_value,
        json_value: { "bogus" => "foo" }
      )
      @validator.validate(value)

      assert_includes value.errors.full_messages, "Json value must include an entry for the 'value' key"
    end
  end

  context "for columns of data_type :single_select" do
    test "validates json_value with a top-level 'id' key" do
      value = build(
        :single_select_memex_project_column_value,
        json_value: { id: "aaaaaa" }
      )
      @validator.validate(value)

      assert_empty value.errors
    end

    test "requires json_value for a single_select column to be non-nil" do
      value = build(
        :single_select_memex_project_column_value,
        json_value: nil
      )
      @validator.validate(value)

      assert_includes value.errors.full_messages, "Json value must be a Hash"
    end

    test "requires json_value for a single_select column to be a hash" do
      value = build(
        :single_select_memex_project_column_value,
        json_value: "123"
      )
      @validator.validate(value)

      assert_includes value.errors.full_messages, "Json value must be a Hash"
    end

    test "requires json_value for single_select column to have a top-level 'id' key" do
      value = build(
        :single_select_memex_project_column_value,
        json_value: { "bogus" => "foo" }
      )
      @validator.validate(value)

      assert_includes value.errors.full_messages, "Json value must include an entry for the 'id' key"
    end
  end

  context "for columns of data_type :date" do
    test "validates json_value with a top-level 'value' key" do
      value = build(
        :date_memex_project_column_value,
        json_value: { value: "2021-04-23T18:25:43.511Z" }
      )
      @validator.validate(value)

      assert_empty value.errors
    end

    test "requires json_value for a date column to be non-nil" do
      value = build(
        :date_memex_project_column_value,
        json_value: nil
      )
      @validator.validate(value)

      assert_includes value.errors.full_messages, "Json value must be a Hash"
    end

    test "requires json_value for a date column to be a hash" do
      value = build(
        :date_memex_project_column_value,
        json_value: "123"
      )
      @validator.validate(value)

      assert_includes value.errors.full_messages, "Json value must be a Hash"
    end

    test "requires json_value for date column to have a top-level 'value' key" do
      value = build(
        :date_memex_project_column_value,
        json_value: { "bogus" => "foo" }
      )
      @validator.validate(value)

      assert_includes value.errors.full_messages, "Json value must include an entry for the 'value' key"
    end
  end

  context "for columns of data_type :milestone" do
    test "validates json_value" do
      value = build(
        :milestone_column_value,
        json_value: { type: "Milestone", value: { id: 5, number: 2, state: "open", title: "GitHub Universe", url: "url" } }
      )
      @validator.validate(value)

      assert_empty value.errors
    end

    test "requires json_value for a milestone column to be non-nil" do
      value = build(
        :milestone_column_value,
        json_value: nil
      )
      @validator.validate(value)

      assert_includes value.errors.full_messages, "Json value must be a Hash"
    end

    test "requires json_value for a milestone column to be a hash" do
      value = build(
        :milestone_column_value,
        json_value: "123"
      )
      @validator.validate(value)

      assert_includes value.errors.full_messages, "Json value must be a Hash"
    end

    test "requires json_value type for a milestone column to be non-nil" do
      value = build(
        :milestone_column_value,
        json_value: { type: nil, value: { id: 5, number: 2, state: "open", title: "GitHub Universe", url: "url" } }
      )
      @validator.validate(value)

      assert_includes value.errors.full_messages, "Json value must include a 'type' of 'Milestone'"
    end
    test "requires json_value value for a milestone column to be non-nil" do
      value = build(
        :milestone_column_value,
        json_value: { type: "Milestone", value: nil }
      )
      @validator.validate(value)

      assert_includes value.errors.full_messages, "Json value must include a 'value' key"
    end
  end
end
