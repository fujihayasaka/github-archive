# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class SnippetsValidatorTest < GitHub::TestCase
    test "is valid if required fields are present" do
      validator = SnippetsValidator.new({ trigger: "", title: "", description: "", value: "", surfaces: SlashCommands::ALL_SURFACE })
      assert_predicate validator, :valid?
      assert_equal [], validator.errors.full_messages
    end

    test "is valid if value_source is provided instead of value" do
      validator = SnippetsValidator.new({ trigger: "", title: "", description: "", value_source: "", surfaces: SlashCommands::ALL_SURFACE })
      assert_predicate validator, :valid?
      assert_equal [], validator.errors.full_messages
    end

    test "errors if schema is not a hash" do
      [1, "foo", [], true, nil].each do |val|
        validator = SnippetsValidator.new(val)
        refute_predicate validator, :valid?
        assert_equal ["Expected schema to be an hash of elements, but was `#{val.class}`"], validator.errors.full_messages
      end
    end

    test "errors if extra top level fields are found" do
      validator = SnippetsValidator.new({ trigger: "", title: "", description: "", value: "", surfaces: SlashCommands::ALL_SURFACE, another_field: "" })
      refute_predicate validator, :valid?
      assert_equal ["`schema` was not expected to include the key `another_field`"], validator.errors.full_messages
    end

    test "errors if required top level field not included" do
      validator = SnippetsValidator.new({ trigger: "", description: "", value: "" })
      refute_predicate validator, :valid?
      assert_equal ["`schema` was expected to include the keys `title` and `surfaces`"], validator.errors.full_messages
    end

    test "errors if surfaces field is not an array" do
      validator = SnippetsValidator.new({ trigger: "", title: "", description: "", value: "", surfaces: "test" })
      refute_predicate validator, :valid?
      assert_equal ["`surfaces` was expected to be an `Array` or the string `all` but was `test`"], validator.errors.full_messages
    end

    test "errors if surfaces contains unsupported values" do
      validator = SnippetsValidator.new({ trigger: "", title: "", description: "", value: "", surfaces: ["test"] })
      refute_predicate validator, :valid?
      assert_equal ["`surfaces` `test` must be one of `discussion`, `pull_request`, `pull_request_body`, `pull_request_comment`, `issue`, `issue_body`, or `issue_comment`"], validator.errors.full_messages
    end

    test "errors if no value or value_source are provided" do
      validator = SnippetsValidator.new({ trigger: "", title: "", description: "", surfaces: SlashCommands::ALL_SURFACE })
      refute_predicate validator, :valid?
      assert_equal ["`value` must provide either a value or a value_source"], validator.errors.full_messages
    end
  end
end
