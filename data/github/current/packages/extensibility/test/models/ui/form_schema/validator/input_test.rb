# typed: true
# frozen_string_literal: true

require "test_helper"

class UI::FormSchema::Validator
  class InputTest < GitHub::TestCase
    test "input is valid" do
      validator = UI::FormSchema::Validator.new([{
        type: "input",
        attributes: {
          label: "name",
          description: "description",
          placeholder: "placeholder",
          value: "value",
          format: "text"
        },
        validations: {
          required: true,
          minLength: 5,
          maxLength: 10,
        }
      }])
      assert_predicate validator, :valid?
    end

    test "input is valid and still supports input type" do
      validator = UI::FormSchema::Validator.new([{
        type: "input",
        attributes: {
          label: "name",
          description: "description",
          placeholder: "placeholder",
          value: "value",
          format: "text"
        },
        validations: {
          required: true,
          minLength: 5,
          maxLength: 10,
        }
      }])
      assert_predicate validator, :valid?
    end

    test "input without attributes is invalid" do
      validator = UI::FormSchema::Validator.new([{ type: "input" }])
      refute_predicate validator, :valid?
      assert_equal ["`[0]` was expected to include the key `attributes`"], validator.errors.full_messages
    end

    test "input with invalid attributes is invalid" do
      validator = UI::FormSchema::Validator.new([{ type: "input", attributes: "nope" }])
      refute_predicate validator, :valid?
      assert_equal ["`[0].attributes` was expected to be a `Hash` but it was a `String`"], validator.errors.full_messages
    end

    test "input without name is invalid" do
      validator = UI::FormSchema::Validator.new([{
        type: "input",
        attributes: {
          description: "description",
          placeholder: "placeholder",
          value: "value",
          format: "text"
        }
      }])
      refute_predicate validator, :valid?
      assert_equal ["`[0].attributes` was expected to have the key `label`"], validator.errors.full_messages
    end

    test "input with incorrect types" do
      validator = UI::FormSchema::Validator.new([{
        type: "input",
        attributes: {
          label: 1,
          description: 1,
          placeholder: 1,
          value: 1,
          format: "text"
        }
      }])
      refute_predicate validator, :valid?
      assert_equal [
        "`[0].attributes.label` was expected to be a `String` but it was a `Integer`",
        "`[0].attributes.description` was expected to be a `String`",
        "`[0].attributes.placeholder` was expected to be a `String`",
        "`[0].attributes.value` was expected to be a `String`",
      ], validator.errors.full_messages
    end

    test "input with incorrect format" do
      validator = UI::FormSchema::Validator.new([{
        type: "input",
        attributes: {
          label: "1",
          description: "1",
          placeholder: "1",
          value: "1",
          format: "foo"
        }
      }])
      refute_predicate validator, :valid?
      assert_equal [
        "`[0].attributes.format` was expected to be one of `text`, `phone`, `number`, `date`, or `email`",
      ], validator.errors.full_messages
    end

    test "input with incorrect validation entries" do
      validator = UI::FormSchema::Validator.new([{
        type: "input",
        attributes: {
          label: "1",
        },
        validations: {
          required: 1,
          minLength: true,
          maxLength: true,
        }
      }])
      refute_predicate validator, :valid?
      assert_equal [
        "`[0].validations.required` was expected to be a `Boolean` but it was a `Integer`",
        "`[0].validations.minLength` was expected to be a `Integer` but it was a `TrueClass`",
        "`[0].validations.maxLength` was expected to be a `Integer` but it was a `TrueClass`"
      ], validator.errors.full_messages
    end

    test "input with incorrect attribute options" do
      validator = UI::FormSchema::Validator.new([{
        type: "input",
        attributes: {
          label: "1",
          foo: "foo",
          bar: "bar",
        },
      }])
      refute_predicate validator, :valid?
      assert_equal [
        "`[0].attributes` `foo` and `bar` must be one of `label`, `id`, `description`, `placeholder`, `value`, or `format`"
      ], validator.errors.full_messages
    end

    test "input with incorrect validation options" do
      validator = UI::FormSchema::Validator.new([{
        type: "input",
        attributes: {
          label: "1",
        },
        validations: {
          required: true,
          foo: :foo,
          bar: :bar,
        }
      }])
      refute_predicate validator, :valid?
      assert_equal [
        "`[0].validations` `foo` and `bar` must be one of `required`, `minLength`, `maxLength`, or `format`"
      ], validator.errors.full_messages
    end
  end
end
