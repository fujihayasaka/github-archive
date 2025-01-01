# typed: true
# frozen_string_literal: true

require "test_helper"

class UI::FormSchema::Validator
  class DropdownTest < GitHub::TestCase
    def test_dropdown_is_valid
      validator = UI::FormSchema::Validator.new([{
        type: "dropdown",
        attributes: {
          label: "label",
          options: [{ label: "label", value: "value" }],
          description: "description",
          placeholder: "placeholder",
          value: "value",
          multiple: false,
        }
      }])
      assert_predicate validator, :valid?
    end

    def test_dropdown_accepts_string_value
      validator = UI::FormSchema::Validator.new([{
        type: "dropdown",
        attributes: {
          label: "label",
          options: [{ label: "label", value: "value" }],
          description: "description",
          placeholder: "placeholder",
          value: "value",
          multiple: false,
        }
      }])
      assert_predicate validator, :valid?
    end

    def test_dropdown_accepts_array_value
      validator = UI::FormSchema::Validator.new([{
        type: "dropdown",
        attributes: {
          label: "label",
          options: [{ label: "label", value: "value" }],
          description: "description",
          placeholder: "placeholder",
          value: ["value"],
          multiple: false,
        }
      }])
      assert_predicate validator, :valid?
    end

    def test_dropdown_without_attributes_is_invalid
      validator = UI::FormSchema::Validator.new([{ type: "dropdown" }])
      refute_predicate validator, :valid?
      assert_equal ["`[0]` was expected to include the key `attributes`"], validator.errors.full_messages
    end

    test "dropdown with invalid attributes is invalid" do
      validator = UI::FormSchema::Validator.new([{ type: "dropdown", attributes: "nope" }])
      refute_predicate validator, :valid?
      assert_equal ["`[0].attributes` was expected to be a `Hash` but it was a `String`"], validator.errors.full_messages
    end

    def test_dropdown_without_name_is_invalid
      validator = UI::FormSchema::Validator.new([{
        type: "dropdown",
        attributes: {
          options: [{ label: "label", value: "value" }],
          description: "description",
          placeholder: "placeholder",
          value: "value"
        }
      }])
      refute_predicate validator, :valid?
      assert_equal ["`[0].attributes` was expected to have the key `label`"], validator.errors.full_messages
    end

    def test_dropdown_without_options_is_invalid
      validator = UI::FormSchema::Validator.new([{
        type: "dropdown",
        attributes: {
          label: "label",
          description: "description",
          placeholder: "placeholder",
          value: "value"
        }
      }])
      refute_predicate validator, :valid?
      assert_equal ["`[0].attributes` was expected to have the key `options`"], validator.errors.full_messages
    end

    def test_dropdown_with_options_that_are_invalid
      validator = UI::FormSchema::Validator.new([{
        type: "dropdown",
        attributes: {
          label: "label",
          description: "description",
          placeholder: "placeholder",
          value: "value",
          options: [{}]
        }
      }])
      refute_predicate validator, :valid?
      assert_equal ["`[0].attributes.options[0]` was expected to have the key `label`"], validator.errors.full_messages
    end

    def test_dropdown_with_options_that_isnt_a_hash
      validator = UI::FormSchema::Validator.new([{
        type: "dropdown",
        attributes: {
          label: "label",
          description: "description",
          placeholder: "placeholder",
          value: "value",
          options: [1]
        }
      }])
      refute_predicate validator, :valid?
      assert_equal ["`[0].attributes.options[0]` was expected to be a `Hash` but was a `Integer`"], validator.errors.full_messages
    end

    def test_dropdown_with_incorrect_types
      validator = UI::FormSchema::Validator.new([{
        type: "dropdown",
        attributes: {
          options: "",
          label: 1,
          description: 1,
          placeholder: 1,
          value: 1,
        }
      }])
      refute_predicate validator, :valid?
      assert_equal [
        "`[0].attributes.label` was expected to be a `String` but it was a `Integer`",
        "`[0].attributes.options` was expected to be an `Array` but it was a `String`",
        "`[0].attributes.description` was expected to be a `String` but it was a `Integer`",
        "`[0].attributes.placeholder` was expected to be a `String` but it was a `Integer`",
        "`[0].attributes.value` was expected to be a `String` or an `Array` but it was a `Integer`",
      ], validator.errors.full_messages
    end

    def test_dropdown_with_incorrect_validation_entries
      validator = UI::FormSchema::Validator.new([{
        type: "dropdown",
        attributes: {
          label: "1",
          options: [{ label: "label", value: "value" }],
        },
        validations: {
          required: 1,
        }
      }])
      refute_predicate validator, :valid?
      assert_equal [
        "`[0].validations.required` was expected to be a `Boolean` but it was a `Integer`"
      ], validator.errors.full_messages
    end

    def test_dropdown_with_incorrect_attribute_options
      validator = UI::FormSchema::Validator.new([{
        type: "dropdown",
        attributes: {
          label: "1",
          options: [{ label: "label", value: "value" }],
          foo: "foo",
          bar: "bar",
        },
      }])
      refute_predicate validator, :valid?
      assert_equal [
        "`[0].attributes` `foo` and `bar` must be one of `label`, `id`, `description`, `placeholder`, `value`, `multiple`, or `options`"
      ], validator.errors.full_messages
    end

    def test_dropdown_with_incorrect_validation_options
      validator = UI::FormSchema::Validator.new([{
        type: "dropdown",
        attributes: {
          label: "1",
          options: [{ label: "label", value: "value" }],
        },
        validations: {
          required: true,
          maxLength: 12,
          bar: :bar,
        }
      }])
      refute_predicate validator, :valid?
      assert_equal [
        "`[0].validations` `maxLength` and `bar` must be one of `required`"
      ], validator.errors.full_messages
    end

    def test_dropdown_limits_options_size_to_100
      options = 101.times.map { |i| { label: "name#{i}", value: "value#{i}" } }
      validator = UI::FormSchema::Validator.new([{
        type: "dropdown",
        attributes: {
          label: "label",
          options: options,
        }
      }])
      refute_predicate validator, :valid?
      assert_equal [
        "`[0].attributes.options` is currently limited to `100` options, but you currently have `101`. Please remove at least `1` option."
      ], validator.errors.full_messages
    end
  end
end
