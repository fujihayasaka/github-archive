# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class EmbeddedCommandValidatorTest < GitHub::TestCase
    test "errors if schema is not a hash" do
      [1, "foo", [], true, nil].each do |val|
        validator = EmbeddedCommandValidator.new(val)
        refute_predicate validator, :valid?
        assert_equal ["Expected schema to be an hash of elements, but was `#{val.class}`"], validator.errors.full_messages
      end
    end

    test "errors if extra top level fields are found" do
      validator = EmbeddedCommandValidator.new({ trigger: "", title: "", description: "", another_field: "" })
      refute_predicate validator, :valid?
      assert_equal ["`schema` was not expected to include the key `another_field`"], validator.errors.full_messages
    end

    test "errors if required top level field not included" do
      validator = EmbeddedCommandValidator.new({ trigger: "", description: "" })
      refute_predicate validator, :valid?
      assert_equal ["`schema` was expected to include the key `title`"], validator.errors.full_messages
    end
  end
end
