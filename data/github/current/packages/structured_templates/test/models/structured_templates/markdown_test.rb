# typed: true
# frozen_string_literal: true

require "test_helper"

class StructuredTemplatesMarkdownTest < GitHub::TestCase
  fixtures do
    @docs_link = "https://docs.github.com/communities/using-templates-to-encourage-useful-issues-and-pull-requests/common-validation-errors-when-creating-issue-forms"
  end

  context ".valid?" do
    test "true when value is provided as a string" do
      input_hash = {
        "type" => "markdown",
        "attributes" => {
          "value" => "here is a description!",
        }
      }

      desc = StructuredTemplates::Markdown.new(input: input_hash)

      assert_predicate desc, :valid?
      assert_equal "here is a description!", desc.value
    end

    test "false when attributes block is missing" do
      input_hash = {
        "type" => "markdown",
      }

      desc = StructuredTemplates::Markdown.new(input: input_hash)

      refute_predicate desc, :valid?
      assert_equal ["Required attribute key `value` is missing"], desc.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-required-attribute-key-value-is-missing", desc.errors.first.options[:docs]
    end

    test "false when attributes block is empty" do
      input_hash = {
        "type" => "markdown",
        "attributes" => {}
      }

      desc = StructuredTemplates::Markdown.new(input: input_hash)

      refute_predicate desc, :valid?
      assert_equal ["Required attribute key `value` is missing"], desc.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-required-attribute-key-value-is-missing", desc.errors.first.options[:docs]
    end

    test "false when value key is nil" do
      input_hash = {
        "type" => "markdown",
        "attributes" => {
          "value" => nil
        }
      }

      desc = StructuredTemplates::Markdown.new(input: input_hash)

      refute_predicate desc, :valid?
      assert_equal ["Required attribute key `value` is missing"], desc.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-required-attribute-key-value-is-missing", desc.errors.first.options[:docs]
    end

    test "false if extraneous attributes provided" do
      input_hash = {
        "type" => "markdown",
        "attributes" => {
          "extra" => "sauce",
          "value" => "some-value"
        }
      }

      desc = StructuredTemplates::Markdown.new(input: input_hash)
      refute_predicate desc, :valid?
      assert_equal ["`extra` is not a permitted attribute"], desc.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-x-is-not-a-permitted-attribute", desc.errors.first.options[:docs]
    end

    test "false if extraneous top-level keys provided" do
      extra_keys = {
        "type" => "input",
        "extra" => "key",
        "attributes" => {
          "value" => "some-value"
        }
      }

      desc = StructuredTemplates::Markdown.new(input: extra_keys)
      refute_predicate desc, :valid?
      assert_equal ["`extra` is not a permitted key"], desc.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-x-is-not-a-permitted-key", desc.errors.first.options[:docs]
    end

    context "type checks" do
      test "false when value is anything other than a string" do
        input_hash = {
          "type" => "markdown",
          "attributes" => {
            "value" => 42
          }
        }

        input = StructuredTemplates::Markdown.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["`value` must be of type String and cannot be empty"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
      end
    end
  end
end
