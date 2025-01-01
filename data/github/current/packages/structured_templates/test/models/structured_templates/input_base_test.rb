# typed: true
# frozen_string_literal: true

require "test_helper"

class StructuredTemplatesInputBaseTest < GitHub::TestCase
  context "#create_from_input_hash" do
    test "returns an instance of markdown if type: markdown" do
      input_hash = {
        "type" => "markdown",
        "attributes" => {
          "value" => "some-description"
        }
      }

      result = StructuredTemplates::InputBase.create_from_input_hash(input_hash)
      assert_equal "StructuredTemplates::Markdown", result.class.name
      assert_predicate result, :valid?
    end

    test "returns an instance of InputBase if type is not valid, but no type-specific validations" do
      input_hash = {
        "type" => "bubble-tea",
        "attributes" => {
          "flavor" => "genmaicha",
          "required" => "nope",
        }
      }

      result = StructuredTemplates::InputBase.create_from_input_hash(input_hash)
      assert_equal "StructuredTemplates::InputBase", result.class.name
      assert_predicate result, :valid?
      refute result.errors.any?
    end
  end
end
