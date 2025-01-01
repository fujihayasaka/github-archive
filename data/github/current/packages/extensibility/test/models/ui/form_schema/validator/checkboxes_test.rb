# typed: true
# frozen_string_literal: true

require "test_helper"

class UI::FormSchema::Validator
  class CheckboxesTest < GitHub::TestCase
    test "checkboxes is valid" do
      validator = UI::FormSchema::Validator.new([{
        type: "checkboxes",
        attributes: {
          label: "label",
          options: [{ label: "label", value: "value" }],
          description: "description",
          value: "value",
        }
      }])
      assert_predicate validator, :valid?
    end

    test "checkboxes accepts string value" do
      validator = UI::FormSchema::Validator.new([{
        type: "checkboxes",
        attributes: {
          label: "label",
          options: [{ label: "label", value: "value" }],
          description: "description",
          value: "value",
        }
      }])
      assert_predicate validator, :valid?
    end

    test "checkboxes accepts array value" do
      validator = UI::FormSchema::Validator.new([{
        type: "checkboxes",
        attributes: {
          label: "label",
          options: [{ label: "label", value: "value" }],
          description: "description",
          value: ["value"],
        }
      }])
      assert_predicate validator, :valid?
    end

    test "checkboxes without attributes is invalid" do
      validator = UI::FormSchema::Validator.new([{ type: "checkboxes" }])
      refute_predicate validator, :valid?
      assert_equal ["`[0]` was expected to include the key `attributes`"], validator.errors.full_messages
    end

    test "checkboxes with invalid attributes is invalid" do
      validator = UI::FormSchema::Validator.new([{ type: "checkboxes", attributes: "nope" }])
      refute_predicate validator, :valid?
      assert_equal ["`[0].attributes` was expected to be a `Hash` but it was a `String`"], validator.errors.full_messages
    end

    test "checkboxes without name is invalid" do
      validator = UI::FormSchema::Validator.new([{
        type: "checkboxes",
        attributes: {
          options: [{ label: "label", value: "value" }],
          description: "description",
          value: "value"
        }
      }])
      refute_predicate validator, :valid?
      assert_equal ["`[0].attributes` was expected to have the key `label`"], validator.errors.full_messages
    end

    test "checkboxes without options is invalid" do
      validator = UI::FormSchema::Validator.new([{
        type: "checkboxes",
        attributes: {
          label: "label",
          description: "description",
          value: "value"
        }
      }])
      refute_predicate validator, :valid?
      assert_equal ["`[0].attributes` was expected to have the key `options`"], validator.errors.full_messages
    end

    test "checkboxes_with_options_that_are_invalid" do
      validator = UI::FormSchema::Validator.new([{
        type: "checkboxes",
        attributes: {
          label: "label",
          description: "description",
          value: "value",
          options: [{}]
        }
      }])
      refute_predicate validator, :valid?
      assert_equal ["`[0].attributes.options[0]` was expected to have the key `label`"], validator.errors.full_messages
    end

    test "checkboxes with options that isnt a hash" do
      validator = UI::FormSchema::Validator.new([{
        type: "checkboxes",
        attributes: {
          label: "label",
          description: "description",
          value: "value",
          options: [1]
        }
      }])
      refute_predicate validator, :valid?
      assert_equal ["`[0].attributes.options[0]` was expected to be a `Hash` but was a `Integer`"], validator.errors.full_messages
    end

    test "checkboxes with incorrect types" do
      validator = UI::FormSchema::Validator.new([{
        type: "checkboxes",
        attributes: {
          options: "",
          label: 1,
          description: 1,
          value: 1
        }
      }])
      refute_predicate validator, :valid?
      assert_equal [
        "`[0].attributes.label` was expected to be a `String` but it was a `Integer`",
        "`[0].attributes.options` was expected to be an `Array` but it was a `String`",
        "`[0].attributes.description` was expected to be a `String` but it was a `Integer`",
        "`[0].attributes.value` was expected to be a `String` or an `Array` but it was a `Integer`"
      ], validator.errors.full_messages
    end

    test "checkboxes with incorrect validation entries" do
      validator = UI::FormSchema::Validator.new([{
        type: "checkboxes",
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

    test "checkboxes_with_incorrect_attribute_options" do
      validator = UI::FormSchema::Validator.new([{
        type: "checkboxes",
        attributes: {
          label: "1",
          options: [{ label: "label", value: "value" }],
          foo: "foo",
          bar: "bar",
        },
      }])
      refute_predicate validator, :valid?
      assert_equal [
        "`[0].attributes` `foo` and `bar` must be one of `label`, `id`, `description`, `value`, or `options`"
      ], validator.errors.full_messages
    end

    test "checkboxes with incorrect validation options" do
      validator = UI::FormSchema::Validator.new([{
        type: "checkboxes",
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

    test "checkboxes with incorrect options" do
      validator = UI::FormSchema::Validator.new([{
        type: "checkboxes",
        attributes: {
          label: "label",
          options: [
            { foo: "name", bar: "value", label: "label" },
            { invalid: "name", label: "label" },
          ],
        }
      }])
      refute_predicate validator, :valid?
      assert_equal [
        "`[0].attributes.options[0]` `foo` and `bar` must be one of `label`, `value`, or `required`",
        "`[0].attributes.options[1]` `invalid` must be one of `label`, `value`, or `required`"
      ], validator.errors.full_messages
    end

    test "checkboxes limits options size to 100" do
      options = 101.times.map { |i| { label: "name#{i}", value: "value#{i}" } }
      validator = UI::FormSchema::Validator.new([{
        type: "checkboxes",
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
