# typed: true
# frozen_string_literal: true

require "test_helper"

class UI::FormSchema::Validator
  class MarkdownTest < GitHub::TestCase
    def test_markdown_is_valid
      validator = UI::FormSchema::Validator.new([{
        type: "markdown",
        attributes: {
          value: "# Hello World"
        }
      }])
      assert_predicate validator, :valid?
    end

    def test_markdown_without_value_is_invalid
      validator = UI::FormSchema::Validator.new([{
        type: "markdown",
        attributes: {}
      }])
      refute_predicate validator, :valid?
      assert_equal ["`[0].attributes` was expected to have the key `value`"], validator.errors.full_messages
    end

    def test_markdown_without_attributes_is_invalid
      validator = UI::FormSchema::Validator.new([{ type: "markdown" }])
      refute_predicate validator, :valid?
      assert_equal ["`[0]` was expected to include the key `attributes`"], validator.errors.full_messages
    end

    test "markdown with invalid attributes is invalid" do
      validator = UI::FormSchema::Validator.new([{ type: "markdown", attributes: "nope" }])
      refute_predicate validator, :valid?
      assert_equal ["`[0].attributes` was expected to be a `Hash` but it was a `String`"], validator.errors.full_messages
    end

    def test_markdown_with_value_that_is_a_hash
      validator = UI::FormSchema::Validator.new([{
        type: "markdown",
        attributes: {
          value: {}
        }
      }])
      refute_predicate validator, :valid?
      assert_equal ["`[0].attributes` was expected to have the key `value`"], validator.errors.full_messages
    end
  end
end
