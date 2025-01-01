# typed: true
# frozen_string_literal: true

require "test_helper"

class UI::FormSchema::Validator
  class TextareaTest < GitHub::TestCase
    test "valid textarea with optional fields" do
      validator = UI::FormSchema::Validator.new([{
        type: "textarea",
        attributes: {
          label: "Operating System",
          description: "What operating system are you using?",
          placeholder: "ex. OSX Mountain Lion",
          value: "operating system",
        },
        validations: {
          required: true
        }
      }])
      assert_predicate validator, :valid?
      assert_predicate validator.errors, :empty?
    end

    test "with missing name is invalid" do
      validator = UI::FormSchema::Validator.new([{
        type: "textarea",
        attributes: {},
        validations: {
          required: true
        }
      }])
      refute_predicate validator, :valid?
      assert_equal ["`[0].attributes` was expected to have the key `label`"], validator.errors.full_messages
    end

    test "with missing attributes is invalid" do
      validator = UI::FormSchema::Validator.new([{ type: "textarea" }])
      refute_predicate validator, :valid?
      assert_equal ["`[0]` was expected to include the key `attributes`"], validator.errors.full_messages
    end

    test "with invalid attributes is invalid" do
      validator = UI::FormSchema::Validator.new([{ type: "textarea", attributes: "nope" }])
      refute_predicate validator, :valid?
      assert_equal ["`[0].attributes` was expected to be a `Hash` but it was a `String`"], validator.errors.full_messages
    end

    test "with non string name is invalid" do
      validator = UI::FormSchema::Validator.new([{
        type: "textarea",
        attributes: {
          label: true
        }
      }])
      refute_predicate validator, :valid?
      assert_equal ["`[0].attributes.label` was expected to be a `String` but it was a `TrueClass`"], validator.errors.full_messages
    end

    [:description, :placeholder, :value].each do |optional_attr|
      test "with empty string #{optional_attr} is valid" do
        validator = UI::FormSchema::Validator.new([{
          type: "textarea",
          attributes: {
            label: "Operating System",
            "#{optional_attr}": "",
          }
        }])
        assert_predicate validator, :valid?
      end

      test "with nil #{optional_attr} is valid" do
        validator = UI::FormSchema::Validator.new([{
          type: "textarea",
          attributes: {
            label: "Operating System",
            "#{optional_attr}": nil,
          }
        }])
        assert_predicate validator, :valid?
      end

      test "with non string #{optional_attr} is invalid" do
        validator = UI::FormSchema::Validator.new([{
          type: "textarea",
          attributes: {
            label: "Operating System",
            "#{optional_attr}": true,
          }
        }])
        refute_predicate validator, :valid?
        assert_equal ["`[0].attributes.#{optional_attr}` was expected to be a `String` but it was a `TrueClass`"], validator.errors.full_messages
      end

      test "with string #{optional_attr} is valid" do
        validator = UI::FormSchema::Validator.new([{
          type: "textarea",
          attributes: {
            label: "Operating System",
            "#{optional_attr}": "macOS?",
          }
        }])
        assert_predicate validator, :valid?
      end
    end
  end
end
